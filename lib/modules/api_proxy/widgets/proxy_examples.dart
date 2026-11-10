import 'package:flutter/material.dart';
import 'package:flutter_code_view/flutter_code_view.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../../I18n/messages.dart';
import '../../../app/controller/api_proxy_controller.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cached_code_view.dart';
import '../../../core/widgets/glass_panel.dart';

/// Usage examples for the local gateway.
///
/// The panel lists every model the proxy can serve. Picking a model rewrites
/// the model id inside the curl, python and node snippets, and picking a
/// protocol switches the endpoint and the request body.
class ProxyExamplesSection extends StatelessWidget {
  const ProxyExamplesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ProtocolCards(),
        const SizedBox(height: Insets.md),
        const _ModelPicker(),
        const SizedBox(height: Insets.md),
        const _CodeBlocks(),
      ],
    );
  }
}

class _ProtocolCards extends StatelessWidget {
  const _ProtocolCards();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ApiProxyController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 900 ? 2 : 1;
        final width =
            (constraints.maxWidth - Insets.md * (columns - 1)) / columns;

        return Obx(
          () => Wrap(
            spacing: Insets.md,
            runSpacing: Insets.md,
            children: [
              SizedBox(
                width: width,
                child: _ProtocolCard(
                  title: Messages.proxyProtocolOpenAI.tr,
                  hint: Messages.proxyProtocolOpenAIHint.tr,
                  endpoint: controller.chatEndpoint,
                  icon: Icons.terminal_rounded,
                  selected: controller.protocol.value == ProxyProtocol.openai,
                  onTap: () => controller.protocol.value = ProxyProtocol.openai,
                ),
              ),
              SizedBox(
                width: width,
                child: _ProtocolCard(
                  title: Messages.proxyProtocolAnthropic.tr,
                  hint: Messages.proxyProtocolAnthropicHint.tr,
                  endpoint: controller.messagesEndpoint,
                  icon: Icons.forum_outlined,
                  selected:
                      controller.protocol.value == ProxyProtocol.anthropic,
                  onTap: () =>
                      controller.protocol.value = ProxyProtocol.anthropic,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({
    required this.title,
    required this.hint,
    required this.endpoint,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String hint;
  final String endpoint;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GlassInset(
      radius: Radii.md,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? palette.accentStrong : palette.textMuted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: palette.accentStrong,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: palette.glassStrong,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: palette.glassBorder),
              ),
              child: Row(
                children: [
                  Text(
                    'POST',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: kLabelTracking,
                      color: palette.accentStrong,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      endpoint.replaceFirst('http://192.0.2.42:8045', ''),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontFamily: kMonoFamily,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              hint,
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lists every model of the catalog and lets the user pick the one used in
/// the generated snippets.
class _ModelPicker extends StatelessWidget {
  const _ModelPicker();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ApiProxyController>();
    final palette = context.palette;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Messages.proxyExampleModel.tr,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      Messages.proxyExampleModelHint.tr,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Obx(
                () => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accentSoft,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    controller.selectedExampleModel.value,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontFamily: kMonoFamily,
                      color: palette.accentStrong,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Obx(
            () => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final model in controller.catalog)
                  _ModelChip(
                    label: model.label,
                    icon: model.family.icon,
                    selected: controller.selectedExampleModel.value == model.id,
                    onTap: () =>
                        controller.selectedExampleModel.value = model.id,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? palette.accent.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: selected
                ? palette.accent.withValues(alpha: 0.55)
                : palette.glassBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? palette.accentStrong : palette.textMuted,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? palette.textPrimary : palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The generated snippets.
class _CodeBlocks extends StatelessWidget {
  const _CodeBlocks();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ApiProxyController>();

    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CodeBlock(
            title: Messages.proxyExampleCurl.tr,
            source: controller.curlSnippet,
            language: Languages.bash,
          ),
          const SizedBox(height: Insets.md),
          _CodeBlock(
            title: Messages.proxyExamplePython.tr,
            source: controller.pythonSnippet,
            language: Languages.python,
          ),
          const SizedBox(height: Insets.md),
          _CodeBlock(
            title: Messages.proxyExampleNode.tr,
            source: controller.nodeSnippet,
            language: Languages.javascript,
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.title,
    required this.source,
    required this.language,
  });

  final String title;
  final String source;
  final Languages language;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GlassPanel(
      padding: const EdgeInsets.all(Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const Spacer(),
              AppButton(
                label: Messages.commonCopy.tr,
                icon: Icons.copy_rounded,
                size: AppButtonSize.small,
                variant: AppButtonVariant.ghost,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          // Cached instance: the highlighted source is not re-parsed while
          // the theme transition animates through its intermediate frames.
          CachedCodeView(
            source: source,
            language: language,
            fontSize: 12.5,
          ),
        ],
      ),
    );
  }
}
