import 'package:get_x_master/get_x_master.dart';

import '../../modules/traffic/traffic_controller.dart';
import '../../modules/workspaces/workspaces_controller.dart';
import '../controller/accounts_controller.dart';
import '../controller/api_proxy_controller.dart';
import '../controller/app_controller.dart';
import '../controller/playground_controller.dart';
import '../controller/settings_controller.dart';
import '../controller/theme_controller.dart';

class AppBinding implements Bindings {
  @override
  void dependencies() {
    Get.put(AppController(), permanent: true);
    Get.put(ThemeController(), permanent: true);
    Get.smartLazyPut(() => AccountsController());
    Get.smartLazyPut(() => WorkspacesController());
    Get.smartLazyPut(() => ApiProxyController());
    Get.smartLazyPut(() => PlaygroundController());
    Get.smartLazyPut(() => TrafficController());
    Get.smartLazyPut(() => SettingsController());
  }
}
