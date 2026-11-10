import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A row of cards that keeps its card size and reflows into a grid when the
/// window gets too narrow.
///
/// The app is desktop first, so the cards are never squeezed: they either sit
/// side by side at their natural width or wrap onto the next line.
class ResponsiveCardRow extends StatelessWidget {
  const ResponsiveCardRow({
    super.key,
    required this.children,
    this.minCardWidth = 250,
    this.spacing = Insets.md,
    this.runSpacing = Insets.md,
  });

  final List<Widget> children;
  final double minCardWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isInfinite || children.isEmpty) {
          return Wrap(
            spacing: spacing,
            runSpacing: runSpacing,
            children: children,
          );
        }

        final slots =
            (constraints.maxWidth / minCardWidth).floor().clamp(1, children.length);

        if (slots >= children.length) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                Expanded(child: children[i]),
              ],
            ],
          );
        }

        final width = (constraints.maxWidth - spacing * (slots - 1)) / slots;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
