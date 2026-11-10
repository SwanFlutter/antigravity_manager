import 'dart:convert';

import 'pipe_transport.dart';

/// The version of the application contract this build speaks.
///
/// It must match `CONTRACT_VERSION` of the Rust `antigravity-contract` crate.
const int kContractVersion = 1;

/// The methods of contract version 1.
class HostMethods {
  HostMethods._();

  static const String hostInfo = 'host.info';
  static const String accountsList = 'accounts.list';
  static const String accountsSetActive = 'accounts.setActive';
  static const String accountsSetSelected = 'accounts.setSelected';
  static const String modelsCatalog = 'models.catalog';

  // Cloud accounts.
  static const String accountsStartConnect = 'accounts.startConnect';
  static const String accountsConnectStatus = 'accounts.connectStatus';
  static const String accountsSubmitCode = 'accounts.submitCode';
  static const String accountsRefreshQuota = 'accounts.refreshQuota';
  static const String accountsRemove = 'accounts.remove';
  static const String accountsConnected = 'accounts.connected';

  // Local proxy.
  static const String proxyStatus = 'proxy.status';
  static const String proxyStart = 'proxy.start';
  static const String proxyStop = 'proxy.stop';
  static const String proxyRotateKey = 'proxy.rotateKey';

  // Traffic.
  static const String trafficList = 'traffic.list';

  // Workspaces.
  static const String workspacesList = 'workspaces.list';
}

/// An error reported by the host.
class HostError implements Exception {
  HostError(this.code, this.message);

  final int code;
  final String message;

  /// Whether the host speaks a different contract version.
  bool get isVersionMismatch => code == -32000;

  @override
  String toString() => 'HostError($code): $message';
}

/// A typed client of the application contract.
class HostClient {
  HostClient({HostTransport? transport})
      : _transport = transport ?? PipeTransport();

  final HostTransport _transport;

  /// Sends a request and returns its result.
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    final response = await _transport.call(method, params);

    final error = response['error'];
    if (error is Map<String, dynamic>) {
      throw HostError(
        (error['code'] as num?)?.toInt() ?? -32603,
        error['message'] as String? ?? 'the host reported an error',
      );
    }

    final result = response['result'];
    if (result is Map<String, dynamic>) return result;
    if (result is List) {
      return <String, dynamic>{'items': result};
    }
    return <String, dynamic>{};
  }

  /// Reads the contract version, the app version and the profile path.
  Future<HostInfo> hostInfo() async {
    final result = await call(HostMethods.hostInfo);
    return HostInfo(
      contractVersion: (result['contractVersion'] as num?)?.toInt() ?? 0,
      appVersion: result['appVersion'] as String? ?? '',
      profilePath: result['profilePath'] as String? ?? '',
    );
  }

  /// Reads every account with its quota windows.
  Future<Map<String, dynamic>> accountsList() =>
      call(HostMethods.accountsList);

  /// Marks one account as the account used by the desktop clients.
  Future<void> setActiveAccount(String id) async {
    await call(HostMethods.accountsSetActive, <String, dynamic>{'id': id});
  }

  /// Adds or removes an account from the selection.
  Future<void> setAccountSelected(String id, bool selected) async {
    await call(HostMethods.accountsSetSelected, <String, dynamic>{
      'id': id,
      'selected': selected,
    });
  }

  /// Reads the catalog of models the gateway can route to.
  Future<List<Map<String, dynamic>>> modelsCatalog() async {
    final result = await call(HostMethods.modelsCatalog);
    final items = result['items'];
    if (items is List) {
      return items.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    return const [];
  }

  // --- Cloud accounts ---------------------------------------------------

  /// Starts an OAuth session and returns the URL the browser has to open.
  Future<Map<String, dynamic>> startConnect() => call(HostMethods.accountsStartConnect);

  /// Reads the state of an OAuth session.
  Future<Map<String, dynamic>> connectStatus(String sessionId) =>
      call(HostMethods.accountsConnectStatus, <String, dynamic>{
        'sessionId': sessionId,
      });

  /// Finishes an OAuth session with a code the user copied by hand.
  Future<Map<String, dynamic>> submitCode(String sessionId, String code) =>
      call(HostMethods.accountsSubmitCode, <String, dynamic>{
        'sessionId': sessionId,
        'code': code,
      });

  /// Refreshes the quota of one account from the provider.
  Future<Map<String, dynamic>> refreshQuota(String id) =>
      call(HostMethods.accountsRefreshQuota, <String, dynamic>{'id': id});

  /// Removes one account with its credentials.
  Future<void> removeAccount(String id) async {
    await call(HostMethods.accountsRemove, <String, dynamic>{'id': id});
  }

  /// Lists the accounts that are connected with real credentials.
  Future<List<Map<String, dynamic>>> connectedAccounts() async {
    final result = await call(HostMethods.accountsConnected);
    final items = result['items'];
    if (items is List) {
      return items.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    return const [];
  }

  // --- Local proxy ------------------------------------------------------

  /// Reads the state of the local proxy.
  Future<Map<String, dynamic>> proxyStatus() => call(HostMethods.proxyStatus);

  /// Starts the local proxy on the given port.
  Future<Map<String, dynamic>> startProxy({int? port}) =>
      call(HostMethods.proxyStart, <String, dynamic>{'port': ?port});

  /// Stops the local proxy.
  Future<Map<String, dynamic>> stopProxy() => call(HostMethods.proxyStop);

  /// Replaces the key of the local proxy.
  Future<Map<String, dynamic>> rotateProxyKey() =>
      call(HostMethods.proxyRotateKey);

  // --- Traffic ----------------------------------------------------------

  /// The newest requests that passed through the local proxy.
  Future<List<Map<String, dynamic>>> traffic({int limit = 100}) async {
    final result = await call(HostMethods.trafficList, <String, dynamic>{
      'limit': limit,
    });
    final items = result['items'];
    if (items is List) {
      return items.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    return const [];
  }

  // --- Workspaces -------------------------------------------------------

  /// The workspaces of the imported upstream installation.
  Future<List<Map<String, dynamic>>> workspaces() async {
    final result = await call(HostMethods.workspacesList);
    final items = result['items'];
    if (items is List) {
      return items.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    return const [];
  }

  /// Encodes a payload the same way the host does, for the tests.
  static String encodeFrame(Map<String, dynamic> payload) => jsonEncode(payload);
}

/// Health and contract information of the running host.
class HostInfo {
  const HostInfo({
    required this.contractVersion,
    required this.appVersion,
    required this.profilePath,
  });

  final int contractVersion;
  final String appVersion;
  final String profilePath;

  /// Whether the host speaks the contract this build expects.
  bool get isCompatible => contractVersion == kContractVersion;
}
