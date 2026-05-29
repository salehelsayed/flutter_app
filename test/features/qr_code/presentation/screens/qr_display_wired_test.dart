import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_display_screen.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_display_wired.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../shared/helpers/readability_test_helpers.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  late FakeIdentityRepository repo;
  late FakeBridge bridge;

  final testIdentity = IdentityModel(
    peerId: 'test-peer-id-12345',
    publicKey: 'test-public-key',
    privateKey: 'test-private-key',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    username: 'TestUser',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  setUp(() {
    repo = FakeIdentityRepository();
    bridge = FakeBridge();
  });

  Widget pumpQRDisplay(
    WidgetTester tester, {
    FakeIdentityRepository? repoOverride,
    FakeBridge? bridgeOverride,
    VoidCallback? onClose,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
  }) {
    final widget = MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: QRDisplayWired(
        repo: repoOverride ?? repo,
        bridgeClient: bridgeOverride ?? bridge,
        onClose: onClose ?? () {},
        backgroundPreference: backgroundPreference,
      ),
    );
    return widget;
  }

  group('QRDisplayWired', () {
    testWidgets('shows loading state initially', (tester) async {
      // Seed identity so _buildPayload does not resolve immediately to
      // noIdentity, but do NOT set bridge response so the async work is
      // still in progress after a single pump.
      repo.seed(testIdentity);

      await tester.pumpWidget(pumpQRDisplay(tester));
      // After a single pump (no settle), the widget should show QRDisplayScreen
      // with null qrData (QRCodeSection renders a loading shimmer).
      expect(find.byType(QRDisplayScreen), findsOneWidget);
    });

    testWidgets('shows QR code on successful payload build', (tester) async {
      repo.seed(testIdentity);
      bridge.responses['payload.sign'] = {
        'ok': true,
        'signature': 'test-sig-123',
      };

      await tester.pumpWidget(pumpQRDisplay(tester));
      // Use pump with duration instead of pumpAndSettle because the
      // success state has infinitely-repeating animations.
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(QRDisplayScreen), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsNothing);
    });

    testWidgets('shows noIdentity state when no identity exists', (
      tester,
    ) async {
      // Do NOT seed identity -- repo returns null.
      await tester.pumpWidget(pumpQRDisplay(tester));
      await tester.pumpAndSettle();

      expect(find.text('No Identity'), findsOneWidget);
      expect(find.byIcon(Icons.person_off), findsOneWidget);
    });

    testWidgets('shows error state when bridge signing fails', (tester) async {
      repo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': false};

      await tester.pumpWidget(pumpQRDisplay(tester));
      await tester.pumpAndSettle();

      expect(find.text('Error'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('retry button rebuilds payload after error', (tester) async {
      repo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': false};

      await tester.pumpWidget(pumpQRDisplay(tester));
      await tester.pumpAndSettle();

      // Verify error state first.
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      // Fix the bridge response so retry succeeds.
      bridge.responses['payload.sign'] = {
        'ok': true,
        'signature': 'test-sig-123',
      };

      await tester.tap(find.text('Try Again'));
      // Use pump with duration because success state has infinite animations.
      await tester.pump(const Duration(seconds: 1));

      // Should now show success screen.
      expect(find.byType(QRDisplayScreen), findsOneWidget);
      expect(find.text('Error'), findsNothing);
    });

    testWidgets('close callback invoked on back tap', (tester) async {
      int closeCount = 0;

      // Use noIdentity state (simplest to reach) to verify close callback.
      await tester.pumpWidget(
        pumpQRDisplay(tester, onClose: () => closeCount++),
      );
      await tester.pumpAndSettle();

      // The arrow_back icon is present in all states.
      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(closeCount, 1);
    });

    testWidgets('shows error state on unexpected exception', (tester) async {
      repo.seed(testIdentity);
      bridge.throwOnSend = true;

      await tester.pumpWidget(pumpQRDisplay(tester));
      await tester.pumpAndSettle();

      expect(find.text('Error'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets(
      'shows error instead of shimmer when signing response is malformed',
      (tester) async {
        repo.seed(testIdentity);
        bridge.responses['payload.sign'] = {'ok': true};

        await tester.pumpWidget(pumpQRDisplay(tester));
        await tester.pumpAndSettle();

        expect(find.text('Error'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsNothing);
        expect(find.byType(QrImageView), findsNothing);
      },
    );

    testWidgets('shows QR screen with FTE layout on success', (tester) async {
      repo.seed(testIdentity);
      bridge.responses['payload.sign'] = {
        'ok': true,
        'signature': 'test-sig-123',
      };

      await tester.pumpWidget(pumpQRDisplay(tester));
      // Use pump with duration because success state has infinite animations.
      await tester.pump(const Duration(seconds: 1));

      // QRDisplayScreen uses FTE-style layout with QR code section
      expect(find.byType(QRDisplayScreen), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
        find.text('Show this to someone you want in your circle...'),
        findsOneWidget,
      );
    });

    testWidgets('daylight lagoon keeps QR display copy readable', (
      tester,
    ) async {
      repo.seed(testIdentity);
      bridge.responses['payload.sign'] = {
        'ok': true,
        'signature': 'test-sig-123',
      };

      await tester.pumpWidget(
        pumpQRDisplay(
          tester,
          backgroundPreference: BackgroundPreference.daylightLagoon,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      const colors = BackgroundReadableColors.representativeLight;
      final description = tester.widget<Text>(
        find.text('Show this to someone you want in your circle...'),
      );
      expectTextContrast(description.style!.color!, colors.surfaceBase);

      final scanTitle = tester.widget<Text>(find.text("Scan a friend's code"));
      expectTextContrast(scanTitle.style!.color!, colors.glassSurface);
    });

    testWidgets('no retry button on noIdentity state', (tester) async {
      // Do NOT seed identity.
      await tester.pumpWidget(pumpQRDisplay(tester));
      await tester.pumpAndSettle();

      expect(find.text('No Identity'), findsOneWidget);
      expect(find.text('Try Again'), findsNothing);
    });
  });
}
