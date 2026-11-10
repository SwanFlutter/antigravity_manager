import 'package:flutter/material.dart';

/// Theme-aware colour set for the glass surfaces.
///
/// Everything the UI paints comes from here so a single switch between
/// [AppPalette.dark] and [AppPalette.light] re-skins the entire app.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.canvasTintA,
    required this.canvasTintB,
    required this.surface,
    required this.glass,
    required this.glassStrong,
    required this.glassBorder,
    required this.glassBorderStrong,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentStrong,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.overlayScrim,
  });

  /// Page background.
  final Color canvas;

  /// Ambient gradient blob — top left.
  final Color canvasTintA;

  /// Ambient gradient blob — bottom right.
  final Color canvasTintB;

  /// Opaque-ish base for structural surfaces (sidebar, table rows).
  final Color surface;

  /// Translucent fill used by glass panels.
  final Color glass;

  /// Slightly denser translucent fill for nested surfaces.
  final Color glassStrong;

  /// Hairline border of a glass panel.
  final Color glassBorder;

  /// Luminous top-left edge of a glass panel.
  final Color glassBorderStrong;

  /// Divider / separator line.
  final Color divider;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Primary action colour.
  final Color accent;

  /// Hover / pressed variant of [accent].
  final Color accentStrong;

  /// Low emphasis accent background.
  final Color accentSoft;

  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;

  /// Scrim behind modal surfaces.
  final Color overlayScrim;

  static const AppPalette dark = AppPalette(
    canvas: Color(0xFF05080F),
    canvasTintA: Color(0xFF1D4ED8),
    canvasTintB: Color(0xFF0E7490),
    surface: Color(0xFF0A1020),
    glass: Color(0x0FFFFFFF),
    glassStrong: Color(0x14FFFFFF),
    glassBorder: Color(0x1FFFFFFF),
    glassBorderStrong: Color(0x3D8FC7FF),
    divider: Color(0x1AFFFFFF),
    textPrimary: Color(0xFFEAF0FA),
    textSecondary: Color(0xFF9AAAC6),
    textMuted: Color(0xFF64748B),
    accent: Color(0xFF3B82F6),
    accentStrong: Color(0xFF60A5FA),
    accentSoft: Color(0x1F3B82F6),
    success: Color(0xFF34D399),
    successSoft: Color(0x1F34D399),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0x1FFBBF24),
    danger: Color(0xFFFB7185),
    dangerSoft: Color(0x1FFB7185),
    info: Color(0xFF22D3EE),
    overlayScrim: Color(0xB3050810),
  );

  static const AppPalette light = AppPalette(
    canvas: Color(0xFFEFF3FA),
    canvasTintA: Color(0xFFBFDBFE),
    canvasTintB: Color(0xFF99F6E4),
    surface: Color(0xFFF7F9FD),
    glass: Color(0xB8FFFFFF),
    glassStrong: Color(0xD9FFFFFF),
    glassBorder: Color(0x14101828),
    glassBorderStrong: Color(0x664F8BE0),
    divider: Color(0x14101828),
    textPrimary: Color(0xFF0D1830),
    textSecondary: Color(0xFF4B5C78),
    textMuted: Color(0xFF7C8CA6),
    accent: Color(0xFF2563EB),
    accentStrong: Color(0xFF1D4ED8),
    accentSoft: Color(0x1A2563EB),
    success: Color(0xFF059669),
    successSoft: Color(0x1A059669),
    warning: Color(0xFFB45309),
    warningSoft: Color(0x1FB45309),
    danger: Color(0xFFE11D48),
    dangerSoft: Color(0x1AE11D48),
    info: Color(0xFF0E7490),
    overlayScrim: Color(0x66101828),
  );

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? canvasTintA,
    Color? canvasTintB,
    Color? surface,
    Color? glass,
    Color? glassStrong,
    Color? glassBorder,
    Color? glassBorderStrong,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentStrong,
    Color? accentSoft,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? overlayScrim,
  }) {
    return AppPalette(
      canvas: canvas ?? this.canvas,
      canvasTintA: canvasTintA ?? this.canvasTintA,
      canvasTintB: canvasTintB ?? this.canvasTintB,
      surface: surface ?? this.surface,
      glass: glass ?? this.glass,
      glassStrong: glassStrong ?? this.glassStrong,
      glassBorder: glassBorder ?? this.glassBorder,
      glassBorderStrong: glassBorderStrong ?? this.glassBorderStrong,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentStrong: accentStrong ?? this.accentStrong,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      info: info ?? this.info,
      overlayScrim: overlayScrim ?? this.overlayScrim,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvasTintA: Color.lerp(canvasTintA, other.canvasTintA, t)!,
      canvasTintB: Color.lerp(canvasTintB, other.canvasTintB, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassStrong: Color.lerp(glassStrong, other.glassStrong, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassBorderStrong:
          Color.lerp(glassBorderStrong, other.glassBorderStrong, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentStrong: Color.lerp(accentStrong, other.accentStrong, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      overlayScrim: Color.lerp(overlayScrim, other.overlayScrim, t)!,
    );
  }
}

/// Convenience accessor: `context.palette.accent`.
extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}
