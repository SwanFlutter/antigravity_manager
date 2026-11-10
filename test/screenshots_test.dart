// Renders every page of the shell to PNG files under test/goldens.
//
// Run with: flutter test --update-goldens test/screenshots_test.dart

import 'dart:io';

import 'package:antigravity_manager/app/controller/api_proxy_controller.dart';
import 'package:antigravity_manager/app/controller/app_controller.dart';
import 'package:antigravity_manager/app/controller/theme_controller.dart';
import 'package:antigravity_manager/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_x_master/get_x_master.dart';

/// Loads the real Windows typefaces so the golden files show readable text
/// instead of the placeholder glyphs the test renderer uses by default.
Future<void> _loadRealFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final path = File('C:/Windows/Fonts/$file');
      if (!path.existsSync()) continue;
      loader.addFont(
        path.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
      );
    }
    await loader.load();
  }

  await load('Segoe UI', [
    'segoeui.ttf',
    'segoeuib.ttf',
    'segoeuii.ttf',
    'segoeuiz.ttf',
    'seguisb.ttf',
  ]);
  await load('Consolas', ['consola.ttf', 'consolab.ttf']);

  // The Material icon font ships with the Flutter SDK cache.
  final materialIcons = File(
    'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (materialIcons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(
        materialIcons.readAsBytes().then(
          (bytes) => ByteData.view(bytes.buffer),
        ),
      );
    await loader.load();
  }
}

void main() {
  setUpAll(_loadRealFonts);

  setUp(() {
    Get.testMode = true;
    Get.put(AppController(), permanent: true);
    Get.put(ThemeController(), permanent: true);
  });

  tearDown(Get.reset);

  Future<void> shoot(WidgetTester tester, int index, String name) async {
    final controller = Get.find<AppController>();
    controller.currentIndex.value = index;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(AntigravityApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('dark theme pages', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1680, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Get.find<ThemeController>().setDarkMode();

    await tester.pumpWidget(const AntigravityApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await shoot(tester, 0, 'accounts_dark');
    await shoot(tester, 1, 'workspaces_dark');
    await shoot(tester, 2, 'api_proxy_dark');
    await shoot(tester, 3, 'playground_dark');
    await shoot(tester, 4, 'traffic_dark');
    await shoot(tester, 5, 'settings_dark');
  });

  testWidgets('api proxy examples', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1680, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = Get.find<AppController>();
    Get.find<ThemeController>().setDarkMode();

    await tester.pumpWidget(const AntigravityApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    controller.currentIndex.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final proxy = Get.find<ApiProxyController>();
    proxy.tab.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(AntigravityApp),
      matchesGoldenFile('goldens/api_proxy_examples_dark.png'),
    );
  });

  testWidgets('the gateway tab', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1680, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = Get.find<AppController>();
    Get.find<ThemeController>().setDarkMode();

    await tester.pumpWidget(const AntigravityApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    controller.currentIndex.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final proxy = Get.find<ApiProxyController>();
    proxy.tab.value = 3;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(AntigravityApp),
      matchesGoldenFile('goldens/api_proxy_gateway_dark.png'),
    );
  });

  testWidgets('light theme pages', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1680, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Get.find<ThemeController>().setLightMode();

    await tester.pumpWidget(const AntigravityApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await shoot(tester, 0, 'accounts_light');
    await shoot(tester, 5, 'settings_light');
  });

  testWidgets('persian right to left', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1680, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final theme = Get.find<ThemeController>();
    theme.setDarkMode();
    theme.setLocale(const Locale('fa', 'IR'));

    await tester.pumpWidget(const AntigravityApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // GetMaterialApp.initState resets Get.locale to main.dart's fixed en_US
    // at mount; restore fa_IR afterwards so .tr resolves Persian translations.
    theme.setLocale(const Locale('fa', 'IR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await shoot(tester, 0, 'accounts_fa_rtl');
  });
}
