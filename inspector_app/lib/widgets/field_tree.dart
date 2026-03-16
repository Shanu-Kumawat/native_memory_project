// Struct field tree — displays decoded struct fields with dual radix,
// inline expansion, padding rows, and bidirectional hover sync.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../models/selection_notifier.dart';
import '../theme.dart';

class FieldTreeView extends StatelessWidget {
  const FieldTreeView({
    super.key,
    required this.fields,
    this.rawBytes,
    required this.selectionNotifier,
    this.onPointerTap,
  });

  final List<StructField> fields;
  final List<int>? rawBytes;
  final SelectionNotifier selectionNotifier;
  final void Function(int address)? onPointerTap;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      // If we have raw bytes but no struct fields, show as raw memory
      if (rawBytes != null && rawBytes!.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 12,
                      color: InspectorTheme.textDim),
                  const SizedBox(width: 6),
                  Text(
                    'Untyped pointer — ${rawBytes!.length} raw bytes',
                    style: InspectorTheme.monoSmall
                        .copyWith(color: InspectorTheme.textDim, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Pattern hints
              ..._patternHints(),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('No field data available',
            style: InspectorTheme.monoSmall.copyWith(fontSize: 10)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('FIELD', style: _headerStyle)),
              Expanded(flex: 4, child: Text('VALUE', style: _headerStyle)),
              Expanded(flex: 2, child: Text('TYPE', style: _headerStyle)),
              SizedBox(width: 50, child: Text('OFF', style: _headerStyle)),
              SizedBox(
                width: 40,
                child: Text('SIZE', style: _headerStyle, textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
        const Divider(color: InspectorTheme.border, height: 1),
        // Source indicator
        if (rawBytes != null && rawBytes!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(
              children: [
                Icon(Icons.memory, size: 10, color: InspectorTheme.success),
                const SizedBox(width: 4),
                Text(
                  '${rawBytes!.length} bytes from native memory',
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
            depth: 0,
            selectionNotifier: selectionNotifier,
            onPointerTap: onPointerTap,
          ),
      ],
    );
  }

  List<Widget> _patternHints() {
    if (rawBytes == null || rawBytes!.isEmpty) return [];
    final hints = <Widget>[];

    // Check for printable ASCII
    int asciiCount = 0;
    for (final b in rawBytes!) {
      if (b >= 32 && b < 127) asciiCount++;
    }
    if (asciiCount > rawBytes!.length ~/ 2) {
      final ascii = rawBytes!
          .map((b) => b >= 32 && b < 127 ? String.fromCharCode(b) : '·')
          .join();
      hints.add(_hint('Printable ASCII: "$ascii"'));
    }

    // Check for pointer-like values (8 bytes starting with 0x7f or 0x55)
    if (rawBytes!.length >= 8) {
      final bd = ByteData.sublistView(Uint8List.fromList(rawBytes!));
      final val = bd.getUint64(0, Endian.little);
      if (val > 0x100000 && val < 0x7fffffffffff) {
        hints.add(
            _hint('Pointer-like value at +0x00: 0x${val.toRadixString(16)}'));
      }
    }

    // Check for zero-filled regions
    int zeroStart = -1;
    for (int i = 0; i < rawBytes!.length; i++) {
      if (rawBytes![i] == 0) {
        if (zeroStart < 0) zeroStart = i;
      } else {
        if (zeroStart >= 0 && i - zeroStart >= 4) {
          hints.add(_hint(
            'Zero-filled: +0x${zeroStart.toRadixString(16)} to +0x${(i - 1).toRadixString(16)}',
          ));
        }
        zeroStart = -1;
      }
    }

    return hints;
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            const SizedBox(width: 18),
            Icon(Icons.lightbulb_outline, size: 10,
                color: InspectorTheme.warning.withValues(alpha: 0.6)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(text,
                  style: InspectorTheme.monoSmall.copyWith(fontSize: 9)),
            ),
          ],
        ),
      );

  static final _headerStyle = InspectorTheme.label.copyWith(fontSize: 9);
}

// ─── Field Row ───────────────────────────────────────────────────────

class _FieldRow extends StatefulWidget {
  const _FieldRow({
    required this.field,
    required this.index,
    this.rawBytes,
    required this.depth,
    required this.selectionNotifier,
    this.onPointerTap,
  });

  final StructField field;
  final int index;
  final List<int>? rawBytes;
  final int depth;
  final SelectionNotifier selectionNotifier;
  final void Function(int address)? onPointerTap;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final color = InspectorTheme.typeColor(f.typeName);

    return ListenableBuilder(
      listenable: widget.selectionNotifier,
      builder: (context, _) {
        final highlighted = widget.selectionNotifier.range;
        final isHighlighted = highlighted != null &&
            highlighted.offset == f.offset &&
            highlighted.size == f.size;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MouseRegion(
              onEnter: (_) => widget.selectionNotifier.highlight(
                f.offset,
                f.size,
                color,
                fieldName: f.name,
              ),
              onExit: (_) => widget.selectionNotifier.clear(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: EdgeInsets.only(
                  left: 12.0 + widget.depth * 16,
                  right: 12,
                  top: 4,
                  bottom: 4,
                ),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? color.withValues(alpha: 0.08)
                      : widget.index.isEven
                          ? Colors.transparent
                          : InspectorTheme.surfaceLight.withValues(alpha: 0.15),
                  border: isHighlighted
                      ? Border(
                          left: BorderSide(color: color, width: 2))
                      : null,
                ),
                child: Row(
                  children: [
                    // Expand/tree icon + name
                    Expanded(
                      flex: 3,
                      child: _nameCell(f, color),
                    ),
                    // Value
                    Expanded(
                      flex: 4,
                      child: _valueCell(f),
                    ),
                    // Type badge
                    Expanded(
                      flex: 2,
                      child: _typeBadge(f, color),
                    ),
                    // Offset
                    SizedBox(
                      width: 50,
                      child: Text(
                        '+${f.offset}',
                        style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
                      ),
                    ),
                    // Size
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${f.size}B',
                        style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Expanded children
            if (f.isExpanded && f.hasChildren)
              for (int i = 0; i < f.children!.length; i++)
                _FieldRow(
                  field: f.children![i],
                  index: i,
                  rawBytes: widget.rawBytes,
                  depth: widget.depth + 1,
                  selectionNotifier: widget.selectionNotifier,
                  onPointerTap: widget.onPointerTap,
                ),
          ],
        );
      },
    );
  }

  Widget _nameCell(StructField f, Color color) {
    return Row(
      children: [
        // Expand toggle for expandable fields
        if (f.hasChildren)
          GestureDetector(
            onTap: () => setState(() => f.isExpanded = !f.isExpanded),
            child: Icon(
              f.isExpanded ? Icons.expand_more : Icons.chevron_right,
              size: 14,
              color: InspectorTheme.textDim,
            ),
          )
        else
          Icon(
            f.isPadding ? Icons.more_horiz : Icons.remove,
            size: 12,
            color: f.isPadding
                ? InspectorTheme.padding
                : InspectorTheme.border,
          ),
        const SizedBox(width: 4),
        Text(
          f.name,
          style: InspectorTheme.monoSmall.copyWith(
            color: f.isPadding
                ? InspectorTheme.padding
                : InspectorTheme.accent,
            fontWeight: FontWeight.w500,
            fontStyle: f.isPadding ? FontStyle.italic : null,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _valueCell(StructField f) {
    if (f.isPadding) {
      return Text('···',
          style: InspectorTheme.monoSmall.copyWith(
              color: InspectorTheme.padding, fontSize: 10));
    }

    final decoded = _decodeFieldValue(f, widget.rawBytes);
    if (decoded != null) {
      // Dual radix for integer types
      if (_isIntType(f.typeName) && !f.isPointer) {
        final intVal = _decodeRawInt(f, widget.rawBytes);
        if (intVal != null) {
          return Row(
            children: [
              Text(decoded,
                  style: InspectorTheme.monoSmall.copyWith(
                      color: InspectorTheme.text, fontSize: 11)),
              const SizedBox(width: 4),
              Text(
                '(0x${intVal.toRadixString(16).toUpperCase()})',
                style: InspectorTheme.monoSmall
                    .copyWith(color: InspectorTheme.textDim, fontSize: 10),
              ),
            ],
          );
        }
      }

      // Pointer values — clickable
      if (f.isPointer && widget.onPointerTap != null) {
        final addr = _decodePointerAddress(f, widget.rawBytes);
        if (addr != null && addr != 0) {
          return GestureDetector(
            onTap: () => widget.onPointerTap!(addr),
            child: Row(
              children: [
                Text(
                  decoded,
                  style: InspectorTheme.monoSmall.copyWith(
                    color: InspectorTheme.success,
                    fontSize: 11,
                    decoration: TextDecoration.underline,
                    decorationColor: InspectorTheme.success.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.open_in_new, size: 9,
                    color: InspectorTheme.success.withValues(alpha: 0.5)),
              ],
            ),
          );
        }
      }

      return Text(decoded,
          style: InspectorTheme.monoSmall
              .copyWith(color: InspectorTheme.text, fontSize: 11));
    }

    return Text('—',
        style: InspectorTheme.monoSmall
            .copyWith(color: InspectorTheme.textDim, fontSize: 10));
  }

  Widget _typeBadge(StructField f, Color color) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(
          f.typeName,
          style: InspectorTheme.monoSmall.copyWith(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  // ─── Decoders ───

  bool _isIntType(String t) => const {
        'Int8', 'Int16', 'Int32', 'Int64',
        'Uint8', 'Uint16', 'Uint32', 'Uint64',
      }.contains(t);

  int? _decodeRawInt(StructField field, List<int>? bytes) {
    if (bytes == null || field.offset + field.size > bytes.length) return null;
    try {
      final data = Uint8List.fromList(
        bytes.sublist(field.offset, field.offset + field.size),
      );
      final bd = ByteData.sublistView(data);
      return switch (field.typeName) {
        'Int8' => bd.getInt8(0),
        'Uint8' => bd.getUint8(0),
        'Int16' => bd.getInt16(0, Endian.little),
        'Uint16' => bd.getUint16(0, Endian.little),
        'Int32' => bd.getInt32(0, Endian.little),
        'Uint32' => bd.getUint32(0, Endian.little),
        'Int64' => bd.getInt64(0, Endian.little),
        'Uint64' => bd.getUint64(0, Endian.little),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  int? _decodePointerAddress(StructField field, List<int>? bytes) {
    if (bytes == null || field.offset + 8 > bytes.length) return null;
    try {
      final data = Uint8List.fromList(
        bytes.sublist(field.offset, field.offset + 8),
      );
      return ByteData.sublistView(data).getUint64(0, Endian.little);
    } catch (_) {
      return null;
    }
  }

  String? _decodeFieldValue(StructField field, List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    if (field.offset + field.size > bytes.length) return null;

    try {
      final data = Uint8List.fromList(
        bytes.sublist(field.offset, field.offset + field.size),
      );
      final bd = ByteData.sublistView(data);

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
        _ => _hexString(data),
      };
    } catch (_) {
      return null;
    }
  }

  String _hexString(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }
}
