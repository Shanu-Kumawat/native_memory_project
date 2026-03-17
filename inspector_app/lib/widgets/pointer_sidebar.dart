// Pointer sidebar — grouped list of scanned pointers with search/filter.

import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../theme.dart';

class PointerSidebar extends StatefulWidget {
  const PointerSidebar({
    super.key,
    required this.pointers,
    required this.selectedIndex,
    required this.onSelect,
    required this.isConnected,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRescan,
    this.isConnecting = false,
    this.errorMessage,
  });

  final List<PointerData> pointers;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool isConnected;
  final ValueChanged<String> onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onRescan;
  final bool isConnecting;
  final String? errorMessage;

  @override
  State<PointerSidebar> createState() => _PointerSidebarState();
}

class _PointerSidebarState extends State<PointerSidebar> {
  final _searchController = TextEditingController();
  String _filter = '';
  final _collapsed = <PointerCategory, bool>{};
  _RelationFilter _relationFilter = _RelationFilter.all;
  bool _groupByGraph = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: InspectorTheme.surface,
      child: Column(
        children: [
          if (!widget.isConnected) ...[
            _connectionPanel(),
          ] else ...[
            _searchBar(),
            _relationControls(),
            Expanded(child: _groupedList()),
            _sidebarActions(),
          ],
        ],
      ),
    );
  }

  Widget _connectionPanel() {
    final uriController = TextEditingController(text: 'ws://127.0.0.1:8181/ws');
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Icon(
              Icons.memory,
              size: 40,
              color: InspectorTheme.accent.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text('Connect to VM', style: InspectorTheme.heading),
            const SizedBox(height: 4),
            Text(
              'Enter the WebSocket URI of a Dart VM running with --enable-vm-service',
              style: InspectorTheme.label,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: uriController,
              style: InspectorTheme.monoSmall,
              decoration: const InputDecoration(
                hintText: 'ws://127.0.0.1:8181/ws',
                prefixIcon: Icon(Icons.link, size: 16),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.isConnecting
                    ? null
                    : () => widget.onConnect(uriController.text.trim()),
                child: widget.isConnecting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect'),
              ),
            ),
            if (widget.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: InspectorTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: InspectorTheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  widget.errorMessage!,
                  style: InspectorTheme.monoSmall.copyWith(
                    color: InspectorTheme.error,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: SizedBox(
        height: 32,
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _filter = v.toLowerCase()),
          style: InspectorTheme.monoSmall.copyWith(fontSize: 11),
          decoration: InputDecoration(
            hintText: 'Filter pointers...',
            hintStyle: InspectorTheme.monoSmall.copyWith(fontSize: 11),
            prefixIcon: const Icon(Icons.search, size: 14),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
        ),
      ),
    );
  }

  Widget _relationControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final value in _RelationFilter.values)
                ChoiceChip(
                  label: Text(
                    value.label,
                    style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
                  ),
                  selected: _relationFilter == value,
                  onSelected: (_) => setState(() => _relationFilter = value),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                height: 22,
                child: Checkbox(
                  value: _groupByGraph,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => setState(() => _groupByGraph = v ?? true),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Group by object graph',
                style: InspectorTheme.label.copyWith(fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupedList() {
    final relation = _buildRelationView(widget.pointers);
    final visible = <int>[];
    for (int i = 0; i < widget.pointers.length; i++) {
      final p = widget.pointers[i];
      if (_filter.isNotEmpty &&
          !p.variableName.toLowerCase().contains(_filter) &&
          !p.nativeType.toLowerCase().contains(_filter)) {
        continue;
      }
      if (!_passesRelationFilter(i, relation)) {
        continue;
      }
      visible.add(i);
    }

    if (visible.isEmpty) {
      return Center(
        child: Text(
          'No pointers match current filters',
          style: InspectorTheme.label.copyWith(fontSize: 11),
        ),
      );
    }

    if (_groupByGraph) {
      final byComponent = <int, List<int>>{};
      for (final idx in visible) {
        final component = relation.componentByIndex[idx] ?? idx;
        byComponent.putIfAbsent(component, () => <int>[]).add(idx);
      }
      final keys = byComponent.keys.toList()..sort();
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (int section = 0; section < keys.length; section++)
            _graphSection(
              section + 1,
              byComponent[keys[section]]!..sort((a, b) => a.compareTo(b)),
              relation,
            ),
        ],
      );
    }

    final groups = <PointerCategory, List<(int, PointerData)>>{};
    for (final i in visible) {
      final p = widget.pointers[i];
      groups.putIfAbsent(p.category, () => []).add((i, p));
    }

    const order = [
      PointerCategory.struct,
      PointerCategory.union,
      PointerCategory.advanced,
      PointerCategory.raw,
      PointerCategory.error,
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final cat in order)
          if (groups.containsKey(cat))
            _section(cat, groups[cat]!, relation),
      ],
    );
  }

  Widget _graphSection(
    int graphNumber,
    List<int> indices,
    _RelationView relation,
  ) {
    final label = 'Object Graph #$graphNumber';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              const Icon(
                Icons.account_tree_outlined,
                size: 14,
                color: InspectorTheme.textDim,
              ),
              const SizedBox(width: 6),
              Text(label, style: InspectorTheme.label.copyWith(fontSize: 10)),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: InspectorTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${indices.length}',
                  style: InspectorTheme.monoSmall.copyWith(fontSize: 9),
                ),
              ),
            ],
          ),
        ),
        for (final index in indices)
          _pointerItem(index, widget.pointers[index], relation),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _section(
    PointerCategory cat,
    List<(int, PointerData)> items,
    _RelationView relation,
  ) {
    final label = switch (cat) {
      PointerCategory.struct => 'Structs',
      PointerCategory.union => 'Unions',
      PointerCategory.advanced => 'Advanced',
      PointerCategory.raw => 'Raw / Unknown',
      PointerCategory.error => 'Errors',
    };
    final collapsed = _collapsed[cat] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _collapsed[cat] = !collapsed),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 14,
                  color: InspectorTheme.textDim,
                ),
                const SizedBox(width: 4),
                Text(label, style: InspectorTheme.label.copyWith(fontSize: 10)),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: InspectorTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${items.length}',
                    style: InspectorTheme.monoSmall.copyWith(fontSize: 9),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!collapsed)
          for (final (index, p) in items) _pointerItem(index, p, relation),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _pointerItem(int index, PointerData p, _RelationView relation) {
    final selected = index == widget.selectedIndex;
    final dotColor = p.hasError
        ? InspectorTheme.error
        : p.hasRawBytes
        ? InspectorTheme.success
        : InspectorTheme.textDim;
    final inCount = relation.inCount[index] ?? 0;
    final outCount = relation.outCount[index] ?? 0;
    final cyclic = relation.cyclic.contains(index);

    return InkWell(
      onTap: () => widget.onSelect(index),
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? InspectorTheme.accent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(color: InspectorTheme.accent.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                p.variableName,
                style: InspectorTheme.monoSmall.copyWith(
                  color: selected ? InspectorTheme.accent : InspectorTheme.text,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: InspectorTheme.surfaceLight,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                p.nativeType == 'Unknown' ? '?' : p.nativeType,
                style: InspectorTheme.monoSmall.copyWith(fontSize: 9),
              ),
            ),
            const SizedBox(width: 4),
            _miniBadge('out:$outCount', InspectorTheme.accent),
            const SizedBox(width: 3),
            _miniBadge('in:$inCount', InspectorTheme.textDim),
            if (cyclic) ...[
              const SizedBox(width: 3),
              _miniBadge('cyc', InspectorTheme.warning),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: InspectorTheme.monoSmall.copyWith(
          fontSize: 8.5,
          color: color,
        ),
      ),
    );
  }

  bool _passesRelationFilter(int index, _RelationView relation) {
    final inCount = relation.inCount[index] ?? 0;
    return switch (_relationFilter) {
      _RelationFilter.all => true,
      _RelationFilter.roots => inCount == 0,
      _RelationFilter.referenced => inCount > 0,
      _RelationFilter.cyclic => relation.cyclic.contains(index),
    };
  }

  _RelationView _buildRelationView(List<PointerData> pointers) {
    final byAddress = <int, List<int>>{};
    for (int i = 0; i < pointers.length; i++) {
      byAddress.putIfAbsent(pointers[i].address, () => <int>[]).add(i);
    }

    final outNeighbors = <int, Set<int>>{};
    final inCount = <int, int>{for (int i = 0; i < pointers.length; i++) i: 0};

    for (int i = 0; i < pointers.length; i++) {
      final p = pointers[i];
      final neighbors = <int>{};
      if (p.rawBytes != null) {
        for (final field in p.fields) {
          if (!field.isPointer || field.isPadding) continue;
          final addr = _decodePointerAddressFromField(field, p.rawBytes!);
          if (addr == null || addr == 0) continue;
          final targets = byAddress[addr];
          if (targets == null) continue;
          for (final t in targets) {
            neighbors.add(t);
          }
        }
      }
      outNeighbors[i] = neighbors;
      for (final t in neighbors) {
        inCount[t] = (inCount[t] ?? 0) + 1;
      }
    }

    final outCount = <int, int>{
      for (int i = 0; i < pointers.length; i++) i: outNeighbors[i]!.length,
    };
    final cyclic = _findCyclicNodes(outNeighbors, pointers.length);
    final componentByIndex = _connectedComponents(outNeighbors, pointers.length);
    return _RelationView(
      inCount: inCount,
      outCount: outCount,
      cyclic: cyclic,
      componentByIndex: componentByIndex,
    );
  }

  int? _decodePointerAddressFromField(StructField field, List<int> bytes) {
    if (field.offset < 0 || field.size <= 0) return null;
    final end = field.offset + field.size;
    if (end > bytes.length) return null;
    int value = 0;
    for (int i = field.size - 1; i >= 0; i--) {
      value = (value << 8) | bytes[field.offset + i];
    }
    return value;
  }

  Set<int> _findCyclicNodes(Map<int, Set<int>> outNeighbors, int count) {
    final onStack = <int>{};
    final visited = <int>{};
    final cyclic = <int>{};

    void dfs(int node, List<int> path) {
      visited.add(node);
      onStack.add(node);
      path.add(node);
      for (final next in outNeighbors[node] ?? const <int>{}) {
        if (!visited.contains(next)) {
          dfs(next, path);
          continue;
        }
        if (onStack.contains(next)) {
          final start = path.indexOf(next);
          if (start >= 0) {
            for (int i = start; i < path.length; i++) {
              cyclic.add(path[i]);
            }
          }
        }
      }
      onStack.remove(node);
      path.removeLast();
    }

    for (int i = 0; i < count; i++) {
      if (!visited.contains(i)) dfs(i, <int>[]);
    }
    return cyclic;
  }

  Map<int, int> _connectedComponents(Map<int, Set<int>> outNeighbors, int count) {
    final undirected = <int, Set<int>>{
      for (int i = 0; i < count; i++) i: <int>{},
    };
    for (int i = 0; i < count; i++) {
      for (final n in outNeighbors[i] ?? const <int>{}) {
        undirected[i]!.add(n);
        undirected[n]!.add(i);
      }
    }

    final componentByIndex = <int, int>{};
    final visited = <int>{};
    int componentId = 0;

    for (int i = 0; i < count; i++) {
      if (visited.contains(i)) continue;
      componentId++;
      final stack = <int>[i];
      visited.add(i);
      while (stack.isNotEmpty) {
        final node = stack.removeLast();
        componentByIndex[node] = componentId;
        for (final next in undirected[node] ?? const <int>{}) {
          if (visited.add(next)) stack.add(next);
        }
      }
    }
    return componentByIndex;
  }

  Widget _sidebarActions() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: InspectorTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextButton.icon(
                onPressed: widget.onRescan,
                icon: const Icon(Icons.refresh, size: 12),
                label: Text(
                  'Rescan',
                  style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: TextButton.icon(
              onPressed: widget.onDisconnect,
              icon: const Icon(
                Icons.power_off,
                size: 12,
                color: InspectorTheme.error,
              ),
              label: Text(
                'Disconnect',
                style: InspectorTheme.monoSmall.copyWith(
                  fontSize: 10,
                  color: InspectorTheme.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RelationFilter { all, roots, referenced, cyclic }

extension on _RelationFilter {
  String get label => switch (this) {
    _RelationFilter.all => 'All',
    _RelationFilter.roots => 'Roots',
    _RelationFilter.referenced => 'Referenced',
    _RelationFilter.cyclic => 'Cyclic',
  };
}

class _RelationView {
  const _RelationView({
    required this.inCount,
    required this.outCount,
    required this.cyclic,
    required this.componentByIndex,
  });

  final Map<int, int> inCount;
  final Map<int, int> outCount;
  final Set<int> cyclic;
  final Map<int, int> componentByIndex;
}
