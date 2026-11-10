import 'package:get_x_master/get_x_master.dart';

import '../../core/data/mock_data.dart';

class AppController extends GetXController {
  final RxBool managerRunning = true.obs;
  final RxBool proxyRunning = true.obs;

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

  void goTo(int index) => currentIndex.value = index;

  void toggleSidebar() => sidebarCollapsed.toggle();

  void toggleManager() => managerRunning.toggle();

  void toggleProxy() => proxyRunning.toggle();
}
