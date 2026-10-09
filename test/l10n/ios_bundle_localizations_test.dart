import 'dart:io';

import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Beta O12 h (2026-10-09): without CFBundleLocalizations iOS treats the app as
// English-only, so Settings offers no per-app language and an iPhone user
// cannot run Mknoon in Arabic unless the whole phone is in Arabic.
void main() {
  test('iOS Info.plist declares every supported app language', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final block = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(block, isNotNull, reason: 'CFBundleLocalizations is missing');
    final declared = RegExp(
      r'<string>([^<]+)</string>',
    ).allMatches(block!.group(1)!).map((m) => m.group(1)).toSet();
    final supported = AppLocalizations.supportedLocales
        .map((locale) => locale.languageCode)
        .toSet();
    expect(declared, supported);
  });
}
