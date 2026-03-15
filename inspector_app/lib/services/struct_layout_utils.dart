/// Extracted pure-logic utilities for struct layout computation.
///
/// These functions are factored out of VmServiceConnection so they can
/// be tested independently without VM Service dependencies.

import 'dart:typed_data';

import '../models/pointer_data.dart';

/// Maps a Dart/FFI type name to its FFI type name and size in bytes.
///
/// The Dart return types (int, double) are ambiguous w.r.t. FFI types:
///   int → Int8, Int16, Int32, Int64, Uint8, Uint16, Uint32, Uint64
///   double → Float, Double
///
/// This function provides a default mapping when no sizeOf reconciliation
/// is possible.
({String typeName, int size}) mapToFfiType(String rawType) {
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
    'X0' => (typeName: 'Double', size: 8),
    _ => (typeName: rawType, size: 8),  // Default to pointer size
  };
}

/// Returns the list of candidate FFI types for an ambiguous Dart type.
///
/// For `int`, the candidates are all integer types that could fit.
/// For `double`, the candidates are Float (4 bytes) and Double (8 bytes).
/// For known FFI types, returns only that type.
List<({String typeName, int size})> getCandidateTypes(String dartType) {
  return switch (dartType) {
    'int' => [
      (typeName: 'Int32', size: 4),
      (typeName: 'Int64', size: 8),
      (typeName: 'Int8', size: 1),
      (typeName: 'Int16', size: 2),
      (typeName: 'Uint8', size: 1),
      (typeName: 'Uint16', size: 2),
      (typeName: 'Uint32', size: 4),
      (typeName: 'Uint64', size: 8),
    ],
    'double' => [
      (typeName: 'Float', size: 4),
      (typeName: 'Double', size: 8),
    ],
    _ => [mapToFfiType(dartType)],
  };
}

/// Recursively try type combinations to find one matching sizeOf.
///
/// For each field, tries all candidate types (e.g., Int32 and Int64
/// for an `int` return type) and computes ABI-aligned offsets.
/// Returns the first combination whose total size matches [targetSize].
List<StructField>? reconcileLayout(
  List<String> fieldNames,
  List<List<({String typeName, int size})>> typeOptions,
  int targetSize,
  int fieldIndex,
  List<({String typeName, int size})> chosen,
) {
  if (fieldIndex == fieldNames.length) {
    // Compute total size including ABI alignment
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

    if (offset == targetSize) return fields;
    return null;
  }

  for (final candidate in typeOptions[fieldIndex]) {
    final result = reconcileLayout(
      fieldNames, typeOptions, targetSize,
      fieldIndex + 1, [...chosen, candidate],
    );
    if (result != null) return result;
  }

  return null;
}

/// Decode a field value from raw bytes based on its FFI type.
///
/// Returns a human-readable string representation of the value.
String decodeFieldValue(
  List<int> rawBytes,
  int offset,
  String typeName,
  int size,
) {
  if (offset + size > rawBytes.length) {
    return '<out of bounds>';
  }

  final byteData = ByteData.sublistView(
    Uint8List.fromList(rawBytes.sublist(offset, offset + size)),
  );

  return switch (typeName) {
    'Int8' => byteData.getInt8(0).toString(),
    'Uint8' || 'Bool' => byteData.getUint8(0).toString(),
    'Int16' => byteData.getInt16(0, Endian.little).toString(),
    'Uint16' => byteData.getUint16(0, Endian.little).toString(),
    'Int32' => byteData.getInt32(0, Endian.little).toString(),
    'Uint32' => byteData.getUint32(0, Endian.little).toString(),
    'Int64' => byteData.getInt64(0, Endian.little).toString(),
    'Uint64' => byteData.getUint64(0, Endian.little).toString(),
    'Float' => byteData.getFloat32(0, Endian.little).toStringAsFixed(6),
    'Double' => byteData.getFloat64(0, Endian.little).toStringAsFixed(6),
    _ when typeName.startsWith('Pointer') =>
      '0x${byteData.getUint64(0, Endian.little).toRadixString(16)}',
    _ => rawBytes.sublist(offset, offset + size)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' '),
  };
}

/// Compute ABI-aligned offset for a field of given size.
int alignOffset(int currentOffset, int fieldSize) {
  if (fieldSize > 0 && currentOffset % fieldSize != 0) {
    return ((currentOffset ~/ fieldSize) + 1) * fieldSize;
  }
  return currentOffset;
}
