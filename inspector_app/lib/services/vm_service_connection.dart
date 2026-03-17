/// VM Service connection manager for live pointer inspection.
///
/// Uses VM-provided metadata only:
/// - BoundVariable.declaredType for pointer target type
/// - Pointer instance JSON (kind/nativeAddress/nativeType)
/// - _readNativeMemory RPC for safe native memory reads

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

    return (vmName: vm.name ?? 'Dart VM', vmVersion: vm.version ?? 'unknown');
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
      await _service!.callMethod(
        '_readNativeMemory',
        isolateId: _isolateId,
        args: {'address': '1', 'count': '0'},
      );
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
              final cls =
                  await _service!.getObject(_isolateId!, classRef.id!) as Class;

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

  /// Extract `T` from a declared type string like `Pointer<T>` or
  /// `Pointer<T>?`.
  String? _extractNativeTypeFromDeclaredType(String? declaredTypeName) {
    if (declaredTypeName == null || declaredTypeName.isEmpty) {
      return null;
    }
    final raw = declaredTypeName.trim();
    final match = RegExp(r'^Pointer<\s*(.+?)\s*>\??$').firstMatch(raw);
    final inner = match?.group(1)?.trim();
    if (inner == null || inner.isEmpty || inner == 'Never') {
      return null;
    }
    return inner;
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
          _log(
            'Frame $fi: ${frame.function?.name ?? "?"} '
            '(${vars.length} vars)',
          );

          for (final variable in vars) {
            final value = variable.value;
            if (value is InstanceRef) {
              final className = value.classRef?.name ?? '';
              final declaredTypeName = variable.declaredType?.name;
              _log('  var "${variable.name}": class=$className');
              if (declaredTypeName != null) {
                _log('    declaredType: $declaredTypeName');
              }
              final pointerData = await _tryExtractPointer(
                variable.name ?? 'unknown',
                value,
                declaredTypeName: declaredTypeName,
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
              final field =
                  await _service!.getObject(_isolateId!, fieldRef.id!) as Field;
              final value = field.staticValue;
              if (value is InstanceRef) {
                final pointerData = await _tryExtractPointer(
                  fieldRef.name ?? 'unknown',
                  value,
                  declaredTypeName: fieldRef.declaredType?.name,
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
          _log(
            'Reading $readSize bytes at 0x${p.address.toRadixString(16)} '
            'for ${p.variableName}...',
          );
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
    InstanceRef ref, {
    String? declaredTypeName,
  }) async {
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

      _log('    final address: 0x${address.toRadixString(16)}');

      // ── Extract type ──

      // Strategy -1: Declared variable type from protocol metadata
      // (preferred, robust against Pointer<T> runtime type erasure).
      final declaredNativeType = _extractNativeTypeFromDeclaredType(
        declaredTypeName,
      );
      if (declaredNativeType != null) {
        nativeType = declaredNativeType;
        _log(
          '    ✓ Type resolved via declaredType: $nativeType '
          '(from $declaredTypeName)',
        );
      } else if (declaredTypeName != null && declaredTypeName.isNotEmpty) {
        _log('    declaredType present but not usable: $declaredTypeName');
      }

      // Detect enriched protocol via kind field
      final instanceKindFromJson = instanceJson?['kind'];
      if (instanceKindFromJson == 'Pointer') {
        _hasEnrichedProtocol = true;
        _log('    ✓ Enriched protocol detected (kind: Pointer)');
      }

      // Secondary metadata source: enriched pointer JSON `nativeType`.
      if (nativeType == 'Unknown' &&
          instanceJson != null &&
          instanceJson.containsKey('nativeType')) {
        final ntData = instanceJson['nativeType'];
        String? extractedName;

        if (ntData is Map) {
          // Full Type JSON object: {"type": "@Type", "name": "Never", ...}
          extractedName = ntData['name'] as String?;
          _log(
            '    nativeType from protocol: $extractedName '
            '(class: ${ntData['type']})',
          );
        } else if (ntData is String) {
          extractedName = ntData;
          _log('    nativeType from protocol: $extractedName (string)');
        }

        if (extractedName != null && extractedName != 'Never') {
          nativeType = extractedName;
          _log('    ✓ Type resolved via enriched protocol: $nativeType');
        } else if (extractedName == 'Never') {
          _log(
            '    nativeType is "Never" (FFI type erasure — '
            'compiler strips Pointer<T> → Pointer<Never>)',
          );
        }
      }
      if (nativeType == 'Unknown') {
        _log('    nativeType unresolved (no usable declaredType/nativeType)');
      } else {
        _log('    nativeType: $nativeType');
      }

      // ── Extract struct layout ──
      final layout = await _extractStructFields(nativeType);
      final rawFields = layout.fields;
      final structSize = layout.totalSize > 0
          ? layout.totalSize
          : (rawFields.isNotEmpty
                ? rawFields.last.offset + rawFields.last.size
                : 0);
      _log(
        '    struct layout: ${rawFields.length} fields, '
        'total size: $structSize bytes (sizeOf=${layout.totalSize})',
      );

      // ── Insert synthetic padding fields ──
      final fields = _insertPadding(rawFields, structSize);

      // ── Populate children for arrays and nested structs ──
      await _populateChildren(fields);

      return PointerData(
        variableName: varName,
        nativeType: nativeType,
        address: address,
        structSize: structSize,
        fields: fields,
        error: address == 0
            ? 'Address unavailable from VM protocol'
            : (nativeType == 'Unknown'
                  ? 'Type unavailable from VM metadata (declaredType/nativeType)'
                  : null),
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
        _log(
          '  Calling _readNativeMemory(0x${address.toRadixString(16)}, $count)',
        );
        final response = await _service!.callMethod(
          '_readNativeMemory',
          isolateId: _isolateId,
          args: {'address': address.toString(), 'count': count.toString()},
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
    return null;
  }

  // ─── Struct Field Extraction ────────────────────────────────────────

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
    String typeName,
  ) async {
    if (_service == null || _isolateId == null) {
      return (fields: <StructField>[], totalSize: 0);
    }
    if (typeName == 'Unknown') {
      _log('    Cannot extract fields: type is Unknown');
      return (fields: <StructField>[], totalSize: 0);
    }

    // Handle internal primitive FFI types mapping
    final primitiveLayout = _primitiveLayout(typeName);
    if (primitiveLayout != null) {
      _log('    ✓ Layout generated for primitive type $typeName');
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
              final cls =
                  await _service!.getObject(_isolateId!, classRef.id!) as Class;

              final result = await _extractFieldsFromStruct(cls);
              if (result.fields.isNotEmpty) {
                _log(
                  '    ✓ Extracted ${result.fields.length} fields '
                  'for $typeName (sizeOf=${result.totalSize})',
                );
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
  Future<({List<StructField> fields, int totalSize})> _extractFieldsFromStruct(
    Class cls,
  ) async {
    final className = cls.name ?? '';
    final classJson = cls.json;

    // ── Scan all functions ──
    final allFuncNames = <String>[];
    final offsetOfNames = <String>{}; // fields that have #offsetOf
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
              0,
              funcName.length - '#offsetOf'.length,
            );
            offsetOfNames.add(fieldName);
            _log('      #offsetOf → field: "$fieldName"');
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

    // ── Determine field names ──
    // Priority 1: #offsetOf entries (authoritative — FFI transformer signal)
    // Priority 2: Class.fields (for structs that keep field declarations)
    List<String> fieldNames;

    if (offsetOfNames.isNotEmpty) {
      // Use #offsetOf as authoritative field list
      fieldNames = offsetOfNames.toList();
      _log('    Using #offsetOf-based field list: $fieldNames');
    } else {
      // Use Class.fields only (no heuristic setter matching).
      fieldNames = <String>[];

      for (final fieldRef in cls.fields ?? <FieldRef>[]) {
        final name = fieldRef.name ?? '';
        if (name.isEmpty) continue;
        if (fieldRef.isStatic == true || fieldRef.isConst == true) continue;
        if (name.startsWith('#') || name.startsWith('_')) continue;
        if (!fieldNames.contains(name)) fieldNames.add(name);
      }
      _log('    Using Class.fields-based field list: $fieldNames');
    }

    // Log Class.fields for diagnosis
    _log('    Class $className fields:');
    for (final fieldRef in cls.fields ?? <FieldRef>[]) {
      final name = fieldRef.name ?? '?';
      final typeName = fieldRef.declaredType?.name ?? '?';
      final isStatic = fieldRef.isStatic ?? false;
      final isConst = fieldRef.isConst ?? false;
      _log(
        '      "$name" type=$typeName '
        'static=$isStatic const=$isConst',
      );
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
          classId,
          '${fieldName}#offsetOf',
        );
        if (offset >= 0) {
          evaluatedOffsets[fieldName] = offset;
          _log('    ${fieldName}#offsetOf = $offset');
        }
      }
    }

    if (totalSize == 0) {
      _log('    #sizeOf unavailable; using computed size');
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
          final func = await _service!.getObject(_isolateId!, funcId) as Func;
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

    // ── Build field layout from VM metadata only ──

    // Check for union layout: all fields at offset 0
    final isUnion =
        evaluatedOffsets.isNotEmpty &&
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

      fields.add(
        StructField(name: name, typeName: typeName, offset: offset, size: size),
      );

      if (!isUnion) {
        computedOffset = offset + size;
      }
    }

    if (totalSize > 0 && !isUnion && computedOffset != totalSize) {
      _log(
        '    ⚠ Size mismatch: computed=$computedOffset vs '
        'sizeOf=$totalSize',
      );
    }

    // Use totalSize from sizeOf if available, else computed
    final finalSize = totalSize > 0
        ? totalSize
        : (fields.isEmpty
              ? 0
              : fields
                    .map((f) => f.offset + f.size)
                    .reduce((a, b) => a > b ? a : b));
    _log(
      '    ✓ Built layout: ${fields.length} fields, '
      'totalSize=$finalSize',
    );
    for (final f in fields) {
      _log(
        '      ${f.name}: ${f.typeName} '
        'offset=${f.offset} size=${f.size}',
      );
    }

    return (fields: fields, totalSize: finalSize);
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
        _isolateId!,
        targetId,
        getterName,
        [],
      );

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

      _log(
        '    $getterName invoke: unexpected response: '
        '${result.json?['type'] ?? result.runtimeType}',
      );
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

  /// Map a Dart/FFI/internal type name to its FFI type name and size.
  ({String typeName, int size}) _mapToFfiType(String rawType) {
    return switch (rawType) {
      'int' ||
      'Int32' ||
      'Uint32' => (typeName: rawType == 'int' ? 'Int32' : rawType, size: 4),
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

  /// Insert synthetic padding fields between struct fields where gaps exist.
  List<StructField> _insertPadding(List<StructField> fields, int totalSize) {
    if (fields.isEmpty || totalSize <= 0) return fields;

    // Skip for unions (all fields at offset 0)
    final isUnion = fields.length >= 2 && fields.every((f) => f.offset == 0);
    if (isUnion) return fields;

    final result = <StructField>[];
    int cursor = 0;

    for (final f in fields) {
      if (f.offset > cursor) {
        // Gap before this field — insert padding
        result.add(
          StructField(
            name: '[pad]',
            typeName: '[pad]',
            offset: cursor,
            size: f.offset - cursor,
            isPadding: true,
          ),
        );
      }
      result.add(f);
      cursor = f.offset + f.size;
    }

    // Trailing padding
    if (cursor < totalSize) {
      result.add(
        StructField(
          name: '[pad]',
          typeName: '[pad]',
          offset: cursor,
          size: totalSize - cursor,
          isPadding: true,
        ),
      );
    }

    return result;
  }

  /// Populate children for array and nested struct fields.
  /// Arrays get element sub-fields; nested structs get their own field layout.
  Future<void> _populateChildren(List<StructField> fields) async {
    for (int idx = 0; idx < fields.length; idx++) {
      final f = fields[idx];

      // ── Array fields: create element children ──
      if (f.isArray && f.size > 0) {
        final match = RegExp(r'Array<(\w+)>').firstMatch(f.typeName);
        if (match != null) {
          final elemType = match.group(1)!;
          final stride = _mapToFfiType(elemType).size;
          if (stride > 0) {
            final count = f.size ~/ stride;
            final children = <StructField>[];
            for (int i = 0; i < count; i++) {
              children.add(
                StructField(
                  name: '[$i]',
                  typeName: elemType,
                  offset: f.offset + i * stride,
                  size: stride,
                ),
              );
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

      // ── Nested struct fields: extract their own layout ──
      if (f.isStruct && _structClassNames.contains(f.typeName)) {
        try {
          final nestedLayout = await _extractStructFields(f.typeName);
          if (nestedLayout.fields.isNotEmpty) {
            // Adjust child offsets to be absolute (relative to parent struct)
            final children = nestedLayout.fields.map((child) {
              return StructField(
                name: child.name,
                typeName: child.typeName,
                offset: f.offset + child.offset,
                size: child.size,
                isPadding: child.isPadding,
                children: child.children,
              );
            }).toList();
            _log(
              '    ✓ Nested struct ${f.name}: '
              '${children.where((c) => !c.isPadding).length} fields',
            );
            fields[idx] = StructField(
              name: f.name,
              typeName: f.typeName,
              offset: f.offset,
              size: f.size,
              children: children,
            );
          }
        } catch (e) {
          _log('    ✗ Failed to expand nested struct ${f.name}: $e');
        }
      }
    }
  }

  /// Creates a single-field layout for known primitive FFI types.
  ({List<StructField> fields, int totalSize})? _primitiveLayout(
    String typeName,
  ) {
    if (typeName == 'Pointer<Pointer>' ||
        typeName.startsWith('Pointer<Pointer')) {
      return (
        fields: [
          StructField(name: 'value', typeName: 'Pointer', offset: 0, size: 8),
        ],
        totalSize: 8,
      );
    }
    final mapped = _mapToFfiType(typeName);
    if (const {
      'Int8',
      'Int16',
      'Int32',
      'Int64',
      'Uint8',
      'Uint16',
      'Uint32',
      'Uint64',
      'Float',
      'Double',
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
    if (typeName.startsWith('Pointer<')) {
      return (
        fields: [
          StructField(name: 'value', typeName: 'Pointer', offset: 0, size: 8),
        ],
        totalSize: 8,
      );
    }
    return null;
  }
}
