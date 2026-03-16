// Shared state for bidirectional field ↔ hex highlighting and byte selection.
//
// Two separate concepts:
// - HOVER: transient highlighting for field↔hex sync (mouse enter/exit)
// - SELECTION: persistent byte range selection for byte interpretation (click)

import 'package:flutter/material.dart';

class SelectionNotifier extends ChangeNotifier {
  // ─── Hover state (for bidirectional field↔hex highlighting) ───
  HighlightRange? _hoverRange;
  HighlightRange? get hoverRange => _hoverRange;

  void hover(int offset, int size, Color color, {String? fieldName}) {
    _hoverRange = HighlightRange(
      offset: offset, size: size, color: color, fieldName: fieldName,
    );
    notifyListeners();
  }

  void clearHover() {
    if (_hoverRange != null) {
      _hoverRange = null;
      notifyListeners();
    }
  }

  // ─── Selection state (for byte interpretation panel) ───
  HighlightRange? _selection;
  HighlightRange? get selection => _selection;

  void select(int offset, int size, Color color, {String? fieldName}) {
    _selection = HighlightRange(
      offset: offset, size: size, color: color, fieldName: fieldName,
    );
    notifyListeners();
  }

  void clearSelection() {
    if (_selection != null) {
      _selection = null;
      notifyListeners();
    }
  }
}

/// A byte range with color and optional field name.
class HighlightRange {
  final int offset;
  final int size;
  final Color color;
  final String? fieldName;

  const HighlightRange({
    required this.offset,
    required this.size,
    required this.color,
    this.fieldName,
  });

  bool contains(int byteIndex) =>
      byteIndex >= offset && byteIndex < offset + size;
}
