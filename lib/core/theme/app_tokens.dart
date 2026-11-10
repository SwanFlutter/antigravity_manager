import 'package:flutter/material.dart';

/// Spacing, radius and elevation tokens shared across every screen.
abstract final class Insets {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double xxl = 40;

  /// Horizontal gutter of the content area.
  static const double pageGutter = 28;

  /// Height of the fixed sidebar.
  static const double sidebarWidth = 248;

  /// Width of the oversized account cards on desktop.
  static const double accountCardWidth = 660;
}

abstract final class Radii {
  static const double xs = 8;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;
}

/// Letter spacing for the small uppercase labels that structure the panels.
const double kLabelTracking = 1.1;

/// Monospace stack used for identifiers, model names, ports and durations.
const String kMonoFamily = 'Consolas';

/// Generic UI stack used for body copy. The platform resolves the fallback
/// chain, so Persian, Arabic and Chinese glyphs stay available.
const String kSansFamily = 'Segoe UI';

/// Text style helpers bound to the active [AppPalette].
extension AppTextStyles on BuildContext {
  TextTheme get texts => Theme.of(this).textTheme;
}
