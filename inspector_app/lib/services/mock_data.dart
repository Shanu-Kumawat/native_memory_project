/// Provides mock pointer data for demonstration when no live VM is available.

import '../models/pointer_data.dart';

class MockDataProvider {
  static List<PointerData> getMockPointers() {
    return [
      PointerData(
        variableName: 'myStruct',
        nativeType: 'MyStruct',
        address: 0x7f9c3d001400,
        structSize: 16,
        fields: [
          const StructField(
            name: 'id',
            typeName: 'Int32',
            offset: 0,
            size: 4,
            value: 42,
          ),
          const StructField(
            name: 'value',
            typeName: 'Float',
            offset: 4,
            size: 4,
            value: 3.140000104904175,
          ),
          const StructField(
            name: 'timestamp',
            typeName: 'Int64',
            offset: 8,
            size: 8,
            value: 1710100000000,
          ),
        ],
        rawBytes: [
          // id = 42 (little-endian Int32)
          0x2a, 0x00, 0x00, 0x00,
          // value = 3.14 (little-endian Float)
          0xc3, 0xf5, 0x48, 0x40,
          // timestamp (little-endian Int64)
          0x00, 0x10, 0xa5, 0xd4, 0xe8, 0x00, 0x00, 0x00,
        ],
      ),
      PointerData(
        variableName: 'point',
        nativeType: 'Point',
        address: 0x7f9c3d002800,
        structSize: 16,
        fields: [
          const StructField(
            name: 'x',
            typeName: 'Double',
            offset: 0,
            size: 8,
            value: 1.5,
          ),
          const StructField(
            name: 'y',
            typeName: 'Double',
            offset: 8,
            size: 8,
            value: 2.7,
          ),
        ],
        rawBytes: [
          // x = 1.5 (little-endian Double)
          0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf8, 0x3f,
          // y = 2.7 (little-endian Double)
          0x9a, 0x99, 0x99, 0x99, 0x99, 0x99, 0x05, 0x40,
        ],
      ),
      PointerData(
        variableName: 'node1',
        nativeType: 'Node',
        address: 0x7f9c3d003c00,
        structSize: 16,
        fields: [
          const StructField(
            name: 'data',
            typeName: 'Int32',
            offset: 0,
            size: 4,
            value: 100,
          ),
          const StructField(
            name: 'next',
            typeName: 'Pointer<Node>',
            offset: 8,
            size: 8,
            value: '0x7f9c3d003c10',
          ),
        ],
        rawBytes: [
          // data = 100 (little-endian Int32)
          0x64, 0x00, 0x00, 0x00,
          // padding
          0x00, 0x00, 0x00, 0x00,
          // next pointer (little-endian)
          0x10, 0x3c, 0x00, 0x3d, 0x9c, 0x7f, 0x00, 0x00,
        ],
      ),
      // Null pointer example
      const PointerData(
        variableName: 'nullPtr',
        nativeType: 'MyStruct',
        address: 0x0,
        structSize: 16,
        fields: [],
        error: 'null pointer (address 0)',
      ),
    ];
  }
}
