// FFI Context Panel — tabbed diagnostic panel with Memory Diff and Inbound References.
// Sits alongside the Object Graph in the detail panel's bottom section.

import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../theme.dart';

class ContextPanel extends StatefulWidget {
  const ContextPanel({
    super.key,
    required this.pointer,
    required this.allPointers,
    required this.snapshotHistory,
    required this.onNavigate,
  });

  final PointerData pointer;
  final List<PointerData> allPointers;
  final List<MemorySnapshot> snapshotHistory;
  final ValueChanged<int> onNavigate;

  @override
  State<ContextPanel> createState() => _ContextPanelState();
}

class _ContextPanelState extends State<ContextPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: InspectorTheme.border),
          left: BorderSide(color: InspectorTheme.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Tab bar ──
          Container(
            decoration: const BoxDecoration(
              color: InspectorTheme.surface,
              border: Border(bottom: BorderSide(color: InspectorTheme.border)),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: InspectorTheme.accent,
              indicatorWeight: 2,
              labelColor: InspectorTheme.accent,
              unselectedLabelColor: InspectorTheme.textDim,
              labelStyle: InspectorTheme.monoSmall.copyWith(fontSize: 11),
              unselectedLabelStyle: InspectorTheme.monoSmall.copyWith(
                fontSize: 11,
              ),
              dividerColor: Colors.transparent,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: const [
                Tab(height: 30, text: 'Δ Changes'),
                Tab(height: 30, text: '← Refs'),
              ],
            ),
          ),
          // ── Tab content ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildChangesTab(), _buildRefsTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // Tab 1: Δ Changes — Value Chain timeline
  // ════════════════════════════════════════════════════════════════

  Widget _buildChangesTab() {
    final history = widget.snapshotHistory;

    if (history.isEmpty) {
      return _emptyMessage(
        Icons.history,
        'No previous scan',
        'Rescan to capture a snapshot for comparison.',
      );
    }

    final isRaw = widget.pointer.category == PointerCategory.raw;

    if (isRaw) {
      return _buildRawByteDiff(history);
    }

    // Build value chains for every field
    final chains = _buildValueChains();

    if (chains.isEmpty) {
      return _emptyMessage(
        Icons.check_circle_outline,
        'No changes detected',
        'All field values are identical across ${history.length + 1} scans.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: chains.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _badge(
                  '${chains.length} field${chains.length == 1 ? '' : 's'} changed',
                  InspectorTheme.warning,
                ),
                const SizedBox(width: 6),
                _badge('${history.length + 1} scans', InspectorTheme.textDim),
              ],
            ),
          );
        }
        return _chainRow(chains[index - 1]);
      },
    );
  }

  /// Raw byte diff for pointers without struct fields (Uint8, Void, etc.)
  Widget _buildRawByteDiff(List<MemorySnapshot> history) {
    final current = widget.pointer;
    final currentBytes = current.rawBytes;

    if (currentBytes == null || currentBytes.isEmpty) {
      return _emptyMessage(
        Icons.memory,
        'No bytes loaded',
        'Raw bytes are not available for comparison.',
      );
    }

    // Compare current bytes against each snapshot
    final entries = <Widget>[];
    bool anyChanges = false;

    for (int i = 0; i < history.length; i++) {
      final snapPointer = history[i].pointers
          .where((p) => p.address == current.address)
          .firstOrNull;

      if (snapPointer == null || snapPointer.rawBytes == null) continue;

      final prevBytes = snapPointer.rawBytes!;
      final compareLen = currentBytes.length < prevBytes.length
          ? currentBytes.length
          : prevBytes.length;

      // Find changed byte offsets
      final changedOffsets = <int>[];
      for (int j = 0; j < compareLen; j++) {
        if (currentBytes[j] != prevBytes[j]) changedOffsets.add(j);
      }

      // Also count size difference as a change
      final sizeDiff = currentBytes.length - prevBytes.length;

      if (changedOffsets.isEmpty && sizeDiff == 0) continue;
      anyChanges = true;

      entries.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: InspectorTheme.warning.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: InspectorTheme.warning.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: scan # → current
                Row(
                  children: [
                    _badge('Scan #${i + 1} → Now', InspectorTheme.warning),
                    const Spacer(),
                    Text(
                      '${changedOffsets.length} of $compareLen bytes changed',
                      style: InspectorTheme.monoSmall.copyWith(
                        fontSize: 10,
                        color: InspectorTheme.warning,
                      ),
                    ),
                  ],
                ),
                if (sizeDiff != 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Size: ${prevBytes.length}B → ${currentBytes.length}B'
                    ' (${sizeDiff > 0 ? '+' : ''}$sizeDiff)',
                    style: InspectorTheme.monoSmall.copyWith(
                      fontSize: 10,
                      color: InspectorTheme.textDim,
                    ),
                  ),
                ],
                if (changedOffsets.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  // Show first 8 changed offsets with old → new values
                  ...changedOffsets.take(8).map((off) {
                    final oldHex = prevBytes[off]
                        .toRadixString(16)
                        .padLeft(2, '0')
                        .toUpperCase();
                    final newHex = currentBytes[off]
                        .toRadixString(16)
                        .padLeft(2, '0')
                        .toUpperCase();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 50,
                            child: Text(
                              '+0x${off.toRadixString(16).padLeft(2, '0')}',
                              style: InspectorTheme.monoSmall.copyWith(
                                fontSize: 10,
                                color: InspectorTheme.textDim,
                              ),
                            ),
                          ),
                          Text(
                            oldHex,
                            style: InspectorTheme.monoSmall.copyWith(
                              fontSize: 10,
                              color: InspectorTheme.error.withValues(
                                alpha: 0.7,
                              ),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Text(
                              '→',
                              style: InspectorTheme.monoSmall.copyWith(
                                fontSize: 12,
                                color: InspectorTheme.warning,
                              ),
                            ),
                          ),
                          Text(
                            newHex,
                            style: InspectorTheme.monoSmall.copyWith(
                              fontSize: 10,
                              color: InspectorTheme.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (changedOffsets.length > 8)
                    Text(
                      '  +${changedOffsets.length - 8} more...',
                      style: InspectorTheme.monoSmall.copyWith(
                        fontSize: 10,
                        color: InspectorTheme.textDim,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (!anyChanges) {
      return _emptyMessage(
        Icons.check_circle_outline,
        'No byte changes',
        'Raw bytes are identical across all ${history.length + 1} scans.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              _badge('Raw byte diff', InspectorTheme.warning),
              const SizedBox(width: 6),
              _badge('${currentBytes.length}B loaded', InspectorTheme.textDim),
            ],
          ),
        ),
        ...entries,
      ],
    );
  }

  /// Build a value chain for each field across all snapshots + current.
  List<_ValueChain> _buildValueChains() {
    final history = widget.snapshotHistory;
    final currentPointer = widget.pointer;
    final chains = <_ValueChain>[];

    for (final field in currentPointer.fields) {
      if (field.isPadding) continue;

      final values = <_ChainEntry>[];
      bool anyChange = false;
      String? prevVal;

      // Walk through each snapshot
      for (int i = 0; i < history.length; i++) {
        final snapPointer = history[i].pointers
            .where((p) => p.address == currentPointer.address)
            .firstOrNull;

        // Skip snapshots where this pointer wasn't found
        if (snapPointer == null || snapPointer.rawBytes == null) continue;

        final val = _extractFieldValue(snapPointer, field);
        if (val == '—') continue; // Skip unreadable values

        final changed = prevVal != null && val != prevVal;
        if (changed) anyChange = true;
        values.add(_ChainEntry(value: val, changed: changed, scanIndex: i));
        prevVal = val;
      }

      // Current value (always the last entry)
      final currentVal = _extractFieldValue(currentPointer, field);
      if (currentVal != '—') {
        final currentChanged = prevVal != null && currentVal != prevVal;
        if (currentChanged) anyChange = true;
        values.add(
          _ChainEntry(
            value: currentVal,
            changed: currentChanged,
            scanIndex: history.length,
            isCurrent: true,
          ),
        );
      }

      if (anyChange && values.length >= 2) {
        chains.add(
          _ValueChain(
            fieldName: field.name,
            typeName: field.typeName,
            entries: values,
          ),
        );
      }
    }

    return chains;
  }

  String _extractFieldValue(PointerData pointer, StructField field) {
    final bytes = pointer.rawBytes;
    if (bytes == null) return '—';

    final end = field.offset + field.size;
    if (end > bytes.length) return '—';

    final slice = bytes.sublist(field.offset, end);
    return _formatFieldValue(field, slice);
  }

  Widget _chainRow(_ValueChain chain) {
    final segments = <Widget>[];

    for (int i = 0; i < chain.entries.length; i++) {
      final e = chain.entries[i];

      // Arrow between values
      if (i > 0) {
        segments.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '→',
              style: InspectorTheme.monoSmall.copyWith(
                fontSize: 13,
                color: e.changed
                    ? InspectorTheme.warning
                    : InspectorTheme.textDim.withValues(alpha: 0.4),
              ),
            ),
          ),
        );
      }

      // Value chip
      segments.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: e.isCurrent
                ? InspectorTheme.success.withValues(alpha: 0.12)
                : e.changed
                ? InspectorTheme.warning.withValues(alpha: 0.08)
                : InspectorTheme.surfaceLight.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
            border: e.isCurrent
                ? Border.all(
                    color: InspectorTheme.success.withValues(alpha: 0.3),
                  )
                : null,
          ),
          child: Text(
            e.value,
            style: InspectorTheme.monoSmall.copyWith(
              fontSize: 11,
              color: e.isCurrent
                  ? InspectorTheme.success
                  : e.changed
                  ? InspectorTheme.warning
                  : InspectorTheme.text.withValues(alpha: 0.5),
              fontWeight: e.isCurrent ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: InspectorTheme.surfaceLight.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: InspectorTheme.border.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Field name + type
            Row(
              children: [
                Text(
                  chain.fieldName,
                  style: InspectorTheme.monoSmall.copyWith(
                    fontSize: 11,
                    color: InspectorTheme.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${chain.typeName})',
                  style: InspectorTheme.monoSmall.copyWith(
                    fontSize: 9,
                    color: InspectorTheme.textDim,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Value chain
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: segments),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFieldValue(StructField field, List<int> bytes) {
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    final len = bytes.length;

    if (field.isPointer && len >= 8) {
      final addr = bd.getUint64(0, Endian.little);
      return addr == 0 ? 'null' : '0x${addr.toRadixString(16)}';
    }

    return switch (field.typeName) {
      'Int8' when len >= 1 => bd.getInt8(0).toString(),
      'Uint8' when len >= 1 => bd.getUint8(0).toString(),
      'Int16' when len >= 2 => bd.getInt16(0, Endian.little).toString(),
      'Uint16' when len >= 2 => bd.getUint16(0, Endian.little).toString(),
      'Int32' when len >= 4 => bd.getInt32(0, Endian.little).toString(),
      'Uint32' when len >= 4 =>
        '0x${bd.getUint32(0, Endian.little).toRadixString(16)}',
      'Int64' when len >= 8 => bd.getInt64(0, Endian.little).toString(),
      'Uint64' when len >= 8 =>
        '0x${bd.getUint64(0, Endian.little).toRadixString(16)}',
      'Float' when len >= 4 =>
        bd.getFloat32(0, Endian.little).toStringAsFixed(4),
      'Double' when len >= 8 =>
        bd.getFloat64(0, Endian.little).toStringAsFixed(6),
      _ =>
        bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' '),
    };
  }

  // ════════════════════════════════════════════════════════════════
  // Tab 2: ← Refs (Inbound References)
  // ════════════════════════════════════════════════════════════════

  Widget _buildRefsTab() {
    final targetAddress = widget.pointer.address;
    final retainers = <_Retainer>[];

    for (int i = 0; i < widget.allPointers.length; i++) {
      final p = widget.allPointers[i];
      if (p.address == targetAddress) continue;
      if (!p.hasRawBytes) continue;

      for (final field in p.fields) {
        if (!field.isPointer) continue;
        final end = field.offset + field.size;
        if (end > p.rawBytes!.length) continue;

        final bytes = p.rawBytes!.sublist(field.offset, end);
        if (bytes.length < 8) continue;

        final bd = ByteData.sublistView(Uint8List.fromList(bytes));
        final addr = bd.getUint64(0, Endian.little);

        if (addr == targetAddress) {
          retainers.add(
            _Retainer(
              sourceIndex: i,
              sourceName: p.variableName,
              sourceType: p.nativeType,
              fieldName: field.name,
            ),
          );
        }
      }
    }

    if (retainers.isEmpty) {
      return _emptyMessage(
        Icons.link_off,
        'No inbound references',
        'No other scanned pointer currently points to this address.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: retainers.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _badge(
                  '${retainers.length} retainer${retainers.length == 1 ? '' : 's'}',
                  InspectorTheme.accent,
                ),
              ],
            ),
          );
        }
        return _retainerRow(retainers[index - 1]);
      },
    );
  }

  Widget _retainerRow(_Retainer r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onNavigate(r.sourceIndex),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: InspectorTheme.surfaceLight.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: InspectorTheme.border.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.call_received,
                  size: 12,
                  color: InspectorTheme.accent.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Text(
                  r.sourceName,
                  style: InspectorTheme.monoSmall.copyWith(
                    fontSize: 11,
                    color: InspectorTheme.success,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '.${r.fieldName}',
                  style: InspectorTheme.monoSmall.copyWith(
                    fontSize: 11,
                    color: InspectorTheme.text,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: InspectorTheme.background.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: InspectorTheme.border.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    r.sourceType,
                    style: InspectorTheme.monoSmall.copyWith(
                      fontSize: 9,
                      color: InspectorTheme.textDim,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: InspectorTheme.textDim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // Shared helpers
  // ════════════════════════════════════════════════════════════════

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: InspectorTheme.monoSmall.copyWith(fontSize: 10, color: color),
      ),
    );
  }

  Widget _emptyMessage(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 28,
              color: InspectorTheme.textDim.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: InspectorTheme.label.copyWith(
                fontSize: 12,
                color: InspectorTheme.textDim,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: InspectorTheme.monoSmall.copyWith(
                fontSize: 10,
                color: InspectorTheme.textDim.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data classes ──

class _ChainEntry {
  final String value;
  final bool changed;
  final int scanIndex;
  final bool isCurrent;

  const _ChainEntry({
    required this.value,
    required this.changed,
    required this.scanIndex,
    this.isCurrent = false,
  });
}

class _ValueChain {
  final String fieldName;
  final String typeName;
  final List<_ChainEntry> entries;

  const _ValueChain({
    required this.fieldName,
    required this.typeName,
    required this.entries,
  });
}

class _Retainer {
  final int sourceIndex;
  final String sourceName;
  final String sourceType;
  final String fieldName;

  const _Retainer({
    required this.sourceIndex,
    required this.sourceName,
    required this.sourceType,
    required this.fieldName,
  });
}
