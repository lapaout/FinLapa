import 'package:finlapa/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FinLapaApp boots to loading or welcome screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FinLapaApp());
    await tester.pump();

    final hasLoader = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    final hasWelcome = find.text('FinLapa').evaluate().isNotEmpty;

    expect(hasLoader || hasWelcome, isTrue);
  });
}
