import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../I18n/messages.dart';
import '../../I18n/translations.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hover_builder.dart';
import '../../core/widgets/status_badge.dart';
import '../controller/app_controller.dart';
import '../controller/theme_controller.dart';
import 'app_logo.dart';

class _NavItem {
  const _NavItem(this.index, this.icon, this.labelKey);

  final int index;
  final IconData icon;
  final String labelKey;
}

const List<_NavItem> _navItems = [
  _NavItem(0, Icons.grid_view_rounded, Messages.navAccounts),
  _NavItem(1, Icons.hub_outlined, Messages.navWorkspaces),
  _NavItem(2, Icons.route_outlined, Messages.navApiProxy),
  _NavItem(3, Icons.science_outlined, Messages.navPlayground),
  _NavItem(4, Icons.insights_outlined, Messages.navTraffic),
  _NavItem(5, Icons.tune_rounded, Messages.navSettings),
];

/// The fixed navigation rail of the application.
class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AppController>();

    return Obx(() {
      final collapsed = controller.sidebarCollapsed.value;
      final palette = context.palette;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: collapsed ? 76 : Insets.sidebarWidth,
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.72),
          border: Border(right: BorderSide(color: palette.glassBorder)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(collapsed: collapsed),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 14 : 12,
                  vertical: 4,
                ),
                children: [
                  for (final item in _navItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _NavTile(
                        item: item,
                        collapsed: collapsed,
                        selected: controller.currentIndex.value == item.index,
                        onTap: () => controller.goTo(item.index),
                      ),
                    ),
                ],
              ),
            ),
            const _SidebarDivider(),
            _ServicesBlock(collapsed: collapsed),
            const _SidebarDivider(),
            _CollapseTile(collapsed: collapsed),
            const SizedBox(height: 10),
          ],
        ),
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    final palette = context.palette;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        collapsed ? 18 : 16,
        18,
        collapsed ? 18 : 12,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppLogo(size: 38),
              if (!collapsed) ...[
                const Spacer(),
                Obx(
                  () => AppIconButton(
                    icon: theme.isDarkMode
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    tooltip: theme.isDarkMode
                        ? Messages.settingsThemeLight
                        : Messages.settingsThemeDark,
                    size: 32,
                    iconSize: 16,
                    onPressed: theme.toggleTheme,
                  ),
                ),
                const SizedBox(width: 6),
                const _LanguageMenu(),
              ],
            ],
          ),
          if (!collapsed) ...[
            const SizedBox(height: 14),
            Text(
              'Antigravity',
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.1,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Manager',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.1,
                color: palette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu();

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    final palette = context.palette;

    return PopupMenuButton<String>(
      tooltip: Messages.settingsLanguage,
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.translate_rounded,
        size: 16,
        color: palette.textSecondary,
      ),
      onSelected: (value) {
        final parts = value.split('_');
        theme.setLocale(Locale(parts.first, parts.last));
      },
      itemBuilder: (context) => AppTranslations.supportedLocales
          .map(
            (code) => PopupMenuItem<String>(
              value: code,
              height: 38,
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: code == theme.locale.value.languageCode
                        ? Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: palette.accent,
                          )
                        : null,
                  ),
                  Text(
                    AppTranslations.languageNames[code] ?? code,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: palette.textPrimary,
                      fontWeight: code == theme.locale.value.languageCode
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.collapsed,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool collapsed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = item.labelKey.tr;

    return HoverBuilder(
      onTap: onTap,
      builder: (context, hovered, focused) {
        return Tooltip(
          message: collapsed ? label : '',
          waitDuration: const Duration(milliseconds: 500),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            decoration: BoxDecoration(
              color: selected
                  ? palette.accent.withValues(alpha: 0.16)
                  : (hovered ? palette.glassStrong : Colors.transparent),
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: selected
                    ? palette.accent.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (selected && !collapsed)
                  Container(
                    width: 3,
                    height: 20,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(Radii.pill),
                      boxShadow: [
                        BoxShadow(
                          color: palette.accent.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                Icon(
                  item.icon,
                  size: 19,
                  color: selected
                      ? palette.accentStrong
                      : palette.textSecondary,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected
                            ? palette.textPrimary
                            : palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ServicesBlock extends StatelessWidget {
  const _ServicesBlock({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AppController>();
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 14 : 16,
        vertical: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!collapsed) ...[
            Row(
              children: [
                Icon(
                  Icons.monitor_heart_outlined,
                  size: 14,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    Messages.sidebarServices.tr,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: kLabelTracking,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          for (final service in controller.services)
            Padding(
              padding: EdgeInsets.only(bottom: collapsed ? 8 : 10),
              child: collapsed
                  ? _ServiceDot(running: service.running, tooltip: service.name)
                  : _ServiceRow(
                      name: service.name,
                      running: service.running,
                      onToggle: service.name.contains('Proxy')
                          ? controller.toggleProxy
                          : controller.toggleManager,
                    ),
            ),
          if (!collapsed)
            Text(
              Messages.sidebarServicesRunning.tr
                  .replaceAll('{n}', '${controller.runningServiceCount}')
                  .replaceAll('{m}', '${controller.services.length}'),
              style: TextStyle(fontSize: 11, color: palette.textMuted),
            ),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.name,
    required this.running,
    required this.onToggle,
  });

  final String name;
  final bool running;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        StatusDot(
          color: running ? palette.success : palette.danger,
          size: 7,
          pulse: running,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: palette.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        HoverBuilder(
          onTap: onToggle,
          builder: (context, hovered, focused) {
            final color = running ? palette.danger : palette.success;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: hovered ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(Radii.xs),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Text(
                running ? Messages.sidebarStop.tr : Messages.sidebarStart.tr,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ServiceDot extends StatelessWidget {
  const _ServiceDot({required this.running, required this.tooltip});

  final bool running;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: StatusDot(
        color: running ? palette.success : palette.danger,
        size: 9,
        pulse: running,
      ),
    );
  }
}

class _CollapseTile extends StatelessWidget {
  const _CollapseTile({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AppController>();
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 14 : 12),
      child: HoverBuilder(
        onTap: controller.toggleSidebar,
        builder: (context, hovered, focused) {
          return Container(
            height: 38,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            decoration: BoxDecoration(
              color: hovered ? palette.glassStrong : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  collapsed
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_left_rounded,
                  size: 17,
                  color: palette.textMuted,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      Messages.sidebarCollapse.tr,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LuminousDivider(),
    );
  }
}
