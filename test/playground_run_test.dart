// Functional tests for the playground run button and the API key regenerate
// button. A real HTTP server plays the local gateway, so the request the
// controller sends and the answer it parses are both exercised.

import 'dart:convert';
import 'dart:io';

import 'package:antigravity_manager/app/controller/api_proxy_controller.dart';
import 'package:antigravity_manager/app/controller/app_controller.dart';
import 'package:antigravity_manager/app/controller/playground_controller.dart';
import 'package:antigravity_manager/core/data/mock_data.dart';
import 'package:antigravity_manager/data/accounts_repository.dart';
import 'package:antigravity_manager/data/cloud_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_x_master/get_x_master.dart';

/// A repository that points the controllers at a local HTTP server.
class FakeGatewayRepository implements AccountsRepository {
  FakeGatewayRepository(this.server, {this.running = true});

  final HttpServer server;
  final bool running;

  final List<String> activeCalls = [];
  int rotateCalls = 0;

  ProxyStatus _status(String key) => ProxyStatus(
    running: running,
    port: server.port,
    baseUrl: 'http://127.0.0.1:${server.port}',
    models: 2,
    apiKey: key,
    selectedAccountId: 'acc-01',
  );

  @override
  Future<AccountSnapshot> load() async => AccountSnapshot(
    accounts: [fakeAccount('acc-01'), fakeAccount('acc-02')],
    activeCount: 2,
    rateLimitedCount: 0,
    globalRemaining: 1,
  );

  @override
  Future<void> setActive(String id) async {
    activeCalls.add(id);
  }

  @override
  Future<void> setSelected(String id, bool selected) async {}

  @override
  Future<List<CatalogModel>> modelCatalog() async => const [
    CatalogModel(
      id: 'gemini-2.5-flash',
      label: 'Gemini Flash',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'claude-sonnet-4-6',
      label: 'Claude',
      family: ModelFamily.claude,
    ),
  ];

  @override
  bool get isLive => true;

  @override
  Future<ConnectSession> startConnect() async => throw UnimplementedError();

  @override
  Future<ConnectState> connectStatus(String sessionId) async =>
      throw UnimplementedError();

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
  Future<ProxyStatus> proxyStatus() async => _status('sk-test-key');

  @override
  Future<ProxyStatus> startProxy({int? port}) async => _status('sk-test-key');

  @override
  Future<ProxyStatus> stopProxy() async => ProxyStatus(
    running: false,
    port: server.port,
    baseUrl: 'http://127.0.0.1:${server.port}',
    models: 2,
  );

  @override
  Future<ProxyStatus> rotateProxyKey() async {
    rotateCalls++;
    return _status('sk-rotated-$rotateCalls');
  }

  @override
  Future<List<TrafficRecord>> traffic({int limit = 100}) async => const [];

  @override
  Future<List<Workspace>> workspaces() async => const [];
}

/// Builds one fake account for the pool.
Account fakeAccount(String id) => Account(
  id: id,
  name: 'Account $id',
  handle: '$id@example.com',
  provider: 'Google',
  plan: 'Google AI Pro',
  status: AccountStatus.active,
  credits: 100,
  inUse: id == 'acc-01',
  quotas: const [],
);

/// The requests the fake gateway received.
class GatewayLog {
  final List<String> authorizations = [];
  final List<Map<String, dynamic>> bodies = [];
}

/// Starts a fake gateway that answers like the real proxy.
Future<(HttpServer, GatewayLog)> startFakeGateway({
  int? failStatus,
  String? errorBody,
}) async {
  final log = GatewayLog();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final body = await utf8.decoder.bind(request).join();
    log.authorizations.add(
      request.headers.value(HttpHeaders.authorizationHeader) ?? '',
    );
    final payload = jsonDecode(body) as Map<String, dynamic>;
    log.bodies.add(payload);

    if (failStatus != null) {
      request.response.statusCode = failStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        errorBody ??
            jsonEncode({
              'error': {
                'message': 'invalid_api_key',
                'code': 'invalid_api_key',
              },
            }),
      );
      await request.response.close();
      return;
    }

    request.response.statusCode = 200;
    if (payload['stream'] == true) {
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write(
        'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":" world"}}],"usage":{"total_tokens":7}}\n\n'
        'data: [DONE]\n\n',
      );
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Hi there'},
            },
          ],
          'usage': {'total_tokens': 5},
        }),
      );
    }
    await request.response.close();
  });
  return (server, log);
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(AppController(), permanent: true);
  });

  tearDown(() {
    Get.reset();
  });

  test(
    'the run button streams a chat completion through the gateway',
    () async {
      final (server, log) = await startFakeGateway();
      addTearDown(server.close);
      final repo = FakeGatewayRepository(server);
      final controller = PlaygroundController(repository: repo);
      addTearDown(controller.dispose);

      controller.promptController.text = 'Say hi';
      await controller.run();

      final result = controller.lastResult.value;
      expect(result, isNotNull);
      expect(result!.isError, isFalse);
      expect(result.text, 'Hello world');
      expect(result.tokens, 7);
      expect(result.latencyMs, greaterThanOrEqualTo(0));
      expect(controller.running.value, isFalse);
      expect(log.authorizations, ['Bearer sk-test-key']);
      expect(log.bodies.single['model'], controller.model.value);
      expect(log.bodies.single['stream'], true);
    },
  );

  test('a non streaming run reads the plain JSON answer', () async {
    final (server, log) = await startFakeGateway();
    addTearDown(server.close);
    final repo = FakeGatewayRepository(server);
    final controller = PlaygroundController(repository: repo);
    addTearDown(controller.dispose);

    controller.stream.value = false;
    controller.promptController.text = 'Say hi';
    await controller.run();

    final result = controller.lastResult.value!;
    expect(result.isError, isFalse);
    expect(result.text, 'Hi there');
    expect(result.tokens, 5);
    expect(log.bodies.single['stream'], false);
  });

  test('the compare tab runs the prompt on every selected account', () async {
    final (server, log) = await startFakeGateway();
    addTearDown(server.close);
    final repo = FakeGatewayRepository(server);
    final controller = PlaygroundController(repository: repo);
    addTearDown(controller.dispose);

    controller.tab.value = PlaygroundTab.compare;
    controller.accounts.assignAll([
      fakeAccount('acc-01'),
      fakeAccount('acc-02'),
    ]);
    controller.compareAccounts.assignAll({'acc-01'});
    controller.promptController.text = 'Compare';
    await controller.run();

    expect(controller.results.keys, ['acc-01']);
    expect(controller.results['acc-01']!.text, 'Hello world');
    expect(repo.activeCalls, ['acc-01']);
    expect(log.bodies, hasLength(1));
  });

  test('an upstream error becomes a readable result card', () async {
    final (server, _) = await startFakeGateway(failStatus: 401);
    addTearDown(server.close);
    final repo = FakeGatewayRepository(server);
    final controller = PlaygroundController(repository: repo);
    addTearDown(controller.dispose);

    controller.promptController.text = 'hi';
    await controller.run();

    final result = controller.lastResult.value!;
    expect(result.isError, isTrue);
    expect(result.error, contains('HTTP 401'));
    expect(result.error, contains('invalid_api_key'));
  });

  test('policy errors retain complete nested provider diagnostics', () async {
    final explanation = List.filled(
      30,
      'The provider restricted this account.',
    ).join(' ');
    final provider = {
      'error': {
        'code': 403,
        'message': explanation,
        'details': [
          {
            'reason': 'TOS_VIOLATION',
            'metadata': {'appeal_url_link_text': 'Submit Appeal'},
          },
        ],
      },
    };
    final (server, log) = await startFakeGateway(
      failStatus: 403,
      errorBody: jsonEncode({
        'error': {'message': jsonEncode(provider)},
      }),
    );
    addTearDown(server.close);
    final controller = PlaygroundController(
      repository: FakeGatewayRepository(server),
    );
    addTearDown(controller.dispose);
    await controller.run();
    final result = controller.lastResult.value!;
    expect(result.status, 403);
    expect(result.displayText, contains(explanation));
    expect(result.displayText, contains('TOS_VIOLATION'));
    expect(result.displayText, contains('Submit Appeal'));
    expect(log.bodies, hasLength(1));
  });

  for (final body in [
    'upstream unavailable',
    '<html>Bad gateway</html>',
    '["failure"]',
  ]) {
    test('non-object HTTP error retains status and content: $body', () async {
      final (server, _) = await startFakeGateway(
        failStatus: 502,
        errorBody: body,
      );
      addTearDown(server.close);
      final controller = PlaygroundController(
        repository: FakeGatewayRepository(server),
      );
      addTearDown(controller.dispose);
      await controller.run();
      expect(controller.lastResult.value!.status, 502);
      expect(controller.lastResult.value!.displayText, contains('HTTP 502'));
      expect(
        controller.lastResult.value!.displayText,
        contains(body.startsWith('[') ? 'failure' : body),
      );
    });
  }

  test('clear all never sends a request to the whole account pool', () async {
    final (server, log) = await startFakeGateway();
    addTearDown(server.close);
    final repo = FakeGatewayRepository(server);
    final controller = PlaygroundController(repository: repo);
    addTearDown(controller.dispose);
    await controller.loadSources();
    controller.tab.value = PlaygroundTab.compare;
    controller.clearAllCompare();
    await controller.run();
    expect(log.bodies, isEmpty);
    expect(repo.activeCalls, isEmpty);
    expect(controller.runError.value, isNotNull);
  });

  test('loading the catalog aligns selected model ids', () async {
    final (server, _) = await startFakeGateway();
    addTearDown(server.close);
    final controller = PlaygroundController(
      repository: FakeGatewayRepository(server),
    );
    addTearDown(controller.dispose);
    await controller.loadSources();
    expect(controller.models, contains(controller.model.value));
    expect(controller.models, contains(controller.secondModel.value));
  });

  test('run refuses to send while the gateway is offline', () async {
    final (server, log) = await startFakeGateway();
    addTearDown(server.close);
    final repo = FakeGatewayRepository(server, running: false);
    final controller = PlaygroundController(repository: repo);
    addTearDown(controller.dispose);

    controller.promptController.text = 'hi';
    await controller.run();

    expect(controller.lastResult.value!.isError, isTrue);
    expect(controller.lastResult.value!.error, contains('offline'));
    expect(controller.runError.value, contains('offline'));
    expect(log.bodies, isEmpty);
  });

  test('regenerate replaces the key and updates the key field', () async {
    final (server, _) = await startFakeGateway();
    addTearDown(server.close);
    final repo = FakeGatewayRepository(server);
    final controller = ApiProxyController(repository: repo);
    addTearDown(controller.dispose);

    await controller.rotateKey();
    await controller.rotateKey();

    expect(repo.rotateCalls, 2);
    expect(controller.keyController.text, 'sk-rotated-2');
    expect(controller.proxy.value.apiKey, 'sk-rotated-2');
  });
}
