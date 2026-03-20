// Object graph — visual structure map for structs with interesting sub-structures.
// Shows nested structs, pointer chains, arrays, and union variants.
// Supports branching, cycle detection, lazy expansion, clickable nodes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pointer_data.dart';
import '../models/selection_notifier.dart';
import '../theme.dart';

class ObjectGraph extends StatefulWidget {
  const ObjectGraph({
    super.key,
    required this.rootPointer,
    required this.allPointers,
    required this.onNavigate,
    this.selectionNotifier,
  });

  final PointerData rootPointer;
  final List<PointerData> allPointers;
  final ValueChanged<int> onNavigate;
  final SelectionNotifier? selectionNotifier;

  @override
  State<ObjectGraph> createState() => _ObjectGraphState();
}

class _ObjectGraphState extends State<ObjectGraph> {
  bool _expanded = false;
  final Set<String> _expandedEdges = <String>{};

  void _expandAll() {
    setState(() {
      _expandedEdges.clear();
      _traverseToExpand(widget.rootPointer, <int>{}, 0);
    });
  }

  void _collapseAll() {
    setState(() {
      _expandedEdges.clear();
    });
  }

  void _traverseToExpand(PointerData p, Set<int> visited, int depth) {
    if (depth > 6 || visited.contains(p.address)) return;
    visited.add(p.address);

    final interestingFields = p.fields
        .where((f) => f.isPointer || f.isStruct || f.isArray)
        .toList();

    for (final field in interestingFields) {
      if (!field.isPointer) continue;
      int? targetAddress = _resolveTargetAddress(p, field);
      if (targetAddress == null || targetAddress == 0) continue;

      final targetIdx = widget.allPointers.indexWhere(
        (x) => x.address == targetAddress,
      );
      if (targetIdx >= 0) {
        final target = widget.allPointers[targetIdx];
        final edgeKey =
            '${p.address}:${field.name}:${target.address.toRadixString(16)}';
        _expandedEdges.add(edgeKey);
        _traverseToExpand(target, Set.of(visited), depth + 1);
      }
    }
  }

  int? _resolveTargetAddress(PointerData parent, StructField field) {
    if (parent.hasRawBytes &&
        field.offset + field.size <= parent.rawBytes!.length) {
      final bytes = parent.rawBytes!.sublist(
        field.offset,
        field.offset + field.size,
      );
      int targetAddress = 0;
      for (int i = bytes.length - 1; i >= 0; i--) {
        targetAddress = (targetAddress << 8) | bytes[i];
      }
      return targetAddress;
    }
    return null;
  }

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: InspectorTheme.textDim,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.account_tree_outlined,
                    size: 13,
                    color: InspectorTheme.textDim,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Structure Map',
                    style: InspectorTheme.label.copyWith(fontSize: 11),
                  ),
                  const Spacer(),
                  if (_expanded) ...[
                    TextButton(
                      onPressed: _expandAll,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Expand All',
                        style: InspectorTheme.monoSmall.copyWith(
                          color: InspectorTheme.accent,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _collapseAll,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Collapse All',
                        style: InspectorTheme.monoSmall.copyWith(
                          color: InspectorTheme.textDim,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
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
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Icon(Icons.loop, size: 14, color: InspectorTheme.warning),
            const SizedBox(width: 4),
            _label(
              ' Cycle detected → ${pointer.variableName}',
              InspectorTheme.warning,
            ),
          ],
        ),
      );
    }
    visited.add(pointer.address);

    // Collect interesting fields
    final interestingFields = pointer.fields
        .where((f) => f.isPointer || f.isStruct || f.isArray)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (depth == 0) _nodeWidget(pointer),
        if (interestingFields.isNotEmpty)
          Container(
            margin: EdgeInsets.only(
              left: depth == 0 ? 12 : 46,
              top: 4,
              bottom: 4,
            ),
            padding: const EdgeInsets.only(left: 0, top: 4, bottom: 0),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: InspectorTheme.border.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final field in interestingFields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildEdge(field, pointer, visited, depth),
                  ),
              ],
            ),
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
          Text(field.name, style: _fieldStyle),
          _arrow(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: InspectorTheme.arrayType.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: InspectorTheme.arrayType.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              '${field.typeName} (${field.size}B)',
              style: InspectorTheme.monoSmall.copyWith(
                color: InspectorTheme.arrayType,
                fontSize: 11,
              ),
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
          Text(field.name, style: _fieldStyle),
          _arrow(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: InspectorTheme.structType.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: InspectorTheme.structType.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              '${field.typeName} (${field.size}B)',
              style: InspectorTheme.monoSmall.copyWith(
                color: InspectorTheme.structType,
                fontSize: 11,
              ),
            ),
          ),
        ],
      );
    }

    // Pointer fields — try to resolve target
    int? targetAddress = _resolveTargetAddress(parent, field);

    final isRoot = parent.address == widget.rootPointer.address;

    Widget wrapHover(Widget child) {
      if (!isRoot || widget.selectionNotifier == null) return child;
      return MouseRegion(
        onEnter: (_) => widget.selectionNotifier!.hover(
          field.offset,
          field.size,
          InspectorTheme.accent.withValues(alpha: 0.3),
        ),
        onExit: (_) => widget.selectionNotifier!.clearHover(),
        child: child,
      );
    }

    if (targetAddress == null || targetAddress == 0) {
      return Row(
        children: [
          _connector(),
          Text(field.name, style: _fieldStyle),
          _arrow(),
          _label('null', InspectorTheme.textDim.withValues(alpha: 0.6)),
        ],
      );
    }

    final targetIdx = widget.allPointers.indexWhere(
      (p) => p.address == targetAddress,
    );

    if (targetIdx < 0) {
      return Row(
        children: [
          _connector(),
          Text(field.name, style: _fieldStyle),
          _arrow(),
          _label(
            '0x${targetAddress.toRadixString(16)} (not scanned)',
            InspectorTheme.textDim,
          ),
        ],
      );
    }

    final target = widget.allPointers[targetIdx];
    final edgeKey =
        '${parent.address}:${field.name}:${target.address.toRadixString(16)}';
    final isExpanded = depth == 0 || _expandedEdges.contains(edgeKey);
    final isCycle = visited.contains(target.address);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        wrapHover(
          Row(
            children: [
              _connector(),
              InkWell(
                onTap: depth == 0
                    ? null
                    : () {
                        setState(() {
                          if (isExpanded) {
                            _expandedEdges.remove(edgeKey);
                          } else {
                            _expandedEdges.add(edgeKey);
                          }
                        });
                      },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: depth == 0
                        ? InspectorTheme.textDim.withValues(alpha: 0.3)
                        : InspectorTheme.textDim,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(field.name, style: _fieldStyle),
              _arrow(),
              if (isCycle)
                Row(
                  children: [
                    Icon(Icons.loop, size: 14, color: InspectorTheme.warning),
                    const SizedBox(width: 4),
                    _label('Cycle', InspectorTheme.warning),
                  ],
                )
              else
                Row(
                  children: [
                    InkWell(
                      onTap: () {
                        widget.onNavigate(targetIdx);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          '${target.variableName} (${target.nativeType})',
                          style: InspectorTheme.monoSmall.copyWith(
                            color: InspectorTheme.success,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    if (target.hasFields) ...[
                      const SizedBox(width: 4),
                      if (_hasPrimitiveData(target))
                        Text(
                          _primitiveSummary(target),
                          style: InspectorTheme.monoSmall.copyWith(
                            fontSize: 11,
                            color: InspectorTheme.accent,
                          ),
                        )
                      else
                        Text(
                          _fieldSummary(target),
                          style: InspectorTheme.monoSmall.copyWith(
                            fontSize: 10,
                            color: InspectorTheme.textDim.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: target.addressHex),
                        );
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.copy,
                          size: 12,
                          color: InspectorTheme.textDim.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (isExpanded && !isCycle)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _buildNode(target, Set.of(visited), depth + 1),
          ),
      ],
    );
  }

  Widget _nodeWidget(PointerData p) {
    final idx = widget.allPointers.indexWhere((x) => x.address == p.address);

    return InkWell(
      onTap: idx >= 0 ? () => widget.onNavigate(idx) : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: InspectorTheme.surfaceLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: InspectorTheme.border.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              p.variableName,
              style: InspectorTheme.monoSmall.copyWith(
                color: InspectorTheme.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: InspectorTheme.background,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: InspectorTheme.border.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                p.nativeType,
                style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
              ),
            ),
            if (p.hasFields) ...[
              const SizedBox(width: 8),
              if (_hasPrimitiveData(p))
                Text(
                  _primitiveSummary(p),
                  style: InspectorTheme.monoSmall.copyWith(
                    fontSize: 11,
                    color: InspectorTheme.accent,
                  ),
                )
              else
                Text(
                  _fieldSummary(p),
                  style: InspectorTheme.monoSmall.copyWith(
                    fontSize: 10,
                    color: InspectorTheme.textDim.withValues(alpha: 0.7),
                  ),
                ),
            ],
            const SizedBox(width: 4),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: p.addressHex));
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.copy,
                  size: 12,
                  color: InspectorTheme.textDim.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasPrimitiveData(PointerData p) {
    if (!p.hasRawBytes) return false;
    final primitives = p.fields
        .where((f) => !f.isPointer && !f.isArray && !f.isStruct && !f.isPadding)
        .toList();
    if (primitives.isEmpty) return false;
    return primitives.length <= 2; // Only show if it's a small wrapper struct
  }

  String _primitiveSummary(PointerData p) {
    final primitives = p.fields
        .where((f) => !f.isPointer && !f.isArray && !f.isStruct && !f.isPadding)
        .toList();
    final parts = <String>[];
    for (final f in primitives.take(2)) {
      if (f.offset + f.size <= p.rawBytes!.length) {
        final bytes = p.rawBytes!.sublist(f.offset, f.offset + f.size);
        int val = 0;
        for (int i = bytes.length - 1; i >= 0; i--) {
          val = (val << 8) | bytes[i];
        }
        parts.add('${f.name}: $val');
      }
    }
    return '[${parts.join(', ')}]';
  }

  String _fieldSummary(PointerData p) {
    final nonPtrFields = p.fields
        .where((f) => !f.isPointer && !f.isPadding)
        .take(2);
    if (nonPtrFields.isEmpty) return '';
    return '[${nonPtrFields.map((f) => f.name).join(', ')}]';
  }

  Widget _connector() => Container(
    width: 14,
    height: 1.5,
    margin: const EdgeInsets.only(right: 8),
    color: InspectorTheme.border.withValues(alpha: 0.5),
  );

  Widget _arrow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Icon(
      Icons.arrow_forward_rounded,
      size: 14,
      color: InspectorTheme.border.withValues(alpha: 0.6),
    ),
  );

  Widget _label(String text, Color color) => Text(
    text,
    style: InspectorTheme.monoSmall.copyWith(
      color: color,
      fontSize: 11,
      fontStyle: FontStyle.italic,
    ),
  );

  static final _fieldStyle = InspectorTheme.monoSmall.copyWith(
    color: InspectorTheme.text.withValues(alpha: 0.9),
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );
}
