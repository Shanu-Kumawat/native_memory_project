// Status bar — bottom bar showing connection state and pointer stats.

import 'package:flutter/material.dart';

import '../models/pointer_data.dart' as models;
import '../theme.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.state});

  final models.InspectorState state;

  @override
  Widget build(BuildContext context) {
    final isConnected =
        state.connectionState == models.ConnectionState.connected;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: InspectorTheme.surface,
        border: Border(top: BorderSide(color: InspectorTheme.border)),
      ),
      child: Row(
        children: [
          _dot(isConnected ? InspectorTheme.success : InspectorTheme.textDim),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'Connected' : 'Disconnected',
            style: _style,
          ),
          if (isConnected) ...[
            _sep(),
            Text('${state.pointers.length} ptrs', style: _style),
            _sep(),
            Text('${state.readableCount} readable', style: _style),
            if (state.errorCount > 0) ...[
              _sep(),
              Text(
                '${state.errorCount} error',
                style: _style.copyWith(color: InspectorTheme.error),
              ),
            ],
            _sep(),
            Text('${state.totalBytesRead}B scanned', style: _style),
          ],
          const Spacer(),
          if (state.vmName != null)
            Text(
              '${state.vmName} ${state.vmVersion ?? ''}',
              style: _style,
            ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c),
      );

  Widget _sep() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('·', style: _style),
      );

  static final _style = InspectorTheme.monoSmall.copyWith(fontSize: 10);
}
