import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';
import 'package:get_x_storage/get_x_storage.dart';

/// Owns the app's theme mode and locale.
///
/// The mode is applied exclusively through get_x_master:
/// [GetMaterialApp] renders from the root controller and
/// [Get.changeThemeMode] updates it, so the whole MaterialApp re-themes with
/// no `forceAppUpdate` / widget-tree teardown.
class ThemeController extends GetXController {
  static ThemeController get to => Get.find();

  final _storage = GetXStorage();
  final Rx<ThemeMode> themeMode = ThemeMode.light.obs;
  final Rx<Locale> locale = const Locale('en', 'US').obs;

  bool get isDarkMode => themeMode.value == ThemeMode.dark;

  /// Must match the key main.dart reads for the initial theme.
  static const String themeKey = 'settings.theme_mode';

  @override
  void onInit() {
    super.onInit();
    _loadTheme();
  }

  void _loadTheme() {
    final savedTheme = _storage.read<String>(key: themeKey);
    themeMode.value = savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  void _applyMode(ThemeMode mode) {
    if (themeMode.value == mode) return;
    themeMode.value = mode;
    _storage.write(key: themeKey, value: mode == ThemeMode.dark ? 'dark' : 'light');
    Get.changeThemeMode(mode);
  }

  void toggleTheme() {
    _applyMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }

  void setLightMode() => _applyMode(ThemeMode.light);

  void setDarkMode() => _applyMode(ThemeMode.dark);

  void setLocale(Locale value) {
    if (locale.value == value) return;
    locale.value = value;
    Get.updateLocale(value);
  }
}
