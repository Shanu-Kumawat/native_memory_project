// Data models for native pointer inspection.

/// Category for grouping pointers in the sidebar.
enum PointerCategory { struct, union, advanced, raw, error }

/// Represents a single field within a native struct.
class StructField {
  final String name;
  final String typeName;
  final int offset;
  final int size;
  final dynamic value;
  final bool isReadable;
  final bool isPadding;
  final List<StructField>? children;
  bool isExpanded;

  StructField({
    required this.name,
    required this.typeName,
    required this.offset,
    required this.size,
    this.value,
    this.isReadable = true,
    this.isPadding = false,
    this.children,
    this.isExpanded = false,
  });

  bool get hasChildren => children != null && children!.isNotEmpty;
  bool get isPointer => typeName.startsWith('Pointer');
  bool get isArray => typeName.startsWith('Array');
  bool get isStruct =>
      !isPadding &&
      !isPointer &&
      !isArray &&
      !_primitiveTypes.contains(typeName);

  static const _primitiveTypes = {
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
    'Bool',
  };
}

/// Represents all the information about a native pointer.
class PointerData {
  final String variableName;
  final String nativeType;
  final int address;
  final int structSize;
  final List<StructField> fields;
  final List<int>? rawBytes;
  final String? error;

  const PointerData({
    required this.variableName,
    required this.nativeType,
    required this.address,
    required this.structSize,
    required this.fields,
    this.rawBytes,
    this.error,
  });

  bool get isNull => address == 0;
  bool get hasError => error != null;
  bool get hasRawBytes => rawBytes != null && rawBytes!.isNotEmpty;
  bool get hasFields => fields.where((f) => !f.isPadding).isNotEmpty;
  bool get hasPointerFields =>
      fields.any((f) => f.typeName.startsWith('Pointer'));

  /// True if struct has nested structs, arrays, or pointer fields worth graphing.
  bool get hasInterestingStructure =>
      fields.any((f) => f.isPointer || f.isStruct || f.isArray);

  String get addressHex => '0x${address.toRadixString(16).padLeft(12, '0')}';

  PointerCategory get category {
    if (hasError || (nativeType == 'Unknown' && !hasRawBytes)) {
      return PointerCategory.error;
    }
    final isBytePointer = nativeType == 'Uint8' || nativeType == 'Int8';
    final isOpaqueLike =
        nativeType == 'Void' ||
        nativeType.contains('Opaque') ||
        nativeType.contains('Handle');
    if (nativeType == 'Unknown' ||
        isBytePointer ||
        isOpaqueLike ||
        (!hasFields && hasRawBytes)) {
      return PointerCategory.raw;
    }

    // Detect union: multiple non-padding fields all at offset 0
    final realFields = fields.where((f) => !f.isPadding).toList();
    if (realFields.length >= 2 && realFields.every((f) => f.offset == 0)) {
      return PointerCategory.union;
    }

    // Advanced classification is intentionally structure-based, not name-based.
    // This avoids brittle string heuristics like nativeType.contains('Buffer').
    if (_isAdvancedByStructure(realFields)) {
      return PointerCategory.advanced;
    }
    return PointerCategory.struct;
  }

  bool _isAdvancedByStructure(List<StructField> realFields) {
    // Explicit pointer-to-pointer primitive/native type, e.g. Pointer<Int32>.
    if (nativeType.startsWith('Pointer<')) {
      return true;
    }

    final pointerFields = realFields.where((f) => f.isPointer).toList();
    final hasArrayField = realFields.any((f) => f.isArray);

    if (hasArrayField) return true; // WithArray
    if (pointerFields.length >= 2) return true; // BiNode-like graph nodes

    // Buffer-like pattern: exactly one pointer field plus an integer
    // count/length/size field used to interpret pointed memory.
    final hasSizeLikeField = realFields.any(
      (f) =>
          _isIntegerType(f.typeName) &&
          _sizeLikeFieldNames.contains(f.name.toLowerCase()),
    );
    final pointsToByteLike = pointerFields.any(
      (f) =>
          f.typeName.contains('Pointer<Uint8>') ||
          f.typeName.contains('Pointer<Int8>') ||
          f.typeName.contains('Pointer<Void>'),
    );
    if (pointerFields.length == 1 && hasSizeLikeField && pointsToByteLike) {
      return true; // Buffer(length + Pointer<Uint8>)
    }

    return false;
  }

  static const _sizeLikeFieldNames = {'length', 'len', 'size', 'count'};

  bool _isIntegerType(String typeName) =>
      typeName == 'Int8' ||
      typeName == 'Int16' ||
      typeName == 'Int32' ||
      typeName == 'Int64' ||
      typeName == 'Uint8' ||
      typeName == 'Uint16' ||
      typeName == 'Uint32' ||
      typeName == 'Uint64' ||
      typeName == 'int';

  PointerData copyWith({
    String? variableName,
    String? nativeType,
    int? address,
    int? structSize,
    List<StructField>? fields,
    List<int>? rawBytes,
    String? error,
  }) {
    return PointerData(
      variableName: variableName ?? this.variableName,
      nativeType: nativeType ?? this.nativeType,
      address: address ?? this.address,
      structSize: structSize ?? this.structSize,
      fields: fields ?? this.fields,
      rawBytes: rawBytes ?? this.rawBytes,
      error: error,
    );
  }
}

/// Connection state for the VM Service.
enum ConnectionState { disconnected, connecting, connected, error }

/// A timestamped snapshot of all pointer states at a given scan.
class MemorySnapshot {
  final List<PointerData> pointers;
  final DateTime timestamp;

  const MemorySnapshot({required this.pointers, required this.timestamp});
}

/// Overall state of the inspector.
class InspectorState {
  final ConnectionState connectionState;
  final String? vmServiceUri;
  final List<PointerData> pointers;
  final List<MemorySnapshot> snapshotHistory;
  final String? errorMessage;
  final String? vmName;
  final String? vmVersion;
  final int selectedPointerIndex;
  final List<int> navigationHistory;

  const InspectorState({
    this.connectionState = ConnectionState.disconnected,
    this.vmServiceUri,
    this.pointers = const [],
    this.snapshotHistory = const [],
    this.errorMessage,
    this.vmName,
    this.vmVersion,
    this.selectedPointerIndex = -1,
    this.navigationHistory = const [],
  });

  PointerData? get selectedPointer =>
      selectedPointerIndex >= 0 && selectedPointerIndex < pointers.length
      ? pointers[selectedPointerIndex]
      : null;

  bool get canGoBack => navigationHistory.isNotEmpty;

  int get readableCount =>
      pointers.where((p) => p.hasRawBytes && !p.hasError).length;
  int get errorCount => pointers.where((p) => p.hasError).length;
  int get totalBytesRead =>
      pointers.fold<int>(0, (sum, p) => sum + (p.rawBytes?.length ?? 0));

  InspectorState copyWith({
    ConnectionState? connectionState,
    String? vmServiceUri,
    List<PointerData>? pointers,
    List<MemorySnapshot>? snapshotHistory,
    String? errorMessage,
    String? vmName,
    String? vmVersion,
    int? selectedPointerIndex,
    List<int>? navigationHistory,
  }) {
    return InspectorState(
      connectionState: connectionState ?? this.connectionState,
      vmServiceUri: vmServiceUri ?? this.vmServiceUri,
      pointers: pointers ?? this.pointers,
      snapshotHistory: snapshotHistory ?? this.snapshotHistory,
      errorMessage: errorMessage,
      vmName: vmName ?? this.vmName,
      vmVersion: vmVersion ?? this.vmVersion,
      selectedPointerIndex: selectedPointerIndex ?? this.selectedPointerIndex,
      navigationHistory: navigationHistory ?? this.navigationHistory,
    );
  }
}
