import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';

class NumberRow extends StatelessWidget {
  const NumberRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final String description;
  final int value;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: palette.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _NumberBox(value: value, unit: unit, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _NumberBox extends StatefulWidget {
  const _NumberBox({
    required this.value,
    required this.unit,
    required this.onChanged,
  });

  final int value;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberBox> createState() => _NumberBoxState();
}

class _NumberBoxState extends State<_NumberBox> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: 150,
      child: TextField(
        controller: _controller,
        onChanged: (text) {
          final parsed = int.tryParse(text);
          if (parsed != null) widget.onChanged(parsed);
        },
        style: TextStyle(
          fontSize: 13.5,
          fontFamily: kMonoFamily,
          color: palette.textPrimary,
        ),
        cursorColor: palette.accent,
        textAlign: TextAlign.end,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              widget.unit,
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
