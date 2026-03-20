import 'dart:async';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/stack_probe.dart <ws-uri>');
    return;
  }
  final wsUri = args.first;
  final service = await vmServiceConnectUri(wsUri);
  final vm = await service.getVM();
  final isolate = vm.isolates!.first;
  final isolateId = isolate.id!;

  print('Connected isolate: ${isolate.name} ($isolateId)');
  final initial = await service.getIsolate(isolateId);
  print('Initial pause: ${initial.pauseEvent?.kind}');

  await service.streamListen(EventStreams.kDebug);
  final pauseBreakpoint = Completer<void>();
  late final StreamSubscription sub;
  sub = service.onDebugEvent.listen((event) {
    print('Debug event: ${event.kind}');
    if (event.kind == EventKind.kPauseBreakpoint &&
        !pauseBreakpoint.isCompleted) {
      pauseBreakpoint.complete();
    }
  });

  await service.resume(isolateId);
  await pauseBreakpoint.future.timeout(const Duration(seconds: 30));

  final stack = await service.getStack(isolateId);
  final frame = stack.frames!.first;
  print('Top frame: ${frame.function?.name}, vars=${frame.vars?.length ?? 0}');

  for (final variable in frame.vars ?? const <BoundVariable>[]) {
    final raw = (variable as dynamic).json;
    final value = variable.value;
    final className = value is InstanceRef
        ? value.classRef?.name
        : value.runtimeType.toString();
    if (className == 'Pointer') {
      print('--- var ${variable.name} ---');
      print('keys: ${raw.keys.toList()}');
      print('declaredType: ${raw['declaredType']}');
      print('_declaredTypeDebug: ${raw['_declaredTypeDebug']}');
      print('value.kind: ${value is InstanceRef ? value.kind : value.runtimeType}');
    }
  }

  await sub.cancel();
  await service.dispose();
}
