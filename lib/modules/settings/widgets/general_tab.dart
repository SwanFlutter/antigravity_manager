import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../../I18n/messages.dart';
import '../../../app/controller/settings_controller.dart';
import '../../../app/controller/theme_controller.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toggle.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/status_badge.dart';
import 'info_row.dart';
import 'language_row.dart';
import 'number_row.dart';
import 'quota_window_row.dart';
import 'settings_grid.dart';
import 'settings_group.dart';

class GeneralTab extends StatelessWidget {
  const GeneralTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SettingsController>();
    final theme = Get.find<ThemeController>();
    final palette = context.palette;

    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsGroup(
            icon: Icons.palette_outlined,
            title: Messages.settingsAppearance.tr,
            description: Messages.settingsAppearanceDesc.tr,
            children: [
              ToggleRow(
                title: Messages.settingsTheme.tr,
                subtitle: Messages.settingsThemeDesc.tr,
                icon: Icons.brightness_6_outlined,
                value: theme.isDarkMode,
                onChanged: (_) => theme.toggleTheme(),
              ),
              const LuminousDivider(),
              LanguageRow(controller: controller),
              const LuminousDivider(),
              ToggleRow(
                title: Messages.settingsDensityCompact.tr,
                subtitle: Messages.settingsDensityDesc.tr,
                icon: Icons.compress_rounded,
                value: controller.compactDensity.value,
                onChanged: (value) => controller.compactDensity.value = value,
              ),
              const LuminousDivider(),
              ToggleRow(
                title: Messages.settingsReduceMotion.tr,
                subtitle: Messages.settingsReduceMotionDesc.tr,
                icon: Icons.animation_rounded,
                value: controller.reduceMotion.value,
                onChanged: (value) => controller.reduceMotion.value = value,
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          SettingsGroup(
            icon: Icons.swap_horiz_rounded,
            title: Messages.settingsAccountBehaviour.tr,
            description: Messages.settingsAccountBehaviourDesc.tr,
            children: [
              ToggleRow(
                title: Messages.settingsAutoSwitch.tr,
                subtitle: Messages.settingsAutoSwitchDesc.tr,
                icon: Icons.bolt_rounded,
                value: controller.autoSwitch.value,
                onChanged: (value) => controller.autoSwitch.value = value,
              ),
              const LuminousDivider(),
              ToggleRow(
                title: Messages.settingsMinimalMode.tr,
                subtitle: Messages.settingsMinimalModeDesc.tr,
                icon: Icons.crop_free_rounded,
                value: controller.minimalMode.value,
                onChanged: (value) => controller.minimalMode.value = value,
              ),
              const LuminousDivider(),
              QuotaWindowRow(controller: controller),
            ],
          ),
          const SizedBox(height: Insets.md),
          SettingsGroup(
            icon: Icons.rocket_launch_outlined,
            title: Messages.settingsStartup.tr,
            description: Messages.settingsStartupDesc.tr,
            children: [
              ToggleRow(
                title: Messages.settingsLaunchOnBoot.tr,
                subtitle: Messages.settingsLaunchOnBootDesc.tr,
                icon: Icons.power_settings_new_rounded,
                value: controller.launchOnBoot.value,
                onChanged: (value) => controller.launchOnBoot.value = value,
              ),
              const LuminousDivider(),
              ToggleRow(
                title: Messages.settingsAutoStartProxy.tr,
                subtitle: Messages.settingsAutoStartProxyDesc.tr,
                icon: Icons.route_outlined,
                value: controller.autoStartProxy.value,
                onChanged: (value) => controller.autoStartProxy.value = value,
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          SettingsGroup(
            icon: Icons.shield_outlined,
            title: Messages.settingsPrivacy.tr,
            description: Messages.settingsPrivacyDesc.tr,
            children: [
              ToggleRow(
                title: Messages.settingsTelemetry.tr,
                subtitle: Messages.settingsTelemetryDesc.tr,
                icon: Icons.insights_outlined,
                value: controller.telemetry.value,
                onChanged: (value) => controller.telemetry.value = value,
              ),
              const LuminousDivider(),
              ToggleRow(
                title: Messages.settingsClearTraffic.tr,
                subtitle: Messages.settingsClearTrafficDesc.tr,
                icon: Icons.delete_sweep_outlined,
                value: false,
                onChanged: (_) {},
              ),
              const LuminousDivider(),
              FullWidth(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton(
                    label: Messages.settingsClearTrafficAction.tr,
                    icon: Icons.delete_outline_rounded,
                    variant: AppButtonVariant.danger,
                    size: AppButtonSize.small,
                    onPressed: () {},
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          SettingsGroup(
            icon: Icons.notifications_none_rounded,
            title: Messages.settingsNotifications.tr,
            description: Messages.settingsNotificationsDesc.tr,
            children: [
              ToggleRow(
                title: Messages.settingsLowQuota.tr,
                subtitle: Messages.settingsLowQuotaDesc.tr,
                icon: Icons.speed_rounded,
                value: controller.lowQuotaAlerts.value,
                onChanged: (value) => controller.lowQuotaAlerts.value = value,
              ),
              const LuminousDivider(),
              NumberRow(
                label: Messages.settingsThreshold.tr,
                description: Messages.settingsThresholdDesc.tr,
                value: controller.alertThreshold.value,
                unit: Messages.settingsPercent.tr,
                onChanged: (value) => controller.alertThreshold.value = value,
              ),
              const LuminousDivider(),
              ToggleRow(
                title: Messages.settingsCreditsAlert.tr,
                subtitle: Messages.settingsCreditsAlertDesc.tr,
                icon: Icons.toll_outlined,
                value: controller.creditsAlert.value,
                onChanged: (value) => controller.creditsAlert.value = value,
              ),
              const LuminousDivider(),
              NumberRow(
                label: Messages.settingsCreditsThreshold.tr,
                description: Messages.settingsCreditsThresholdDesc.tr,
                value: controller.creditsThreshold.value,
                unit: Messages.settingsCreditsUnit.tr,
                onChanged: (value) => controller.creditsThreshold.value = value,
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          SettingsGroup(
            icon: Icons.info_outline_rounded,
            title: Messages.settingsAbout.tr,
            description: Messages.settingsAboutDesc.tr,
            children: [
              InfoRow(label: Messages.settingsVersion.tr, value: '1.0.0'),
              const LuminousDivider(),
              InfoRow(label: Messages.settingsBuild.tr, value: 'stable'),
              const LuminousDivider(),
              InfoRow(
                label: Messages.settingsStorage.tr,
                value: Messages.settingsStorageDesc.tr,
              ),
              const LuminousDivider(),
              Row(
                children: [
                  Text(
                    Messages.settingsLicences.tr,
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  AppBadge(label: 'MIT', tone: BadgeTone.info),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
