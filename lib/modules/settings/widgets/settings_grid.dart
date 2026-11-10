import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/glass_panel.dart';

/// Marks a settings item that spans the full group width instead of taking
/// one cell of the two column grid.
class FullWidth extends StatelessWidget {
  const FullWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Lays out the items of a settings group as a responsive grid.
///
/// Two items share a row on a wide window so the panel stays compact, and
/// every item falls back to its own line when the window gets narrow.
class SettingsGrid extends StatelessWidget {
  const SettingsGrid({super.key, required this.children});

  final List<Widget> children;

  /// The group items without the separators between them.
  List<Widget> get _cells => [
    for (final child in children)
      if (child is! LuminousDivider) child,
  ];

  @override
  Widget build(BuildContext context) {
    final cells = _cells;

    if (cells.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 760;

        // Pack the cells into rows of two. A full width item always starts a
        // new row because it cannot share the line with another item.
        final rows = <List<int>>[];
        var pending = <int>[];
        for (var i = 0; i < cells.length; i++) {
          if (cells[i] is FullWidth) {
            if (pending.isNotEmpty) {
              rows.add(pending);
              pending = <int>[];
            }
            rows.add([i]);
            continue;
          }
          pending.add(i);
          if (pending.length == 2) {
            rows.add(pending);
            pending = <int>[];
          }
        }
        if (pending.isNotEmpty) rows.add(pending);

        // On a narrow window every cell gets its own line.
        final effectiveRows = <List<int>>[
          for (final row in rows)
            if (!twoColumns)
              for (final index in row) [index]
            else
              row,
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < effectiveRows.length; r++) ...[
              if (r > 0) ...[
                const SizedBox(height: Insets.xs),
                const LuminousDivider(),
                const SizedBox(height: Insets.xs),
              ],
              _buildRow(context, effectiveRows[r]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRow(BuildContext context, List<int> row) {
    final cells = _cells;
    if (row.length == 1) return _unwrap(cells[row.first]);

    final palette = context.palette;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _unwrap(cells[row[0]])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.md),
            child: SizedBox(
              width: 1,
              child: ColoredBox(color: palette.glassBorder),
            ),
          ),
          Expanded(child: _unwrap(cells[row[1]])),
        ],
      ),
    );
  }

  Widget _unwrap(Widget child) => child is FullWidth ? child.child : child;
}
