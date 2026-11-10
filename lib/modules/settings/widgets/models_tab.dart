import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';
import '../../../I18n/messages.dart';
import '../../../app/controller/settings_controller.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toggle.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/status_badge.dart';
import 'settings_group.dart';
import 'settings_grid.dart';
import 'model_list.dart';

class ModelsTab extends StatelessWidget {
  const ModelsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SettingsController>();

    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsGroup(
            icon: Icons.visibility_outlined,
            title: Messages.settingsModelVisibility.tr,
            description: Messages.settingsModelVisibilityDesc.tr,
            trailing: AppBadge(
              label: Messages.settingsVisibleModels.tr.replaceAll(
                '{n}',
                '${controller.visibleModelCount}',
              ),
              tone: BadgeTone.accent,
            ),
            children: [
              ToggleRow(
                title: Messages.settingsProviderGrouping.tr,
                subtitle: Messages.settingsProviderGroupingDesc.tr,
                icon: Icons.account_tree_outlined,
                value: controller.providerGrouping.value,
                onChanged: (value) => controller.providerGrouping.value = value,
              ),
              const LuminousDivider(),
              FullWidth(child: ModelList(controller: controller)),
              FullWidth(
                child: Row(
                  children: [
                    Text(
                      '${Messages.settingsTotal.tr}: ${controller.allModels.length}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.palette.textMuted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${Messages.settingsVisible.tr}: ${controller.visibleModelCount}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.palette.textMuted,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      '${Messages.settingsHidden.tr}: ${controller.hiddenModelCount}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              FullWidth(
                child: Row(
                  children: [
                    AppButton(
                      label: Messages.commonResetDefaults.tr,
                      icon: Icons.settings_backup_restore_rounded,
                      variant: AppButtonVariant.ghost,
                      onPressed: controller.resetModelVisibility,
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: Messages.commonSaveChanges.tr,
                      icon: Icons.save_outlined,
                      variant: AppButtonVariant.primary,
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
