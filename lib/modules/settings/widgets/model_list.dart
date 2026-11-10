import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../../I18n/messages.dart';
import '../../../app/controller/settings_controller.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/status_badge.dart';

class ModelList extends StatefulWidget {
  const ModelList({super.key, required this.controller});

  final SettingsController controller;

  @override
  State<ModelList> createState() => _ModelListState();
}

class _ModelListState extends State<ModelList> {
  /// The scrollbar and the list share one controller. Without an explicit
  /// controller the scrollbar falls back to the primary scroll controller,
  /// which has no position attached on desktop.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = widget.controller;

    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(
        color: palette.glassStrong,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.glassBorder),
      ),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: controller.allModels.length,
          itemBuilder: (context, index) {
            final model = controller.allModels[index];
            final visible = !controller.hiddenModels.contains(model);

            return InkWell(
              onTap: () => controller.toggleModel(model),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: visible,
                        onChanged: (_) => controller.toggleModel(model),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      model,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: kMonoFamily,
                        color: visible
                            ? palette.textPrimary
                            : palette.textMuted,
                      ),
                    ),
                    const Spacer(),
                    if (!visible)
                      AppBadge(
                        label: Messages.settingsHidden.tr,
                        tone: BadgeTone.warning,
                        dense: true,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
