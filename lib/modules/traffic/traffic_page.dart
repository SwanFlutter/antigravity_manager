import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../I18n/messages.dart';
import '../../core/data/mock_data.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_field.dart';
import '../../core/widgets/app_toggle.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hover_builder.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/status_badge.dart';
import 'traffic_controller.dart';

class TrafficPage extends ReactiveGetView<TrafficController> {
  const TrafficPage({super.key});

  @override
  Widget buildReactive(BuildContext context) {
    final controller = Get.find<TrafficController>();

    // Read once here so the page level observer follows the log.
    final storedCount = controller.storedCount;

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
            icon: Icons.insights_outlined,
            title: Messages.trafficTitle.tr,
            description: Messages.trafficDesc.tr,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBadge(
                  label: Messages.trafficRecords
                      .tr
                      .replaceAll('{n}', '$storedCount'),
                  tone: BadgeTone.accent,
                  mono: true,
                ),
                const SizedBox(width: 8),
                Obx(
                  () => AppBadge(
                    label: controller.storedSizeLabel,
                    tone: BadgeTone.neutral,
                    mono: true,
                  ),
                ),
              ],
            ),
          ),
          const _FilterPanel(),
          const SizedBox(height: Insets.md),
          const _LogTable(),
        ],
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<TrafficController>();

    return GlassPanel(
      padding: const EdgeInsetsDirectional.fromSTEB(Insets.md, Insets.sm, Insets.md, Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Obx(
                () => AppSegmented<TrafficCategory>(
                  value: controller.category.value,
                  dense: true,
                  options: [
                    for (final category in TrafficCategory.values)
                      SegmentOption(
                        label: category.label,
                        value: category,
                      ),
                  ],
                  onChanged: controller.setCategory,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380, minWidth: 260),
                child: GlassSearchField(
                  controller: controller.searchController,
                  hint: Messages.trafficSearch.tr,
                  onChanged: controller.setQuery,
                  trailing: AppIconButton(
                    icon: Icons.close_rounded,
                    tooltip: Messages.commonClear.tr,
                    size: 26,
                    iconSize: 14,
                    onPressed: controller.clearQuery,
                  ),
                ),
              ),
              AppIconButton(
                icon: Icons.refresh_rounded,
                tooltip: Messages.commonRefresh.tr,
                onPressed: controller.reload,
              ),
              AppButton(
                label: Messages.trafficClearCategory.tr,
                icon: Icons.delete_sweep_outlined,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.small,
                onPressed: controller.clearCategory,
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          const LuminousDivider(),
          const SizedBox(height: Insets.sm),
          Obx(
            () => Wrap(
              spacing: Insets.md,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                _Filter(
                  label: Messages.trafficAccount.tr,
                  width: 250,
                  child: GlassDropdown<String>(
                    value: controller.accountFilter.value,
                    items: [
                      GlassDropdownItem(
                        value: 'all',
                        label: Messages.trafficAllAccounts.tr,
                      ),
                      for (final account in controller.availableAccounts)
                        GlassDropdownItem(
                          value: account,
                          label: account,
                          mono: true,
                        ),
                    ],
                    onChanged: controller.setAccountFilter,
                  ),
                ),
                const SizedBox(width: Insets.md),
                _Filter(
                  label: Messages.trafficModelFamily.tr,
                  width: 230,
                  child: GlassDropdown<String>(
                    value: controller.familyFilter.value?.name ?? 'all',
                    items: [
                      GlassDropdownItem(
                        value: 'all',
                        label: Messages.trafficAllFamilies.tr,
                      ),
                      for (final family in ModelFamily.values)
                        GlassDropdownItem(
                          value: family.name,
                          label: family.label,
                        ),
                    ],
                    onChanged: (value) => controller.setFamilyFilter(
                      value == 'all' ? null : ModelFamily.values.byName(value),
                    ),
                  ),
                ),
                const SizedBox(width: Insets.md),
                _Filter(
                  label: Messages.trafficOutput.tr,
                  width: 200,
                  child: GlassDropdown<String>(
                    value: controller.outputFilter.value,
                    items: [
                      GlassDropdownItem(
                        value: 'all',
                        label: Messages.trafficAllOutputs.tr,
                      ),
                      for (final output in controller.availableOutputs)
                        GlassDropdownItem(value: output, label: output),
                    ],
                    onChanged: controller.setOutputFilter,
                  ),
                ),
                const SizedBox(width: Insets.md),
                _Filter(
                  label: Messages.trafficStatus.tr,
                  width: 210,
                  child: GlassDropdown<String>(
                    value: controller.statusFilter.value,
                    items: [
                      GlassDropdownItem(
                        value: 'all',
                        label: Messages.trafficAllStatuses.tr,
                      ),
                      for (final result in TrafficResult.values)
                        GlassDropdownItem(
                          value: result.name,
                          label: result.label,
                        ),
                    ],
                    onChanged: controller.setStatusFilter,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: ToggleRow(
                    title: Messages.trafficIncludeKey.tr,
                    subtitle: '',
                    value: controller.includeKeyInCurl.value,
                    onChanged: (value) =>
                        controller.includeKeyInCurl.value = value,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({required this.label, required this.child, required this.width});

  final String label;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: kLabelTracking,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(width: width, child: child),
      ],
    );
  }
}

class _LogTable extends StatelessWidget {
  const _LogTable();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<TrafficController>();
    final palette = context.palette;

    return Obx(() {
      final rows = controller.pagedEntries;

      return GlassPanel(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _TableHeader(),
            const LuminousDivider(),
            if (rows.isEmpty)
              EmptyState(
                icon: Icons.receipt_long_outlined,
                title: Messages.trafficEmpty.tr,
                message: Messages.trafficEmptyMessage.tr,
                action: AppButton(
                  label: Messages.commonReset.tr,
                  icon: Icons.refresh_rounded,
                  onPressed: controller.resetFilters,
                ),
              )
            else
              for (final entry in rows) ...[
                _LogRow(entry: entry, controller: controller),
                const LuminousDivider(),
              ],
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 14),
              child: Row(
                children: [
                  Text(
                    Messages.trafficTotal
                        .tr
                        .replaceAll('{n}', '${controller.totalCount}'),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: palette.textMuted,
                      fontFamily: kMonoFamily,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    Messages.trafficPage
                        .tr
                        .replaceAll('{n}', '${controller.page.value}'),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: palette.textMuted,
                      fontFamily: kMonoFamily,
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppIconButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: Messages.commonMore.tr,
                    onPressed: controller.canGoBack ? controller.previousPage : null,
                  ),
                  const SizedBox(width: 6),
                  AppIconButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: Messages.commonMore.tr,
                    onPressed: controller.canGoForward ? controller.nextPage : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget cell(String label, {double flex = 1, AlignmentGeometry align = AlignmentDirectional.centerStart}) {
      return Expanded(
        flex: (flex * 10).round(),
        child: Align(
          alignment: align,
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: kLabelTracking,
              color: palette.textMuted,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 14, 18, 12),
      child: Row(
        children: [
          cell(Messages.trafficTime.tr, flex: 1.1),
          cell(Messages.trafficModelUsed.tr, flex: 1.6),
          cell(Messages.trafficAccount.tr, flex: 1.3),
          cell(Messages.trafficTokens.tr, flex: 1.0),
          cell(Messages.trafficOutput.tr, flex: 0.7),
          cell(Messages.trafficResult.tr, flex: 1.0),
          cell(Messages.trafficDuration.tr, flex: 0.8),
          cell(Messages.trafficEndpoint.tr, flex: 1.4),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.controller});

  final TrafficEntry entry;
  final TrafficController controller;

  BadgeTone get _resultTone => switch (entry.result) {
        TrafficResult.success => BadgeTone.success,
        TrafficResult.appError => BadgeTone.danger,
        TrafficResult.signInFailed => BadgeTone.warning,
        TrafficResult.timeout => BadgeTone.info,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget cell(Widget child, {double flex = 1, AlignmentGeometry align = AlignmentDirectional.centerStart}) {
      return Expanded(
        flex: (flex * 10).round(),
        child: Align(
          alignment: align,
          child: child,
        ),
      );
    }

    return HoverBuilder(
      builder: (context, hovered, focused) {
        return Container(
          color: hovered ? palette.accentSoft.withValues(alpha: 0.4) : null,
          padding: const EdgeInsetsDirectional.fromSTEB(18, 11, 18, 11),
          child: Row(
            children: [
              cell(
                Text(
                  entry.time,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: kMonoFamily,
                    color: palette.textSecondary,
                  ),
                ),
                flex: 1.1,
              ),
              cell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.model,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: kMonoFamily,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.family.shortLabel.toLowerCase(),
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
                flex: 1.6,
              ),
              cell(
                Text(
                  entry.account,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: kMonoFamily,
                    color: palette.textSecondary,
                  ),
                ),
                flex: 1.3,
              ),
              cell(
                Text(
                  '${entry.tokensIn} / ${entry.tokensOut}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: kMonoFamily,
                    color: palette.textSecondary,
                  ),
                ),
                flex: 1.0,
              ),
              cell(
                Text(
                  entry.output,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
                flex: 0.7,
              ),
              cell(
                AppBadge(
                  label: entry.result.label,
                  tone: _resultTone,
                  dense: true,
                ),
                flex: 1.0,
              ),
              cell(
                Text(
                  '${entry.statusCode}  ·  ${entry.durationMs} ms',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: kMonoFamily,
                    color: palette.textSecondary,
                  ),
                ),
                flex: 0.8,
              ),
              cell(
                Text(
                  entry.endpoint,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: kMonoFamily,
                    color: palette.textMuted,
                  ),
                ),
                flex: 1.4,
              ),
              SizedBox(
                width: 40,
                child: AppOverflowMenu<String>(
                  items: [
                    AppMenuEntry(
                      label: Messages.trafficCopyCurl.tr,
                      value: 'curl',
                      icon: Icons.copy_rounded,
                    ),
                    AppMenuEntry(
                      label: Messages.trafficClearLog.tr,
                      value: 'clear',
                      icon: Icons.delete_outline_rounded,
                      destructive: true,
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'curl') {
                      controller.copyCurl(entry);
                    } else {
                      controller.clearEntry(entry);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
