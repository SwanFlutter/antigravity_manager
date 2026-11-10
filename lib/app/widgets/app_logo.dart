import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

/// The application mark.
///
/// Three arcs of different length read as a quota dial, crossed by a single
/// needle — the same idea the account cards express with their meters.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.accent.withValues(alpha: 0.32),
            palette.info.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(
          color: palette.accent.withValues(alpha: 0.45),
        ),
      ),
      child: CustomPaint(
        painter: _LogoPainter(
          accent: palette.accentStrong,
          highlight: palette.info,
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({required this.accent, required this.highlight});

  final Color accent;
  final Color highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.30;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round
      ..color = accent.withValues(alpha: 0.22);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);

    // Three arcs of different length: a quota dial.
    final segments = <(double, double, Color)>[
      (-math.pi * 0.92, math.pi * 0.62, accent),
      (math.pi * 0.78, math.pi * 0.34, highlight),
      (math.pi * 0.30, math.pi * 0.20, accent.withValues(alpha: 0.7)),
    ];

    for (final (start, sweep, color) in segments) {
      arc.color = color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        arc,
      );
    }

    // Needle.
    final needle = Paint()
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round
      ..color = highlight;

    final tip = Offset(
      center.dx + radius * 0.82 * math.cos(-math.pi / 3.2),
      center.dy + radius * 0.82 * math.sin(-math.pi / 3.2),
    );

    canvas.drawLine(center, tip, needle);
    canvas.drawCircle(center, size.width * 0.055, needle);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) {
    return oldDelegate.accent != accent || oldDelegate.highlight != highlight;
  }
}
