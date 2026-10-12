import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The localized iOS permission prompts (ios/Runner/*.lproj/InfoPlist.strings)
// must ship in the Runner bundle, use only real Info.plist usage keys, and
// English must stay identical to Info.plist.

const _languages = ['en', 'de', 'ar'];

final _entry = RegExp(
  r'^"?([A-Za-z]+)"? = "((?:[^"\\]|\\.)*)";$',
  multiLine: true,
);

Map<String, String> _strings(String language) => {
  for (final m in _entry.allMatches(
    File('ios/Runner/$language.lproj/InfoPlist.strings').readAsStringSync(),
  ))
    m.group(1)!: m.group(2)!.replaceAll(r'\"', '"').replaceAll(r'\\', r'\'),
};

Map<String, String> _usageDescriptions() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final pair = RegExp(
    r'<key>(NS[A-Za-z]+UsageDescription)</key>\s*<string>([^<]*)</string>',
  );
  return {
    for (final m in pair.allMatches(plist))
      m.group(1)!: m
          .group(2)!
          .replaceAll('&apos;', "'")
          .replaceAll('&quot;', '"')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&'),
  };
}

void main() {
  test('every key is a usage description in Info.plist', () {
    final usage = _usageDescriptions().keys.toSet();
    expect(usage, isNotEmpty);
    for (final language in _languages) {
      final keys = _strings(language).keys.toSet();
      expect(keys, isNotEmpty, reason: language);
      expect(keys.difference(usage), isEmpty, reason: language);
    }
  });

  test('English is identical to Info.plist', () {
    expect(_strings('en'), _usageDescriptions());
  });

  test('InfoPlist.strings ships in the Runner Resources phase', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(
      project,
      contains('/* InfoPlist.strings in Resources */ = {isa = PBXBuildFile;'),
    );
    for (final language in _languages) {
      expect(
        project,
        contains('path = $language.lproj/InfoPlist.strings;'),
        reason: language,
      );
    }
    final resources = RegExp(
      r'97C146EC1CF9000F007C117D /\* Resources \*/ = \{[^}]*\}',
    ).firstMatch(project)!.group(0)!;
    expect(resources, contains('InfoPlist.strings in Resources'));
  });
}
