import 'package:get_x_master/get_x_master.dart';

import '../../data/accounts_repository.dart';
import 'app_controller.dart';

enum SettingsTab { general, models, proxy }

class SettingsController extends GetXController {
  SettingsController({AccountsRepository? repository})
    : repository = repository ?? defaultAccountsRepository();

  final AccountsRepository repository;

  final Rx<SettingsTab> tab = SettingsTab.general.obs;

  final RxBool compactDensity = false.obs;
  final RxBool reduceMotion = false.obs;
  final RxBool autoSwitch = true.obs;
  final RxBool minimalMode = false.obs;
  final RxString quotaWindow = 'both'.obs;

  final RxBool launchOnBoot = false.obs;
  final RxBool autoStartProxy = true.obs;

  final RxString bindAddress = 'http://192.0.2.42:8045/v1'.obs;
  final RxBool allowLan = true.obs;
  final RxBool maskKey = true.obs;

  final RxSet<String> hiddenModels = <String>{}.obs;
  final RxBool providerGrouping = true.obs;

  final RxBool telemetry = false.obs;
  final RxBool lowQuotaAlerts = true.obs;
  final RxInt alertThreshold = 20.obs;
  final RxBool creditsAlert = true.obs;
  final RxInt creditsThreshold = 5000.obs;

  final RxList<String> allModels = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadModels();
    // The host may still be starting; reload once it answers.
    ever(Get.find<AppController>().hostReady, (_) => loadModels());
  }

  /// Reads the model catalog from the repository.
  Future<void> loadModels() async {
    try {
      final catalog = await repository.modelCatalog();
      allModels.assignAll([for (final model in catalog) model.id]);
    } catch (_) {
      allModels.clear();
    }
  }

  int get visibleModelCount =>
      allModels.length - hiddenModels.where(allModels.contains).length;

  int get hiddenModelCount => hiddenModels.where(allModels.contains).length;

  void toggleModel(String model) {
    if (hiddenModels.contains(model)) {
      hiddenModels.remove(model);
    } else {
      hiddenModels.add(model);
    }
  }

  void resetModelVisibility() => hiddenModels.clear();
}
