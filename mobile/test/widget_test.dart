// Smoke test: the app boots to the login screen without crashing.
//
// This replaces the unmodified Flutter template test (which referenced a
// nonexistent `MyApp` counter-demo class and never built at all). It's
// intentionally minimal — there's no shared repository/service layer or
// widget-testing convention elsewhere in this app to build on top of, and
// most screens require a live backend, so this just checks the app shell
// itself doesn't crash before real network calls are involved (see
// CLAUDE.md's "Mobile architecture" section).
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';

void main() {
  testWidgets('App boots to the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RallyXApp(initialRoute: '/login'));
    await tester.pumpAndSettle();

    expect(find.text('RallyX'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Email or mobile number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
