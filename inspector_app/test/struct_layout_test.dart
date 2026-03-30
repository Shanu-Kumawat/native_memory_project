import 'package:flutter_test/flutter_test.dart';

import 'package:pointer_inspector/models/pointer_data.dart';

void main() {
  group('StructField flags', () {
    test('primitive vs pointer vs array vs struct classification', () {
      final intField = StructField(
        name: 'id',
        typeName: 'Int32',
        offset: 0,
        size: 4,
      );
      final ptrField = StructField(
        name: 'next',
        typeName: 'Pointer<Node>',
        offset: 8,
        size: 8,
      );
      final arrayField = StructField(
        name: 'values',
        typeName: 'Array<Int32>',
        offset: 4,
        size: 16,
      );
      final nestedStruct = StructField(
        name: 'inner',
        typeName: 'Point',
        offset: 8,
        size: 16,
      );
      final pad = StructField(
        name: '[pad]',
        typeName: '[pad]',
        offset: 4,
        size: 4,
        isPadding: true,
      );

      expect(intField.isPointer, isFalse);
      expect(intField.isArray, isFalse);
      expect(intField.isStruct, isFalse);

      expect(ptrField.isPointer, isTrue);
      expect(ptrField.isArray, isFalse);
      expect(ptrField.isStruct, isFalse);

      expect(arrayField.isPointer, isFalse);
      expect(arrayField.isArray, isTrue);
      expect(arrayField.isStruct, isFalse);

      expect(nestedStruct.isPointer, isFalse);
      expect(nestedStruct.isArray, isFalse);
      expect(nestedStruct.isStruct, isTrue);

      expect(pad.isStruct, isFalse);
    });
  });

  group('PointerData core behavior', () {
    test('addressHex formatting', () {
      final data = PointerData(
        variableName: 'ptr',
        nativeType: 'MyStruct',
        address: 0x1234,
        structSize: 16,
        fields: const [],
      );
      expect(data.addressHex, '0x000000001234');
    });

    test('isNull and hasRawBytes', () {
      final nullPtr = PointerData(
        variableName: 'p',
        nativeType: 'Unknown',
        address: 0,
        structSize: 0,
        fields: const [],
      );
      final withBytes = PointerData(
        variableName: 'buf',
        nativeType: 'Uint8',
        address: 0x1000,
        structSize: 1,
        fields: const [],
        rawBytes: [0xAA],
      );
      expect(nullPtr.isNull, isTrue);
      expect(nullPtr.hasRawBytes, isFalse);
      expect(withBytes.isNull, isFalse);
      expect(withBytes.hasRawBytes, isTrue);
    });

    test('hasFields ignores padding-only entries', () {
      final onlyPadding = PointerData(
        variableName: 'p',
        nativeType: 'MyStruct',
        address: 1,
        structSize: 8,
        fields: [
          StructField(
            name: '[pad]',
            typeName: '[pad]',
            offset: 0,
            size: 8,
            isPadding: true,
          ),
        ],
      );
      expect(onlyPadding.hasFields, isFalse);
    });

    test('hasPointerFields and hasInterestingStructure', () {
      final data = PointerData(
        variableName: 'node',
        nativeType: 'Node',
        address: 1,
        structSize: 16,
        fields: [
          StructField(name: 'data', typeName: 'Int32', offset: 0, size: 4),
          StructField(
            name: 'next',
            typeName: 'Pointer<Node>',
            offset: 8,
            size: 8,
          ),
        ],
      );
      expect(data.hasPointerFields, isTrue);
      expect(data.hasInterestingStructure, isTrue);
    });
  });

  group('PointerData.category classification', () {
    test('error category when has error', () {
      final p = PointerData(
        variableName: 'bad',
        nativeType: 'MyStruct',
        address: 0xDEADBEEF,
        structSize: 0,
        fields: const [],
        error: 'read failed',
      );
      expect(p.category, PointerCategory.error);
    });

    test('error category for Unknown without bytes', () {
      final p = PointerData(
        variableName: 'u',
        nativeType: 'Unknown',
        address: 123,
        structSize: 0,
        fields: const [],
      );
      expect(p.category, PointerCategory.error);
    });

    test('raw category for byte pointers and unknown with bytes', () {
      final bytePtr = PointerData(
        variableName: 'raw',
        nativeType: 'Uint8',
        address: 0x1000,
        structSize: 1,
        fields: const [],
        rawBytes: [0, 1, 2],
      );
      final unknownWithBytes = PointerData(
        variableName: 'u',
        nativeType: 'Unknown',
        address: 0x1001,
        structSize: 0,
        fields: const [],
        rawBytes: [0xAA, 0xBB],
      );
      expect(bytePtr.category, PointerCategory.raw);
      expect(unknownWithBytes.category, PointerCategory.raw);
    });

    test('raw category for opaque/handle-like native types', () {
      final opaque = PointerData(
        variableName: 'handle',
        nativeType: 'NativeHandle',
        address: 0x1000,
        structSize: 0,
        fields: const [],
        rawBytes: [1, 2, 3],
      );
      expect(opaque.category, PointerCategory.raw);
    });

    test('union category when all real fields share offset 0', () {
      final union = PointerData(
        variableName: 'intOrFloat',
        nativeType: 'IntOrFloat',
        address: 0x2000,
        structSize: 4,
        fields: [
          StructField(name: 'asInt', typeName: 'Int32', offset: 0, size: 4),
          StructField(name: 'asFloat', typeName: 'Float', offset: 0, size: 4),
        ],
      );
      expect(union.category, PointerCategory.union);
    });

    test('advanced category when array field exists', () {
      final withArray = PointerData(
        variableName: 'withArray',
        nativeType: 'WithArray',
        address: 0x3000,
        structSize: 20,
        fields: [
          StructField(name: 'count', typeName: 'Int32', offset: 0, size: 4),
          StructField(
            name: 'values',
            typeName: 'Array<Int32>',
            offset: 4,
            size: 16,
          ),
        ],
      );
      expect(withArray.category, PointerCategory.advanced);
    });

    test('advanced category for pointer-to-pointer primitive type', () {
      final ptrToPtr = PointerData(
        variableName: 'ptrToPtr',
        nativeType: 'Pointer<Int32>',
        address: 0x3100,
        structSize: 8,
        fields: [
          StructField(
            name: 'value',
            typeName: 'Pointer<Int32>',
            offset: 0,
            size: 8,
          ),
        ],
      );
      expect(ptrToPtr.category, PointerCategory.advanced);
    });

    test('advanced category for buffer-like length + byte pointer layout', () {
      final buffer = PointerData(
        variableName: 'buffer',
        nativeType: 'Buffer',
        address: 0x3200,
        structSize: 16,
        fields: [
          StructField(name: 'length', typeName: 'Int32', offset: 0, size: 4),
          StructField(
            name: 'data',
            typeName: 'Pointer<Uint8>',
            offset: 8,
            size: 8,
          ),
        ],
      );
      expect(buffer.category, PointerCategory.advanced);
    });

    test('advanced category for multi-pointer graph node layout', () {
      final biNode = PointerData(
        variableName: 'treeRoot',
        nativeType: 'BiNode',
        address: 0x3300,
        structSize: 32,
        fields: [
          StructField(name: 'id', typeName: 'Int32', offset: 0, size: 4),
          StructField(
            name: 'left',
            typeName: 'Pointer<BiNode>',
            offset: 8,
            size: 8,
          ),
          StructField(
            name: 'right',
            typeName: 'Pointer<BiNode>',
            offset: 16,
            size: 8,
          ),
          StructField(
            name: 'payload',
            typeName: 'Pointer<Uint8>',
            offset: 24,
            size: 8,
          ),
        ],
      );
      expect(biNode.category, PointerCategory.advanced);
    });

    test('single pointer field struct remains struct category', () {
      final node = PointerData(
        variableName: 'node1',
        nativeType: 'Node',
        address: 0x3400,
        structSize: 16,
        fields: [
          StructField(name: 'data', typeName: 'Int32', offset: 0, size: 4),
          StructField(
            name: 'next',
            typeName: 'Pointer<Node>',
            offset: 8,
            size: 8,
          ),
        ],
      );
      expect(node.category, PointerCategory.struct);
    });

    test('struct category for regular struct pointer', () {
      final myStruct = PointerData(
        variableName: 'myStruct',
        nativeType: 'MyStruct',
        address: 0x4000,
        structSize: 16,
        fields: [
          StructField(name: 'id', typeName: 'Int32', offset: 0, size: 4),
          StructField(
            name: '[pad]',
            typeName: '[pad]',
            offset: 4,
            size: 4,
            isPadding: true,
          ),
          StructField(name: 'value', typeName: 'Float', offset: 8, size: 4),
          StructField(name: 'timestamp', typeName: 'Int64', offset: 8, size: 8),
        ],
      );
      expect(myStruct.category, PointerCategory.struct);
    });
  });

  group('PointerData.copyWith', () {
    test('copyWith updates selected fields and preserves others', () {
      final original = PointerData(
        variableName: 'ptr',
        nativeType: 'Node',
        address: 0x1234,
        structSize: 16,
        fields: [
          StructField(name: 'data', typeName: 'Int32', offset: 0, size: 4),
        ],
        rawBytes: [1, 2, 3, 4],
      );

      final updated = original.copyWith(
        nativeType: 'MyStruct',
        error: 'failed',
      );

      expect(updated.variableName, original.variableName);
      expect(updated.address, original.address);
      expect(updated.structSize, original.structSize);
      expect(updated.fields, original.fields);
      expect(updated.rawBytes, original.rawBytes);
      expect(updated.nativeType, 'MyStruct');
      expect(updated.error, 'failed');
    });
  });
}
