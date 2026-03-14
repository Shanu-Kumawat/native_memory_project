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

// A compound struct with mixed field types for demonstration.
final class MyStruct extends Struct {
  @Int32()
  external int id;

  @Float()
  external double value;

  @Int64()
  external int timestamp;
}

// A nested struct to demonstrate compound pointer traversal.
final class Point extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;
}

// A struct containing a pointer to another struct.
final class Node extends Struct {
  @Int32()
  external int data;

  external Pointer<Node> next;
}

void main() {
  print('=== Native Memory Inspection Target ===\n');

  // Allocate and populate MyStruct
  final myStruct = calloc<MyStruct>();
  myStruct.ref
    ..id = 42
    ..value = 3.14
    ..timestamp = DateTime.now().millisecondsSinceEpoch;

  // Allocate and populate Point
  final point = calloc<Point>();
  point.ref
    ..x = 1.5
    ..y = 2.7;

  // Allocate a linked list: node1 -> node2 -> null
  final node1 = calloc<Node>();
  final node2 = calloc<Node>();
  node1.ref
    ..data = 100
    ..next = node2;
  node2.ref
    ..data = 200
    ..next = nullptr;

  // Print info for manual verification
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

  // ──────────────────────────────────────────────────────────
  // Pause at a programmatic breakpoint.
  // This keeps the isolate paused at a VM safepoint where all
  // local variables (myStruct, point, node1, node2) are visible
  // to the debugger and the VM Service.
  //
  // Connect the Native Memory Inspector to the VM Service URL
  // printed above, then click "Rescan" to detect the pointers.
  //
  // After inspection, resume the isolate from the inspector or
  // press Enter in this terminal to continue.
  // ──────────────────────────────────────────────────────────
  print('Pausing at debugger() breakpoint...');
  print('Connect the inspector now, then press Enter here to continue.\n');

  debugger(message: 'Inspect native pointers now');

  // After the debugger resumes, wait for user to press Enter
  print('Debugger resumed. Press Enter to free memory and exit...');
  stdin.readLineSync();

  // Cleanup
  calloc.free(node2);
  calloc.free(node1);
  calloc.free(point);
  calloc.free(myStruct);
  print('Memory freed. Exiting.');
}
