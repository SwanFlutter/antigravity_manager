import 'package:flutter/material.dart';

/// Rebuilds its child whenever the pointer enters or leaves the widget.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
    this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  final Widget Function(BuildContext context, bool hovered, bool focused)
      builder;

  final MouseCursor cursor;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (value) => setState(() => _focused = value),
      child: MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: widget.builder(context, _hovered, _focused),
        ),
      ),
    );
  }
}
