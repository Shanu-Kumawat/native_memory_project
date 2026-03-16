/// Struct field tree widget for displaying decoded struct fields.
/// When raw bytes are available (from _readNativeMemory RPC), decodes
/// actual field values from memory. Otherwise shows layout-only data.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../theme.dart';

class FieldTreeView extends StatelessWidget {
  const FieldTreeView({
    super.key,
    required this.fields,
    this.rawBytes,
  });

  final List<StructField> fields;
  /// Raw bytes from native memory (via _readNativeMemory RPC).
  final List<int>? rawBytes;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      // If we have raw bytes but no struct fields, show as raw memory
      if (rawBytes != null && rawBytes!.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14,
                      color: InspectorTheme.textDim),
                  const SizedBox(width: 6),
                  Text(
                    'Untyped pointer — showing ${rawBytes!.length} raw bytes',
                    style: InspectorTheme.monoSmall.copyWith(
                      color: InspectorTheme.textDim,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: InspectorTheme.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: InspectorTheme.border),
                ),
                child: SelectableText(
                  _formatRawBytes(rawBytes!),
                  style: InspectorTheme.monoSmall.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No field data available',
          style: InspectorTheme.monoSmall,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('FIELD', style: InspectorTheme.label),
              ),
              Expanded(
                flex: 3,
                child: Text('VALUE', style: InspectorTheme.label),
              ),
              Expanded(
                flex: 2,
                child: Text('TYPE', style: InspectorTheme.label),
              ),
              SizedBox(
                width: 80,
                child: Text('OFFSET', style: InspectorTheme.label),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  'SIZE',
                  style: InspectorTheme.label,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        const Divider(color: InspectorTheme.border, height: 1),
        // Source indicator
        if (rawBytes != null && rawBytes!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.memory, size: 12, color: InspectorTheme.success),
                const SizedBox(width: 4),
                Text(
                  'Live memory values (${rawBytes!.length} bytes read)',
                  style: InspectorTheme.monoSmall.copyWith(
                    color: InspectorTheme.success,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        // Field rows
        for (int i = 0; i < fields.length; i++)
          _FieldRow(
            field: fields[i],
            index: i,
            rawBytes: rawBytes,
          ),
      ],
    );
  }

  /// Format raw bytes as a hex string with address markers (8 bytes per line).
  static String _formatRawBytes(List<int> bytes) {
    final buf = StringBuffer();
    for (int i = 0; i < bytes.length; i += 8) {
      final end = (i + 8).clamp(0, bytes.length);
      final hex = bytes.sublist(i, end)
          .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
          .join(' ');
      final ascii = bytes.sublist(i, end)
          .map((b) => b >= 32 && b < 127 ? String.fromCharCode(b) : '·')
          .join();
      buf.writeln('+${i.toRadixString(16).padLeft(4, '0')}  $hex${' ' * (24 - hex.length)}  $ascii');
    }
    return buf.toString().trimRight();
  }
}

class _FieldRow extends StatefulWidget {
  const _FieldRow({
    required this.field,
    required this.index,
    this.rawBytes,
  });

  final StructField field;
  final int index;
  final List<int>? rawBytes;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final typeColor = InspectorTheme.typeColor(f.typeName);

    // Try to decode value from raw bytes
    final decodedValue = _decodeFieldValue(f, widget.rawBytes);
    final hasLiveValue = decodedValue != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered
              ? InspectorTheme.surfaceLight.withValues(alpha: 0.5)
              : widget.index.isEven
                  ? Colors.transparent
                  : InspectorTheme.surfaceLight.withValues(alpha: 0.2),
        ),
        child: Row(
          children: [
            // Tree connector + name
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Icon(
                    Icons.remove,
                    size: 14,
                    color: InspectorTheme.border,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    f.name,
                    style: InspectorTheme.mono.copyWith(
                      color: InspectorTheme.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Value — decoded from memory or from field.value
            Expanded(
              flex: 3,
              child: _buildValueCell(f, decodedValue, hasLiveValue),
            ),
            // Type badge
            Expanded(
              flex: 2,
              child: _TypeBadge(typeName: f.typeName, color: typeColor),
            ),
            // Offset
            SizedBox(
              width: 80,
              child: Text(
                '+${f.offset}',
                style: InspectorTheme.monoSmall,
              ),
            ),
            // Size
            SizedBox(
              width: 60,
              child: Text(
                '${f.size}B',
                style: InspectorTheme.monoSmall,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValueCell(StructField f, String? decodedValue, bool hasLiveValue) {
    if (hasLiveValue) {
      return Row(
        children: [
          Text(
            decodedValue!,
            style: InspectorTheme.mono.copyWith(
              color: InspectorTheme.text,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.memory, size: 10, color: InspectorTheme.success.withValues(alpha: 0.6)),
        ],
      );
    }

    // Fallback: use field.value if available
    if (f.isReadable && f.value != null) {
      return Text(
        _formatValue(f),
        style: InspectorTheme.mono.copyWith(
          color: InspectorTheme.text,
        ),
      );
    }

    return Text(
      f.isReadable ? '—' : '<unreadable>',
      style: InspectorTheme.monoSmall.copyWith(
        color: InspectorTheme.error,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  /// Decode a field's value from raw bytes using its offset, size, and type.
  String? _decodeFieldValue(StructField field, List<int>? rawBytes) {
    if (rawBytes == null || rawBytes.isEmpty) return null;
    if (field.offset + field.size > rawBytes.length) return null;

    try {
      final bytes = Uint8List.fromList(
        rawBytes.sublist(field.offset, field.offset + field.size),
      );
      final bd = ByteData.sublistView(bytes);

      return switch (field.typeName) {
        'Int8' => bd.getInt8(0).toString(),
        'Uint8' => bd.getUint8(0).toString(),
        'Int16' => bd.getInt16(0, Endian.little).toString(),
        'Uint16' => bd.getUint16(0, Endian.little).toString(),
        'Int32' => bd.getInt32(0, Endian.little).toString(),
        'Uint32' => bd.getUint32(0, Endian.little).toString(),
        'Int64' => bd.getInt64(0, Endian.little).toString(),
        'Uint64' => bd.getUint64(0, Endian.little).toString(),
        'Float' => bd.getFloat32(0, Endian.little).toStringAsFixed(4),
        'Double' => bd.getFloat64(0, Endian.little).toStringAsFixed(6),
        'Bool' => bd.getUint8(0) != 0 ? 'true' : 'false',
        _ when field.typeName.startsWith('Pointer') =>
          '0x${bd.getUint64(0, Endian.little).toRadixString(16)}',
        _ => _hexString(bytes),
      };
    } catch (e) {
      return null;
    }
  }

  String _hexString(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  String _formatValue(StructField f) {
    final v = f.value;
    if (v is double) {
      return v.toStringAsFixed(v == v.truncateToDouble() ? 1 : 6);
    }
    if (v is int) {
      if (f.typeName.startsWith('Pointer')) {
        return '0x${v.toRadixString(16)}';
      }
      return v.toString();
    }
    if (v is String && v.startsWith('0x')) {
      return v;
    }
    return v.toString();
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.typeName, required this.color});

  final String typeName;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          typeName,
          style: InspectorTheme.monoSmall.copyWith(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
