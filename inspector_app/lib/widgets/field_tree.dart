/// Struct field tree widget for displaying decoded struct fields.

import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../theme.dart';

class FieldTreeView extends StatelessWidget {
  const FieldTreeView({
    super.key,
    required this.fields,
  });

  final List<StructField> fields;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
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
        // Field rows
        for (int i = 0; i < fields.length; i++) _FieldRow(field: fields[i], index: i),
      ],
    );
  }
}

class _FieldRow extends StatefulWidget {
  const _FieldRow({required this.field, required this.index});

  final StructField field;
  final int index;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final typeColor = InspectorTheme.typeColor(f.typeName);
    final isLast = false; // Will be set by parent if needed

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
            // Tree connector
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Icon(
                    isLast ? Icons.subdirectory_arrow_right : Icons.remove,
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
            // Value
            Expanded(
              flex: 3,
              child: f.isReadable && f.value != null
                  ? Text(
                      _formatValue(f),
                      style: InspectorTheme.mono.copyWith(
                        color: InspectorTheme.text,
                      ),
                    )
                  : Text(
                      f.isReadable ? '—' : '<unreadable>',
                      style: InspectorTheme.monoSmall.copyWith(
                        color: InspectorTheme.error,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
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
      return v; // Already formatted as hex
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
