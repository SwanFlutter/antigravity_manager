import 'package:antigravity_manager/core/data/mock_data.dart';
import 'package:antigravity_manager/data/accounts_repository.dart';
import 'package:antigravity_manager/data/host/host_client.dart';
import 'package:antigravity_manager/data/host/pipe_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canned JSON-RPC results/errors, without opening a real host connection.
class FakeTransport implements HostTransport {
  FakeTransport(
    this.answers, {
    Map<String, Map<String, dynamic>>? errors,
    Map<String, HostUnavailable>? failures,
  }) : errors = errors ?? {},
       failures = failures ?? {};

  final Map<String, Map<String, dynamic>> answers;
  final Map<String, Map<String, dynamic>> errors;
  final Map<String, HostUnavailable> failures;
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> parameters = [];

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    calls.add(method);
    parameters.add(Map<String, dynamic>.from(params));
    final failure = failures[method];
    if (failure != null) throw failure;
    final error = errors[method];
    if (error != null) {
      return {'jsonrpc': '2.0', 'id': 1, 'error': error};
    }
    final answer = answers[method];
    if (answer == null) {
      throw HostUnavailable('no answer for $method');
    }
    return {'jsonrpc': '2.0', 'id': 1, 'result': answer};
  }
}

Map<String, dynamic> hostInfoPayload() => {
  'contractVersion': kContractVersion,
  'appVersion': '0.1.0',
  'profilePath': 'profile.sqlite3',
};

Map<String, dynamic> accountRow({
  String id = 'real-account',
  String status = 'active',
  bool demo = false,
  List<Map<String, dynamic>> quotas = const [],
  List<Map<String, dynamic>> weeklyQuotas = const [],
}) => {
  'id': id,
  'name': id,
  'handle': '$id@example.com',
  'provider': 'Google',
  'plan': 'Google AI Pro',
  'status': status,
  'demo': demo,
  'quotas': quotas,
  'weeklyQuotas': weeklyQuotas,
};

Matcher hostError(int code, String message) => isA<HostError>()
    .having((error) => error.code, 'code', code)
    .having((error) => error.message, 'message', message);

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

  test(
    'a broken host propagates HostUnavailable instead of demo accounts',
    () async {
      final failure = HostUnavailable('the host is not running');
      final transport = FakeTransport(
        {},
        failures: {HostMethods.hostInfo: failure},
      );
      final repository = HostAccountsRepository(
        client: HostClient(transport: transport),
      );

      await expectLater(repository.load(), throwsA(same(failure)));

      expect(repository.isLive, isFalse);
      expect(transport.calls, [HostMethods.hostInfo]);
    },
  );

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

    await expectLater(
      repository.load(),
      throwsA(
        isA<HostError>().having(
          (error) => error.isVersionMismatch,
          'isVersionMismatch',
          isTrue,
        ),
      ),
    );

    expect(repository.isLive, isFalse);
    expect(transport.calls, [HostMethods.hostInfo]);
  });

  test('an empty host stays empty even with a nonempty host summary', () async {
    final transport = FakeTransport({
      HostMethods.hostInfo: hostInfoPayload(),
      HostMethods.accountsList: {
        'accounts': <Map<String, dynamic>>[],
        'summary': {
          'total': 99,
          'active': 80,
          'rateLimited': 19,
          'globalRemaining': 0.9,
        },
      },
    });
    final repository = HostAccountsRepository(
      client: HostClient(transport: transport),
    );

    final snapshot = await repository.load();

    expect(repository.isLive, isTrue);
    expect(snapshot.accounts, isEmpty);
    expect(snapshot.activeCount, 0);
    expect(snapshot.rateLimitedCount, 0);
    expect(snapshot.globalRemaining, 0);
  });

  test(
    'demo rows are filtered and host summary is recomputed from real rows',
    () async {
      final transport = FakeTransport({
        HostMethods.hostInfo: hostInfoPayload(),
        HostMethods.accountsList: {
          'accounts': [
            accountRow(
              id: 'demo-active',
              demo: true,
              quotas: [
                {'name': 'Synthetic quota', 'remaining': 1},
              ],
            ),
            accountRow(id: 'demo-limited', demo: true, status: 'rateLimited'),
            accountRow(
              id: 'real-active',
              quotas: [
                {'name': 'Model A', 'remaining': 0.8},
                {'name': 'Model B', 'remaining': 0.4},
              ],
            ),
            accountRow(
              id: 'real-limited',
              status: 'rateLimited',
              quotas: [
                {'name': 'Model A', 'remaining': 0.2},
              ],
            ),
            accountRow(id: 'unknown-active'),
            accountRow(id: 'unknown-error', status: 'error'),
          ],
          'summary': {
            'total': 200,
            'active': 150,
            'rateLimited': 50,
            'globalRemaining': 0.99,
          },
        },
      });
      final repository = HostAccountsRepository(
        client: HostClient(transport: transport),
      );

      final snapshot = await repository.load();

      expect(snapshot.accounts.map((account) => account.id), [
        'real-active',
        'real-limited',
        'unknown-active',
        'unknown-error',
      ]);
      expect(snapshot.accounts.every((account) => !account.demo), isTrue);
      expect(snapshot.activeCount, 2);
      expect(snapshot.rateLimitedCount, 1);
      // Mean of real account means: ((0.8 + 0.4) / 2 + 0.2) / 2.
      // Unknown quotas count as accounts, but not as exhausted allowances.
      expect(snapshot.globalRemaining, closeTo(0.4, 1e-9));
    },
  );

  test('a demo-only host produces an empty snapshot', () async {
    final transport = FakeTransport({
      HostMethods.hostInfo: hostInfoPayload(),
      HostMethods.accountsList: {
        'accounts': [
          accountRow(
            demo: true,
            quotas: [
              {'name': 'Synthetic quota', 'remaining': 1},
            ],
          ),
        ],
        'summary': {
          'total': 1,
          'active': 1,
          'rateLimited': 0,
          'globalRemaining': 1,
        },
      },
    });
    final repository = HostAccountsRepository(
      client: HostClient(transport: transport),
    );

    final snapshot = await repository.load();

    expect(snapshot.accounts, isEmpty);
    expect(snapshot.activeCount, 0);
    expect(snapshot.rateLimitedCount, 0);
    expect(snapshot.globalRemaining, 0);
    expect(repository.isLive, isTrue);
  });

  test(
    'only unknown quotas produce a finite zero summary, not demo quotas',
    () async {
      final transport = FakeTransport({
        HostMethods.hostInfo: hostInfoPayload(),
        HostMethods.accountsList: {
          'accounts': [accountRow()],
        },
      });
      final repository = HostAccountsRepository(
        client: HostClient(transport: transport),
      );

      final snapshot = await repository.load();

      expect(snapshot.accounts, hasLength(1));
      expect(snapshot.accounts.single.quotas, isEmpty);
      expect(snapshot.accounts.single.weeklyQuotas, isEmpty);
      expect(snapshot.activeCount, 1);
      expect(snapshot.rateLimitedCount, 0);
      expect(snapshot.globalRemaining, 0);
    },
  );

  test(
    'a genuine zero quota participates in the summary denominator',
    () async {
      final transport = FakeTransport({
        HostMethods.hostInfo: hostInfoPayload(),
        HostMethods.accountsList: {
          'accounts': [
            accountRow(
              id: 'available',
              quotas: [
                {'name': 'Model A', 'remaining': 0.8},
              ],
            ),
            accountRow(
              id: 'exhausted',
              status: 'rateLimited',
              quotas: [
                {'name': 'Model A', 'remaining': 0},
              ],
            ),
            accountRow(id: 'unknown'),
          ],
        },
      });
      final repository = HostAccountsRepository(
        client: HostClient(transport: transport),
      );

      final snapshot = await repository.load();

      expect(snapshot.accounts, hasLength(3));
      expect(snapshot.accounts[1].quotas.single.remaining, 0);
      expect(snapshot.globalRemaining, closeTo(0.4, 1e-9));
    },
  );

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

    expect(transport.calls, [
      HostMethods.hostInfo,
      HostMethods.accountsList,
      HostMethods.accountsSetActive,
      HostMethods.accountsSetSelected,
    ]);
    expect(transport.parameters, [
      {},
      {},
      {'id': 'acc-01'},
      {'id': 'acc-01', 'selected': true},
    ]);
  });

  final operations =
      <
        ({
          String method,
          Map<String, dynamic> params,
          Future<dynamic> Function(HostAccountsRepository) invoke,
        })
      >[
        (
          method: HostMethods.accountsSetActive,
          params: {'id': 'acc-01'},
          invoke: (repository) => repository.setActive('acc-01'),
        ),
        (
          method: HostMethods.accountsSetSelected,
          params: {'id': 'acc-01', 'selected': false},
          invoke: (repository) => repository.setSelected('acc-01', false),
        ),
        (
          method: HostMethods.modelsCatalog,
          params: {},
          invoke: (repository) => repository.modelCatalog(),
        ),
        (
          method: HostMethods.accountsRefreshQuota,
          params: {'id': 'acc-01'},
          invoke: (repository) => repository.refreshQuota('acc-01'),
        ),
        (
          method: HostMethods.accountsRemove,
          params: {'id': 'acc-01'},
          invoke: (repository) => repository.removeAccount('acc-01'),
        ),
        (
          method: HostMethods.accountsStartConnect,
          params: {},
          invoke: (repository) => repository.startConnect(),
        ),
        (
          method: HostMethods.accountsConnected,
          params: {},
          invoke: (repository) => repository.connectedAccounts(),
        ),
        (
          method: HostMethods.proxyStatus,
          params: {},
          invoke: (repository) => repository.proxyStatus(),
        ),
        (
          method: HostMethods.trafficList,
          params: {'limit': 7},
          invoke: (repository) => repository.traffic(limit: 7),
        ),
        (
          method: HostMethods.workspacesList,
          params: {},
          invoke: (repository) => repository.workspaces(),
        ),
      ];

  for (final operation in operations) {
    test(
      '${operation.method} propagates failure even before the first load',
      () async {
        final failure = HostUnavailable('the host is not running');
        final transport = FakeTransport(
          {},
          failures: {operation.method: failure},
        );
        final repository = HostAccountsRepository(
          client: HostClient(transport: transport),
        );

        await expectLater(operation.invoke(repository), throwsA(same(failure)));

        expect(repository.isLive, isFalse);
        expect(transport.calls, [operation.method]);
        expect(transport.parameters, [operation.params]);
      },
    );

    test(
      '${operation.method} propagates provider errors and stays live',
      () async {
        const code = -32001;
        const message = 'provider rejected the request';
        final transport = FakeTransport(
          {
            HostMethods.hostInfo: hostInfoPayload(),
            HostMethods.accountsList: accountPayload(),
          },
          errors: {
            operation.method: {'code': code, 'message': message},
          },
        );
        final repository = HostAccountsRepository(
          client: HostClient(transport: transport),
        );
        await repository.load();
        expect(repository.isLive, isTrue);

        await expectLater(
          operation.invoke(repository),
          throwsA(hostError(code, message)),
        );

        expect(repository.isLive, isTrue);
        expect(transport.calls, [
          HostMethods.hostInfo,
          HostMethods.accountsList,
          operation.method,
        ]);
        expect(transport.parameters.last, operation.params);
      },
    );

    test(
      '${operation.method} propagates transport failures and goes offline',
      () async {
        final failure = HostUnavailable('the host disconnected');
        final transport = FakeTransport(
          {
            HostMethods.hostInfo: hostInfoPayload(),
            HostMethods.accountsList: accountPayload(),
          },
          failures: {operation.method: failure},
        );
        final repository = HostAccountsRepository(
          client: HostClient(transport: transport),
        );
        await repository.load();
        expect(repository.isLive, isTrue);

        await expectLater(operation.invoke(repository), throwsA(same(failure)));

        expect(repository.isLive, isFalse);
        expect(transport.calls, [
          HostMethods.hostInfo,
          HostMethods.accountsList,
          operation.method,
        ]);
        expect(transport.parameters.last, operation.params);
      },
    );
  }

  test(
    'a provider error during load propagates without marking the host offline',
    () async {
      final transport = FakeTransport(
        {HostMethods.hostInfo: hostInfoPayload()},
        errors: {
          HostMethods.accountsList: {
            'code': -32001,
            'message': 'quota unavailable',
          },
        },
      );
      final repository = HostAccountsRepository(
        client: HostClient(transport: transport),
      );

      await expectLater(
        repository.load(),
        throwsA(hostError(-32001, 'quota unavailable')),
      );

      expect(repository.isLive, isTrue);
      transport.errors.clear();
      transport.answers[HostMethods.accountsList] = accountPayload();
      final recovered = await repository.load();
      expect(recovered.accounts.map((account) => account.id), ['acc-01']);
      expect(repository.isLive, isTrue);
    },
  );

  for (final method in [HostMethods.hostInfo, HostMethods.accountsList]) {
    test(
      'load recovers after $method transport failure on the same repository',
      () async {
        final failure = HostUnavailable('the host disconnected');
        final transport = FakeTransport({
          HostMethods.hostInfo: hostInfoPayload(),
          HostMethods.accountsList: accountPayload(),
        });
        final repository = HostAccountsRepository(
          client: HostClient(transport: transport),
        );
        await repository.load();
        expect(repository.isLive, isTrue);
        transport.failures[method] = failure;

        await expectLater(repository.load(), throwsA(same(failure)));
        expect(repository.isLive, isFalse);

        transport.failures.clear();
        transport.answers[HostMethods.accountsList] = {
          'accounts': [accountRow(id: 'recovered-account')],
        };
        final recovered = await repository.load();

        expect(repository.isLive, isTrue);
        expect(recovered.accounts.map((account) => account.id), [
          'recovered-account',
        ]);
        expect(recovered.activeCount, 1);
        expect(recovered.globalRemaining, 0);
        expect(transport.calls, [
          HostMethods.hostInfo,
          HostMethods.accountsList,
          HostMethods.hostInfo,
          if (method == HostMethods.accountsList) HostMethods.accountsList,
          HostMethods.hostInfo,
          HostMethods.accountsList,
        ]);
      },
    );
  }

  test(
    'a contract error after successful load propagates and marks host offline',
    () async {
      final transport = FakeTransport({
        HostMethods.hostInfo: hostInfoPayload(),
        HostMethods.accountsList: accountPayload(),
      });
      final repository = HostAccountsRepository(
        client: HostClient(transport: transport),
      );
      await repository.load();
      expect(repository.isLive, isTrue);
      transport.errors[HostMethods.accountsList] = {
        'code': -32000,
        'message': 'unsupported contract version',
      };

      await expectLater(
        repository.load(),
        throwsA(hostError(-32000, 'unsupported contract version')),
      );

      expect(repository.isLive, isFalse);
    },
  );

  test('an empty model catalog does not acquire synthetic models', () async {
    final transport = FakeTransport({
      HostMethods.modelsCatalog: {'items': []},
    });
    final repository = HostAccountsRepository(
      client: HostClient(transport: transport),
    );

    expect(await repository.modelCatalog(), isEmpty);
    expect(transport.calls, [HostMethods.modelsCatalog]);
  });

  test('model catalog contains only the host models', () async {
    final transport = FakeTransport({
      HostMethods.modelsCatalog: {
        'items': [
          {'id': 'host-model', 'label': 'Host Model', 'family': 'openai'},
        ],
      },
    });
    final repository = HostAccountsRepository(
      client: HostClient(transport: transport),
    );

    final models = await repository.modelCatalog();

    expect(models, hasLength(1));
    expect(models.single.id, 'host-model');
    expect(models.single.label, 'Host Model');
    expect(models.single.family, ModelFamily.openai);
  });

  test(
    'the mock repository reports the same summary as the domain rules',
    () async {
      final repository = MockAccountsRepository();

      final snapshot = await repository.load();

      expect(snapshot.accounts, hasLength(MockData.accounts.length));
      expect(snapshot.activeCount, greaterThan(0));

      // Synthetic data is an explicit test fixture, never a host fallback.
      expect(snapshot.globalRemaining, closeTo(0.3905095967741935, 1e-12));
      expect(repository.isLive, isFalse);
    },
  );

  for (final refresh in [false, true]) {
    final source = refresh ? 'refreshQuota' : 'load';

    HostAccountsRepository repositoryForRow(Map<String, dynamic> row) =>
        HostAccountsRepository(
          client: HostClient(
            transport: FakeTransport({
              HostMethods.hostInfo: hostInfoPayload(),
              HostMethods.accountsList: {
                'accounts': [row],
              },
              HostMethods.accountsRefreshQuota: row,
            }),
          ),
        );

    Future<Account> readAccount(HostAccountsRepository repository) async =>
        refresh
        ? (await repository.refreshQuota('real-account'))!
        : (await repository.load()).accounts.single;

    test(
      '$source parses quotaFetchedAt as int and quotaError as string',
      () async {
        final repository = repositoryForRow({
          ...accountRow(),
          'quotaFetchedAt': 1700000000123,
          'quotaError': 'HTTP 429: quota provider unavailable',
        });

        final account = await readAccount(repository);

        expect(account.id, 'real-account');
        expect(account.quotaFetchedAt, 1700000000123);
        expect(account.quotaError, 'HTTP 429: quota provider unavailable');
        expect(account.quotas, isEmpty);
        expect(account.weeklyQuotas, isEmpty);
      },
    );

    test('$source preserves absent quota metadata as null', () async {
      final account = await readAccount(repositoryForRow(accountRow()));

      expect(account.quotaFetchedAt, isNull);
      expect(account.quotaError, isNull);
    });

    test('$source preserves explicitly null quota metadata', () async {
      final account = await readAccount(
        repositoryForRow({
          ...accountRow(),
          'quotaFetchedAt': null,
          'quotaError': null,
        }),
      );

      expect(account.quotaFetchedAt, isNull);
      expect(account.quotaError, isNull);
    });

    test(
      '$source preserves a fetched timestamp without a quota error',
      () async {
        final account = await readAccount(
          repositoryForRow({
            ...accountRow(),
            'quotaFetchedAt': 1700000000456,
            'quotaError': null,
          }),
        );

        expect(account.quotaFetchedAt, 1700000000456);
        expect(account.quotaError, isNull);
      },
    );

    test(
      '$source preserves a quota error without a fetched timestamp',
      () async {
        final account = await readAccount(
          repositoryForRow({
            ...accountRow(),
            'quotaFetchedAt': null,
            'quotaError': 'quota has not been fetched',
          }),
        );

        expect(account.quotaFetchedAt, isNull);
        expect(account.quotaError, 'quota has not been fetched');
      },
    );

    test(
      '$source skips missing and malformed fractions, but retains real zero',
      () async {
        final fractions = <Map<String, dynamic>>[
          {'name': 'missing', 'groupId': 'missing'},
          {'name': 'null', 'groupId': 'null', 'remaining': null},
          {'name': 'text', 'groupId': 'text', 'remaining': 'unknown'},
          {
            'name': 'numeric-string',
            'groupId': 'numeric-string',
            'remaining': '0.5',
          },
          {'name': 'boolean', 'groupId': 'boolean', 'remaining': false},
          {
            'name': 'object',
            'groupId': 'object',
            'remaining': <String, dynamic>{},
          },
          {'name': 'list', 'groupId': 'list', 'remaining': <dynamic>[]},
          {'name': 'empty', 'groupId': 'empty', 'remaining': 0},
          {'name': 'half', 'groupId': 'half', 'remaining': 0.5},
          {'name': 'full', 'groupId': 'full', 'remaining': 1},
        ];
        final account = await readAccount(
          repositoryForRow(
            accountRow(quotas: fractions, weeklyQuotas: fractions),
          ),
        );

        expect(account.quotas.map((quota) => quota.name), [
          'empty',
          'half',
          'full',
        ]);
        expect(account.quotas.map((quota) => quota.remaining), [0, 0.5, 1]);
        expect(account.weeklyQuotas.map((quota) => quota.groupId), [
          'empty',
          'half',
          'full',
        ]);
        expect(account.weeklyQuotas.map((quota) => quota.remaining), [
          0,
          0.5,
          1,
        ]);
        expect(account.globalRemaining, closeTo(0.5, 1e-9));
      },
    );

    test(
      '$source keeps entirely invalid quota lists empty, not fake zeros',
      () async {
        final account = await readAccount(
          repositoryForRow(
            accountRow(
              quotas: [
                {'name': 'missing fraction'},
                {'name': 'invalid fraction', 'remaining': 'unavailable'},
              ],
              weeklyQuotas: [
                {'groupId': 'missing fraction'},
                {'groupId': 'invalid fraction', 'remaining': 'unavailable'},
              ],
            ),
          ),
        );

        expect(account.quotas, isEmpty);
        expect(account.weeklyQuotas, isEmpty);
      },
    );

    test(
      '$source does not invent quotas for missing or malformed quota lists',
      () async {
        for (final raw in [null, 'unavailable', <String, dynamic>{}]) {
          final row = accountRow()
            ..remove('quotas')
            ..remove('weeklyQuotas');
          if (raw != null) {
            row['quotas'] = raw;
            row['weeklyQuotas'] = raw;
          }
          final account = await readAccount(repositoryForRow(row));

          expect(account.quotas, isEmpty, reason: 'quota list: $raw');
          expect(
            account.weeklyQuotas,
            isEmpty,
            reason: 'weekly quota list: $raw',
          );
        }
      },
    );
  }

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
