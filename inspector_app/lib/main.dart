// Native Memory Inspector — GSoC Sample Project
//
// A Flutter desktop application that inspects Pointer<T> objects
// through the Dart VM Service Protocol.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  void _updateState(
      models.InspectorState Function(models.InspectorState) fn) {
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
    _updateState((s) => s.copyWith(
      pointers: pointers,
      selectedPointerIndex: pointers.isNotEmpty ? 0 : -1,
    ));
  }

  void _selectPointer(int index) {
    final history = List<int>.from(_state.navigationHistory);
    if (_state.selectedPointerIndex >= 0) {
      history.add(_state.selectedPointerIndex);
    }
    _updateState((s) => s.copyWith(
      selectedPointerIndex: index,
      navigationHistory: history,
    ));
  }

  void _navigateBack() {
    if (!_state.canGoBack) return;
    final history = List<int>.from(_state.navigationHistory);
    final prev = history.removeLast();
    _updateState((s) => s.copyWith(
      selectedPointerIndex: prev,
      navigationHistory: history,
    ));
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
          _titleBar(),
          Expanded(
            child: Row(
              children: [
                // ─── Sidebar ───
                SizedBox(
                  width: 260,
                  child: PointerSidebar(
                    pointers: _state.pointers,
                    selectedIndex: _state.selectedPointerIndex,
                    onSelect: _selectPointer,
                    isConnected: _state.connectionState ==
                        models.ConnectionState.connected,
                    onConnect: _connect,
                    onDisconnect: _disconnect,
                    onRescan: _scanForPointers,
                    isConnecting: _state.connectionState ==
                        models.ConnectionState.connecting,
                    errorMessage: _state.connectionState ==
                            models.ConnectionState.error
                        ? _state.errorMessage
                        : null,
                  ),
                ),
                // ─── Divider ───
                Container(
                  width: 1,
                  color: InspectorTheme.border,
                ),
                // ─── Detail panel ───
                Expanded(
                  child: _state.selectedPointer != null
                      ? DetailPanel(
                          key: ValueKey(_state.selectedPointerIndex),
                          pointer: _state.selectedPointer!,
                          allPointers: _state.pointers,
                          onNavigate: _selectPointer,
                          canGoBack: _state.canGoBack,
                          onGoBack: _navigateBack,
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

  Widget _titleBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: InspectorTheme.surface,
        border: Border(bottom: BorderSide(color: InspectorTheme.border)),
      ),
      child: Row(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: InspectorTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.memory, size: 16,
                color: InspectorTheme.accent),
          ),
          const SizedBox(width: 10),
          Text(
            'Native Memory Inspector',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: InspectorTheme.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: InspectorTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'GSoC',
              style: InspectorTheme.monoSmall.copyWith(
                color: InspectorTheme.warning,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          // Connection indicator
          _connectionDot(),
          const SizedBox(width: 6),
          Text(_connectionLabel(), style: InspectorTheme.label.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _connectionDot() {
    final color = switch (_state.connectionState) {
      models.ConnectionState.connected => InspectorTheme.success,
      models.ConnectionState.connecting => InspectorTheme.warning,
      models.ConnectionState.error => InspectorTheme.error,
      models.ConnectionState.disconnected => InspectorTheme.textDim,
    };
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  String _connectionLabel() {
    return switch (_state.connectionState) {
      models.ConnectionState.connected =>
        '${_state.vmName} ${_state.vmVersion}',
      models.ConnectionState.connecting => 'Connecting...',
      models.ConnectionState.error => 'Connection failed',
      models.ConnectionState.disconnected => 'Disconnected',
    };
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
