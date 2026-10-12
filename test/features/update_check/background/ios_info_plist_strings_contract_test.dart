import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The localized iOS permission prompts (ios/Runner/*.lproj/InfoPlist.strings)
// must ship in the Runner bundle, use only real Info.plist usage keys, and
// English must stay identical to Info.plist.

const _languages = ['en', 'de', 'ar'];

const _usageKeys = {
  'NSCameraUsageDescription',
  'NSLocalNetworkUsageDescription',
  'NSLocationAlwaysAndWhenInUseUsageDescription',
  'NSLocationWhenInUseUsageDescription',
  'NSMicrophoneUsageDescription',
  'NSPhotoLibraryAddUsageDescription',
  'NSPhotoLibraryUsageDescription',
};

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
  test('each language has exactly the 7 Info.plist usage keys', () {
    expect(_usageDescriptions().keys.toSet(), _usageKeys);
    for (final language in _languages) {
      final strings = _strings(language);
      expect(strings.keys.toSet(), _usageKeys, reason: language);
      for (final MapEntry(:key, :value) in strings.entries) {
        expect(value.trim(), isNotEmpty, reason: '$language $key');
      }
    }
  });

  test('the Arabic prompts are Arabic', () {
    for (final MapEntry(:key, :value) in _strings('ar').entries) {
      expect(RegExp('[\u0600-\u06FF]').hasMatch(value), isTrue, reason: key);
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
