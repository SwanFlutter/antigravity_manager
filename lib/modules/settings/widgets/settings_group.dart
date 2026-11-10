import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/glass_panel.dart';
import 'settings_grid.dart';

/// A titled group of settings inside one glass panel.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.description,
    required this.children,
    this.trailing,
    this.icon,
  });

  final String title;
  final String description;
  final List<Widget> children;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: palette.accentSoft,
                    borderRadius: BorderRadius.circular(Radii.xs),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(icon, size: 16, color: palette.accentStrong),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 16), trailing!],
            ],
          ),
          const SizedBox(height: Insets.md),
          const LuminousDivider(),
          const SizedBox(height: Insets.xs),
          SettingsGrid(children: children),
        ],
      ),
    );
  }
}
