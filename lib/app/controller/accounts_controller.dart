import 'dart:async';

import 'package:get_x_master/get_x_master.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/mock_data.dart';
import '../../data/accounts_repository.dart';
import '../../data/cloud_models.dart';
import '../../data/host/host_launcher.dart';
import 'app_controller.dart';

enum QuotaWindow { fiveHours, week, both }

enum AccountViewMode { comfortable, compact }

class AccountsController extends GetXController {
  AccountsController({AccountsRepository? repository})
    : repository = repository ?? defaultAccountsRepository();

  final AccountsRepository repository;
  Timer? _connectTimer;
  int _connectGeneration = 0;
  bool _liveQuotaFetched = false;

  final RxList<Account> accounts = <Account>[].obs;
  final RxString activeAccountId = ''.obs;
  final RxBool loading = false.obs;
  final RxBool refreshing = false.obs;
  final RxnString loadError = RxnString();
  final RxSet<String> refreshingIds = <String>{}.obs;
  final RxMap<String, String> quotaErrors = <String, String>{}.obs;

  final RxSet<String> selectedIds = <String>{}.obs;
  final RxBool autoSwitch = true.obs;
  final RxBool minimalMode = false.obs;
  final Rx<QuotaWindow> quotaWindow = QuotaWindow.both.obs;
  final Rx<AccountViewMode> viewMode = AccountViewMode.comfortable.obs;
  final RxString query = ''.obs;

  /// Whether the account pool is served by the running Rust host.
  final RxBool isLive = false.obs;

  /// Whether a connection is running right now.
  final RxBool connecting = false.obs;

  /// The authorization URL the browser has to open.
  final RxnString connectUrl = RxnString();

  /// The id of the running connection.
  final RxString connectSessionId = ''.obs;

  /// The state of the running connection: `pending`, `completed`, `failed`.
  final RxString connectStatus = ''.obs;

  /// The address of the account that was connected.
  final RxnString connectEmail = RxnString();

  /// The reason the last connection failed.
  final RxnString connectError = RxnString();

  /// Whether the authorization URL reached the browser of the system.
  final RxBool browserOpened = false.obs;

  /// The accounts that are connected with real credentials.
  final RxList<ConnectedAccount> connected = <ConnectedAccount>[].obs;

  int get totalCount => accounts.length;

  int get activeCount => accounts
      .where((account) => account.status == AccountStatus.active)
      .length;

  int get rateLimitedCount => accounts
      .where((account) => account.status == AccountStatus.rateLimited)
      .length;

  double? get globalRemaining {
    final measured = accounts.where((a) => a.quotas.isNotEmpty).toList();
    if (measured.isEmpty) return null;
    final total = measured.fold<double>(0, (sum, a) => sum + a.globalRemaining);
    return total / measured.length;
  }

  List<Account> get visibleAccounts {
    final needle = query.value.trim().toLowerCase();
    if (needle.isEmpty) return accounts;
    return accounts
        .where(
          (account) =>
              account.name.toLowerCase().contains(needle) ||
              account.handle.toLowerCase().contains(needle) ||
              account.provider.toLowerCase().contains(needle) ||
              account.plan.toLowerCase().contains(needle),
        )
        .toList();
  }

  Account? get activeAccount {
    for (final account in accounts) {
      if (account.id == activeAccountId.value) return account;
    }
    return null;
  }

  @override
  void onInit() {
    super.onInit();
    _startHost();
  }

  /// Starts the Rust host when it is not running yet and reads the pool.
  Future<void> _startHost() async {
    if (repository is HostAccountsRepository) {
      await HostLauncher().ensureRunning();
    }
    await loadAccounts();
    await _fetchLiveQuotas();
  }

  /// Asks the provider for the quota of every account once per session.
  ///
  /// The host seeds the pool with the snapshot of the upstream installation,
  /// which carries no fetch time. The cards must show what the provider says
  /// right now, so the pool is refreshed behind the snapshot as soon as it is
  /// on screen.
  Future<void> _fetchLiveQuotas() async {
    if (_liveQuotaFetched || !isLive.value) return;
    _liveQuotaFetched = true;
    for (final account in accounts.where((a) => !a.demo).toList()) {
      if (loadError.value != null) return;
      await refreshQuota(account);
    }
  }

  Future<void> loadAccounts() async {
    if (loading.value) return;
    loading.value = true;
    loadError.value = null;
    try {
      final snapshot = await repository.load();
      accounts.assignAll(snapshot.accounts);
      activeAccountId.value =
          snapshot.accounts
              .where((account) => account.inUse)
              .map((account) => account.id)
              .firstOrNull ??
          '';
      selectedIds.retainAll(snapshot.accounts.map((account) => account.id));
      isLive.value = repository.isLive;
      await loadConnected();
      _notifyDataChanged();
    } catch (error) {
      isLive.value = false;
      loadError.value = error.toString();
    } finally {
      loading.value = false;
    }
  }

  void _notifyDataChanged() {
    if (repository.isLive && Get.isRegistered<AppController>()) {
      final ready = Get.find<AppController>().hostReady;
      if (ready.value) {
        ready.refresh();
      } else {
        ready.value = true;
      }
    }
  }

  /// Reads the accounts that are connected with real credentials.
  Future<void> loadConnected() async {
    try {
      connected.assignAll(await repository.connectedAccounts());
    } catch (error) {
      connected.clear();
      loadError.value = error.toString();
    }
  }

  /// Starts the connection of a Google account.
  ///
  /// The host opens the browser, the user approves the access and the host
  /// stores the account.
  Future<void> startConnect() async {
    if (connecting.value) return;
    _connectTimer?.cancel();
    final generation = ++_connectGeneration;
    connecting.value = true;
    connectSessionId.value = '';
    connectUrl.value = null;
    browserOpened.value = false;
    connectError.value = null;
    connectEmail.value = null;
    connectStatus.value = 'pending';

    try {
      final session = await repository.startConnect();
      if (generation != _connectGeneration) return;
      connectSessionId.value = session.sessionId;
      connectUrl.value = session.authorizationUrl;
      await openConnectUrl();
      _watchConnect(session.sessionId, generation, 0);
    } catch (error) {
      if (generation != _connectGeneration) return;
      connectStatus.value = 'failed';
      connectError.value = error.toString();
    } finally {
      if (generation == _connectGeneration) connecting.value = false;
    }
  }

  /// Opens the authorization URL in the browser of the system.
  ///
  /// The address stays on screen either way, so a browser that refuses the
  /// launch never blocks the hand written code path.
  Future<void> openConnectUrl() async {
    final url = connectUrl.value;
    if (url == null || url.isEmpty) return;
    try {
      browserOpened.value = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      browserOpened.value = false;
    }
  }

  void _watchConnect(String sessionId, int generation, int attempt) {
    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(seconds: 2), () async {
      if (generation != _connectGeneration) return;
      try {
        final state = await repository.connectStatus(sessionId);
        if (generation != _connectGeneration) return;
        connectStatus.value = state.status;
        connectEmail.value = state.email;
        connectError.value = state.error;
        if (state.isCompleted) {
          await loadAccounts();
          return;
        }
        if (state.isFailed) return;
        if (attempt >= 149) {
          connectStatus.value = 'expired';
          return;
        }
        _watchConnect(sessionId, generation, attempt + 1);
      } catch (error) {
        if (generation != _connectGeneration) return;
        connectStatus.value = 'failed';
        connectError.value = error.toString();
      }
    });
  }

  /// Finishes a connection with a code the user copied by hand.
  Future<void> submitCode(String sessionId, String code) async {
    if (code.trim().isEmpty ||
        sessionId != connectSessionId.value ||
        connecting.value ||
        connectStatus.value != 'pending') {
      return;
    }
    final generation = _connectGeneration;
    connecting.value = true;
    connectError.value = null;
    try {
      await repository.submitCode(sessionId, code.trim());
      if (generation != _connectGeneration) return;
      _watchConnect(sessionId, generation, 0);
    } catch (error) {
      if (generation != _connectGeneration) return;
      connectError.value = error.toString();
    } finally {
      if (generation == _connectGeneration) connecting.value = false;
    }
  }

  @override
  void onClose() {
    _connectGeneration++;
    _connectTimer?.cancel();
    super.onClose();
  }

  Future<void> refreshQuota(Account account) async {
    if (refreshingIds.contains(account.id)) return;
    refreshingIds.add(account.id);
    quotaErrors.remove(account.id);
    try {
      final updated = await repository.refreshQuota(account.id);
      if (updated == null) {
        throw StateError('No account returned by quota refresh');
      }
      final index = accounts.indexWhere((item) => item.id == updated.id);
      if (index >= 0) accounts[index] = updated;
      _notifyDataChanged();
    } catch (error) {
      quotaErrors[account.id] = error.toString();
    } finally {
      refreshingIds.remove(account.id);
    }
  }

  Future<void> refreshAllQuotas() async {
    if (refreshing.value || loading.value) return;
    refreshing.value = true;
    try {
      await loadAccounts();
      if (loadError.value != null) return;
      for (final account in accounts.where((a) => !a.demo).toList()) {
        await refreshQuota(account);
      }
    } finally {
      refreshing.value = false;
    }
  }

  /// Removes one account with its credentials.
  Future<void> removeAccount(Account account) async {
    await repository.removeAccount(account.id);
    await loadConnected();
  }

  Future<void> useAccount(Account account) async {
    try {
      await repository.setActive(account.id);
      await loadAccounts();
    } catch (error) {
      loadError.value = error.toString();
    }
  }

  Future<void> toggleSelected(String id) async {
    final selected = !selectedIds.contains(id);
    try {
      await repository.setSelected(id, selected);
      if (selected) {
        selectedIds.add(id);
      } else {
        selectedIds.remove(id);
      }
    } catch (error) {
      loadError.value = error.toString();
    }
  }

  void selectAll() {
    if (selectedIds.length == visibleAccounts.length) {
      selectedIds.clear();
      return;
    }
    selectedIds
      ..clear()
      ..addAll(visibleAccounts.map((account) => account.id));
  }

  void clearSelection() => selectedIds.clear();
}
