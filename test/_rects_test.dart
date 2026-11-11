import 'package:antigravity_manager/app/controller/app_controller.dart';
import 'package:antigravity_manager/app/controller/theme_controller.dart';
import 'package:antigravity_manager/core/widgets/app_button.dart';
import 'package:antigravity_manager/core/widgets/glass_panel.dart';
import 'package:antigravity_manager/core/widgets/page_header.dart';
import 'package:antigravity_manager/main.dart';
import 'package:antigravity_manager/modules/accounts/accounts_page.dart';
import 'package:antigravity_manager/modules/accounts/widgets/account_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_x_master/get_x_master.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(AppController(), permanent: true);
    Get.put(ThemeController(), permanent: true);
  });
  tearDown(Get.reset);

  testWidgets('dump accounts page structure', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1264, 681);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Get.find<ThemeController>().setDarkMode();
    await tester.pumpWidget(const AntigravityApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final controller = Get.find<AppController>();
    controller.currentIndex.value = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    void dump(String tag, Finder finder) {
      for (final element in finder.evaluate()) {
        final box = element.renderObject;
        if (box is! RenderBox || !box.hasSize) continue;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        debugPrint('$tag  x=${rect.left.round()} y=${rect.top.round()} '
            'w=${rect.width.round()} h=${rect.height.round()}');
      }
    }

    dump('PAGEHEADER', find.byType(PageHeader));
    dump('ACCOUNTSPAGE', find.byType(AccountsPage));
    dump('SCROLLVIEW', find.byType(SingleChildScrollView).first);
    dump('ACCOUNTCARD', find.byType(AccountCard));
    dump('GLASSPANEL', find.byType(GlassPanel));
    for (final element in find.byType(AppButton).evaluate()) {
      final widget = element.widget as AppButton;
      final box = element.renderObject;
      if (box is! RenderBox || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      debugPrint('BUTTON "${widget.label}" '
          'x=${rect.left.round()} y=${rect.top.round()} '
          'w=${rect.width.round()} h=${rect.height.round()}');
    }
  });
}
