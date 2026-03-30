// Target program for demonstrating native pointer inspection.

import 'dart:developer';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

// ═══ Basic structs ═══

// A compound struct with mixed field types for demonstration.
final class MyStruct extends Struct {
  @Int32()
  external int id;

  @Float()
  external double value;

  @Int64()
  external int timestamp;
}

// A simple struct with same-type fields.
final class Point extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;
}

// A struct containing a pointer to another struct (linked list).
final class Node extends Struct {
  @Int32()
  external int data;

  external Pointer<Node> next;
}

// ═══ Edge case structs ═══

// Packed struct — fields have no padding between them.
// Tests that the inspector correctly handles non-standard alignment.
@Packed(1)
final class PackedData extends Struct {
  @Int32()
  external int a;

  @Int8()
  external int b;

  @Int32()
  external int c; // With Packed(1): offset 5 (no padding after b)
}

// Nested struct — contains an embedded struct field.
// Tests compound field decoding.
final class Outer extends Struct {
  @Int32()
  external int header;

  external Point inner; // Embedded Point struct (16 bytes)

  @Int64()
  external int footer;
}

// Union — all fields share the same memory location.
// Tests union layout (all fields at offset 0).
final class IntOrFloat extends Union {
  @Int32()
  external int asInt;

  @Float()
  external double asFloat;
}

// ═══ Advanced patterns ═══

// Struct with inline array field.
// Tests contiguous repeated field decoding inside a struct.
final class WithArray extends Struct {
  @Int32()
  external int count;

  @Array(4)
  external Array<Int32> values; // 4 x Int32 = 16 bytes inline
}

// Length + pointer buffer pattern — mimics common native API patterns.
// The struct contains a length and a pointer to a separate data buffer.
final class Buffer extends Struct {
  @Int32()
  external int length;

  external Pointer<Uint8> data; // Points to a separate byte buffer
}

// Branching graph node with multiple pointer members.
final class BiNode extends Struct {
  @Int32()
  external int id;

  external Pointer<BiNode> left;
  external Pointer<BiNode> right;
  external Pointer<Uint8> payload;
}

// Opaque native handle type.
final class NativeHandle extends Opaque {}

void main() {
  print('=== Native Memory Inspection Target ===\n');

  // ── Basic structs ──

  final myStruct = calloc<MyStruct>();
  myStruct.ref
    ..id = 42
    ..value = 3.14
    ..timestamp = DateTime.now().millisecondsSinceEpoch;

  final point = calloc<Point>();
  point.ref
    ..x = 1.5
    ..y = 2.7;

  final node1 = calloc<Node>();
  final node2 = calloc<Node>();
  node1.ref
    ..data = 100
    ..next = node2;
  node2.ref
    ..data = 200
    ..next = nullptr;

  // ── Edge case structs ──

  final packedData = calloc<PackedData>();
  packedData.ref
    ..a = 0x11223344
    ..b = 0x55
    ..c = 0x66778899;

  final outer = calloc<Outer>();
  outer.ref
    ..header = 999
    ..inner.x = 10.0
    ..inner.y = 20.0
    ..footer = 8888888888;

  final intOrFloat = calloc<IntOrFloat>();
  intOrFloat.ref.asInt = 0x40490FDB; // IEEE 754 representation of π ≈ 3.14159

  // ── Advanced patterns ──

  // Struct with inline array
  final withArray = calloc<WithArray>();
  withArray.ref.count = 4;
  for (int i = 0; i < 4; i++) {
    withArray.ref.values[i] = (i + 1) * 10; // 10, 20, 30, 40
  }

  // Pointer-to-pointer (double indirection)
  final innerInt = calloc<Int32>();
  innerInt.value = 12345;
  final ptrToPtr = calloc<Pointer<Int32>>();
  ptrToPtr.value = innerInt;

  // Raw byte buffer with deterministic pattern
  final rawBuf = calloc<Uint8>(16);
  for (int i = 0; i < 16; i++) {
    rawBuf[i] = 0xAA + i; // 0xAA, 0xAB, 0xAC, ...
  }

  // Larger byte buffer to validate "load more" behavior.
  final longRawBuf = calloc<Uint8>(256);
  for (int i = 0; i < 256; i++) {
    longRawBuf[i] = i;
  }

  // Length + pointer buffer struct
  final bufData = calloc<Uint8>(8);
  for (int i = 0; i < 8; i++) {
    bufData[i] = i * 11; // 0, 11, 22, 33, 44, 55, 66, 77
  }
  final buffer = calloc<Buffer>();
  buffer.ref
    ..length = 8
    ..data = bufData;

  // Multi-depth/multi-member branching graph.
  final treeRoot = calloc<BiNode>();
  final treeLeft = calloc<BiNode>();
  final treeRight = calloc<BiNode>();
  final treeLeftLeft = calloc<BiNode>();
  final treeRightRight = calloc<BiNode>();
  final treePayloadA = calloc<Uint8>(6);
  final treePayloadB = calloc<Uint8>(6);
  final treePayloadC = calloc<Uint8>(6);
  for (int i = 0; i < 6; i++) {
    treePayloadA[i] = 10 + i;
    treePayloadB[i] = 20 + i;
    treePayloadC[i] = 30 + i;
  }
  treeRoot.ref
    ..id = 1
    ..left = treeLeft
    ..right = treeRight
    ..payload = treePayloadA;
  treeLeft.ref
    ..id = 2
    ..left = treeLeftLeft
    ..right = nullptr
    ..payload = treePayloadB;
  treeRight.ref
    ..id = 3
    ..left = nullptr
    ..right = treeRightRight
    ..payload = treePayloadC;
  treeLeftLeft.ref
    ..id = 4
    ..left = nullptr
    ..right = nullptr
    ..payload = treePayloadA;
  treeRightRight.ref
    ..id = 5
    ..left = treeRoot // back-reference to root for cycle visibility
    ..right = nullptr
    ..payload = treePayloadB;

  // Pointer value with erased static type information on the variable.
  dynamic unknownPtr = rawBuf.cast<Void>();

  // Opaque pointer with no struct layout metadata.
  final handle = Pointer<NativeHandle>.fromAddress(rawBuf.address);

  // Tagged pointer — address | 1 to simulate runtime tag bits
  final tagTarget = calloc<Point>();
  tagTarget.ref
    ..x = 42.0
    ..y = 84.0;
  final taggedAddr = tagTarget.address | 1; // Low bit set as tag
  final taggedPointPtr = Pointer<Point>.fromAddress(taggedAddr);

  // Cycle for graph traversal testing.
  final cycleA = calloc<Node>();
  final cycleB = calloc<Node>();
  cycleA.ref
    ..data = 11
    ..next = cycleB;
  cycleB.ref
    ..data = 22
    ..next = cycleA;

  // Safety test pointers
  final invalidPtr = Pointer<MyStruct>.fromAddress(0xDEADBEEF);
  final nullPtr = Pointer<Point>.fromAddress(0);

  // ── Print info for manual verification ──

  print('── Basic Structs ──');
  print('MyStruct @ 0x${myStruct.address.toRadixString(16)}');
  print('  id:        ${myStruct.ref.id}');
  print('  value:     ${myStruct.ref.value}');
  print('  timestamp: ${myStruct.ref.timestamp}');
  print('');
  print('Point @ 0x${point.address.toRadixString(16)}');
  print('  x: ${point.ref.x}');
  print('  y: ${point.ref.y}');
  print('');
  print('Node1 @ 0x${node1.address.toRadixString(16)}');
  print('  data: ${node1.ref.data}');
  print('  next: 0x${node1.ref.next.address.toRadixString(16)}');
  print('Node2 @ 0x${node2.address.toRadixString(16)}');
  print('  data: ${node2.ref.data}');
  print('  next: 0x${node2.ref.next.address.toRadixString(16)} (null)');
  print('');

  print('── Edge Case Structs ──');
  print('PackedData @ 0x${packedData.address.toRadixString(16)}');
  print('  a: 0x${packedData.ref.a.toRadixString(16)}');
  print('  b: 0x${packedData.ref.b.toRadixString(16)}');
  print('  c: 0x${packedData.ref.c.toRadixString(16)}');
  print('  sizeOf<PackedData>: ${sizeOf<PackedData>()} bytes');
  print('');
  print('Outer @ 0x${outer.address.toRadixString(16)}');
  print('  header: ${outer.ref.header}');
  print('  inner.x: ${outer.ref.inner.x}');
  print('  inner.y: ${outer.ref.inner.y}');
  print('  footer: ${outer.ref.footer}');
  print('  sizeOf<Outer>: ${sizeOf<Outer>()} bytes');
  print('');
  print('IntOrFloat @ 0x${intOrFloat.address.toRadixString(16)}');
  print('  asInt:   0x${intOrFloat.ref.asInt.toRadixString(16)}');
  print('  asFloat: ${intOrFloat.ref.asFloat}');
  print('  sizeOf<IntOrFloat>: ${sizeOf<IntOrFloat>()} bytes');
  print('');

  print('── Advanced Patterns ──');
  print('WithArray @ 0x${withArray.address.toRadixString(16)}');
  print('  count: ${withArray.ref.count}');
  print(
      '  values: [${List.generate(4, (i) => withArray.ref.values[i]).join(', ')}]');
  print('  sizeOf<WithArray>: ${sizeOf<WithArray>()} bytes');
  print('');
  print('ptrToPtr @ 0x${ptrToPtr.address.toRadixString(16)}');
  print('  *ptrToPtr: 0x${ptrToPtr.value.address.toRadixString(16)}');
  print('  **ptrToPtr: ${ptrToPtr.value.value}');
  print('');
  print('rawBuf @ 0x${rawBuf.address.toRadixString(16)}');
  print(
      '  bytes: ${List.generate(16, (i) => '0x${rawBuf[i].toRadixString(16)}').join(', ')}');
  print('');
  print('longRawBuf @ 0x${longRawBuf.address.toRadixString(16)}');
  print(
      '  first 16 bytes: ${List.generate(16, (i) => longRawBuf[i]).join(', ')}');
  print(
      '  last 16 bytes: ${List.generate(16, (i) => longRawBuf[240 + i]).join(', ')}');
  print('');
  print('Buffer @ 0x${buffer.address.toRadixString(16)}');
  print('  length: ${buffer.ref.length}');
  print('  data: 0x${buffer.ref.data.address.toRadixString(16)}');
  print(
      '  data bytes: ${List.generate(8, (i) => buffer.ref.data[i]).join(', ')}');
  print('  sizeOf<Buffer>: ${sizeOf<Buffer>()} bytes');
  print('');
  print('BiNode tree (branching + deep + cycle):');
  print('  treeRoot @ 0x${treeRoot.address.toRadixString(16)}');
  print('  root.left:  0x${treeRoot.ref.left.address.toRadixString(16)}');
  print('  root.right: 0x${treeRoot.ref.right.address.toRadixString(16)}');
  print('  right.right: 0x${treeRight.ref.right.address.toRadixString(16)}');
  print('  right.right.left (cycle): '
      '0x${treeRightRight.ref.left.address.toRadixString(16)}');
  print('  sizeOf<BiNode>: ${sizeOf<BiNode>()} bytes');
  print('');
  print(
      'unknownPtr (dynamic) @ 0x${(unknownPtr as Pointer).address.toRadixString(16)}');
  print('  declared as dynamic (value is Pointer<Void>)');
  print('');
  print(
      'handle (Pointer<NativeHandle>) @ 0x${handle.address.toRadixString(16)}');
  print('  opaque pointer, no struct fields');
  print('');
  print('Tagged pointer:');
  print('  tagTarget @ 0x${tagTarget.address.toRadixString(16)}');
  print('  taggedAddr = 0x${taggedAddr.toRadixString(16)} (address | 1)');
  print('  Untagged: 0x${(taggedAddr & ~1).toRadixString(16)}');
  print('  taggedPointPtr @ 0x${taggedPointPtr.address.toRadixString(16)}');
  print('');
  print('Cycle nodes:');
  print(
      '  cycleA @ 0x${cycleA.address.toRadixString(16)} -> 0x${cycleA.ref.next.address.toRadixString(16)}');
  print(
      '  cycleB @ 0x${cycleB.address.toRadixString(16)} -> 0x${cycleB.ref.next.address.toRadixString(16)}');
  print('');

  print('── Safety Tests ──');
  print('invalidPtr @ 0x${invalidPtr.address.toRadixString(16)}');
  print('  (reading this should produce a clean error, no crash)');
  print('nullPtr @ 0x${nullPtr.address.toRadixString(16)}');
  print('  (null pointer — should also produce a clean error)');
  print('');

  // ── Phase 1: Initial inspection ──
  print('Phase 1: Pausing for initial inspection...');
  print('Connect the inspector, Rescan, then click Resume Target.\n');

  debugger(message: 'Phase 1 — Inspect initial state');

  // ── Phase 2: Mutate memory to demonstrate Δ Changes ──
  print('Phase 2: Mutating memory...');

  // Mutate scalar values
  treeRoot.ref.id = 99; // id: 1 → 99
  myStruct.ref.value = 9.81; // value: 3.14 → 9.81
  node1.ref.data = 777; // data: 100 → 777

  // Mutate pointer topology — treeLeft gains a new right child
  // Before: treeLeft.right = null
  // After:  treeLeft.right = treeRightRight
  // This creates a new inbound reference to treeRightRight!
  treeLeft.ref.right = treeRightRight;

  // Mutate buffer contents
  for (int i = 0; i < 8; i++) {
    bufData[i] = 0xFF - i; // 255, 254, 253, ... (reversed pattern)
  }
  buffer.ref.length = 99; // length: 8 → 99

  print('  treeRoot.id:    1 → ${treeRoot.ref.id}');
  print('  myStruct.value: 3.14 → ${myStruct.ref.value}');
  print('  node1.data:     100 → ${node1.ref.data}');
  print(
      '  treeLeft.right: null → 0x${treeLeft.ref.right.address.toRadixString(16)}');
  print('  buffer.length:  8 → ${buffer.ref.length}');
  print('');
  print('Phase 2: Pausing — Rescan in the inspector to see Δ Changes.\n');

  debugger(message: 'Phase 2 — Rescan to see memory diffs');

  // ── Phase 3: Partial revert + new mutations ──
  print('\nPhase 3: Partial revert + new mutations...');

  // Revert some Phase 2 changes
  treeRoot.ref.id = 1; // id: 99 → 1 (back to original!)
  buffer.ref.length = 8; // length: 99 → 8 (reverted)

  // New mutations on previously-unchanged fields
  point.ref.x = 100.0; // x: 1.5 → 100.0
  point.ref.y = 200.0; // y: 2.7 → 200.0
  node2.ref.data = 999; // data: 200 → 999

  // Mutate raw buffer bytes to demonstrate raw byte diff
  bufData[0] = 0xAA; // was 0xFF from Phase 2
  bufData[1] = 0xBB; // was 0xFE from Phase 2
  bufData[4] = 0x00; // was 0xFB from Phase 2

  print('  treeRoot.id:    99 → ${treeRoot.ref.id} (reverted!)');
  print('  buffer.length:  99 → ${buffer.ref.length} (reverted!)');
  print('  point.x:        1.5 → ${point.ref.x}');
  print('  point.y:        2.7 → ${point.ref.y}');
  print('  node2.data:     200 → ${node2.ref.data}');
  print('  bufData[0..4]:  FF→AA, FE→BB, FB→00');
  print('\nPhase 3: Pausing — Rescan to see all changes across timeline.\n');

  debugger(message: 'Phase 3 — Compare across timeline');

  // When resumed, cleanup and exit
  print('\nDone. Freeing memory and exiting...');

  // Cleanup
  calloc.free(buffer);
  calloc.free(bufData);
  calloc.free(treePayloadC);
  calloc.free(treePayloadB);
  calloc.free(treePayloadA);
  calloc.free(treeRightRight);
  calloc.free(treeLeftLeft);
  calloc.free(treeRight);
  calloc.free(treeLeft);
  calloc.free(treeRoot);
  calloc.free(longRawBuf);
  calloc.free(rawBuf);
  calloc.free(ptrToPtr);
  calloc.free(innerInt);
  calloc.free(withArray);
  calloc.free(intOrFloat);
  calloc.free(outer);
  calloc.free(packedData);
  calloc.free(node2);
  calloc.free(node1);
  calloc.free(cycleB);
  calloc.free(cycleA);
  calloc.free(point);
  calloc.free(tagTarget);
  calloc.free(myStruct);
  print('Memory freed. Exiting.');
}
