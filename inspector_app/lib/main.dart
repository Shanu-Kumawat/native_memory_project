// Native Memory Inspector — GSoC Sample Project
//
// A Flutter desktop application that inspects Pointer<T> objects
// through the Dart VM Service Protocol.

import 'package:flutter/material.dart';

import 'models/pointer_data.dart' as models;
import 'services/vm_service_connection.dart';
import 'theme.dart';
import 'widgets/detail_panel.dart';
import 'widgets/pointer_sidebar.dart';
import 'widgets/status_bar.dart';

void main() {
  runApp(const NativeMemoryInspectorApp());
}

class NativeMemoryInspectorApp extends StatelessWidget {
  const NativeMemoryInspectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Memory Inspector',
      debugShowCheckedModeBanner: false,
      theme: InspectorTheme.themeData,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.15)),
          child: child!,
        );
      },
      home: const InspectorPage(),
    );
  }
}

class InspectorPage extends StatefulWidget {
  const InspectorPage({super.key});

  @override
  State<InspectorPage> createState() => _InspectorPageState();
}

class _InspectorPageState extends State<InspectorPage> {
  final _vmConnection = VmServiceConnection();
  var _state = const models.InspectorState();

  void _updateState(models.InspectorState Function(models.InspectorState) fn) {
    setState(() => _state = fn(_state));
  }

  Future<void> _connect(String uri) async {
    _updateState(
      (s) => s.copyWith(
        connectionState: models.ConnectionState.connecting,
        vmServiceUri: uri,
      ),
    );

    try {
      final info = await _vmConnection.connect(uri);
      _updateState(
        (s) => s.copyWith(
          connectionState: models.ConnectionState.connected,
          vmName: info.vmName,
          vmVersion: info.vmVersion,
        ),
      );
      await _scanForPointers();
    } catch (e) {
      _updateState(
        (s) => s.copyWith(
          connectionState: models.ConnectionState.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    await _vmConnection.disconnect();
    _updateState(
      (s) => s.copyWith(
        connectionState: models.ConnectionState.disconnected,
        pointers: [],
        selectedPointerIndex: -1,
        navigationHistory: [],
      ),
    );
  }

  Future<void> _scanForPointers() async {
    final pointers = await _vmConnection.findPointers();
    _updateState((s) {
      // Append current state as a snapshot (cap at 10)
      final history = List<models.MemorySnapshot>.from(s.snapshotHistory);
      if (s.pointers.isNotEmpty) {
        history.add(
          models.MemorySnapshot(
            pointers: s.pointers,
            timestamp: DateTime.now(),
          ),
        );
        if (history.length > 10) history.removeAt(0);
      }
      return s.copyWith(
        snapshotHistory: history,
        pointers: pointers,
        selectedPointerIndex: pointers.isNotEmpty ? 0 : -1,
      );
    });
  }

  Future<void> _resumeAndRescan() async {
    await _vmConnection.resumeTarget();
    // Brief delay to let the target app advance to next breakpoint
    await Future.delayed(const Duration(milliseconds: 500));
    await _scanForPointers();
  }

  Future<void> _loadMoreForSelectedPointer() async {
    final selectedIndex = _state.selectedPointerIndex;
    if (selectedIndex < 0 || selectedIndex >= _state.pointers.length) return;
    if (!_vmConnection.hasReadMemoryRpc) return;

    final pointer = _state.pointers[selectedIndex];
    if (pointer.address == 0) return;

    final currentLength = pointer.rawBytes?.length ?? 0;
    final nextLength = (currentLength + 64).clamp(64, 4096);
    final bytes = await _vmConnection.readNativeMemory(
      pointer.address,
      nextLength,
    );
    if (bytes == null) return;

    final updated = pointer.copyWith(
      rawBytes: bytes,
      structSize: pointer.structSize > bytes.length ? null : bytes.length,
      error: null,
    );

    final pointers = List<models.PointerData>.from(_state.pointers);
    pointers[selectedIndex] = updated;
    _updateState((s) => s.copyWith(pointers: pointers));
  }

  void _selectPointer(int index) {
    final history = List<int>.from(_state.navigationHistory);
    if (_state.selectedPointerIndex >= 0) {
      history.add(_state.selectedPointerIndex);
    }
    _updateState(
      (s) =>
          s.copyWith(selectedPointerIndex: index, navigationHistory: history),
    );
  }

  void _navigateBack() {
    if (!_state.canGoBack) return;
    final history = List<int>.from(_state.navigationHistory);
    final prev = history.removeLast();
    _updateState(
      (s) => s.copyWith(selectedPointerIndex: prev, navigationHistory: history),
    );
  }

  @override
  void dispose() {
    _vmConnection.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // ─── Sidebar ───
                SizedBox(
                  width: 360,
                  child: PointerSidebar(
                    pointers: _state.pointers,
                    selectedIndex: _state.selectedPointerIndex,
                    onSelect: _selectPointer,
                    isConnected:
                        _state.connectionState ==
                        models.ConnectionState.connected,
                    onConnect: _connect,
                    onDisconnect: _disconnect,
                    onRescan: _scanForPointers,
                    onResumeTarget: _resumeAndRescan,
                    isConnecting:
                        _state.connectionState ==
                        models.ConnectionState.connecting,
                    errorMessage:
                        _state.connectionState == models.ConnectionState.error
                        ? _state.errorMessage
                        : null,
                  ),
                ),
                // ─── Divider ───
                Container(width: 1, color: InspectorTheme.border),
                // ─── Detail panel ───
                Expanded(
                  child: _state.selectedPointer != null
                      ? DetailPanel(
                          key: ValueKey(_state.selectedPointerIndex),
                          pointer: _state.selectedPointer!,
                          allPointers: _state.pointers,
                          snapshotHistory: _state.snapshotHistory,
                          onNavigate: _selectPointer,
                          canGoBack: _state.canGoBack,
                          onGoBack: _navigateBack,
                          canLoadMore:
                              _vmConnection.hasReadMemoryRpc &&
                              _state.selectedPointer!.address != 0 &&
                              _state.selectedPointer!.category ==
                                  models.PointerCategory.raw &&
                              (_state.selectedPointer!.rawBytes?.length ?? 0) <
                                  4096,
                          onLoadMore: _loadMoreForSelectedPointer,
                        )
                      : _emptyState(),
                ),
              ],
            ),
          ),
          // ─── Status bar ───
          StatusBar(state: _state),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _state.connectionState == models.ConnectionState.connected
                ? Icons.search_off
                : Icons.link_off,
            size: 36,
            color: InspectorTheme.textDim.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            _state.connectionState == models.ConnectionState.connected
                ? 'No pointer selected'
                : 'Connect to a Dart VM to start inspecting',
            style: InspectorTheme.label,
          ),
        ],
      ),
    );
  }
}
