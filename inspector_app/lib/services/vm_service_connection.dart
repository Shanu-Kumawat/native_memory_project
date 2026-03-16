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

    // Check against known struct class names first
    for (final className in _structClassNames) {
      if (className.toLowerCase() == lowerVar) return className;
      if (lowerVar.endsWith(className.toLowerCase())) return className;
      if (lowerVar.contains(className.toLowerCase())) return className;
    }

    // Detect primitive FFI types from variable name patterns
    // e.g., innerInt → Int32, rawBuf/bufData → Uint8, ptrToPtr → Pointer
    final primitiveMatch = _inferPrimitiveTypeFromName(varName);
    if (primitiveMatch != null) return primitiveMatch;

    // If only one struct class exists, it's likely the target
    if (_structClassNames.length == 1) return _structClassNames.first;

    return 'Unknown';
  }

  /// Try to infer a primitive FFI type from a variable name.
  /// Returns the FFI type name (e.g., 'Int32', 'Uint8', 'Pointer')
  /// or null if no match.
  String? _inferPrimitiveTypeFromName(String varName) {
    final lower = varName.toLowerCase();

    // Pointer-to-pointer patterns: ptrToPtr, doublePtr, ptrPtr
    if (lower.contains('ptrtoptr') || lower.contains('ptrtop') ||
        lower.contains('doubleptr') || lower.contains('ptrptr')) {
      return 'Pointer<Pointer>';
    }

    // Integer patterns: innerInt, myInt32, intValue
    if (lower.contains('int64') || lower.contains('long')) return 'Int64';
    if (lower.contains('int32') || lower.endsWith('int') ||
        lower.startsWith('int') || lower.contains('inner') &&
        lower.contains('int')) {
      return 'Int32';
    }
    if (lower.contains('int16') || lower.contains('short')) return 'Int16';
    if (lower.contains('int8') || lower.contains('byte') &&
        !lower.contains('buf')) {
      return 'Int8';
    }

    // Unsigned integer patterns
    if (lower.contains('uint64')) return 'Uint64';
    if (lower.contains('uint32')) return 'Uint32';
    if (lower.contains('uint16')) return 'Uint16';
    if (lower.contains('uint8') || lower.contains('rawbuf') ||
        lower.contains('bufdata') || lower.contains('rawdata') ||
        lower.contains('databuf')) {
      return 'Uint8';
    }

    // Float/double patterns
    if (lower.contains('float')) return 'Float';
    if (lower.contains('double') || lower.contains('dbl')) return 'Double';

    return null;
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
        if (p.address != 0) {
          // Read structSize bytes if known, otherwise 64 bytes for untyped pointers
          final readSize = p.structSize > 0 ? p.structSize : 64;
          _log('Reading $readSize bytes at 0x${p.address.toRadixString(16)} '
              'for ${p.variableName}...');
          final bytes = await readNativeMemory(p.address, readSize);
          if (bytes != null) {
            // For unknown pointers, update structSize to bytes read
            pointers[i] = p.copyWith(
              rawBytes: bytes,
              structSize: p.structSize > 0 ? null : bytes.length,
            );
            _log('  ✓ Read ${bytes.length} bytes successfully');
          } else {
            // Memory read failed — set error so UI shows it
            if (p.nativeType == 'Unknown') {
              pointers[i] = p.copyWith(
                error: 'Memory read failed: address may be invalid or unmapped',
              );
            }
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
      final layout = await _extractStructFields(nativeType);
      final rawFields = layout.fields;
      final structSize = layout.totalSize > 0
          ? layout.totalSize
          : (rawFields.isNotEmpty
              ? rawFields.last.offset + rawFields.last.size
              : 0);
      _log('    struct layout: ${rawFields.length} fields, '
          'total size: $structSize bytes (sizeOf=${ layout.totalSize })');

      // ── Insert synthetic padding fields ──
      final fields = _insertPadding(rawFields, structSize);

      // ── Populate children for arrays ──
      _populateArrayChildren(fields);

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

  /// Cached root library ID for evaluate calls that need dart:ffi imports.
  String? _rootLibraryId;

  /// Get the root library ID (the user's library that imports dart:ffi).
  Future<String?> _getRootLibraryId() async {
    if (_rootLibraryId != null) return _rootLibraryId;
    if (_service == null || _isolateId == null) return null;
    try {
      final isolate = await _service!.getIsolate(_isolateId!);
      final rootLib = isolate.rootLib;
      if (rootLib != null) {
        _rootLibraryId = rootLib.id;
        _log('    Root library: ${rootLib.uri}');
        return _rootLibraryId;
      }
    } catch (e) {
      _log('    Could not find root library: $e');
    }
    return null;
  }

  /// Try to extract struct field metadata from the VM.
  ///
  /// The FFI transformer rewrites struct classes:
  /// - Original `external int x;` → getter/setter functions
  /// - Field declarations may vanish from Class.fields
  /// - @pragma('vm:ffi:struct-fields') injected with type list
  ///
  /// Strategy: get field NAMES from getters, TYPES from pragma/evaluate.
  /// Returns both the field list and the evaluated total size.
  Future<({List<StructField> fields, int totalSize})> _extractStructFields(
      String typeName) async {
    if (_service == null || _isolateId == null) {
      return (fields: <StructField>[], totalSize: 0);
    }
    if (typeName == 'Unknown') {
      _log('    Cannot extract fields: type is Unknown');
      return (fields: <StructField>[], totalSize: 0);
    }

    // Handle primitive FFI types — create synthetic single-field layout
    final primitiveLayout = _syntheticPrimitiveLayout(typeName);
    if (primitiveLayout != null) {
      _log('    ✓ Synthetic layout for primitive type $typeName');
      return primitiveLayout;
    }

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

              final result = await _extractFieldsFromStruct(cls);
              if (result.fields.isNotEmpty) {
                _log('    ✓ Extracted ${result.fields.length} fields '
                    'for $typeName (sizeOf=${result.totalSize})');
                return result;
              }

              _log('    ✗ Could not extract field layout for $typeName');
              return (fields: <StructField>[], totalSize: 0);
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      _log('    ✗ Struct field extraction error: $e');
      return (fields: <StructField>[], totalSize: 0);
    }

    _log('    ✗ Class $typeName not found in loaded libraries');
    return (fields: <StructField>[], totalSize: 0);
  }

  /// Extract field layout for an FFI Struct/Union class.
  ///
  /// The FFI transformer rewrites struct classes and generates:
  /// - Getter/setter pairs: `id`, `id=` for each field
  /// - Offset helpers: `id#offsetOf` for each field (evaluable)
  /// - Size helper: `#sizeOf` for total struct size (evaluable)
  /// - Constructors: `ClassName`, `ClassName.#fromTypedDataBase`, etc.
  ///
  /// Strategy:
  /// 1. Use `fieldName#offsetOf` entries as the authoritative field list
  /// 2. For structs without #offsetOf (same-type fields), use setter
  ///    matching: if `name=` exists, `name` is a field
  /// 3. Evaluate #offsetOf and #sizeOf for ABI-correct layout
  /// 4. Get field types from Class.fields or size-based inference
  Future<({List<StructField> fields, int totalSize})>
      _extractFieldsFromStruct(Class cls) async {
    final className = cls.name ?? '';
    final classJson = cls.json;

    // ── Scan all functions ──
    final allFuncNames = <String>[];
    final offsetOfNames = <String>{};  // fields that have #offsetOf
    final setterNames = <String>{};    // fields that have setters
    final getterFuncIds = <String, String>{}; // field name → func ID

    final functions = classJson?['functions'] as List?;
    if (functions != null) {
      _log('    Class $className has ${functions.length} functions');

      for (final funcEntry in functions) {
        if (funcEntry is Map) {
          final funcName = funcEntry['name'] as String? ?? '';
          final funcId = funcEntry['id'] as String?;
          allFuncNames.add(funcName);

          // Detect #offsetOf entries: "id#offsetOf" → field "id"
          if (funcName.endsWith('#offsetOf')) {
            final fieldName = funcName.substring(
                0, funcName.length - '#offsetOf'.length);
            offsetOfNames.add(fieldName);
            _log('      #offsetOf → field: "$fieldName"');
          }

          // Detect setters: "id=" → field "id"
          if (funcName.endsWith('=') && !funcName.startsWith('_')) {
            final fieldName = funcName.substring(0, funcName.length - 1);
            setterNames.add(fieldName);
          }

          // Track getter function IDs for return type lookup
          if (funcId != null &&
              !funcName.startsWith('#') &&
              !funcName.startsWith('_') &&
              !funcName.endsWith('=') &&
              !funcName.contains('#') &&
              !funcName.contains('.') &&
              funcName != className) {
            getterFuncIds[funcName] = funcId;
          }
        }
      }
    }

    _log('    #offsetOf fields: $offsetOfNames');
    _log('    setter fields: $setterNames');

    // ── Determine field names ──
    // Priority 1: #offsetOf entries (authoritative — FFI transformer signal)
    // Priority 2: Class.fields (for structs that keep field declarations)
    // Priority 3: setter-matching (if name= exists, name is a field)
    List<String> fieldNames;

    if (offsetOfNames.isNotEmpty) {
      // Use #offsetOf as authoritative field list
      fieldNames = offsetOfNames.toList();
      _log('    Using #offsetOf-based field list: $fieldNames');
    } else {
      // Fallback: use Class.fields + setter matching
      fieldNames = <String>[];

      // From Class.fields
      for (final fieldRef in cls.fields ?? <FieldRef>[]) {
        final name = fieldRef.name ?? '';
        if (name.isEmpty) continue;
        if (fieldRef.isStatic == true || fieldRef.isConst == true) continue;
        if (name.startsWith('#') || name.startsWith('_')) continue;
        if (!fieldNames.contains(name)) fieldNames.add(name);
      }

      // From setter matching (filter by setter existence)
      if (fieldNames.isEmpty) {
        for (final setter in setterNames) {
          if (!setter.contains('.') &&
              !setter.contains('#') &&
              allFuncNames.contains(setter)) {
            if (!fieldNames.contains(setter)) fieldNames.add(setter);
          }
        }
      }

      _log('    Using fallback field list: $fieldNames');
    }

    // Log Class.fields for diagnosis
    _log('    Class $className fields:');
    for (final fieldRef in cls.fields ?? <FieldRef>[]) {
      final name = fieldRef.name ?? '?';
      final typeName = fieldRef.declaredType?.name ?? '?';
      final isStatic = fieldRef.isStatic ?? false;
      final isConst = fieldRef.isConst ?? false;
      _log('      "$name" type=$typeName '
          'static=$isStatic const=$isConst');
    }

    if (fieldNames.isEmpty) {
      _log('    ✗ No fields found for $className');
      return (fields: <StructField>[], totalSize: 0);

    }

    // ── Get struct size via invoke on #sizeOf ──
    // The FFI transformer injects #sizeOf as a static GETTER (not method).
    // invoke() evaluates the getter → gets int N → tries N.call() → fails
    // with NoSuchMethodError: "Receiver: N". We parse N from the error.
    int totalSize = 0;
    final classId = cls.id;
    if (classId != null) {
      totalSize = await _invokeGetterValue(classId, '#sizeOf');
      if (totalSize > 0) {
        _log('    #sizeOf = $totalSize');
      }
    }

    // ── Get field offsets via invoke on fieldName#offsetOf ──
    final evaluatedOffsets = <String, int>{};
    if (classId != null && offsetOfNames.isNotEmpty) {
      for (final fieldName in fieldNames) {
        if (!offsetOfNames.contains(fieldName)) continue;
        final offset = await _invokeGetterValue(
            classId, '${fieldName}#offsetOf');
        if (offset >= 0) {
          evaluatedOffsets[fieldName] = offset;
          _log('    ${fieldName}#offsetOf = $offset');
        }
      }
    }

    if (totalSize == 0) {
      _log('    ⚠ Could not get struct size — '
          'will use default type mapping');
    }

    // ── Get field types from getter return types ──
    // Since Class.fields may be empty (FFI transformer removes them),
    // we get types from the getter function's return type.
    final fieldTypes = <String, String>{};
    for (final name in fieldNames) {
      // First try Class.fields
      String type = _getFieldDeclaredType(cls, name);
      if (type != 'Unknown') {
        fieldTypes[name] = type;
        continue;
      }

      // Then try getter function return type
      final funcId = getterFuncIds[name];
      if (funcId != null) {
        try {
          final func = await _service!.getObject(
            _isolateId!, funcId) as Func;
          final sig = func.signature;
          final retType = sig?.returnType;
          if (retType != null && retType.name != null) {
            type = retType.name!;
            _log('    getter $name() returns: $type');
            fieldTypes[name] = type;
          }
        } catch (e) {
          _log('    getter $name return type lookup failed: $e');
        }
      }
    }
    _log('    Field types: $fieldTypes');

    // ── Build field layout with sizeOf reconciliation ──
    // The Dart return types (int, double) are ambiguous w.r.t. FFI types:
    //   int → Int8, Int16, Int32, Int64, Uint8, Uint16, Uint32, Uint64
    //   double → Float, Double
    // We use sizeOf<T>() to disambiguate by trying different type
    // combinations and selecting the one that matches the total size.

    // Build candidate type options for each field
    final typeOptions = <List<({String typeName, int size})>>[];
    for (final name in fieldNames) {
      final rawType = fieldTypes[name] ?? 'Unknown';

      // Generate candidate types for ambiguous Dart types
      List<({String typeName, int size})> candidates;
      if (rawType == 'int') {
        candidates = [
          (typeName: 'Int32', size: 4),
          (typeName: 'Int64', size: 8),
        ];
      } else if (rawType == 'double') {
        candidates = [
          (typeName: 'Float', size: 4),
          (typeName: 'Double', size: 8),
        ];
      } else {
        final mapped = _mapToFfiType(rawType);
        candidates = [mapped];
      }

      typeOptions.add(candidates);
    }

    // Try to find a type combination that matches sizeOf
    List<StructField>? bestLayout;

    if (totalSize > 0) {
      bestLayout = _reconcileLayout(
          fieldNames, typeOptions, totalSize, 0, []);
    }

    // If reconciliation found a match, use it
    if (bestLayout != null) {
      _log('    ✓ Reconciled layout with sizeOf=$totalSize');
      for (final f in bestLayout) {
        _log('      ${f.name}: ${f.typeName} '
            'offset=${f.offset} size=${f.size}');
      }
      return (fields: bestLayout, totalSize: totalSize);
    }

    // Fallback: use default type mapping with evaluated offsets.
    // When we have #offsetOf data, compute sizes from offset gaps
    // instead of relying on default type sizes.
    _log('    Using default type mapping (no sizeOf reconciliation)');

    // Check for union layout: all fields at offset 0
    final isUnion = evaluatedOffsets.isNotEmpty &&
        evaluatedOffsets.values.every((o) => o == 0);
    if (isUnion) {
      _log('    Detected union layout (all offsets = 0)');
    }

    final fields = <StructField>[];
    int computedOffset = 0;

    for (int i = 0; i < fieldNames.length; i++) {
      final name = fieldNames[i];
      final rawType = fieldTypes[name] ?? 'Unknown';
      final mapped = _mapToFfiType(rawType);
      String typeName = mapped.typeName;
      int size = mapped.size;

      // Use evaluated offset if available, otherwise compute
      int offset;
      if (evaluatedOffsets.containsKey(name)) {
        offset = evaluatedOffsets[name]!;
      } else {
        // Compute offset with ABI alignment
        if (size > 0 && computedOffset % size != 0) {
          computedOffset = ((computedOffset ~/ size) + 1) * size;
        }
        offset = computedOffset;
      }

      // ── Refine size using offset gaps ──
      // When we have #offsetOf data for consecutive fields, we can
      // compute the exact field size from the gap between offsets.
      // This handles packed structs, nested structs, and arrays correctly.
      if (evaluatedOffsets.containsKey(name)) {
        int inferredSize = size; // fallback to default

        if (isUnion && totalSize > 0) {
          // Union: each field fits within sizeOf
          inferredSize = totalSize.clamp(0, size);
        } else if (i + 1 < fieldNames.length &&
            evaluatedOffsets.containsKey(fieldNames[i + 1])) {
          // Size = next field's offset - this field's offset
          inferredSize = evaluatedOffsets[fieldNames[i + 1]]! - offset;
        } else if (totalSize > 0) {
          // Last field: size = sizeOf - this offset
          inferredSize = totalSize - offset;
        }

        if (inferredSize > 0 && inferredSize != size) {
          // Look up the right type name for the inferred size
          final corrected = _inferTypeFromSize(rawType, inferredSize,
              _structClassNames);
          typeName = corrected.typeName;
          size = corrected.size;
          _log('      $name: offset gap → size=$size (was ${mapped.size}), '
              'type=$typeName');
        }
      }

      fields.add(StructField(
        name: name,
        typeName: typeName,
        offset: offset,
        size: size,
      ));

      if (!isUnion) {
        computedOffset = offset + size;
      }
    }

    if (totalSize > 0 && !isUnion && computedOffset != totalSize) {
      _log('    ⚠ Size mismatch: computed=$computedOffset vs '
          'sizeOf=$totalSize');
    }

    // Use totalSize from sizeOf if available, else computed
    final finalSize = totalSize > 0 ? totalSize : computedOffset;
    _log('    ✓ Built layout: ${fields.length} fields, '
        'totalSize=$finalSize');
    for (final f in fields) {
      _log('      ${f.name}: ${f.typeName} '
          'offset=${f.offset} size=${f.size}');
    }

    return (fields: fields, totalSize: finalSize);
  }

  /// Recursively try type combinations to find one matching sizeOf.
  ///
  /// For each field, tries all candidate types (e.g., Int32 and Int64
  /// for an `int` return type) and computes ABI-aligned offsets.
  /// Returns the first combination whose total size matches [targetSize].
  List<StructField>? _reconcileLayout(
    List<String> fieldNames,
    List<List<({String typeName, int size})>> typeOptions,
    int targetSize,
    int fieldIndex,
    List<({String typeName, int size})> chosen,
  ) {
    if (fieldIndex == fieldNames.length) {
      // All fields assigned — compute total with alignment and check
      int offset = 0;
      final fields = <StructField>[];
      for (int i = 0; i < fieldNames.length; i++) {
        final size = chosen[i].size;
        // ABI alignment
        if (size > 0 && offset % size != 0) {
          offset = ((offset ~/ size) + 1) * size;
        }
        fields.add(StructField(
          name: fieldNames[i],
          typeName: chosen[i].typeName,
          offset: offset,
          size: size,
        ));
        offset += size;
      }

      // Check with struct end alignment (align total to max field size)
      int maxAlign = 1;
      for (final c in chosen) {
        if (c.size > maxAlign) maxAlign = c.size;
      }
      if (offset % maxAlign != 0) {
        offset = ((offset ~/ maxAlign) + 1) * maxAlign;
      }

      if (offset == targetSize) return fields;
      return null;
    }

    // Try each candidate type for this field
    for (final candidate in typeOptions[fieldIndex]) {
      final result = _reconcileLayout(
        fieldNames,
        typeOptions,
        targetSize,
        fieldIndex + 1,
        [...chosen, candidate],
      );
      if (result != null) return result;
    }

    return null;
  }

  /// Invoke a static getter on a class and extract its int value.
  ///
  /// The FFI transformer injects `#sizeOf` and `fieldName#offsetOf` as
  /// static getters (ProcedureKind.Getter). When called via `invoke()`,
  /// the VM evaluates the getter to get the int value N, then tries
  /// `N.call()` which fails with:
  ///   NoSuchMethodError: Class 'int' has no instance method 'call'.
  ///   Receiver: N
  ///
  /// We parse N from the error message. This gives us exact ABI-correct
  /// values without needing expression evaluation (which can't handle #).
  Future<int> _invokeGetterValue(String targetId, String getterName) async {
    if (_service == null || _isolateId == null) return -1;

    try {
      final result = await _service!.invoke(
        _isolateId!, targetId, getterName, []);

      // Direct success (if VM ever supports getter invocation properly)
      if (result is InstanceRef && result.valueAsString != null) {
        return int.tryParse(result.valueAsString!) ?? -1;
      }

      // Parse "Receiver: N" from error message
      final message = result.json?['message'] as String? ?? '';
      final match = RegExp(r'Receiver:\s*(\d+)').firstMatch(message);
      if (match != null) {
        final value = int.tryParse(match.group(1)!) ?? -1;
        _log('    $getterName → $value (parsed from invoke error)');
        return value;
      }

      _log('    $getterName invoke: unexpected response: '
          '${result.json?['type'] ?? result.runtimeType}');
    } catch (e) {
      // The error might also be thrown as an exception
      final errorStr = e.toString();
      final match = RegExp(r'Receiver:\s*(\d+)').firstMatch(errorStr);
      if (match != null) {
        final value = int.tryParse(match.group(1)!) ?? -1;
        _log('    $getterName → $value (parsed from invoke exception)');
        return value;
      }
      _log('    $getterName invoke failed: $e');
    }

    return -1;
  }

  /// Get the declared type name for a field from class inspection.
  String _getFieldDeclaredType(Class cls, String fieldName) {
    for (final fieldRef in cls.fields ?? <FieldRef>[]) {
      String? name = fieldRef.name;
      if (name == null) continue;
      if (name.startsWith('#')) name = name.substring(1);
      if (name == fieldName) {
        return fieldRef.declaredType?.name ?? 'Unknown';
      }
    }
    return 'Unknown';
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
      // FFI transformer internal type names (X0, X1 etc.)
      // X0 is typically Double in the FFI-transformed code
      'X0' => (typeName: 'Double', size: 8),
      _ => (typeName: rawType, size: 8), // Default to pointer size
    };
  }

  /// Infer the correct FFI type from a Dart type and a known byte size.
  ///
  /// Used when #offsetOf gaps reveal the actual field size, which
  /// may differ from the default mapping (e.g., int → Int32 by default,
  /// but offset gap says 1 byte → must be Int8).
  ({String typeName, int size}) _inferTypeFromSize(
      String dartType, int size, List<String> structClassNames) {
    // If this is a known struct class, it's a nested struct field
    if (structClassNames.contains(dartType)) {
      return (typeName: dartType, size: size);
    }

    // For ambiguous Dart types, pick the FFI type matching the size
    if (dartType == 'int') {
      return switch (size) {
        1 => (typeName: 'Int8', size: 1),
        2 => (typeName: 'Int16', size: 2),
        4 => (typeName: 'Int32', size: 4),
        8 => (typeName: 'Int64', size: 8),
        _ => (typeName: 'Int32', size: size), // Keep discovered size
      };
    }
    if (dartType == 'double') {
      return switch (size) {
        4 => (typeName: 'Float', size: 4),
        8 => (typeName: 'Double', size: 8),
        _ => (typeName: 'Double', size: size),
      };
    }

    // For non-ambiguous types, just update the size
    final mapped = _mapToFfiType(dartType);
    return (typeName: mapped.typeName, size: size);
  }

  /// Insert synthetic padding fields between struct fields where gaps exist.
  List<StructField> _insertPadding(List<StructField> fields, int totalSize) {
    if (fields.isEmpty || totalSize <= 0) return fields;

    // Skip for unions (all fields at offset 0)
    final isUnion = fields.length >= 2 &&
        fields.every((f) => f.offset == 0);
    if (isUnion) return fields;

    final result = <StructField>[];
    int cursor = 0;

    for (final f in fields) {
      if (f.offset > cursor) {
        // Gap before this field — insert padding
        result.add(StructField(
          name: '[pad]',
          typeName: '[pad]',
          offset: cursor,
          size: f.offset - cursor,
          isPadding: true,
        ));
      }
      result.add(f);
      cursor = f.offset + f.size;
    }

    // Trailing padding
    if (cursor < totalSize) {
      result.add(StructField(
        name: '[pad]',
        typeName: '[pad]',
        offset: cursor,
        size: totalSize - cursor,
        isPadding: true,
      ));
    }

    return result;
  }

  /// For Array fields, populate children with element sub-fields.
  void _populateArrayChildren(List<StructField> fields) {
    for (int idx = 0; idx < fields.length; idx++) {
      final f = fields[idx];
      if (f.isArray && f.size > 0) {
        // Parse element type and compute stride. e.g. "Array<Int32>" → Int32, stride 4
        final match = RegExp(r'Array<(\w+)>').firstMatch(f.typeName);
        if (match != null) {
          final elemType = match.group(1)!;
          final stride = _mapToFfiType(elemType).size;
          if (stride > 0) {
            final count = f.size ~/ stride;
            final children = <StructField>[];
            for (int i = 0; i < count; i++) {
              children.add(StructField(
                name: '[$i]',
                typeName: elemType,
                offset: f.offset + i * stride,
                size: stride,
              ));
            }
            _log('    ✓ Array ${f.name}: $count elements of $elemType');
            fields[idx] = StructField(
              name: f.name,
              typeName: f.typeName,
              offset: f.offset,
              size: f.size,
              children: children,
            );
          }
        }
      }
    }
  }

  /// Create a synthetic layout for known primitive FFI types.
  /// Returns null if the type isn't a recognized primitive.
  ({List<StructField> fields, int totalSize})? _syntheticPrimitiveLayout(
      String typeName) {
    // Check for Pointer<Pointer> (double indirection)
    if (typeName == 'Pointer<Pointer>' || typeName.startsWith('Pointer<Pointer')) {
      return (
        fields: [
          StructField(
            name: 'value',
            typeName: 'Pointer',
            offset: 0,
            size: 8,
          ),
        ],
        totalSize: 8,
      );
    }

    // Check for known FFI primitive types
    final mapped = _mapToFfiType(typeName);
    if (const {
      'Int8', 'Int16', 'Int32', 'Int64',
      'Uint8', 'Uint16', 'Uint32', 'Uint64',
      'Float', 'Double',
    }.contains(mapped.typeName)) {
      return (
        fields: [
          StructField(
            name: 'value',
            typeName: mapped.typeName,
            offset: 0,
            size: mapped.size,
          ),
        ],
        totalSize: mapped.size,
      );
    }

    return null; // Not a primitive type — let struct extraction handle it
  }
}
