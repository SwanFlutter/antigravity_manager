import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'hover_builder.dart';

enum AppButtonVariant { primary, secondary, ghost, danger }

enum AppButtonSize { small, medium, large }

/// The one button used across the app.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.secondary,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final bool expand;
  final String? tooltip;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  double get _height => switch (widget.size) {
        AppButtonSize.small => 32,
        AppButtonSize.medium => 38,
        AppButtonSize.large => 46,
      };

  double get _horizontalPadding => switch (widget.size) {
        AppButtonSize.small => 12,
        AppButtonSize.medium => 16,
        AppButtonSize.large => 22,
      };

  double get _fontSize => switch (widget.size) {
        AppButtonSize.small => 12.5,
        AppButtonSize.medium => 13.5,
        AppButtonSize.large => 15,
      };

  double get _iconSize => switch (widget.size) {
        AppButtonSize.small => 15,
        AppButtonSize.medium => 17,
        AppButtonSize.large => 19,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = widget.onPressed != null && !widget.loading;
    final onAccent = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF06101F)
        : Colors.white;

    return HoverBuilder(
      onTap: enabled ? widget.onPressed : null,
      onTapDown: enabled ? () => setState(() => _pressed = true) : null,
      onTapUp: enabled ? () => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered, focused) {
        final active = hovered && enabled;
        final (Color background, Color foreground, Color border) = switch (
            widget.variant) {
          AppButtonVariant.primary => (
              active ? palette.accentStrong : palette.accent,
              onAccent,
              Colors.transparent,
            ),
          AppButtonVariant.secondary => (
              active ? palette.accentSoft : palette.glassStrong,
              active ? palette.accentStrong : palette.textPrimary,
              active ? palette.accent : palette.glassBorder,
            ),
          AppButtonVariant.ghost => (
              active ? palette.glassStrong : Colors.transparent,
              active ? palette.accentStrong : palette.textSecondary,
              Colors.transparent,
            ),
          AppButtonVariant.danger => (
              active ? palette.dangerSoft : palette.glassStrong,
              palette.danger,
              active ? palette.danger : palette.danger.withValues(alpha: 0.35),
            ),
        };

        final content = AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _pressed ? 1 : 0, 0),
          height: _height,
          padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
          decoration: BoxDecoration(
            color: enabled ? background : background.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(Radii.sm),
            border:
                Border.all(color: enabled ? border : border.withValues(alpha: 0.4)),
            boxShadow: widget.variant == AppButtonVariant.primary && enabled
                ? [
                    BoxShadow(
                      color:
                          palette.accent.withValues(alpha: active ? 0.34 : 0.22),
                      blurRadius: active ? 18 : 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading)
                SizedBox(
                  width: _iconSize - 2,
                  height: _iconSize - 2,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else if (widget.icon != null)
                Icon(widget.icon, size: _iconSize, color: foreground),
              if (widget.icon != null || widget.loading)
                const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        enabled ? foreground : foreground.withValues(alpha: 0.6),
                    fontSize: _fontSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        );

        return Semantics(
          button: true,
          enabled: enabled,
          label: widget.label,
          child: widget.expand
              ? SizedBox(width: double.infinity, child: content)
              : content,
        );
      },
    );
  }
}

/// Square icon-only control used in dense toolbars.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.tone,
    this.size = 36,
    this.iconSize = 18,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? tone;
  final double size;
  final double iconSize;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = tone ?? (selected ? palette.accent : palette.textSecondary);

    final button = HoverBuilder(
      onTap: onPressed,
      cursor:
          onPressed == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (context, hovered, focused) {
        final active = hovered && onPressed != null;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: selected || active
                ? color.withValues(alpha: 0.16)
                : palette.glassStrong,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: selected || active
                  ? color.withValues(alpha: 0.5)
                  : palette.glassBorder,
            ),
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: selected || active ? color : palette.textSecondary,
          ),
        );
      },
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Overflow menu (three dots) used by the workspace and account cards.
class AppOverflowMenu<T> extends StatelessWidget {
  const AppOverflowMenu({
    super.key,
    required this.items,
    this.onSelected,
    this.tooltip,
  });

  final List<AppMenuEntry<T>> items;
  final void Function(T value)? onSelected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      icon: const Icon(Icons.more_horiz_rounded, size: 18),
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => items
          .map(
            (entry) => PopupMenuItem<T>(
              value: entry.value,
              height: 38,
              child: Row(
                children: [
                  if (entry.icon != null) ...[
                    Icon(entry.icon, size: 16, color: context.palette.textSecondary),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    entry.label,
                    style: TextStyle(
                      color: entry.destructive
                          ? context.palette.danger
                          : context.palette.textPrimary,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class AppMenuEntry<T> {
  const AppMenuEntry({
    required this.label,
    required this.value,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final T value;
  final IconData? icon;
  final bool destructive;
}

/// A segmented choice control, used for filters and view modes.
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.dense = false,
  });

  final T value;
  final List<SegmentOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.glassStrong,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: palette.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((option) {
          final selected = option.value == value;
          return Flexible(
            child: HoverBuilder(
              onTap: () => onChanged(option.value),
              builder: (context, hovered, focused) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(
                    horizontal: dense ? 10 : 13,
                    vertical: dense ? 5 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? palette.accent.withValues(alpha: 0.18)
                        : (hovered ? palette.glass : Colors.transparent),
                    borderRadius: BorderRadius.circular(Radii.xs),
                    border: Border.all(
                      color: selected
                          ? palette.accent.withValues(alpha: 0.55)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 12 : 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color:
                          selected ? palette.accentStrong : palette.textSecondary,
                    ),
                  ),
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class SegmentOption<T> {
  const SegmentOption({required this.label, required this.value, this.icon});

  final String label;
  final T value;
  final IconData? icon;
}

/// Small uppercase label that heads a group inside a panel.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: kLabelTracking,
            color: palette.textMuted,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}
