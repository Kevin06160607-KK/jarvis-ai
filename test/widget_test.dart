import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jarvis_ai/main.dart';

void main() {
  testWidgets('shows the JARVIS chat screen', (WidgetTester tester) async {
    await tester.pumpWidget(const JarvisApp());

    expect(find.text('JARVIS AI'), findsOneWidget);
    expect(find.text('OFFLINE READY'), findsOneWidget);
    expect(find.byTooltip('Use microphone'), findsOneWidget);
  });

  testWidgets('answers a basic help request while offline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const JarvisApp());

    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'help');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Offline, I can tell you the time or date'),
      findsOneWidget,
    );
  });
}
