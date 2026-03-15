// Target program for demonstrating native pointer inspection.
//
// Run with:
//   dart run --enable-vm-service bin/main.dart
//
// The VM Service URL will be printed to stderr.
// Connect the Native Memory Inspector to that URL.

import 'dart:developer';
import 'dart:ffi';
import 'dart:io';

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
  // Without packing: offset 8 (3 bytes padding after b)
}

// Nested struct — contains an embedded struct field.
// Tests compound field decoding.
final class Outer extends Struct {
  @Int32()
  external int header;

  external Point inner; // Embedded Point struct

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

  // ── Safety test pointers ──
  // These demonstrate that the inspector handles error cases gracefully.

  // Invalid address (0xDEADBEEF) — should produce a clean error, no crash.
  final invalidPtr = Pointer<MyStruct>.fromAddress(0xDEADBEEF);

  // Print info for manual verification
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

  print('── Safety Tests ──');
  print('invalidPtr @ 0x${invalidPtr.address.toRadixString(16)}');
  print('  (reading this should produce a clean error, no crash)');
  print('');

  // ──────────────────────────────────────────────────────────
  // Pause at a programmatic breakpoint.
  // This keeps the isolate paused at a VM safepoint where all
  // local variables are visible to the debugger and VM Service.
  //
  // Connect the Native Memory Inspector to the VM Service URL
  // printed above, then click "Rescan" to detect the pointers.
  // ──────────────────────────────────────────────────────────
  print('Pausing at debugger() breakpoint...');
  print('Connect the inspector now, then press Enter here to continue.\n');

  debugger(message: 'Inspect native pointers now');

  // After the debugger resumes, wait for user to press Enter
  print('Debugger resumed. Press Enter to free memory and exit...');
  stdin.readLineSync();

  // Cleanup
  calloc.free(intOrFloat);
  calloc.free(outer);
  calloc.free(packedData);
  calloc.free(node2);
  calloc.free(node1);
  calloc.free(point);
  calloc.free(myStruct);
  print('Memory freed. Exiting.');
}
