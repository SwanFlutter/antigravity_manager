import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_tokens.dart';

/// Builds the light and dark themes for the app.
///
/// The two themes share one shape language — same radii, same spacing, same
/// component shapes — and only swap the palette.
abstract final class AppTheme {
  static ThemeData light() => _build(AppPalette.light, Brightness.light);

  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.accent,
      onPrimary: isDark ? const Color(0xFF06101F) : Colors.white,
      secondary: palette.info,
      onSecondary: isDark ? const Color(0xFF06101F) : Colors.white,
      error: palette.danger,
      onError: isDark ? const Color(0xFF2A0710) : Colors.white,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      surfaceContainerHighest: palette.glassStrong,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.glassBorder,
      outlineVariant: palette.divider,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.canvas,
      fontFamily: kSansFamily,
      fontFamilyFallback: const [
        'Segoe UI',
        'Tahoma',
        'Microsoft YaHei',
        'Noto Sans',
        'Segoe UI Emoji',
      ],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(
        color: palette.divider,
        thickness: 1,
        space: 1,
      ),
      extensions: <ThemeExtension<dynamic>>[palette],
    );

    final text = base.textTheme.apply(
      bodyColor: palette.textPrimary,
      displayColor: palette.textPrimary,
    );

    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          height: 1.1,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          height: 1.15,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          height: 1.2,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          height: 1.25,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        titleSmall: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        bodyLarge: text.bodyLarge?.copyWith(height: 1.45),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
        bodySmall: text.bodySmall?.copyWith(
          height: 1.4,
          color: palette.textSecondary,
        ),
        labelLarge: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        labelMedium: text.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelSmall: text.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: kLabelTracking,
          color: palette.textMuted,
        ),
      ),
      iconTheme: IconThemeData(color: palette.textSecondary, size: 20),
      dividerColor: palette.divider,
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF16203A) : const Color(0xFF16203A),
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: palette.glassBorder),
        ),
        textStyle: const TextStyle(
          color: Color(0xFFEAF0FA),
          fontSize: 12,
          fontFamily: kSansFamily,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 450),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return palette.accent.withValues(alpha: 0.75);
          }
          if (states.contains(WidgetState.dragged)) {
            return palette.accent.withValues(alpha: 0.85);
          }
          return palette.textMuted.withValues(alpha: 0.5);
        }),
        trackColor: WidgetStatePropertyAll(
          palette.textMuted.withValues(alpha: 0.12),
        ),
        trackVisibility: const WidgetStatePropertyAll(false),
        radius: const Radius.circular(Radii.pill),
        thickness: const WidgetStatePropertyAll(8),
        interactive: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.glassStrong,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: TextStyle(color: palette.textMuted, fontSize: 13.5),
        labelStyle: TextStyle(color: palette.textSecondary, fontSize: 13.5),
        floatingLabelStyle: TextStyle(color: palette.accent, fontSize: 13),
        border: _inputBorder(palette, palette.glassBorder),
        enabledBorder: _inputBorder(palette, palette.glassBorder),
        focusedBorder: _inputBorder(palette, palette.accent, width: 1.4),
        errorBorder: _inputBorder(palette, palette.danger),
        focusedErrorBorder: _inputBorder(palette, palette.danger, width: 1.4),
        errorStyle: TextStyle(color: palette.danger, fontSize: 12),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? const Color(0xFF111A2E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: palette.glassBorder),
        ),
        textStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 13.5,
          fontFamily: kSansFamily,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: palette.glassStrong,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: _inputBorder(palette, palette.glassBorder),
          enabledBorder: _inputBorder(palette, palette.glassBorder),
          focusedBorder: _inputBorder(palette, palette.accent, width: 1.4),
        ),
        textStyle: TextStyle(color: palette.textPrimary, fontSize: 13.5),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return palette.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.accent;
          }
          return palette.textMuted.withValues(alpha: 0.3);
        }),
        trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.accent;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: palette.textMuted.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.textMuted.withValues(alpha: 0.18),
        circularTrackColor: palette.textMuted.withValues(alpha: 0.18),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF141E33) : const Color(0xFF101B30),
        contentTextStyle: const TextStyle(
          color: Color(0xFFEAF0FA),
          fontSize: 13.5,
          fontFamily: kSansFamily,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF101A2E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: palette.glassBorder),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(palette.glassStrong),
          foregroundColor: WidgetStatePropertyAll(palette.textPrimary),
          side: WidgetStatePropertyAll(
            BorderSide(color: palette.glassBorder),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
          ),
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(
    AppPalette palette,
    Color color, {
    double width = 1,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.sm),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
