// Byte interpretation panel — HxD-style multi-type decode of selected bytes.
// Triggers ONLY on byte selection (click), not on hover.
// Positioned at the bottom of the detail panel to avoid layout jumps.

import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../models/selection_notifier.dart';
import '../theme.dart';

class ByteInterpretationPanel extends StatelessWidget {
  const ByteInterpretationPanel({
    super.key,
    required this.selectionNotifier,
    required this.rawBytes,
  });

  final SelectionNotifier selectionNotifier;
  final List<int>? rawBytes;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selectionNotifier,
      builder: (context, _) {
        // Only trigger on SELECTION (click), not hover
        final range = selectionNotifier.selection;
        if (range == null || rawBytes == null || rawBytes!.isEmpty) {
          return _empty();
        }

        final offset = range.offset;
        final size = range.size;
        if (offset + size > rawBytes!.length) return _empty();

        final bytes = Uint8List.fromList(
          rawBytes!.sublist(offset, offset + size),
        );
        final interpretations = _interpret(bytes);

        if (interpretations.isEmpty) return _empty();

        return Container(
          decoration: const BoxDecoration(
            color: InspectorTheme.surface,
            border: Border(top: BorderSide(color: InspectorTheme.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Icon(Icons.data_object,
                        size: 13, color: InspectorTheme.textDim),
                    const SizedBox(width: 6),
                    Text('Byte Interpretation',
                        style: InspectorTheme.label.copyWith(fontSize: 11)),
                    const Spacer(),
                    Text(
                      '${range.fieldName ?? 'selected'}: $size byte${size == 1 ? '' : 's'} @ +$offset',
                      style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => selectionNotifier.clearSelection(),
                      borderRadius: BorderRadius.circular(3),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.close,
                            size: 12, color: InspectorTheme.textDim),
                      ),
                    ),
                  ],
                ),
              ),
              for (final entry in interpretations)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 65,
                        child: Text(entry.type,
                            style: InspectorTheme.monoSmall
                                .copyWith(color: InspectorTheme.textDim)),
                      ),
                      Expanded(
                        child: SelectableText(entry.value,
                            style: InspectorTheme.monoSmall
                                .copyWith(color: InspectorTheme.text)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Widget _empty() {
    return Container(
      decoration: const BoxDecoration(
        color: InspectorTheme.surface,
        border: Border(top: BorderSide(color: InspectorTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.data_object,
              size: 13,
              color: InspectorTheme.textDim.withValues(alpha: 0.4)),
          const SizedBox(width: 6),
          Text(
            'Click a field or select hex bytes to see interpretations',
            style: InspectorTheme.monoSmall
                .copyWith(fontSize: 10, color: InspectorTheme.textDim),
          ),
        ],
      ),
    );
  }

  List<_Interpretation> _interpret(Uint8List bytes) {
    final results = <_Interpretation>[];
    final bd = ByteData.sublistView(bytes);
    final len = bytes.length;

    // Hex
    results.add(_Interpretation(
      'hex',
      bytes
          .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
          .join(' '),
    ));

    if (len >= 1) {
      results.add(_Interpretation('int8', bd.getInt8(0).toString()));
      results.add(_Interpretation('uint8', bd.getUint8(0).toString()));
    }
    if (len >= 2) {
      results.add(_Interpretation(
          'int16', bd.getInt16(0, Endian.little).toString()));
      results.add(_Interpretation(
          'uint16', bd.getUint16(0, Endian.little).toString()));
    }
    if (len >= 4) {
      results.add(_Interpretation(
          'int32', bd.getInt32(0, Endian.little).toString()));
      results.add(_Interpretation(
        'uint32',
        '${bd.getUint32(0, Endian.little)} (0x${bd.getUint32(0, Endian.little).toRadixString(16)})',
      ));
      final f = bd.getFloat32(0, Endian.little);
      if (f.isFinite) {
        results.add(_Interpretation('float', f.toString()));
      }
    }
    if (len >= 8) {
      results.add(_Interpretation(
          'int64', bd.getInt64(0, Endian.little).toString()));
      results.add(_Interpretation(
        'uint64',
        '0x${bd.getUint64(0, Endian.little).toRadixString(16)}',
      ));
      final d = bd.getFloat64(0, Endian.little);
      if (d.isFinite) {
        results.add(_Interpretation('double', d.toString()));
      }
    }

    // ASCII
    final ascii = bytes
        .map((b) => b >= 32 && b < 127 ? String.fromCharCode(b) : '·')
        .join();
    if (ascii.contains(RegExp(r'[a-zA-Z0-9]'))) {
      results.add(_Interpretation('ascii', '"$ascii"'));
    }

    return results;
  }
}

class _Interpretation {
  final String type;
  final String value;
  const _Interpretation(this.type, this.value);
}
