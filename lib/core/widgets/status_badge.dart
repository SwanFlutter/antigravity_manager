import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

enum BadgeTone { neutral, accent, success, warning, danger, info }

/// Compact pill used for providers, plans and statuses.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = BadgeTone.neutral,
    this.icon,
    this.dot = false,
    this.mono = false,
    this.dense = false,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;
  final bool dot;
  final bool mono;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (Color fg, Color bg) = switch (tone) {
      BadgeTone.neutral => (palette.textSecondary, palette.glassStrong),
      BadgeTone.accent => (palette.accentStrong, palette.accentSoft),
      BadgeTone.success => (palette.success, palette.successSoft),
      BadgeTone.warning => (palette.warning, palette.warningSoft),
      BadgeTone.danger => (palette.danger, palette.dangerSoft),
      BadgeTone.info => (palette.info, palette.info.withValues(alpha: 0.14)),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 3 : 4.5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: fg.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 12.5, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              fontFamily: mono ? kMonoFamily : kSansFamily,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small glowing status dot.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.color,
    this.size = 8,
    this.pulse = false,
  });

  final Color color;
  final double size;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: size * 0.9,
            spreadRadius: size * 0.1,
          ),
        ],
      ),
    );

    if (!pulse) return dot;

    return _PulsingDot(dot: dot, color: color, size: size);
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({
    required this.dot,
    required this.color,
    required this.size,
  });

  final Widget dot;
  final Color color;
  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> {
  Timer? _timer;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (!mounted) return;
      setState(() => _expanded = !_expanded);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOut,
          width: widget.size * (_expanded ? 2.4 : 1),
          height: widget.size * (_expanded ? 2.4 : 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: _expanded ? 0 : 0.32),
          ),
        ),
        widget.dot,
      ],
    );
  }
}

/// Round monogram avatar used by the account and workspace cards.
class MonogramAvatar extends StatelessWidget {
  const MonogramAvatar({
    super.key,
    required this.text,
    this.size = 44,
    this.tone = BadgeTone.accent,
  });

  final String text;
  final double size;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (tone) {
      BadgeTone.accent => palette.accent,
      BadgeTone.success => palette.success,
      BadgeTone.warning => palette.warning,
      BadgeTone.danger => palette.danger,
      BadgeTone.info => palette.info,
      BadgeTone.neutral => palette.textMuted,
    };

    final initials = text.trim().isEmpty
        ? '?'
        : text
            .trim()
            .split(RegExp(r'[\s._-]+'))
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.42),
            color.withValues(alpha: 0.14),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
