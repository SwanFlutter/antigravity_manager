import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// A translucent panel with a luminous hairline edge.
///
/// The edge is a one pixel gradient shell wrapped around a translucent body,
/// which is what gives the interface its glass read without flattening
/// contrast. No [BackdropFilter] is used on purpose: the only content behind
/// panels is the smooth [AmbientBackground] gradient, so blurring adds no
/// visible value — but it forces an expensive saveLayer per panel and makes
/// the whole-app theme transition janky (each frame of the `AnimatedTheme`
/// fade re-rasterised every blur pass).
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.md),
    this.radius = Radii.lg,
    this.strong = false,
    this.borderTint,
    this.margin,
    this.gradientBorder = true,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool strong;

  /// Overrides the default luminous edge colour.
  final Color? borderTint;

  final EdgeInsetsGeometry? margin;

  /// Set to false for panels that should read as flat dividers.
  final bool gradientBorder;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shape = BorderRadius.circular(radius);
    final edge = borderTint ??
        (gradientBorder ? palette.glassBorderStrong : palette.glassBorder);

    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: strong ? palette.glassStrong : palette.glass,
        borderRadius: BorderRadius.circular(radius - 1),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: palette.canvas.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (!gradientBorder) {
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: shape,
          border: Border.all(color: edge),
        ),
        child: body,
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [edge, palette.glassBorder],
          stops: const [0, 0.65],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: body,
      ),
    );
  }
}

/// A flat, low emphasis surface used for nested blocks inside a glass panel.
class GlassInset extends StatelessWidget {
  const GlassInset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.sm),
    this.radius = Radii.md,
    this.color,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? palette.glassStrong,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: palette.glassBorder) : null,
      ),
      child: child,
    );
  }
}

/// Paints the ambient blue / teal light behind the whole application.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(palette.canvas, palette.canvasTintA, isDark ? 0.22 : 0.5)!,
            palette.canvas,
            Color.lerp(palette.canvas, palette.canvasTintB, isDark ? 0.16 : 0.42)!,
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -180,
            left: -140,
            child: _Blob(
              color: palette.canvasTintA.withValues(alpha: isDark ? 0.26 : 0.4),
              size: 520,
            ),
          ),
          Positioned(
            bottom: -220,
            right: -160,
            child: _Blob(
              color: palette.canvasTintB.withValues(alpha: isDark ? 0.2 : 0.34),
              size: 560,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Thin luminous rule used to separate sections inside a panel.
class LuminousDivider extends StatelessWidget {
  const LuminousDivider({super.key, this.height = 1, this.indent = 0});

  final double height;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: indent),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.glassBorder,
              palette.accent.withValues(alpha: 0.28),
              palette.glassBorder,
            ],
          ),
        ),
      ),
    );
  }
}
