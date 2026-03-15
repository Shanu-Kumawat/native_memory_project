/// VM Service connection manager for live pointer inspection.
///
/// Supports two modes:
/// 1. Standard SDK: Uses heuristic type inference + known struct layouts
/// 2. Custom SDK (Phase 2): Uses enriched protocol data:
///    - kind: "Pointer" with nativeAddress and nativeType
///    - _readNativeMemory RPC for safe memory reads

import 'dart:async';
import 'dart:typed_data';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../models/pointer_data.dart';

/// Log callback for diagnostics.
typedef LogCallback = void Function(String message);

class VmServiceConnection {
  VmService? _service;
  String? _isolateId;
  LogCallback? onLog;

  /// Whether the connected VM supports the enriched Pointer protocol.
  bool _hasEnrichedProtocol = false;

  /// Whether the connected VM supports the _readNativeMemory RPC.
  bool _hasReadMemoryRpc = false;

  /// Cache of struct class names found in the target library.
  List<String> _structClassNames = [];

  bool get isConnected => _service != null;
  bool get hasEnrichedProtocol => _hasEnrichedProtocol;
  bool get hasReadMemoryRpc => _hasReadMemoryRpc;

  void _log(String message) {
    onLog?.call(message);
    // ignore: avoid_print
    print('[VmServiceConnection] $message');
  }

  // ─── Connection Lifecycle ───────────────────────────────────────────

  /// Connect to a running Dart VM's service.
  Future<({String vmName, String vmVersion})> connect(String wsUri) async {
    _log('Connecting to: $wsUri');
    _service = await vmServiceConnectUri(wsUri);
    final vm = await _service!.getVM();
    _log('Connected to ${vm.name} v${vm.version}');

    for (final isolate in vm.isolates ?? <IsolateRef>[]) {
      _isolateId = isolate.id;
      _log('Found isolate: ${isolate.name} (${isolate.id})');
    }

    // Pre-scan for Struct/Union subclasses
    await _scanStructClasses();

    // Probe for enriched protocol support
    await _probeEnrichedProtocol();

    return (
      vmName: vm.name ?? 'Dart VM',
      vmVersion: vm.version ?? 'unknown',
    );
  }

  /// Disconnect from the VM Service.
  Future<void> disconnect() async {
    _log('Disconnecting...');
    await _service?.dispose();
    _service = null;
    _isolateId = null;
    _structClassNames = [];
    _hasEnrichedProtocol = false;
    _hasReadMemoryRpc = false;
    _log('Disconnected');
  }

  /// Probe whether the connected VM has our custom protocol extensions.
  Future<void> _probeEnrichedProtocol() async {
    if (_service == null || _isolateId == null) return;

    // Try calling _readNativeMemory with address=1, count=0 to see if it
    // exists. If it returns an error other than "method not found", it exists.
    try {
      await _service!.callMethod('_readNativeMemory', isolateId: _isolateId, args: {
        'address': '1',
        'count': '0',
      });
      _hasReadMemoryRpc = true;
      _log('✓ _readNativeMemory RPC is available');
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('method not found') ||
          errStr.contains('Unrecognized')) {
        _hasReadMemoryRpc = false;
        _log('✗ _readNativeMemory RPC not available (standard SDK)');
      } else {
        // The method exists but returned an error (expected for address=1)
        _hasReadMemoryRpc = true;
        _log('✓ _readNativeMemory RPC is available (returned error: expected)');
      }
    }

    // Check for enriched protocol by looking at a Pointer instance's kind.
    // We'll detect this during pointer extraction — set to false for now.
    _hasEnrichedProtocol = false;
    _log('Protocol enrichment will be detected during pointer extraction');
  }

  // ─── Struct Class Discovery ─────────────────────────────────────────

  /// Scan all libraries for classes that extend Struct or Union.
  Future<void> _scanStructClasses() async {
    if (_service == null || _isolateId == null) return;
    _structClassNames = [];

    _log('Scanning for Struct/Union subclasses...');

    try {
      final isolate = await _service!.getIsolate(_isolateId!);
      for (final libRef in isolate.libraries ?? <LibraryRef>[]) {
        // Only scan user libraries (skip dart: and package: from SDK)
        final uri = libRef.uri ?? '';
        if (uri.startsWith('dart:') ||
            uri.startsWith('package:ffi/') ||
            uri.contains('dart_internal')) {
          continue;
        }

        try {
          final lib =
              await _service!.getObject(_isolateId!, libRef.id!) as Library;
          for (final classRef in lib.classes ?? <ClassRef>[]) {
            final name = classRef.name;
            if (name == null || name.startsWith('_')) continue;

            try {
              final cls = await _service!.getObject(
                _isolateId!,
                classRef.id!,
              ) as Class;

              // Check if superclass is Struct or Union
              final superName = cls.superClass?.name;
              if (superName == 'Struct' || superName == 'Union') {
                _structClassNames.add(name);
                _log('  Found struct class: $name (extends $superName)');
              }
            } catch (_) {}
          }
        } catch (_) {}
      }
    } catch (e) {
      _log('Struct class scan error: $e');
    }

    _log('Struct classes found: $_structClassNames');
  }

  /// Try to infer the struct type for a pointer variable by name matching.
  String _inferTypeByName(String varName) {
    final lowerVar = varName.toLowerCase().replaceAll(RegExp(r'[0-9]+$'), '');

    for (final className in _structClassNames) {
      if (className.toLowerCase() == lowerVar) return className;
      if (lowerVar.endsWith(className.toLowerCase())) return className;
      if (lowerVar.contains(className.toLowerCase())) return className;
    }

    // If only one struct class exists, it's likely the target
    if (_structClassNames.length == 1) return _structClassNames.first;

    return 'Unknown';
  }

  // ─── Pointer Discovery ──────────────────────────────────────────────

  /// Scan the current isolate for Pointer variables.
  Future<List<PointerData>> findPointers() async {
    if (_service == null || _isolateId == null) {
      _log('Not connected or no isolate');
      return [];
    }

    _log('═══ Starting pointer scan ═══');
    final pointers = <PointerData>[];
    bool wePaused = false;

    try {
      // Step 1: Check isolate state
      final isolate = await _service!.getIsolate(_isolateId!);
      final pauseKind = isolate.pauseEvent?.kind;
      _log('Isolate pause state: $pauseKind');

      // Handle PauseStart specially: main() hasn't run yet, so we need
      // to resume and wait for the debugger() breakpoint.
      if (pauseKind == EventKind.kPauseStart) {
        _log('Isolate paused at start — resuming to reach debugger()...');
        
        // Subscribe to debug events to detect when we hit the breakpoint
        final completer = Completer<void>();
        StreamSubscription? sub;
        
        sub = _service!.onDebugEvent.listen((event) {
          _log('Debug event: ${event.kind}');
          if (event.kind == EventKind.kPauseBreakpoint ||
              event.kind == EventKind.kPauseInterrupted ||
              event.kind == EventKind.kPauseException) {
            if (!completer.isCompleted) {
              completer.complete();
            }
            sub?.cancel();
          }
        });

        await _service!.streamListen(EventStreams.kDebug);
        await _service!.resume(_isolateId!);

        // Wait for the breakpoint (timeout after 10 seconds)
        try {
          await completer.future.timeout(const Duration(seconds: 10));
          _log('Isolate hit breakpoint — ready to scan');
        } catch (e) {
          _log('Timeout waiting for breakpoint: $e');
          sub?.cancel();
          // Try pausing manually as fallback
          await _service!.pause(_isolateId!);
          wePaused = true;
          await Future.delayed(const Duration(milliseconds: 300));
        }

        try {
          await _service!.streamCancel(EventStreams.kDebug);
        } catch (_) {}
      }

      final isPaused = () {
        // Re-check after possible PauseStart handling
        return pauseKind == EventKind.kPauseBreakpoint ||
            pauseKind == EventKind.kPauseInterrupted ||
            pauseKind == EventKind.kPauseException ||
            pauseKind == EventKind.kPausePostRequest ||
            pauseKind == EventKind.kPauseExit;
      }();

      if (!isPaused && pauseKind != EventKind.kPauseStart) {
        _log('Pausing isolate...');
        await _service!.pause(_isolateId!);
        wePaused = true;
        await Future.delayed(const Duration(milliseconds: 200));
        final check = await _service!.getIsolate(_isolateId!);
        _log('After pause: ${check.pauseEvent?.kind}');
      }

      // Step 2: Read stack frames for local Pointer variables
      try {
        final stack = await _service!.getStack(_isolateId!);
        final frames = stack.frames ?? <Frame>[];
        _log('Stack has ${frames.length} frames');

        for (int fi = 0; fi < frames.length; fi++) {
          final frame = frames[fi];
          final vars = frame.vars ?? <BoundVariable>[];
          _log('Frame $fi: ${frame.function?.name ?? "?"} '
              '(${vars.length} vars)');

          for (final variable in vars) {
            final value = variable.value;
            if (value is InstanceRef) {
              final className = value.classRef?.name ?? '';
              _log('  var "${variable.name}": class=$className');
              final pointerData = await _tryExtractPointer(
                variable.name ?? 'unknown',
                value,
              );
              if (pointerData != null) {
                pointers.add(pointerData);
              }
            }
          }
        }
      } catch (e) {
        _log('Stack read error: $e');
      }

      // Step 3: Also scan top-level variables in root library
      try {
        final freshIsolate = await _service!.getIsolate(_isolateId!);
        final rootLibId = freshIsolate.rootLib?.id;
        if (rootLibId != null) {
          final rootLib =
              await _service!.getObject(_isolateId!, rootLibId) as Library;
          final vars = rootLib.variables ?? <FieldRef>[];
          _log('Root library has ${vars.length} variables');

          for (final fieldRef in vars) {
            try {
              final field = await _service!.getObject(
                _isolateId!,
                fieldRef.id!,
              ) as Field;
              final value = field.staticValue;
              if (value is InstanceRef) {
                final pointerData = await _tryExtractPointer(
                  fieldRef.name ?? 'unknown',
                  value,
                );
                if (pointerData != null) {
                  pointers.add(pointerData);
                }
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        _log('Root library scan error: $e');
      }

      // Step 4: Read native memory for all found pointers
      for (int i = 0; i < pointers.length; i++) {
        final p = pointers[i];
        if (p.address != 0 && p.structSize > 0) {
          _log('Reading ${p.structSize} bytes at 0x${p.address.toRadixString(16)} '
              'for ${p.variableName}...');
          final bytes = await readNativeMemory(p.address, p.structSize);
          if (bytes != null) {
            pointers[i] = p.copyWith(rawBytes: bytes);
            _log('  ✓ Read ${bytes.length} bytes successfully');
          } else {
            _log('  ✗ Memory read failed or unavailable');
          }
        }
      }
    } finally {
      if (wePaused) {
        try {
          _log('Resuming isolate...');
          await _service!.resume(_isolateId!);
        } catch (_) {}
      }
    }

    _log('═══ Found ${pointers.length} pointers total ═══');
    return pointers;
  }

  // ─── Pointer Extraction ─────────────────────────────────────────────

  /// Try to extract pointer data from an InstanceRef.
  Future<PointerData?> _tryExtractPointer(
    String varName,
    InstanceRef ref,
  ) async {
    final className = ref.classRef?.name ?? '';

    // Check if this is a Pointer class via class name
    if (className != 'Pointer' && !className.startsWith('Pointer<')) {
      return null;
    }
    if (className.contains('NativeFunction')) return null;

    _log('  → Extracting pointer: $varName (class: $className)');

    // Check if the InstanceRef already has enriched protocol data
    // (kind == "Pointer" instead of "PlainInstance")
    final instanceKind = ref.kind;
    _log('    instanceRef.kind: $instanceKind');

    try {
      final instance =
          await _service!.getObject(_isolateId!, ref.id!) as Instance;

      int address = 0;
      String nativeType = 'Unknown';
      String typeSource = 'unknown';

      // ── Extract address ──

      // Strategy 0: Enriched protocol (nativeAddress in JSON)
      // When using the custom SDK, the Instance JSON will have
      // "nativeAddress" directly. We check the instance's json field.
      final instanceJson = instance.json;
      if (instanceJson != null && instanceJson.containsKey('nativeAddress')) {
        final nAddr = instanceJson['nativeAddress'];
        if (nAddr is int) {
          address = nAddr;
          _log('    address via enriched protocol: $address');
        }
      }

      // Strategy 1: Object fields
      if (address == 0) {
        for (final field in instance.fields ?? <BoundField>[]) {
          final decl = field.decl;
          if (decl?.name == '_address' || decl?.name == 'address') {
            final val = field.value;
            if (val is InstanceRef && val.valueAsString != null) {
              address = int.tryParse(val.valueAsString!) ?? 0;
              _log('    address via field: $address');
            }
          }
        }
      }

      // Strategy 2: Evaluate .address
      if (address == 0) {
        try {
          final evalResult = await _service!.evaluate(
            _isolateId!,
            instance.id!,
            'address',
          );
          if (evalResult is InstanceRef && evalResult.valueAsString != null) {
            address = int.tryParse(evalResult.valueAsString!) ?? 0;
            _log('    address via evaluate: $address');
          }
        } catch (e) {
          _log('    evaluate("address") failed: $e');
        }
      }

      _log('    final address: 0x${address.toRadixString(16)}');

      // ── Extract type ──

      // Detect enriched protocol via kind field
      final instanceKindFromJson = instanceJson?['kind'];
      if (instanceKindFromJson == 'Pointer') {
        _hasEnrichedProtocol = true;
        _log('    ✓ Enriched protocol detected (kind: Pointer)');
      }

      // Strategy 0: Enriched protocol (nativeType in Instance JSON)
      // NOTE: Due to FFI type erasure, the Dart compiler's FFI transformer
      // replaces Pointer<MyStruct> → Pointer<Never> at compile time.
      // So the VM's type_argument() returns "Never" even with our SDK
      // changes. This is a COMPILER-level issue, not a VM-level one.
      // The heuristic fallback (Strategy 3) is still needed until the
      // FFI transformer is modified to preserve type arguments.
      if (instanceJson != null && instanceJson.containsKey('nativeType')) {
        final ntData = instanceJson['nativeType'];
        String? extractedName;

        if (ntData is Map) {
          // Full Type JSON object: {"type": "@Type", "name": "Never", ...}
          extractedName = ntData['name'] as String?;
          _log('    nativeType from protocol: $extractedName '
              '(class: ${ntData['type']})');
        } else if (ntData is String) {
          extractedName = ntData;
          _log('    nativeType from protocol: $extractedName (string)');
        }

        if (extractedName != null && extractedName != 'Never') {
          nativeType = extractedName;
          typeSource = 'enriched protocol';
          _log('    ✓ Type resolved via enriched protocol: $nativeType');
        } else if (extractedName == 'Never') {
          _log('    nativeType is "Never" (FFI type erasure — '
              'compiler strips Pointer<T> → Pointer<Never>)');
        }
      }

      // Strategy 1: TypeArgumentsRef name
      if (nativeType == 'Unknown') {
        final typeArgs = instance.typeArguments;
        if (typeArgs != null && typeArgs.name != null) {
          final typeArgsName = typeArgs.name!;
          _log('    typeArguments.name: $typeArgsName');
          final match = RegExp(r'<(\w+)>').firstMatch(typeArgsName);
          if (match != null && match.group(1) != 'Never') {
            nativeType = match.group(1)!;
            typeSource = 'typeArguments';
          }
        }
      }

      // Strategy 2: runtimeType (often returns Pointer<Never> but try anyway)
      if (nativeType == 'Unknown') {
        try {
          final rtResult = await _service!.evaluate(
            _isolateId!,
            instance.id!,
            'runtimeType.toString()',
          );
          if (rtResult is InstanceRef && rtResult.valueAsString != null) {
            final rtStr = rtResult.valueAsString!;
            _log('    runtimeType: $rtStr');
            final match = RegExp(r'Pointer<(\w+)>').firstMatch(rtStr);
            if (match != null && match.group(1) != 'Never') {
              nativeType = match.group(1)!;
              typeSource = 'runtimeType';
            }
          }
        } catch (_) {}
      }

      // Strategy 3: Name-based heuristic (last resort)
      if (nativeType == 'Unknown') {
        nativeType = _inferTypeByName(varName);
        if (nativeType != 'Unknown') {
          typeSource = 'name heuristic';
          _log('    type inferred from name: $nativeType (heuristic)');
        }
      }

      _log('    nativeType: $nativeType (via $typeSource)');

      // ── Extract struct layout ──
      final fields = await _extractStructFields(nativeType);
      final structSize =
          fields.isNotEmpty ? fields.last.offset + fields.last.size : 0;
      _log('    struct layout: ${fields.length} fields, '
          'total size: $structSize bytes');

      return PointerData(
        variableName: varName,
        nativeType: nativeType,
        address: address,
        structSize: structSize,
        fields: fields,
        error: address == 0 ? 'null pointer (address 0)' : null,
      );
    } catch (e) {
      _log('    extraction failed: $e');
      return PointerData(
        variableName: varName,
        nativeType: 'Unknown',
        address: 0,
        structSize: 0,
        fields: [],
        error: 'Failed to inspect: $e',
      );
    }
  }

  // ─── Native Memory Reading ──────────────────────────────────────────

  /// Read native memory from the target process.
  ///
  /// Uses the custom SDK's _readNativeMemory RPC when available.
  /// Returns null if the RPC is not available or the read fails.
  Future<Uint8List?> readNativeMemory(int address, int count) async {
    if (_service == null || _isolateId == null) return null;
    if (address == 0 || count <= 0) return null;

    // Try the custom SDK RPC
    if (_hasReadMemoryRpc) {
      try {
        _log('  Calling _readNativeMemory(0x${address.toRadixString(16)}, $count)');
        final response = await _service!.callMethod(
          '_readNativeMemory',
          isolateId: _isolateId,
          args: {
            'address': address.toString(),
            'count': count.toString(),
          },
        );

        final json = response.json;
        if (json != null && json['bytes'] is List) {
          final byteList = (json['bytes'] as List).cast<int>();
          _log('  _readNativeMemory returned ${byteList.length} bytes');
          return Uint8List.fromList(byteList);
        }
      } catch (e) {
        _log('  _readNativeMemory failed: $e');
        // If method not found, disable for future calls
        if (e.toString().contains('method not found') ||
            e.toString().contains('Unrecognized')) {
          _hasReadMemoryRpc = false;
          _log('  Disabling _readNativeMemory RPC (not available)');
        }
      }
    }

    // Fallback: Try to read memory via evaluate on the pointer
    try {
      _log('  Trying memory read via evaluate...');
      // Use Dart FFI's Pointer.cast<Uint8>() to read bytes
      // This requires the pointer to be in scope
      return null;
    } catch (_) {}

    return null;
  }

  // ─── Struct Field Extraction ────────────────────────────────────────

  /// Try to extract struct field metadata.
  Future<List<StructField>> _extractStructFields(String typeName) async {
    if (_service == null || _isolateId == null) return [];
    if (typeName == 'Unknown') return [];

    try {
      final isolate = await _service!.getIsolate(_isolateId!);
      for (final libRef in isolate.libraries ?? <LibraryRef>[]) {
        try {
          final lib =
              await _service!.getObject(_isolateId!, libRef.id!) as Library;
          for (final classRef in lib.classes ?? <ClassRef>[]) {
            if (classRef.name == typeName) {
              _log('    Found class $typeName');
              final cls = await _service!.getObject(
                _isolateId!,
                classRef.id!,
              ) as Class;
              return _extractFieldsFromClass(cls);
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      _log('    struct field extraction error: $e');
    }
    return [];
  }

  /// Extract field information from a Class object.
  /// Handles FFI-transformed fields where:
  /// - Fields may be prefixed with '#' (synthetic helpers)
  /// - Declared types may be internal names (e.g., 'X0' instead of 'Double')
  /// - Some fields are generated accessors, not user-declared fields
  List<StructField> _extractFieldsFromClass(Class cls) {
    final fields = <StructField>[];
    int offset = 0;

    // Log ALL fields for diagnosis
    _log('    Class ${cls.name} fields:');
    for (final fieldRef in cls.fields ?? <FieldRef>[]) {
      final name = fieldRef.name ?? '?';
      final typeName = fieldRef.declaredType?.name ?? '?';
      final isStatic = fieldRef.isStatic ?? false;
      final isConst = fieldRef.isConst ?? false;
      _log('      "$name" type=$typeName '
          'static=$isStatic const=$isConst');
    }

    // Collect user-visible fields
    for (final fieldRef in cls.fields ?? <FieldRef>[]) {
      String? name = fieldRef.name;
      if (name == null) continue;

      // Skip static and const fields (like #sizeOf, type metadata)
      if (fieldRef.isStatic == true || fieldRef.isConst == true) continue;

      // Skip internal helpers (offsetOf, sizeOf, etc.)
      if (name.startsWith('#')) {
        if (name == '#sizeOf' ||
            name == '#offsetOf' ||
            name.contains('offsetOf')) {
          continue;
        }
        name = name.substring(1);
      }

      // Skip remaining private fields
      if (name.startsWith('_')) continue;

      // Determine type and size from field metadata
      final declType = fieldRef.declaredType;
      String typeName = declType?.name ?? 'Unknown';

      // Map the actual type to FFI type name and size
      final mapped = _mapToFfiType(typeName);
      typeName = mapped.typeName;
      int size = mapped.size;

      // Alignment
      if (size > 0 && offset % size != 0) {
        offset = ((offset ~/ size) + 1) * size;
      }

      fields.add(StructField(
        name: name,
        typeName: typeName,
        offset: offset,
        size: size,
      ));

      offset += size;
    }

    // If no fields found, OR if fields have unrecognized FFI types
    // (e.g., 'X0' from the FFI transformer), fall back to known layouts.
    final hasUnknownTypes = fields.any((f) => !_isKnownFfiType(f.typeName));
    if (fields.isEmpty || hasUnknownTypes) {
      final known = _getKnownStructLayout(cls.name ?? '');
      if (known.isNotEmpty) {
        _log('    → Using fallback layout for: ${cls.name}');
        return known;
      }
    }

    return fields;
  }

  // ─── Type Mapping ───────────────────────────────────────────────────

  /// Check if a type name is a recognized FFI type.
  bool _isKnownFfiType(String typeName) {
    const knownTypes = {
      'Int8', 'Int16', 'Int32', 'Int64',
      'Uint8', 'Uint16', 'Uint32', 'Uint64',
      'Float', 'Double', 'Bool', 'Void',
      'int', 'double', 'float', 'bool',
    };
    return knownTypes.contains(typeName) || typeName.startsWith('Pointer');
  }

  /// Map a Dart/FFI/internal type name to its FFI type name and size.
  ({String typeName, int size}) _mapToFfiType(String rawType) {
    return switch (rawType) {
      'int' || 'Int32' || 'Uint32' => (
        typeName: rawType == 'int' ? 'Int32' : rawType,
        size: 4
      ),
      'Int8' || 'Uint8' || 'Bool' => (typeName: rawType, size: 1),
      'Int16' || 'Uint16' => (typeName: rawType, size: 2),
      'Int64' || 'Uint64' => (typeName: rawType, size: 8),
      'Float' || 'float' => (typeName: 'Float', size: 4),
      'Double' || 'double' => (typeName: 'Double', size: 8),
      'Pointer' => (typeName: 'Pointer', size: 8),
      _ when rawType.startsWith('Pointer') => (typeName: rawType, size: 8),
      _ => (typeName: rawType, size: 8), // Default to pointer size
    };
  }

  /// Get known struct layouts when class inspection fails.
  ///
  /// In the real GSoC implementation, this would use:
  /// 1. @pragma('vm:ffi:struct-fields') metadata
  /// 2. The enriched VM Service Protocol (Phase 2)
  List<StructField> _getKnownStructLayout(String className) {
    _log('    → Known layout fallback for: $className');
    return switch (className) {
      'MyStruct' => const [
          StructField(name: 'id', typeName: 'Int32', offset: 0, size: 4),
          StructField(name: 'value', typeName: 'Float', offset: 4, size: 4),
          StructField(
              name: 'timestamp', typeName: 'Int64', offset: 8, size: 8),
        ],
      'Point' => const [
          StructField(name: 'x', typeName: 'Double', offset: 0, size: 8),
          StructField(name: 'y', typeName: 'Double', offset: 8, size: 8),
        ],
      'Node' => const [
          StructField(name: 'data', typeName: 'Int32', offset: 0, size: 4),
          StructField(
              name: 'next', typeName: 'Pointer<Node>', offset: 8, size: 8),
        ],
      _ => [],
    };
  }
}
