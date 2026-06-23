import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/l10n/app_localizations_ar.dart';
import 'package:flutter_app/l10n/app_localizations_de.dart';
import 'package:flutter_app/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

/// 134-P8 TC-34 — feed-specific l10n parity.
///
/// Scoped to the feed redesign: it locks the NEW feed keys into every locale's
/// generated `AppLocalizations` API AND the underlying ARB files, and asserts
/// the OLD (now-removed) feed keys are gone from every ARB. Cross-locale parity
/// for the WHOLE app stays the responsibility of
/// `test/l10n/l10n_integrity_test.dart`; this test only guards feed copy.
void main() {
  // The feed keys introduced by the 134 redesign (P5/P6/P7 + P8 l10n pass).
  // Every one MUST exist in en/ar/de.
  const newFeedKeys = <String>[
    'feed_all_caught_up',
    'feed_reply_to_name',
    'feed_message_name',
    'feed_add_another',
    'feed_removed_undo',
    'feed_open_full_conversation',
    'feed_tap_to_say_hi',
    'feed_connected',
  ];

  // Old per-card / partition / quote feed copy removed in the 134 redesign.
  // These keys MUST be absent from every ARB now that their widgets are gone.
  const removedFeedKeys = <String>[
    'feed_you_replied',
    'feed_previously_seen',
    'feed_view_earlier_messages',
  ];

  Map<String, Object?> loadArb(String locale) {
    final file = File('lib/l10n/app_$locale.arb');
    return (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
        .cast<String, Object?>();
  }

  group('feed strings parity (TC-34)', () {
    test('new feed keys exist in every ARB locale', () {
      for (final locale in const ['en', 'ar', 'de']) {
        final bundle = loadArb(locale);
        for (final key in newFeedKeys) {
          expect(
            bundle.containsKey(key),
            isTrue,
            reason: '$locale ARB is missing new feed key "$key"',
          );
          expect(
            (bundle[key] as String?)?.trim().isNotEmpty ?? false,
            isTrue,
            reason: '$locale:$key is empty',
          );
        }
      }
    });

    test('new feed keys are reachable through the generated API', () {
      // Instantiating each generated locale proves the key set compiled into
      // the AppLocalizations surface for en/ar/de (a missing key would not
      // generate a getter and this file would not compile).
      for (final l10n in [
        AppLocalizationsEn(),
        AppLocalizationsAr(),
        AppLocalizationsDe(),
      ]) {
        expect(l10n.feed_all_caught_up.trim(), isNotEmpty);
        expect(l10n.feed_reply_to_name('Ann').trim(), isNotEmpty);
        expect(l10n.feed_message_name('Ann').trim(), isNotEmpty);
        expect(l10n.feed_add_another.trim(), isNotEmpty);
        expect(l10n.feed_removed_undo('Ann').trim(), isNotEmpty);
        expect(l10n.feed_open_full_conversation.trim(), isNotEmpty);
        expect(l10n.feed_tap_to_say_hi.trim(), isNotEmpty);
        expect(l10n.feed_connected.trim(), isNotEmpty);
      }
    });

    test('English feed copy renders the expected baseline text', () {
      // Locks the rendered English strings so existing find.text(...) feed
      // assertions keep passing.
      final en = AppLocalizationsEn();
      expect(en.feed_reply_to_name('Ann'), 'Reply to Ann…');
      expect(en.feed_message_name('Ann'), 'Message Ann…');
      expect(en.feed_add_another, 'Add another…');
      expect(en.feed_removed_undo('Ann'), 'Removed Ann');
      expect(en.feed_open_full_conversation, 'Open full conversation');
      expect(en.feed_tap_to_retry, 'tap to retry');
      expect(en.feed_undo, 'Undo');
      expect(en.feed_tap_to_say_hi, 'tap to say hi');
      expect(en.feed_connected, 'Connected');
      expect(en.feed_introduced_by('Eve'), 'Introduced by Eve');
    });

    test('removed feed keys are gone from every ARB locale', () {
      for (final locale in const ['en', 'ar', 'de']) {
        final bundle = loadArb(locale);
        for (final key in removedFeedKeys) {
          expect(
            bundle.containsKey(key),
            isFalse,
            reason: '$locale ARB still carries removed feed key "$key"',
          );
          // Its metadata block must be gone too.
          expect(
            bundle.containsKey('@$key'),
            isFalse,
            reason: '$locale ARB still carries metadata "@$key"',
          );
        }
      }
    });
  });
}
