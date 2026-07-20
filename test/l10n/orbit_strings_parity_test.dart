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
    // 206 — the orbit center self-avatar's "open settings" button Semantics
    // label (the migrated settings entry point). A hardcoded literal would trip
    // l10n_integrity_test, so this key is mandatory across every locale.
    'orbit_open_settings',
    // 212 TC-212-10 — the all-chats floated search trigger's Semantics label
    // (the find pill has had one since 198; the trigger was the unlabeled
    // sibling; the dock's `orbit_search` hint is placeholder copy, not a
    // button label — V4).
    'orbit_search_trigger_semantics',
    // 207 TC-207-21 — top-row intro dock/remnant entry point labels.
    'orbit_intro_dock_label',
    'orbit_intro_dock_semantics',
    'orbit_intro_remnant_semantics',
  ];
  const groupExitKeys = <String>[
    'orbit_leave_action',
    'orbit_leave_group_body',
    'orbit_leave_group_action',
    'group_exit_only_admin_title',
    'group_exit_only_admin_body',
    'group_exit_choose_admin',
    'group_exit_choose_admin_body',
    'group_exit_dissolve_for_everyone',
    'group_exit_keep_group',
    'group_exit_keep_and_close_semantics',
    'group_exit_no_eligible_successor',
    'group_exit_choose_member',
    'group_exit_continue_to_leave',
    'group_exit_stay_in_group',
    'group_exit_admin_sync_pending_title',
    'group_exit_admin_sync_pending_body',
    'group_exit_leave_uncertain',
    'group_exit_cleanup_incomplete',
  ];

  Map<String, Object?> loadArb(String locale) {
    final file = File('lib/l10n/app_$locale.arb');
    return (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
        .cast<String, Object?>();
  }

  group('orbit strings parity (TC-193-14)', () {
    test('group exit keys exist in every locale and generated API', () {
      for (final locale in const ['en', 'ar', 'de']) {
        final bundle = loadArb(locale);
        for (final key in groupExitKeys) {
          expect(bundle[key], isA<String>());
          expect((bundle[key] as String).trim(), isNotEmpty);
        }
      }
      for (final l10n in [
        AppLocalizationsEn(),
        AppLocalizationsAr(),
        AppLocalizationsDe(),
      ]) {
        expect(l10n.orbit_leave_action.trim(), isNotEmpty);
        expect(l10n.orbit_leave_group_body.trim(), isNotEmpty);
        expect(l10n.orbit_leave_group_action.trim(), isNotEmpty);
        expect(l10n.group_exit_only_admin_title.trim(), isNotEmpty);
        expect(
          l10n.group_exit_only_admin_body('Night Owls').trim(),
          isNotEmpty,
        );
        expect(l10n.group_exit_choose_admin.trim(), isNotEmpty);
        expect(l10n.group_exit_choose_admin_body.trim(), isNotEmpty);
        expect(l10n.group_exit_dissolve_for_everyone.trim(), isNotEmpty);
        expect(l10n.group_exit_keep_group.trim(), isNotEmpty);
        expect(l10n.group_exit_keep_and_close_semantics.trim(), isNotEmpty);
        expect(l10n.group_exit_no_eligible_successor.trim(), isNotEmpty);
        expect(l10n.group_exit_choose_member.trim(), isNotEmpty);
        expect(l10n.group_exit_continue_to_leave.trim(), isNotEmpty);
        expect(l10n.group_exit_stay_in_group.trim(), isNotEmpty);
        expect(l10n.group_exit_admin_sync_pending_title.trim(), isNotEmpty);
        expect(l10n.group_exit_admin_sync_pending_body.trim(), isNotEmpty);
        expect(l10n.group_exit_leave_uncertain.trim(), isNotEmpty);
        expect(l10n.group_exit_cleanup_incomplete.trim(), isNotEmpty);
      }
      final en = AppLocalizationsEn();
      expect(en.orbit_leave_action, 'Leave');
      expect(en.orbit_leave_group_action, 'Leave & Delete');
      expect(en.group_exit_only_admin_title, 'You’re the only admin');
      expect(
        en.group_exit_only_admin_body('Night Owls'),
        'A group needs at least one admin before you can leave. '
        'Choose what should happen to Night Owls.',
      );
    });

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

    test('TC-205-11 orbit2/orbit3/nav_orbit3 keys are absent from every ARB', () {
      // 205 item 7 — the deleted mock prototypes take all their l10n with them,
      // atomically across every locale (a one-sided removal would trip
      // l10n_integrity parity).
      for (final locale in const ['en', 'ar', 'de']) {
        final bundle = loadArb(locale);
        final leftover = bundle.keys
            .where(
              (k) =>
                  k.startsWith('orbit2_') ||
                  k.startsWith('orbit3_') ||
                  k.startsWith('@orbit2_') ||
                  k.startsWith('@orbit3_') ||
                  k == 'nav_orbit3',
            )
            .toList();
        expect(
          leftover,
          isEmpty,
          reason: '$locale ARB still carries prototype keys: $leftover',
        );
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
        expect(
          l10n.orbit_edit_step_increase('Ring spacing').trim(),
          isNotEmpty,
        );
        expect(
          l10n.orbit_edit_step_decrease('Ring spacing').trim(),
          isNotEmpty,
        );
        expect(l10n.orbit_find_placeholder.trim(), isNotEmpty);
        expect(l10n.orbit_find_pill_semantics.trim(), isNotEmpty);
        expect(l10n.orbit_chip_provenance_ring(1).trim(), isNotEmpty);
        expect(l10n.orbit_chip_provenance_arc(2).trim(), isNotEmpty);
        expect(l10n.orbit_chip_open('Alice').trim(), isNotEmpty);
        // 206 — the center self-avatar settings-entry Semantics label.
        expect(l10n.orbit_open_settings.trim(), isNotEmpty);
        // 212 — the all-chats floated search trigger's Semantics label.
        expect(l10n.orbit_search_trigger_semantics.trim(), isNotEmpty);
      }
    });

    test(
      'English orbit view-split copy renders the expected baseline text',
      () {
        final en = AppLocalizationsEn();
        expect(en.orbit_view_toggle_to_list, 'Show all chats');
        expect(en.orbit_view_toggle_to_circle, 'Show inner circle');
        expect(
          en.orbit_inner_circle_empty_hint,
          'Add friends to see your inner circle',
        );
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
        expect(
          en.orbit_edit_step_increase('Ring spacing'),
          'Increase Ring spacing',
        );
        expect(en.orbit_chip_provenance_ring(1), 'Ring 1');
        expect(en.orbit_chip_provenance_arc(2), 'Arc 2');
        expect(en.orbit_chip_open('Alice'), 'Open Alice');
        // 206 baseline.
        expect(en.orbit_open_settings, 'Open settings');
        // 212 baseline (TC-212-09 finds the trigger by this exact label).
        expect(en.orbit_search_trigger_semantics, 'Search chats');
      },
    );
  });
}
