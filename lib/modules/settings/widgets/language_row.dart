import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../../I18n/messages.dart';
import '../../../I18n/translations.dart';
import '../../../app/controller/settings_controller.dart';
import '../../../app/controller/theme_controller.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_field.dart';

class LanguageRow extends StatelessWidget {
  const LanguageRow({super.key, required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.glassStrong,
              borderRadius: BorderRadius.circular(Radii.xs),
              border: Border.all(color: palette.glassBorder),
            ),
            child: Icon(
              Icons.translate_rounded,
              size: 17,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Messages.settingsLanguage.tr,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  Messages.settingsLanguageDesc.tr,
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
          SizedBox(
            width: 190,
            child: GlassDropdown<String>(
              value: _code(theme),
              icon: Icons.language_rounded,
              items: [
                for (final code in AppTranslations.supportedLocales)
                  GlassDropdownItem(
                    value: code,
                    label: AppTranslations.languageNames[code] ?? code,
                  ),
              ],
              onChanged: (value) {
                final parts = value.split('_');
                theme.setLocale(Locale(parts.first, parts.last));
              },
            ),
          ),
        ],
      ),
    );
  }

  String _code(ThemeController theme) {
    final locale = theme.locale.value;
    final code = '${locale.languageCode}_${locale.countryCode}';
    return AppTranslations.supportedLocales.contains(code)
        ? code
        : AppTranslations.supportedLocales.first;
  }
}
