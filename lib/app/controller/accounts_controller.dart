import 'package:get_x_master/get_x_master.dart';

import '../../../core/data/mock_data.dart';
import '../../data/accounts_repository.dart';
import '../../data/cloud_models.dart';
import '../../data/host/host_launcher.dart';
import 'app_controller.dart';

enum QuotaWindow { fiveHours, week, both }

enum AccountViewMode { comfortable, compact }

/// State of the account pool screen.
///
/// The data comes from the [AccountsRepository]. The default repository talks
/// to the Rust host over the private named pipe and falls back to the in
/// process fake while the host is not running.
class AccountsController extends GetXController {
  AccountsController({AccountsRepository? repository})
      : repository = repository ?? defaultAccountsRepository();

  final AccountsRepository repository;

  final RxList<Account> accounts = MockData.accounts.obs;

  /// Id of the account currently serving traffic.
  final RxString activeAccountId = MockData.accounts.first.id.obs;

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

  /// The accounts that are connected with real credentials.
  final RxList<ConnectedAccount> connected = <ConnectedAccount>[].obs;

  int get totalCount => accounts.length;

  int get activeCount =>
      accounts.where((account) => account.status == AccountStatus.active).length;

  int get rateLimitedCount => accounts
      .where((account) => account.status == AccountStatus.rateLimited)
      .length;

  double get globalRemaining {
    if (accounts.isEmpty) return 0;
    final total = accounts.fold<double>(0, (sum, a) => sum + a.globalRemaining);
    return total / accounts.length;
  }

  List<Account> get visibleAccounts {
    final needle = query.value.trim().toLowerCase();
    if (needle.isEmpty) return accounts;
    return accounts
        .where((account) =>
            account.name.toLowerCase().contains(needle) ||
            account.handle.toLowerCase().contains(needle) ||
            account.provider.toLowerCase().contains(needle) ||
            account.plan.toLowerCase().contains(needle))
        .toList();
  }

  Account? get activeAccount {
    for (final account in accounts) {
      if (account.id == activeAccountId.value) return account;
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  @override
  void onInit() {
    super.onInit();
    _startHost();
  }

  /// Starts the Rust host when it is not running yet and reads the pool.
  Future<void> _startHost() async {
    await HostLauncher().ensureRunning();
    await loadAccounts();
  }

  /// Reads the account pool from the repository.
  Future<void> loadAccounts() async {
    final snapshot = await repository.load();
    if (snapshot.accounts.isEmpty) return;

    accounts.assignAll(snapshot.accounts);

    final active = snapshot.accounts.firstWhere(
      (account) => account.inUse,
      orElse: () => snapshot.accounts.first,
    );
    activeAccountId.value = active.id;

    isLive.value = repository.isLive;
    if (repository.isLive) {
      try {
        Get.find<AppController>().hostReady.value = true;
      } catch (_) {
        // The shell controller is not registered in standalone tests.
      }
    }
    await loadConnected();
  }

  /// Reads the accounts that are connected with real credentials.
  Future<void> loadConnected() async {
    try {
      connected.assignAll(await repository.connectedAccounts());
    } catch (_) {
      connected.clear();
    }
  }

  /// Starts the connection of a Google account.
  ///
  /// The host opens the browser, the user approves the access and the host
  /// stores the account.
  Future<void> startConnect() async {
    connecting.value = true;
    connectError.value = null;
    connectEmail.value = null;
    connectStatus.value = 'pending';

    try {
      final session = await repository.startConnect();
      connectSessionId.value = session.sessionId;
      connectUrl.value = session.authorizationUrl;
      _watchConnect(session.sessionId);
    } catch (error) {
      connectStatus.value = 'failed';
      connectError.value = error.toString();
    } finally {
      connecting.value = false;
    }
  }

  /// Waits for the browser to come back.
  Future<void> _watchConnect(String sessionId) async {
    for (var attempt = 0; attempt < 150; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (connectStatus.value != 'pending') return;

      try {
        final state = await repository.connectStatus(sessionId);
        connectStatus.value = state.status;
        connectEmail.value = state.email;
        connectError.value = state.error;

        if (state.isCompleted) {
          await loadAccounts();
          return;
        }
        if (state.isFailed) return;
      } catch (error) {
        connectStatus.value = 'failed';
        connectError.value = error.toString();
        return;
      }
    }

    connectStatus.value = 'expired';
  }

  /// Finishes a connection with a code the user copied by hand.
  Future<void> submitCode(String sessionId, String code) async {
    connectError.value = null;
    try {
      await repository.submitCode(sessionId, code);
      connectStatus.value = 'pending';
      _watchConnect(sessionId);
    } catch (error) {
      connectStatus.value = 'failed';
      connectError.value = error.toString();
    }
  }

  /// Refreshes the quota of one account from the provider.
  Future<void> refreshQuota(Account account) async {
    final updated = await repository.refreshQuota(account.id);
    if (updated == null) return;

    final index = accounts.indexWhere((item) => item.id == updated.id);
    if (index >= 0) accounts[index] = updated;
  }

  /// Removes one account with its credentials.
  Future<void> removeAccount(Account account) async {
    await repository.removeAccount(account.id);
    await loadConnected();
  }

  void useAccount(Account account) {
    activeAccountId.value = account.id;
    repository.setActive(account.id);
  }

  void toggleSelected(String id) {
    final selected = !selectedIds.contains(id);
    if (selected) {
      selectedIds.add(id);
    } else {
      selectedIds.remove(id);
    }
    repository.setSelected(id, selected);
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
