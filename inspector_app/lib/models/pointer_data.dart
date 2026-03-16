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
    'Int8', 'Int16', 'Int32', 'Int64',
    'Uint8', 'Uint16', 'Uint32', 'Uint64',
    'Float', 'Double', 'Bool',
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
  String get addressHex => '0x${address.toRadixString(16).padLeft(12, '0')}';

  PointerCategory get category {
    if (hasError || (nativeType == 'Unknown' && !hasRawBytes)) {
      return PointerCategory.error;
    }
    if (nativeType == 'Unknown') return PointerCategory.raw;
    if (nativeType.contains('Union') || _unionTypes.contains(nativeType)) {
      return PointerCategory.union;
    }
    if (fields.any((f) => f.isArray) ||
        nativeType.contains('Buffer') ||
        nativeType.contains('Array')) {
      return PointerCategory.advanced;
    }
    return PointerCategory.struct;
  }

  // Track known union types by checking if multiple fields share offset 0
  static final Set<String> _unionTypes = {};
  static void markAsUnion(String typeName) => _unionTypes.add(typeName);

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
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Overall state of the inspector.
class InspectorState {
  final ConnectionState connectionState;
  final String? vmServiceUri;
  final List<PointerData> pointers;
  final String? errorMessage;
  final String? vmName;
  final String? vmVersion;
  final int selectedPointerIndex;
  final List<int> navigationHistory;

  const InspectorState({
    this.connectionState = ConnectionState.disconnected,
    this.vmServiceUri,
    this.pointers = const [],
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
  int get totalBytesRead => pointers.fold<int>(
      0, (sum, p) => sum + (p.rawBytes?.length ?? 0));

  InspectorState copyWith({
    ConnectionState? connectionState,
    String? vmServiceUri,
    List<PointerData>? pointers,
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
      errorMessage: errorMessage,
      vmName: vmName ?? this.vmName,
      vmVersion: vmVersion ?? this.vmVersion,
      selectedPointerIndex:
          selectedPointerIndex ?? this.selectedPointerIndex,
      navigationHistory: navigationHistory ?? this.navigationHistory,
    );
  }
}
