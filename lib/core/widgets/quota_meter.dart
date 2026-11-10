import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// The signature quota meter.
///
/// Quota is the core tension of juggling several accounts at once, so the
/// meter is drawn as discrete ticks rather than a continuous bar: each tick is
/// one chunk of the allowance and the colour states the urgency at a glance.
class SegmentedQuotaMeter extends StatelessWidget {
  const SegmentedQuotaMeter({
    super.key,
    required this.remaining,
    this.segments = 24,
    this.height = 8,
    this.color,
    this.trackColor,
  });

  /// Remaining allowance, 0.0 – 1.0.
  final double remaining;
  final int segments;
  final double height;
  final Color? color;
  final Color? trackColor;

  Color _tone(AppPalette palette) {
    if (color != null) return color!;
    if (remaining <= 0.001) return palette.textMuted;
    if (remaining < 0.2) return palette.danger;
    if (remaining < 0.5) return palette.warning;
    return palette.success;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tone = _tone(palette);
    final filled = (remaining.clamp(0.0, 1.0) * segments).ceil();

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 3.0;
        final count = segments;
        final segmentWidth =
            ((constraints.maxWidth - gap * (count - 1)) / count).clamp(2.0, 14.0);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(count, (index) {
            final isFilled = index < filled;
            final isLastFilled = isFilled && index == filled - 1;
            return Padding(
              padding: EdgeInsets.only(right: index == count - 1 ? 0 : gap),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                width: segmentWidth,
                height: height,
                decoration: BoxDecoration(
                  color: isFilled
                      ? (isLastFilled ? tone : tone.withValues(alpha: 0.82))
                      : (trackColor ?? palette.textMuted.withValues(alpha: 0.16)),
                  borderRadius: BorderRadius.circular(height / 2.6),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// A smooth quota bar for compact contexts.
class QuotaBar extends StatelessWidget {
  const QuotaBar({
    super.key,
    required this.remaining,
    this.height = 6,
    this.color,
    this.width,
  });

  final double remaining;
  final double height;
  final Color? color;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tone = color ??
        (remaining <= 0.001
            ? palette.textMuted
            : remaining < 0.2
                ? palette.danger
                : remaining < 0.5
                    ? palette.warning
                    : palette.success);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        width: width,
        child: Stack(
          children: [
            Container(color: palette.textMuted.withValues(alpha: 0.16)),
            FractionallySizedBox(
              widthFactor: remaining.clamp(0.0, 1.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One model row inside an account card: name, meter, percentage and reset.
class QuotaRow extends StatelessWidget {
  const QuotaRow({
    super.key,
    required this.model,
    required this.remaining,
    required this.resetLabel,
    this.segments = 20,
    this.showReset = true,
  });

  final String model;
  final double remaining;
  final String resetLabel;
  final int segments;
  final bool showReset;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final percent = (remaining * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  model,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (showReset) ...[
                Text(
                  resetLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: palette.textMuted,
                    fontFamily: kMonoFamily,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              SizedBox(
                width: 40,
                child: Text(
                  '$percent%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: kMonoFamily,
                    color: remaining <= 0.001
                        ? palette.textMuted
                        : remaining < 0.2
                            ? palette.danger
                            : remaining < 0.5
                                ? palette.warning
                                : palette.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SegmentedQuotaMeter(remaining: remaining, segments: segments),
        ],
      ),
    );
  }
}
