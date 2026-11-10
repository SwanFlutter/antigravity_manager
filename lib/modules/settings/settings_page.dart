import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../I18n/messages.dart';
import '../../app/controller/settings_controller.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/page_header.dart';

import 'widgets/general_tab.dart';
import 'widgets/models_tab.dart';
import 'widgets/proxy_tab.dart';
import 'widgets/settings_tabs.dart';

class SettingsPage extends ReactiveGetView<SettingsController> {
  const SettingsPage({super.key});

  @override
  Widget buildReactive(BuildContext context) {
    final controller = Get.smartFind<SettingsController>();

    // Read once here so the page level observer follows the active tab.
    final tab = controller.tab.value;

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Insets.pageGutter,
        Insets.xl,
        Insets.pageGutter,
        Insets.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            icon: Icons.tune_rounded,
            title: Messages.settingsTitle.tr,
            description: Messages.settingsDesc.tr,
          ),
          SettingsTabs(tab: tab),
          const SizedBox(height: Insets.md),
          switch (tab) {
            SettingsTab.general => const GeneralTab(),
            SettingsTab.models => const ModelsTab(),
            SettingsTab.proxy => const ProxyTab(),
          },
        ],
      ),
    );
  }
}
