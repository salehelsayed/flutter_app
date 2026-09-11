import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';
import 'package:flutter_app/features/settings/presentation/widgets/background_choice_control.dart';
import 'package:flutter_app/features/settings/presentation/widgets/image_quality_toggle.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_recovery_phrase_card.dart';
import 'package:flutter_app/features/settings/presentation/widgets/safety_support_sheet.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// 209 — the focused sub-sheets the One-Screen rows open (background, photo
/// quality, video quality, recovery phrase). Each sheet hosts the EXISTING
/// control widget (BackgroundChoiceControl / ImageQualityToggle /
/// SettingsRecoveryPhraseCard) and reuses the existing wired handlers, so
/// persistence, propagation (single change-kind mechanism, INV-206-6), failure
/// revert, and reveal/copy/hide semantics carry over unchanged.
class _FailingWriteSecureKeyStore extends FakeSecureKeyStore {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('write failed');
  }
}

class _GatedWriteSecureKeyStore extends FakeSecureKeyStore {
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    await gate.future;
    await super.write(key, value);
  }
}

void main() {
  const twelveWords =
      'abandon ability able about above absent absorb abstract absurd abuse access accident';

  Future<AppShellController> pumpWired(
    WidgetTester tester, {
    FakeIdentityRepository? identityRepo,
    FakeSecureKeyStore? store,
    String mnemonic = twelveWords,
    ThemeData? themeOverride,
    bool callPrivacyAvailable = false,
  }) async {
    final repo =
        identityRepo ??
        (FakeIdentityRepository()..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'sheet-peer',
            mnemonic12: mnemonic,
          ),
        ));
    final shell = AppShellController();
    addTearDown(shell.dispose);
    final privacyRepo = InMemoryPostsPrivacySettingsRepository();
    addTearDown(privacyRepo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: themeOverride,
        home: SettingsWired(
          identityRepo: repo,
          bridge: FakeBridge(),
          contactRepo: FakeContactRepository(),
          p2pService: FakeP2PService(),
          secureKeyStore: store ?? FakeSecureKeyStore(),
          voiceCallFeatureFlags: {
            'voice_call_always_relay_enabled': callPrivacyAvailable,
          },
          imageProcessor: ImageProcessor(),
          appShellController: shell,
          postsPrivacySettingsRepository: privacyRepo,
        ),
      ),
    );
    // AmbientBackground animates forever — bounded pumps only.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    return shell;
  }

  Future<void> openSheet(WidgetTester tester, String rowKey) async {
    await tester.tap(find.byKey(ValueKey(rowKey)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settleSheetClose(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'call privacy availability opens the persisted setting in the existing sheet',
    (tester) async {
      final store = FakeSecureKeyStore();
      await pumpWired(tester, store: store);
      expect(
        find.byKey(const ValueKey('settings-row-call-privacy')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await pumpWired(tester, store: store, callPrivacyAvailable: true);
      final row = find.byKey(const ValueKey('settings-row-call-privacy'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      final toggle = find.byKey(
        const ValueKey('settings-always-relay-calls-switch'),
      );
      expect(tester.widget<Switch>(toggle).value, false);
      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 100));
      expect(await store.read('settings_always_relay_calls'), 'true');
      expect(tester.widget<Switch>(toggle).value, true);
    },
  );

  testWidgets('Settings help opens the reporting contact and safety policy', (
    tester,
  ) async {
    await pumpWired(tester);

    await openSheet(tester, 'settings-safety-support-action');

    expect(find.byType(SafetySupportSheet), findsOneWidget);
    expect(find.text('Safety & support'), findsOneWidget);
    expect(find.text('saleh.m.elsayed@proton.me'), findsOneWidget);
    expect(find.text('https://mknoon.space/child-safety'), findsOneWidget);
    expect(find.byKey(const ValueKey('safety-support-email')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Close'));
    await settleSheetClose(tester);
    expect(find.byType(SafetySupportSheet), findsNothing);
  });

  testWidgets(
    'T1 background row opens sheet with 4 options, selection marked',
    (tester) async {
      await pumpWired(tester);

      await openSheet(tester, 'settings-row-background');

      expect(find.byType(BackgroundChoiceControl), findsOneWidget);
      expect(
        find.byKey(const ValueKey('background-choice-default')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('background-choice-cosmic')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('background-choice-aurora')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('background-choice-daylight-lagoon')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('background-choice-default-selected-icon')),
        findsOneWidget,
      );
    },
  );

  testWidgets('T2 selecting Cosmic persists, updates shell, closes to row', (
    tester,
  ) async {
    final store = FakeSecureKeyStore();
    final shell = await pumpWired(tester, store: store);

    await openSheet(tester, 'settings-row-background');
    await tester.tap(find.byKey(const ValueKey('background-choice-cosmic')));
    await settleSheetClose(tester);

    expect(await store.read(BackgroundPreference.storageKey), 'cosmic');
    expect(shell.backgroundPreference, BackgroundPreference.cosmic);
    expect(find.byType(BackgroundChoiceControl), findsNothing);
    expect(find.text('Cosmic'), findsOneWidget);
  });

  // TC-248-20: under a Signal light root the background + photo-quality sheets
  // render light Material controls + warm readable extensions, while the
  // existing persist-and-close / quality-callback semantics are unchanged.
  testWidgets(
    'Signal settings sheets use light Material controls and warm semantic '
    'surfaces',
    (tester) async {
      // daylightLagoon state so the sheet's re-provided extension is warm light.
      final store = FakeSecureKeyStore();
      await store.write(BackgroundPreference.storageKey, 'daylight_lagoon');
      final shell = await pumpWired(
        tester,
        store: store,
        themeOverride: AppTheme.lightTheme,
      );

      // Photo-quality sheet: light Material brightness + warm extension, and
      // the existing quality callback still fires (and pops the sheet).
      final kinds = <AppShellChangeKind>[];
      shell.addListener(() => kinds.add(shell.lastChangeKind));
      await openSheet(tester, 'settings-row-photo-quality');
      final toggleContext = tester.element(find.byType(ImageQualityToggle));
      expect(Theme.of(toggleContext).brightness, Brightness.light);
      expect(
        Theme.of(
          toggleContext,
        ).extension<BackgroundReadableColors>()!.isLightSurface,
        isTrue,
      );
      await tester.tap(find.text('Original').first);
      await settleSheetClose(tester);
      expect(kinds, contains(AppShellChangeKind.mediaQuality));
      expect(find.byType(ImageQualityToggle), findsNothing);

      // Background sheet: light Material + warm extension, and the existing
      // persist-and-close semantics are unchanged (selecting a choice commits
      // immediately and closes to the row).
      await openSheet(tester, 'settings-row-background');
      final controlContext = tester.element(
        find.byType(BackgroundChoiceControl),
      );
      expect(Theme.of(controlContext).brightness, Brightness.light);
      final readable = Theme.of(
        controlContext,
      ).extension<BackgroundReadableColors>();
      expect(readable, isNotNull);
      expect(readable!.isLightSurface, isTrue);

      await tester.tap(find.byKey(const ValueKey('background-choice-cosmic')));
      await settleSheetClose(tester);
      expect(await store.read(BackgroundPreference.storageKey), 'cosmic');
      expect(shell.backgroundPreference, BackgroundPreference.cosmic);
      expect(find.byType(BackgroundChoiceControl), findsNothing);
    },
  );

  testWidgets('T3 background save failure reverts and surfaces the error', (
    tester,
  ) async {
    final store = _FailingWriteSecureKeyStore();
    final shell = await pumpWired(tester, store: store);

    await openSheet(tester, 'settings-row-background');
    await tester.tap(find.byKey(const ValueKey('background-choice-cosmic')));
    await settleSheetClose(tester);

    expect(find.text("Couldn't save. Try again."), findsOneWidget);
    expect(await store.read(BackgroundPreference.storageKey), isNull);
    expect(shell.backgroundPreference, BackgroundPreference.defaultBackground);

    // Dismiss the sheet — the row is back on the previous choice.
    await tester.tapAt(const Offset(200, 40));
    await settleSheetClose(tester);
    expect(find.byType(BackgroundChoiceControl), findsNothing);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets(
    'T4 photo sheet parity: options present, Original fires mediaQuality once',
    (tester) async {
      final shell = await pumpWired(tester);
      final kinds = <AppShellChangeKind>[];
      shell.addListener(() => kinds.add(shell.lastChangeKind));

      await openSheet(tester, 'settings-row-photo-quality');
      expect(find.byType(ImageQualityToggle), findsOneWidget);
      // Both options + the control's helper text surface (parity with the
      // retired inline control — behavior locked by image_quality_toggle_test).
      expect(find.text('Compressed'), findsWidgets);
      expect(find.text('Original'), findsWidgets);

      await tester.tap(
        find.descendant(
          of: find.byType(ImageQualityToggle),
          matching: find.text('Original'),
        ),
      );
      await settleSheetClose(tester);

      // Discriminator: exactly one mediaQuality change-kind, and NOT identity.
      expect(
        kinds.where((k) => k == AppShellChangeKind.mediaQuality).length,
        1,
      );
      expect(kinds.where((k) => k == AppShellChangeKind.identity), isEmpty);
      expect(find.byType(ImageQualityToggle), findsNothing);
      expect(find.text('Original'), findsOneWidget);
    },
  );

  testWidgets('T5 video sheet independent of photo', (tester) async {
    final store = FakeSecureKeyStore();
    await pumpWired(tester, store: store);

    await openSheet(tester, 'settings-row-video-quality');
    await tester.tap(
      find.descendant(
        of: find.byType(ImageQualityToggle),
        matching: find.text('Original'),
      ),
    );
    await settleSheetClose(tester);

    // Video row reads Original; the photo row is untouched (Compressed).
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Compressed'), findsOneWidget);
  });

  testWidgets(
    'T6 recovery sheet: warning, blur, reveal, copy, hide re-blurs; phrase '
    'never on the main page',
    (tester) async {
      await pumpWired(tester);

      // Never-on-page lock: the first mnemonic word is absent at rest.
      expect(find.text('abandon'), findsNothing);

      await openSheet(tester, 'settings-row-recovery');
      expect(find.byType(SettingsRecoveryPhraseCard), findsOneWidget);
      expect(find.text('Tap to reveal'), findsOneWidget);

      await tester.tap(find.text('Tap to reveal'));
      await tester.pump();
      expect(find.text('Tap to reveal'), findsNothing);
      expect(find.text('abandon'), findsOneWidget);

      await tester.tap(find.text('Copy to clipboard'));
      await tester.pump();
      expect(find.text('Copied!'), findsOneWidget);

      await tester.tap(find.text('Hide'));
      await tester.pump();
      expect(find.text('Tap to reveal'), findsOneWidget);
    },
  );

  testWidgets('T7 recovery row absent when mnemonic is not 12 words', (
    tester,
  ) async {
    await pumpWired(tester, mnemonic: 'only three words');

    expect(find.byKey(const ValueKey('settings-row-recovery')), findsNothing);
    // The rest of the identity group still renders.
    expect(find.byKey(const ValueKey('settings-row-peer-id')), findsOneWidget);
  });

  testWidgets('T8 sheet dismissed without choice changes nothing', (
    tester,
  ) async {
    final store = FakeSecureKeyStore();
    final shell = await pumpWired(tester, store: store);

    await openSheet(tester, 'settings-row-background');
    expect(find.byType(BackgroundChoiceControl), findsOneWidget);

    // Barrier-dismiss without selecting.
    await tester.tapAt(const Offset(200, 40));
    await settleSheetClose(tester);

    expect(find.byType(BackgroundChoiceControl), findsNothing);
    expect(await store.read(BackgroundPreference.storageKey), isNull);
    expect(shell.backgroundPreference, BackgroundPreference.defaultBackground);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets('T9 mid-save back-nav is safe', (tester) async {
    final store = _GatedWriteSecureKeyStore();
    await pumpWired(tester, store: store);

    await openSheet(tester, 'settings-row-background');
    await tester.tap(find.byKey(const ValueKey('background-choice-cosmic')));
    await tester.pump();

    // Pop the sheet while the save is still in flight.
    await tester.tapAt(const Offset(200, 40));
    await settleSheetClose(tester);
    expect(tester.takeException(), isNull);

    // The save eventually lands; the row matches the persisted outcome —
    // never a stale third state.
    store.gate.complete();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(await store.read(BackgroundPreference.storageKey), 'cosmic');
    expect(find.text('Cosmic'), findsOneWidget);
  });
}
