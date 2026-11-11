import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../I18n/messages.dart';
import '../../app/controller/playground_controller.dart';
import '../../core/data/mock_data.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_field.dart';
import '../../core/widgets/app_toggle.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/status_badge.dart';

class PlaygroundPage extends ReactiveGetView<PlaygroundController> {
  const PlaygroundPage({super.key});

  @override
  Widget buildReactive(BuildContext context) {
    final controller = Get.find<PlaygroundController>();
    final palette = context.palette;

    // Read once here so the page level observer follows the active tab.
    final tab = controller.tab.value;

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Insets.pageGutter,
        Insets.xl,
        Insets.pageGutter,
        Insets.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            icon: Icons.science_outlined,
            title: Messages.playgroundTitle.tr,
            description: Messages.playgroundDesc.tr,
            trailing: Obx(
              () => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassSwitch(
                    value: controller.stream.value,
                    width: 40,
                    height: 23,
                    onChanged: (value) => controller.stream.value = value,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    Messages.playgroundStream.tr,
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Obx(() {
                    final gateway = controller.gateway.value;
                    return AppBadge(
                      label: gateway.running
                          ? '${Messages.playgroundGatewayOnline.tr} (${gateway.port})'
                          : Messages.proxyGatewayStopped.tr,
                      tone: gateway.running
                          ? BadgeTone.success
                          : BadgeTone.danger,
                      dot: true,
                    );
                  }),
                ],
              ),
            ),
          ),
          Obx(() {
            final error = controller.sourceError.value;
            if (error == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: Insets.md),
              child: _ErrorBanner(text: error),
            );
          }),
          _TabBar(tab: tab),
          const SizedBox(height: Insets.md),
          if (tab == PlaygroundTab.compare)
            _CompareSection(controller: controller)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 1080;
                final editor = _EditorColumn(controller: controller);
                final output = _OutputColumn(controller: controller);

                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      editor,
                      const SizedBox(height: Insets.md),
                      output,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: editor),
                    const SizedBox(width: Insets.md),
                    Expanded(flex: 5, child: output),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tab});

  final PlaygroundTab tab;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PlaygroundController>();

    return GlassPanel(
      padding: const EdgeInsets.all(5),
      radius: Radii.md,
      child: Row(
        children: [
          for (final entry in _tabEntries)
            Expanded(
              child: _TabTile(
                label: entry.label,
                icon: entry.icon,
                selected: tab == entry.tab,
                onTap: () => controller.tab.value = entry.tab,
              ),
            ),
        ],
      ),
    );
  }
}

class _TabEntry {
  const _TabEntry(this.tab, this.label, this.icon);

  final PlaygroundTab tab;
  final String label;
  final IconData icon;
}

final List<_TabEntry> _tabEntries = [
  _TabEntry(
    PlaygroundTab.single,
    Messages.playgroundTabSingle,
    Icons.play_circle_outline_rounded,
  ),
  _TabEntry(
    PlaygroundTab.compare,
    Messages.playgroundTabCompare,
    Icons.compare_arrows_rounded,
  ),
  _TabEntry(
    PlaygroundTab.benchmark,
    Messages.playgroundTabBenchmark,
    Icons.speed_rounded,
  ),
  _TabEntry(
    PlaygroundTab.dual,
    Messages.playgroundTabDual,
    Icons.vertical_split_rounded,
  ),
];

class _TabTile extends StatelessWidget {
  const _TabTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 40,
        decoration: BoxDecoration(
          color: selected ? palette.accent.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: selected
                ? palette.accent.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? palette.accentStrong : palette.textMuted,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label.tr,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? palette.textPrimary : palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorColumn extends StatelessWidget {
  const _EditorColumn({required this.controller});

  final PlaygroundController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Obx(
            () => Text(
              _titleFor(controller.tab.value),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Obx(
            () => Text(
              _hintFor(controller.tab.value),
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ),
          const SizedBox(height: Insets.md),
          Obx(
            () => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Field(
                    label: Messages.playgroundTargetAccount.tr,
                    child: _isMultiAccount(controller.tab.value)
                        ? _AccountChips(controller: controller)
                        : GlassDropdown<String>(
                            value: controller.account.value,
                            icon: Icons.auto_awesome_motion_outlined,
                            items: [
                              GlassDropdownItem(
                                value: 'auto',
                                label: Messages.playgroundAutoPool.tr,
                              ),
                              for (final account in controller.accounts)
                                GlassDropdownItem(
                                  value: account.id,
                                  label: account.name,
                                ),
                            ],
                            onChanged: (value) =>
                                controller.account.value = value,
                          ),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: _Field(
                    label: Messages.playgroundModel.tr,
                    child: GlassDropdown<String>(
                      value: controller.model.value,
                      icon: Icons.memory_rounded,
                      items: [
                        for (final model in controller.models)
                          GlassDropdownItem(
                            value: model,
                            label: model,
                            mono: true,
                          ),
                      ],
                      onChanged: (value) => controller.model.value = value,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (controller.tab.value == PlaygroundTab.dual) ...[
            const SizedBox(height: Insets.md),
            _Field(
              label: Messages.playgroundSecondModel.tr,
              child: Obx(
                () => GlassDropdown<String>(
                  value: controller.secondModel.value,
                  icon: Icons.memory_rounded,
                  items: [
                    for (final model in controller.models)
                      GlassDropdownItem(value: model, label: model, mono: true),
                  ],
                  onChanged: (value) => controller.secondModel.value = value,
                ),
              ),
            ),
          ],
          const SizedBox(height: Insets.md),
          Text(
            Messages.playgroundPresets.tr,
            style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in controller.presets)
                AppButton(
                  label: preset,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.small,
                  onPressed: () =>
                      controller.promptController.text = _presetPrompt(preset),
                ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Obx(
            () => _AdvancedPanel(
              controller: controller,
              open: controller.advancedOpen.value,
            ),
          ),
          const SizedBox(height: Insets.md),
          Row(
            children: [
              Text(
                Messages.playgroundPrompt.tr,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                'Ctrl + Enter',
                style: TextStyle(
                  fontSize: 11.5,
                  color: palette.textMuted,
                  fontFamily: kMonoFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _PromptBox(controller: controller),
          const SizedBox(height: Insets.md),
          Row(
            children: [
              AppButton(
                label: Messages.playgroundClear.tr,
                icon: Icons.backspace_outlined,
                variant: AppButtonVariant.ghost,
                onPressed: () => controller.promptController.clear(),
              ),
              const Spacer(),
              Obx(
                () => AppButton(
                  label: Messages.playgroundRun.tr,
                  icon: Icons.play_arrow_rounded,
                  variant: AppButtonVariant.primary,
                  size: AppButtonSize.large,
                  loading: controller.running.value,
                  onPressed: controller.run,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _isMultiAccount(PlaygroundTab tab) =>
      tab == PlaygroundTab.compare || tab == PlaygroundTab.benchmark;

  String _titleFor(PlaygroundTab tab) => switch (tab) {
    PlaygroundTab.single => Messages.playgroundTabSingle.tr,
    PlaygroundTab.compare => Messages.playgroundTabCompare.tr,
    PlaygroundTab.benchmark => Messages.playgroundTabBenchmark.tr,
    PlaygroundTab.dual => Messages.playgroundTabDual.tr,
  };

  String _hintFor(PlaygroundTab tab) => switch (tab) {
    PlaygroundTab.single => Messages.playgroundDesc.tr,
    PlaygroundTab.compare => Messages.playgroundCompareHint.tr,
    PlaygroundTab.benchmark => Messages.playgroundBenchmarkHint.tr,
    PlaygroundTab.dual => Messages.playgroundDualHint.tr,
  };
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

class _AdvancedPanel extends StatelessWidget {
  const _AdvancedPanel({required this.controller, required this.open});

  final PlaygroundController controller;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GlassInset(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => controller.advancedOpen.value = !open,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 16, color: palette.textMuted),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      Messages.playgroundAdvanced.tr,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _SliderField(
                          label: Messages.playgroundTemperature.tr,
                          value: controller.temperature.value,
                          min: 0,
                          max: 2,
                          onChanged: (value) =>
                              controller.temperature.value = value,
                        ),
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: _SliderField(
                          label: Messages.playgroundTopP.tr,
                          value: controller.topP.value,
                          min: 0,
                          max: 1,
                          onChanged: (value) => controller.topP.value = value,
                        ),
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: _SliderField(
                          label: Messages.playgroundMaxTokens.tr,
                          value: controller.maxTokens.value.toDouble(),
                          min: 256,
                          max: 8192,
                          onChanged: (value) =>
                              controller.maxTokens.value = value.round(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ),
            Text(
              value.toStringAsFixed(value >= 100 ? 0 : 2),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: kMonoFamily,
                color: palette.accentStrong,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: palette.accent,
            inactiveTrackColor: palette.textMuted.withValues(alpha: 0.2),
            thumbColor: palette.accentStrong,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _OutputColumn extends StatelessWidget {
  const _OutputColumn({required this.controller});

  final PlaygroundController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Response',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const Spacer(),
              Obx(
                () => AppBadge(
                  label: controller.model.value,
                  tone: BadgeTone.accent,
                  mono: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Obx(() {
            final error = controller.runError.value;
            if (error == null || controller.tab.value == PlaygroundTab.single) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: Insets.md),
              child: _ErrorBanner(text: error),
            );
          }),
          Obx(() {
            if (controller.running.value) {
              return const _RunningPlaceholder();
            }
            final tab = controller.tab.value;
            if (_EditorColumn._isMultiAccount(tab)) {
              if (controller.results.isEmpty) return const _EmptyResponse();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in controller.results.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ResultCard(
                        title: _accountName(controller, entry.key),
                        result: entry.value,
                      ),
                    ),
                ],
              );
            }
            if (tab == PlaygroundTab.dual) {
              if (controller.results.isEmpty) return const _EmptyResponse();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final modelId in [
                    controller.model.value,
                    controller.secondModel.value,
                  ])
                    if (controller.results.containsKey(modelId))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ResultCard(
                          title: modelId,
                          result: controller.results[modelId]!,
                        ),
                      ),
                ],
              );
            }
            final result = controller.lastResult.value;
            if (result == null) return const _EmptyResponse();
            return _ResultCard(title: controller.model.value, result: result);
          }),
          const SizedBox(height: Insets.md),
          Obx(() {
            final result = controller.lastResult.value;
            return Row(
              children: [
                _Metric(
                  label: Messages.playgroundLatency.tr,
                  value: result == null ? '—' : '${result.latencyMs} ms',
                ),
                const SizedBox(width: Insets.sm),
                _Metric(
                  label: Messages.playgroundTokens.tr,
                  value: result == null ? '—' : '${result.tokens}',
                ),
                const SizedBox(width: Insets.sm),
                _Metric(
                  label: Messages.playgroundEstimatedCost.tr,
                  value: result == null
                      ? '—'
                      : '\$${(result.tokens * 0.000003).toStringAsFixed(3)}',
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: GlassInset(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: palette.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: kMonoFamily,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunningPlaceholder extends StatelessWidget {
  const _RunningPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              Messages.commonLoading.tr,
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              height: 12,
              width: double.infinity,
              decoration: BoxDecoration(
                color: palette.textMuted.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
            ),
          ),
      ],
    );
  }
}

/// The accounts the multi-account tabs can target.
class _AccountChips extends StatelessWidget {
  const _AccountChips({required this.controller});

  final PlaygroundController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Obx(
      () => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final account in controller.accounts)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final selected = controller.compareAccounts.contains(
                  account.id,
                );
                if (selected) {
                  controller.compareAccounts.remove(account.id);
                } else {
                  controller.compareAccounts.add(account.id);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: controller.compareAccounts.contains(account.id)
                      ? palette.accent.withValues(alpha: 0.16)
                      : palette.glassStrong,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(
                    color: controller.compareAccounts.contains(account.id)
                        ? palette.accent.withValues(alpha: 0.45)
                        : palette.glassBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      controller.compareAccounts.contains(account.id)
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 15,
                      color: controller.compareAccounts.contains(account.id)
                          ? palette.accentStrong
                          : palette.textMuted,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      account.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CopyResponseButton extends StatefulWidget {
  const _CopyResponseButton({required this.text});

  final String text;

  @override
  State<_CopyResponseButton> createState() => _CopyResponseButtonState();
}

class _CopyResponseButtonState extends State<_CopyResponseButton> {
  bool _copied = false;

  @override
  void didUpdateWidget(_CopyResponseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _copied = false;
  }

  @override
  Widget build(BuildContext context) => AppButton(
    label: _copied ? Messages.commonCopied.tr : Messages.commonCopy.tr,
    icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
    variant: AppButtonVariant.ghost,
    size: AppButtonSize.small,
    onPressed: () async {
      final text = widget.text;
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted && widget.text == text) setState(() => _copied = true);
    },
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.title, required this.result});

  final String title;
  final PlaygroundResult result;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.glassStrong,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: result.isError ? palette.danger : palette.glassBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: kMonoFamily,
                    color: palette.accentStrong,
                  ),
                ),
              ),
              Text(
                '${result.latencyMs} ms • ${result.tokens} tok',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: kMonoFamily,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(width: Insets.sm),
              _CopyResponseButton(text: result.displayText),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            result.displayText,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: result.isError ? palette.danger : palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in the multi-account tabs before the first run.
class _EmptyResponse extends StatelessWidget {
  const _EmptyResponse();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.glassStrong,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.glassBorder),
      ),
      child: Center(
        child: Text(
          Messages.playgroundRun.tr,
          style: TextStyle(fontSize: 13, color: palette.textMuted),
        ),
      ),
    );
  }
}

/// The display name of an account id.
String _accountName(PlaygroundController controller, String accountId) {
  for (final account in controller.accounts) {
    if (account.id == accountId) return account.name;
  }
  return accountId;
}

/// The account behind an id, when it is still in the pool.
Account? _accountFor(PlaygroundController controller, String accountId) {
  for (final account in controller.accounts) {
    if (account.id == accountId) return account;
  }
  return null;
}

/// The prompt a preset chip writes into the editor.
String _presetPrompt(String preset) => switch (preset) {
  'Say hello' => 'Say hello and introduce yourself in one sentence.',
  'Reasoning' => 'A train leaves at 14:05 and arrives at 17:40. It stops 12 minutes at three stations. How long was the journey?',
  'Identity' => 'State your exact model name and your context window.',
  _ => 'Write a typed TypeScript function that groups items by a key.',
};

/// The multiline prompt editor shared by every playground tab.
class _PromptBox extends StatelessWidget {
  const _PromptBox({required this.controller, this.minLines = 6});

  final PlaygroundController controller;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.glassStrong,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.glassBorder),
      ),
      child: TextField(
        controller: controller.promptController,
        maxLines: null,
        minLines: minLines,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.55,
          color: palette.textPrimary,
        ),
        cursorColor: palette.accent,
        decoration: InputDecoration(
          hintText: Messages.playgroundPrompt.tr,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
          hintStyle: TextStyle(color: palette.textMuted, fontSize: 13.5),
        ),
      ),
    );
  }
}

/// Why a run ended before any answer arrived.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Insets.sm),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: palette.danger),
          const SizedBox(width: Insets.xs),
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: palette.danger,
              ),
            ),
          ),
          const SizedBox(width: Insets.sm),
          _CopyResponseButton(text: text),
        ],
      ),
    );
  }
}

/// The full width editor of the multi-account compare tab.
class _CompareSection extends StatelessWidget {
  const _CompareSection({required this.controller});

  final PlaygroundController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            Messages.playgroundCompareTitle.tr,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            Messages.playgroundCompareDesc.tr,
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              Text(
                Messages.playgroundSelectAccounts.tr,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const Spacer(),
              _SelectionAction(
                icon: Icons.check_box_rounded,
                label: Messages.playgroundSelectAll.tr,
                onTap: controller.selectAllCompare,
              ),
              const SizedBox(width: Insets.lg),
              _SelectionAction(
                icon: Icons.check_box_outline_blank_rounded,
                label: Messages.playgroundClearAll.tr,
                onTap: controller.clearAllCompare,
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Obx(() {
            final accounts = controller.accounts.toList();
            return LayoutBuilder(
              builder: (context, constraints) {
                return _AccountGrid(
                  width: constraints.maxWidth,
                  children: [
                    for (final account in accounts)
                      _CompareAccountCard(
                        controller: controller,
                        account: account,
                      ),
                  ],
                );
              },
            );
          }),
          const SizedBox(height: Insets.lg),
          Text(
            Messages.playgroundModel.tr,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Obx(
                      () => GlassDropdown<String>(
                        value: controller.model.value,
                        icon: Icons.memory_rounded,
                        items: [
                          for (final model in controller.catalog)
                            GlassDropdownItem(
                              value: model.id,
                              label: controller.modelLabel(model.id),
                            ),
                        ],
                        onChanged: (value) => controller.model.value = value,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Insets.sm),
              for (final preset in controller.presets.take(3)) ...[
                AppButton(
                  label: preset,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.small,
                  onPressed: () =>
                      controller.promptController.text = _presetPrompt(preset),
                ),
                const SizedBox(width: Insets.xs),
              ],
            ],
          ),
          const SizedBox(height: Insets.md),
          _PromptBox(controller: controller, minLines: 4),
          const SizedBox(height: Insets.md),
          Row(
            children: [
              Obx(
                () => Text(
                  Messages.playgroundSelectedCount.tr.replaceAll(
                    '{n}',
                    '${controller.compareAccounts.length}',
                  ),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: palette.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              Obx(
                () => AppButton(
                  label: Messages.playgroundRunSelected.tr,
                  icon: Icons.play_arrow_rounded,
                  variant: AppButtonVariant.primary,
                  loading: controller.running.value,
                  onPressed: controller.compareAccounts.isEmpty
                      ? null
                      : controller.run,
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Divider(height: 1, color: palette.glassBorder),
          const SizedBox(height: Insets.lg),
          Text(
            Messages.playgroundComparisonResults.tr,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: Insets.md),
          Obx(() {
            final error = controller.runError.value;
            final entries = controller.results.entries.toList();
            if (error == null && entries.isEmpty) {
              return const _EmptyResponse();
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                return _AccountGrid(
                  width: constraints.maxWidth,
                  children: [
                    if (error != null) _ErrorBanner(text: error),
                    for (final entry in entries)
                      _CompareResultCard(
                        controller: controller,
                        accountId: entry.key,
                        result: entry.value,
                      ),
                  ],
                );
              },
            );
          }),
        ],
      ),
    );
  }
}

/// Lays children out in two equal columns when there is room for them.
class _AccountGrid extends StatelessWidget {
  const _AccountGrid({required this.width, required this.children});

  final double width;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final wide = width > 720;
    final cardWidth = wide ? (width - Insets.md) / 2 : width;
    return Wrap(
      spacing: Insets.md,
      runSpacing: Insets.md,
      children: [
        for (final child in children) SizedBox(width: cardWidth, child: child),
      ],
    );
  }
}

/// The select all / clear all affordances of the compare tab.
class _SelectionAction extends StatelessWidget {
  const _SelectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: palette.textSecondary),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One selectable account of the compare pool.
class _CompareAccountCard extends StatelessWidget {
  const _CompareAccountCard({required this.controller, required this.account});

  final PlaygroundController controller;
  final Account account;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Obx(() {
      final selected = controller.compareAccounts.contains(account.id);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => controller.toggleCompareAccount(account.id),
        child: Container(
          padding: const EdgeInsets.all(Insets.sm),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.10)
                : palette.glassStrong,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: selected
                  ? palette.accent.withValues(alpha: 0.5)
                  : palette.glassBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 18,
                color: selected ? palette.accentStrong : palette.textMuted,
              ),
              const SizedBox(width: Insets.sm),
              MonogramAvatar(text: account.name, size: 30),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.handle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Insets.xs),
              AppBadge(
                label: account.quotas.isEmpty
                    ? '—'
                    : '${(account.globalRemaining * 100).round()}%',
                tone: account.quotas.isEmpty
                    ? BadgeTone.neutral
                    : account.globalRemaining > 0.25
                    ? BadgeTone.neutral
                    : BadgeTone.danger,
                dense: true,
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// One answer card of the comparison results.
class _CompareResultCard extends StatelessWidget {
  const _CompareResultCard({
    required this.controller,
    required this.accountId,
    required this.result,
  });

  final PlaygroundController controller;
  final String accountId;
  final PlaygroundResult result;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final account = _accountFor(controller, accountId);

    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: palette.glassStrong,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: result.isError
              ? palette.danger.withValues(alpha: 0.45)
              : palette.glassBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppBadge(
                label: result.isError
                    ? (result.status > 0
                          ? '${Messages.playgroundError.tr} ${result.status}'
                          : Messages.playgroundError.tr)
                    : Messages.playgroundSuccess.tr,
                tone: result.isError ? BadgeTone.danger : BadgeTone.success,
                dense: true,
              ),
              const SizedBox(width: Insets.sm),
              MonogramAvatar(text: account?.name ?? accountId, size: 22),
              const SizedBox(width: Insets.xs),
              Expanded(
                child: Text(
                  account?.handle ?? accountId,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          AppBadge(
            label: controller.model.value,
            tone: BadgeTone.neutral,
            mono: true,
            dense: true,
          ),
          const SizedBox(height: Insets.sm),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 13, color: palette.textMuted),
              const SizedBox(width: 6),
              Text(
                '${result.latencyMs} ms',
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: kMonoFamily,
                  color: palette.textMuted,
                ),
              ),
              const Spacer(),
              _CopyResponseButton(text: result.displayText),
            ],
          ),
          const SizedBox(height: Insets.sm),
          SelectableText(
            result.displayText,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: result.isError ? palette.danger : palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
