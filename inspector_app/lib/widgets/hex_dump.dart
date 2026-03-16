// Hex dump view — interactive hex viewer with bidirectional highlighting,
// byte selection for interpretation, padding visualization, and lazy loading.

import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../models/selection_notifier.dart';
import '../theme.dart';

class HexDumpView extends StatefulWidget {
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
  State<HexDumpView> createState() => _HexDumpViewState();
}

class _HexDumpViewState extends State<HexDumpView> {
  // Selection state for click-drag
  int? _selectStart;
  int? _selectEnd;
  bool _isDragging = false;

  void _startSelect(int index) {
    setState(() {
      _selectStart = index;
      _selectEnd = index;
      _isDragging = true;
    });
  }

  void _updateSelect(int index) {
    if (_isDragging && _selectStart != null) {
      setState(() => _selectEnd = index);
    }
  }

  void _finishSelect() {
    if (_selectStart != null && _selectEnd != null) {
      final lo = _selectStart! < _selectEnd! ? _selectStart! : _selectEnd!;
      final hi = _selectStart! > _selectEnd! ? _selectStart! : _selectEnd!;
      final size = hi - lo + 1;

      // Find the field at the selection start for naming
      final field = _fieldAt(lo);
      widget.selectionNotifier.select(
        lo,
        size,
        field != null
            ? InspectorTheme.typeColor(field.typeName)
            : InspectorTheme.accent,
        fieldName: field?.name,
      );
    }
    _isDragging = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bytes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('No memory data',
            style: InspectorTheme.monoSmall.copyWith(fontSize: 11)),
      );
    }

    return ListenableBuilder(
      listenable: widget.selectionNotifier,
      builder: (context, _) {
        final hovered = widget.selectionNotifier.hoverRange;
        final selected = widget.selectionNotifier.selection;
        const bytesPerRow = 8;
        final rowCount =
            (widget.bytes.length + bytesPerRow - 1) ~/ bytesPerRow;

        return MouseRegion(
          onExit: (_) {
            if (_isDragging) _finishSelect();
          },
          child: GestureDetector(
            onPanEnd: (_) => _finishSelect(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 70,
                          child: Text('OFFSET', style: _headerStyle)),
                      for (int c = 0; c < bytesPerRow; c++)
                        SizedBox(
                          width: 28,
                          child: Text(
                            c.toRadixString(16).toUpperCase(),
                            style: _headerStyle,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(width: 14),
                      Text('ASCII', style: _headerStyle),
                    ],
                  ),
                ),
                const Divider(color: InspectorTheme.border, height: 1),
                // Hex rows
                for (int row = 0; row < rowCount; row++)
                  _hexRow(row, bytesPerRow, hovered, selected),
                // Load more button
                if (widget.hasMore && widget.onLoadMore != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(
                      child: TextButton.icon(
                        onPressed: widget.onLoadMore,
                        icon: const Icon(Icons.expand_more, size: 14),
                        label: Text('Load more...',
                            style:
                                InspectorTheme.monoSmall.copyWith(fontSize: 11)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hexRow(int row, int bytesPerRow, HighlightRange? hovered,
      HighlightRange? selected) {
    final startIdx = row * bytesPerRow;
    final endIdx =
        (startIdx + bytesPerRow).clamp(0, widget.bytes.length);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(
                '+${startIdx.toRadixString(16).padLeft(4, '0')}',
                style: InspectorTheme.monoSmall
                    .copyWith(color: InspectorTheme.textDim, fontSize: 11),
              ),
            ),
            for (int i = startIdx; i < startIdx + bytesPerRow; i++)
              SizedBox(
                width: 28,
                child: i < endIdx
                    ? _hexByte(i, widget.bytes[i], hovered, selected)
                    : const SizedBox.shrink(),
              ),
            const SizedBox(width: 14),
            Text(
              widget.bytes
                  .sublist(startIdx, endIdx)
                  .map((b) =>
                      b >= 32 && b < 127 ? String.fromCharCode(b) : '·')
                  .join(),
              style: InspectorTheme.monoSmall.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hexByte(int index, int value, HighlightRange? hovered,
      HighlightRange? selected) {
    final containingField = _fieldAt(index);
    final isPadding = containingField?.isPadding ?? false;

    final isHovered = hovered != null && hovered.contains(index);
    final isSelected = selected != null && selected.contains(index);

    // Drag selection highlight
    bool isDragSelected = false;
    if (_isDragging && _selectStart != null && _selectEnd != null) {
      final lo = _selectStart! < _selectEnd! ? _selectStart! : _selectEnd!;
      final hi = _selectStart! > _selectEnd! ? _selectStart! : _selectEnd!;
      isDragSelected = index >= lo && index <= hi;
    }

    Color? bgColor;
    Color textColor = InspectorTheme.text;

    if (isDragSelected || isSelected) {
      bgColor = InspectorTheme.accent.withValues(alpha: 0.25);
      textColor = InspectorTheme.accent;
    } else if (isHovered) {
      bgColor = hovered.color.withValues(alpha: 0.15);
      textColor = hovered.color;
    } else if (isPadding) {
      textColor = InspectorTheme.padding.withValues(alpha: 0.6);
    }

    return MouseRegion(
      onEnter: (_) {
        if (containingField != null && !containingField.isPadding) {
          widget.selectionNotifier.hover(
            containingField.offset,
            containingField.size,
            InspectorTheme.typeColor(containingField.typeName),
            fieldName: containingField.name,
          );
        }
      },
      onExit: (_) => widget.selectionNotifier.clearHover(),
      child: GestureDetector(
        onTapDown: (_) => _startSelect(index),
        onPanStart: (_) => _startSelect(index),
        onPanUpdate: (details) {
          // Calculate which byte the cursor is over
          // Each byte is 28px wide, offset from 70px
          if (_isDragging) {
            _updateSelect(index);
          }
        },
        onTapUp: (_) => _finishSelect(),
        child: Container(
          alignment: Alignment.center,
          decoration: bgColor != null
              ? BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(2),
                )
              : null,
          child: Text(
            value.toRadixString(16).toUpperCase().padLeft(2, '0'),
            style: InspectorTheme.monoSmall.copyWith(
              fontSize: 11,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  StructField? _fieldAt(int byteIndex) {
    for (final f in widget.fields) {
      if (byteIndex >= f.offset && byteIndex < f.offset + f.size) {
        return f;
      }
    }
    return null;
  }

  static final _headerStyle = InspectorTheme.label.copyWith(fontSize: 10);
}
