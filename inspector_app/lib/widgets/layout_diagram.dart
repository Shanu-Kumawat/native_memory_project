// Layout diagram — byte-level ruler showing field positions and padding.
// Always visible (not collapsible).

import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../models/selection_notifier.dart';
import '../theme.dart';

class LayoutDiagram extends StatelessWidget {
  const LayoutDiagram({
    super.key,
    required this.fields,
    required this.totalSize,
    required this.selectionNotifier,
  });

  final List<StructField> fields;
  final int totalSize;
  final SelectionNotifier selectionNotifier;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty || totalSize <= 0) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: selectionNotifier,
      builder: (context, _) {
        final hovered = selectionNotifier.hoverRange;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: InspectorTheme.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.straighten,
                      size: 13, color: InspectorTheme.textDim),
                  const SizedBox(width: 6),
                  Text('Memory Layout',
                      style: InspectorTheme.label.copyWith(fontSize: 11)),
                  const Spacer(),
                  Text('$totalSize bytes',
                      style: InspectorTheme.monoSmall.copyWith(fontSize: 10)),
                ],
              ),
              const SizedBox(height: 8),
              // Field blocks
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: InspectorTheme.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Row(
                    children: [
                      for (final field in fields)
                        Expanded(
                          flex: field.size.clamp(1, totalSize),
                          child: _fieldBlock(field, hovered),
                        ),
                    ],
                  ),
                ),
              ),
              // Offset ruler
              const SizedBox(height: 2),
              Row(
                children: [
                  Text('0',
                      style: InspectorTheme.monoSmall.copyWith(fontSize: 9)),
                  const Spacer(),
                  Text('$totalSize',
                      style: InspectorTheme.monoSmall.copyWith(fontSize: 9)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _fieldBlock(StructField field, HighlightRange? hovered) {
    final color = field.isPadding
        ? InspectorTheme.padding
        : InspectorTheme.typeColor(field.typeName);

    final isHovered = hovered != null &&
        hovered.offset == field.offset &&
        hovered.size == field.size;

    return MouseRegion(
      onEnter: (_) {
        if (!field.isPadding) {
          selectionNotifier.hover(
            field.offset, field.size, color,
            fieldName: field.name,
          );
        }
      },
      onExit: (_) => selectionNotifier.clearHover(),
      child: Tooltip(
        message: field.isPadding
            ? 'padding: ${field.size}B @ +${field.offset}'
            : '${field.name}: ${field.typeName} (${field.size}B @ +${field.offset})',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 30,
          decoration: BoxDecoration(
            color: isHovered
                ? color.withValues(alpha: 0.35)
                : color.withValues(alpha: field.isPadding ? 0.08 : 0.15),
            border: Border(
              right: BorderSide(
                color: InspectorTheme.border.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            field.isPadding ? '···' : field.name,
            style: InspectorTheme.monoSmall.copyWith(
              color: field.isPadding
                  ? InspectorTheme.textDim.withValues(alpha: 0.5)
                  : color,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
