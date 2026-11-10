import 'package:antigravity_manager/core/data/mock_data.dart';
import 'package:antigravity_manager/data/accounts_repository.dart';
import 'package:antigravity_manager/data/host/host_client.dart';
import 'package:antigravity_manager/data/host/pipe_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// A transport that answers with canned payloads.
class FakeTransport implements HostTransport {
  FakeTransport(this.answers);

  final Map<String, Map<String, dynamic>> answers;
  final List<String> calls = <String>[];

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    calls.add(method);
    final answer = answers[method];
    if (answer == null) {
      throw HostUnavailable('no answer for $method');
    }
    return <String, dynamic>{
      'jsonrpc': '2.0',
      'id': 1,
      'result': answer,
    };
  }
}

/// A transport that always fails, like a host that is not running.
class BrokenTransport implements HostTransport {
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    throw HostUnavailable('the host is not running');
  }
}

Map<String, dynamic> accountPayload() => {
      'accounts': [
        {
          'id': 'acc-01',
          'name': 'Northwind Studio',
          'handle': 'northwind.studio@example.com',
          'provider': 'Google',
          'plan': 'Google AI Pro',
          'status': 'rateLimited',
          'credits': 2400,
          'inUse': true,
          'recommended': true,
          'quotas': [
            {
              'name': 'Gemini 3.8 Flash (High)',
              'family': 'gemini',
              'remaining': 0.8,
              'resetLabel': '6d 21h',
            },
            {
              'name': 'Claude Sonnet 4.6',
              'family': 'claude',
              'remaining': 0.3,
              'resetLabel': '42m',
            },
          ],
          'weeklyQuotas': [
            {
              'groupId': 'gemini',
              'groupLabel': 'Gemini models',
              'remaining': 0.86,
              'resetLabel': '6d 23h',
            },
          ],
        },
      ],
      'summary': {
        'total': 1,
        'active': 0,
        'rateLimited': 1,
        'globalRemaining': 0.55,
      },
    };

void main() {
  test('the host payload is mapped onto the domain models', () async {
    final transport = FakeTransport({
      HostMethods.hostInfo: {
        'contractVersion': kContractVersion,
        'appVersion': '0.1.0',
        'profilePath': 'profile.sqlite3',
      },
      HostMethods.accountsList: accountPayload(),
    });

    final repository = HostAccountsRepository(
      client: HostClient(transport: transport),
    );

    final snapshot = await repository.load();

    expect(repository.isLive, isTrue);
    expect(snapshot.accounts, hasLength(1));
    expect(snapshot.rateLimitedCount, 1);
    expect(snapshot.globalRemaining, closeTo(0.55, 1e-9));

    final account = snapshot.accounts.first;
    expect(account.id, 'acc-01');
    expect(account.status, AccountStatus.rateLimited);
    expect(account.inUse, isTrue);
    expect(account.quotas, hasLength(2));
    expect(account.quotas.first.family, ModelFamily.gemini);
    expect(account.quotas.last.family, ModelFamily.claude);
    expect(account.weeklyOf('gemini')?.remaining, closeTo(0.86, 1e-9));
  });

  test('a broken host falls back to the in process fake', () async {
    final repository = HostAccountsRepository(
      client: HostClient(transport: BrokenTransport()),
    );

    final snapshot = await repository.load();

    expect(repository.isLive, isFalse);
    expect(snapshot.accounts, hasLength(MockData.accounts.length));
  });

  test('a host that speaks another contract version is refused', () async {
    final transport = FakeTransport({
      HostMethods.hostInfo: {
        'contractVersion': kContractVersion + 1,
        'appVersion': '0.2.0',
        'profilePath': 'profile.sqlite3',
      },
    });

    final repository = HostAccountsRepository(
      client: HostClient(transport: transport),
    );

    final snapshot = await repository.load();

    expect(repository.isLive, isFalse);
    expect(snapshot.accounts, hasLength(MockData.accounts.length));
  });

  test('the selection and the active account reach the host', () async {
    final transport = FakeTransport({
      HostMethods.hostInfo: {
        'contractVersion': kContractVersion,
        'appVersion': '0.1.0',
        'profilePath': 'profile.sqlite3',
      },
      HostMethods.accountsList: accountPayload(),
      HostMethods.accountsSetActive: {'ok': true},
      HostMethods.accountsSetSelected: {'ok': true},
    });

    final repository = HostAccountsRepository(
      client: HostClient(transport: transport),
    );

    await repository.load();
    await repository.setActive('acc-01');
    await repository.setSelected('acc-01', true);

    expect(
      transport.calls,
      containsAll(<String>[
        HostMethods.accountsSetActive,
        HostMethods.accountsSetSelected,
      ]),
    );
  });

  test('the mock repository reports the same summary as the domain rules',
      () async {
    final repository = MockAccountsRepository();

    final snapshot = await repository.load();

    expect(snapshot.accounts, hasLength(MockData.accounts.length));
    expect(snapshot.activeCount, greaterThan(0));

    // The Rust host computes the same numbers with the same seed, so the
    // interface looks the same with and without a running host.
    expect(snapshot.globalRemaining, closeTo(0.3905095967741935, 1e-12));
    expect(repository.isLive, isFalse);
  });

  test('the connection session is read out of the host answer', () async {
    final transport = FakeTransport({
      HostMethods.accountsStartConnect: {
        'sessionId': 'session-1',
        'authorizationUrl': 'https://accounts.google.com/o/oauth2/v2/auth?x=1',
        'redirectUri': 'http://127.0.0.1:5000/oauth-callback',
        'expiresAt': 1700000000000,
      },
    });

    final repository = HostAccountsRepository(
      client: HostClient(transport: transport),
    );

    final session = await repository.startConnect();

    expect(session.sessionId, 'session-1');
    expect(session.authorizationUrl, contains('accounts.google.com'));
    expect(session.redirectUri, 'http://127.0.0.1:5000/oauth-callback');
    expect(session.expiresAt, 1700000000000);
  });

  test('the state of a connection is read out of the host answer', () async {
    final transport = FakeTransport({
      HostMethods.accountsConnectStatus: {
        'status': 'completed',
        'email': 'user@example.com',
      },
    });

    final repository = HostAccountsRepository(
      client: HostClient(transport: transport),
    );

    final state = await repository.connectStatus('session-1');

    expect(state.isCompleted, isTrue);
    expect(state.email, 'user@example.com');
    expect(state.error, isNull);
  });

  test('the state of the proxy is read out of the host answer', () async {
    final transport = FakeTransport({
      HostMethods.proxyStatus: {
        'running': true,
        'port': 8045,
        'baseUrl': 'http://127.0.0.1:8045',
        'apiKey': 'sk-0123456789abcdef',
        'selectedAccountId': 'google-1',
        'models': 31,
      },
    });

    final repository = HostAccountsRepository(
      client: HostClient(transport: transport),
    );

    final status = await repository.proxyStatus();

    expect(status.running, isTrue);
    expect(status.port, 8045);
    expect(status.baseUrl, 'http://127.0.0.1:8045');
    expect(status.apiKey, 'sk-0123456789abcdef');
    expect(status.selectedAccountId, 'google-1');
    expect(status.models, 31);
  });

  test('the traffic log is read out of the host answer', () async {
    final transport = FakeTransport({
      HostMethods.trafficList: {
        'items': [
          {
            'id': 7,
            'at': 1700000000000,
            'protocol': 'openai',
            'model': 'gemini-3.8-flash-high',
            'accountId': 'google-1',
            'status': 200,
            'durationMs': 420,
            'requestBytes': 128,
            'responseBytes': 512,
          },
        ],
      },
    });

    final repository = HostAccountsRepository(
      client: HostClient(transport: transport),
    );

    final entries = await repository.traffic();

    expect(entries, hasLength(1));
    expect(entries.first.id, 7);
    expect(entries.first.protocol, 'openai');
    expect(entries.first.model, 'gemini-3.8-flash-high');
    expect(entries.first.isSuccess, isTrue);
    expect(entries.first.durationMs, 420);
  });
}
