import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../I18n/messages.dart';
import '../../app/controller/api_proxy_controller.dart';
import '../../core/data/mock_data.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_field.dart';
import '../../core/widgets/app_toggle.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/status_badge.dart';
import '../../data/cloud_models.dart';
import 'widgets/proxy_examples.dart';

class ApiProxyPage extends ReactiveGetView<ApiProxyController> {
  const ApiProxyPage({super.key});

  @override
  Widget buildReactive(BuildContext context) {
    final controller = Get.find<ApiProxyController>();

    // Read once here so the page level observer follows the service state.
    final running = controller.running;
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
            icon: Icons.route_outlined,
            title: Messages.proxyTitle.tr,
            description: Messages.proxyDesc.tr,
          ),
          const SizedBox(height: Insets.md),
          _ProxyTabs(tab: tab),
          const SizedBox(height: Insets.lg),
          switch (tab) {
            0 => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AccessStrip(running: running),
                const SizedBox(height: Insets.md),
                const _ServicePanel(),
              ],
            ),
            1 => const _MappingSection(),
            2 => const ProxyExamplesSection(),
            _ => const _GatewaySection(),
          },
        ],
      ),
    );
  }
}

/// Tab strip of the proxy screen.
class _ProxyTabs extends StatelessWidget {
  const _ProxyTabs({required this.tab});

  final int tab;

  static const List<(String, int)> _entries = [
    (Messages.proxyTabTools, 0),
    (Messages.proxyTabModels, 1),
    (Messages.proxyTabExamples, 2),
    (Messages.proxyTabGateway, 3),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ApiProxyController>();
    final palette = context.palette;

    return Row(
      children: [
        for (final entry in _entries)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 24),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.tab.value = entry.$2,
              child: Container(
                padding: const EdgeInsets.only(bottom: 7),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: tab == entry.$2
                          ? palette.accent
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  entry.$1.tr,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: tab == entry.$2
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: tab == entry.$2
                        ? palette.textPrimary
                        : palette.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The panel that shows the local gateway: its state, its key and its traffic.
class _GatewaySection extends StatelessWidget {
  const _GatewaySection();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ApiProxyController>();
    final palette = context.palette;

    return Obx(() {
      final status = controller.proxy.value;
      final entries = controller.traffic;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.settings_ethernet_rounded,
                        size: 18, color: palette.textMuted),
                    const SizedBox(width: 10),
                    Text(
                      Messages.proxyGatewayStatus.tr,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    AppBadge(
                      label: status.running
                          ? Messages.proxyGatewayRunning.tr
                          : Messages.proxyGatewayStopped.tr,
                      tone:
                          status.running ? BadgeTone.success : BadgeTone.danger,
                      dot: true,
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                GroupLabel(Messages.proxyGatewayKey.tr),
                const SizedBox(height: Insets.sm),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: palette.glassStrong,
                          borderRadius: BorderRadius.circular(Radii.sm),
                          border: Border.all(color: palette.glassBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                controller.maskedApiKey,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: kMonoFamily,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Show',
                              onPressed: () => controller.revealKey.toggle(),
                              icon: Icon(
                                controller.revealKey.value
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 17,
                                color: palette.textMuted,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy',
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: controller.apiKey),
                                );
                              },
                              icon: Icon(Icons.copy_rounded,
                                  size: 16, color: palette.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    AppButton(
                      label: Messages.proxyGatewayRotate.tr,
                      icon: Icons.autorenew_rounded,
                      variant: AppButtonVariant.secondary,
                      onPressed: () => controller.rotateKey(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  Messages.proxyGatewayKeyHint.tr,
                  style: TextStyle(fontSize: 12, color: palette.textMuted),
                ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: palette.glassStrong,
                        borderRadius: BorderRadius.circular(Radii.sm),
                        border: Border.all(color: palette.glassBorder),
                      ),
                      child: Text(
                        '${status.baseUrl}/v1',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontFamily: kMonoFamily,
                          color: palette.accentStrong,
                        ),
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    SizedBox(
                      width: 140,
                      child: GlassTextField(
                        controller: controller.portController,
                        label: 'Port',
                        monospace: true,
                      ),
                    ),
                    const Spacer(),
                    AppButton(
                      label: status.running
                          ? Messages.proxyGatewayStop.tr
                          : Messages.proxyGatewayStart.tr,
                      icon: status.running
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline_rounded,
                      variant: status.running
                          ? AppButtonVariant.danger
                          : AppButtonVariant.primary,
                      onPressed: () => status.running
                          ? controller.stopProxy()
                          : controller.startProxy(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.timeline_rounded, size: 18,
                        color: palette.textMuted),
                    const SizedBox(width: 10),
                    Text(
                      Messages.proxyGatewayTraffic.tr,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${status.models} models',
                      style: TextStyle(fontSize: 12, color: palette.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                if (entries.isEmpty)
                  Text(
                    Messages.proxyGatewayEmpty.tr,
                    style: TextStyle(fontSize: 12.5, color: palette.textMuted),
                  )
                else
                  for (final entry in entries) _TrafficRow(entry: entry),
              ],
            ),
          ),
        ],
      );
    });
  }
}

/// One request of the traffic log.
class _TrafficRow extends StatelessWidget {
  const _TrafficRow({required this.entry});

  final TrafficRecord entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final time = DateTime.fromMillisecondsSinceEpoch(entry.at);
    final stamp = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.glassBorder)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              stamp,
              style: TextStyle(
                fontSize: 12,
                fontFamily: kMonoFamily,
                color: palette.textMuted,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              entry.protocol,
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              entry.model,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontFamily: kMonoFamily,
                color: palette.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              '${entry.durationMs} ms',
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
          ),
          AppBadge(
            label: '${entry.status}',
            tone: entry.isSuccess ? BadgeTone.success : BadgeTone.danger,
          ),
        ],
      ),
    );
  }
}

class _AccessStrip extends StatelessWidget {
  const _AccessStrip({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ApiProxyController>();
    final palette = context.palette;

    return GlassPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.lan_outlined, size: 17, color: palette.textMuted),
          const SizedBox(width: 10),
          Text(
            Messages.proxyLocalAccess.tr,
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: palette.glassStrong,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: palette.glassBorder),
            ),
            child: Text(
              '${controller.baseUrl}/v1',
              style: TextStyle(
                fontSize: 12.5,
                fontFamily: kMonoFamily,
                color: palette.accentStrong,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 240,
            child: GlassDropdown<String>(
              value: controller.selectedNetwork.value,
              icon: Icons.wifi_rounded,
              items: [
                for (final network in controller.networks)
                  GlassDropdownItem(value: network, label: network),
              ],
              onChanged: (value) => controller.selectedNetwork.value = value,
            ),
          ),
          const Spacer(),
          AppBadge(
            label: running
                ? Messages.proxyRunning.tr
                : Messages.proxyStopped.tr,
            tone: running ? BadgeTone.success : BadgeTone.danger,
            dot: true,
          ),
        ],
      ),
    );
  }
}

class _ServicePanel extends StatelessWidget {
  const _ServicePanel();

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
                      Messages.proxyServiceStatus.tr,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Messages.proxyDesc.tr,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Obx(
                () => AppButton(
                  label: controller.running
                      ? Messages.proxyStop.tr
                      : Messages.proxyStart.tr,
                  icon: controller.running
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline_rounded,
                  variant: controller.running
                      ? AppButtonVariant.danger
                      : AppButtonVariant.primary,
                  onPressed: controller.app.toggleProxy,
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          const LuminousDivider(),
          const SizedBox(height: Insets.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NumberField(
                  controller: controller.portController,
                  label: Messages.proxyListenPort.tr,
                  unit: Messages.proxyPortUnit.tr,
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: NumberField(
                  controller: controller.timeoutController,
                  label: Messages.proxyRequestTimeout.tr,
                  unit: Messages.proxyTimeoutUnit.tr,
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          GlassTextField(
            controller: controller.keyController,
            label: Messages.proxyApiKey.tr,
            icon: Icons.key_rounded,
            monospace: true,
            obscure: true,
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIconButton(
                  icon: controller.revealKey.value
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  tooltip: controller.revealKey.value
                      ? Messages.commonHide.tr
                      : Messages.commonShow.tr,
                  size: 30,
                  iconSize: 16,
                  onPressed: () =>
                      controller.revealKey.value = !controller.revealKey.value,
                ),
                const SizedBox(width: 6),
                AppButton(
                  label: Messages.commonCopy.tr,
                  icon: Icons.copy_rounded,
                  size: AppButtonSize.small,
                  onPressed: () {},
                ),
                const SizedBox(width: 6),
                AppButton(
                  label: Messages.proxyRegenerate.tr,
                  icon: Icons.autorenew_rounded,
                  size: AppButtonSize.small,
                  onPressed: controller.regenerateKey,
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.sm),
          Obx(
            () => ToggleRow(
              title: Messages.proxyAutoStart.tr,
              subtitle: Messages.proxyAutoStartHint.tr,
              icon: Icons.power_settings_new_rounded,
              value: controller.autoStart.value,
              onChanged: (value) => controller.autoStart.value = value,
            ),
          ),
        ],
      ),
    );
  }
}

class _MappingSection extends StatelessWidget {
  const _MappingSection();

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
                      Messages.proxyModelMapping.tr,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Messages.proxyModelMappingDesc.tr,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                label: Messages.proxyRestoreDefaults.tr,
                icon: Icons.settings_backup_restore_rounded,
                size: AppButtonSize.small,
                onPressed: controller.restoreDefaults,
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          GlassInset(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Messages.proxyOnlyListed.tr,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        Messages.proxyOnlyListedHint.tr,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                GlassSwitch(value: true, onChanged: (_) {}),
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1100 ? 2 : 1;
              final width =
                  (constraints.maxWidth - Insets.md * (columns - 1)) / columns;

              return Obx(
                () => Wrap(
                  spacing: Insets.md,
                  runSpacing: Insets.md,
                  children: [
                    for (var i = 0; i < controller.mappings.length; i++)
                      SizedBox(
                        width: width,
                        child: _MappingCard(
                          mapping: controller.mappings[i],
                          modelIds: controller.modelIds,
                          onChanged: (value) =>
                              controller.updateMapping(i, value),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MappingCard extends StatelessWidget {
  const _MappingCard({
    required this.mapping,
    required this.modelIds,
    required this.onChanged,
  });

  final ModelMapping mapping;
  final List<String> modelIds;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GlassInset(
      radius: Radii.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: mapping.enabled ? palette.accent : palette.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  mapping.source,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            Messages.proxyMapsTo.tr,
            style: TextStyle(fontSize: 12, color: palette.textMuted),
          ),
          const SizedBox(height: 7),
          GlassDropdown<String>(
            value: modelIds.contains(mapping.target)
                ? mapping.target
                : modelIds.first,
            items: [
              for (final model in modelIds)
                GlassDropdownItem(value: model, label: model, mono: true),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
