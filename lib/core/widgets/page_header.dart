import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'status_badge.dart';

/// Page title, short description and the contextual actions of the page.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.description,
    this.actions = const [],
    this.icon,
    this.trailing,
    this.dense = false,
  });

  final String title;
  final String description;
  final List<Widget> actions;
  final IconData? icon;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: dense ? 22 : 27,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.15,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          description,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: palette.textSecondary,
          ),
        ),
      ],
    );

    final actionBlock = actions.isEmpty
        ? null
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: actions,
          );

    final trailingBlock = trailing;

    return Padding(
      padding: EdgeInsets.only(bottom: dense ? Insets.md : Insets.xl),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 760;

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      _IconBadge(icon: icon!),
                      const SizedBox(width: 14),
                    ],
                    Expanded(child: titleBlock),
                  ],
                ),
                if (trailingBlock != null) ...[
                  const SizedBox(height: 14),
                  trailingBlock,
                ],
                if (actionBlock != null) ...[
                  const SizedBox(height: 14),
                  actionBlock,
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                _IconBadge(icon: icon!),
                const SizedBox(width: 14),
              ],
              Expanded(child: titleBlock),
              if (trailingBlock != null) ...[
                const SizedBox(width: 20),
                trailingBlock,
              ] else if (actionBlock != null) ...[
                const SizedBox(width: 20),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.65,
                  ),
                  child: actionBlock,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.accent.withValues(alpha: 0.28),
            palette.accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, size: 21, color: palette.accentStrong),
    );
  }
}

/// Summary tile used by the account overview row.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone = BadgeTone.neutral,
    this.footnote,
    this.meter,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final BadgeTone tone;
  final String? footnote;
  final double? meter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (Color color, Color soft) = switch (tone) {
      BadgeTone.neutral => (palette.textPrimary, palette.glassStrong),
      BadgeTone.accent => (palette.accentStrong, palette.accentSoft),
      BadgeTone.success => (palette.success, palette.successSoft),
      BadgeTone.warning => (palette.warning, palette.warningSoft),
      BadgeTone.danger => (palette.danger, palette.dangerSoft),
      BadgeTone.info => (palette.info, palette.info.withValues(alpha: 0.14)),
    };

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [soft.withValues(alpha: 0.55), Colors.transparent],
        ),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Container(
        padding: const EdgeInsets.all(Insets.md),
        decoration: BoxDecoration(
          color: palette.glass,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: palette.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: kLabelTracking,
                      color: palette.textMuted,
                    ),
                  ),
                ),
                if (icon != null)
                  Icon(icon, size: 17, color: color.withValues(alpha: 0.85)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    height: 1,
                    color: color,
                  ),
                ),
                if (meter != null) ...[
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SizedBox(
                      width: 64,
                      child: _MiniMeter(value: meter!, color: color),
                    ),
                  ),
                ],
              ],
            ),
            if (footnote != null) ...[
              const SizedBox(height: 8),
              Text(
                footnote!,
                style: TextStyle(
                  fontSize: 12,
                  color: palette.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniMeter extends StatelessWidget {
  const _MiniMeter({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.pill),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Container(color: palette.textMuted.withValues(alpha: 0.18)),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
