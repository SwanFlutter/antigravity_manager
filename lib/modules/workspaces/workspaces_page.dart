import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../I18n/messages.dart';
import '../../core/data/mock_data.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_field.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/status_badge.dart';
import 'workspaces_controller.dart';

class WorkspacesPage extends ReactiveGetView<WorkspacesController> {
  const WorkspacesPage({super.key});

  @override
  Widget buildReactive(BuildContext context) {
    final controller = Get.find<WorkspacesController>();

    // Read once here so the page level observer follows the workspace list.
    final workspaceCount = controller.workspaces.length;

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
            icon: Icons.hub_outlined,
            title: Messages.workspacesTitle.tr,
            description: Messages.workspacesDesc.tr,
            actions: [
              AppButton(
                label: Messages.workspacesNew.tr,
                icon: Icons.add_rounded,
                variant: AppButtonVariant.primary,
                onPressed: () {},
              ),
            ],
          ),
          Row(
            children: [
              GlassSearchField(
                controller: controller.searchController,
                hint: Messages.workspacesSearch.tr,
                width: 420,
                onChanged: (value) => controller.query.value = value,
              ),
              const Spacer(),
              Obx(
                () => Text(
                  '$workspaceCount / ${controller.workspaces.length}  •  ${controller.runningCount} ${Messages.commonRunning.tr.toLowerCase()}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Obx(() {
            final workspaces = controller.visibleWorkspaces;
            if (workspaces.isEmpty) {
              return GlassPanel(
                child: EmptyState(
                  icon: Icons.folder_open_outlined,
                  title: Messages.workspacesEmpty.tr,
                  message: Messages.workspacesEmptyMessage.tr,
                  action: AppButton(
                    label: Messages.workspacesNew.tr,
                    icon: Icons.add_rounded,
                    variant: AppButtonVariant.primary,
                    onPressed: () {},
                  ),
                ),
              );
            }

            return Wrap(
              spacing: Insets.md,
              runSpacing: Insets.md,
              children: [
                for (final workspace in workspaces)
                  SizedBox(
                    width: 470,
                    child: _WorkspaceCard(
                      workspace: workspace,
                      onLaunch: () => controller.launch(workspace),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({required this.workspace, required this.onLaunch});

  final Workspace workspace;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final running = workspace.state == WorkspaceState.running;

    final (BadgeTone tone, String label) = switch (workspace.state) {
      WorkspaceState.running => (BadgeTone.success, Messages.commonRunning.tr),
      WorkspaceState.idle => (BadgeTone.neutral, Messages.commonStopped.tr),
      WorkspaceState.stopped => (BadgeTone.warning, Messages.commonStopped.tr),
    };

    return GlassPanel(
      radius: Radii.lg,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 14, 14),
            child: Row(
              children: [
                MonogramAvatar(
                  text: workspace.name,
                  size: 40,
                  tone: workspace.unbound ? BadgeTone.warning : BadgeTone.accent,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workspace.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${Messages.workspacesLastActive.tr}: ${workspace.lastActive}',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AppBadge(label: label, tone: tone, dot: true),
              ],
            ),
          ),
          const LuminousDivider(),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GroupLabel(Messages.workspacesBoundAccount.tr),
                const SizedBox(height: 10),
                GlassInset(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      MonogramAvatar(
                        text: workspace.accountName,
                        size: 30,
                        tone: workspace.unbound
                            ? BadgeTone.warning
                            : BadgeTone.accent,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              workspace.accountName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: palette.textPrimary,
                              ),
                            ),
                            Text(
                              workspace.plan,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (workspace.unbound)
                        AppBadge(
                          label: Messages.workspacesUnbound.tr,
                          tone: BadgeTone.warning,
                        )
                      else
                        AppBadge(label: workspace.plan, tone: BadgeTone.info),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GroupLabel(Messages.workspacesProjectFolder.tr),
                const SizedBox(height: 10),
                _PathRow(
                  icon: Icons.folder_outlined,
                  text: workspace.projectFolder,
                ),
                const SizedBox(height: 8),
                _PathRow(
                  icon: Icons.shield_outlined,
                  text: workspace.profileFolder,
                  muted: true,
                ),
              ],
            ),
          ),
          const LuminousDivider(),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
            child: Row(
              children: [
                AppButton(
                  label: Messages.workspacesLaunch.tr,
                  icon: running
                      ? Icons.stop_circle_outlined
                      : Icons.play_arrow_rounded,
                  variant: running
                      ? AppButtonVariant.secondary
                      : AppButtonVariant.primary,
                  onPressed: onLaunch,
                ),
                const Spacer(),
                AppIconButton(
                  icon: Icons.folder_open_outlined,
                  tooltip: Messages.workspacesOpenFolder.tr,
                  onPressed: () {},
                ),
                const SizedBox(width: 6),
                AppOverflowMenu<String>(
                  items: [
                    AppMenuEntry(
                      label: Messages.workspacesRevealProfile.tr,
                      value: 'profile',
                      icon: Icons.folder_outlined,
                    ),
                    AppMenuEntry(
                      label: Messages.workspacesDetach.tr,
                      value: 'detach',
                      icon: Icons.link_off_rounded,
                    ),
                    AppMenuEntry(
                      label: Messages.commonRename.tr,
                      value: 'rename',
                      icon: Icons.edit_outlined,
                    ),
                    AppMenuEntry(
                      label: Messages.commonDelete.tr,
                      value: 'delete',
                      icon: Icons.delete_outline_rounded,
                      destructive: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({required this.icon, required this.text, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.glassStrong,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: palette.glassBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: palette.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: muted ? palette.textMuted : palette.textSecondary,
                fontFamily: kMonoFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
