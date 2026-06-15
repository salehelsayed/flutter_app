import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';
import 'package:flutter_app/features/account_migration/application/migration_transfer_keep_alive.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/presentation/models/account_migration_ui_state.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_journey_screen.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_journey_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/fake_upload_wake_lock_driver.dart';

class _FakeBridge implements Bridge {
  @override
  Future<String> send(String message) async => jsonEncode({'ok': true});

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  bool get isInitialized => true;

  @override
  void Function(ChatMessage)? onMessageReceived;

  @override
  void Function(p2p.ConnectionState)? onPeerConnected;

  @override
  void Function(p2p.ConnectionState)? onPeerDisconnected;

  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;

  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;

  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;

  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

class _FakeIdentityRepository implements IdentityRepository {
  @override
  Future<IdentityModel?> loadIdentity() async => IdentityModel(
    peerId: 'old-phone-peer',
    publicKey: 'public',
    privateKey: 'private',
    mnemonic12:
        'abandon ability able about above absent absorb abstract absurd abuse access accident',
    username: 'Alice',
    createdAt: '2026-06-07T10:00:00.000Z',
    updatedAt: '2026-06-07T10:00:00.000Z',
  );

  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  MigrationQrPayload payload({
    String sessionId = 'session-123',
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    final created =
        createdAt ??
        DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    return MigrationQrPayload(
      sessionId: sessionId,
      createdAt: created,
      expiresAt: expiresAt ?? created.add(const Duration(minutes: 5)),
      newPhoneEphemeralPublicKey: 'new-phone-public-key',
      channelNonce: 'channel-nonce',
    );
  }

  testWidgets(
    'old-phone daylight screen uses readable colors and a visible back action',
    (tester) async {
      var closed = false;

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyScreen(
            role: AccountMigrationRole.oldPhone,
            backgroundPreference: BackgroundPreference.daylightLagoon,
            onClose: () => closed = true,
          ),
        ),
      );
      await tester.pump();

      const readableColors = BackgroundReadableColors.representativeLight;
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      final title = tester.widget<Text>(find.text('Move account to new phone'));
      final subtitle = tester.widget<Text>(
        find.text('Scan the migration QR shown on your new phone.'),
      );
      final panelTitle = tester.widget<Text>(
        find.text('Scan the migration QR'),
      );
      final panelBody = tester.widget<Text>(
        find.text('Only Move Account QR codes are accepted here.'),
      );
      final backButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('account-migration-close')),
      );

      expect(scaffold.backgroundColor, readableColors.surfaceBase);
      expect(title.style?.color, readableColors.textPrimary);
      expect(subtitle.style?.color, readableColors.textSecondary);
      expect(panelTitle.style?.color, readableColors.textPrimary);
      expect(panelBody.style?.color, readableColors.textMuted);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(backButton.tooltip, 'Back');
      expect(
        backButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        readableColors.iconPrimary,
      );
      expect(
        backButton.style?.backgroundColor?.resolve(<WidgetState>{}),
        readableColors.surfaceRaised,
      );

      await tester.tap(find.byKey(const ValueKey('account-migration-close')));

      expect(closed, isTrue);
    },
  );

  testWidgets('wired old-phone close button pops the pushed route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return TextButton(
              key: const ValueKey('open-migration'),
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AccountMigrationJourneyWired.oldPhone(
                      secureKeyStore: FakeSecureKeyStore(),
                      identityRepository: _FakeIdentityRepository(),
                      backgroundPreference: BackgroundPreference.daylightLagoon,
                    ),
                  ),
                );
              },
              child: const Text('Open migration'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-migration')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Move account to new phone'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('account-migration-close')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Move account to new phone'), findsNothing);
    expect(find.text('Open migration'), findsOneWidget);
  });

  testWidgets('new-phone QR shows loading then success without raw secrets', (
    tester,
  ) async {
    final qrPayload = payload();
    final completer =
        Future<(BuildMigrationQrPayloadResult, MigrationQrBuildOutput?)>.value((
          BuildMigrationQrPayloadResult.success,
          MigrationQrBuildOutput(
            payload: qrPayload,
            qrJson: qrPayload.toJsonString(),
          ),
        ));

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.newPhone(
          key: const ValueKey('account-migration-keygen-failed-test'),
          bridge: _FakeBridge(),
          secureKeyStore: FakeSecureKeyStore(),
          buildQrPayload: () => completer,
        ),
      ),
    );

    expect(find.text('Creating secure pairing code'), findsOneWidget);

    await tester.pump();

    expect(find.text('Move Account QR'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('account-migration-qr-image')),
      findsOneWidget,
    );
    final qrImage = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qrImage.errorCorrectionLevel, QrErrorCorrectLevel.L);
    expect(qrImage.padding, EdgeInsets.zero);
    expect(
      tester.getSize(find.byKey(const ValueKey('account-migration-qr-image'))),
      const Size(300, 300),
    );
    expect(
      find.byKey(
        const ValueKey('account-migration-new-phone-confirmation-code'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(deriveMigrationPairingConfirmationCode(qrPayload)),
      findsOneWidget,
    );
    expect(find.textContaining('Expires at'), findsOneWidget);
    expect(find.textContaining('new-phone-public-key'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('private'), findsNothing);
  });

  testWidgets('new-phone receiver activation event shows completion', (
    tester,
  ) async {
    final qrPayload = payload(sessionId: 'session-activated');
    final events = StreamController<AccountMigrationReceiverEvent>.broadcast();
    var activatedCallbackCalled = false;
    addTearDown(events.close);

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.newPhone(
          bridge: _FakeBridge(),
          secureKeyStore: FakeSecureKeyStore(),
          buildQrPayload: () async => (
            BuildMigrationQrPayloadResult.success,
            MigrationQrBuildOutput(
              payload: qrPayload,
              qrJson: qrPayload.toJsonString(),
            ),
          ),
          startReceiver: (_) async =>
              const AccountMigrationReceiverStartResult.started(),
          receiverEvents: events.stream,
          onReceiverActivated: () async {
            activatedCallbackCalled = true;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    events.add(
      const AccountMigrationReceiverEvent.importVerified(
        sessionId: 'session-activated',
      ),
    );
    await tester.pump();
    expect(find.text('Checking transferred data'), findsOneWidget);

    events.add(
      const AccountMigrationReceiverEvent.activated(
        sessionId: 'session-activated',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Transfer complete'), findsOneWidget);
    expect(find.text('Move Account QR'), findsNothing);
    expect(activatedCallbackCalled, isTrue);
  });

  testWidgets('new-phone QR renders keygen and persistence failures', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.newPhone(
          key: const ValueKey('account-migration-persistence-failed-test'),
          bridge: _FakeBridge(),
          secureKeyStore: FakeSecureKeyStore(),
          buildQrPayload: () async =>
              (BuildMigrationQrPayloadResult.keygenFailed, null),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Could not create migration keys'), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.newPhone(
          bridge: _FakeBridge(),
          secureKeyStore: FakeSecureKeyStore(),
          buildQrPayload: () async =>
              (BuildMigrationQrPayloadResult.persistenceFailed, null),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Could not save pairing session'), findsOneWidget);
  });

  testWidgets('new-phone QR reports local receiver startup failure', (
    tester,
  ) async {
    final qrPayload = payload();

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.newPhone(
          bridge: _FakeBridge(),
          secureKeyStore: FakeSecureKeyStore(),
          buildQrPayload: () async => (
            BuildMigrationQrPayloadResult.success,
            MigrationQrBuildOutput(
              payload: qrPayload,
              qrJson: qrPayload.toJsonString(),
            ),
          ),
          startReceiver: (_) async =>
              const AccountMigrationReceiverStartResult.failure(
                code: AccountMigrationReceiverStartFailureCode
                    .localNetworkUnavailable,
                safeMessage: 'Local network permission is unavailable.',
              ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Could not start local transfer'), findsOneWidget);
    expect(
      find.text('Local network permission is unavailable.'),
      findsOneWidget,
    );
    expect(find.text('Move Account QR'), findsNothing);
  });

  testWidgets(
    'old-phone scan authorizes migration QR and shows matching pairing code',
    (tester) async {
      final qrPayload = payload(sessionId: 'migration-session');
      final transcript = AuthenticatedMigrationChannelTranscript(
        sessionId: qrPayload.sessionId,
        newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
        oldPhonePeerId: 'old-phone-peer',
        authenticatedChannelBinding: 'authenticated-binding',
        authorizationNonce: 'authorized-nonce',
      );
      final expectedCode = deriveMigrationPairingConfirmationCode(qrPayload);
      MigrationQrPayload? authorizedPayload;

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyWired.oldPhone(
            secureKeyStore: FakeSecureKeyStore(),
            identityRepository: _FakeIdentityRepository(),
            scanQr: (_) async => qrPayload.toJsonString(),
            authorizeExport: (payload) async {
              authorizedPayload = payload;
              return (
                MigrationExportAuthorizationResult.authorized,
                transcript,
              );
            },
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Scan migration QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(authorizedPayload?.sessionId, 'migration-session');
      expect(find.text('Confirm the code'), findsOneWidget);
      expect(find.text(expectedCode), findsOneWidget);
    },
  );

  testWidgets('old-phone scan rejects contact QR without authorization', (
    tester,
  ) async {
    var authorizeCalls = 0;

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.oldPhone(
          secureKeyStore: FakeSecureKeyStore(),
          identityRepository: _FakeIdentityRepository(),
          scanQr: (_) async => '{"pk":"contact-public","ns":"contact"}',
          authorizeExport: (_) async {
            authorizeCalls += 1;
            throw StateError('must not authorize contact QR');
          },
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Scan migration QR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(authorizeCalls, 0);
    expect(find.text('Migration QR rejected'), findsOneWidget);
    expect(
      find.text('This is not a valid Move Account QR code.'),
      findsOneWidget,
    );
  });

  testWidgets('old-phone scanner route uses migration-specific copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.oldPhone(
          secureKeyStore: FakeSecureKeyStore(),
          identityRepository: _FakeIdentityRepository(),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Scan migration QR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(QRScannerScreen), findsOneWidget);
    expect(
      find.text('Point your camera at the Move Account QR on your new phone'),
      findsOneWidget,
    );
    expect(find.text('Paste migration QR'), findsOneWidget);
    expect(find.text("Point your camera at a friend's QR code"), findsNothing);
    expect(find.text("They'll be added to your circle"), findsNothing);
    expect(find.text('Paste QR Data'), findsNothing);

    await tester.tap(find.text('Paste migration QR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Paste the Move Account QR payload shown on your new phone:'),
      findsOneWidget,
    );
    expect(find.text('Paste migration QR from Clipboard'), findsOneWidget);
    expect(
      find.text('Paste the JSON QR payload from another device:'),
      findsNothing,
    );
  });

  testWidgets('progress stage copy covers proposal stages', (tester) async {
    const expectations = {
      AccountMigrationProgressStage.preparing: 'Preparing transfer',
      AccountMigrationProgressStage.connecting: 'Connecting phones',
      AccountMigrationProgressStage.encrypting: 'Encrypting account bundle',
      AccountMigrationProgressStage.transferringDatabase:
          'Transferring database',
      AccountMigrationProgressStage.transferringMedia: 'Transferring media',
      AccountMigrationProgressStage.checking: 'Checking transferred data',
      AccountMigrationProgressStage.finishing: 'Finishing move',
      AccountMigrationProgressStage.completed: 'Transfer complete',
      AccountMigrationProgressStage.cancelled: 'Move cancelled',
      AccountMigrationProgressStage.failed: 'Move failed',
    };

    for (final entry in expectations.entries) {
      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyScreen(
            role: AccountMigrationRole.oldPhone,
            progressStage: entry.key,
          ),
        ),
      );
      await tester.pump();

      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets(
    'progress wake lock acquires once and releases on terminal states',
    (tester) async {
      final driver = FakeUploadWakeLockDriver();
      UploadWakeLockController.debugReset(driver: driver);
      addTearDown(() {
        UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
      });

      await tester.pumpWidget(
        wrap(
          const AccountMigrationProgressWakeLock(
            stage: AccountMigrationProgressStage.preparing,
            active: true,
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      expect(UploadWakeLockController.debugActiveHolds, 1);
      expect(driver.enableCalls, 1);

      await tester.pumpWidget(
        wrap(
          const AccountMigrationProgressWakeLock(
            stage: AccountMigrationProgressStage.encrypting,
            active: true,
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      expect(UploadWakeLockController.debugActiveHolds, 1);
      expect(driver.enableCalls, 1);

      await tester.pumpWidget(
        wrap(
          const AccountMigrationProgressWakeLock(
            stage: AccountMigrationProgressStage.cancelled,
            active: true,
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      expect(UploadWakeLockController.debugActiveHolds, 0);
      expect(driver.disableCalls, 1);
    },
  );

  testWidgets('progress wake lock releases on inactive update and dispose', (
    tester,
  ) async {
    final driver = FakeUploadWakeLockDriver();
    UploadWakeLockController.debugReset(driver: driver);
    addTearDown(() {
      UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
    });

    await tester.pumpWidget(
      wrap(
        const AccountMigrationProgressWakeLock(
          stage: AccountMigrationProgressStage.connecting,
          active: true,
          child: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    expect(UploadWakeLockController.debugActiveHolds, 1);

    await tester.pumpWidget(
      wrap(
        const AccountMigrationProgressWakeLock(
          stage: AccountMigrationProgressStage.connecting,
          active: false,
          child: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    expect(UploadWakeLockController.debugActiveHolds, 0);
    expect(driver.disableCalls, 1);

    await tester.pumpWidget(
      wrap(
        const AccountMigrationProgressWakeLock(
          stage: AccountMigrationProgressStage.finishing,
          active: true,
          child: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    expect(UploadWakeLockController.debugActiveHolds, 1);

    await tester.pumpWidget(wrap(const SizedBox.shrink()));
    await tester.pump();
    expect(UploadWakeLockController.debugActiveHolds, 0);
    expect(driver.disableCalls, 2);
  });

  testWidgets('old-phone start transfer drives injected runner to completion', (
    tester,
  ) async {
    final qrPayload = payload(sessionId: 'migration-session');
    final transcript = AuthenticatedMigrationChannelTranscript(
      sessionId: qrPayload.sessionId,
      newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
      oldPhonePeerId: 'old-phone-peer',
      authenticatedChannelBinding: 'authenticated-binding',
      authorizationNonce: 'authorized-nonce',
    );
    final runnerStarted = Completer<void>();
    final allowFinish = Completer<void>();
    String? requestedSessionId;

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.oldPhone(
          secureKeyStore: FakeSecureKeyStore(),
          identityRepository: _FakeIdentityRepository(),
          scanQr: (_) async => qrPayload.toJsonString(),
          authorizeExport: (_) async =>
              (MigrationExportAuthorizationResult.authorized, transcript),
          runTransfer:
              ({
                required request,
                required onProgress,
                required isCancelled,
                onSegmentProgress,
              }) async {
                requestedSessionId = request.sessionId;
                onProgress(AccountMigrationTransferStep.connecting);
                runnerStarted.complete();
                await allowFinish.future;
                onProgress(AccountMigrationTransferStep.finishing);
                return const AccountMigrationTransferResult.success();
              },
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Scan migration QR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(
      find.byKey(const ValueKey('account-migration-start-transfer')),
    );
    await tester.pump();
    await runnerStarted.future;
    await tester.pump();

    expect(requestedSessionId, 'migration-session');
    expect(find.text('Connecting phones'), findsOneWidget);

    allowFinish.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Transfer complete'), findsOneWidget);
    expect(find.text('Finishing move'), findsNothing);
  });

  testWidgets('old-phone initial scanned QR opens confirmation directly', (
    tester,
  ) async {
    final qrPayload = payload(sessionId: 'migration-session');
    final transcript = AuthenticatedMigrationChannelTranscript(
      sessionId: qrPayload.sessionId,
      newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
      oldPhonePeerId: 'old-phone-peer',
      authenticatedChannelBinding: 'authenticated-binding',
      authorizationNonce: 'authorized-nonce',
    );
    MigrationQrPayload? authorizedPayload;

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.oldPhone(
          secureKeyStore: FakeSecureKeyStore(),
          identityRepository: _FakeIdentityRepository(),
          initialScannedQr: qrPayload.toJsonString(),
          authorizeExport: (payload) async {
            authorizedPayload = payload;
            return (MigrationExportAuthorizationResult.authorized, transcript);
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(authorizedPayload?.sessionId, 'migration-session');
    expect(find.text('Confirm the code'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('account-migration-start-transfer')),
      findsOneWidget,
    );
  });

  testWidgets(
    'P0-2: over-cap account blocks Start transfer at the confirm stage',
    (tester) async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final qrPayload = payload(sessionId: 'migration-session');
      final transcript = AuthenticatedMigrationChannelTranscript(
        sessionId: qrPayload.sessionId,
        newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
        oldPhonePeerId: 'old-phone-peer',
        authenticatedChannelBinding: 'authenticated-binding',
        authorizationNonce: 'authorized-nonce',
      );
      var runnerCalls = 0;

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyWired.oldPhone(
            secureKeyStore: FakeSecureKeyStore(),
            identityRepository: _FakeIdentityRepository(),
            scanQr: (_) async => qrPayload.toJsonString(),
            authorizeExport: (_) async =>
                (MigrationExportAuthorizationResult.authorized, transcript),
            sizeGate: AccountMigrationSizeGate(
              estimateMoveSize: () async =>
                  const AccountMigrationMoveSizeEstimate(
                    databaseBytes: 50 * 1024 * 1024,
                    mediaBytes: 200 * 1024 * 1024,
                    secureBytes: 0,
                  ),
              policy: const AccountMigrationSizePolicy(
                maxAccountBytes: 200 * 1024 * 1024,
              ),
            ),
            runTransfer:
                ({
                  required request,
                  required onProgress,
                  required isCancelled,
                  onSegmentProgress,
                }) async {
                  runnerCalls++;
                  return const AccountMigrationTransferResult.success();
                },
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Scan migration QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('This account is too large to move (250 MB of 200 MB max)'),
        findsOneWidget,
      );
      final startButton = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('account-migration-start-transfer')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(startButton.onPressed, isNull, reason: 'Start must be blocked');

      // Tapping the blocked button must not start a transfer (and therefore
      // no transcript/manifest POST can ever be attempted).
      await tester.tap(
        find.byKey(const ValueKey('account-migration-start-transfer')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(runnerCalls, 0);

      final blockedEvents = flowEvents
          .where(
            (event) => event['event'] == 'ACCOUNT_MIGRATION_SIZE_CAP_BLOCKED',
          )
          .toList(growable: false);
      expect(blockedEvents, hasLength(1));
      final details = Map<String, dynamic>.from(
        blockedEvents.single['details'] as Map,
      );
      expect(details['sessionId'], 'migration-session');
      expect(details['totalBytes'], 250 * 1024 * 1024);
      expect(details['maxAccountBytes'], 200 * 1024 * 1024);
    },
  );

  testWidgets(
    'P0-2: under-cap account shows the size estimate and keeps Start active',
    (tester) async {
      final qrPayload = payload(sessionId: 'migration-session');
      final transcript = AuthenticatedMigrationChannelTranscript(
        sessionId: qrPayload.sessionId,
        newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
        oldPhonePeerId: 'old-phone-peer',
        authenticatedChannelBinding: 'authenticated-binding',
        authorizationNonce: 'authorized-nonce',
      );
      var runnerCalls = 0;

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyWired.oldPhone(
            secureKeyStore: FakeSecureKeyStore(),
            identityRepository: _FakeIdentityRepository(),
            scanQr: (_) async => qrPayload.toJsonString(),
            authorizeExport: (_) async =>
                (MigrationExportAuthorizationResult.authorized, transcript),
            sizeGate: AccountMigrationSizeGate(
              estimateMoveSize: () async =>
                  const AccountMigrationMoveSizeEstimate(
                    databaseBytes: 2 * 1024 * 1024,
                    mediaBytes: 10 * 1024 * 1024,
                    secureBytes: 0,
                  ),
              policy: const AccountMigrationSizePolicy(
                maxAccountBytes: 200 * 1024 * 1024,
              ),
            ),
            runTransfer:
                ({
                  required request,
                  required onProgress,
                  required isCancelled,
                  onSegmentProgress,
                }) async {
                  runnerCalls++;
                  return const AccountMigrationTransferResult.success();
                },
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Scan migration QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey('account-migration-size-estimate')),
        findsOneWidget,
      );
      expect(find.text('Account size: about 12 MB'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('account-migration-start-transfer')),
      );
      await tester.pump();
      await tester.pump();
      expect(runnerCalls, 1);
    },
  );

  testWidgets('old-phone default transfer runner fails explicitly', (
    tester,
  ) async {
    final qrPayload = payload(sessionId: 'migration-session');
    final transcript = AuthenticatedMigrationChannelTranscript(
      sessionId: qrPayload.sessionId,
      newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
      oldPhonePeerId: 'old-phone-peer',
      authenticatedChannelBinding: 'authenticated-binding',
      authorizationNonce: 'authorized-nonce',
    );

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.oldPhone(
          secureKeyStore: FakeSecureKeyStore(),
          identityRepository: _FakeIdentityRepository(),
          scanQr: (_) async => qrPayload.toJsonString(),
          authorizeExport: (_) async =>
              (MigrationExportAuthorizationResult.authorized, transcript),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Scan migration QR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(
      find.byKey(const ValueKey('account-migration-start-transfer')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Move failed'), findsOneWidget);
    expect(
      find.text(
        'Move Account could not start the transfer from this screen. Close this screen, reopen Settings, and start Move Account again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'old-phone cancellation is not overwritten by runner completion',
    (tester) async {
      final qrPayload = payload(sessionId: 'migration-session');
      final transcript = AuthenticatedMigrationChannelTranscript(
        sessionId: qrPayload.sessionId,
        newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
        oldPhonePeerId: 'old-phone-peer',
        authenticatedChannelBinding: 'authenticated-binding',
        authorizationNonce: 'authorized-nonce',
      );
      final runnerStarted = Completer<void>();
      final allowFinish = Completer<void>();

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyWired.oldPhone(
            secureKeyStore: FakeSecureKeyStore(),
            identityRepository: _FakeIdentityRepository(),
            scanQr: (_) async => qrPayload.toJsonString(),
            authorizeExport: (_) async =>
                (MigrationExportAuthorizationResult.authorized, transcript),
            runTransfer:
                ({
                  required request,
                  required onProgress,
                  required isCancelled,
                  onSegmentProgress,
                }) async {
                  onProgress(AccountMigrationTransferStep.connecting);
                  runnerStarted.complete();
                  await allowFinish.future;
                  onProgress(AccountMigrationTransferStep.finishing);
                  return const AccountMigrationTransferResult.success();
                },
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Scan migration QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byKey(const ValueKey('account-migration-start-transfer')),
      );
      await tester.pump();
      await runnerStarted.future;
      await tester.pump();

      expect(find.text('Connecting phones'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('account-migration-cancel-transfer')),
      );
      await tester.pump();

      expect(find.text('Move cancelled'), findsOneWidget);

      allowFinish.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Move cancelled'), findsOneWidget);
      expect(find.text('Transfer complete'), findsNothing);
    },
  );

  testWidgets(
    'old-phone typed local transfer timeout shows stalled copy with enriched FAILED telemetry',
    (tester) async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final qrPayload = payload(sessionId: 'migration-session');
      final transcript = AuthenticatedMigrationChannelTranscript(
        sessionId: qrPayload.sessionId,
        newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
        oldPhonePeerId: 'old-phone-peer',
        authenticatedChannelBinding: 'authenticated-binding',
        authorizationNonce: 'authorized-nonce',
      );

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyWired.oldPhone(
            secureKeyStore: FakeSecureKeyStore(),
            identityRepository: _FakeIdentityRepository(),
            scanQr: (_) async => qrPayload.toJsonString(),
            authorizeExport: (_) async =>
                (MigrationExportAuthorizationResult.authorized, transcript),
            runTransfer:
                ({
                  required request,
                  required onProgress,
                  required isCancelled,
                  onSegmentProgress,
                }) async {
                  onProgress(AccountMigrationTransferStep.transferringDatabase);
                  return const AccountMigrationTransferResult.failure(
                    code:
                        AccountMigrationTransferFailureCode
                            .localTransferTimedOut,
                    safeMessage: accountMigrationLocalTransferStalledSafeMessage,
                  );
                },
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Scan migration QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byKey(const ValueKey('account-migration-start-transfer')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Move failed'), findsOneWidget);
      expect(
        find.text(accountMigrationLocalTransferStalledSafeMessage),
        findsOneWidget,
      );
      expect(
        find.text('The account move stopped unexpectedly before final handoff.'),
        findsNothing,
      );

      expect(
        flowEvents.where(
          (event) => event['event'] == 'ACCOUNT_MIGRATION_TRANSFER_ERROR',
        ),
        isEmpty,
      );
      final failedEvent = flowEvents.singleWhere(
        (event) => event['event'] == 'ACCOUNT_MIGRATION_TRANSFER_FAILED',
      );
      final details = failedEvent['details'] as Map;
      expect(details['reason'], 'localTransferTimedOut');
      expect(details['failureCode'], 'localTransferTimedOut');
      expect(details['sessionId'], 'migration-session');
      expect(details['stage'], 'transferringDatabase');
    },
  );

  testWidgets(
    'old-phone runner throwing TimeoutException keeps catch-all copy and error telemetry',
    (tester) async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final qrPayload = payload(sessionId: 'migration-session');
      final transcript = AuthenticatedMigrationChannelTranscript(
        sessionId: qrPayload.sessionId,
        newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
        oldPhonePeerId: 'old-phone-peer',
        authenticatedChannelBinding: 'authenticated-binding',
        authorizationNonce: 'authorized-nonce',
      );

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyWired.oldPhone(
            secureKeyStore: FakeSecureKeyStore(),
            identityRepository: _FakeIdentityRepository(),
            scanQr: (_) async => qrPayload.toJsonString(),
            authorizeExport: (_) async =>
                (MigrationExportAuthorizationResult.authorized, transcript),
            runTransfer:
                ({
                  required request,
                  required onProgress,
                  required isCancelled,
                  onSegmentProgress,
                }) async {
                  throw TimeoutException(
                    'segment post stalled',
                    const Duration(milliseconds: 200),
                  );
                },
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Scan migration QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byKey(const ValueKey('account-migration-start-transfer')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Move failed'), findsOneWidget);
      expect(
        find.text('The account move stopped unexpectedly before final handoff.'),
        findsOneWidget,
      );

      final errorEvent = flowEvents.singleWhere(
        (event) => event['event'] == 'ACCOUNT_MIGRATION_TRANSFER_ERROR',
      );
      final details = errorEvent['details'] as Map;
      expect(details['errorType'], 'TimeoutException');
    },
  );

  testWidgets(
    'new-phone receivingSegment and importingBundle drive progress stages and wake lock',
    (tester) async {
      final driver = FakeUploadWakeLockDriver();
      UploadWakeLockController.debugReset(driver: driver);
      addTearDown(() {
        UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
      });

      final qrPayload = payload(sessionId: 'session-progress');
      final events =
          StreamController<AccountMigrationReceiverEvent>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyWired.newPhone(
            bridge: _FakeBridge(),
            secureKeyStore: FakeSecureKeyStore(),
            buildQrPayload: () async => (
              BuildMigrationQrPayloadResult.success,
              MigrationQrBuildOutput(
                payload: qrPayload,
                qrJson: qrPayload.toJsonString(),
              ),
            ),
            startReceiver: (_) async =>
                const AccountMigrationReceiverStartResult.started(),
            receiverEvents: events.stream,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(UploadWakeLockController.debugActiveHolds, 0);

      events.add(
        const AccountMigrationReceiverEvent.receivingSegment(
          sessionId: 'session-progress',
          segmentIndex: 0,
          segmentCount: 34,
          verifiedCount: 1,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(
          const ValueKey('account-migration-progress-transferringDatabase'),
        ),
        findsOneWidget,
      );
      expect(UploadWakeLockController.debugActiveHolds, greaterThan(0));

      events.add(
        const AccountMigrationReceiverEvent.importingBundle(
          sessionId: 'session-progress',
          segmentCount: 34,
          verifiedCount: 34,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('account-migration-progress-checking')),
        findsOneWidget,
      );
      expect(UploadWakeLockController.debugActiveHolds, greaterThan(0));

      // Monotonic guard: a late segment event must not regress the stage.
      events.add(
        const AccountMigrationReceiverEvent.receivingSegment(
          sessionId: 'session-progress',
          segmentIndex: 33,
          segmentCount: 34,
          verifiedCount: 34,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('account-migration-progress-checking')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('account-migration-progress-transferringDatabase'),
        ),
        findsNothing,
      );

      events.add(
        const AccountMigrationReceiverEvent.activated(
          sessionId: 'session-progress',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('account-migration-progress-completed')),
        findsOneWidget,
      );
      expect(find.text('Transfer complete'), findsOneWidget);
      expect(UploadWakeLockController.debugActiveHolds, 0);
    },
  );

  testWidgets(
    'new-phone receiver failure after receivingSegment releases wake lock',
    (tester) async {
      final driver = FakeUploadWakeLockDriver();
      UploadWakeLockController.debugReset(driver: driver);
      addTearDown(() {
        UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
      });

      final qrPayload = payload(sessionId: 'session-progress-failed');
      final events =
          StreamController<AccountMigrationReceiverEvent>.broadcast();
      addTearDown(events.close);

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyWired.newPhone(
            bridge: _FakeBridge(),
            secureKeyStore: FakeSecureKeyStore(),
            buildQrPayload: () async => (
              BuildMigrationQrPayloadResult.success,
              MigrationQrBuildOutput(
                payload: qrPayload,
                qrJson: qrPayload.toJsonString(),
              ),
            ),
            startReceiver: (_) async =>
                const AccountMigrationReceiverStartResult.started(),
            receiverEvents: events.stream,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      events.add(
        const AccountMigrationReceiverEvent.receivingSegment(
          sessionId: 'session-progress-failed',
          segmentIndex: 0,
          segmentCount: 34,
          verifiedCount: 1,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(
          const ValueKey('account-migration-progress-transferringDatabase'),
        ),
        findsOneWidget,
      );
      expect(UploadWakeLockController.debugActiveHolds, greaterThan(0));

      events.add(
        const AccountMigrationReceiverEvent.failed(
          sessionId: 'session-progress-failed',
          safeMessage: 'Local import failed.',
        ),
      );
      await tester.pump();

      expect(find.text('Move failed'), findsOneWidget);
      expect(find.text('Local import failed.'), findsOneWidget);
      expect(UploadWakeLockController.debugActiveHolds, 0);
    },
  );

  testWidgets('old-phone transfer holds the platform keep-alive for the run', (
    tester,
  ) async {
    final qrPayload = payload(sessionId: 'keepalive-session');
    final transcript = AuthenticatedMigrationChannelTranscript(
      sessionId: qrPayload.sessionId,
      newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
      oldPhonePeerId: 'old-phone-peer',
      authenticatedChannelBinding: 'authenticated-binding',
      authorizationNonce: 'authorized-nonce',
    );
    final keepAliveCalls = <String>[];
    List<String>? callsWhenRunnerStarted;

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.oldPhone(
          secureKeyStore: FakeSecureKeyStore(),
          identityRepository: _FakeIdentityRepository(),
          initialScannedQr: qrPayload.toJsonString(),
          authorizeExport: (_) async =>
              (MigrationExportAuthorizationResult.authorized, transcript),
          transferKeepAlive: MigrationTransferKeepAlive(
            invoker: (method, args) async => keepAliveCalls.add(method),
          ),
          runTransfer:
              ({
                required request,
                required onProgress,
                required isCancelled,
                onSegmentProgress,
              }) async {
                callsWhenRunnerStarted = List.of(keepAliveCalls);
                return const AccountMigrationTransferResult.success();
              },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(
      find.byKey(const ValueKey('account-migration-start-transfer')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The keep-alive was held before the runner executed and released after
    // the run completed.
    expect(callsWhenRunnerStarted, ['start']);
    expect(keepAliveCalls, ['start', 'stop']);
  });

  testWidgets('new-phone receiver holds the keep-alive until closed', (
    tester,
  ) async {
    final qrPayload = payload(sessionId: 'keepalive-receiver');
    final keepAliveCalls = <String>[];

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.newPhone(
          bridge: _FakeBridge(),
          secureKeyStore: FakeSecureKeyStore(),
          buildQrPayload: () async => (
            BuildMigrationQrPayloadResult.success,
            MigrationQrBuildOutput(
              payload: qrPayload,
              qrJson: qrPayload.toJsonString(),
            ),
          ),
          startReceiver: (_) async =>
              const AccountMigrationReceiverStartResult.started(),
          stopReceiver: (_) async {},
          transferKeepAlive: MigrationTransferKeepAlive(
            invoker: (method, args) async => keepAliveCalls.add(method),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(keepAliveCalls, ['start']);

    // Leaving the journey (dispose) releases the receiver's hold.
    await tester.pumpWidget(wrap(const SizedBox()));
    await tester.pump();

    expect(keepAliveCalls, ['start', 'stop']);
  });

  testWidgets('old-phone transferring stage shows determinate segment bar', (
    tester,
  ) async {
    final qrPayload = payload(sessionId: 'progress-session');
    final transcript = AuthenticatedMigrationChannelTranscript(
      sessionId: qrPayload.sessionId,
      newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
      oldPhonePeerId: 'old-phone-peer',
      authenticatedChannelBinding: 'authenticated-binding',
      authorizationNonce: 'authorized-nonce',
    );
    final finishTransfer = Completer<void>();

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.oldPhone(
          secureKeyStore: FakeSecureKeyStore(),
          identityRepository: _FakeIdentityRepository(),
          initialScannedQr: qrPayload.toJsonString(),
          authorizeExport: (_) async =>
              (MigrationExportAuthorizationResult.authorized, transcript),
          runTransfer:
              ({
                required request,
                required onProgress,
                required isCancelled,
                onSegmentProgress,
              }) async {
                onProgress(AccountMigrationTransferStep.transferringDatabase);
                onSegmentProgress?.call(
                  const AccountMigrationTransferSegmentProgress(
                    sentSegments: 12,
                    totalSegments: 34,
                  ),
                );
                await finishTransfer.future;
                return const AccountMigrationTransferResult.success();
              },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(
      find.byKey(const ValueKey('account-migration-start-transfer')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Transferring database'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('account-migration-progress-bar')),
    );
    expect(bar.value, closeTo(12 / 34, 0.001));
    expect(find.text('12 of 34'), findsOneWidget);

    finishTransfer.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Transfer complete'), findsOneWidget);
  });

  testWidgets(
    'old-phone transferring caption shows the account size when known',
    (tester) async {
      // The size estimate from the confirm screen must stay visible during
      // the transfer, so "14 of 460" reads as "14 of 460 of a ~454 MB move".
      final qrPayload = payload(sessionId: 'progress-size-session');
      final transcript = AuthenticatedMigrationChannelTranscript(
        sessionId: qrPayload.sessionId,
        newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
        oldPhonePeerId: 'old-phone-peer',
        authenticatedChannelBinding: 'authenticated-binding',
        authorizationNonce: 'authorized-nonce',
      );
      final finishTransfer = Completer<void>();

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyWired.oldPhone(
            secureKeyStore: FakeSecureKeyStore(),
            identityRepository: _FakeIdentityRepository(),
            initialScannedQr: qrPayload.toJsonString(),
            sizeGate: AccountMigrationSizeGate(
              estimateMoveSize: () async =>
                  const AccountMigrationMoveSizeEstimate(
                    databaseBytes: 1024 * 1024,
                    mediaBytes: 453 * 1024 * 1024,
                    secureBytes: 0,
                  ),
            ),
            authorizeExport: (_) async =>
                (MigrationExportAuthorizationResult.authorized, transcript),
            runTransfer:
                ({
                  required request,
                  required onProgress,
                  required isCancelled,
                  onSegmentProgress,
                }) async {
                  onProgress(AccountMigrationTransferStep.transferringDatabase);
                  onSegmentProgress?.call(
                    const AccountMigrationTransferSegmentProgress(
                      sentSegments: 14,
                      totalSegments: 460,
                    ),
                  );
                  await finishTransfer.future;
                  return const AccountMigrationTransferResult.success();
                },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(
        find.byKey(const ValueKey('account-migration-start-transfer')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('14 of 460 · ~454 MB'), findsOneWidget);

      finishTransfer.complete();
      await tester.pump();
      await tester.pump();
    },
  );

  testWidgets(
    'stitched old-phone journey: scan → authorize → confirm → transfer → done',
    (tester) async {
      final qrPayload = payload(sessionId: 'stitched-old-session');
      final transcript = AuthenticatedMigrationChannelTranscript(
        sessionId: qrPayload.sessionId,
        newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
        oldPhonePeerId: 'old-phone-peer',
        authenticatedChannelBinding: 'authenticated-binding',
        authorizationNonce: 'authorized-nonce',
      );
      final midTransferGate = Completer<void>();

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyWired.oldPhone(
            secureKeyStore: FakeSecureKeyStore(),
            identityRepository: _FakeIdentityRepository(),
            scanQr: (_) async => qrPayload.toJsonString(),
            authorizeExport: (_) async =>
                (MigrationExportAuthorizationResult.authorized, transcript),
            transferKeepAlive: MigrationTransferKeepAlive(
              invoker: (method, args) async {},
            ),
            runTransfer:
                ({
                  required request,
                  required onProgress,
                  required isCancelled,
                  onSegmentProgress,
                }) async {
                  onProgress(AccountMigrationTransferStep.preparing);
                  onProgress(AccountMigrationTransferStep.connecting);
                  onProgress(AccountMigrationTransferStep.encrypting);
                  onProgress(
                    AccountMigrationTransferStep.transferringDatabase,
                  );
                  onSegmentProgress?.call(
                    const AccountMigrationTransferSegmentProgress(
                      sentSegments: 2,
                      totalSegments: 3,
                    ),
                  );
                  await midTransferGate.future;
                  onSegmentProgress?.call(
                    const AccountMigrationTransferSegmentProgress(
                      sentSegments: 3,
                      totalSegments: 3,
                    ),
                  );
                  onProgress(AccountMigrationTransferStep.checking);
                  onProgress(AccountMigrationTransferStep.finishing);
                  return const AccountMigrationTransferResult.success();
                },
          ),
        ),
      );
      await tester.pump();

      // 1. Scan the new phone's QR.
      await tester.tap(find.widgetWithText(FilledButton, 'Scan migration QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 2. Authorization produced the confirmation step.
      expect(find.text('Confirm the code'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('account-migration-start-transfer')),
        findsOneWidget,
      );

      // 3. Start the transfer; mid-transfer the determinate bar shows 2/3.
      await tester.tap(
        find.byKey(const ValueKey('account-migration-start-transfer')),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Transferring database'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('account-migration-progress-bar')),
      );
      expect(bar.value, closeTo(2 / 3, 0.001));
      expect(find.text('2 of 3'), findsOneWidget);

      // 4. The run finishes through checking/finishing to completion.
      midTransferGate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Transfer complete'), findsOneWidget);
    },
  );

  testWidgets(
    'stitched new-phone journey: QR → receive → import → activated',
    (tester) async {
      final qrPayload = payload(sessionId: 'stitched-new-session');
      final events =
          StreamController<AccountMigrationReceiverEvent>.broadcast();
      addTearDown(events.close);
      var activated = false;

      await tester.pumpWidget(
        wrap(
          AccountMigrationJourneyWired.newPhone(
            bridge: _FakeBridge(),
            secureKeyStore: FakeSecureKeyStore(),
            buildQrPayload: () async => (
              BuildMigrationQrPayloadResult.success,
              MigrationQrBuildOutput(
                payload: qrPayload,
                qrJson: qrPayload.toJsonString(),
              ),
            ),
            startReceiver: (_) async =>
                const AccountMigrationReceiverStartResult.started(),
            stopReceiver: (_) async {},
            receiverEvents: events.stream,
            onReceiverActivated: () async => activated = true,
            transferKeepAlive: MigrationTransferKeepAlive(
              invoker: (method, args) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // 1. QR ready and shown.
      expect(find.text('Move Account QR'), findsOneWidget);

      // 2. Segments stream in: receiving stage with a determinate bar.
      events.add(
        const AccountMigrationReceiverEvent.receivingSegment(
          sessionId: 'stitched-new-session',
          segmentIndex: 0,
          segmentCount: 3,
          verifiedCount: 1,
        ),
      );
      await tester.pump();
      expect(find.text('Transferring database'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('account-migration-progress-bar')),
      );
      expect(bar.value, closeTo(1 / 3, 0.001));

      // 3. Import begins, then verifies.
      events.add(
        const AccountMigrationReceiverEvent.importingBundle(
          sessionId: 'stitched-new-session',
          segmentCount: 3,
          verifiedCount: 3,
        ),
      );
      await tester.pump();
      expect(find.text('Checking transferred data'), findsOneWidget);

      events.add(
        const AccountMigrationReceiverEvent.importVerified(
          sessionId: 'stitched-new-session',
        ),
      );
      await tester.pump();
      expect(find.text('Checking transferred data'), findsOneWidget);

      // 4. Activation completes the journey and fires the reroute hook.
      events.add(
        const AccountMigrationReceiverEvent.activated(
          sessionId: 'stitched-new-session',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Transfer complete'), findsOneWidget);
      expect(activated, isTrue);
    },
  );

  testWidgets('leaving the journey cancels an in-flight transfer run', (
    tester,
  ) async {
    final qrPayload = payload(sessionId: 'cancel-on-close-session');
    final transcript = AuthenticatedMigrationChannelTranscript(
      sessionId: qrPayload.sessionId,
      newPhoneEphemeralPublicKey: qrPayload.newPhoneEphemeralPublicKey,
      oldPhonePeerId: 'old-phone-peer',
      authenticatedChannelBinding: 'authenticated-binding',
      authorizationNonce: 'authorized-nonce',
    );
    var runnerObservedCancellation = false;
    var runnerFinished = false;

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.oldPhone(
          secureKeyStore: FakeSecureKeyStore(),
          identityRepository: _FakeIdentityRepository(),
          initialScannedQr: qrPayload.toJsonString(),
          authorizeExport: (_) async =>
              (MigrationExportAuthorizationResult.authorized, transcript),
          transferKeepAlive: MigrationTransferKeepAlive(
            invoker: (method, args) async {},
          ),
          runTransfer:
              ({
                required request,
                required onProgress,
                required isCancelled,
                onSegmentProgress,
              }) async {
                // Long-running transfer that observes cancellation at its
                // checkpoints, like the real runtime does between commands.
                while (!isCancelled()) {
                  await Future<void>.delayed(const Duration(milliseconds: 10));
                }
                runnerObservedCancellation = true;
                runnerFinished = true;
                return const AccountMigrationTransferResult.cancelled();
              },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(
      find.byKey(const ValueKey('account-migration-start-transfer')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(runnerFinished, isFalse, reason: 'transfer must still be running');

    // Leaving the journey (dispose) must flag cancellation so the run exits
    // at its next checkpoint instead of holding the export network pause.
    await tester.pumpWidget(wrap(const SizedBox()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(runnerObservedCancellation, isTrue);
  });

  testWidgets('leaving the journey stops the active receiver', (tester) async {
    final qrPayload = payload(sessionId: 'receiver-stop-session');
    final stoppedSessions = <String>[];

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.newPhone(
          bridge: _FakeBridge(),
          secureKeyStore: FakeSecureKeyStore(),
          buildQrPayload: () async => (
            BuildMigrationQrPayloadResult.success,
            MigrationQrBuildOutput(
              payload: qrPayload,
              qrJson: qrPayload.toJsonString(),
            ),
          ),
          startReceiver: (_) async =>
              const AccountMigrationReceiverStartResult.started(),
          stopReceiver: (sessionId) async => stoppedSessions.add(sessionId),
          transferKeepAlive: MigrationTransferKeepAlive(
            invoker: (method, args) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(stoppedSessions, isEmpty);

    // Dispose: the receiver server must not be left running.
    await tester.pumpWidget(wrap(const SizedBox()));
    await tester.pump();

    expect(stoppedSessions, ['receiver-stop-session']);
  });

  testWidgets('new-phone receiving segments shows determinate bar', (
    tester,
  ) async {
    final qrPayload = payload(sessionId: 'progress-receiver');
    final events = StreamController<AccountMigrationReceiverEvent>.broadcast();
    addTearDown(events.close);

    await tester.pumpWidget(
      wrap(
        AccountMigrationJourneyWired.newPhone(
          bridge: _FakeBridge(),
          secureKeyStore: FakeSecureKeyStore(),
          buildQrPayload: () async => (
            BuildMigrationQrPayloadResult.success,
            MigrationQrBuildOutput(
              payload: qrPayload,
              qrJson: qrPayload.toJsonString(),
            ),
          ),
          startReceiver: (_) async =>
              const AccountMigrationReceiverStartResult.started(),
          receiverEvents: events.stream,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    events.add(
      const AccountMigrationReceiverEvent.receivingSegment(
        sessionId: 'progress-receiver',
        segmentIndex: 11,
        segmentCount: 34,
        verifiedCount: 12,
      ),
    );
    await tester.pump();

    expect(find.text('Transferring database'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('account-migration-progress-bar')),
    );
    expect(bar.value, closeTo(12 / 34, 0.001));
    expect(find.text('12 of 34'), findsOneWidget);

    // Later events advance the bar monotonically.
    events.add(
      const AccountMigrationReceiverEvent.receivingSegment(
        sessionId: 'progress-receiver',
        segmentIndex: 33,
        segmentCount: 34,
        verifiedCount: 34,
      ),
    );
    await tester.pump();
    final fullBar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('account-migration-progress-bar')),
    );
    expect(fullBar.value, closeTo(1.0, 0.001));
  });
}
