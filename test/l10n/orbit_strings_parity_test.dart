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
    // 198 TC-198-57 — Sculpt & Summon strings (badge / edit handles / find / chips).
    'orbit_overflow_badge_open',
    'orbit_overflow_badge_collapse',
    'orbit_edit_banner',
    'orbit_edit_reset',
    'orbit_handle_ring_spacing',
    'orbit_handle_avatar_size',
    'orbit_handle_arc_wrap',
    'orbit_handle_max_per_arc',
    'orbit_handle_orbit_gap',
    'orbit_edit_step_increase',
    'orbit_edit_step_decrease',
    'orbit_find_placeholder',
    'orbit_find_pill_semantics',
    'orbit_chip_provenance_ring',
    'orbit_chip_provenance_arc',
    'orbit_chip_open',
    // 205 TC-205-11 — the inner-circle find-pill close X Semantics label.
    'orbit_find_close',
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

    test('TC-203-13 removed orbit keys are absent from every ARB locale', () {
      // 203 B5 — permanent re-introduction guard: the ring-view title and the
      // close-friends caption/header were removed from ALL render sites and
      // all three ARBs atomically (near-miss keys like orbit_inner_circle_badge
      // and orbit_inner_circle_empty_hint stay live with their consumers).
      const removedOrbitKeys = <String>[
        'orbit_close_friends',
        'orbit_inner_circle_title',
      ];
      for (final locale in const ['en', 'ar', 'de']) {
        final bundle = loadArb(locale);
        for (final key in removedOrbitKeys) {
          expect(
            bundle.containsKey(key),
            isFalse,
            reason: '$locale ARB re-introduces removed orbit key "$key"',
          );
        }
      }
    });

    test('TC-205-11 orbit2/orbit3/nav_orbit3 keys are absent from every ARB',
        () {
      // 205 item 7 — the deleted mock prototypes take all their l10n with them,
      // atomically across every locale (a one-sided removal would trip
      // l10n_integrity parity).
      for (final locale in const ['en', 'ar', 'de']) {
        final bundle = loadArb(locale);
        final leftover = bundle.keys
            .where((k) =>
                k.startsWith('orbit2_') ||
                k.startsWith('orbit3_') ||
                k.startsWith('@orbit2_') ||
                k.startsWith('@orbit3_') ||
                k == 'nav_orbit3')
            .toList();
        expect(leftover, isEmpty,
            reason: '$locale ARB still carries prototype keys: $leftover');
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
        // 198 Sculpt & Summon — invoke each with its args to prove it generated.
        expect(l10n.orbit_overflow_badge_open(1).trim(), isNotEmpty);
        expect(l10n.orbit_overflow_badge_open(3).trim(), isNotEmpty);
        expect(l10n.orbit_overflow_badge_collapse.trim(), isNotEmpty);
        expect(l10n.orbit_edit_banner.trim(), isNotEmpty);
        expect(l10n.orbit_edit_reset.trim(), isNotEmpty);
        expect(l10n.orbit_handle_ring_spacing.trim(), isNotEmpty);
        expect(l10n.orbit_handle_avatar_size.trim(), isNotEmpty);
        expect(l10n.orbit_handle_arc_wrap.trim(), isNotEmpty);
        expect(l10n.orbit_handle_max_per_arc.trim(), isNotEmpty);
        expect(l10n.orbit_handle_orbit_gap.trim(), isNotEmpty);
        expect(l10n.orbit_edit_step_increase('Ring spacing').trim(), isNotEmpty);
        expect(l10n.orbit_edit_step_decrease('Ring spacing').trim(), isNotEmpty);
        expect(l10n.orbit_find_placeholder.trim(), isNotEmpty);
        expect(l10n.orbit_find_pill_semantics.trim(), isNotEmpty);
        expect(l10n.orbit_chip_provenance_ring(1).trim(), isNotEmpty);
        expect(l10n.orbit_chip_provenance_arc(2).trim(), isNotEmpty);
        expect(l10n.orbit_chip_open('Alice').trim(), isNotEmpty);
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
      // 198 English baselines.
      expect(en.orbit_overflow_badge_open(1), '1 more person — tap to open');
      expect(en.orbit_overflow_badge_open(3), '3 more people — tap to open');
      expect(en.orbit_overflow_badge_collapse, 'Hide extra people');
      expect(en.orbit_edit_banner, 'TAP AWAY TO FINISH');
      expect(en.orbit_edit_reset, 'Reset');
      expect(en.orbit_handle_ring_spacing, 'Ring spacing');
      expect(en.orbit_edit_step_increase('Ring spacing'), 'Increase Ring spacing');
      expect(en.orbit_chip_provenance_ring(1), 'Ring 1');
      expect(en.orbit_chip_provenance_arc(2), 'Arc 2');
      expect(en.orbit_chip_open('Alice'), 'Open Alice');
    });
  });
}
