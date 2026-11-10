import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';
import '../../../I18n/messages.dart';
import '../../../app/controller/settings_controller.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toggle.dart';
import '../../../core/widgets/glass_panel.dart';
import 'settings_group.dart';
import 'settings_grid.dart';
import 'info_row.dart';

class ProxyTab extends StatelessWidget {
  const ProxyTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SettingsController>();

    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsGroup(
            icon: Icons.route_outlined,
            title: Messages.settingsProxy.tr,
            description: Messages.settingsProxyDesc.tr,
            children: [
              InfoRow(
                label: Messages.settingsBindAddress.tr,
                value: controller.bindAddress.value,
              ),
              const LuminousDivider(),
              ToggleRow(
                title: Messages.settingsAllowLan.tr,
                subtitle: Messages.settingsAllowLanDesc.tr,
                icon: Icons.lan_outlined,
                value: controller.allowLan.value,
                onChanged: (value) => controller.allowLan.value = value,
              ),
              const LuminousDivider(),
              ToggleRow(
                title: Messages.settingsMaskKey.tr,
                subtitle: Messages.settingsMaskKeyDesc.tr,
                icon: Icons.key_off_outlined,
                value: controller.maskKey.value,
                onChanged: (value) => controller.maskKey.value = value,
              ),
              FullWidth(
                child: Row(
                  children: [
                    AppButton(
                      label: Messages.commonSaveChanges.tr,
                      icon: Icons.save_outlined,
                      variant: AppButtonVariant.primary,
                      onPressed: () {},
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: Messages.commonResetDefaults.tr,
                      icon: Icons.settings_backup_restore_rounded,
                      variant: AppButtonVariant.ghost,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
