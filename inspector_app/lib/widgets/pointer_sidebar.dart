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
            Expanded(child: _groupedList()),
            _sidebarActions(),
          ],
        ],
      ),
    );
  }

  // ─── Connection panel ───
  Widget _connectionPanel() {
    final uriController = TextEditingController(
      text: 'ws://127.0.0.1:8181/ws',
    );
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Icon(Icons.memory, size: 40, color: InspectorTheme.accent.withValues(alpha: 0.4)),
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

  // ─── Search bar ───
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

  // ─── Grouped list ───
  Widget _groupedList() {
    final groups = <PointerCategory, List<(int, PointerData)>>{};
    for (int i = 0; i < widget.pointers.length; i++) {
      final p = widget.pointers[i];
      if (_filter.isNotEmpty &&
          !p.variableName.toLowerCase().contains(_filter) &&
          !p.nativeType.toLowerCase().contains(_filter)) {
        continue;
      }
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
            _section(cat, groups[cat]!),
      ],
    );
  }

  Widget _section(PointerCategory cat, List<(int, PointerData)> items) {
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
          for (final (index, p) in items) _pointerItem(index, p),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _pointerItem(int index, PointerData p) {
    final selected = index == widget.selectedIndex;
    final dotColor = p.hasError
        ? InspectorTheme.error
        : p.hasRawBytes
            ? InspectorTheme.success
            : InspectorTheme.textDim;

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
              ? Border.all(
                  color: InspectorTheme.accent.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
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
          ],
        ),
      ),
    );
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
                label: Text('Rescan', style: InspectorTheme.monoSmall.copyWith(fontSize: 10)),
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: TextButton.icon(
              onPressed: widget.onDisconnect,
              icon: const Icon(Icons.power_off, size: 12,
                  color: InspectorTheme.error),
              label: Text('Disconnect',
                  style: InspectorTheme.monoSmall
                      .copyWith(fontSize: 10, color: InspectorTheme.error)),
            ),
          ),
        ],
      ),
    );
  }
}
