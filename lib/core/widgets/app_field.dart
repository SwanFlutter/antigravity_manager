import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// Single line text field with an optional label, icon and trailing action.
class GlassTextField extends StatefulWidget {
  const GlassTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.icon,
    this.suffix,
    this.obscure = false,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.readOnly = false,
    this.monospace = false,
    this.autofocus = false,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final IconData? icon;
  final Widget? suffix;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool readOnly;
  final bool monospace;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? minLines;

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return TextField(
      controller: widget.controller,
      obscureText: widget.obscure && _hidden,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: TextStyle(
        fontSize: 13.5,
        color: palette.textPrimary,
        fontFamily:
            widget.monospace ? kMonoFamily : kSansFamily,
        height: 1.4,
      ),
      cursorColor: palette.accent,
      cursorWidth: 1.6,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.icon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(widget.icon, size: 17, color: palette.textMuted),
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0),
        // An obscured field keeps its visibility toggle unless the caller
        // passes a suffix of its own (the API key row brings its own toggle).
        suffixIcon: widget.suffix ??
            (widget.obscure
                ? IconButton(
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 17,
                      color: palette.textMuted,
                    ),
                    tooltip: _hidden ? 'Show' : 'Hide',
                  )
                : null),
      ),
    );
  }
}

/// Rounded search input with a leading magnifier and optional trailing clear.
class GlassSearchField extends StatelessWidget {
  const GlassSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    this.width,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final field = SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: TextStyle(fontSize: 13.5, color: palette.textPrimary),
        cursorColor: palette.accent,
        decoration: InputDecoration(
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child:
                Icon(Icons.search_rounded, size: 18, color: palette.textMuted),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0),
          suffixIcon: trailing == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: trailing,
                ),
        ),
      ),
    );

    if (width == null) return field;
    return SizedBox(width: width, child: field);
  }
}

/// Dropdown that follows the glass input styling.
class GlassDropdown<T> extends StatelessWidget {
  const GlassDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.icon,
    this.expand = true,
    this.width,
    this.itemBuilder,
  });

  final T value;
  final List<GlassDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final String? hint;
  final IconData? icon;
  final bool expand;
  final double? width;
  final Widget Function(BuildContext context, GlassDropdownItem<T> item)?
      itemBuilder;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selected = items.firstWhere(
      (item) => item.value == value,
      orElse: () => items.isEmpty
          ? GlassDropdownItem<T>(value: value, label: '')
          : items.first,
    );

    return Container(
      width: expand ? null : (width ?? 240),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.glassStrong,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: palette.glassBorder),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: palette.textMuted),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                dropdownColor:
                    Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF111A2E)
                        : Colors.white,
                borderRadius: BorderRadius.circular(Radii.md),
                icon: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: palette.textMuted,
                ),
                style: TextStyle(
                  fontSize: 13.5,
                  color: palette.textPrimary,
                  fontFamily: kSansFamily,
                ),
                items: items.map((item) {
                  return DropdownMenuItem<T>(
                    value: item.value,
                    child: itemBuilder?.call(context, item) ??
                        Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: palette.textPrimary,
                            fontFamily:
                                item.mono ? kMonoFamily : kSansFamily,
                          ),
                        ),
                  );
                }).toList(),
                onChanged: (next) {
                  if (next != null) onChanged(next);
                },
              ),
            ),
          ),
          if (selected.description != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.info_outline_rounded,
                size: 14, color: palette.textMuted),
          ],
        ],
      ),
    );
  }
}

class GlassDropdownItem<T> {
  const GlassDropdownItem({
    required this.value,
    required this.label,
    this.description,
    this.mono = false,
    this.icon,
  });

  final T value;
  final String label;
  final String? description;
  final bool mono;
  final IconData? icon;
}

/// Numeric field rendered with a trailing unit.
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.unit,
    this.onChanged,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String unit;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return GlassTextField(
      controller: controller,
      label: label,
      monospace: true,
      onChanged: onChanged,
      suffix: suffix ??
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              unit,
              style: TextStyle(
                fontSize: 12.5,
                color: context.palette.textMuted,
                fontFamily: kMonoFamily,
              ),
            ),
          ),
    );
  }
}
