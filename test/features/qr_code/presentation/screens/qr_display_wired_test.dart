import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/qr_code/application/direct_linked_device_qr.dart';
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
    DirectLinkedDeviceQrSource? linkedDeviceQrSource,
  }) {
    final widget = MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: QRDisplayWired(
        // A distinct key per (bridge, source) forces a fresh State so the
        // payload is rebuilt instead of reusing the previous pump's result.
        key: ValueKey<int>(
          Object.hash(
            identityHashCode(bridgeOverride ?? bridge),
            identityHashCode(linkedDeviceQrSource),
          ),
        ),
        repo: repoOverride ?? repo,
        bridgeClient: bridgeOverride ?? bridge,
        onClose: onClose ?? () {},
        backgroundPreference: backgroundPreference,
        linkedDeviceQrSource: linkedDeviceQrSource,
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

    testWidgets('TC-360-02a dual-signed linked-device QR stages only exact '
        'known-contact pending authority', (tester) async {
      const accountPublicKey = 'xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo=';
      const accountPeerId =
          '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj';
      const transportPublicKey = 'xvKsVZiXDHljNxTT61w017/D6S2ljHNUs3mW2aSvOrI=';
      const transportPeerId =
          '12D3KooWPCyWnZCXR3VGdrQjLr5d8TBaAHD956XZvo6xoCXYB5AR';

      final linkedIdentity = IdentityModel(
        peerId: accountPeerId,
        publicKey: accountPublicKey,
        privateKey: 'account-private-key',
        mnemonic12: testIdentity.mnemonic12,
        mlKemPublicKey: 'device-mlkem',
        mlKemSecretKey: 'device-mlkem-secret',
        username: 'Linked',
        createdAt: testIdentity.createdAt,
        updatedAt: testIdentity.updatedAt,
      );

      // ── Default (no source): the LEGACY contact QR, byte-for-byte. No
      // optional field was added to it, so an old parser still reads it and
      // still rejects the device document. ──
      repo.seed(linkedIdentity);
      bridge.responses['payload.sign'] = {
        'ok': true,
        'signature': 'legacy-sig',
      };
      await tester.pumpWidget(pumpQRDisplay(tester));
      await tester.pump(const Duration(seconds: 1));
      final legacyData = tester
          .widget<QRDisplayScreen>(find.byType(QRDisplayScreen))
          .qrData!;
      final legacyPayload = jsonDecode(legacyData) as Map<String, dynamic>;
      expect(legacyPayload.keys.toSet(), <String>{
        'ns',
        'pk',
        'rv',
        'sig',
        'ts',
        'un',
      });
      expect(legacyPayload.containsKey('mknoon'), isFalse);
      expect(isDirectLinkedDeviceQrDocument(legacyData), isFalse);

      // ── The explicit linked setup/status route renders the DEDICATED
      // dual-signed device document instead. ──
      // FakeBridge answers `payload.sign` with one canned signature, so the
      // DISTINCTNESS of the two signatures is proven in the foundation test
      // (real key-derived signer). What this layer proves is the wiring: two
      // sign calls, two DIFFERENT private keys, one identical signed body.
      final linkedBridge = FakeBridge();
      await tester.pumpWidget(
        pumpQRDisplay(
          tester,
          bridgeOverride: linkedBridge,
          linkedDeviceQrSource: DirectLinkedDeviceQrSource(
            selector: const DirectLinkedDeviceSelector.enabled(),
            loadAuthority: () async =>
                const LinkedInstallationAuthoritySnapshot(
                  disposition: LinkedInstallationDisposition.active,
                  credential: LinkedTransportCredential(
                    state: LinkedTransportCredentialState.active,
                    accountPeerId: accountPeerId,
                    accountPublicKey: accountPublicKey,
                    deviceId: 'installation-1',
                    transportPeerId: transportPeerId,
                    transportPublicKey: transportPublicKey,
                    transportPrivateKey: 'transport-private-key',
                    createdAt: '2026-01-01T00:00:00.000Z',
                    activatedAt: '2026-01-01T00:00:00.000Z',
                  ),
                  failClosedReason: null,
                ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final linkedData = tester
          .widget<QRDisplayScreen>(find.byType(QRDisplayScreen))
          .qrData!;
      expect(isDirectLinkedDeviceQrDocument(linkedData), isTrue);
      final envelope =
          (jsonDecode(linkedData) as Map<String, dynamic>)['mknoon']
              as Map<String, dynamic>;
      expect(envelope['purpose'], directLinkedDeviceQrPurpose);
      expect(envelope['version'], directLinkedDeviceQrVersion);
      // TWO independent signatures over the SAME domain-separated body,
      // produced by two DIFFERENT private keys.
      final signRequests = linkedBridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .where((request) => request['cmd'] == 'payload.sign')
          .map((request) => request['payload'] as Map<String, dynamic>)
          .toList();
      expect(signRequests, hasLength(2));
      expect(signRequests[0]['privateKey'], 'account-private-key');
      expect(signRequests[1]['privateKey'], 'transport-private-key');
      expect(
        signRequests[0]['data'],
        signRequests[1]['data'],
        reason: 'both keys sign the SAME canonical body',
      );
      expect(
        signRequests[0]['data'] as String,
        startsWith(directLinkedDeviceQrSigningDomain),
        reason:
            'the domain separator is what stops either signature being '
            'replayed against the legacy contact QR',
      );
      expect(envelope['accountSignature'], isA<String>());
      expect(envelope['transportSignature'], isA<String>());
      // The legacy contact QR's required flat fields are absent, so an old
      // parser rejects this document rather than half-reading it.
      for (final legacyField in const <String>['pk', 'ns', 'rv', 'ts', 'sig']) {
        expect(
          (jsonDecode(linkedData) as Map<String, dynamic>).containsKey(
            legacyField,
          ),
          isFalse,
        );
      }

      // ── Selector OFF authors nothing, even on the linked route. ──
      await tester.pumpWidget(
        pumpQRDisplay(
          tester,
          bridgeOverride: FakeBridge(),
          linkedDeviceQrSource: DirectLinkedDeviceQrSource(
            selector: const DirectLinkedDeviceSelector.disabled(),
            loadAuthority: () async =>
                const LinkedInstallationAuthoritySnapshot(
                  disposition: LinkedInstallationDisposition.active,
                  credential: LinkedTransportCredential(
                    state: LinkedTransportCredentialState.active,
                    accountPeerId: accountPeerId,
                    accountPublicKey: accountPublicKey,
                    deviceId: 'installation-1',
                    transportPeerId: transportPeerId,
                    transportPublicKey: transportPublicKey,
                    transportPrivateKey: 'transport-private-key',
                    createdAt: '2026-01-01T00:00:00.000Z',
                    activatedAt: '2026-01-01T00:00:00.000Z',
                  ),
                  failClosedReason: null,
                ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(QrImageView), findsNothing);
    });
  });
}
