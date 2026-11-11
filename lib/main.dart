import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';
import 'package:get_x_storage/get_x_storage.dart';

import 'I18n/translations.dart';
import 'app/app_shell.dart';
import 'app/bindings/app_binding.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetXStorage.init();

  // این خط برای رفع خطای LocaleDataException اضافه شد
  //  await initializeDateFormatting('fa_IR', null);

  runApp(const AntigravityApp());
}

class AntigravityApp extends StatelessWidget {
  const AntigravityApp({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = GetXStorage();
    final savedTheme = storage.read<String>(key: 'settings.theme_mode');
    final initialTheme = savedTheme == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
    return GetMaterialApp(
      title: 'AntigravityManager',
      debugShowCheckedModeBanner: false,
      textDirection: TextDirection.rtl,
      locale: const Locale('en', 'US'),
      fallbackLocale: const Locale('en', 'US'),
      translations: AppTranslations(),
      initialBinding: AppBinding(),
      defaultTransition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 700),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: initialTheme,
      home: const AppShell(),
    );
  }
}
