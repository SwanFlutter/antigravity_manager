import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../core/widgets/glass_panel.dart';
import '../modules/accounts/accounts_page.dart';
import '../modules/api_proxy/api_proxy_page.dart';
import '../modules/playground/playground_page.dart';
import '../modules/settings/settings_page.dart';
import '../modules/traffic/traffic_page.dart';
import '../modules/workspaces/workspaces_page.dart';
import 'controller/app_controller.dart';
import 'controller/theme_controller.dart';
import 'widgets/app_sidebar.dart';

/// An [IndexedStack] that only builds children once they have been visited.
///
/// A plain IndexedStack keeps every child laid out from frame one, so a theme
/// switch re-resolved text layouts for pages the user never opened — the single
/// most expensive step of the mode flip. Children stay alive after their first
/// visit, preserving state exactly like the eager version.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  final Set<int> _visited = <int>{};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _visited.contains(i) ? widget.children[i] : const SizedBox.shrink(),
      ],
    );
  }
}

/// The application frame: fixed navigation rail plus the active page.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const List<String> _rtlLanguages = ['fa', 'ar', 'he', 'ps', 'ur'];

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AppController>();
    final theme = Get.find<ThemeController>();

    return Scaffold(
      body: AmbientBackground(
        child: Obx(() {
          final isRtl = _rtlLanguages.contains(
            theme.locale.value.languageCode,
          );

          return Directionality(
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSidebar(),
                Expanded(
                  child: ClipRect(
                    child: LazyIndexedStack(
                      index: controller.currentIndex.value,
                      children: const [
                        AccountsPage(),
                        WorkspacesPage(),
                        ApiProxyPage(),
                        PlaygroundPage(),
                        TrafficPage(),
                        SettingsPage(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
