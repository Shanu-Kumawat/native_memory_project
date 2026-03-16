import 'package:flutter_test/flutter_test.dart';

import 'package:pointer_inspector/main.dart';

void main() {
  testWidgets('App renders title bar', (WidgetTester tester) async {
    await tester.pumpWidget(const NativeMemoryInspectorApp());
    expect(find.text('Native Memory Inspector'), findsOneWidget);
  });
}
