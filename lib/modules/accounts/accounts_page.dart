import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../I18n/messages.dart';
import '../../app/controller/accounts_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_field.dart';
import '../../core/widgets/app_toggle.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/responsive_card_grid.dart';
import '../../core/widgets/responsive_row.dart';
import '../../core/widgets/status_badge.dart';
import 'widgets/account_card.dart';

class AccountsPage extends ReactiveGetView<AccountsController> {
  const AccountsPage({super.key});

  @override
  Widget buildReactive(BuildContext context) {
    final controller = Get.find<AccountsController>();

    // Read once here so the page level observer follows the account pool.
    final accountCount = controller.accounts.length;

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
            icon: Icons.grid_view_rounded,
            title: Messages.accountsTitle.tr,
            description: Messages.accountsDesc.tr,
            actions: [
              AppButton(
                label: Messages.accountsImportLocal.tr,
                icon: Icons.computer_rounded,
                variant: AppButtonVariant.ghost,
              ),
              AppButton(
                label: Messages.accountsExport.tr,
                icon: Icons.file_upload_outlined,
                variant: AppButtonVariant.secondary,
              ),
              AppButton(
                label: Messages.accountsImport.tr,
                icon: Icons.file_download_outlined,
                variant: AppButtonVariant.secondary,
              ),
              AppButton(
                label: Messages.accountsAddAccount.tr,
                icon: Icons.add_rounded,
                variant: AppButtonVariant.primary,
                loading: controller.connecting.value,
                onPressed: () => controller.startConnect(),
              ),
            ],
          ),
          const _SummaryRow(),
          const SizedBox(height: Insets.md),
          const _ConnectPanel(),
          const _Toolbar(),
          const SizedBox(height: Insets.lg),
          _AccountGallery(accountCount: accountCount),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AccountsController>();

    return Obx(() {
      final remaining = controller.globalRemaining;

      return ResponsiveCardRow(
        minCardWidth: 250,
        children: [
          StatCard(
            label: Messages.accountsTotal.tr,
            value: '${controller.totalCount}',
            icon: Icons.people_alt_outlined,
            tone: BadgeTone.accent,
            footnote: Messages.accountsTotalHint.tr,
          ),
          StatCard(
            label: Messages.accountsActive.tr,
            value: '${controller.activeCount}',
            icon: Icons.check_circle_outline_rounded,
            tone: BadgeTone.success,
            footnote: Messages.accountsActiveHint.tr,
          ),
          StatCard(
            label: Messages.accountsRateLimited.tr,
            value: '${controller.rateLimitedCount}',
            icon: Icons.schedule_rounded,
            tone: BadgeTone.warning,
            footnote: Messages.accountsRateLimitedHint.tr,
          ),
          StatCard(
            label: Messages.accountsGlobalQuota.tr,
            value: '${(remaining * 100).round()}%',
            icon: Icons.donut_large_rounded,
            tone: remaining < 0.4 ? BadgeTone.warning : BadgeTone.success,
            meter: remaining,
            footnote: Messages.accountsGlobalQuotaHint.tr,
          ),
        ],
      );
    });
  }
}

/// The panel that shows the connection of a Google account.
class _ConnectPanel extends StatefulWidget {
  const _ConnectPanel();

  @override
  State<_ConnectPanel> createState() => _ConnectPanelState();
}

class _ConnectPanelState extends State<_ConnectPanel> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AccountsController>();
    final palette = context.palette;

    return Obx(() {
      final status = controller.connectStatus.value;
      final error = controller.connectError.value;
      final url = controller.connectUrl.value;

      if (status.isEmpty && error == null) return const SizedBox.shrink();

      final tone = status == 'completed'
          ? palette.success
          : (status == 'failed' || status == 'expired'
              ? palette.danger
              : palette.accent);

      return Padding(
        padding: const EdgeInsets.only(bottom: Insets.md),
        child: GlassPanel(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.link_rounded, size: 18, color: tone),
                  const SizedBox(width: 10),
                  Text(
                    Messages.accountsConnectTitle.tr,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.sm),
              Text(
                switch (status) {
                  'completed' => Messages.accountsConnectDone.tr,
                  'failed' || 'expired' => Messages.accountsConnectFailed.tr,
                  _ => Messages.accountsConnectWaiting.tr,
                },
                style: TextStyle(fontSize: 12.5, color: tone),
              ),
              if (controller.connectEmail.value != null) ...[
                const SizedBox(height: 4),
                Text(
                  controller.connectEmail.value!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: palette.textMuted,
                    fontFamily: kMonoFamily,
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 4),
                Text(
                  error,
                  style: TextStyle(fontSize: 12, color: palette.danger),
                ),
              ],
              if (url != null && status == 'pending') ...[
                const SizedBox(height: Insets.sm),
                SelectableText(
                  url,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: palette.textMuted,
                    fontFamily: kMonoFamily,
                  ),
                ),
                const SizedBox(height: Insets.sm),
                Text(
                  Messages.accountsConnectManual.tr,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: GlassTextField(
                        controller: _codeController,
                        icon: Icons.vpn_key_outlined,
                        monospace: true,
                        hint: '4/0A...',
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    AppButton(
                      label: Messages.accountsConnectSubmit.tr,
                      variant: AppButtonVariant.secondary,
                      onPressed: () => controller.submitCode(
                        controller.connectSessionId.value,
                        _codeController.text.trim(),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AccountsController>();
    final palette = context.palette;

    return GlassPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.sm,
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 17, color: palette.accent),
                  const SizedBox(width: 9),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Messages.accountsAutoSwitch.tr,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                        Text(
                          Messages.accountsAutoSwitchHint.tr,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Obx(
                () => GlassSwitch(
                  value: controller.autoSwitch.value,
                  onChanged: (value) => controller.autoSwitch.value = value,
                ),
              ),
              AppIconButton(
                icon: Icons.refresh_rounded,
                tooltip: Messages.commonRefresh.tr,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          const LuminousDivider(),
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton(
                label: Messages.accountsSelectAll.tr,
                icon: Icons.checklist_rounded,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.small,
                onPressed: controller.selectAll,
              ),
              AppButton(
                label: Messages.accountsAllTiers.tr,
                icon: Icons.filter_alt_outlined,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.small,
                onPressed: () {},
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    Messages.accountsMinimalMode.tr,
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Obx(
                    () => GlassSwitch(
                      value: controller.minimalMode.value,
                      width: 40,
                      height: 23,
                      onChanged: (value) =>
                          controller.minimalMode.value = value,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    Messages.accountsQuotaDisplay.tr,
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                  Obx(
                    () => AppSegmented<QuotaWindow>(
                      value: controller.quotaWindow.value,
                      dense: true,
                      options: [
                        SegmentOption(
                          label: Messages.accountsQuotaWindow5h.tr,
                          value: QuotaWindow.fiveHours,
                        ),
                        SegmentOption(
                          label: Messages.accountsQuotaWindowWeek.tr,
                          value: QuotaWindow.week,
                        ),
                        SegmentOption(
                          label: Messages.accountsQuotaWindowBoth.tr,
                          value: QuotaWindow.both,
                        ),
                      ],
                      onChanged: (value) =>
                          controller.quotaWindow.value = value,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountGallery extends StatelessWidget {
  const _AccountGallery({required this.accountCount});

  final int accountCount;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AccountsController>();

    return Obx(() {
      final accounts = controller.visibleAccounts;

      if (accounts.isEmpty) {
        return GlassPanel(child: _EmptyAccounts(controller: controller));
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              Messages.accountsPoolCount.tr.replaceAll('{n}', '$accountCount'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.palette.textMuted,
              ),
            ),
          ),
          ResponsiveCardGrid(
            itemHeight: 470,
            minCardWidth: 430,
            children: [
              for (final account in accounts)
                AccountCard(
                  account: account,
                  active: controller.activeAccountId.value == account.id,
                  selected: controller.selectedIds.contains(account.id),
                  minimalMode: controller.minimalMode.value,
                  onUse: () => controller.useAccount(account),
                  onToggleSelect: () => controller.toggleSelected(account.id),
                ),
            ],
          ),
        ],
      );
    });
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts({required this.controller});

  final AccountsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          Messages.accountsEmpty.tr,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          Messages.accountsEmptyMessage.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: 18),
        AppButton(
          label: Messages.accountsAddAccount.tr,
          icon: Icons.add_rounded,
          variant: AppButtonVariant.primary,
          onPressed: () {},
        ),
      ],
    );
  }
}
