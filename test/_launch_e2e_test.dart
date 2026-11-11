// Temporary end-to-end check: the Add account flow really opens the browser.

import 'package:antigravity_manager/app/controller/accounts_controller.dart';
import 'package:antigravity_manager/data/accounts_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startConnect opens the authorization URL in the browser', () async {
    final controller = AccountsController(repository: HostAccountsRepository());
    addTearDown(controller.onClose);

    await controller.startConnect();
    // ignore: avoid_print
    print('URL=${controller.connectUrl.value}');
    // ignore: avoid_print
    print('browserOpened=${controller.browserOpened.value}');
    // ignore: avoid_print
    print('status=${controller.connectStatus.value}');
    // ignore: avoid_print
    print('error=${controller.connectError.value}');

    expect(controller.connectUrl.value, isNotNull);
    expect(controller.browserOpened.value, isTrue,
        reason: 'the authorization URL did not reach the browser');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
