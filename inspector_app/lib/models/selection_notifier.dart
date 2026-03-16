// Shared hover state for bidirectional field ↔ hex highlighting.

import 'package:flutter/material.dart';

/// Notifies listeners when a byte range should be highlighted.
/// Used to synchronize field tree rows and hex dump bytes.
class SelectionNotifier extends ChangeNotifier {
  /// Currently highlighted byte range, or null if nothing is highlighted.
  HighlightRange? _range;
  HighlightRange? get range => _range;

  /// Set the highlighted range. Called by field rows on hover.
  void highlight(int offset, int size, Color color, {String? fieldName}) {
    _range = HighlightRange(
      offset: offset,
      size: size,
      color: color,
      fieldName: fieldName,
    );
    notifyListeners();
  }

  /// Clear the highlight. Called on hover exit.
  void clear() {
    if (_range != null) {
      _range = null;
      notifyListeners();
    }
  }
}

/// A byte range to highlight, with color and optional field name.
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

  /// Check if a byte index falls within this range.
  bool contains(int byteIndex) =>
      byteIndex >= offset && byteIndex < offset + size;
}
