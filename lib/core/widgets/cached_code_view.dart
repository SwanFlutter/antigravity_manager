import 'package:flutter/material.dart';
import 'package:flutter_code_view/flutter_code_view.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// A [FlutterCodeView] wrapper that memoises the built widget instance.
///
/// `FlutterCodeView` re-parses its whole source inside `State.build()`.
/// During the ~200 ms `AnimatedTheme` transition every Theme-dependent widget
/// rebuilds once per frame, which would re-run the syntax highlighter on every
/// frame. Two details keep that from happening here:
///
/// 1. The built child is cached per `(language, themeType, source)` and
///    returned verbatim afterwards — since the identical widget instance is
///    handed back to the element, Flutter skips updating that whole subtree.
/// 2. The decorative colours snap to the static [AppPalette.light] /
///    [AppPalette.dark] constants instead of the per-frame lerped palette, so
///    the cache key only changes when the mode actually flips.
class CachedCodeView extends StatelessWidget {
  const CachedCodeView({
    super.key,
    required this.source,
    required this.language,
    this.fontSize = 12.5,
    this.showLineNumbers = true,
  });

  final String source;
  final Languages language;
  final double fontSize;
  final bool showLineNumbers;

  static final Map<String, Widget> _cache = <String, Widget>{};

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeType = isDark ? ThemeType.nord : ThemeType.github;
    final palette = isDark ? AppPalette.dark : AppPalette.light;

    final key = '${language.name}|$themeType|$source';
    return _cache[key] ??= RepaintBoundary(
      child: FlutterCodeView(
        source: source,
        language: language,
        themeType: themeType,
        showLineNumbers: showLineNumbers,
        fontSize: fontSize,
        textStyle: TextStyle(fontFamily: kMonoFamily, fontSize: fontSize),
        lineNumberStyle: TextStyle(
          fontFamily: kMonoFamily,
          fontSize: fontSize - 1.5,
          color: palette.textMuted,
        ),
        selectionColor: palette.accent.withValues(alpha: 0.3),
        borderColor: palette.glassStrong,
        borderRadius: BorderRadius.circular(Radii.sm),
        borderRadiusCodeView: BorderRadius.circular(Radii.xs),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        paddingBorder: EdgeInsets.zero,
      ),
    );
  }
}
