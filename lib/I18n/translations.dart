import 'package:get_x_master/get_x_master.dart';

import 'ar.dart';
import 'de.dart';
import 'en.dart';
import 'fa.dart';
import 'fr.dart';
import 'zh.dart';

abstract class AppTranslationsKeys {
  Map<String, String> get keys;
}

/// Every supported interface language.
///
/// English is the default. Persian and Arabic are right to left, which the
/// app framework handles through the locale of the active route.
class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en_US': English().keys,
    'fa_IR': Farsi().keys,
    'ar_SA': Arabic().keys,
    'de_DE': German().keys,
    'fr_FR': French().keys,
    'zh_CN': Chinese().keys,
  };

  /// Native names shown in the language picker.
  static const Map<String, String> languageNames = {
    'en_US': 'English',
    'fa_IR': 'فارسی',
    'ar_SA': 'العربية',
    'de_DE': 'Deutsch',
    'fr_FR': 'Français',
    'zh_CN': '中文',
  };

  static const List<String> supportedLocales = [
    'en_US',
    'fa_IR',
    'ar_SA',
    'de_DE',
    'fr_FR',
    'zh_CN',
  ];
}
