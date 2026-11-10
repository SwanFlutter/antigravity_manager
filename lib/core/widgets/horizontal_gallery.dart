import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';
import 'app_button.dart';

/// Horizontal gallery for the oversized account cards.
///
/// The row never wraps. It scrolls sideways with a visible thumb, arrows that
/// step one card at a time, and a reserved gutter on the right so the next
/// card peeks into view and signals there is more to the right.
class HorizontalGallery extends StatefulWidget {
  const HorizontalGallery({
    super.key,
    required this.children,
    required this.itemWidth,
    this.gap = 20,
    this.height,
    this.controller,
    this.leading,
    this.trailing,
  });

  final List<Widget> children;
  final double itemWidth;
  final double gap;
  final double? height;
  final ScrollController? controller;

  /// Widget pinned above the scroller, on the leading side.
  final Widget? leading;

  /// Widget pinned above the scroller, on the trailing side.
  final Widget? trailing;

  @override
  State<HorizontalGallery> createState() => _HorizontalGalleryState();
}

class _HorizontalGalleryState extends State<HorizontalGallery> {
  late final ScrollController _controller =
      widget.controller ?? ScrollController();
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  double get _maxExtent =>
      _controller.hasClients ? _controller.position.maxScrollExtent : 0;

  double get _offset =>
      _controller.hasClients ? _controller.offset : 0;

  void _step(double direction) {
    if (!_controller.hasClients) return;
    final target = (_offset + direction * (widget.itemWidth + widget.gap))
        .clamp(0.0, _maxExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!HardwareKeyboard.instance.isShiftPressed) return;
    if (!_controller.hasClients) return;
    final delta = event.scrollDelta.dy != 0 ? event.scrollDelta.dy : event.scrollDelta.dx;
    final target = (_offset + delta).clamp(0.0, _maxExtent);
    _controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canScrollBack = _offset > 1;
    final canScrollForward = _offset < _maxExtent - 1;

    final scroller = Listener(
      onPointerSignal: _onPointerSignal,
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.only(right: 56),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.children.length; i++) ...[
                SizedBox(width: widget.itemWidth, child: widget.children[i]),
                if (i != widget.children.length - 1)
                  SizedBox(width: widget.gap),
              ],
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.leading != null || widget.trailing != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                if (widget.leading != null) widget.leading!,
                const Spacer(),
                if (widget.trailing != null) widget.trailing!,
                const SizedBox(width: 8),
                AppIconButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Previous',
                  onPressed: canScrollBack ? () => _step(-1) : null,
                ),
                const SizedBox(width: 6),
                AppIconButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Next',
                  onPressed: canScrollForward ? () => _step(1) : null,
                ),
              ],
            ),
          ),
        Stack(
          children: [
            SizedBox(height: widget.height, child: scroller),
            Positioned(
              top: 0,
              bottom: 16,
              right: 0,
              width: 54,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        palette.canvas,
                        palette.canvas.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
