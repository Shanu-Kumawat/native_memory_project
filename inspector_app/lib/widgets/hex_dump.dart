/// Hex dump widget for displaying raw memory bytes.

import 'package:flutter/material.dart';

import '../theme.dart';

class HexDumpView extends StatelessWidget {
  const HexDumpView({
    super.key,
    required this.bytes,
    required this.baseAddress,
    this.bytesPerRow = 8,
    this.highlightRanges = const [],
  });

  final List<int> bytes;
  final int baseAddress;
  final int bytesPerRow;
  final List<({int offset, int length, Color color})> highlightRanges;

  Color? _highlightColor(int byteIndex) {
    for (final range in highlightRanges) {
      if (byteIndex >= range.offset &&
          byteIndex < range.offset + range.length) {
        return range.color.withValues(alpha: 0.15);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (bytes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No memory data available', style: InspectorTheme.monoSmall),
      );
    }

    final rowCount = (bytes.length + bytesPerRow - 1) ~/ bytesPerRow;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          _buildHeaderRow(),
          const Divider(color: InspectorTheme.border, height: 1),
          // Data rows
          for (int row = 0; row < rowCount; row++) _buildDataRow(row),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text('ADDRESS', style: InspectorTheme.label),
          ),
          for (int i = 0; i < bytesPerRow; i++)
            SizedBox(
              width: 28,
              child: Text(
                i.toRadixString(16).toUpperCase().padLeft(2, '0'),
                style: InspectorTheme.label,
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(width: 16),
          Text('ASCII', style: InspectorTheme.label),
        ],
      ),
    );
  }

  Widget _buildDataRow(int row) {
    final rowStart = row * bytesPerRow;
    final rowEnd =
        (rowStart + bytesPerRow).clamp(0, bytes.length);
    final rowAddr = baseAddress + rowStart;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: row.isEven
            ? Colors.transparent
            : InspectorTheme.surfaceLight.withValues(alpha: 0.3),
      ),
      child: Row(
        children: [
          // Address column
          SizedBox(
            width: 110,
            child: Text(
              '0x${rowAddr.toRadixString(16).padLeft(12, '0')}',
              style: InspectorTheme.monoSmall.copyWith(
                color: InspectorTheme.textDim,
              ),
            ),
          ),
          // Hex bytes
          for (int i = 0; i < bytesPerRow; i++)
            SizedBox(
              width: 28,
              child: rowStart + i < rowEnd
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _highlightColor(rowStart + i),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        bytes[rowStart + i]
                            .toRadixString(16)
                            .toUpperCase()
                            .padLeft(2, '0'),
                        style: InspectorTheme.mono.copyWith(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          const SizedBox(width: 16),
          // ASCII column
          Text(
            _asciiRepr(rowStart, rowEnd),
            style: InspectorTheme.monoSmall,
          ),
        ],
      ),
    );
  }

  String _asciiRepr(int start, int end) {
    final buffer = StringBuffer();
    for (int i = start; i < end; i++) {
      final b = bytes[i];
      buffer.write(b >= 32 && b < 127 ? String.fromCharCode(b) : '·');
    }
    return buffer.toString();
  }
}
