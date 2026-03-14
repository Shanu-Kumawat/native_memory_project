/// Connection panel widget for entering VM Service URI.

import 'package:flutter/material.dart';

import '../theme.dart';

class ConnectionPanel extends StatefulWidget {
  const ConnectionPanel({
    super.key,
    required this.onConnect,
    required this.isConnecting,
    this.errorMessage,
  });

  final void Function(String uri) onConnect;
  final bool isConnecting;
  final String? errorMessage;

  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel> {
  final _controller = TextEditingController(
    text: 'ws://127.0.0.1:8181/ws',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // VM Service icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: InspectorTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.terminal,
              color: InspectorTheme.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          // URI input
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _controller,
                style: InspectorTheme.mono.copyWith(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'ws://127.0.0.1:8181/ws',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  errorText: widget.errorMessage,
                  errorMaxLines: 1,
                  errorStyle: InspectorTheme.monoSmall.copyWith(
                    color: InspectorTheme.error,
                    fontSize: 10,
                  ),
                ),
                onSubmitted: widget.isConnecting ? null : widget.onConnect,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Connect button
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: widget.isConnecting
                  ? null
                  : () => widget.onConnect(_controller.text.trim()),
              icon: widget.isConnecting
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: InspectorTheme.text,
                      ),
                    )
                  : const Icon(Icons.power_settings_new, size: 16),
              label: Text(
                widget.isConnecting ? 'Connecting...' : 'Connect',
                style: InspectorTheme.label.copyWith(
                  color: InspectorTheme.text,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
