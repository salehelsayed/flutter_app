import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/l10n/app_localizations_ar.dart';
import 'package:flutter_app/l10n/app_localizations_de.dart';
import 'package:flutter_app/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

/// 193 TC-193-14 — orbit view-split l10n parity.
///
/// Locks the NEW orbit view-split keys (the top-left view toggle's two
/// per-state Semantics labels + the zero-contacts Inner-Circle hint) into every
/// locale's generated `AppLocalizations` API AND the underlying ARB files.
/// Hardcoded literals for these would trip `l10n_integrity_test`; a missing key
/// in any locale would either break generated-API compilation (block 2) or the
/// ARB parity assertion (block 1).
void main() {
  const newOrbitKeys = <String>[
    'orbit_view_toggle_to_list',
    'orbit_view_toggle_to_circle',
    'orbit_inner_circle_empty_hint',
    // 194 TC-194-28 — per-node unread "messenger orbit" semantic label (plural).
    'orbit_node_unread_open_chat',
    // 196 TC-196-19 — the QR "My QR" / "Scan" chrome button Semantics labels.
    // The migrated chrome is now their only consumer (the header pills are
    // gone), so this keeps the keys live across every locale.
    'orbit_my_qr',
    'orbit_scan',
  ];

  Map<String, Object?> loadArb(String locale) {
    final file = File('lib/l10n/app_$locale.arb');
    return (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
        .cast<String, Object?>();
  }

  group('orbit strings parity (TC-193-14)', () {
    test('new orbit view-split keys exist in every ARB locale', () {
      for (final locale in const ['en', 'ar', 'de']) {
        final bundle = loadArb(locale);
        for (final key in newOrbitKeys) {
          expect(
            bundle.containsKey(key),
            isTrue,
            reason: '$locale ARB is missing new orbit key "$key"',
          );
          expect(
            (bundle[key] as String?)?.trim().isNotEmpty ?? false,
            isTrue,
            reason: '$locale:$key is empty',
          );
        }
      }
    });

    test('new orbit view-split keys are reachable through the generated API', () {
      // Instantiating each generated locale proves the key set compiled into
      // the AppLocalizations surface for en/ar/de (a missing key would not
      // generate a getter and this file would not compile).
      for (final l10n in [
        AppLocalizationsEn(),
        AppLocalizationsAr(),
        AppLocalizationsDe(),
      ]) {
        expect(l10n.orbit_view_toggle_to_list.trim(), isNotEmpty);
        expect(l10n.orbit_view_toggle_to_circle.trim(), isNotEmpty);
        expect(l10n.orbit_inner_circle_empty_hint.trim(), isNotEmpty);
        // Plural method key: invoke with args to prove it generated.
        expect(l10n.orbit_node_unread_open_chat('Alice', 3).trim(), isNotEmpty);
        // 196 QR chrome button labels.
        expect(l10n.orbit_my_qr.trim(), isNotEmpty);
        expect(l10n.orbit_scan.trim(), isNotEmpty);
      }
    });

    test('English orbit view-split copy renders the expected baseline text', () {
      final en = AppLocalizationsEn();
      expect(en.orbit_view_toggle_to_list, 'Show all chats');
      expect(en.orbit_view_toggle_to_circle, 'Show inner circle');
      expect(en.orbit_inner_circle_empty_hint, 'Add friends to see your inner circle');
      expect(
        en.orbit_node_unread_open_chat('Alice', 1),
        'Open chat with Alice, 1 unread message',
      );
      expect(
        en.orbit_node_unread_open_chat('Alice', 5),
        'Open chat with Alice, 5 unread messages',
      );
      expect(en.orbit_my_qr, 'My QR');
      expect(en.orbit_scan, 'Scan');
    });
  });
}
