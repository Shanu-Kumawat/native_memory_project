// Detail panel — shows selected pointer's fields, hex dump, layout, and graph.
// Split view: fields on top, hex dump below. Layout diagram and object graph
// are collapsible sections.

import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../models/selection_notifier.dart';
import '../theme.dart';
import 'byte_interpretation.dart';
import 'field_tree.dart';
import 'hex_dump.dart';
import 'layout_diagram.dart';
import 'object_graph.dart';

class DetailPanel extends StatefulWidget {
  const DetailPanel({
    super.key,
    required this.pointer,
    required this.allPointers,
    required this.onNavigate,
    this.canGoBack = false,
    this.onGoBack,
  });

  final PointerData pointer;
  final List<PointerData> allPointers;
  final ValueChanged<int> onNavigate;
  final bool canGoBack;
  final VoidCallback? onGoBack;

  @override
  State<DetailPanel> createState() => _DetailPanelState();
}

class _DetailPanelState extends State<DetailPanel> {
  final SelectionNotifier _selectionNotifier = SelectionNotifier();
  bool _layoutExpanded = false;

  @override
  void dispose() {
    _selectionNotifier.dispose();
    super.dispose();
  }

  /// Navigate to a pointer by its address.
  void _navigateToAddress(int address) {
    final idx =
        widget.allPointers.indexWhere((p) => p.address == address);
    if (idx >= 0) {
      widget.onNavigate(idx);
    }
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
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ─── Fields view ───
                FieldTreeView(
                  fields: d.fields,
                  rawBytes: d.rawBytes,
                  selectionNotifier: _selectionNotifier,
                  onPointerTap: _navigateToAddress,
                ),
                // ─── Hex dump view ───
                if (d.hasRawBytes) ...[
                  const Divider(color: InspectorTheme.border, height: 1),
                  HexDumpView(
                    bytes: d.rawBytes ?? [],
                    baseAddress: d.address,
                    selectionNotifier: _selectionNotifier,
                    fields: d.fields,
                  ),
                ],
                // ─── Byte interpretation panel ───
                if (d.hasRawBytes)
                  ByteInterpretationPanel(
                    selectionNotifier: _selectionNotifier,
                    rawBytes: d.rawBytes,
                  ),
                // ─── Layout diagram (collapsible) ───
                if (d.hasFields) ...[
                  _collapsibleHeader(
                    'Layout Diagram',
                    Icons.straighten,
                    _layoutExpanded,
                    () => setState(() =>
                        _layoutExpanded = !_layoutExpanded),
                  ),
                  if (_layoutExpanded)
                    LayoutDiagram(
                      fields: d.fields,
                      totalSize: d.structSize,
                      selectionNotifier: _selectionNotifier,
                    ),
                ],
                // ─── Object graph (auto-shows for pointer-containing structs) ───
                if (d.hasPointerFields)
                  ObjectGraph(
                    rootPointer: d,
                    allPointers: widget.allPointers,
                    onNavigate: widget.onNavigate,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Header ───
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
                child: const Icon(Icons.arrow_back,
                    size: 16, color: InspectorTheme.textDim),
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
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Text('→',
              style: InspectorTheme.mono
                  .copyWith(color: InspectorTheme.textDim, fontSize: 12)),
          const SizedBox(width: 8),
          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: InspectorTheme.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: InspectorTheme.purple.withValues(alpha: 0.25)),
            ),
            child: Text(
              'Pointer<${d.nativeType}>',
              style: InspectorTheme.monoSmall.copyWith(
                color: InspectorTheme.purple,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Address
          Text(
            d.addressHex,
            style: InspectorTheme.monoSmall.copyWith(fontSize: 11),
          ),
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
              style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
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
              style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _collapsibleHeader(
    String label,
    IconData icon,
    bool expanded,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: InspectorTheme.border)),
        ),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: 14,
              color: InspectorTheme.textDim,
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 12, color: InspectorTheme.textDim),
            const SizedBox(width: 6),
            Text(label,
                style: InspectorTheme.label.copyWith(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ─── Error view ───
  Widget _errorView(PointerData d) {
    return Column(
      children: [
        _header(d),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 36,
                    color: InspectorTheme.error.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(d.error ?? 'Unknown error',
                    style: InspectorTheme.mono.copyWith(
                        color: InspectorTheme.error, fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  'Address: ${d.addressHex}',
                  style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
