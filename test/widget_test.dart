import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rina_admin/main.dart';

void main() {
  testWidgets('Admin login screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );

    expect(find.text('Admin dashboard'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
