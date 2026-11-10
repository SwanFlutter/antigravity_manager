// Smoke tests for the Antigravity Manager shell.

import 'package:antigravity_manager/app/controller/app_controller.dart';
import 'package:antigravity_manager/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_x_master/get_x_master.dart';
import 'package:get_x_storage/get_x_storage.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    // Construct storage outside the test's FakeAsync zone: its debounced
    // flush stream starts a 2s timer on first construction, which would
    // otherwise be reported as a pending timer after the widget tree is
    // disposed. The factory caches the instance, so pumpWidget reuses it.
    GetXStorage();
    Get.put(AppController(), permanent: true);
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('renders the accounts page by default', (tester) async {
    await tester.pumpWidget(const AntigravityApp());
    await tester.pump();

    expect(find.text('Accounts'), findsWidgets);
    expect(find.text('Antigravity'), findsOneWidget);
  });

  testWidgets('navigation switches the visible page', (tester) async {
    await tester.pumpWidget(const AntigravityApp());
    await tester.pump();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
  });
}
