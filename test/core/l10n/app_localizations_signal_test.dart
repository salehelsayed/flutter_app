import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('en/de/ar Signal label and description are exact', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final de = lookupAppLocalizations(const Locale('de'));
    final ar = lookupAppLocalizations(const Locale('ar'));

    expect(en.settings_background_daylight_lagoon, 'Signal');
    expect(
      en.settings_background_daylight_lagoon_desc,
      'A cool porcelain sky with one electric-violet star.',
    );
    expect(en.settings_background_daylight_lagoon_selected, 'Signal selected');

    expect(de.settings_background_daylight_lagoon, 'Signal');
    expect(
      de.settings_background_daylight_lagoon_desc,
      'Ein kühler Porzellanhimmel mit einem elektrisch-violetten Stern.',
    );
    expect(
      de.settings_background_daylight_lagoon_selected,
      'Signal ausgewählt',
    );

    expect(ar.settings_background_daylight_lagoon, 'سيجنال');
    expect(
      ar.settings_background_daylight_lagoon_desc,
      'سماء خزفية باردة بنجمة واحدة بنفسجية كهربائية.',
    );
    expect(ar.settings_background_daylight_lagoon_selected, 'تم اختيار سيجنال');
  });
}
