import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// Invitation to act when a list has nothing in it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.glassStrong,
              border: Border.all(color: palette.glassBorder),
            ),
            child: Icon(icon, size: 24, color: palette.textMuted),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: palette.textSecondary,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 20),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Skeleton placeholder shown while content is being fetched.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label, this.lines = 3});

  final String? label;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(fontSize: 13, color: palette.textMuted),
          ),
          const SizedBox(height: 16),
        ],
        for (var i = 0; i < lines; i++) ...[
          _SkeletonBar(widthFactor: i == 0 ? 0.4 : 1 - i * 0.22),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SkeletonBar extends StatefulWidget {
  const _SkeletonBar({required this.widthFactor});

  final double widthFactor;

  @override
  State<_SkeletonBar> createState() => _SkeletonBarState();
}

class _SkeletonBarState extends State<_SkeletonBar> {
  Timer? _timer;
  bool _bright = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() => _bright = !_bright);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widget.widthFactor,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
        height: 14,
        decoration: BoxDecoration(
          color: palette.textMuted.withValues(alpha: _bright ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
      ),
    );
  }
}

/// Failure state with a retry affordance.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.dangerSoft,
              border: Border.all(
                color: palette.danger.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(Icons.error_outline_rounded,
                size: 24, color: palette.danger),
          ),
          const SizedBox(height: 15),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: palette.textSecondary,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: Text(retryLabel),
              style: TextButton.styleFrom(
                foregroundColor: palette.accentStrong,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
