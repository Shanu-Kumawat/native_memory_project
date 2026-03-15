/// Pointer inspection card — the main composite widget for displaying
/// a single Pointer<T> with its fields, raw memory, and layout info.

import 'package:flutter/material.dart';

import '../models/pointer_data.dart';
import '../theme.dart';
import 'field_tree.dart';
import 'hex_dump.dart';

class PointerCard extends StatefulWidget {
  const PointerCard({
    super.key,
    required this.data,
    this.initiallyExpanded = false,
  });

  final PointerData data;
  final bool initiallyExpanded;

  @override
  State<PointerCard> createState() => _PointerCardState();
}

class _PointerCardState extends State<PointerCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  int _tabIndex = 0; // 0 = fields, 1 = hex dump, 2 = layout

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(d),
          if (_expanded && !d.hasError) ...[
            _tabBar(),
            _tabContent(d),
          ],
          if (_expanded && d.hasError) _errorContent(d),
        ],
      ),
    );
  }

  Widget _header(PointerData d) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Expand/collapse icon
            AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.chevron_right,
                color: InspectorTheme.textDim,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            // Status icon
            _statusIcon(d),
            const SizedBox(width: 10),
            // Variable name
            Text(
              d.variableName,
              style: InspectorTheme.mono.copyWith(
                color: InspectorTheme.accent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            // Arrow
            Text(
              '→',
              style: InspectorTheme.mono.copyWith(
                color: InspectorTheme.textDim,
              ),
            ),
            const SizedBox(width: 8),
            // Type
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: InspectorTheme.purple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: InspectorTheme.purple.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                'Pointer<${d.nativeType}>',
                style: InspectorTheme.mono.copyWith(
                  color: InspectorTheme.purple,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Address
            Text(
              '@ ${d.addressHex}',
              style: InspectorTheme.monoSmall.copyWith(
                color: d.isNull ? InspectorTheme.error : InspectorTheme.textDim,
              ),
            ),
            const Spacer(),
            // Size badge
            if (!d.hasError)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: InspectorTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${d.structSize}B',
                  style: InspectorTheme.monoSmall.copyWith(fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(PointerData d) {
    if (d.hasError || d.isNull) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: InspectorTheme.error,
          boxShadow: [
            BoxShadow(
              color: InspectorTheme.error.withValues(alpha: 0.4),
              blurRadius: 6,
            ),
          ],
        ),
      );
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: InspectorTheme.success,
        boxShadow: [
          BoxShadow(
            color: InspectorTheme.success.withValues(alpha: 0.4),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: InspectorTheme.border),
        ),
      ),
      child: Row(
        children: [
          _tab('Fields', 0, Icons.account_tree_outlined),
          _tab('Hex Dump', 1, Icons.grid_on),
          _tab('Layout', 2, Icons.straighten),
        ],
      ),
    );
  }

  Widget _tab(String label, int index, IconData icon) {
    final selected = _tabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? InspectorTheme.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected
                    ? InspectorTheme.accent
                    : InspectorTheme.textDim,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: InspectorTheme.label.copyWith(
                  color: selected
                      ? InspectorTheme.accent
                      : InspectorTheme.textDim,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabContent(PointerData d) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (_tabIndex) {
        0 => FieldTreeView(key: const ValueKey('fields'), fields: d.fields, rawBytes: d.rawBytes),
        1 => HexDumpView(
            key: const ValueKey('hex'),
            bytes: d.rawBytes ?? [],
            baseAddress: d.address,
            highlightRanges: d.fields
                .map(
                  (f) => (
                    offset: f.offset,
                    length: f.size,
                    color: InspectorTheme.typeColor(f.typeName),
                  ),
                )
                .toList(),
          ),
        2 => _layoutInfo(d),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _layoutInfo(PointerData d) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('Struct Type', d.nativeType),
          _infoRow('Total Size', '${d.structSize} bytes'),
          _infoRow('Field Count', '${d.fields.length}'),
          _infoRow('Base Address', d.addressHex),
          const SizedBox(height: 12),
          Text('Memory Layout', style: InspectorTheme.label),
          const SizedBox(height: 8),
          _layoutDiagram(d),
        ],
      ),
    );
  }

  Widget _layoutDiagram(PointerData d) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: InspectorTheme.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: InspectorTheme.border),
      ),
      child: Row(
        children: [
          for (final field in d.fields)
            Expanded(
              flex: field.size,
              child: Tooltip(
                message: '${field.name}: ${field.typeName} (${field.size}B)',
                child: Container(
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: InspectorTheme.typeColor(field.typeName)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: InspectorTheme.typeColor(field.typeName)
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    field.name,
                    style: InspectorTheme.monoSmall.copyWith(
                      color: InspectorTheme.typeColor(field.typeName),
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: InspectorTheme.label),
          ),
          Text(value, style: InspectorTheme.mono),
        ],
      ),
    );
  }

  Widget _errorContent(PointerData d) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: InspectorTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: InspectorTheme.error, size: 18),
          const SizedBox(width: 10),
          Text(
            d.error!,
            style: InspectorTheme.mono.copyWith(
              color: InspectorTheme.error,
            ),
          ),
        ],
      ),
    );
  }
}
