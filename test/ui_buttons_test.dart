// Widget tests for the two buttons the user reported: the playground run
// button and the API key regenerate button. A fake repository is injected
// before the app is pumped, so the tap drives the controller for real.

import 'dart:async';

import 'package:antigravity_manager/app/controller/accounts_controller.dart';
import 'package:antigravity_manager/app/controller/api_proxy_controller.dart';
import 'package:antigravity_manager/app/controller/app_controller.dart';
import 'package:antigravity_manager/app/controller/playground_controller.dart';
import 'package:antigravity_manager/core/data/mock_data.dart';
import 'package:antigravity_manager/core/widgets/app_button.dart';
import 'package:antigravity_manager/data/accounts_repository.dart';
import 'package:antigravity_manager/data/cloud_models.dart';
import 'package:antigravity_manager/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_x_master/get_x_master.dart';
import 'package:get_x_storage/get_x_storage.dart';

/// A repository that reports the gateway as offline and rotates the key.
class OfflineFakeRepository implements AccountsRepository {
  int rotateCalls = 0;
  int connectCalls = 0;
  int loadCalls = 0;
  Object? connectFailure;
  ConnectState connectionState = const ConnectState(status: 'pending');
  final List<String> polledSessions = [];
  Completer<ConnectState>? pendingStatus;

  @override
  Future<AccountSnapshot> load() async {
    loadCalls++;
    return AccountSnapshot(
      accounts: MockData.accounts,
      activeCount: 1,
      rateLimitedCount: 0,
      globalRemaining: 1,
    );
  }

  @override
  Future<void> setActive(String id) async {}

  @override
  Future<void> setSelected(String id, bool selected) async {}

  @override
  Future<List<CatalogModel>> modelCatalog() async => MockData.modelCatalog;

  @override
  bool get isLive => true;

  @override
  Future<ConnectSession> startConnect() async {
    connectCalls++;
    if (connectFailure != null) throw connectFailure!;
    return ConnectSession(
      sessionId: 'session-$connectCalls',
      authorizationUrl:
          'https://accounts.google.com/o/oauth2/v2/auth?state=test-$connectCalls',
      redirectUri: 'http://127.0.0.1:34567/oauth-callback',
      expiresAt: DateTime.now().millisecondsSinceEpoch + 300000,
    );
  }

  @override
  Future<ConnectState> connectStatus(String sessionId) async {
    polledSessions.add(sessionId);
    return pendingStatus == null
        ? connectionState
        : await pendingStatus!.future;
  }

  @override
  Future<void> submitCode(String sessionId, String code) async =>
      throw UnimplementedError();

  @override
  Future<Account?> refreshQuota(String id) async => null;

  @override
  Future<void> removeAccount(String id) async {}

  @override
  Future<List<ConnectedAccount>> connectedAccounts() async => const [];

  @override
  Future<ProxyStatus> proxyStatus() async => const ProxyStatus(
    running: false,
    port: 8045,
    baseUrl: 'http://127.0.0.1:8045',
    models: 15,
    apiKey: 'sk-old-key',
  );

  @override
  Future<ProxyStatus> startProxy({int? port}) async =>
      throw UnimplementedError();

  @override
  Future<ProxyStatus> stopProxy() async => const ProxyStatus.empty();

  @override
  Future<ProxyStatus> rotateProxyKey() async {
    rotateCalls++;
    return const ProxyStatus(
      running: true,
      port: 8045,
      baseUrl: 'http://127.0.0.1:8045',
      models: 15,
      apiKey: 'sk-fake-rotated',
    );
  }

  @override
  Future<List<TrafficRecord>> traffic({int limit = 100}) async => const [];

  @override
  Future<List<Workspace>> workspaces() async => MockData.workspaces;
}

void mockUrlLauncher(WidgetTester tester) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (_) async => true,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
}

void main() {
  setUp(() {
    Get.testMode = true;
    GetXStorage();
    Get.put(AppController(), permanent: true);
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('the playground run button drives the controller', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1584, 1061);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = OfflineFakeRepository();
    Get.put(PlaygroundController(repository: repo), permanent: true);
    Get.put(ApiProxyController(repository: repo), permanent: true);

    await tester.pumpWidget(const AntigravityApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    Get.find<AppController>().currentIndex.value = 3;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final controller = Get.find<PlaygroundController>();
    expect(controller.lastResult.value, isNull);

    // The gateway is offline in the fake, so the run ends in an error result.
    final runButton = find.widgetWithText(AppButton, 'Run prompt');
    expect(tester.widget<AppButton>(runButton).onPressed, isNotNull);
    await tester.tap(runButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.lastResult.value, isNotNull);
    expect(controller.lastResult.value!.isError, isTrue);
  });

  for (final tab in PlaygroundTab.values) {
    testWidgets('copy preserves the entire response in $tab', (tester) async {
      tester.view.physicalSize = const Size(1584, 1061);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = OfflineFakeRepository();
      final controller = Get.put(
        PlaygroundController(repository: repo),
        permanent: true,
      );
      await tester.pumpWidget(const AntigravityApp());
      await tester.pump(const Duration(milliseconds: 500));
      Get.find<AppController>().currentIndex.value = 3;
      controller.tab.value = tab;
      final text =
          'HTTP 403: TOS_VIOLATION\n${List.filled(25, 'Complete provider diagnostic.').join(' ')}\nEnd of error';
      final result = PlaygroundResult(error: text, status: 403);
      if (tab == PlaygroundTab.single) {
        controller.lastResult.value = result;
      } else {
        controller.results[tab == PlaygroundTab.dual
                ? controller.model.value
                : controller.accounts.first.id] =
            result;
      }
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      final button = find.widgetWithText(AppButton, 'Copy');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(copied, text);
      expect(
        find.widgetWithText(AppButton, 'Copied to clipboard'),
        findsOneWidget,
      );
    });
  }

  testWidgets('compare selection and layout remain usable at desktop widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    final controller = Get.put(
      PlaygroundController(repository: OfflineFakeRepository()),
      permanent: true,
    );
    await tester.pumpWidget(const AntigravityApp());
    await tester.pump(const Duration(milliseconds: 500));
    Get.find<AppController>().currentIndex.value = 3;
    controller.tab.value = PlaygroundTab.compare;
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    expect(controller.compareAccounts, isEmpty);
    expect(
      tester
          .widget<AppButton>(
            find.widgetWithText(AppButton, 'Run on Selected Accounts'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(controller.compareAccounts.length, controller.accounts.length);
    tester.view.physicalSize = const Size(1000, 900);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add account starts OAuth and reloads after completion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1584, 1061);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockUrlLauncher(tester);
    final repo = OfflineFakeRepository();
    final controller = Get.put(
      AccountsController(repository: repo),
      permanent: true,
    );
    await tester.pumpWidget(const AntigravityApp());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(AppButton, 'Add account'));
    await tester.pump();
    expect(repo.connectCalls, 1);
    expect(controller.connectUrl.value, contains('accounts.google.com'));
    repo.connectionState = const ConnectState(
      status: 'completed',
      email: 'new@example.com',
    );
    final before = repo.loadCalls;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(controller.connectStatus.value, 'completed');
    expect(controller.connectEmail.value, 'new@example.com');
    expect(repo.loadCalls, greaterThan(before));
    controller.onClose();
  });

  testWidgets('OAuth launch failure is shown rather than waiting forever', (
    tester,
  ) async {
    final repo = OfflineFakeRepository()
      ..connectFailure = Exception('Chrome could not be opened');
    final controller = AccountsController(repository: repo);
    await controller.startConnect();
    expect(controller.connectStatus.value, 'failed');
    expect(controller.connectError.value, contains('Chrome'));
    expect(controller.connectUrl.value, isNull);
    expect(controller.connecting.value, isFalse);
    controller.onClose();
  });

  testWidgets('a stale OAuth poll cannot overwrite a new session', (
    tester,
  ) async {
    mockUrlLauncher(tester);
    final repo = OfflineFakeRepository()
      ..pendingStatus = Completer<ConnectState>();
    final controller = AccountsController(repository: repo);
    await controller.startConnect();
    await tester.pump(const Duration(seconds: 2));
    expect(repo.polledSessions, ['session-1']);
    await controller.startConnect();
    repo.pendingStatus!.complete(
      const ConnectState(status: 'failed', error: 'old error'),
    );
    await tester.pump();
    expect(controller.connectSessionId.value, 'session-2');
    expect(controller.connectStatus.value, 'pending');
    expect(controller.connectError.value, isNull);
    controller.onClose();
    await tester.pump(const Duration(seconds: 3));
    expect(repo.polledSessions, ['session-1']);
  });

  testWidgets('the regenerate button replaces the key field', (tester) async {
    tester.view.physicalSize = const Size(1584, 1061);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = OfflineFakeRepository();
    Get.put(PlaygroundController(repository: repo), permanent: true);
    Get.put(ApiProxyController(repository: repo), permanent: true);

    await tester.pumpWidget(const AntigravityApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    Get.find<AppController>().currentIndex.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final controller = Get.find<ApiProxyController>();
    controller.tab.value = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final button = find.widgetWithText(AppButton, 'Regenerate');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(repo.rotateCalls, 1);
    expect(controller.keyController.text, 'sk-fake-rotated');
    expect(controller.proxy.value.apiKey, 'sk-fake-rotated');
  });
}
