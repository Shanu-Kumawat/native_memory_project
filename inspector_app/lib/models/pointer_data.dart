/// Data models for native pointer inspection.

/// Represents a single field within a native struct.
class StructField {
  final String name;
  final String typeName;
  final int offset;
  final int size;
  final dynamic value;
  final bool isReadable;

  const StructField({
    required this.name,
    required this.typeName,
    required this.offset,
    required this.size,
    this.value,
    this.isReadable = true,
  });
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
  String get addressHex => '0x${address.toRadixString(16).padLeft(12, '0')}';

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

  const InspectorState({
    this.connectionState = ConnectionState.disconnected,
    this.vmServiceUri,
    this.pointers = const [],
    this.errorMessage,
    this.vmName,
    this.vmVersion,
  });

  InspectorState copyWith({
    ConnectionState? connectionState,
    String? vmServiceUri,
    List<PointerData>? pointers,
    String? errorMessage,
    String? vmName,
    String? vmVersion,
  }) {
    return InspectorState(
      connectionState: connectionState ?? this.connectionState,
      vmServiceUri: vmServiceUri ?? this.vmServiceUri,
      pointers: pointers ?? this.pointers,
      errorMessage: errorMessage,
      vmName: vmName ?? this.vmName,
      vmVersion: vmVersion ?? this.vmVersion,
    );
  }
}
