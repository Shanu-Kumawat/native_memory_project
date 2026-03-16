// Hex dump view — interactive hex viewer with bidirectional highlighting,
// byte selection for interpretation, padding visualization, and lazy loading.
//
// Two interaction modes:
// - HOVER: mouse enter/exit on bytes → bidirectional field↔hex highlighting
// - SELECT: click a byte or click+drag across bytes → byte interpretation panel

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

  static const int bytesPerRow = 8;
  static const double offsetColWidth = 72;
  static const double byteWidth = 30;
  static const double asciiGap = 14;
  static const double rowHeight = 26;

  @override
  State<HexDumpView> createState() => _HexDumpViewState();
}

class _HexDumpViewState extends State<HexDumpView> {
  // Selection state
  int? _selectStart;
  int? _selectEnd;
  bool _isDragging = false;

  /// Convert a local offset (relative to the hex area) to a byte index.
  int? _hitTestByte(Offset localPos, double hexAreaLeft) {
    final relX = localPos.dx - hexAreaLeft;
    final relY = localPos.dy;

    if (relX < 0) return null;

    final col = (relX / HexDumpView.byteWidth).floor();
    // Subtract 1 row for the header
    final rowOffset = relY - HexDumpView.rowHeight; // header row
    if (rowOffset < 0) return null;
    final row = (rowOffset / HexDumpView.rowHeight).floor();

    if (col < 0 || col >= HexDumpView.bytesPerRow) return null;

    final idx = row * HexDumpView.bytesPerRow + col;
    if (idx < 0 || idx >= widget.bytes.length) return null;
    return idx;
  }

  void _startSelect(int index) {
    setState(() {
      _selectStart = index;
      _selectEnd = index;
      _isDragging = true;
    });
  }

  void _updateSelect(int index) {
    if (_isDragging) {
      setState(() => _selectEnd = index);
    }
  }

  void _finishSelect() {
    if (_selectStart != null && _selectEnd != null) {
      final lo = _selectStart! < _selectEnd! ? _selectStart! : _selectEnd!;
      final hi = _selectStart! > _selectEnd! ? _selectStart! : _selectEnd!;
      final size = hi - lo + 1;

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
    setState(() => _isDragging = false);
  }

  /// Get the selected range (lo, hi inclusive).
  (int, int)? get _selectionRange {
    if (_selectStart == null || _selectEnd == null) return null;
    final lo = _selectStart! < _selectEnd! ? _selectStart! : _selectEnd!;
    final hi = _selectStart! > _selectEnd! ? _selectStart! : _selectEnd!;
    return (lo, hi);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bytes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('No memory data',
            style: InspectorTheme.monoSmall.copyWith(fontSize: 12)),
      );
    }

    return ListenableBuilder(
      listenable: widget.selectionNotifier,
      builder: (context, _) {
        final hovered = widget.selectionNotifier.hoverRange;
        final selected = widget.selectionNotifier.selection;
        final rowCount =
            (widget.bytes.length + HexDumpView.bytesPerRow - 1) ~/
                HexDumpView.bytesPerRow;

        return LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) {
                final idx = _hitTestByte(
                    d.localPosition, HexDumpView.offsetColWidth);
                if (idx != null) _startSelect(idx);
              },
              onPanUpdate: (d) {
                final idx = _hitTestByte(
                    d.localPosition, HexDumpView.offsetColWidth);
                if (idx != null) _updateSelect(idx);
              },
              onPanEnd: (_) => _finishSelect(),
              onPanCancel: () => _finishSelect(),
              onTapUp: (d) {
                final idx = _hitTestByte(
                    d.localPosition, HexDumpView.offsetColWidth);
                if (idx != null) {
                  _startSelect(idx);
                  _finishSelect();
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  SizedBox(
                    height: HexDumpView.rowHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: HexDumpView.offsetColWidth,
                            child: Text('OFFSET', style: _headerStyle),
                          ),
                          for (int c = 0; c < HexDumpView.bytesPerRow; c++)
                            SizedBox(
                              width: HexDumpView.byteWidth,
                              child: Text(
                                c.toRadixString(16).toUpperCase(),
                                style: _headerStyle,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(width: HexDumpView.asciiGap),
                          Text('ASCII', style: _headerStyle),
                        ],
                      ),
                    ),
                  ),
                  const Divider(color: InspectorTheme.border, height: 1),
                  // Data rows
                  for (int row = 0; row < rowCount; row++)
                    _hexRow(row, hovered, selected),
                  // Load more
                  if (widget.hasMore && widget.onLoadMore != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Center(
                        child: TextButton.icon(
                          onPressed: widget.onLoadMore,
                          icon: const Icon(Icons.expand_more, size: 14),
                          label: Text('Load more...',
                              style: InspectorTheme.monoSmall
                                  .copyWith(fontSize: 12)),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _hexRow(
      int row, HighlightRange? hovered, HighlightRange? selected) {
    final startIdx = row * HexDumpView.bytesPerRow;
    final endIdx =
        (startIdx + HexDumpView.bytesPerRow).clamp(0, widget.bytes.length);
    final dragRange = _selectionRange;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: HexDumpView.rowHeight,
        child: Row(
          children: [
            // Offset column
            SizedBox(
              width: HexDumpView.offsetColWidth,
              child: Text(
                '+${startIdx.toRadixString(16).padLeft(4, '0')}',
                style: InspectorTheme.monoSmall
                    .copyWith(color: InspectorTheme.textDim, fontSize: 12),
              ),
            ),
            // Hex bytes
            for (int i = startIdx; i < startIdx + HexDumpView.bytesPerRow; i++)
              SizedBox(
                width: HexDumpView.byteWidth,
                child: i < endIdx
                    ? _hexByte(i, widget.bytes[i], hovered, selected,
                        dragRange)
                    : const SizedBox.shrink(),
              ),
            // ASCII
            const SizedBox(width: HexDumpView.asciiGap),
            Text(
              widget.bytes
                  .sublist(startIdx, endIdx)
                  .map((b) =>
                      b >= 32 && b < 127 ? String.fromCharCode(b) : '·')
                  .join(),
              style: InspectorTheme.monoSmall.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hexByte(int index, int value, HighlightRange? hovered,
      HighlightRange? selected, (int, int)? dragRange) {
    final containingField = _fieldAt(index);
    final isPadding = containingField?.isPadding ?? false;

    final isHovered = hovered != null && hovered.contains(index);
    final isSelected = selected != null && selected.contains(index);
    final isDragSelected = dragRange != null &&
        index >= dragRange.$1 &&
        index <= dragRange.$2 &&
        _isDragging;

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
            fontSize: 12,
            color: textColor,
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

  static final _headerStyle = InspectorTheme.label.copyWith(fontSize: 11);
}
