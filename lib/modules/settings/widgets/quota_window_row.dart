import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../../I18n/messages.dart';
import '../../../app/controller/settings_controller.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_button.dart';

class QuotaWindowRow extends StatelessWidget {
  const QuotaWindowRow({super.key, required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Messages.settingsQuotaWindow.tr,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  Messages.settingsQuotaWindowDesc.tr,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: palette.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          AppSegmented<String>(
            value: controller.quotaWindow.value,
            dense: true,
            options: [
              SegmentOption(
                label: Messages.accountsQuotaWindow5h.tr,
                value: '5h',
              ),
              SegmentOption(
                label: Messages.accountsQuotaWindowWeek.tr,
                value: 'week',
              ),
              SegmentOption(
                label: Messages.accountsQuotaWindowBoth.tr,
                value: 'both',
              ),
            ],
            onChanged: (value) => controller.quotaWindow.value = value,
          ),
        ],
      ),
    );
  }
}
