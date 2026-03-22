// Detail panel — shows selected pointer's fields, hex dump, layout, and graph.
// Split view: fields on top, hex dump below. Layout diagram always visible.
// Byte interpretation panel pinned to bottom (only appears on selection).

import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../models/selection_notifier.dart';
import '../theme.dart';
import 'byte_interpretation.dart';
import 'context_panel.dart';
import 'field_tree.dart';
import 'hex_dump.dart';
import 'layout_diagram.dart';
import 'object_graph.dart';

class DetailPanel extends StatefulWidget {
  const DetailPanel({
    super.key,
    required this.pointer,
    required this.allPointers,
    required this.snapshotHistory,
    required this.onNavigate,
    this.canGoBack = false,
    this.onGoBack,
    this.canLoadMore = false,
    this.onLoadMore,
  });

  final PointerData pointer;
  final List<PointerData> allPointers;
  final List<MemorySnapshot> snapshotHistory;
  final ValueChanged<int> onNavigate;
  final bool canGoBack;
  final VoidCallback? onGoBack;
  final bool canLoadMore;
  final VoidCallback? onLoadMore;

  @override
  State<DetailPanel> createState() => _DetailPanelState();
}

class _DetailPanelState extends State<DetailPanel> {
  final SelectionNotifier _selectionNotifier = SelectionNotifier();

  @override
  void dispose() {
    _selectionNotifier.dispose();
    super.dispose();
  }

  void _navigateToAddress(int address) {
    final idx = widget.allPointers.indexWhere((p) => p.address == address);
    if (idx >= 0) widget.onNavigate(idx);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.pointer;

    if (d.hasError && !d.hasRawBytes) {
      return _errorView(d);
    }

    return Column(
      children: [
        _header(d),
        // ── Scrollable content ──
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fields view
                FieldTreeView(
                  fields: d.fields,
                  rawBytes: d.rawBytes,
                  selectionNotifier: _selectionNotifier,
                  onPointerTap: _navigateToAddress,
                ),
                // Layout diagram — always visible
                if (d.hasFields)
                  LayoutDiagram(
                    fields: d.fields,
                    totalSize: d.structSize,
                    selectionNotifier: _selectionNotifier,
                  ),
                // Hex dump view
                if (d.hasRawBytes) ...[
                  const Divider(color: InspectorTheme.border, height: 1),
                  HexDumpView(
                    bytes: d.rawBytes ?? [],
                    baseAddress: d.address,
                    selectionNotifier: _selectionNotifier,
                    fields: d.fields,
                    hasMore: widget.canLoadMore,
                    onLoadMore: widget.canLoadMore ? widget.onLoadMore : null,
                  ),
                ],
                // Object graph + Context panel (side by side)
                if (d.hasInterestingStructure)
                  SizedBox(
                    height: 350,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ObjectGraph(
                            rootPointer: d,
                            allPointers: widget.allPointers,
                            onNavigate: widget.onNavigate,
                            selectionNotifier: _selectionNotifier,
                          ),
                        ),
                        SizedBox(
                          width: 280,
                          child: ContextPanel(
                            pointer: d,
                            allPointers: widget.allPointers,
                            snapshotHistory: widget.snapshotHistory,
                            onNavigate: widget.onNavigate,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: 250,
                    child: ContextPanel(
                      pointer: d,
                      allPointers: widget.allPointers,
                      snapshotHistory: widget.snapshotHistory,
                      onNavigate: widget.onNavigate,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // ── Byte interpretation — pinned to bottom ──
        if (d.hasRawBytes)
          ByteInterpretationPanel(
            selectionNotifier: _selectionNotifier,
            rawBytes: d.rawBytes,
          ),
      ],
    );
  }

  Widget _header(PointerData d) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: InspectorTheme.surface,
        border: Border(bottom: BorderSide(color: InspectorTheme.border)),
      ),
      child: Row(
        children: [
          // Back button
          if (widget.canGoBack) ...[
            InkWell(
              onTap: widget.onGoBack,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  Icons.arrow_back,
                  size: 16,
                  color: InspectorTheme.textDim,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Name
          Text(
            d.variableName,
            style: InspectorTheme.mono.copyWith(
              color: InspectorTheme.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '→',
            style: InspectorTheme.mono.copyWith(
              color: InspectorTheme.textDim,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: InspectorTheme.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: InspectorTheme.purple.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              'Pointer<${d.nativeType}>',
              style: InspectorTheme.monoSmall.copyWith(
                color: InspectorTheme.purple,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Address
          Text(d.addressHex, style: InspectorTheme.monoSmall),
          const Spacer(),
          // Size badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: InspectorTheme.surfaceLight,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${d.structSize}B',
              style: InspectorTheme.monoSmall.copyWith(fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          // Field count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: InspectorTheme.surfaceLight,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${d.fields.where((f) => !f.isPadding).length} fields',
              style: InspectorTheme.monoSmall.copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(PointerData d) {
    return Column(
      children: [
        _header(d),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 36,
                  color: InspectorTheme.error.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  d.error ?? 'Unknown error',
                  style: InspectorTheme.mono.copyWith(
                    color: InspectorTheme.error,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Address: ${d.addressHex}',
                  style: InspectorTheme.monoSmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
