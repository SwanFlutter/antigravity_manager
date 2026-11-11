import 'package:get_x_master/get_x_master.dart';

import '../../core/data/mock_data.dart';
import '../../data/accounts_repository.dart';

class AppController extends GetXController {
  AppController({AccountsRepository? repository})
      : repository = repository ?? defaultAccountsRepository();

  /// The source of the proxy state, so the sidebar tells the truth.
  final AccountsRepository repository;

  final RxBool managerRunning = true.obs;
  final RxBool proxyRunning = false.obs;

  /// Whether the Rust host answered, so every screen can load real data.
  final RxBool hostReady = false.obs;

  final RxInt currentIndex = 0.obs;
  final RxBool sidebarCollapsed = false.obs;

  int get runningServiceCount =>
      services.where((service) => service.running).length;

  List<ServiceEntry> get services => [
    ServiceEntry(
      name: 'Antigravity Manager',
      running: managerRunning.value,
      description: 'Desktop shell and account pool',
    ),
    ServiceEntry(
      name: 'Local API Proxy',
      running: proxyRunning.value,
      description: 'OpenAI compatible gateway',
    ),
  ];

  @override
  void onInit() {
    super.onInit();
    refreshProxyStatus();
  }

  /// Reads whether the gateway of the host is listening right now.
  Future<void> refreshProxyStatus() async {
    try {
      proxyRunning.value = (await repository.proxyStatus()).running;
    } catch (_) {
      proxyRunning.value = false;
    }
  }

  void goTo(int index) => currentIndex.value = index;

  void toggleSidebar() => sidebarCollapsed.toggle();

  void toggleManager() => managerRunning.toggle();

  /// Starts or stops the gateway of the host.
  Future<void> toggleProxy() async {
    try {
      final status = proxyRunning.value
          ? await repository.stopProxy()
          : await repository.startProxy();
      proxyRunning.value = status.running;
    } catch (_) {
      await refreshProxyStatus();
    }
  }
}
