// Hex dump view — interactive hex viewer with bidirectional highlighting,
// padding visualization, and lazy loading.

import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../models/selection_notifier.dart';
import '../theme.dart';

class HexDumpView extends StatelessWidget {
  const HexDumpView({
    super.key,
    required this.bytes,
    required this.baseAddress,
    required this.selectionNotifier,
    this.fields = const [],
    this.onLoadMore,
    this.hasMore = false,
  });

  final List<int> bytes;
  final int baseAddress;
  final SelectionNotifier selectionNotifier;
  final List<StructField> fields;
  final VoidCallback? onLoadMore;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    if (bytes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('No memory data',
            style: InspectorTheme.monoSmall.copyWith(fontSize: 10)),
      );
    }

    return ListenableBuilder(
      listenable: selectionNotifier,
      builder: (context, _) {
        final highlighted = selectionNotifier.range;
        const bytesPerRow = 8;
        final rowCount = (bytes.length + bytesPerRow - 1) ~/ bytesPerRow;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text('OFFSET', style: _headerStyle),
                  ),
                  // Byte column headers
                  for (int c = 0; c < bytesPerRow; c++)
                    SizedBox(
                      width: 26,
                      child: Text(
                        c.toRadixString(16).toUpperCase(),
                        style: _headerStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Text('ASCII', style: _headerStyle),
                ],
              ),
            ),
            const Divider(color: InspectorTheme.border, height: 1),
            // Hex rows
            for (int row = 0; row < rowCount; row++)
              _hexRow(row, bytesPerRow, highlighted),
            // Load more button
            if (hasMore && onLoadMore != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: TextButton.icon(
                    onPressed: onLoadMore,
                    icon: const Icon(Icons.expand_more, size: 14),
                    label: Text('Load more...',
                        style: InspectorTheme.monoSmall.copyWith(fontSize: 10)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _hexRow(int row, int bytesPerRow, HighlightRange? highlighted) {
    final startIdx = row * bytesPerRow;
    final endIdx = (startIdx + bytesPerRow).clamp(0, bytes.length);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 22,
        child: Row(
          children: [
            // Address
            SizedBox(
              width: 70,
              child: Text(
                '+${startIdx.toRadixString(16).padLeft(4, '0')}',
                style: InspectorTheme.monoSmall
                    .copyWith(color: InspectorTheme.textDim, fontSize: 10),
              ),
            ),
            // Hex bytes
            for (int i = startIdx; i < startIdx + bytesPerRow; i++)
              SizedBox(
                width: 26,
                child: i < endIdx
                    ? _hexByte(i, bytes[i], highlighted)
                    : const SizedBox.shrink(),
              ),
            const SizedBox(width: 12),
            // ASCII
            Text(
              bytes
                  .sublist(startIdx, endIdx)
                  .map((b) =>
                      b >= 32 && b < 127 ? String.fromCharCode(b) : '·')
                  .join(),
              style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hexByte(int index, int value, HighlightRange? highlighted) {
    // Find the field this byte belongs to
    final containingField = _fieldAt(index);
    final isPadding = containingField?.isPadding ?? false;

    final isInHighlight =
        highlighted != null && highlighted.contains(index);

    final color = isInHighlight
        ? highlighted.color
        : isPadding
            ? InspectorTheme.padding
            : null;

    return MouseRegion(
      onEnter: (_) {
        if (containingField != null && !containingField.isPadding) {
          selectionNotifier.highlight(
            containingField.offset,
            containingField.size,
            InspectorTheme.typeColor(containingField.typeName),
            fieldName: containingField.name,
          );
        }
      },
      onExit: (_) => selectionNotifier.clear(),
      child: Container(
        alignment: Alignment.center,
        decoration: isInHighlight
            ? BoxDecoration(
                color: color?.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              )
            : null,
        child: Text(
          value.toRadixString(16).toUpperCase().padLeft(2, '0'),
          style: InspectorTheme.monoSmall.copyWith(
            fontSize: 10,
            color: isInHighlight
                ? color
                : isPadding
                    ? InspectorTheme.padding.withValues(alpha: 0.6)
                    : InspectorTheme.text,
          ),
        ),
      ),
    );
  }

  StructField? _fieldAt(int byteIndex) {
    for (final f in fields) {
      if (byteIndex >= f.offset && byteIndex < f.offset + f.size) {
        return f;
      }
    }
    return null;
  }

  static final _headerStyle = InspectorTheme.label.copyWith(fontSize: 9);
}
