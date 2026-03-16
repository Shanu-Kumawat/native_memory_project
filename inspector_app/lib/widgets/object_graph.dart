// Object graph — visual structure map for structs with interesting sub-structures.
// Shows nested structs, pointer chains, arrays, and union variants.
// Supports branching, cycle detection, lazy expansion, clickable nodes.

import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../theme.dart';

class ObjectGraph extends StatefulWidget {
  const ObjectGraph({
    super.key,
    required this.rootPointer,
    required this.allPointers,
    required this.onNavigate,
  });

  final PointerData rootPointer;
  final List<PointerData> allPointers;
  final ValueChanged<int> onNavigate;

  @override
  State<ObjectGraph> createState() => _ObjectGraphState();
}

class _ObjectGraphState extends State<ObjectGraph> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Show for any struct with interesting sub-structure:
    // pointer fields, nested structs, arrays, or unions
    if (!widget.rootPointer.hasInterestingStructure) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: InspectorTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: InspectorTheme.textDim,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.account_tree_outlined,
                      size: 13, color: InspectorTheme.textDim),
                  const SizedBox(width: 6),
                  Text('Structure Map',
                      style: InspectorTheme.label.copyWith(fontSize: 11)),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildGraph(),
            ),
        ],
      ),
    );
  }

  Widget _buildGraph() {
    final visited = <int>{};
    return _buildNode(widget.rootPointer, visited, 0);
  }

  Widget _buildNode(PointerData pointer, Set<int> visited, int depth) {
    if (depth > 8) {
      return _label('... (depth limit)', InspectorTheme.textDim);
    }

    if (visited.contains(pointer.address)) {
      return _label(
          '↻ cycle → ${pointer.variableName}', InspectorTheme.warning);
    }
    visited.add(pointer.address);

    // Collect interesting fields
    final interestingFields = pointer.fields
        .where((f) => f.isPointer || f.isStruct || f.isArray)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _nodeWidget(pointer),
        for (final field in interestingFields)
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: _buildEdge(field, pointer, visited, depth),
          ),
      ],
    );
  }

  Widget _buildEdge(
    StructField field,
    PointerData parent,
    Set<int> visited,
    int depth,
  ) {
    // Array fields — show inline summary
    if (field.isArray) {
      return Row(
        children: [
          _connector(),
          Text('.${field.name}', style: _fieldStyle),
          _arrow(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: InspectorTheme.arrayType.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                  color: InspectorTheme.arrayType.withValues(alpha: 0.25)),
            ),
            child: Text(
              '${field.typeName} (${field.size}B)',
              style: InspectorTheme.monoSmall
                  .copyWith(color: InspectorTheme.arrayType, fontSize: 10),
            ),
          ),
        ],
      );
    }

    // Nested struct fields — show type info
    if (field.isStruct) {
      return Row(
        children: [
          _connector(),
          Text('.${field.name}', style: _fieldStyle),
          _arrow(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: InspectorTheme.structType.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                  color: InspectorTheme.structType.withValues(alpha: 0.25)),
            ),
            child: Text(
              '${field.typeName} (${field.size}B)',
              style: InspectorTheme.monoSmall
                  .copyWith(color: InspectorTheme.structType, fontSize: 10),
            ),
          ),
        ],
      );
    }

    // Pointer fields — try to resolve target
    int? targetAddress;
    if (parent.hasRawBytes &&
        field.offset + field.size <= parent.rawBytes!.length) {
      final bytes = parent.rawBytes!.sublist(
        field.offset,
        field.offset + field.size,
      );
      targetAddress = 0;
      for (int i = bytes.length - 1; i >= 0; i--) {
        targetAddress = (targetAddress! << 8) | bytes[i];
      }
    }

    if (targetAddress == null || targetAddress == 0) {
      return Row(
        children: [
          _connector(),
          Text('.${field.name}', style: _fieldStyle),
          _arrow(),
          _label('null', InspectorTheme.textDim),
        ],
      );
    }

    final targetIdx =
        widget.allPointers.indexWhere((p) => p.address == targetAddress);

    if (targetIdx < 0) {
      return Row(
        children: [
          _connector(),
          Text('.${field.name}', style: _fieldStyle),
          _arrow(),
          _label(
            '0x${targetAddress.toRadixString(16)} (not scanned)',
            InspectorTheme.textDim,
          ),
        ],
      );
    }

    final target = widget.allPointers[targetIdx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _connector(),
            Text('.${field.name}', style: _fieldStyle),
            _arrow(),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: _buildNode(target, Set.of(visited), depth + 1),
        ),
      ],
    );
  }

  Widget _nodeWidget(PointerData p) {
    final idx =
        widget.allPointers.indexWhere((x) => x.address == p.address);

    return InkWell(
      onTap: idx >= 0 ? () => widget.onNavigate(idx) : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: InspectorTheme.surfaceLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: InspectorTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              p.variableName,
              style: InspectorTheme.monoSmall.copyWith(
                  color: InspectorTheme.accent, fontSize: 12),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: InspectorTheme.background,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(p.nativeType,
                  style: InspectorTheme.monoSmall.copyWith(fontSize: 10)),
            ),
            if (p.hasFields) ...[
              const SizedBox(width: 6),
              Text(
                _fieldSummary(p),
                style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fieldSummary(PointerData p) {
    final nonPtrFields =
        p.fields.where((f) => !f.isPointer && !f.isPadding).take(2);
    if (nonPtrFields.isEmpty) return '';
    return '[${nonPtrFields.map((f) => f.name).join(', ')}]';
  }

  Widget _connector() => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text('├─', style: _connStyle),
      );

  Widget _arrow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text('──→', style: _connStyle),
      );

  Widget _label(String text, Color color) => Text(
        text,
        style: InspectorTheme.monoSmall.copyWith(
          color: color,
          fontSize: 11,
          fontStyle: FontStyle.italic,
        ),
      );

  static final _fieldStyle = InspectorTheme.monoSmall
      .copyWith(color: InspectorTheme.accent, fontSize: 11);

  static final _connStyle = InspectorTheme.monoSmall.copyWith(
    color: InspectorTheme.border,
    fontSize: 11,
  );
}
