import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// SE-41 T4b: platform contracts for the check-now push that host tests can
// read. The relay's --ios-alert mode sends only the two loc-keys; iOS draws
// the text from Runner's Localizable.strings, so all three languages must
// have both keys, with the owner-approved copy (SE-41 comment 01a130c5).

const _copy = {
  'en': (
    'Is Mknoon up to date?',
    'Older versions can lose their connection. Tap to open Mknoon and check.',
  ),
  'de': (
    'Ist Mknoon auf dem neuesten Stand?',
    'Ältere Versionen können die Verbindung verlieren. Tippe, um Mknoon zu '
        'öffnen und nachzusehen.',
  ),
  'ar': (
    'هل مكنون محدّث؟',
    'قد تفقد الإصدارات القديمة اتصالها. اضغط لفتح مكنون والتحقق.',
  ),
};

final _entry = RegExp(r'^"([A-Z_]+)" = "((?:[^"\\]|\\.)*)";$', multiLine: true);

Map<String, String> _strings(String language) {
  final text = File(
    'ios/Runner/$language.lproj/Localizable.strings',
  ).readAsStringSync();
  return {for (final m in _entry.allMatches(text)) m.group(1)!: m.group(2)!};
}

/// True when the first strong directional character is Arabic, so iOS lays
/// the alert out right to left.
bool _startsRtl(String value) {
  for (final rune in value.runes) {
    if (rune >= 0x0600 && rune <= 0x06FF) return true;
    final char = String.fromCharCode(rune);
    if (RegExp(r'[A-Za-z]').hasMatch(char)) return false;
  }
  return false;
}

void main() {
  test('both alert keys in all 3 .lproj files, with the approved copy', () {
    for (final MapEntry(key: language, value: (title, body)) in _copy.entries) {
      expect(_strings(language), {
        'UPDATE_CHECK_ALERT_TITLE': title,
        'UPDATE_CHECK_ALERT_BODY': body,
      }, reason: language);
    }
  });

  test('no format arguments (the push sends no loc-args)', () {
    for (final language in _copy.keys) {
      for (final value in _strings(language).values) {
        expect(value, isNot(contains('%')), reason: language);
      }
    }
  });

  test('the Arabic copy is right to left', () {
    final ar = _strings('ar');
    expect(_startsRtl(ar['UPDATE_CHECK_ALERT_TITLE']!), isTrue);
    expect(_startsRtl(ar['UPDATE_CHECK_ALERT_BODY']!), isTrue);
    expect(_startsRtl(_strings('en')['UPDATE_CHECK_ALERT_TITLE']!), isFalse);
  });

  test('Localizable.strings ships in the Runner bundle', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(
      project,
      contains('/* Localizable.strings in Resources */ = {isa = PBXBuildFile;'),
    );
    for (final language in _copy.keys) {
      expect(
        project,
        contains('path = $language.lproj/Localizable.strings;'),
        reason: language,
      );
    }
    final resources = RegExp(
      r'97C146EC1CF9000F007C117D /\* Resources \*/ = \{[^}]*\}',
    ).firstMatch(project)!.group(0)!;
    expect(resources, contains('Localizable.strings in Resources'));
  });

  test('iOS: the remote push goes to the update check before super', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final start = delegate.indexOf(
      'didReceiveRemoteNotification userInfo: [AnyHashable: Any],',
    );
    expect(start, greaterThan(0));
    final handled = delegate.indexOf(
      'updateCheckBackground.handleRemotePush(',
      start,
    );
    final superCall = delegate.indexOf(
      'didReceiveRemoteNotification: userInfo,',
      start,
    );
    expect(handled, greaterThan(start));
    expect(handled, lessThan(superCall));
  });

  test('both platforms use the same topic and payload type', () {
    final swift = File(
      'ios/Runner/UpdateCheckBackgroundTask.swift',
    ).readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/com/mknoon/app/UpdateCheckBackgroundWork.kt',
    ).readAsStringSync();
    expect(swift, contains('static let pushTopic = "update_check"'));
    expect(swift, contains('static let pushPayloadType = "update_check"'));
    expect(kotlin, contains('const val PUSH_TOPIC = "update_check"'));
    expect(kotlin, contains('const val PUSH_PAYLOAD_TYPE = "update_check"'));
  });
}
