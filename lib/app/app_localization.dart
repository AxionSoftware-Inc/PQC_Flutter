import 'package:flutter/widgets.dart';

enum AppLanguagePreference { uzbek, english }

extension AntiQLocalization on BuildContext {
  bool get usesUzbek => Localizations.maybeLocaleOf(this)?.languageCode != 'en';

  String antiQText({required String uz, required String en}) {
    return usesUzbek ? uz : en;
  }
}
