import 'package:flutter/material.dart';

/// A responsive grid of fixed size cards.
///
/// The cards never shrink below [minCardWidth]: the grid simply drops to a
/// single column when the window gets too narrow, so the content inside a
/// card stays readable instead of being squeezed.
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.children,
    this.minCardWidth = 430,
    this.maxColumns = 2,
    this.itemHeight = 470,
    this.spacing = 20,
    this.runSpacing = 20,
  });

  final List<Widget> children;
  final double minCardWidth;
  final int maxColumns;
  final double itemHeight;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isInfinite) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: runSpacing),
                SizedBox(height: itemHeight, child: children[i]),
              ],
            ],
          );
        }

        final columns = (constraints.maxWidth / minCardWidth)
            .floor()
            .clamp(1, maxColumns)
            .toInt();

        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(width: width, height: itemHeight, child: child),
          ],
        );
      },
    );
  }
}
