import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_group.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/private_translator_settings_section.dart';
import 'package:flutter_app/features/translate_preview/translation_preferences.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/bridge/fake_bridge.dart';
import '../../core/secure_storage/fake_secure_key_store.dart';
import '../../core/services/fake_p2p_service.dart';
import '../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../contacts/domain/repositories/fake_contact_repository.dart';
import '../identity/domain/repositories/fake_identity_repository.dart';
import 'fake_model_delivery_controller.dart';

const _total = 2600000000;

Future<FakeModelDeliveryController> _pumpRow(
  WidgetTester tester,
  ModelDeliveryState state, {
  VoidCallback? onFreeUpSpace,
}) async {
  final controller = FakeModelDeliveryController(state);
  await tester.pumpWidget(
    localizedApp(
      Scaffold(
        body: PrivateTranslatorSettingsSection(
          controller: controller,
          onFreeUpSpace: onFreeUpSpace,
        ),
      ),
    ),
  );
  return controller;
}

Future<FakeModelDeliveryController> _pumpSettings(
  WidgetTester tester,
  ModelDeliveryState state, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool enabled = true,
}) async {
  final controller = FakeModelDeliveryController(state);
  debugTranslatePreviewEnabledOverride = enabled;
  debugModelDeliveryOverride = controller;
  final shell = AppShellController();
  final privacyRepo = InMemoryPostsPrivacySettingsRepository();
  addTearDown(() {
    debugTranslatePreviewEnabledOverride = null;
    debugModelDeliveryOverride = null;
    shell.dispose();
    privacyRepo.dispose();
    controller.state.dispose();
    controller.allowMobileData.dispose();
    controller.memoryNoticePending.dispose();
  });
  await tester.pumpWidget(
    localizedApp(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: SettingsWired(
            identityRepo: FakeIdentityRepository(),
            bridge: FakeBridge(),
            contactRepo: FakeContactRepository(),
            p2pService: FakeP2PService(),
            secureKeyStore: FakeSecureKeyStore(),
            imageProcessor: ImageProcessor(),
            appShellController: shell,
            postsPrivacySettingsRepository: privacyRepo,
          ),
        ),
      ),
      locale: locale,
    ),
  );
  // AmbientBackground animates continuously; settle only the owned startup.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return controller;
}

void _expectPreferencesRows(WidgetTester tester) {
  final privateRow = find.byKey(
    const ValueKey('settings-row-private-translator'),
  );
  final targetRow = find.byKey(const ValueKey('settings-row-translate-to'));
  expect(privateRow, findsOneWidget);
  expect(targetRow, findsOneWidget);
  final card = find.ancestor(
    of: privateRow,
    matching: find.byType(SettingsGroupCard),
  );
  expect(card, findsOneWidget);
  expect(
    tester.widget<SettingsGroupCard>(card).label,
    AppLocalizations.of(
      tester.element(privateRow),
    )!.settings_section_preferences,
  );
  expect(find.descendant(of: card, matching: targetRow), findsOneWidget);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugTranslationPreferencesOverride = TranslationPreferences();
  });
  tearDown(() => debugTranslationPreferencesOverride = null);

  testWidgets('unsupported: Settings row keeps a manual memory retry without '
      'a download or mobile-data switch', (tester) async {
    final controller = await _pumpRow(tester, const ModelUnsupported());
    expect(find.text('Private translator'), findsOneWidget);
    expect(find.text('Not available on this phone'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Download over mobile data'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Your private translator'), findsNothing);
    expect(controller.calls, ['retryMemorySafety']);
  });

  testWidgets('5a not downloaded: Get opens the offer sheet', (tester) async {
    await _pumpRow(
      tester,
      const ModelNotDownloaded(
        totalBytes: _total,
        freeBytes: 18400000000,
        onWifi: true,
      ),
    );
    expect(
      find.text('Translate Thoughts and voice notes. Stays on your phone.'),
      findsOneWidget,
    );
    expect(find.text('Download over mobile data'), findsOneWidget);
    await tester.tap(find.text('Get'));
    await tester.pumpAndSettle();
    expect(find.text('Your private translator'), findsOneWidget);
    expect(find.text('Download on Wi-Fi'), findsOneWidget);
  });

  testWidgets('not enough space: Get · Needs 2.8 GB, and Free up space in the '
      'sheet opens Storage', (tester) async {
    var storageOpened = 0;
    await _pumpRow(
      tester,
      const ModelNotEnoughSpace(
        totalBytes: _total,
        neededBytes: 2800000000,
        freeBytes: 1100000000,
      ),
      onFreeUpSpace: () => storageOpened++,
    );
    expect(find.text('Needs 2.8 GB'), findsOneWidget);
    await tester.tap(find.text('Get'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Free up space'));
    await tester.pumpAndSettle();
    expect(storageOpened, 1);
    expect(find.text('Your private translator'), findsNothing);
  });

  testWidgets('5b downloading: amount, bar, and Pause pauses', (tester) async {
    final controller = await _pumpRow(
      tester,
      const ModelDownloading(receivedBytes: 1100000000, totalBytes: _total),
    );
    expect(find.text('Downloading · 1.1 of 2.6 GB'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.42,
    );
    await tester.tap(find.text('Pause'));
    expect(controller.calls, ['pause']);
  });

  for (final (name, state) in [
    (
      'waiting for Wi-Fi',
      const ModelWaitingForWifi(receivedBytes: 1100000000, totalBytes: _total),
    ),
    (
      'paused',
      const ModelPaused(receivedBytes: 1100000000, totalBytes: _total),
    ),
  ]) {
    testWidgets('$name: Paused · Resume resumes', (tester) async {
      final controller = await _pumpRow(tester, state);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.text('Resume'));
      expect(controller.calls, ['resume']);
    });
  }

  testWidgets("failed: Didn't finish · Try again retries", (tester) async {
    final controller = await _pumpRow(tester, const ModelFailed());
    expect(find.text("Didn't finish"), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(controller.calls, ['retry']);
  });

  testWidgets('5c ready: Remove asks once; Cancel keeps it, Remove removes', (
    tester,
  ) async {
    final controller = await _pumpRow(
      tester,
      const ModelReady(sizeBytes: _total),
    );
    expect(find.text('On this phone · works without internet'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove translation?'), findsOneWidget);
    expect(
      find.text('Frees 2.6 GB. You can download it again any time.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Remove translation?'), findsNothing);
    expect(controller.calls, isEmpty);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Remove'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.calls, ['remove']);
  });

  testWidgets('the mobile-data switch saves the choice', (tester) async {
    final controller = await _pumpRow(
      tester,
      const ModelNotDownloaded(
        totalBytes: _total,
        freeBytes: 18400000000,
        onWifi: false,
      ),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(controller.calls, ['setAllowMobileData(true)']);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets(
    'BL25U1 causal ready controller already provides translator rows',
    (tester) async {
      final controller = await _pumpRow(
        tester,
        const ModelReady(sizeBytes: _total),
      );
      expect(find.text('Private translator'), findsOneWidget);
      expect(find.text('Translate to'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(controller.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('BL25U1 causal real Settings exposes rows in Preferences', (
    tester,
  ) async {
    final controller = await _pumpSettings(
      tester,
      const ModelReady(sizeBytes: _total),
    );
    expect(
      find.byKey(const ValueKey('settings-row-media-storage')),
      findsOneWidget,
    );
    _expectPreferencesRows(tester);
    final privateRow = find.byKey(
      const ValueKey('settings-row-private-translator'),
    );
    final l10n = AppLocalizations.of(tester.element(privateRow))!;
    final privacy = find.text(l10n.translator_sheet_privacy);
    expect(privacy, findsOneWidget);
    expect(
      find.ancestor(of: privacy, matching: find.byType(SettingsGroupCard)),
      findsNothing,
    );
    expect(find.text('new'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-row-translator-mobile-data')),
      findsNothing,
    );
    expect(controller.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final (language, badge) in [
    ('en', 'new'),
    ('de', 'neu'),
    ('ar', 'جديد'),
  ]) {
    testWidgets(
      'BL25U1 $language narrow 2x Settings keeps badge and privacy readable',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pumpSettings(
          tester,
          const ModelReady(sizeBytes: _total),
          locale: Locale(language),
          textScale: 2,
        );
        _expectPreferencesRows(tester);
        final target = find.byKey(const ValueKey('settings-row-translate-to'));
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 100));
        final badgeFinder = find.descendant(
          of: target,
          matching: find.text(badge),
        );
        expect(badgeFinder, findsOneWidget);
        final badgeText = tester.widget<Text>(badgeFinder);
        final colors = tester.element(badgeFinder).backgroundReadableColors;
        expect(badgeText.style?.fontSize, 10);
        expect(badgeText.style?.height, 1.6);
        expect(badgeText.style?.fontWeight, FontWeight.w600);
        expect(badgeText.style?.color, colors.accent);
        expect(
          Directionality.of(tester.element(target)),
          language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        final l10n = AppLocalizations.of(tester.element(target))!;
        final privacy = find.text(l10n.translator_sheet_privacy);
        await tester.ensureVisible(privacy);
        await tester.pump(const Duration(milliseconds: 100));
        final card = find.ancestor(
          of: target,
          matching: find.byType(SettingsGroupCard),
        );
        expect(
          tester.getTopLeft(privacy).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(card).dy),
        );
        expect(tester.getTopLeft(privacy).dx, 24);
        expect(tester.getSize(privacy).width, 272);
        final privacyText = tester.widget<Text>(privacy);
        expect(privacyText.style?.fontSize, 13);
        expect(privacyText.style?.height, 18 / 13);
        expect(privacyText.style?.color, colors.textSecondary);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'BL25U1 flag off keeps translation absent from Settings and media sheet',
    (tester) async {
      final controller = await _pumpSettings(
        tester,
        const ModelReady(sizeBytes: _total),
        enabled: false,
      );
      expect(find.byType(PrivateTranslatorSettingsSection), findsNothing);
      final media = find.byKey(const ValueKey('settings-row-media-storage'));
      await tester.ensureVisible(media);
      await tester.tap(media);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PrivateTranslatorSettingsSection), findsNothing);
      expect(find.text('new'), findsNothing);
      expect(controller.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BL25U1 unsupported Settings keeps only manual translator retry',
    (tester) async {
      final controller = await _pumpSettings(tester, const ModelUnsupported());
      final row = find.byKey(const ValueKey('settings-row-private-translator'));
      expect(row, findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-row-translate-to')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-row-translator-mobile-data')),
        findsNothing,
      );
      expect(find.text('new'), findsNothing);
      await tester.ensureVisible(row);
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.calls, ['retryMemorySafety']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BL25U1 main Settings reacts to ready and media sheet has no duplicate',
    (tester) async {
      final controller = await _pumpSettings(
        tester,
        const ModelNotDownloaded(
          totalBytes: _total,
          freeBytes: 18400000000,
          onWifi: true,
        ),
      );
      _expectPreferencesRows(tester);
      expect(
        find.byKey(const ValueKey('settings-row-translator-mobile-data')),
        findsOneWidget,
      );
      controller.state.value = const ModelReady(sizeBytes: _total);
      await tester.pump();
      _expectPreferencesRows(tester);
      expect(
        find.byKey(const ValueKey('settings-row-translator-mobile-data')),
        findsNothing,
      );
      expect(find.text('Remove'), findsOneWidget);
      final media = find.byKey(const ValueKey('settings-row-media-storage'));
      await tester.ensureVisible(media);
      await tester.tap(media);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(PrivateTranslatorSettingsSection),
        ),
        findsNothing,
      );
      expect(controller.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
