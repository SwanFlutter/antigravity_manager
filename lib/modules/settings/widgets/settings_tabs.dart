import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../../I18n/messages.dart';
import '../../../app/controller/settings_controller.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/glass_panel.dart';

class SettingsTabs extends StatelessWidget {
  const SettingsTabs({super.key, required this.tab});

  final SettingsTab tab;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SettingsController>();
    final palette = context.palette;

    return GlassPanel(
      padding: const EdgeInsets.all(5),
      radius: Radii.md,
      child: Row(
        children: [
          for (final entry in _entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => controller.tab.value = entry.tab,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tab == entry.tab
                        ? palette.accent.withValues(alpha: 0.16)
                        : null,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(
                      color: tab == entry.tab
                          ? palette.accent.withValues(alpha: 0.45)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    entry.label.tr,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: tab == entry.tab
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: tab == entry.tab
                          ? palette.textPrimary
                          : palette.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabEntry {
  const _TabEntry(this.tab, this.label);

  final SettingsTab tab;
  final String label;
}

final List<_TabEntry> _entries = [
  _TabEntry(SettingsTab.general, Messages.settingsTabGeneral),
  _TabEntry(SettingsTab.models, Messages.settingsTabModels),
  _TabEntry(SettingsTab.proxy, Messages.settingsTabProxy),
];
