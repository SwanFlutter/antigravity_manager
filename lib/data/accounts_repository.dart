import 'dart:io';

import '../core/data/mock_data.dart';
import 'cloud_models.dart';
import 'host/host_client.dart';
import 'host/pipe_transport.dart';

/// The accounts and the aggregate counters of one snapshot.
class AccountSnapshot {
  const AccountSnapshot({
    required this.accounts,
    required this.activeCount,
    required this.rateLimitedCount,
    required this.globalRemaining,
  });

  const AccountSnapshot.empty()
      : accounts = const [],
        activeCount = 0,
        rateLimitedCount = 0,
        globalRemaining = 0;

  final List<Account> accounts;
  final int activeCount;
  final int rateLimitedCount;
  final double globalRemaining;
}

/// The source of the account pool.
///
/// The interface hides whether the data comes from the Rust host or from the
/// in process fake, so the controllers do not care.
abstract class AccountsRepository {
  /// Reads the account pool.
  Future<AccountSnapshot> load();

  /// Marks one account as the account used by the desktop clients.
  Future<void> setActive(String id);

  /// Adds or removes an account from the selection.
  Future<void> setSelected(String id, bool selected);

  /// Reads the catalog of models the gateway can route to.
  Future<List<CatalogModel>> modelCatalog();

  /// Whether the repository is served by the running Rust host.
  bool get isLive => false;

  // --- Cloud accounts ---------------------------------------------------

  /// Starts an OAuth session and returns the URL the browser has to open.
  Future<ConnectSession> startConnect();

  /// Reads the state of an OAuth session.
  Future<ConnectState> connectStatus(String sessionId);

  /// Finishes an OAuth session with a code the user copied by hand.
  Future<void> submitCode(String sessionId, String code);

  /// Refreshes the quota of one account from the provider.
  Future<Account?> refreshQuota(String id);

  /// Removes one account with its credentials.
  Future<void> removeAccount(String id);

  /// Lists the accounts that are connected with real credentials.
  Future<List<ConnectedAccount>> connectedAccounts();

  // --- Local proxy ------------------------------------------------------

  /// Reads the state of the local proxy.
  Future<ProxyStatus> proxyStatus();

  /// Starts the local proxy.
  Future<ProxyStatus> startProxy({int? port});

  /// Stops the local proxy.
  Future<ProxyStatus> stopProxy();

  /// Replaces the key of the local proxy.
  Future<ProxyStatus> rotateProxyKey();

  /// The newest requests that passed through the local proxy.
  Future<List<TrafficRecord>> traffic({int limit = 100});

  /// The workspaces of the imported upstream installation.
  Future<List<Workspace>> workspaces();
}

/// The repository the application uses.
///
/// The application talks to the Rust host. The tests never do: a host that
/// happens to run on the machine would make the golden files of the screens
/// different on every machine.
AccountsRepository defaultAccountsRepository() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return MockAccountsRepository();
  }
  return HostAccountsRepository();
}

/// The in process fake used by the prototype and by the tests.
class MockAccountsRepository implements AccountsRepository {
  MockAccountsRepository({List<Account>? accounts})
      : _accounts = accounts ?? MockData.accounts;

  final List<Account> _accounts;

  @override
  Future<AccountSnapshot> load() async => _snapshot(_accounts);

  @override
  Future<void> setActive(String id) async {}

  @override
  Future<void> setSelected(String id, bool selected) async {}

  @override
  Future<List<CatalogModel>> modelCatalog() async => MockData.modelCatalog;

  @override
  bool get isLive => false;

  @override
  Future<ConnectSession> startConnect() async {
    throw HostUnavailable('the account host is not running');
  }

  @override
  Future<ConnectState> connectStatus(String sessionId) async {
    throw HostUnavailable('the account host is not running');
  }

  @override
  Future<void> submitCode(String sessionId, String code) async {
    throw HostUnavailable('the account host is not running');
  }

  @override
  Future<Account?> refreshQuota(String id) async => null;

  @override
  Future<void> removeAccount(String id) async {}

  @override
  Future<List<ConnectedAccount>> connectedAccounts() async => const [];

  @override
  Future<ProxyStatus> proxyStatus() async => const ProxyStatus.empty();

  @override
  Future<ProxyStatus> startProxy({int? port}) async {
    throw HostUnavailable('the account host is not running');
  }

  @override
  Future<ProxyStatus> stopProxy() async => const ProxyStatus.empty();

  @override
  Future<ProxyStatus> rotateProxyKey() async {
    throw HostUnavailable('the account host is not running');
  }

  @override
  Future<List<TrafficRecord>> traffic({int limit = 100}) async => const [];

  @override
  Future<List<Workspace>> workspaces() async => MockData.workspaces;

  /// Builds the snapshot of a list of accounts.
  static AccountSnapshot _snapshot(List<Account> accounts) {
    if (accounts.isEmpty) return const AccountSnapshot.empty();

    final active = accounts
        .where((account) => account.status == AccountStatus.active)
        .length;
    final rateLimited = accounts
        .where((account) => account.status == AccountStatus.rateLimited)
        .length;
    final total = accounts.fold<double>(
      0,
      (sum, account) => sum + account.globalRemaining,
    );

    return AccountSnapshot(
      accounts: accounts,
      activeCount: active,
      rateLimitedCount: rateLimited,
      globalRemaining: total / accounts.length,
    );
  }
}

/// The repository backed by the Rust host.
///
/// When the host is not running, the repository falls back to the in process
/// fake so the interface keeps working while the core is being developed.
class HostAccountsRepository implements AccountsRepository {
  HostAccountsRepository({HostClient? client, AccountsRepository? fallback})
      : _client = client ?? HostClient(),
        _fallback = fallback ?? MockAccountsRepository();

  final HostClient _client;
  final AccountsRepository _fallback;

  bool _live = false;

  /// Whether the last call was answered by the running host.
  @override
  bool get isLive => _live;

  @override
  Future<AccountSnapshot> load() async {
    try {
      final info = await _client.hostInfo();
      if (!info.isCompatible) {
        throw HostError(
          -32000,
          'the host speaks contract version ${info.contractVersion}',
        );
      }

      final payload = await _client.accountsList();
      final accounts = _parseAccounts(payload);
      _live = true;

      final summary = payload['summary'] as Map<String, dynamic>?;
      return AccountSnapshot(
        accounts: accounts,
        activeCount: (summary?['active'] as num?)?.toInt() ?? 0,
        rateLimitedCount: (summary?['rateLimited'] as num?)?.toInt() ?? 0,
        globalRemaining:
            (summary?['globalRemaining'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      _live = false;
      return _fallback.load();
    }
  }

  @override
  Future<void> setActive(String id) async {
    if (!_live) return _fallback.setActive(id);
    try {
      await _client.setActiveAccount(id);
    } catch (_) {
      _live = false;
      await _fallback.setActive(id);
    }
  }

  @override
  Future<void> setSelected(String id, bool selected) async {
    if (!_live) return _fallback.setSelected(id, selected);
    try {
      await _client.setAccountSelected(id, selected);
    } catch (_) {
      _live = false;
      await _fallback.setSelected(id, selected);
    }
  }

  @override
  Future<List<CatalogModel>> modelCatalog() async {
    if (!_live) return _fallback.modelCatalog();
    try {
      final items = await _client.modelsCatalog();
      return items
          .map(
            (item) => CatalogModel(
              id: item['id'] as String? ?? '',
              label: item['label'] as String? ?? '',
              family: _parseFamily(item['family'] as String?),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      _live = false;
      return _fallback.modelCatalog();
    }
  }

  // --- Cloud accounts ---------------------------------------------------

  @override
  Future<ConnectSession> startConnect() async {
    final payload = await _client.startConnect();
    return ConnectSession(
      sessionId: payload['sessionId'] as String? ?? '',
      authorizationUrl: payload['authorizationUrl'] as String? ?? '',
      redirectUri: payload['redirectUri'] as String? ?? '',
      expiresAt: (payload['expiresAt'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<ConnectState> connectStatus(String sessionId) async {
    final payload = await _client.connectStatus(sessionId);
    return ConnectState(
      status: payload['status'] as String? ?? 'pending',
      email: payload['email'] as String?,
      error: payload['error'] as String?,
    );
  }

  @override
  Future<void> submitCode(String sessionId, String code) =>
      _client.submitCode(sessionId, code);

  @override
  Future<Account?> refreshQuota(String id) async {
    if (!_live) return _fallback.refreshQuota(id);
    try {
      final payload = await _client.refreshQuota(id);
      final accounts = _parseAccounts({'accounts': [payload]});
      return accounts.isEmpty ? null : accounts.first;
    } catch (_) {
      _live = false;
      return _fallback.refreshQuota(id);
    }
  }

  @override
  Future<void> removeAccount(String id) async {
    if (!_live) return _fallback.removeAccount(id);
    try {
      await _client.removeAccount(id);
    } catch (_) {
      _live = false;
      await _fallback.removeAccount(id);
    }
  }

  @override
  Future<List<ConnectedAccount>> connectedAccounts() async {
    if (!_live) return _fallback.connectedAccounts();
    try {
      final items = await _client.connectedAccounts();
      return items
          .map(
            (item) => ConnectedAccount(
              accountId: item['accountId'] as String? ?? '',
              email: item['email'] as String? ?? '',
              plan: item['plan'] as String?,
              projectId: item['projectId'] as String?,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      _live = false;
      return _fallback.connectedAccounts();
    }
  }

  // --- Local proxy ------------------------------------------------------

  @override
  Future<ProxyStatus> proxyStatus() async {
    try {
      return _parseProxyStatus(await _client.proxyStatus());
    } catch (_) {
      _live = false;
      return _fallback.proxyStatus();
    }
  }

  @override
  Future<ProxyStatus> startProxy({int? port}) async {
    final payload = await _client.startProxy(port: port);
    return _parseProxyStatus(payload);
  }

  @override
  Future<ProxyStatus> stopProxy() async {
    final payload = await _client.stopProxy();
    return _parseProxyStatus(payload);
  }

  @override
  Future<ProxyStatus> rotateProxyKey() async {
    final payload = await _client.rotateProxyKey();
    return _parseProxyStatus(payload);
  }

  @override
  Future<List<TrafficRecord>> traffic({int limit = 100}) async {
    try {
      final items = await _client.traffic(limit: limit);
      _live = true;
      return items.map(_parseTraffic).toList(growable: false);
    } catch (_) {
      _live = false;
      return _fallback.traffic(limit: limit);
    }
  }

  @override
  Future<List<Workspace>> workspaces() async {
    try {
      final items = await _client.workspaces();
      _live = true;
      return items.map(_parseWorkspace).toList(growable: false);
    } catch (_) {
      _live = false;
      return _fallback.workspaces();
    }
  }

  /// Reads one workspace out of the payload of `workspaces.list`.
  static Workspace _parseWorkspace(Map<String, dynamic> item) {
    final plan = item['plan'] as String? ?? '';
    final state = item['state'] as String? ?? 'idle';
    return Workspace(
      id: item['id'] as String? ?? '',
      name: item['name'] as String? ?? '',
      accountName: item['accountName'] as String? ?? '',
      plan: plan.isEmpty ? '—' : plan,
      projectFolder: item['projectFolder'] as String? ?? '',
      profileFolder: item['profileFolder'] as String? ?? '',
      lastActive: formatEpochMillis((item['lastActiveAt'] as num?)?.toInt() ?? 0),
      state: switch (state) {
        'running' => WorkspaceState.running,
        'stopped' => WorkspaceState.stopped,
        _ => WorkspaceState.idle,
      },
      unbound: item['unbound'] as bool? ?? false,
    );
  }

  /// Reads the state of the local proxy out of the payload.
  static ProxyStatus _parseProxyStatus(Map<String, dynamic> payload) {
    return ProxyStatus(
      running: payload['running'] as bool? ?? false,
      port: (payload['port'] as num?)?.toInt() ?? 8045,
      baseUrl: payload['baseUrl'] as String? ?? 'http://127.0.0.1:8045',
      apiKey: payload['apiKey'] as String?,
      selectedAccountId: payload['selectedAccountId'] as String?,
      models: (payload['models'] as num?)?.toInt() ?? 0,
    );
  }

  /// Reads one traffic entry out of the payload.
  static TrafficRecord _parseTraffic(Map<String, dynamic> item) {
    return TrafficRecord(
      id: (item['id'] as num?)?.toInt() ?? 0,
      at: (item['at'] as num?)?.toInt() ?? 0,
      protocol: item['protocol'] as String? ?? '',
      model: item['model'] as String? ?? '',
      accountId: item['accountId'] as String?,
      status: (item['status'] as num?)?.toInt() ?? 0,
      durationMs: (item['durationMs'] as num?)?.toInt() ?? 0,
      requestBytes: (item['requestBytes'] as num?)?.toInt() ?? 0,
      responseBytes: (item['responseBytes'] as num?)?.toInt() ?? 0,
      error: item['error'] as String?,
    );
  }

  /// Reads the accounts out of the payload of `accounts.list`.
  static List<Account> _parseAccounts(Map<String, dynamic> payload) {
    final items = payload['accounts'];
    if (items is! List) return const [];

    return items.whereType<Map<String, dynamic>>().map((item) {
      final quotas = _parseQuotas(item['quotas']);
      final weekly = _parseWeeklyQuotas(item['weeklyQuotas']);

      return Account(
        id: item['id'] as String? ?? '',
        name: item['name'] as String? ?? '',
        handle: item['handle'] as String? ?? '',
        provider: item['provider'] as String? ?? '',
        plan: item['plan'] as String? ?? '',
        status: _parseStatus(item['status'] as String?),
        credits: (item['credits'] as num?)?.toInt() ?? 0,
        inUse: item['inUse'] as bool? ?? false,
        recommended: item['recommended'] as bool? ?? false,
        demo: item['demo'] as bool? ?? false,
        quotas: quotas,
        weeklyQuotas: weekly,
      );
    }).toList(growable: false);
  }

  static List<ModelQuota> _parseQuotas(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map((item) {
      return ModelQuota(
        name: item['name'] as String? ?? '',
        family: _parseFamily(item['family'] as String?),
        remaining: (item['remaining'] as num?)?.toDouble() ?? 0,
        resetLabel: item['resetLabel'] as String? ?? '—',
      );
    }).toList(growable: false);
  }

  static List<WeeklyQuota> _parseWeeklyQuotas(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map((item) {
      return WeeklyQuota(
        groupId: item['groupId'] as String? ?? '',
        remaining: (item['remaining'] as num?)?.toDouble() ?? 0,
        resetLabel: item['resetLabel'] as String? ?? '—',
      );
    }).toList(growable: false);
  }

  static ModelFamily _parseFamily(String? raw) => switch (raw) {
        'claude' => ModelFamily.claude,
        'openai' => ModelFamily.openai,
        _ => ModelFamily.gemini,
      };

  static AccountStatus _parseStatus(String? raw) => switch (raw) {
        'idle' => AccountStatus.idle,
        'rateLimited' => AccountStatus.rateLimited,
        'error' => AccountStatus.error,
        _ => AccountStatus.active,
      };
}
