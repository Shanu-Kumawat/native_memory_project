/// Native Memory Inspector — GSoC Sample Project
///
/// A Flutter desktop application that inspects Pointer<T> objects
/// through the Dart VM Service Protocol.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/pointer_data.dart' as models;
import 'services/mock_data.dart';
import 'services/vm_service_connection.dart';
import 'theme.dart';
import 'widgets/connection_panel.dart';
import 'widgets/pointer_card.dart';

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

class _InspectorPageState extends State<InspectorPage>
    with SingleTickerProviderStateMixin {
  final _vmConnection = VmServiceConnection();
  var _state = const models.InspectorState();
  bool _useMockData = false;

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
      ),
    );
  }

  Future<void> _scanForPointers() async {
    final pointers = await _vmConnection.findPointers();
    _updateState((s) => s.copyWith(pointers: pointers));
  }

  void _loadMockData() {
    setState(() {
      _useMockData = true;
      _state = _state.copyWith(
        connectionState: models.ConnectionState.connected,
        pointers: MockDataProvider.getMockPointers(),
        vmName: 'Mock VM',
        vmVersion: '(demo mode)',
      );
    });
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
          if (_state.connectionState != models.ConnectionState.connected)
            _connectionSection()
          else
            _connectedHeader(),
          Expanded(
            child: _state.pointers.isEmpty
                ? _emptyState()
                : _pointerList(),
          ),
        ],
      ),
    );
  }

  Widget _titleBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: InspectorTheme.surface,
        border: Border(
          bottom: BorderSide(color: InspectorTheme.border),
        ),
      ),
      child: Row(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  InspectorTheme.accent.withValues(alpha: 0.2),
                  InspectorTheme.purple.withValues(alpha: 0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.memory,
              size: 20,
              color: InspectorTheme.accent,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Native Memory Inspector',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: InspectorTheme.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: InspectorTheme.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'GSoC Sample',
              style: InspectorTheme.monoSmall.copyWith(
                color: InspectorTheme.warning,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          // Connection status
          _connectionDot(),
          const SizedBox(width: 8),
          Text(
            _connectionLabel(),
            style: InspectorTheme.label,
          ),
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
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)],
      ),
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

  Widget _connectionSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Connect to VM Service',
                    style: InspectorTheme.heading,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Enter the WebSocket URI of a running Dart VM with --enable-vm-service',
                    style: InspectorTheme.label,
                  ),
                ),
                ConnectionPanel(
                  onConnect: _connect,
                  isConnecting: _state.connectionState ==
                      models.ConnectionState.connecting,
                  errorMessage: _state.connectionState ==
                          models.ConnectionState.error
                      ? _state.errorMessage
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Mock data button
          OutlinedButton.icon(
            onPressed: _loadMockData,
            icon: const Icon(Icons.science_outlined, size: 16),
            label: Text(
              'Load Demo Data (No VM Required)',
              style: InspectorTheme.label.copyWith(
                color: InspectorTheme.accent,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: InspectorTheme.accent.withValues(alpha: 0.3),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectedHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: InspectorTheme.border)),
      ),
      child: Row(
        children: [
          Text(
            '${_state.pointers.length} pointer(s) found',
            style: InspectorTheme.label,
          ),
          const Spacer(),
          if (!_useMockData)
            TextButton.icon(
              onPressed: _scanForPointers,
              icon: const Icon(Icons.refresh, size: 14),
              label: Text('Rescan', style: InspectorTheme.label),
            ),
          TextButton.icon(
            onPressed: _useMockData
                ? () {
                    setState(() {
                      _useMockData = false;
                      _state = const models.InspectorState();
                    });
                  }
                : _disconnect,
            icon: const Icon(Icons.power_off, size: 14, color: InspectorTheme.error),
            label: Text(
              'Disconnect',
              style: InspectorTheme.label.copyWith(
                color: InspectorTheme.error,
              ),
            ),
          ),
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
            Icons.search_off,
            size: 48,
            color: InspectorTheme.textDim.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No Pointer<T> variables found',
            style: InspectorTheme.heading.copyWith(
              color: InspectorTheme.textDim,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure your program uses dart:ffi Pointer allocations\nand is paused at a breakpoint.',
            style: InspectorTheme.label,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _pointerList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _state.pointers.length,
      itemBuilder: (context, index) {
        return PointerCard(
          data: _state.pointers[index],
          initiallyExpanded: index == 0,
        );
      },
    );
  }
}
