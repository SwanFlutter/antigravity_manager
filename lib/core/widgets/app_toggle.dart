import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// A pill toggle that matches the glass language of the rest of the app.
class GlassSwitch extends StatelessWidget {
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 44,
    this.height = 25,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onChanged != null;

    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: width,
            height: height,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value
                  ? palette.accent
                  : palette.textMuted.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(
                color: value
                    ? palette.accentStrong.withValues(alpha: 0.8)
                    : palette.glassBorder,
              ),
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: palette.accent.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: height - 8,
                height: height - 8,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled switch row used all over the settings surface.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: palette.glassStrong,
                borderRadius: BorderRadius.circular(Radii.xs),
                border: Border.all(color: palette.glassBorder),
              ),
              child: Icon(icon, size: 17, color: palette.textSecondary),
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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
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
          GlassSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
