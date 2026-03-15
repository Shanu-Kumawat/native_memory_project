import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:pointer_inspector/services/struct_layout_utils.dart';

void main() {
  // ═══ mapToFfiType tests ═══

  group('mapToFfiType', () {
    test('int defaults to Int32', () {
      final result = mapToFfiType('int');
      expect(result.typeName, 'Int32');
      expect(result.size, 4);
    });

    test('double defaults to Double', () {
      final result = mapToFfiType('double');
      expect(result.typeName, 'Double');
      expect(result.size, 8);
    });

    test('Float maps to 4 bytes', () {
      final result = mapToFfiType('Float');
      expect(result.typeName, 'Float');
      expect(result.size, 4);
    });

    test('Int64 maps to 8 bytes', () {
      final result = mapToFfiType('Int64');
      expect(result.typeName, 'Int64');
      expect(result.size, 8);
    });

    test('Int8 maps to 1 byte', () {
      final result = mapToFfiType('Int8');
      expect(result.typeName, 'Int8');
      expect(result.size, 1);
    });

    test('Int16 maps to 2 bytes', () {
      final result = mapToFfiType('Int16');
      expect(result.typeName, 'Int16');
      expect(result.size, 2);
    });

    test('Pointer maps to 8 bytes', () {
      final result = mapToFfiType('Pointer');
      expect(result.typeName, 'Pointer');
      expect(result.size, 8);
    });

    test('Pointer<Node> maps to 8 bytes', () {
      final result = mapToFfiType('Pointer<Node>');
      expect(result.typeName, 'Pointer<Node>');
      expect(result.size, 8);
    });

    test('X0 (FFI internal) maps to Double', () {
      final result = mapToFfiType('X0');
      expect(result.typeName, 'Double');
      expect(result.size, 8);
    });

    test('Unknown type defaults to 8 bytes', () {
      final result = mapToFfiType('SomeCustomType');
      expect(result.size, 8);
    });
  });

  // ═══ getCandidateTypes tests ═══

  group('getCandidateTypes', () {
    test('int has all integer candidates', () {
      final candidates = getCandidateTypes('int');
      final typeNames = candidates.map((c) => c.typeName).toList();
      expect(typeNames, contains('Int32'));
      expect(typeNames, contains('Int64'));
      expect(typeNames, contains('Int8'));
      expect(typeNames, contains('Uint8'));
      expect(candidates.length, 8);
    });

    test('double has Float and Double candidates', () {
      final candidates = getCandidateTypes('double');
      expect(candidates.length, 2);
      expect(candidates[0].typeName, 'Float');
      expect(candidates[0].size, 4);
      expect(candidates[1].typeName, 'Double');
      expect(candidates[1].size, 8);
    });

    test('Pointer<Node> has single candidate', () {
      final candidates = getCandidateTypes('Pointer<Node>');
      expect(candidates.length, 1);
      expect(candidates[0].typeName, 'Pointer<Node>');
      expect(candidates[0].size, 8);
    });
  });

  // ═══ ABI alignment tests ═══

  group('alignOffset', () {
    test('already aligned', () {
      expect(alignOffset(0, 4), 0);
      expect(alignOffset(4, 4), 4);
      expect(alignOffset(8, 8), 8);
    });

    test('Int32 alignment (4 bytes)', () {
      expect(alignOffset(1, 4), 4);
      expect(alignOffset(2, 4), 4);
      expect(alignOffset(3, 4), 4);
      expect(alignOffset(5, 4), 8);
    });

    test('Int64 alignment (8 bytes)', () {
      expect(alignOffset(4, 8), 8);
      expect(alignOffset(5, 8), 8);
      expect(alignOffset(7, 8), 8);
      expect(alignOffset(12, 8), 16);
    });

    test('Int8 alignment (1 byte, never needs padding)', () {
      expect(alignOffset(0, 1), 0);
      expect(alignOffset(3, 1), 3);
      expect(alignOffset(7, 1), 7);
    });
  });

  // ═══ reconcileLayout tests ═══

  group('reconcileLayout', () {
    test('MyStruct: id:int, value:double, timestamp:int → sizeOf=16', () {
      // MyStruct has @Int32() id, @Float() value, @Int64() timestamp
      // Getter return types: int, double, int
      // sizeOf = 16 on x64
      final result = reconcileLayout(
        ['id', 'value', 'timestamp'],
        [
          getCandidateTypes('int'),     // id → Int32,Int64,...
          getCandidateTypes('double'),  // value → Float,Double
          getCandidateTypes('int'),     // timestamp → Int32,Int64,...
        ],
        16,  // #sizeOf = 16
        0,
        [],
      );

      expect(result, isNotNull);
      expect(result!.length, 3);

      // id: Int32 @ offset 0, size 4
      expect(result[0].typeName, 'Int32');
      expect(result[0].offset, 0);
      expect(result[0].size, 4);

      // value: Float @ offset 4, size 4
      expect(result[1].typeName, 'Float');
      expect(result[1].offset, 4);
      expect(result[1].size, 4);

      // timestamp: Int64 @ offset 8, size 8
      expect(result[2].typeName, 'Int64');
      expect(result[2].offset, 8);
      expect(result[2].size, 8);
    });

    test('Node: data:int, next:Pointer<Node> → sizeOf=16', () {
      final result = reconcileLayout(
        ['data', 'next'],
        [
          getCandidateTypes('int'),
          [(typeName: 'Pointer<Node>', size: 8)],
        ],
        16,
        0,
        [],
      );

      expect(result, isNotNull);
      expect(result!.length, 2);

      // data: Int32 @ offset 0
      expect(result[0].typeName, 'Int32');
      expect(result[0].offset, 0);

      // next: Pointer<Node> @ offset 8 (aligned to 8)
      expect(result[1].typeName, 'Pointer<Node>');
      expect(result[1].offset, 8);
    });

    test('Point: x:double, y:double → sizeOf=16', () {
      // The reconciler tries candidates in order. Float is first.
      // Float(4 @ 0) + Double(8 @ 8, aligned) = 16 → valid match.
      // In practice, evaluated offsets from #offsetOf override this,
      // so the reconciler's greedy behavior is fine.
      final result = reconcileLayout(
        ['x', 'y'],
        [
          getCandidateTypes('double'),
          getCandidateTypes('double'),
        ],
        16,
        0,
        [],
      );

      expect(result, isNotNull);
      expect(result!.length, 2);

      // First valid combo: Float(4) + Double(8@8) = 16
      expect(result[0].typeName, 'Float');
      expect(result[0].offset, 0);
      expect(result[0].size, 4);

      expect(result[1].typeName, 'Double');
      expect(result[1].offset, 8);
      expect(result[1].size, 8);
    });

    test('Impossible layout returns null', () {
      // 3 int fields with sizeOf=3 is impossible (smallest int is Int8=1,
      // so minimum is 3, but 3 Int8s = 3 which matches... use sizeOf=2)
      final result = reconcileLayout(
        ['a', 'b', 'c'],
        [
          getCandidateTypes('int'),
          getCandidateTypes('int'),
          getCandidateTypes('int'),
        ],
        2,  // Impossible: 3 fields can't fit in 2 bytes
        0,
        [],
      );

      expect(result, isNull);
    });

    test('Three int fields with sizeOf=12', () {
      // The reconciler tries Int32 first for 'int' type.
      // Int32(4@0) + Int32(4@4) + Int32(4@8) = 12 → valid match.
      final result = reconcileLayout(
        ['a', 'b', 'c'],
        [
          getCandidateTypes('int'),
          getCandidateTypes('int'),
          getCandidateTypes('int'),
        ],
        12,
        0,
        [],
      );

      expect(result, isNotNull);
      expect(result!.length, 3);

      // First valid combo: all Int32
      expect(result[0].typeName, 'Int32');
      expect(result[0].offset, 0);

      expect(result[1].typeName, 'Int32');
      expect(result[1].offset, 4);

      expect(result[2].typeName, 'Int32');
      expect(result[2].offset, 8);
    });
  });

  // ═══ decodeFieldValue tests ═══

  group('decodeFieldValue', () {
    test('Int32: decode 42', () {
      final bytes = <int>[42, 0, 0, 0];  // 42 in little-endian
      expect(decodeFieldValue(bytes, 0, 'Int32', 4), '42');
    });

    test('Int32: decode negative', () {
      final bytes = <int>[0xFE, 0xFF, 0xFF, 0xFF];  // -2 in little-endian
      expect(decodeFieldValue(bytes, 0, 'Int32', 4), '-2');
    });

    test('Float: decode 3.14', () {
      // 3.14f in IEEE 754 little-endian
      final bd = ByteData(4);
      bd.setFloat32(0, 3.14, Endian.little);
      final bytes = bd.buffer.asUint8List().toList();

      final result = decodeFieldValue(bytes, 0, 'Float', 4);
      expect(double.parse(result), closeTo(3.14, 0.001));
    });

    test('Double: decode 1.5', () {
      final bd = ByteData(8);
      bd.setFloat64(0, 1.5, Endian.little);
      final bytes = bd.buffer.asUint8List().toList();

      final result = decodeFieldValue(bytes, 0, 'Double', 8);
      expect(double.parse(result), closeTo(1.5, 0.0001));
    });

    test('Int64: decode large number', () {
      final bd = ByteData(8);
      bd.setInt64(0, 1234567890123, Endian.little);
      final bytes = bd.buffer.asUint8List().toList();

      expect(decodeFieldValue(bytes, 0, 'Int64', 8), '1234567890123');
    });

    test('Uint8: decode 255', () {
      expect(decodeFieldValue([255], 0, 'Uint8', 1), '255');
    });

    test('Pointer: decode as hex address', () {
      final bd = ByteData(8);
      bd.setUint64(0, 0x7f2b7c00d370, Endian.little);
      final bytes = bd.buffer.asUint8List().toList();

      final result = decodeFieldValue(bytes, 0, 'Pointer<Node>', 8);
      expect(result, '0x7f2b7c00d370');
    });

    test('offset into larger buffer', () {
      // 16-byte buffer simulating MyStruct
      final bd = ByteData(16);
      bd.setInt32(0, 42, Endian.little);       // id
      bd.setFloat32(4, 3.14, Endian.little);   // value
      bd.setInt64(8, 9999999, Endian.little);   // timestamp
      final bytes = bd.buffer.asUint8List().toList();

      expect(decodeFieldValue(bytes, 0, 'Int32', 4), '42');
      expect(double.parse(decodeFieldValue(bytes, 4, 'Float', 4)),
             closeTo(3.14, 0.001));
      expect(decodeFieldValue(bytes, 8, 'Int64', 8), '9999999');
    });

    test('out of bounds returns error', () {
      expect(decodeFieldValue([1, 2], 0, 'Int32', 4), '<out of bounds>');
    });
  });
}
