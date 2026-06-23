import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myapp/main.dart';

void main() {
  testWidgets('Login screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      const DwbApiTrackerApp(initialHome: HomeScreen.login),
    );
    await tester.pumpAndSettle();

    expect(find.text('SafeRoute Intelligence'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
