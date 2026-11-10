import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../../I18n/messages.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/quota_meter.dart';
import '../../../core/widgets/status_badge.dart';

/// One oversized account card.
///
/// The card is intentionally tall: the quota list is the part of the product
/// people actually read, so it keeps its own scroll instead of being shrunk
/// to fit the viewport.
class AccountCard extends StatefulWidget {
  const AccountCard({
    super.key,
    required this.account,
    required this.active,
    required this.selected,
    required this.onUse,
    required this.onToggleSelect,
    required this.minimalMode,
  });

  final Account account;
  final bool active;
  final bool selected;
  final VoidCallback onUse;
  final VoidCallback onToggleSelect;
  final bool minimalMode;

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  BadgeTone get _statusTone => switch (widget.account.status) {
        AccountStatus.active => BadgeTone.success,
        AccountStatus.idle => BadgeTone.neutral,
        AccountStatus.rateLimited => BadgeTone.warning,
        AccountStatus.error => BadgeTone.danger,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final account = widget.account;

    final families = ModelFamily.values
        .where((family) => account.quotasOf(family).isNotEmpty)
        .toList();

    return GlassPanel(
      radius: Radii.xl,
      padding: EdgeInsets.zero,
      borderTint: widget.active
          ? palette.accent.withValues(alpha: 0.55)
          : palette.glassBorderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(22, 20, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 24,
                      child: Checkbox(
                        value: widget.selected,
                        onChanged: (_) => widget.onToggleSelect(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 12),
                    MonogramAvatar(
                      text: account.name,
                      size: 46,
                      tone: widget.active ? BadgeTone.accent : _statusTone,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            account.handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AppBadge(
                          label: account.status.label,
                          tone: _statusTone,
                          dot: true,
                        ),
                        const SizedBox(height: 7),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.active
                                  ? Icons.bolt_rounded
                                  : Icons.pause_circle_outline_rounded,
                              size: 13,
                              color: widget.active
                                  ? palette.accentStrong
                                  : palette.textMuted,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              widget.active
                                      ? Messages.accountsInUse.tr
                                      : Messages.accountsNotInUse.tr,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: widget.active
                                    ? palette.accentStrong
                                    : palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppBadge(label: account.provider.toUpperCase()),
                    AppBadge(label: account.plan, tone: BadgeTone.info),
                    if (account.demo)
                      AppBadge(
                        label: Messages.accountsSample.tr,
                        tone: BadgeTone.neutral,
                        icon: Icons.science_outlined,
                      ),
                    if (account.recommended)
                      AppBadge(
                        label: Messages.accountsRecommendedNext.tr,
                        tone: BadgeTone.accent,
                        icon: Icons.auto_awesome_rounded,
                      ),
                    AppBadge(
                      label: Messages.accountsCredits.tr.replaceAll('{n}', '${account.credits}'),
                      tone: BadgeTone.neutral,
                      icon: Icons.toll_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: Messages.accountsUse.tr,
                        icon: Icons.power_settings_new_rounded,
                        variant: widget.active
                            ? AppButtonVariant.primary
                            : AppButtonVariant.secondary,
                        onPressed: () => widget.onUse(),
                        expand: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppIconButton(
                      icon: Icons.expand_more_rounded,
                      tooltip: Messages.accountsMoreActions.tr,
                      onPressed: () {},
                    ),
                    const SizedBox(width: 6),
                    AppOverflowMenu<String>(
                      items: [
                        AppMenuEntry(
                          label: Messages.accountsOpenInPlayground.tr,
                          value: 'playground',
                          icon: Icons.science_outlined,
                        ),
                        AppMenuEntry(
                          label: Messages.accountsRefreshQuota.tr,
                          value: 'refresh',
                          icon: Icons.refresh_rounded,
                        ),
                        AppMenuEntry(
                          label: Messages.accountsCopyAccountId.tr,
                          value: 'copy',
                          icon: Icons.copy_rounded,
                        ),
                        AppMenuEntry(
                          label: Messages.accountsRemoveAccount.tr,
                          value: 'remove',
                          icon: Icons.delete_outline_rounded,
                          destructive: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const LuminousDivider(),
          Expanded(
            child: widget.minimalMode
                ? _MinimalBody(account: account)
                : _QuotaBody(
                    account: account,
                    families: families,
                    scrollController: _scrollController,
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuotaBody extends StatelessWidget {
  const _QuotaBody({
    required this.account,
    required this.families,
    required this.scrollController,
  });

  final Account account;
  final List<ModelFamily> families;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scrollbar(
      controller: scrollController,
      thumbVisibility: true,
      trackVisibility: false,
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsetsDirectional.fromSTEB(22, 18, 14, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WeeklyQuotaSection(account: account),
            const SizedBox(height: 6),
            const LuminousDivider(),
            const SizedBox(height: 18),
            for (final family in families) ...[
              Row(
                children: [
                  Icon(family.icon, size: 14, color: palette.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    family.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: kLabelTracking,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (final quota in account.quotasOf(family))
                QuotaRow(
                  model: quota.name,
                  remaining: quota.remaining,
                  resetLabel: Messages.accountsReset
                      .tr
                      .replaceAll('{t}', quota.resetLabel),
                ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// The weekly allowance of an account, one block per model group.
class _WeeklyQuotaSection extends StatelessWidget {
  const _WeeklyQuotaSection({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final quotas = account.weeklyQuotas;

    if (quotas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.calendar_month_rounded,
              size: 14,
              color: palette.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              Messages.accountsWeeklyQuota.tr.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: kLabelTracking,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final quota in quotas)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _WeeklyQuotaRow(
              title: _groupTitle(quota.groupId),
              remaining: quota.remaining,
              resetLabel: Messages.accountsReset.tr.replaceAll(
                '{t}',
                quota.resetLabel,
              ),
            ),
          ),
      ],
    );
  }

  String _groupTitle(String groupId) {
    return switch (groupId) {
      'gemini' => Messages.accountsGroupGemini.tr,
      'claudeGpt' => Messages.accountsGroupClaudeGpt.tr,
      _ => groupId,
    };
  }
}

/// One weekly allowance: title, remaining share, meter and reset time.
class _WeeklyQuotaRow extends StatelessWidget {
  const _WeeklyQuotaRow({
    required this.title,
    required this.remaining,
    required this.resetLabel,
  });

  final String title;
  final double remaining;
  final String resetLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final percent = (remaining * 100).round();
    final used = 100 - percent;

    final tone = remaining <= 0.001
        ? palette.textMuted
        : remaining < 0.2
            ? palette.danger
            : remaining < 0.5
                ? palette.warning
                : palette.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '$percent%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: kMonoFamily,
                  color: tone,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          Messages.accountsWeeklyRemaining.tr,
          style: TextStyle(fontSize: 12, color: palette.textMuted),
        ),
        const SizedBox(height: 7),
        SegmentedQuotaMeter(remaining: remaining, segments: 20),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: Text(
                Messages.accountsWeeklyUsed.tr.replaceAll('{n}', '$used'),
                style: TextStyle(fontSize: 11.5, color: palette.textMuted),
              ),
            ),
            Text(
              resetLabel,
              style: TextStyle(
                fontSize: 11.5,
                color: palette.textMuted,
                fontFamily: kMonoFamily,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MinimalBody extends StatelessWidget {
  const _MinimalBody({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final remaining = account.globalRemaining;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Messages.accountsQuotaSummary.tr,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${(remaining * 100).round()}%',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: QuotaBar(remaining: remaining, height: 8),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            Messages.accountsMinimalHint.tr,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
