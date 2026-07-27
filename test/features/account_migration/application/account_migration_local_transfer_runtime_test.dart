import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_local_transfer_runtime.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/account_migration/application/migration_storage_preflight.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_coordinator.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_segmented_transfer_service.dart';
import 'package:flutter_app/features/account_migration/application/migration_transfer_checkpoint_store.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_cutover_repository.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_pairing_session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountMigrationLocalTransferRuntime', () {
    late Map<String, LocalPeer> registry;
    late _MemoryPairingSessionRepository pairingRepo;
    late LocalWsServer newPhoneServer;
    late LocalWsServer oldPhoneServer;
    late _SharedFakeDiscovery newPhoneDiscovery;
    late _SharedFakeDiscovery oldPhoneDiscovery;

    setUp(() {
      registry = <String, LocalPeer>{};
      pairingRepo = _MemoryPairingSessionRepository();
      newPhoneServer = LocalWsServer();
      oldPhoneServer = LocalWsServer();
      newPhoneDiscovery = _SharedFakeDiscovery(registry);
      oldPhoneDiscovery = _SharedFakeDiscovery(registry);
    });

    tearDown(() async {
      debugSetFlowEventSink(null);
      await newPhoneServer.stop();
      await oldPhoneServer.stop();
      newPhoneDiscovery.dispose();
      oldPhoneDiscovery.dispose();
    });

    test(
      'pairs over migration local route and reports exporter gap precisely',
      () async {
        final output = await _savePendingSession(pairingRepo);
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
        );
        newPhoneServer.configureMigrationTransferHandler(
          newRuntime.handleMigrationTransferRequest,
        );
        final startResult = await newRuntime.startNewPhoneReceiver(output);
        expect(startResult.isStarted, isTrue);

        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(result.isSuccess, isFalse);
        expect(
          result.failureCode,
          AccountMigrationTransferFailureCode.bundleExporterUnavailable,
        );
        expect(
          result.safeMessage,
          contains('cannot assemble the account bundle yet'),
        );
      },
    );

    test('returns typed bundle failure when old phone export throws', () async {
      final output = await _savePendingSession(pairingRepo);
      final receiver = _RecordingBundleReceiver(onSegment: (_) {});
      final newRuntime = AccountMigrationLocalTransferRuntime(
        discovery: newPhoneDiscovery,
        wsServer: newPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleReceiver: receiver,
      );
      newPhoneServer.configureMigrationTransferHandler(
        newRuntime.handleMigrationTransferRequest,
      );
      expect(
        (await newRuntime.startNewPhoneReceiver(output)).isStarted,
        isTrue,
      );

      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => throw StateError(
          'file changed while assembling migration bundle: Documents/x.jpg',
        ),
      );

      final result = await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.bundleExporterUnavailable,
      );
      expect(
        result.safeMessage,
        contains('old phone could not assemble the account bundle'),
      );
      expect(
        flowEvents,
        contains(
          predicate<Map<String, dynamic>>((event) {
            final details = event['details'] as Map<String, dynamic>;
            return event['event'] ==
                    'ACCOUNT_MIGRATION_TRANSFER_BUNDLE_SOURCE_FAILED' &&
                details['sessionId'] == output.payload.sessionId &&
                details['errorType'] == 'StateError' &&
                details['reason'] == 'fileChangedWhileAssembling';
          }),
        ),
      );
    });

    test(
      'sends manifest and segments when bundle seams are supplied',
      () async {
        final output = await _savePendingSession(pairingRepo);
        final receivedSegments = <int>[];
        final receiver = _RecordingBundleReceiver(
          onSegment: (segment) => receivedSegments.add(segment.index),
        );
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleReceiver: receiver,
        );
        newPhoneServer.configureMigrationTransferHandler(
          newRuntime.handleMigrationTransferRequest,
        );
        expect(
          (await newRuntime.startNewPhoneReceiver(output)).isStarted,
          isTrue,
        );

        final crypto = _DeterministicSegmentCrypto();
        final plaintextSegments = {
          0: Uint8List.fromList(utf8.encode('db-1')),
          1: Uint8List.fromList(utf8.encode('db-2')),
        };
        final manifest = _manifestFor(
          plaintextSegments: plaintextSegments,
          sessionId: output.payload.sessionId,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => AccountMigrationLocalTransferBundle(
            manifest: manifest,
            plaintextSegments: plaintextSegments,
          ),
          transferService: MigrationSegmentedTransferService(
            crypto: crypto,
            checkpointStore: InMemoryMigrationTransferCheckpointStore(),
          ),
        );

        final progress = <AccountMigrationTransferStep>[];
        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: progress.add,
          isCancelled: () => false,
        );

        expect(result.isSuccess, isTrue);
        expect(progress, contains(AccountMigrationTransferStep.connecting));
        expect(progress, contains(AccountMigrationTransferStep.finishing));
        expect(receiver.acceptedManifest?.bundleId, 'bundle-1');
        expect(receivedSegments, [0, 1]);
      },
    );

    test('sends pre-encrypted bundle segments without re-encrypting', () async {
      final output = await _savePendingSession(pairingRepo);
      final receivedSegments = <int>[];
      final receiver = _RecordingBundleReceiver(
        onSegment: (segment) => receivedSegments.add(segment.index),
      );
      final newRuntime = AccountMigrationLocalTransferRuntime(
        discovery: newPhoneDiscovery,
        wsServer: newPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleReceiver: receiver,
      );
      newPhoneServer.configureMigrationTransferHandler(
        newRuntime.handleMigrationTransferRequest,
      );
      expect(
        (await newRuntime.startNewPhoneReceiver(output)).isStarted,
        isTrue,
      );

      final plaintextSegments = {
        0: Uint8List.fromList(utf8.encode('p001')),
        1: Uint8List.fromList(utf8.encode('p002')),
      };
      final manifest = _manifestFor(
        plaintextSegments: plaintextSegments,
        sessionId: output.payload.sessionId,
      );
      final encryptedSegments = [
        for (final descriptor in manifest.orderedSegments)
          _encryptedSegmentFor(
            descriptor: descriptor,
            manifest: manifest,
            plaintext: plaintextSegments[descriptor.index]!,
          ),
      ];
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => AccountMigrationLocalTransferBundle(
          manifest: manifest,
          encryptedSegments: encryptedSegments,
        ),
      );

      final result = await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.isSuccess, isTrue);
      expect(receiver.acceptedManifest?.bundleId, 'bundle-1');
      expect(receivedSegments, [0, 1]);
    });

    test('P1-1/P1-3: reuses one HTTP client across transfer posts and keeps '
        'sender telemetry fields stable', () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      final httpClient = _CloseCountingHttpClient();
      var httpClientFactoryCalls = 0;
      final output = await _savePendingSession(
        pairingRepo,
        sessionId: 'connection-reuse',
      );
      final remotePorts = <int>{};
      final receivedSegments = <int>[];
      final receiver = _RecordingBundleReceiver(
        onSegment: (segment) => receivedSegments.add(segment.index),
      );
      final newRuntime = AccountMigrationLocalTransferRuntime(
        discovery: newPhoneDiscovery,
        wsServer: newPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleReceiver: receiver,
      );
      newPhoneServer.configureMigrationTransferHandler((request, path) async {
        final remotePort = request.connectionInfo?.remotePort;
        if (remotePort != null) {
          remotePorts.add(remotePort);
        }
        await newRuntime.handleMigrationTransferRequest(request, path);
      });
      expect(
        (await newRuntime.startNewPhoneReceiver(output)).isStarted,
        isTrue,
      );

      final bundle = _preparedBundle(
        sessionId: output.payload.sessionId,
        segmentCount: 6,
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => bundle,
        httpClientFactory: () {
          httpClientFactoryCalls += 1;
          return httpClient;
        },
      );

      final result = await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.isSuccess, isTrue, reason: result.safeMessage);
      expect(receivedSegments, List<int>.generate(6, (i) => i));
      expect(httpClientFactoryCalls, 1);
      expect(httpClient.closeCount, 1);
      expect(httpClient.forceCloseCount, 1);
      expect(
        remotePorts.length,
        lessThanOrEqualTo(2),
        reason:
            'the sender should keep one HTTP session alive instead of '
            'opening a fresh TCP port for every command',
      );

      Map<String, dynamic> detailsOf(Map<String, dynamic> event) =>
          Map<String, dynamic>.from(event['details'] as Map);
      final postStarts = flowEvents
          .where(
            (event) =>
                event['event'] == 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_START',
          )
          .map(detailsOf)
          .toList(growable: false);
      expect(postStarts.map((details) => details['command']).toList(), [
        'transcript',
        'manifest',
        for (var i = 0; i < 6; i++) 'segment',
        'complete',
      ]);
      for (final start in postStarts) {
        expect(start['commandStage'], isA<String>());
        expect(start['payloadBytes'], isA<int>());
        expect(start['timeoutMs'], isA<int>());
        expect(start['httpTimeoutMs'], isA<int>());
      }
      final responses = flowEvents
          .where(
            (event) =>
                event['event'] ==
                'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_RESPONSE',
          )
          .map(detailsOf)
          .toList(growable: false);
      expect(responses, hasLength(postStarts.length));
      for (final response in responses) {
        expect(response['commandStage'], isA<String>());
        expect(response['connectMs'], isA<int>());
        expect(response['bodyWriteMs'], isA<int>());
        expect(response['responseWaitMs'], isA<int>());
        expect(response['drainMs'], isA<int>());
      }
    });

    test(
      'P1-1: closes reused HTTP client exactly once on transfer failure',
      () async {
        final output = await _savePendingSession(
          pairingRepo,
          sessionId: 'connection-reuse-failure',
        );
        final receiver = _RejectingSegmentReceiver(rejectFromIndex: 1);
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleReceiver: receiver,
        );
        newPhoneServer.configureMigrationTransferHandler(
          newRuntime.handleMigrationTransferRequest,
        );
        expect(
          (await newRuntime.startNewPhoneReceiver(output)).isStarted,
          isTrue,
        );
        final httpClient = _CloseCountingHttpClient();
        var httpClientFactoryCalls = 0;
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => _preparedBundle(
            sessionId: output.payload.sessionId,
            segmentCount: 3,
          ),
          httpClientFactory: () {
            httpClientFactoryCalls += 1;
            return httpClient;
          },
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(result.isSuccess, isFalse);
        expect(
          result.failureCode,
          AccountMigrationTransferFailureCode.transferRejected,
        );
        expect(httpClientFactoryCalls, 1);
        expect(httpClient.closeCount, 1);
        expect(httpClient.forceCloseCount, 1);
      },
    );

    test('exchanges cutover proofs before old phone reports success', () async {
      final output = await _savePendingSession(pairingRepo);
      final receiver = _CutoverRecordingBundleReceiver();
      final newRuntime = AccountMigrationLocalTransferRuntime(
        discovery: newPhoneDiscovery,
        wsServer: newPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleReceiver: receiver,
      );
      newPhoneServer.configureMigrationTransferHandler(
        newRuntime.handleMigrationTransferRequest,
      );
      expect(
        (await newRuntime.startNewPhoneReceiver(output)).isStarted,
        isTrue,
      );

      final plaintextSegments = {0: Uint8List.fromList(utf8.encode('p001'))};
      final manifest = _manifestFor(
        plaintextSegments: plaintextSegments,
        sessionId: output.payload.sessionId,
      );
      final encryptedSegments = [
        for (final descriptor in manifest.orderedSegments)
          _encryptedSegmentFor(
            descriptor: descriptor,
            manifest: manifest,
            plaintext: plaintextSegments[descriptor.index]!,
          ),
      ];
      final oldAuthority = _MemoryAuthorityRepository();
      final oldCutover = _MemoryCutoverRepository();
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => AccountMigrationLocalTransferBundle(
          manifest: manifest,
          encryptedSegments: encryptedSegments,
        ),
        oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
          authorityRepository: oldAuthority,
          cutoverRepository: oldCutover,
          now: _fixedNow,
        ),
        oldPhoneLeaseCleanup: _noopLeaseCleanup(),
      );

      final result = await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.isSuccess, isTrue);
      expect(receiver.oldBlockProof?.provesOldNetworkBlocked, isTrue);
      expect(
        receiver.oldBlockProof?.deviceRole,
        MigrationCutoverDeviceRole.oldPhone,
      );
      expect(
        oldAuthority.saved?.state,
        AccountMigrationAuthorityState.migratedOut,
      );
      expect(oldCutover.saved?.oldMigratedOutCommitted, isTrue);
      // Export quiesce ordering: paused before the snapshot, superseded by
      // the cutover block, and never reverted to active after a successful
      // handoff.
      final authorityStates = oldAuthority.history
          .map((record) => record.state)
          .toList(growable: false);
      expect(
        authorityStates.first,
        AccountMigrationAuthorityState.migrationExportingNetworkPaused,
      );
      expect(
        authorityStates.indexOf(
          AccountMigrationAuthorityState.migrationExportingNetworkPaused,
        ),
        lessThan(
          authorityStates.indexOf(
            AccountMigrationAuthorityState.migrationCutoverPendingBlocked,
          ),
        ),
      );
      expect(
        authorityStates,
        isNot(
          contains(
            AccountMigrationAuthorityState.migrationFailedActiveRestored,
          ),
        ),
      );
    });

    test(
      'does not block old phone when receiver lacks cutover support',
      () async {
        final output = await _savePendingSession(pairingRepo);
        final receiver = _RecordingBundleReceiver(onSegment: (_) {});
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleReceiver: receiver,
        );
        newPhoneServer.configureMigrationTransferHandler(
          newRuntime.handleMigrationTransferRequest,
        );
        expect(
          (await newRuntime.startNewPhoneReceiver(output)).isStarted,
          isTrue,
        );

        final plaintextSegments = {0: Uint8List.fromList(utf8.encode('p001'))};
        final manifest = _manifestFor(
          plaintextSegments: plaintextSegments,
          sessionId: output.payload.sessionId,
        );
        final encryptedSegments = [
          for (final descriptor in manifest.orderedSegments)
            _encryptedSegmentFor(
              descriptor: descriptor,
              manifest: manifest,
              plaintext: plaintextSegments[descriptor.index]!,
            ),
        ];
        final oldAuthority = _MemoryAuthorityRepository();
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => AccountMigrationLocalTransferBundle(
            manifest: manifest,
            encryptedSegments: encryptedSegments,
          ),
          oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: oldAuthority,
            cutoverRepository: _MemoryCutoverRepository(),
            now: _fixedNow,
          ),
          oldPhoneLeaseCleanup: _noopLeaseCleanup(),
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(result.isSuccess, isFalse);
        expect(
          result.failureCode,
          AccountMigrationTransferFailureCode.cutoverRejected,
        );
        // The export pause is engaged before the snapshot, then restored on
        // failure; the old phone must end with active authority, never a
        // blocked/migrated-out state.
        expect(
          oldAuthority.saved?.state,
          AccountMigrationAuthorityState.migrationFailedActiveRestored,
        );
        expect(oldAuthority.saved?.state.isActiveAccountAuthority, isTrue);
        expect(
          oldAuthority.history.map((record) => record.state),
          isNot(
            contains(
              AccountMigrationAuthorityState.migrationCutoverPendingBlocked,
            ),
          ),
        );

        await newRuntime.stopNewPhoneReceiver(output.payload.sessionId);
        final stoppedRoute = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: {
            accountMigrationLocalTransferFieldOldBlockProof:
                _validOldBlockProof(output.payload.sessionId).toJson(),
          },
        );
        expect(stoppedRoute.statusCode, HttpStatus.notFound);
        expect(stoppedRoute.body?['reason'], 'unknown_session');
      },
    );

    test(
      'rejects transcript for a different new-phone ephemeral key',
      () async {
        final output = await _savePendingSession(pairingRepo);
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
        );
        newPhoneServer.configureMigrationTransferHandler(
          newRuntime.handleMigrationTransferRequest,
        );
        expect(
          (await newRuntime.startNewPhoneReceiver(output)).isStarted,
          isTrue,
        );

        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: AuthenticatedMigrationChannelTranscript(
              sessionId: output.payload.sessionId,
              newPhoneEphemeralPublicKey: 'wrong-public-key',
              oldPhonePeerId: 'old-phone-peer',
              authenticatedChannelBinding: 'binding',
              authorizationNonce: 'nonce',
            ),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(
          result.failureCode,
          AccountMigrationTransferFailureCode.receiverRejected,
        );
      },
    );
  });

  group('cutover proof routing recovery', () {
    late Map<String, LocalPeer> registry;
    late _MemoryPairingSessionRepository pairingRepo;
    late LocalWsServer newPhoneServer;
    late LocalWsServer oldPhoneServer;
    late _SharedFakeDiscovery newPhoneDiscovery;
    late _SharedFakeDiscovery oldPhoneDiscovery;
    late List<Map<String, dynamic>> flowEvents;

    setUp(() {
      registry = <String, LocalPeer>{};
      pairingRepo = _MemoryPairingSessionRepository();
      newPhoneServer = LocalWsServer();
      oldPhoneServer = LocalWsServer();
      newPhoneDiscovery = _SharedFakeDiscovery(registry);
      oldPhoneDiscovery = _SharedFakeDiscovery(registry);
      flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
    });

    tearDown(() async {
      debugSetFlowEventSink(null);
      await newPhoneServer.stop();
      await oldPhoneServer.stop();
      newPhoneDiscovery.dispose();
      oldPhoneDiscovery.dispose();
    });

    Future<(MigrationQrBuildOutput, AccountMigrationLocalTransferRuntime)>
    startNewPhone(
      AccountMigrationLocalBundleReceiver receiver, {
      required String sessionId,
      Duration replayGrace = const Duration(milliseconds: 80),
    }) async {
      final output = await _savePendingSession(
        pairingRepo,
        sessionId: sessionId,
      );
      final runtime = AccountMigrationLocalTransferRuntime(
        discovery: newPhoneDiscovery,
        wsServer: newPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleReceiver: receiver,
        committedProofReplayGrace: replayGrace,
      );
      newPhoneServer.configureMigrationTransferHandler(
        runtime.handleMigrationTransferRequest,
      );
      expect((await runtime.startNewPhoneReceiver(output)).isStarted, isTrue);
      return (output, runtime);
    }

    AccountMigrationLocalTransferRuntime oldPhoneRuntime({
      required MigrationQrBuildOutput output,
      Duration httpTimeout = const Duration(seconds: 1),
      Future<void> Function(Duration)? retryDelay,
    }) {
      return AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => _preparedBundle(
          sessionId: output.payload.sessionId,
          segmentCount: 1,
        ),
        oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
          authorityRepository: _MemoryAuthorityRepository(),
          cutoverRepository: _MemoryCutoverRepository(),
          now: _fixedNow,
        ),
        oldPhoneLeaseCleanup: _noopLeaseCleanup(),
        httpTimeout: httpTimeout,
        oldBlockProofRetryDelay: retryDelay,
      );
    }

    Future<AccountMigrationTransferResult> runTransfer(
      AccountMigrationLocalTransferRuntime runtime,
      MigrationQrBuildOutput output,
    ) {
      return runtime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );
    }

    Future<MigrationTransferManifest> prepareRawReceiver(
      MigrationQrBuildOutput output,
    ) async {
      final transcriptResponse = await _postMigrationJson(
        port: newPhoneServer.port!,
        sessionId: output.payload.sessionId,
        command: accountMigrationLocalTransferCommandTranscript,
        body: _transcript(output.payload).toJson(),
      );
      expect(transcriptResponse.statusCode, HttpStatus.ok);

      final manifest = _preparedBundle(
        sessionId: output.payload.sessionId,
        segmentCount: 1,
      ).manifest;
      final manifestResponse = await _postMigrationJson(
        port: newPhoneServer.port!,
        sessionId: output.payload.sessionId,
        command: accountMigrationLocalTransferCommandManifest,
        body: manifest.toJson(),
      );
      expect(manifestResponse.statusCode, HttpStatus.ok);
      return manifest;
    }

    test(
      'stop during complete defers removal and a successful complete remains cutover-routable',
      () async {
        final receiver = _PausableCompleteCutoverReceiver();
        final (output, newRuntime) = await startNewPhone(
          receiver,
          sessionId: 'stop-during-complete',
        );
        final oldRuntime = oldPhoneRuntime(output: output);

        final transferFuture = runTransfer(oldRuntime, output);
        await receiver.completeEntered.future.timeout(
          const Duration(seconds: 2),
        );

        await newRuntime.stopNewPhoneReceiver(output.payload.sessionId);
        expect(newPhoneDiscovery.advertisedPeerId, isNull);
        expect(
          registry,
          isNot(
            contains(
              accountMigrationLocalPeerIdForSession(output.payload.sessionId),
            ),
          ),
        );

        receiver.releaseComplete();
        final result = await transferFuture.timeout(const Duration(seconds: 2));

        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(receiver.completeCalls, 1);
        expect(receiver.oldBlockProofCalls, 1);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
    );

    test(
      'stop while complete body is still arriving preserves the proof route',
      () async {
        final receiver = _CutoverRecordingBundleReceiver();
        final (output, runtime) = await startNewPhone(
          receiver,
          sessionId: 'stop-during-complete-body-read',
          replayGrace: const Duration(milliseconds: 150),
        );
        final manifest = await prepareRawReceiver(output);
        final encodedBody = jsonEncode({
          accountMigrationLocalTransferFieldBundleId: manifest.bundleId,
        });
        final splitAt = encodedBody.length ~/ 2;
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.post(
          InternetAddress.loopbackIPv4.address,
          newPhoneServer.port!,
          '/migration/${Uri.encodeComponent(output.payload.sessionId)}/'
          '$accountMigrationLocalTransferCommandComplete',
        );
        request.headers.contentType = ContentType.json;
        request.contentLength = utf8.encode(encodedBody).length;
        request.write(encodedBody.substring(0, splitAt));
        await request.flush();

        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (!flowEvents.any((event) {
          if (event['event'] != 'ACCOUNT_MIGRATION_RECEIVER_REQUEST_START') {
            return false;
          }
          final details = Map<String, dynamic>.from(event['details'] as Map);
          return details['sessionId'] == output.payload.sessionId &&
              details['command'] ==
                  accountMigrationLocalTransferCommandComplete;
        })) {
          if (DateTime.now().isAfter(deadline)) {
            fail('complete request did not enter the runtime route');
          }
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }

        await runtime.stopNewPhoneReceiver(output.payload.sessionId);
        expect(newPhoneDiscovery.advertisedPeerId, isNull);
        request.write(encodedBody.substring(splitAt));
        final completeResponse = await request.close();
        await completeResponse.drain<void>();
        expect(completeResponse.statusCode, HttpStatus.ok);

        final proof = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: {
            accountMigrationLocalTransferFieldOldBlockProof:
                _validOldBlockProof(output.payload.sessionId).toJson(),
          },
        );
        expect(proof.statusCode, HttpStatus.ok);
        expect(receiver.completeCalls, 1);
        expect(receiver.oldBlockProofCalls, 1);
        await Future<void>.delayed(const Duration(milliseconds: 170));
      },
    );

    final failingCompleteCases = <({String name, Object? error})>[
      (name: 'false', error: null),
      (name: 'error', error: StateError('injected complete failure')),
    ];

    for (final failure in failingCompleteCases) {
      test('stop during in-flight complete settling ${failure.name} removes '
          'the route', () async {
        final receiver = _PausableFailingCompleteCutoverReceiver(
          error: failure.error,
        );
        final (output, runtime) = await startNewPhone(
          receiver,
          sessionId: 'stop-complete-${failure.name}',
        );
        final manifest = await prepareRawReceiver(output);
        final completeFuture = _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandComplete,
          body: {accountMigrationLocalTransferFieldBundleId: manifest.bundleId},
        );
        await receiver.completeEntered.future.timeout(
          const Duration(seconds: 2),
        );

        await runtime.stopNewPhoneReceiver(output.payload.sessionId);
        receiver.releaseComplete();
        final complete = await completeFuture.timeout(
          const Duration(seconds: 2),
        );

        expect(complete.statusCode, HttpStatus.badRequest);
        final proof = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: {
            accountMigrationLocalTransferFieldOldBlockProof:
                _validOldBlockProof(output.payload.sessionId).toJson(),
          },
        );
        expect(proof.statusCode, HttpStatus.notFound);
        expect(proof.body?['reason'], 'unknown_session');
        expect(receiver.completeCalls, 1);
        expect(receiver.oldBlockProofCalls, 0);
      });

      test(
        'duplicate complete joins an owner settling ${failure.name} even when '
        'its body finishes later',
        () async {
          final receiver = _PausableFailingCompleteCutoverReceiver(
            error: failure.error,
          );
          final (output, _) = await startNewPhone(
            receiver,
            sessionId: 'duplicate-complete-${failure.name}',
          );
          final manifest = await prepareRawReceiver(output);
          final completeBody = jsonEncode({
            accountMigrationLocalTransferFieldBundleId: manifest.bundleId,
          });
          final first = _postMigrationJson(
            port: newPhoneServer.port!,
            sessionId: output.payload.sessionId,
            command: accountMigrationLocalTransferCommandComplete,
            body: {
              accountMigrationLocalTransferFieldBundleId: manifest.bundleId,
            },
          );
          await receiver.completeEntered.future.timeout(
            const Duration(seconds: 2),
          );

          final client = HttpClient();
          addTearDown(() => client.close(force: true));
          final duplicateRequest = await client.post(
            InternetAddress.loopbackIPv4.address,
            newPhoneServer.port!,
            '/migration/${Uri.encodeComponent(output.payload.sessionId)}/'
            '$accountMigrationLocalTransferCommandComplete',
          );
          duplicateRequest.headers.contentType = ContentType.json;
          duplicateRequest.contentLength = utf8.encode(completeBody).length;
          final splitAt = completeBody.length ~/ 2;
          duplicateRequest.write(completeBody.substring(0, splitAt));
          await duplicateRequest.flush();

          final deadline = DateTime.now().add(const Duration(seconds: 2));
          while (flowEvents.where((event) {
                if (event['event'] !=
                    'ACCOUNT_MIGRATION_RECEIVER_REQUEST_START') {
                  return false;
                }
                final details = Map<String, dynamic>.from(
                  event['details'] as Map,
                );
                return details['sessionId'] == output.payload.sessionId &&
                    details['command'] ==
                        accountMigrationLocalTransferCommandComplete;
              }).length <
              2) {
            if (DateTime.now().isAfter(deadline)) {
              fail('duplicate complete did not enter the runtime route');
            }
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));

          receiver.releaseComplete();
          final firstResponse = await first.timeout(const Duration(seconds: 2));
          expect(firstResponse.statusCode, HttpStatus.badRequest);

          duplicateRequest.write(completeBody.substring(splitAt));
          final duplicateResponse = await duplicateRequest.close().timeout(
            const Duration(seconds: 2),
          );
          await duplicateResponse.drain<void>();

          expect(duplicateResponse.statusCode, HttpStatus.badRequest);
          expect(receiver.completeCalls, 1);
        },
      );
    }

    test(
      'stopNewPhoneReceiver rejects a later proof for a pre-verification session',
      () async {
        final receiver = _CutoverRecordingBundleReceiver();
        final (output, runtime) = await startNewPhone(
          receiver,
          sessionId: 'preverify-stop',
        );

        await runtime.stopNewPhoneReceiver(output.payload.sessionId);
        final response = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: {
            accountMigrationLocalTransferFieldOldBlockProof:
                _validOldBlockProof(output.payload.sessionId).toJson(),
          },
        );

        expect(response.statusCode, HttpStatus.notFound);
        expect(response.body?['reason'], 'unknown_session');
        expect(receiver.oldBlockProofCalls, 0);
      },
    );

    test(
      'pre-verification stop revokes the route when advertising cleanup throws',
      () async {
        final receiver = _CutoverRecordingBundleReceiver();
        final (output, runtime) = await startNewPhone(
          receiver,
          sessionId: 'stop-advertising-failure',
        );
        newPhoneDiscovery.stopAdvertisingError = StateError(
          'injected advertising cleanup failure',
        );

        await expectLater(
          runtime.stopNewPhoneReceiver(output.payload.sessionId),
          throwsStateError,
        );
        final response = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandTranscript,
          body: _transcript(output.payload).toJson(),
        );

        expect(response.statusCode, HttpStatus.notFound);
        expect(response.body?['reason'], 'unknown_session');
        expect(receiver.oldBlockProofCalls, 0);
      },
    );

    test(
      'committed proof stops advertising, replays during grace, then expires to unknown_session',
      () async {
        const replayGrace = Duration(milliseconds: 80);
        final receiver = _CutoverRecordingBundleReceiver();
        final (output, newRuntime) = await startNewPhone(
          receiver,
          sessionId: 'committed-replay-grace',
          replayGrace: replayGrace,
        );
        var activationCount = 0;
        final stopped = Completer<void>();
        final subscription = newRuntime.receiverEvents.listen((event) {
          if (event.type != AccountMigrationReceiverEventType.activated) {
            return;
          }
          activationCount += 1;
          unawaited(
            newRuntime.stopNewPhoneReceiver(event.sessionId).whenComplete(() {
              if (!stopped.isCompleted) stopped.complete();
            }),
          );
        });
        addTearDown(subscription.cancel);

        final result = await runTransfer(
          oldPhoneRuntime(output: output),
          output,
        );
        await stopped.future.timeout(const Duration(seconds: 2));

        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(newPhoneDiscovery.advertisedPeerId, isNull);
        expect(receiver.completeCalls, 1);
        expect(receiver.oldBlockProofCalls, 1);
        expect(activationCount, 1);

        final replay = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: {
            accountMigrationLocalTransferFieldOldBlockProof: receiver
                .oldBlockProof!
                .toJson(),
          },
        );
        expect(replay.statusCode, HttpStatus.ok);
        expect(
          replay.body?[accountMigrationLocalTransferFieldNewActiveProof],
          receiver.newActiveProof!.toJson(),
        );
        expect(receiver.completeCalls, 1);
        expect(receiver.oldBlockProofCalls, 1);
        expect(activationCount, 1);

        await Future<void>.delayed(
          replayGrace + const Duration(milliseconds: 60),
        );
        final expired = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: {
            accountMigrationLocalTransferFieldOldBlockProof: receiver
                .oldBlockProof!
                .toJson(),
          },
        );
        expect(expired.statusCode, HttpStatus.notFound);
        expect(expired.body?['reason'], 'unknown_session');
      },
    );

    test(
      'committed proof tombstone rejects manifest mutation without reaching receiver',
      () async {
        final receiver = _CutoverRecordingBundleReceiver();
        final (output, _) = await startNewPhone(
          receiver,
          sessionId: 'committed-manifest-rejected',
          replayGrace: const Duration(milliseconds: 180),
        );

        final result = await runTransfer(
          oldPhoneRuntime(output: output),
          output,
        );
        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(receiver.acceptManifestCalls, 1);

        final mutation = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandManifest,
          body: _preparedBundle(
            sessionId: output.payload.sessionId,
            segmentCount: 1,
          ).manifest.toJson(),
        );

        expect(mutation.statusCode, HttpStatus.conflict);
        expect(mutation.body?['reason'], 'session_finalizing');
        expect(receiver.acceptManifestCalls, 1);
        expect(receiver.oldBlockProofCalls, 1);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
    );

    test(
      'same-session restart during committed grace preserves replay proof',
      () async {
        final receiver = _CutoverRecordingBundleReceiver();
        final (output, runtime) = await startNewPhone(
          receiver,
          sessionId: 'committed-restart-rejected',
          replayGrace: const Duration(milliseconds: 220),
        );
        final result = await runTransfer(
          oldPhoneRuntime(output: output),
          output,
        );
        expect(result.isSuccess, isTrue, reason: result.safeMessage);

        final restart = await runtime.startNewPhoneReceiver(output);
        expect(restart.isStarted, isFalse);
        expect(
          restart.failureCode,
          AccountMigrationReceiverStartFailureCode.sessionUnavailable,
        );

        final replay = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: {
            accountMigrationLocalTransferFieldOldBlockProof: receiver
                .oldBlockProof!
                .toJson(),
          },
        );
        expect(replay.statusCode, HttpStatus.ok);
        expect(
          replay.body?[accountMigrationLocalTransferFieldNewActiveProof],
          receiver.newActiveProof!.toJson(),
        );
        expect(receiver.oldBlockProofCalls, 1);
        await Future<void>.delayed(const Duration(milliseconds: 240));
      },
    );

    final invalidNewActiveProofIdentities =
        <
          ({
            String field,
            MigrationCutoverRecord Function(MigrationCutoverRecord proof)
            mutate,
          })
        >[
          (
            field: 'sessionId',
            mutate: (proof) => proof.copyWith(sessionId: 'wrong-session'),
          ),
          (
            field: 'accountPeerId',
            mutate: (proof) =>
                proof.copyWith(accountPeerId: 'wrong-account-peer'),
          ),
          (
            field: 'role',
            mutate: (proof) =>
                proof.copyWith(deviceRole: MigrationCutoverDeviceRole.oldPhone),
          ),
          (
            field: 'devicePeerId',
            mutate: (proof) =>
                proof.copyWith(devicePeerId: 'wrong-new-phone-key'),
          ),
        ];

    for (final invalidIdentity in invalidNewActiveProofIdentities) {
      test('receiver rejects new-active proof with invalid '
          '${invalidIdentity.field} identity without activation', () async {
        final receiver = _MutatingNewActiveProofCutoverReceiver(
          invalidIdentity.mutate,
        );
        final (output, runtime) = await startNewPhone(
          receiver,
          sessionId: 'receiver-wrong-${invalidIdentity.field}',
        );
        final manifest = await prepareRawReceiver(output);
        final complete = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandComplete,
          body: {accountMigrationLocalTransferFieldBundleId: manifest.bundleId},
        );
        expect(complete.statusCode, HttpStatus.ok);

        var activationCount = 0;
        final subscription = runtime.receiverEvents.listen((event) {
          if (event.type == AccountMigrationReceiverEventType.activated) {
            activationCount += 1;
          }
        });
        addTearDown(subscription.cancel);
        final proofBody = {
          accountMigrationLocalTransferFieldOldBlockProof: _validOldBlockProof(
            output.payload.sessionId,
          ).toJson(),
        };

        final first = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: proofBody,
        );
        final retry = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: proofBody,
        );

        expect(first.statusCode, HttpStatus.badRequest);
        expect(first.body?['reason'], 'cutover_rejected');
        expect(retry.statusCode, HttpStatus.badRequest);
        expect(retry.body?['reason'], 'cutover_rejected');
        expect(receiver.oldBlockProofCalls, 2);
        expect(activationCount, 0);
        expect(newPhoneDiscovery.advertisedPeerId, isNotNull);
        expect(
          registry,
          contains(
            accountMigrationLocalPeerIdForSession(output.payload.sessionId),
          ),
        );
      });
    }

    for (final invalidIdentity in invalidNewActiveProofIdentities) {
      test(
        'sender rejects new-active proof with invalid '
        '${invalidIdentity.field} identity without migrated-out commit',
        () async {
          final sessionId = 'sender-wrong-${invalidIdentity.field}';
          final output = await _savePendingSession(
            pairingRepo,
            sessionId: sessionId,
          );
          final wrongProof = invalidIdentity.mutate(
            _validNewActiveProof(
              sessionId: sessionId,
              devicePeerId: output.payload.newPhoneEphemeralPublicKey,
            ),
          );
          var proofAttempts = 0;
          newPhoneServer.configureMigrationTransferHandler((
            request,
            path,
          ) async {
            await utf8.decoder.bind(request).join();
            final command = request.uri.pathSegments.last;
            final response = <String, Object?>{'ok': true};
            if (command == accountMigrationLocalTransferCommandTranscript) {
              response[accountMigrationLocalTransferFieldOldBlockProofReplaySafe] =
                  true;
            } else if (command ==
                accountMigrationLocalTransferCommandComplete) {
              response[accountMigrationLocalTransferFieldCutoverReady] = true;
              response[accountMigrationLocalTransferFieldOldBlockProofReplaySafe] =
                  true;
            } else if (command ==
                accountMigrationLocalTransferCommandOldBlockProof) {
              proofAttempts += 1;
              response[accountMigrationLocalTransferFieldNewActiveProof] =
                  wrongProof.toJson();
            }
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(response));
            await request.response.close();
          });
          final port = await newPhoneServer.start();
          await newPhoneDiscovery.startAdvertising(
            accountMigrationLocalPeerIdForSession(sessionId),
            port,
          );
          final oldAuthority = _MemoryAuthorityRepository();
          final oldCutover = _MemoryCutoverRepository();
          final oldRuntime = AccountMigrationLocalTransferRuntime(
            discovery: oldPhoneDiscovery,
            wsServer: oldPhoneServer,
            pairingSessionRepository: pairingRepo,
            bundleSource: (_) async =>
                _preparedBundle(sessionId: sessionId, segmentCount: 1),
            oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
              authorityRepository: oldAuthority,
              cutoverRepository: oldCutover,
              now: _fixedNow,
            ),
            oldPhoneLeaseCleanup: _noopLeaseCleanup(),
          );

          final result = await runTransfer(oldRuntime, output);

          expect(result.isSuccess, isFalse);
          expect(
            result.failureCode,
            AccountMigrationTransferFailureCode.cutoverRejected,
          );
          expect(
            oldAuthority.saved?.state,
            AccountMigrationAuthorityState.migrationCutoverPendingBlocked,
          );
          expect(oldCutover.saved?.oldMigratedOutCommitted, isFalse);
          expect(proofAttempts, 1);
        },
      );
    }

    final retryableProofFailureCases = <({String name, Object? error})>[
      (name: 'null', error: null),
      (name: 'error', error: StateError('injected proof settlement failure')),
    ];

    for (final failure in retryableProofFailureCases) {
      test('replay-safe proof retries one ${failure.name} receiver rejection '
          'without stranding cutover', () async {
        final receiver = _RetryableProofCutoverReceiver(error: failure.error);
        final (output, runtime) = await startNewPhone(
          receiver,
          sessionId: 'proof-rejection-retry-${failure.name}',
          replayGrace: const Duration(milliseconds: 120),
        );
        var activationCount = 0;
        final subscription = runtime.receiverEvents.listen((event) {
          if (event.type == AccountMigrationReceiverEventType.activated) {
            activationCount += 1;
          }
        });
        addTearDown(subscription.cancel);
        final requestedDelays = <Duration>[];
        final result = await runTransfer(
          oldPhoneRuntime(
            output: output,
            retryDelay: (delay) async {
              requestedDelays.add(delay);
            },
          ),
          output,
        );

        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(receiver.completeCalls, 1);
        expect(receiver.oldBlockProofCalls, 2);
        expect(requestedDelays, [const Duration(milliseconds: 250)]);
        expect(activationCount, 1);
        await Future<void>.delayed(const Duration(milliseconds: 140));
      });
    }

    test(
      'complete response loss retries once after early replay-safe negotiation',
      () async {
        final receiver = _PausableCompleteCutoverReceiver();
        final (output, _) = await startNewPhone(
          receiver,
          sessionId: 'complete-response-loss-retry',
          replayGrace: const Duration(milliseconds: 120),
        );
        final oldRuntime = oldPhoneRuntime(
          output: output,
          httpTimeout: const Duration(milliseconds: 30),
        );
        final transferFuture = runTransfer(oldRuntime, output);
        final safetyRelease = Timer(
          const Duration(seconds: 1),
          receiver.releaseComplete,
        );
        try {
          await receiver.completeEntered.future.timeout(
            const Duration(seconds: 2),
          );
          final deadline = DateTime.now().add(const Duration(seconds: 2));
          while (flowEvents.where((event) {
                if (event['event'] !=
                    'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_START') {
                  return false;
                }
                final details = Map<String, dynamic>.from(
                  event['details'] as Map,
                );
                return details['sessionId'] == output.payload.sessionId &&
                    details['command'] ==
                        accountMigrationLocalTransferCommandComplete;
              }).length <
              2) {
            if (DateTime.now().isAfter(deadline)) {
              fail('sender did not issue the replay-safe complete retry');
            }
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
          receiver.releaseComplete();
          final result = await transferFuture.timeout(
            const Duration(seconds: 2),
          );

          final completeAttempts = flowEvents.where((event) {
            if (event['event'] !=
                'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_START') {
              return false;
            }
            final details = Map<String, dynamic>.from(event['details'] as Map);
            return details['sessionId'] == output.payload.sessionId &&
                details['command'] ==
                    accountMigrationLocalTransferCommandComplete;
          }).length;
          expect(result.isSuccess, isTrue, reason: result.safeMessage);
          expect(completeAttempts, 2);
          expect(receiver.completeCalls, 1);
          expect(receiver.oldBlockProofCalls, 1);
          await Future<void>.delayed(const Duration(milliseconds: 140));
        } finally {
          safetyRelease.cancel();
          receiver.releaseComplete();
        }
      },
    );

    test(
      'complete transport loss is not retried without early replay capability',
      () async {
        const sessionId = 'complete-no-replay-capability';
        final output = await _savePendingSession(
          pairingRepo,
          sessionId: sessionId,
        );
        newPhoneServer.configureMigrationTransferHandler((request, path) async {
          await utf8.decoder.bind(request).join();
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'ok': true}));
          await request.response.close();
        });
        final port = await newPhoneServer.start();
        await newPhoneDiscovery.startAdvertising(
          accountMigrationLocalPeerIdForSession(sessionId),
          port,
        );
        final failingClient = _CommandFailingHttpClient(
          accountMigrationLocalTransferCommandComplete,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async =>
              _preparedBundle(sessionId: sessionId, segmentCount: 1),
          httpClientFactory: () => failingClient,
        );

        final result = await runTransfer(oldRuntime, output);

        expect(result.isSuccess, isFalse);
        expect(
          result.failureCode,
          AccountMigrationTransferFailureCode.localTransferTimedOut,
        );
        expect(failingClient.failedCommandAttempts, 1);
      },
    );

    test(
      'response-lost committed proof retries once without duplicate import or activation',
      () async {
        final receiver = _PausableProofCutoverReceiver();
        final (output, newRuntime) = await startNewPhone(
          receiver,
          sessionId: 'response-loss-retry',
          replayGrace: const Duration(milliseconds: 300),
        );
        var activationCount = 0;
        final activationStopped = Completer<void>();
        final subscription = newRuntime.receiverEvents.listen((event) {
          if (event.type != AccountMigrationReceiverEventType.activated) {
            return;
          }
          activationCount += 1;
          unawaited(
            newRuntime.stopNewPhoneReceiver(event.sessionId).whenComplete(() {
              if (!activationStopped.isCompleted) {
                activationStopped.complete();
              }
            }),
          );
        });
        addTearDown(subscription.cancel);

        final requestedDelays = <Duration>[];
        final oldRuntime = oldPhoneRuntime(
          output: output,
          httpTimeout: const Duration(milliseconds: 25),
          retryDelay: (requested) async {
            requestedDelays.add(requested);
            receiver.releaseProof();
            await activationStopped.future.timeout(const Duration(seconds: 1));
            await Future<void>.delayed(const Duration(milliseconds: 1));
          },
        );
        final safetyRelease = Timer(
          const Duration(seconds: 1),
          receiver.releaseProof,
        );
        final AccountMigrationTransferResult result;
        try {
          result = await runTransfer(
            oldRuntime,
            output,
          ).timeout(const Duration(seconds: 2));
        } finally {
          safetyRelease.cancel();
          receiver.releaseProof();
        }

        final proofAttempts = flowEvents.where((event) {
          if (event['event'] != 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_START') {
            return false;
          }
          final details = Map<String, dynamic>.from(event['details'] as Map);
          return details['command'] ==
              accountMigrationLocalTransferCommandOldBlockProof;
        }).length;
        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(proofAttempts, 2);
        expect(requestedDelays, [const Duration(milliseconds: 250)]);
        expect(receiver.acceptInvocations, 1);
        expect(receiver.completeCalls, 1);
        expect(activationCount, 1);
        await Future<void>.delayed(const Duration(milliseconds: 320));
      },
    );

    test(
      'old-block retry exhausts at two attempts and is disabled without receiver capability',
      () async {
        Future<(AccountMigrationTransferResult, int, List<Duration>)>
        runScenario({
          required String sessionId,
          required bool advertiseReplayCapability,
        }) async {
          final registry = <String, LocalPeer>{};
          final receiverDiscovery = _SharedFakeDiscovery(registry);
          final senderDiscovery = _SharedFakeDiscovery(registry);
          final receiverServer = LocalWsServer();
          final senderServer = LocalWsServer();
          final failingClient = _ProofFailingHttpClient();
          final delays = <Duration>[];
          try {
            receiverServer.configureMigrationTransferHandler((
              request,
              path,
            ) async {
              await utf8.decoder.bind(request).join();
              final command = request.uri.pathSegments.last;
              final response = <String, Object?>{'ok': true};
              if (command == accountMigrationLocalTransferCommandComplete) {
                response[accountMigrationLocalTransferFieldCutoverReady] = true;
                if (advertiseReplayCapability) {
                  response[accountMigrationLocalTransferFieldOldBlockProofReplaySafe] =
                      true;
                }
              }
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(jsonEncode(response));
              await request.response.close();
            });
            final port = await receiverServer.start();
            await receiverDiscovery.startAdvertising(
              accountMigrationLocalPeerIdForSession(sessionId),
              port,
            );
            final output = await _savePendingSession(
              _MemoryPairingSessionRepository(),
              sessionId: sessionId,
            );
            final runtime = AccountMigrationLocalTransferRuntime(
              discovery: senderDiscovery,
              wsServer: senderServer,
              pairingSessionRepository: _MemoryPairingSessionRepository(),
              bundleSource: (_) async =>
                  _preparedBundle(sessionId: sessionId, segmentCount: 1),
              oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
                authorityRepository: _MemoryAuthorityRepository(),
                cutoverRepository: _MemoryCutoverRepository(),
                now: _fixedNow,
              ),
              oldPhoneLeaseCleanup: _noopLeaseCleanup(),
              httpClientFactory: () => failingClient,
              oldBlockProofRetryDelay: (requested) async {
                delays.add(requested);
              },
            );

            final AccountMigrationTransferResult result = await runtime
                .runOldPhoneTransfer(
                  request: AccountMigrationTransferRequest(
                    transcript: _transcript(output.payload),
                  ),
                  onProgress: (_) {},
                  isCancelled: () => false,
                );
            return (result, failingClient.proofAttempts, delays);
          } finally {
            await receiverServer.stop();
            await senderServer.stop();
            receiverDiscovery.dispose();
            senderDiscovery.dispose();
          }
        }

        final withCapability = await runScenario(
          sessionId: 'bounded-retry-capable',
          advertiseReplayCapability: true,
        );
        expect(withCapability.$1.isSuccess, isFalse);
        expect(withCapability.$2, 2);
        expect(withCapability.$3, [const Duration(milliseconds: 250)]);

        final withoutCapability = await runScenario(
          sessionId: 'bounded-retry-old-receiver',
          advertiseReplayCapability: false,
        );
        expect(withoutCapability.$1.isSuccess, isFalse);
        expect(withoutCapability.$2, 1);
        expect(withoutCapability.$3, isEmpty);
      },
    );

    test(
      'concurrent old-block proofs single-flight one receiver cutover and one activation',
      () async {
        final receiver = _PausableProofCutoverReceiver();
        final (output, newRuntime) = await startNewPhone(
          receiver,
          sessionId: 'concurrent-proof-single-flight',
          replayGrace: const Duration(milliseconds: 120),
        );
        final manifest = await prepareRawReceiver(output);
        final complete = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandComplete,
          body: {accountMigrationLocalTransferFieldBundleId: manifest.bundleId},
        );
        expect(complete.statusCode, HttpStatus.ok);
        expect(
          complete
              .body?[accountMigrationLocalTransferFieldOldBlockProofReplaySafe],
          isTrue,
        );

        var activationCount = 0;
        final subscription = newRuntime.receiverEvents.listen((event) {
          if (event.type == AccountMigrationReceiverEventType.activated) {
            activationCount += 1;
          }
        });
        addTearDown(subscription.cancel);

        final validProof = _validOldBlockProof(output.payload.sessionId);
        final first = _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: {
            accountMigrationLocalTransferFieldOldBlockProof: validProof
                .toJson(),
          },
        );
        await receiver.proofEntered.future.timeout(const Duration(seconds: 2));
        final inFlightMutation = await _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandManifest,
          body: manifest.toJson(),
        );
        expect(inFlightMutation.statusCode, HttpStatus.conflict);
        expect(inFlightMutation.body?['reason'], 'session_finalizing');
        expect(receiver.acceptManifestCalls, 1);
        final second = _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: {
            accountMigrationLocalTransferFieldOldBlockProof: validProof
                .toJson(),
          },
        );
        final invalid = _postMigrationJson(
          port: newPhoneServer.port!,
          sessionId: output.payload.sessionId,
          command: accountMigrationLocalTransferCommandOldBlockProof,
          body: {
            accountMigrationLocalTransferFieldOldBlockProof: {
              'version': MigrationCutoverRecord.currentVersion + 1,
            },
          },
        );

        final _TestMigrationHttpResponse invalidResponse;
        try {
          invalidResponse = await invalid.timeout(const Duration(seconds: 1));
        } finally {
          receiver.releaseProof();
        }
        expect(invalidResponse.statusCode, HttpStatus.badRequest);
        expect(invalidResponse.body?['reason'], 'invalid_old_block_proof');

        final responses = await Future.wait([first, second]);
        expect(responses.map((response) => response.statusCode), [
          HttpStatus.ok,
          HttpStatus.ok,
        ]);
        expect(
          responses.map(
            (response) => response
                .body?[accountMigrationLocalTransferFieldNewActiveProof],
          ),
          everyElement(receiver.newActiveProof!.toJson()),
        );
        expect(receiver.acceptInvocations, 1);
        expect(receiver.oldBlockProofCalls, 1);
        expect(activationCount, 1);
        await Future<void>.delayed(const Duration(milliseconds: 140));
      },
    );
  });

  group('local transfer timeout classification and telemetry', () {
    late Map<String, LocalPeer> registry;
    late _MemoryPairingSessionRepository pairingRepo;
    late LocalWsServer newPhoneServer;
    late LocalWsServer oldPhoneServer;
    late _SharedFakeDiscovery newPhoneDiscovery;
    late _SharedFakeDiscovery oldPhoneDiscovery;
    late List<Map<String, dynamic>> flowEvents;

    setUp(() {
      registry = <String, LocalPeer>{};
      pairingRepo = _MemoryPairingSessionRepository();
      newPhoneServer = LocalWsServer();
      oldPhoneServer = LocalWsServer();
      newPhoneDiscovery = _SharedFakeDiscovery(registry);
      oldPhoneDiscovery = _SharedFakeDiscovery(registry);
      flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
    });

    tearDown(() async {
      debugSetFlowEventSink(null);
      await newPhoneServer.stop();
      await oldPhoneServer.stop();
      newPhoneDiscovery.dispose();
      oldPhoneDiscovery.dispose();
    });

    List<Map<String, dynamic>> eventsNamed(String name) => flowEvents
        .where((event) => event['event'] == name)
        .toList(growable: false);

    Map<String, dynamic> detailsOf(Map<String, dynamic> event) =>
        Map<String, dynamic>.from(event['details'] as Map);

    const downstreamCommandTimeout = Duration(seconds: 1);
    const downstreamCommandDelay = Duration(milliseconds: 1500);

    Future<(MigrationQrBuildOutput, AccountMigrationLocalTransferRuntime)>
    startNewPhone(
      AccountMigrationLocalBundleReceiver receiver, {
      String sessionId = 'session-1',
    }) async {
      final output = await _savePendingSession(
        pairingRepo,
        sessionId: sessionId,
      );
      final newRuntime = AccountMigrationLocalTransferRuntime(
        discovery: newPhoneDiscovery,
        wsServer: newPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleReceiver: receiver,
      );
      newPhoneServer.configureMigrationTransferHandler(
        newRuntime.handleMigrationTransferRequest,
      );
      expect(
        (await newRuntime.startNewPhoneReceiver(output)).isStarted,
        isTrue,
      );
      return (output, newRuntime);
    }

    Future<AccountMigrationTransferResult> runTransfer(
      AccountMigrationLocalTransferRuntime oldRuntime,
      MigrationQrBuildOutput output,
    ) {
      return oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );
    }

    test(
      'classifies slow segment response as local transfer timeout',
      () async {
        final receiver = _DelayingBundleReceiver(
          segmentDelay: (index) => index == 1 ? downstreamCommandDelay : null,
        );
        final (output, _) = await startNewPhone(receiver);
        final bundle = _preparedBundle(
          sessionId: output.payload.sessionId,
          segmentCount: 3,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => bundle,
          httpTimeout: downstreamCommandTimeout,
        );

        final result = await runTransfer(oldRuntime, output);

        expect(result.isSuccess, isFalse);
        expect(
          result.failureCode,
          AccountMigrationTransferFailureCode.localTransferTimedOut,
        );
        expect(
          result.safeMessage,
          accountMigrationLocalTransferStalledSafeMessage,
        );
        expect(
          eventsNamed('ACCOUNT_MIGRATION_TRANSFER_BUNDLE_SOURCE_FAILED'),
          isEmpty,
        );
      },
    );

    test(
      'segment timeout telemetry pinpoints command, index, and phase',
      () async {
        final receiver = _DelayingBundleReceiver(
          segmentDelay: (index) => index == 1 ? downstreamCommandDelay : null,
        );
        final (output, _) = await startNewPhone(receiver);
        final bundle = _preparedBundle(
          sessionId: output.payload.sessionId,
          segmentCount: 3,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => bundle,
          httpTimeout: downstreamCommandTimeout,
        );

        await runTransfer(oldRuntime, output);

        final starts =
            eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_START')
                .map(detailsOf)
                .where((details) => details['command'] == 'segment')
                .toList(growable: false);
        expect(starts, isNotEmpty);
        expect(starts.first['payloadBytes'], isA<int>());
        expect(starts.first['timeoutMs'], isA<int>());
        expect(
          starts.first['httpTimeoutMs'],
          downstreamCommandTimeout.inMilliseconds,
        );

        final failures = eventsNamed(
          'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED',
        ).map(detailsOf).toList(growable: false);
        expect(failures, hasLength(1));
        final failure = failures.single;
        expect(failure['command'], 'segment');
        expect(failure['commandStage'], 'segmentTransfer');
        expect(failure['segmentIndex'], 1);
        expect(failure['segmentCount'], 3);
        expect(failure['payloadBytes'], isA<int>());
        expect(failure['phase'], 'closeAwaitResponse');
        expect(failure['elapsedMs'], isA<int>());
        expect(failure['timeoutMs'], isA<int>());
        expect(failure['errorType'], 'TimeoutException');
        expect(failure['reason'], 'timeout');
      },
    );

    test('connect failure on transcript is typed with connect phase', () async {
      final closedSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final deadPort = closedSocket.port;
      await closedSocket.close();
      final output = await _savePendingSession(pairingRepo);
      registry[accountMigrationLocalPeerIdForSession(
        output.payload.sessionId,
      )] = LocalPeer(
        peerId: 'dead-peer',
        host: '127.0.0.1',
        port: deadPort,
        discoveredAt: DateTime.now().toUtc(),
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        httpTimeout: const Duration(milliseconds: 300),
      );

      final result = await runTransfer(oldRuntime, output);

      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.localTransferTimedOut,
      );
      expect(
        result.safeMessage,
        accountMigrationLocalTransferStalledSafeMessage,
      );
      final failure = detailsOf(
        eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED').single,
      );
      expect(failure['command'], 'transcript');
      expect(failure['commandStage'], 'transcriptPairing');
      expect(failure['phase'], 'connect');
      expect(failure['reason'], 'socketError');
      expect(failure['errorType'], 'SocketException');
    });

    test(
      'killed connection mid-transfer is typed as local transfer timeout',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async => server.close(force: true));
        final commands = <String>[];
        server.listen((request) async {
          final command = request.uri.pathSegments.last;
          commands.add(command);
          if (command == accountMigrationLocalTransferCommandSegment) {
            final body = await utf8.decoder.bind(request).join();
            final decoded = jsonDecode(body) as Map<String, dynamic>;
            if (decoded['index'] == 1) {
              final socket = await request.response.detachSocket();
              socket.destroy();
              return;
            }
          } else {
            await request.drain<void>();
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'ok': true}));
          await request.response.close();
        });

        final output = await _savePendingSession(
          pairingRepo,
          sessionId: 'reused-connection-killed',
        );
        registry[accountMigrationLocalPeerIdForSession(
          output.payload.sessionId,
        )] = LocalPeer(
          peerId: 'raw-kill-peer',
          host: '127.0.0.1',
          port: server.port,
          discoveredAt: DateTime.now().toUtc(),
        );
        final httpClient = _CloseCountingHttpClient();
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => _preparedBundle(
            sessionId: output.payload.sessionId,
            segmentCount: 3,
          ),
          httpClientFactory: () => httpClient,
          httpTimeout: const Duration(seconds: 2),
        );

        final result = await runTransfer(oldRuntime, output);

        expect(
          result.failureCode,
          AccountMigrationTransferFailureCode.localTransferTimedOut,
        );
        expect(commands, [
          accountMigrationLocalTransferCommandTranscript,
          accountMigrationLocalTransferCommandManifest,
          accountMigrationLocalTransferCommandSegment,
          accountMigrationLocalTransferCommandSegment,
        ]);
        expect(httpClient.closeCount, 1);
        expect(httpClient.forceCloseCount, 1);
        final failure = detailsOf(
          eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED').single,
        );
        expect(failure['command'], 'segment');
        expect(failure['commandStage'], 'segmentTransfer');
        expect(failure['segmentIndex'], 1);
        expect(failure['reason'], isIn(<String>['socketError', 'httpError']));
        expect(
          failure['errorType'],
          isIn(<String>['SocketException', 'HttpException']),
        );
      },
    );

    test('response header stall is attributed to closeAwaitResponse', () async {
      final stallServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async => stallServer.close());
      final sockets = <Socket>[];
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
      });
      stallServer.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {});
      });
      final output = await _savePendingSession(pairingRepo);
      registry[accountMigrationLocalPeerIdForSession(
        output.payload.sessionId,
      )] = LocalPeer(
        peerId: 'stalled-peer',
        host: '127.0.0.1',
        port: stallServer.port,
        discoveredAt: DateTime.now().toUtc(),
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        httpTimeout: const Duration(milliseconds: 200),
      );

      final result = await runTransfer(oldRuntime, output);

      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.localTransferTimedOut,
      );
      final failure = detailsOf(
        eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED').single,
      );
      expect(failure['command'], 'transcript');
      expect(failure['phase'], 'closeAwaitResponse');
      expect(failure['reason'], 'timeout');
    });

    test('response body stall is attributed to responseBodyDrain', () async {
      final stallServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async => stallServer.close());
      final sockets = <Socket>[];
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
      });
      stallServer.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {});
        socket.write(
          'HTTP/1.1 200 OK\r\n'
          'content-type: application/json\r\n'
          'content-length: 100000\r\n'
          '\r\n'
          '{"ok":',
        );
      });
      final output = await _savePendingSession(pairingRepo);
      registry[accountMigrationLocalPeerIdForSession(
        output.payload.sessionId,
      )] = LocalPeer(
        peerId: 'draining-peer',
        host: '127.0.0.1',
        port: stallServer.port,
        discoveredAt: DateTime.now().toUtc(),
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        httpTimeout: const Duration(milliseconds: 200),
      );

      final result = await runTransfer(oldRuntime, output);

      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.localTransferTimedOut,
      );
      final failure = detailsOf(
        eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED').single,
      );
      expect(failure['command'], 'transcript');
      expect(failure['phase'], 'responseBodyDrain');
      expect(failure['reason'], 'timeout');
    });

    test('receiver telemetry tracks manifest, segments, and complete', () async {
      final receiver = _DelayingBundleReceiver();
      // Unique session id so late telemetry leaking from earlier slow-receiver
      // tests (whose delayed handlers outlive their test body) cannot pollute
      // the count assertions below.
      final (output, newRuntime) = await startNewPhone(
        receiver,
        sessionId: 'session-receiver-telemetry',
      );
      final receivedEvents = <AccountMigrationReceiverEvent>[];
      final sub = newRuntime.receiverEvents.listen(receivedEvents.add);
      addTearDown(sub.cancel);
      final bundle = _preparedBundle(
        sessionId: output.payload.sessionId,
        segmentCount: 3,
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => bundle,
      );

      final result = await runTransfer(oldRuntime, output);
      await pumpEventQueue();

      expect(result.isSuccess, isTrue);

      List<Map<String, dynamic>> sessionDetails(String name) =>
          eventsNamed(name)
              .map(detailsOf)
              .where(
                (details) => details['sessionId'] == output.payload.sessionId,
              )
              .toList(growable: false);

      final startCommands = sessionDetails(
        'ACCOUNT_MIGRATION_RECEIVER_REQUEST_START',
      ).map((details) => details['command']).toSet();
      expect(
        startCommands,
        containsAll(<String>['transcript', 'manifest', 'segment', 'complete']),
      );

      final manifestAccepted = sessionDetails(
        'ACCOUNT_MIGRATION_RECEIVER_MANIFEST_ACCEPTED',
      ).single;
      expect(manifestAccepted['sessionId'], output.payload.sessionId);
      expect(manifestAccepted['bundleId'], 'bundle-1');
      expect(manifestAccepted['segmentCount'], 3);
      expect(manifestAccepted['totalBytes'], isA<int>());
      expect(manifestAccepted['bodyBytes'], isA<int>());
      expect(manifestAccepted['bodyReadMs'], isA<int>());
      expect(manifestAccepted['decodeMs'], isA<int>());
      expect(manifestAccepted['acceptMs'], isA<int>());

      final segmentAccepted = sessionDetails(
        'ACCOUNT_MIGRATION_RECEIVER_SEGMENT_ACCEPTED',
      );
      expect(segmentAccepted, hasLength(3));
      expect(
        segmentAccepted.map((details) => details['verifiedCount']).toList(),
        [1, 2, 3],
      );
      expect(segmentAccepted.first['segmentIndex'], 0);
      expect(segmentAccepted.first['segmentCount'], 3);
      expect(segmentAccepted.first['bodyBytes'], isA<int>());
      expect(segmentAccepted.first['bodyReadMs'], isA<int>());
      expect(segmentAccepted.first['decodeMs'], isA<int>());
      expect(segmentAccepted.first['acceptMs'], isA<int>());

      final completeAccepted = sessionDetails(
        'ACCOUNT_MIGRATION_RECEIVER_COMPLETE_ACCEPTED',
      ).single;
      expect(completeAccepted['verifiedCount'], 3);

      final segmentDone =
          sessionDetails('ACCOUNT_MIGRATION_RECEIVER_REQUEST_DONE')
              .where((details) => details['command'] == 'segment')
              .toList(growable: false);
      expect(segmentDone, hasLength(3));
      expect(segmentDone.first['statusCode'], 200);
      expect(segmentDone.first['elapsedMs'], isA<int>());
      expect(segmentDone.first['writeMs'], isA<int>());

      final types = receivedEvents.map((event) => event.type).toList();
      expect(types, [
        AccountMigrationReceiverEventType.receivingSegment,
        AccountMigrationReceiverEventType.receivingSegment,
        AccountMigrationReceiverEventType.receivingSegment,
        AccountMigrationReceiverEventType.receivingSegment,
        AccountMigrationReceiverEventType.importingBundle,
        AccountMigrationReceiverEventType.importVerified,
      ]);
      expect(receivedEvents.first.segmentCount, 3);
      expect(receivedEvents.first.verifiedCount, 0);
      expect(receivedEvents[3].segmentIndex, 2);
      expect(receivedEvents[3].verifiedCount, 3);
    });

    test('rejected segment emits receiver rejection telemetry', () async {
      final receiver = _RejectingSegmentReceiver(rejectFromIndex: 1);
      final (output, _) = await startNewPhone(receiver);
      final bundle = _preparedBundle(
        sessionId: output.payload.sessionId,
        segmentCount: 3,
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => bundle,
      );

      final result = await runTransfer(oldRuntime, output);

      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.transferRejected,
      );
      final rejected = detailsOf(
        eventsNamed('ACCOUNT_MIGRATION_RECEIVER_SEGMENT_REJECTED').single,
      );
      expect(rejected['sessionId'], output.payload.sessionId);
      expect(rejected['reason'], 'segment_rejected');
      expect(rejected['statusCode'], 400);

      final rejectedCiphertext = bundle.encryptedSegments![1].ciphertext;
      for (final event in flowEvents) {
        expect(
          jsonEncode(event['details']),
          isNot(contains(rejectedCiphertext)),
          reason:
              'telemetry must not leak segment ciphertext: ${event['event']}',
        );
      }
    });

    test(
      '34 segments complete with monotonic sender progress telemetry',
      () async {
        final receiver = _DelayingBundleReceiver(
          segmentDelay: (index) =>
              index == 17 ? const Duration(milliseconds: 150) : null,
        );
        final (output, _) = await startNewPhone(receiver);
        final bundle = _preparedBundle(
          sessionId: output.payload.sessionId,
          segmentCount: 34,
          payloadSize: 32,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => bundle,
          httpTimeout: const Duration(milliseconds: 250),
        );

        final result = await runTransfer(oldRuntime, output);

        expect(result.isSuccess, isTrue);
        expect(
          eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED'),
          isEmpty,
        );
        final progress = eventsNamed(
          'ACCOUNT_MIGRATION_LOCAL_TRANSFER_SEGMENT_PROGRESS',
        ).map(detailsOf).toList(growable: false);
        expect(progress, hasLength(34));
        expect(
          progress.map((details) => details['sentCount']).toList(),
          List<int>.generate(34, (i) => i + 1),
        );
        expect(progress.first['sessionId'], output.payload.sessionId);
        expect(progress.first['bundleId'], 'bundle-1');
        expect(progress.first['segmentCount'], 34);
        expect(progress.first['payloadBytes'], isA<int>());
        expect(progress.first['elapsedMs'], isA<int>());
      },
    );

    test(
      'payload-scaled budget tolerates receiver work past flat timeout',
      () async {
        final receiver = _DelayingBundleReceiver(
          segmentDelay: (_) => const Duration(milliseconds: 600),
        );
        final (output, _) = await startNewPhone(receiver);
        final bundle = _preparedBundle(
          sessionId: output.payload.sessionId,
          segmentCount: 1,
          payloadSize: 1024,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => bundle,
          httpTimeout: const Duration(milliseconds: 200),
          transferBytesPerSecondFloor: 1000,
        );

        final result = await runTransfer(oldRuntime, output);

        expect(result.isSuccess, isTrue, reason: result.safeMessage ?? '');
        expect(
          eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED'),
          isEmpty,
        );
      },
    );

    test('manifest timeout is typed by command', () async {
      final receiver = _DelayingBundleReceiver(
        manifestDelay: downstreamCommandDelay,
      );
      final (output, _) = await startNewPhone(receiver);
      final bundle = _preparedBundle(
        sessionId: output.payload.sessionId,
        segmentCount: 1,
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => bundle,
        httpTimeout: downstreamCommandTimeout,
      );

      final result = await runTransfer(oldRuntime, output);

      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.localTransferTimedOut,
      );
      final failure = detailsOf(
        eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED').single,
      );
      expect(failure['command'], 'manifest');
      expect(failure['commandStage'], 'manifestAcceptance');
    });

    test('plaintext segment sender path timeout is typed', () async {
      final receiver = _DelayingBundleReceiver(
        segmentDelay: (_) => downstreamCommandDelay,
      );
      final (output, _) = await startNewPhone(receiver);
      final plaintextSegments = {
        0: Uint8List.fromList(utf8.encode('db-1')),
        1: Uint8List.fromList(utf8.encode('db-2')),
      };
      final manifest = _manifestFor(
        plaintextSegments: plaintextSegments,
        sessionId: output.payload.sessionId,
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => AccountMigrationLocalTransferBundle(
          manifest: manifest,
          plaintextSegments: plaintextSegments,
        ),
        transferService: MigrationSegmentedTransferService(
          crypto: _DeterministicSegmentCrypto(),
          checkpointStore: InMemoryMigrationTransferCheckpointStore(),
        ),
        httpTimeout: downstreamCommandTimeout,
      );

      final result = await runTransfer(oldRuntime, output);

      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.localTransferTimedOut,
      );
      expect(
        result.safeMessage,
        accountMigrationLocalTransferStalledSafeMessage,
      );
      final failure = detailsOf(
        eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED').single,
      );
      expect(failure['command'], 'segment');
    });

    test('complete timeout is typed by command stage', () async {
      final receiver = _DelayingBundleReceiver(
        completeDelay: downstreamCommandDelay,
      );
      final (output, _) = await startNewPhone(receiver);
      final bundle = _preparedBundle(
        sessionId: output.payload.sessionId,
        segmentCount: 1,
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => bundle,
        httpTimeout: downstreamCommandTimeout,
      );

      final result = await runTransfer(oldRuntime, output);

      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.localTransferTimedOut,
      );
      final failure = detailsOf(
        eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED').single,
      );
      expect(failure['command'], 'complete');
      expect(failure['commandStage'], 'completeVerification');
    });

    test(
      'old block proof timeout is typed with explicit authority risk',
      () async {
        final receiver = _DelayingCutoverReceiver(
          oldBlockProofDelay: const Duration(milliseconds: 700),
        );
        final (output, _) = await startNewPhone(receiver);
        final bundle = _preparedBundle(
          sessionId: output.payload.sessionId,
          segmentCount: 1,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => bundle,
          oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: _MemoryAuthorityRepository(),
            cutoverRepository: _MemoryCutoverRepository(),
            now: _fixedNow,
          ),
          oldPhoneLeaseCleanup: _noopLeaseCleanup(),
          httpTimeout: const Duration(milliseconds: 250),
          oldBlockProofRetryDelay: (_) async {},
        );

        final result = await runTransfer(oldRuntime, output);

        expect(
          result.failureCode,
          AccountMigrationTransferFailureCode.localTransferTimedOut,
        );
        expect(
          result.safeMessage,
          accountMigrationFinalHandoffStalledSafeMessage,
        );
        final failures = eventsNamed(
          'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED',
        ).map(detailsOf).toList(growable: false);
        expect(failures, hasLength(2));
        for (final failure in failures) {
          expect(failure['command'], 'old-block-proof');
          expect(failure['commandStage'], 'oldBlockProofCutover');
          expect(
            failure['authorityRisk'],
            'oldNetworkBlockedWithoutNewActiveProof',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
    );

    test('segment progress callback reports monotonic sent counts', () async {
      final receiver = _RecordingBundleReceiver(onSegment: (_) {});
      final (output, _) = await startNewPhone(receiver);
      final bundle = _preparedBundle(
        sessionId: output.payload.sessionId,
        segmentCount: 3,
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => bundle,
      );
      final progress = <(int, int)>[];

      final result = await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
        onSegmentProgress: (update) =>
            progress.add((update.sentSegments, update.totalSegments)),
      );

      expect(result.isSuccess, isTrue);
      expect(progress, [(0, 3), (1, 3), (2, 3), (3, 3)]);
      expect(progress.last.$1 / progress.last.$2, 1.0);
    });
  });

  group('export network quiesce (C4 mid-transfer message loss)', () {
    late Map<String, LocalPeer> registry;
    late _MemoryPairingSessionRepository pairingRepo;
    late LocalWsServer newPhoneServer;
    late LocalWsServer oldPhoneServer;
    late _SharedFakeDiscovery newPhoneDiscovery;
    late _SharedFakeDiscovery oldPhoneDiscovery;
    late List<Map<String, dynamic>> flowEvents;
    late _MemoryAuthorityRepository oldAuthority;

    setUp(() {
      registry = <String, LocalPeer>{};
      pairingRepo = _MemoryPairingSessionRepository();
      newPhoneServer = LocalWsServer();
      oldPhoneServer = LocalWsServer();
      newPhoneDiscovery = _SharedFakeDiscovery(registry);
      oldPhoneDiscovery = _SharedFakeDiscovery(registry);
      flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      oldAuthority = _MemoryAuthorityRepository();
    });

    tearDown(() async {
      debugSetFlowEventSink(null);
      await newPhoneServer.stop();
      await oldPhoneServer.stop();
      newPhoneDiscovery.dispose();
      oldPhoneDiscovery.dispose();
    });

    List<Map<String, dynamic>> eventsNamed(String name) => flowEvents
        .where((event) => event['event'] == name)
        .toList(growable: false);

    const downstreamCommandTimeout = Duration(seconds: 1);
    const downstreamCommandDelay = Duration(milliseconds: 1500);

    MigrationCutoverCoordinator coordinator() => MigrationCutoverCoordinator(
      authorityRepository: oldAuthority,
      cutoverRepository: _MemoryCutoverRepository(),
      now: _fixedNow,
    );

    Future<void> waitFor(bool Function() condition, String what) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('timed out waiting for $what');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    Future<(MigrationQrBuildOutput, AccountMigrationLocalTransferRuntime)>
    startNewPhone(
      AccountMigrationLocalBundleReceiver receiver, {
      String sessionId = 'session-1',
    }) async {
      final output = await _savePendingSession(
        pairingRepo,
        sessionId: sessionId,
      );
      final newRuntime = AccountMigrationLocalTransferRuntime(
        discovery: newPhoneDiscovery,
        wsServer: newPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleReceiver: receiver,
      );
      newPhoneServer.configureMigrationTransferHandler(
        newRuntime.handleMigrationTransferRequest,
      );
      expect(
        (await newRuntime.startNewPhoneReceiver(output)).isStarted,
        isTrue,
      );
      return (output, newRuntime);
    }

    test('pauses account network before the bundle snapshot is read', () async {
      final receiver = _RecordingBundleReceiver(onSegment: (_) {});
      final (output, _) = await startNewPhone(receiver);
      final bundle = _preparedBundle(
        sessionId: output.payload.sessionId,
        segmentCount: 1,
      );
      AccountMigrationAuthorityState? stateDuringSnapshot;
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async {
          stateDuringSnapshot = (await oldAuthority.loadAuthority())?.state;
          return bundle;
        },
        oldPhoneCutoverCoordinator: coordinator(),
        oldPhoneLeaseCleanup: _noopLeaseCleanup(),
      );

      await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(
        stateDuringSnapshot,
        AccountMigrationAuthorityState.migrationExportingNetworkPaused,
      );
      expect(
        eventsNamed('ACCOUNT_MIGRATION_EXPORT_NETWORK_PAUSED'),
        hasLength(1),
      );
    });

    test('restores active authority when the bundle source throws', () async {
      final receiver = _RecordingBundleReceiver(onSegment: (_) {});
      final (output, _) = await startNewPhone(receiver);
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async =>
            throw StateError('database snapshot export failed: quick_check'),
        oldPhoneCutoverCoordinator: coordinator(),
        oldPhoneLeaseCleanup: _noopLeaseCleanup(),
      );

      final result = await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.bundleExporterUnavailable,
      );
      expect(oldAuthority.history.map((record) => record.state), [
        AccountMigrationAuthorityState.migrationExportingNetworkPaused,
        AccountMigrationAuthorityState.migrationFailedActiveRestored,
      ]);
      expect(oldAuthority.saved?.state.isActiveAccountAuthority, isTrue);
    });

    test(
      'restores active authority when a segment times out mid-transfer',
      () async {
        final receiver = _DelayingBundleReceiver(
          segmentDelay: (index) => index == 1 ? downstreamCommandDelay : null,
        );
        final (output, _) = await startNewPhone(receiver);
        final bundle = _preparedBundle(
          sessionId: output.payload.sessionId,
          segmentCount: 3,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => bundle,
          oldPhoneCutoverCoordinator: coordinator(),
          oldPhoneLeaseCleanup: _noopLeaseCleanup(),
          httpTimeout: downstreamCommandTimeout,
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(
          result.failureCode,
          AccountMigrationTransferFailureCode.localTransferTimedOut,
        );
        expect(
          oldAuthority.saved?.state,
          AccountMigrationAuthorityState.migrationFailedActiveRestored,
        );
        final restored = eventsNamed(
          'ACCOUNT_MIGRATION_EXPORT_NETWORK_RESTORED',
        ).single;
        expect(
          Map<String, dynamic>.from(restored['details'] as Map)['restored'],
          isTrue,
        );
      },
    );

    test('restores active authority when the transfer is cancelled', () async {
      final receiver = _RecordingBundleReceiver(onSegment: (_) {});
      final (output, _) = await startNewPhone(receiver);
      final bundle = _preparedBundle(
        sessionId: output.payload.sessionId,
        segmentCount: 1,
      );
      var cancelled = false;
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async {
          cancelled = true;
          return bundle;
        },
        oldPhoneCutoverCoordinator: coordinator(),
        oldPhoneLeaseCleanup: _noopLeaseCleanup(),
      );

      final result = await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => cancelled,
      );

      expect(result.failureCode, AccountMigrationTransferFailureCode.cancelled);
      expect(
        oldAuthority.saved?.state,
        AccountMigrationAuthorityState.migrationFailedActiveRestored,
      );
    });

    test(
      'abandoned run does not un-pause an overlapping retried export',
      () async {
        final receiver = _RecordingBundleReceiver(onSegment: (_) {});
        final (output, _) = await startNewPhone(receiver);
        final bundle = _preparedBundle(
          sessionId: output.payload.sessionId,
          segmentCount: 1,
        );
        var sourceCalls = 0;
        final run1Gate = Completer<void>();
        final run2Gate = Completer<void>();
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async {
            sourceCalls++;
            await (sourceCalls == 1 ? run1Gate.future : run2Gate.future);
            return bundle;
          },
          oldPhoneCutoverCoordinator: coordinator(),
          oldPhoneLeaseCleanup: _noopLeaseCleanup(),
        );
        final request = AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        );

        // Run 1 starts, pauses, and hangs inside the bundle source.
        var run1Cancelled = false;
        final run1 = oldRuntime.runOldPhoneTransfer(
          request: request,
          onProgress: (_) {},
          isCancelled: () => run1Cancelled,
        );
        await waitFor(() => sourceCalls >= 1, 'run 1 to reach bundle source');

        // The user retries: run 2 starts and also engages the pause.
        final run2 = oldRuntime.runOldPhoneTransfer(
          request: request,
          onProgress: (_) {},
          isCancelled: () => false,
        );
        await waitFor(() => sourceCalls >= 2, 'run 2 to reach bundle source');

        // Run 1 is abandoned and exits while run 2 is still mid-export: its
        // cleanup must NOT restore active authority out from under run 2.
        run1Cancelled = true;
        run1Gate.complete();
        final run1Result = await run1;
        expect(
          run1Result.failureCode,
          AccountMigrationTransferFailureCode.cancelled,
        );
        expect(
          oldAuthority.saved?.state,
          AccountMigrationAuthorityState.migrationExportingNetworkPaused,
        );
        expect(
          eventsNamed('ACCOUNT_MIGRATION_EXPORT_NETWORK_RESTORE_DEFERRED'),
          hasLength(1),
        );

        // When run 2 (the last live run) exits, the pause is restored.
        run2Gate.complete();
        await run2;
        expect(
          oldAuthority.saved?.state,
          AccountMigrationAuthorityState.migrationFailedActiveRestored,
        );
      },
    );

    test(
      'pause-write failure aborts typed and does not leak the counter',
      () async {
        final throwingAuthority = _ThrowingSaveAuthorityRepository();
        throwingAuthority.shouldThrow = (_) => true;
        oldAuthority = throwingAuthority;
        final receiver = _RecordingBundleReceiver(onSegment: (_) {});
        final (output, _) = await startNewPhone(
          receiver,
          sessionId: 'quiesce-pause-fail',
        );
        final bundle = _preparedBundle(
          sessionId: output.payload.sessionId,
          segmentCount: 1,
        );
        var sourceCalls = 0;
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async {
            sourceCalls++;
            return bundle;
          },
          oldPhoneCutoverCoordinator: coordinator(),
          oldPhoneLeaseCleanup: _noopLeaseCleanup(),
        );
        final request = AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: request,
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(result.failureCode, AccountMigrationTransferFailureCode.unknown);
        expect(result.safeMessage, contains('could not pause'));
        expect(sourceCalls, 0, reason: 'snapshot must not run un-paused');
        expect(
          eventsNamed('ACCOUNT_MIGRATION_EXPORT_NETWORK_PAUSE_FAILED'),
          hasLength(1),
        );
        expect(oldAuthority.history, isEmpty);
        expect(
          eventsNamed('ACCOUNT_MIGRATION_EXPORT_NETWORK_RESTORE_DEFERRED'),
          isEmpty,
        );

        // The failed pause must not leak the counter: a follow-up transfer on
        // the same runtime restores normally instead of deferring.
        throwingAuthority.shouldThrow = (_) => false;
        final secondResult = await oldRuntime.runOldPhoneTransfer(
          request: request,
          onProgress: (_) {},
          isCancelled: () => false,
        );
        expect(secondResult.isSuccess, isFalse);
        expect(
          oldAuthority.saved?.state,
          AccountMigrationAuthorityState.migrationFailedActiveRestored,
        );
        expect(
          eventsNamed('ACCOUNT_MIGRATION_EXPORT_NETWORK_RESTORE_DEFERRED'),
          isEmpty,
        );
      },
    );

    test('restore failure never masks the transfer result', () async {
      final throwingAuthority = _ThrowingSaveAuthorityRepository();
      throwingAuthority.shouldThrow = (record) =>
          record.state ==
          AccountMigrationAuthorityState.migrationFailedActiveRestored;
      oldAuthority = throwingAuthority;
      final receiver = _RecordingBundleReceiver(onSegment: (_) {});
      final (output, _) = await startNewPhone(
        receiver,
        sessionId: 'quiesce-restore-fail',
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => throw StateError('snapshot exploded'),
        oldPhoneCutoverCoordinator: coordinator(),
        oldPhoneLeaseCleanup: _noopLeaseCleanup(),
      );

      final result = await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.bundleExporterUnavailable,
      );
      expect(
        eventsNamed('ACCOUNT_MIGRATION_EXPORT_NETWORK_RESTORE_FAILED'),
        hasLength(1),
      );
      // The pause record is still in place (restore write failed).
      expect(
        oldAuthority.saved?.state,
        AccountMigrationAuthorityState.migrationExportingNetworkPaused,
      );
    });

    test('missing bundle source aborts before any pause is written', () async {
      final receiver = _RecordingBundleReceiver(onSegment: (_) {});
      final (output, _) = await startNewPhone(
        receiver,
        sessionId: 'quiesce-no-source',
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        oldPhoneCutoverCoordinator: coordinator(),
        oldPhoneLeaseCleanup: _noopLeaseCleanup(),
      );

      final result = await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.bundleExporterUnavailable,
      );
      expect(oldAuthority.history, isEmpty);
      expect(eventsNamed('ACCOUNT_MIGRATION_EXPORT_NETWORK_PAUSED'), isEmpty);
    });

    test('hasActiveExportRun tracks the in-flight export pause', () async {
      final receiver = _RecordingBundleReceiver(onSegment: (_) {});
      final (output, _) = await startNewPhone(
        receiver,
        sessionId: 'quiesce-active-run',
      );
      final bundle = _preparedBundle(
        sessionId: output.payload.sessionId,
        segmentCount: 1,
      );
      var sourceCalls = 0;
      final sourceGate = Completer<void>();
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async {
          sourceCalls++;
          await sourceGate.future;
          return bundle;
        },
        oldPhoneCutoverCoordinator: coordinator(),
        oldPhoneLeaseCleanup: _noopLeaseCleanup(),
      );
      expect(oldRuntime.hasActiveExportRun, isFalse);

      final run = oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );
      await waitFor(() => sourceCalls >= 1, 'run to reach the bundle source');

      // The resume-time recovery hook must refuse to restore while this is
      // true (main.dart guards recoverInterruptedExportPause on it).
      expect(oldRuntime.hasActiveExportRun, isTrue);

      sourceGate.complete();
      await run;
      expect(oldRuntime.hasActiveExportRun, isFalse);
    });

    test(
      'runs without authority writes when no coordinator is configured',
      () async {
        final receiver = _RecordingBundleReceiver(onSegment: (_) {});
        final (output, _) = await startNewPhone(receiver);
        final bundle = _preparedBundle(
          sessionId: output.payload.sessionId,
          segmentCount: 1,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => bundle,
        );

        await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(oldAuthority.history, isEmpty);
        expect(eventsNamed('ACCOUNT_MIGRATION_EXPORT_NETWORK_PAUSED'), isEmpty);
        expect(
          eventsNamed('ACCOUNT_MIGRATION_EXPORT_NETWORK_RESTORED'),
          isEmpty,
        );
      },
    );
  });

  group('size cap and receiver storage preflight (P0-3 / P0-4)', () {
    late Map<String, LocalPeer> registry;
    late _MemoryPairingSessionRepository pairingRepo;
    late LocalWsServer newPhoneServer;
    late LocalWsServer oldPhoneServer;
    late _SharedFakeDiscovery newPhoneDiscovery;
    late _SharedFakeDiscovery oldPhoneDiscovery;
    late List<Map<String, dynamic>> flowEvents;

    setUp(() {
      registry = <String, LocalPeer>{};
      pairingRepo = _MemoryPairingSessionRepository();
      newPhoneServer = LocalWsServer();
      oldPhoneServer = LocalWsServer();
      newPhoneDiscovery = _SharedFakeDiscovery(registry);
      oldPhoneDiscovery = _SharedFakeDiscovery(registry);
      flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
    });

    tearDown(() async {
      debugSetFlowEventSink(null);
      await newPhoneServer.stop();
      await oldPhoneServer.stop();
      newPhoneDiscovery.dispose();
      oldPhoneDiscovery.dispose();
    });

    List<Map<String, dynamic>> eventsNamed(String name) => flowEvents
        .where((event) => event['event'] == name)
        .toList(growable: false);

    Map<String, dynamic> detailsOf(Map<String, dynamic> event) =>
        Map<String, dynamic>.from(event['details'] as Map);

    AccountMigrationSizeGate gate({
      required int totalBytes,
      int maxAccountBytes = 100,
    }) {
      return AccountMigrationSizeGate(
        estimateMoveSize: () async => AccountMigrationMoveSizeEstimate(
          databaseBytes: totalBytes,
          mediaBytes: 0,
          secureBytes: 0,
        ),
        policy: AccountMigrationSizePolicy(maxAccountBytes: maxAccountBytes),
      );
    }

    Future<(MigrationQrBuildOutput, AccountMigrationLocalTransferRuntime)>
    startNewPhone(
      AccountMigrationLocalBundleReceiver receiver, {
      String sessionId = 'session-1',
      MigrationStoragePreflight? storagePreflight,
    }) async {
      final output = await _savePendingSession(
        pairingRepo,
        sessionId: sessionId,
      );
      final newRuntime = AccountMigrationLocalTransferRuntime(
        discovery: newPhoneDiscovery,
        wsServer: newPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleReceiver: receiver,
        storagePreflight: storagePreflight,
      );
      newPhoneServer.configureMigrationTransferHandler(
        newRuntime.handleMigrationTransferRequest,
      );
      expect(
        (await newRuntime.startNewPhoneReceiver(output)).isStarted,
        isTrue,
      );
      return (output, newRuntime);
    }

    test('P0-3: over-cap estimate aborts typed before pause, bundle source, '
        'or any POST', () async {
      final receiver = _RecordingBundleReceiver(onSegment: (_) {});
      final (output, _) = await startNewPhone(
        receiver,
        sessionId: 'size-cap-runtime',
      );
      final oldAuthority = _MemoryAuthorityRepository();
      var sourceCalls = 0;
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async {
          sourceCalls++;
          return _preparedBundle(
            sessionId: output.payload.sessionId,
            segmentCount: 1,
          );
        },
        sizeGate: gate(totalBytes: 250, maxAccountBytes: 100),
        oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
          authorityRepository: oldAuthority,
          cutoverRepository: _MemoryCutoverRepository(),
          now: _fixedNow,
        ),
        oldPhoneLeaseCleanup: _noopLeaseCleanup(),
      );

      final result = await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.accountTooLargeToMove,
      );
      expect(result.safeMessage, contains('too large to move'));
      expect(sourceCalls, 0, reason: 'bundle source must never run');
      expect(eventsNamed('ACCOUNT_MIGRATION_BUNDLE_SOURCE_BUILT'), isEmpty);
      expect(
        eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_START'),
        isEmpty,
        reason: 'the cap blocks before any transcript/manifest POST',
      );
      expect(
        oldAuthority.history,
        isEmpty,
        reason: 'no export pause may be written for a blocked move',
      );
      final blocked = detailsOf(
        eventsNamed('ACCOUNT_MIGRATION_SIZE_CAP_BLOCKED').single,
      );
      expect(blocked['sessionId'], output.payload.sessionId);
      expect(blocked['totalBytes'], 250);
      expect(blocked['maxAccountBytes'], 100);
      expect(blocked['surface'], 'runtime');
    });

    test(
      'P0-3: under-cap estimate leaves the transfer path unchanged',
      () async {
        final receiver = _RecordingBundleReceiver(onSegment: (_) {});
        final (output, _) = await startNewPhone(
          receiver,
          sessionId: 'size-cap-under',
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => _preparedBundle(
            sessionId: output.payload.sessionId,
            segmentCount: 2,
          ),
          sizeGate: gate(totalBytes: 99, maxAccountBytes: 100),
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(eventsNamed('ACCOUNT_MIGRATION_SIZE_CAP_BLOCKED'), isEmpty);
      },
    );

    test(
      'P0-3: estimator failure is advisory — the transfer proceeds',
      () async {
        final receiver = _RecordingBundleReceiver(onSegment: (_) {});
        final (output, _) = await startNewPhone(
          receiver,
          sessionId: 'size-cap-estimator-broken',
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => _preparedBundle(
            sessionId: output.payload.sessionId,
            segmentCount: 1,
          ),
          sizeGate: AccountMigrationSizeGate(
            estimateMoveSize: () async => throw StateError('scan failed'),
            policy: const AccountMigrationSizePolicy(maxAccountBytes: 100),
          ),
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(
          eventsNamed('ACCOUNT_MIGRATION_SIZE_ESTIMATE_FAILED'),
          hasLength(1),
          reason: 'the receiver preflight stays the hard gate',
        );
      },
    );

    test('P0-4: insufficient receiver storage rejects the manifest typed and '
        'no segment is ever sent', () async {
      final receivedSegments = <int>[];
      final receiver = _RecordingBundleReceiver(
        onSegment: (segment) => receivedSegments.add(segment.index),
      );
      final (output, _) = await startNewPhone(
        receiver,
        sessionId: 'storage-insufficient',
        storagePreflight: MigrationStoragePreflight(
          availableBytesProvider: () async => 10,
        ),
      );
      final bundle = _preparedBundle(
        sessionId: output.payload.sessionId,
        segmentCount: 3,
      );
      final oldRuntime = AccountMigrationLocalTransferRuntime(
        discovery: oldPhoneDiscovery,
        wsServer: oldPhoneServer,
        pairingSessionRepository: pairingRepo,
        bundleSource: (_) async => bundle,
      );

      final result = await oldRuntime.runOldPhoneTransfer(
        request: AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        ),
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.failureCode,
        AccountMigrationTransferFailureCode.receiverStorageInsufficient,
      );
      // The user sees the receiver's concrete numbers, not vague advice.
      expect(
        result.safeMessage,
        accountMigrationReceiverStorageInsufficientMessage(
          requiredBytes:
              bundle.manifest.totalBytes *
              MigrationStoragePreflight.v1ProtocolImportAmplificationFactor,
          availableBytes: 10,
        ),
      );
      expect(result.safeMessage, contains('MB'));
      expect(receivedSegments, isEmpty);
      expect(
        eventsNamed('ACCOUNT_MIGRATION_RECEIVER_REQUEST_START')
            .map(detailsOf)
            .where(
              (details) =>
                  details['sessionId'] == output.payload.sessionId &&
                  details['command'] == 'segment',
            ),
        isEmpty,
        reason: 'no segment request may reach the receiver',
      );

      final rejected = detailsOf(
        eventsNamed('ACCOUNT_MIGRATION_RECEIVER_MANIFEST_REJECTED').single,
      );
      expect(rejected['reason'], 'receiver_storage_insufficient');
      expect(rejected['statusCode'], HttpStatus.insufficientStorage);
      expect(
        rejected['requiredBytes'],
        bundle.manifest.totalBytes *
            MigrationStoragePreflight.v1ProtocolImportAmplificationFactor,
      );
      expect(rejected['availableBytes'], 10);
    });

    test(
      'P0-4: storage probe failure blocks typed as unavailable, not a crash',
      () async {
        final receiver = _RecordingBundleReceiver(onSegment: (_) {});
        final (output, _) = await startNewPhone(
          receiver,
          sessionId: 'storage-unavailable',
          storagePreflight: MigrationStoragePreflight(
            availableBytesProvider: () async =>
                throw StateError('disk api unavailable'),
          ),
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => _preparedBundle(
            sessionId: output.payload.sessionId,
            segmentCount: 1,
          ),
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(
          result.failureCode,
          AccountMigrationTransferFailureCode.receiverStorageInsufficient,
        );
        // A failed probe reads differently from a full disk: the user should
        // not start deleting photos when the phone simply could not check.
        expect(
          result.safeMessage,
          accountMigrationReceiverStorageUnavailableMessage,
        );
        final rejected = detailsOf(
          eventsNamed('ACCOUNT_MIGRATION_RECEIVER_MANIFEST_REJECTED').single,
        );
        expect(rejected['reason'], 'receiver_storage_unavailable');
        expect(rejected['statusCode'], HttpStatus.insufficientStorage);
      },
    );

    test(
      'P0-4: sufficient receiver storage leaves the existing path unchanged',
      () async {
        final receivedSegments = <int>[];
        final receiver = _RecordingBundleReceiver(
          onSegment: (segment) => receivedSegments.add(segment.index),
        );
        final (output, _) = await startNewPhone(
          receiver,
          sessionId: 'storage-sufficient',
          storagePreflight: MigrationStoragePreflight(
            availableBytesProvider: () async => 1024 * 1024 * 1024,
          ),
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => _preparedBundle(
            sessionId: output.payload.sessionId,
            segmentCount: 2,
          ),
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(receivedSegments, [0, 1]);
        expect(
          eventsNamed('ACCOUNT_MIGRATION_RECEIVER_MANIFEST_REJECTED'),
          isEmpty,
        );
      },
    );
  });
}

class _TestMigrationHttpResponse {
  final int statusCode;
  final Map<String, dynamic>? body;

  const _TestMigrationHttpResponse({
    required this.statusCode,
    required this.body,
  });
}

Future<_TestMigrationHttpResponse> _postMigrationJson({
  required int port,
  required String sessionId,
  required String command,
  required Map<String, Object?> body,
}) async {
  final client = HttpClient();
  try {
    final encodedSessionId = Uri.encodeComponent(sessionId);
    final request = await client.post(
      InternetAddress.loopbackIPv4.address,
      port,
      '/migration/$encodedSessionId/$command',
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 2));
    final rawBody = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 2));
    final decoded = rawBody.trim().isEmpty ? null : jsonDecode(rawBody);
    return _TestMigrationHttpResponse(
      statusCode: response.statusCode,
      body: decoded is Map ? Map<String, dynamic>.from(decoded) : null,
    );
  } finally {
    client.close(force: true);
  }
}

MigrationCutoverRecord _validOldBlockProof(String sessionId) {
  final now = _fixedNow();
  return MigrationCutoverRecord.initial(
    sessionId: sessionId,
    accountPeerId: 'old-phone-peer',
    devicePeerId: 'old-phone-peer',
    deviceRole: MigrationCutoverDeviceRole.oldPhone,
    now: now,
  ).copyWith(
    phase: MigrationCutoverPhase.oldNetworkBlocked,
    oldNetworkBlocked: true,
    oldNetworkBlockedAt: now,
  );
}

MigrationCutoverRecord _validNewActiveProof({
  required String sessionId,
  required String devicePeerId,
}) {
  final now = _fixedNow();
  return MigrationCutoverRecord.initial(
    sessionId: sessionId,
    accountPeerId: 'old-phone-peer',
    devicePeerId: devicePeerId,
    deviceRole: MigrationCutoverDeviceRole.newPhone,
    now: now,
  ).copyWith(
    phase: MigrationCutoverPhase.newActiveCommitted,
    oldNetworkBlocked: true,
    oldNetworkBlockedAt: now,
    oldBlockProofReceived: true,
    oldBlockProofReceivedAt: now,
    newActiveCommitted: true,
    newActiveCommittedAt: now,
  );
}

AccountMigrationLocalTransferBundle _preparedBundle({
  required String sessionId,
  required int segmentCount,
  int payloadSize = 4,
}) {
  final plaintextSegments = {
    for (var i = 0; i < segmentCount; i++)
      i: Uint8List.fromList(List<int>.filled(payloadSize, 0x61 + (i % 26))),
  };
  final manifest = _manifestFor(
    plaintextSegments: plaintextSegments,
    sessionId: sessionId,
    segmentSize: payloadSize,
  );
  final encryptedSegments = [
    for (final descriptor in manifest.orderedSegments)
      _encryptedSegmentFor(
        descriptor: descriptor,
        manifest: manifest,
        plaintext: plaintextSegments[descriptor.index]!,
      ),
  ];
  return AccountMigrationLocalTransferBundle(
    manifest: manifest,
    encryptedSegments: encryptedSegments,
  );
}

class _CloseCountingHttpClient implements HttpClient {
  final HttpClient _delegate;
  int closeCount = 0;
  int forceCloseCount = 0;

  _CloseCountingHttpClient({HttpClient? delegate})
    : _delegate = delegate ?? HttpClient();

  @override
  Future<HttpClientRequest> post(String host, int port, String path) {
    return _delegate.post(host, port, path);
  }

  @override
  void close({bool force = false}) {
    closeCount += 1;
    if (force) {
      forceCloseCount += 1;
    }
    _delegate.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProofFailingHttpClient implements HttpClient {
  final HttpClient _delegate = HttpClient();
  int proofAttempts = 0;

  @override
  Future<HttpClientRequest> post(String host, int port, String path) {
    if (path.endsWith('/$accountMigrationLocalTransferCommandOldBlockProof')) {
      proofAttempts += 1;
      return Future<HttpClientRequest>.error(
        const SocketException('injected old-block-proof transport loss'),
      );
    }
    return _delegate.post(host, port, path);
  }

  @override
  void close({bool force = false}) {
    _delegate.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CommandFailingHttpClient implements HttpClient {
  final String failingCommand;
  final HttpClient _delegate = HttpClient();
  int failedCommandAttempts = 0;

  _CommandFailingHttpClient(this.failingCommand);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) {
    if (path.endsWith('/$failingCommand')) {
      failedCommandAttempts += 1;
      return Future<HttpClientRequest>.error(
        SocketException('injected $failingCommand transport loss'),
      );
    }
    return _delegate.post(host, port, path);
  }

  @override
  void close({bool force = false}) {
    _delegate.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayingBundleReceiver extends _RecordingBundleReceiver {
  final Duration? manifestDelay;
  final Duration? completeDelay;
  final Duration? Function(int index)? segmentDelay;

  _DelayingBundleReceiver({
    this.manifestDelay,
    this.completeDelay,
    this.segmentDelay,
  }) : super(onSegment: (_) {});

  @override
  Future<bool> acceptManifest({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    final delay = manifestDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    return super.acceptManifest(
      manifest: manifest,
      transcript: transcript,
      pendingSession: pendingSession,
    );
  }

  @override
  Future<bool> acceptSegment({
    required MigrationTransferManifest manifest,
    required MigrationEncryptedSegment segment,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    final delay = segmentDelay?.call(segment.index);
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    return super.acceptSegment(
      manifest: manifest,
      segment: segment,
      transcript: transcript,
      pendingSession: pendingSession,
    );
  }

  @override
  Future<bool> complete({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    final delay = completeDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    return super.complete(
      manifest: manifest,
      transcript: transcript,
      pendingSession: pendingSession,
    );
  }
}

class _RejectingSegmentReceiver extends _RecordingBundleReceiver {
  final int rejectFromIndex;

  _RejectingSegmentReceiver({required this.rejectFromIndex})
    : super(onSegment: (_) {});

  @override
  Future<bool> acceptSegment({
    required MigrationTransferManifest manifest,
    required MigrationEncryptedSegment segment,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    if (segment.index >= rejectFromIndex) {
      return false;
    }
    return super.acceptSegment(
      manifest: manifest,
      segment: segment,
      transcript: transcript,
      pendingSession: pendingSession,
    );
  }
}

class _DelayingCutoverReceiver extends _CutoverRecordingBundleReceiver {
  final Duration oldBlockProofDelay;

  _DelayingCutoverReceiver({required this.oldBlockProofDelay});

  @override
  Future<MigrationCutoverRecord?> acceptOldBlockProof({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
    required MigrationCutoverRecord oldBlockProof,
  }) async {
    await Future<void>.delayed(oldBlockProofDelay);
    return super.acceptOldBlockProof(
      manifest: manifest,
      transcript: transcript,
      pendingSession: pendingSession,
      oldBlockProof: oldBlockProof,
    );
  }
}

class _PausableCompleteCutoverReceiver extends _CutoverRecordingBundleReceiver {
  final completeEntered = Completer<void>();
  final _completeRelease = Completer<void>();

  void releaseComplete() {
    if (!_completeRelease.isCompleted) {
      _completeRelease.complete();
    }
  }

  @override
  Future<bool> complete({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    if (!completeEntered.isCompleted) {
      completeEntered.complete();
    }
    await _completeRelease.future;
    return super.complete(
      manifest: manifest,
      transcript: transcript,
      pendingSession: pendingSession,
    );
  }
}

class _PausableFailingCompleteCutoverReceiver
    extends _CutoverRecordingBundleReceiver {
  final Object? error;
  final completeEntered = Completer<void>();
  final _completeRelease = Completer<void>();

  _PausableFailingCompleteCutoverReceiver({required this.error});

  void releaseComplete() {
    if (!_completeRelease.isCompleted) {
      _completeRelease.complete();
    }
  }

  @override
  Future<bool> complete({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    completeCalls += 1;
    if (!completeEntered.isCompleted) {
      completeEntered.complete();
    }
    await _completeRelease.future;
    final failure = error;
    if (failure != null) throw failure;
    return false;
  }
}

class _MutatingNewActiveProofCutoverReceiver
    extends _CutoverRecordingBundleReceiver {
  final MigrationCutoverRecord Function(MigrationCutoverRecord proof)
  mutateProof;

  _MutatingNewActiveProofCutoverReceiver(this.mutateProof);

  @override
  Future<MigrationCutoverRecord?> acceptOldBlockProof({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
    required MigrationCutoverRecord oldBlockProof,
  }) async {
    final accepted = await super.acceptOldBlockProof(
      manifest: manifest,
      transcript: transcript,
      pendingSession: pendingSession,
      oldBlockProof: oldBlockProof,
    );
    if (accepted == null) return null;
    newActiveProof = mutateProof(accepted);
    return newActiveProof;
  }
}

class _PausableProofCutoverReceiver extends _CutoverRecordingBundleReceiver {
  final proofEntered = Completer<void>();
  final _proofRelease = Completer<void>();
  int acceptInvocations = 0;

  void releaseProof() {
    if (!_proofRelease.isCompleted) {
      _proofRelease.complete();
    }
  }

  @override
  Future<MigrationCutoverRecord?> acceptOldBlockProof({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
    required MigrationCutoverRecord oldBlockProof,
  }) async {
    acceptInvocations += 1;
    if (!proofEntered.isCompleted) {
      proofEntered.complete();
    }
    await _proofRelease.future;
    return super.acceptOldBlockProof(
      manifest: manifest,
      transcript: transcript,
      pendingSession: pendingSession,
      oldBlockProof: oldBlockProof,
    );
  }
}

class _RetryableProofCutoverReceiver extends _CutoverRecordingBundleReceiver {
  final Object? error;

  _RetryableProofCutoverReceiver({required this.error});

  @override
  Future<MigrationCutoverRecord?> acceptOldBlockProof({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
    required MigrationCutoverRecord oldBlockProof,
  }) async {
    if (oldBlockProofCalls == 0) {
      oldBlockProofCalls += 1;
      this.oldBlockProof = oldBlockProof;
      final failure = error;
      if (failure != null) throw failure;
      return null;
    }
    return super.acceptOldBlockProof(
      manifest: manifest,
      transcript: transcript,
      pendingSession: pendingSession,
      oldBlockProof: oldBlockProof,
    );
  }
}

MigrationEncryptedSegment _encryptedSegmentFor({
  required MigrationTransferSegmentDescriptor descriptor,
  required MigrationTransferManifest manifest,
  required Uint8List plaintext,
}) {
  final aad = MigrationSegmentAssociatedData(
    sessionId: manifest.sessionId,
    bundleId: manifest.bundleId,
    segmentIndex: descriptor.index,
    offset: descriptor.offset,
    plaintextLength: descriptor.plaintextLength,
    manifestSha256: manifest.manifestSha256,
  );
  final ciphertext =
      'ct:${descriptor.index}:${base64Encode(plaintext)}:${aad.sha256Hex}';
  return MigrationEncryptedSegment(
    index: descriptor.index,
    kem: 'kem-${descriptor.index}',
    ciphertext: ciphertext,
    nonce: descriptor.nonce,
    plaintextSha256: descriptor.plaintextSha256,
    ciphertextSha256: descriptor.ciphertextSha256,
    associatedDataSha256: aad.sha256Hex,
  );
}

Future<MigrationQrBuildOutput> _savePendingSession(
  _MemoryPairingSessionRepository repo, {
  String sessionId = 'session-1',
}) async {
  final createdAt = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
  final payload = MigrationQrPayload(
    sessionId: sessionId,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(minutes: 5)),
    newPhoneEphemeralPublicKey: 'new-phone-public-key',
    channelNonce: 'nonce',
  );
  await repo.savePendingNewPhoneSession(
    MigrationPendingPairingSession(
      sessionId: payload.sessionId,
      createdAt: payload.createdAt,
      expiresAt: payload.expiresAt,
      newPhoneEphemeralPublicKey: payload.newPhoneEphemeralPublicKey,
      newPhoneEphemeralSecretKey: 'new-phone-secret-key',
    ),
  );
  return MigrationQrBuildOutput(
    payload: payload,
    qrJson: payload.toJsonString(),
  );
}

AuthenticatedMigrationChannelTranscript _transcript(
  MigrationQrPayload payload,
) {
  return AuthenticatedMigrationChannelTranscript(
    sessionId: payload.sessionId,
    newPhoneEphemeralPublicKey: payload.newPhoneEphemeralPublicKey,
    oldPhonePeerId: 'old-phone-peer',
    authenticatedChannelBinding: 'binding',
    authorizationNonce: payload.channelNonce ?? 'nonce',
  );
}

class _MemoryPairingSessionRepository
    implements MigrationPairingSessionRepository {
  final pending = <String, MigrationPendingPairingSession>{};
  final consumed = <String, MigrationConsumedPairingSession>{};

  @override
  Future<void> savePendingNewPhoneSession(
    MigrationPendingPairingSession session,
  ) async {
    pending[session.sessionId] = session;
  }

  @override
  Future<MigrationPendingPairingSession?> loadPendingNewPhoneSession(
    String sessionId,
  ) async {
    return pending[sessionId];
  }

  @override
  Future<MigrationPairingSessionConsumeResult> consumeSession({
    required MigrationQrPayload payload,
    required DateTime consumedAt,
  }) async {
    if (consumed.containsKey(payload.sessionId)) {
      return MigrationPairingSessionConsumeResult.alreadyConsumed;
    }
    consumed[payload.sessionId] = MigrationConsumedPairingSession(
      sessionId: payload.sessionId,
      consumedAt: consumedAt,
      qrCreatedAt: payload.createdAt,
      qrExpiresAt: payload.expiresAt,
      newPhoneEphemeralPublicKey: payload.newPhoneEphemeralPublicKey,
    );
    return MigrationPairingSessionConsumeResult.consumed;
  }

  @override
  Future<bool> isSessionConsumed(String sessionId) async {
    return consumed.containsKey(sessionId);
  }

  @override
  Future<MigrationConsumedPairingSession?> loadConsumedSession(
    String sessionId,
  ) async {
    return consumed[sessionId];
  }
}

class _SharedFakeDiscovery implements LocalDiscoveryService {
  @override
  bool get isAdvertiseBroadcastGated => false; // 179: host fake never gates

  final Map<String, LocalPeer> registry;
  final _controller = StreamController<Map<String, LocalPeer>>.broadcast();
  String? advertisedPeerId;
  Object? stopAdvertisingError;

  _SharedFakeDiscovery(this.registry);

  @override
  Future<void> startAdvertising(
    String peerId,
    int wsPort, {
    int? quicPort,
    int? tcpPort,
  }) async {
    advertisedPeerId = peerId;
    registry[peerId] = LocalPeer(
      peerId: peerId,
      host: 'localhost',
      port: wsPort,
      discoveredAt: DateTime.now().toUtc(),
    );
    _controller.add(Map<String, LocalPeer>.from(registry));
  }

  @override
  Future<void> stopAdvertising() async {
    final error = stopAdvertisingError;
    if (error != null) throw error;
    final peerId = advertisedPeerId;
    if (peerId != null) {
      registry.remove(peerId);
      advertisedPeerId = null;
    }
    _controller.add(Map<String, LocalPeer>.from(registry));
  }

  @override
  Stream<Map<String, LocalPeer>> get discoveredPeersStream =>
      _controller.stream;

  @override
  Map<String, LocalPeer> get discoveredPeers =>
      Map<String, LocalPeer>.from(registry);

  @override
  bool isLocalPeer(String peerId) => registry.containsKey(peerId);

  @override
  LocalPeer? getLocalPeer(String peerId) => registry[peerId];

  @override
  Future<LocalPeer?> resolvePeer(
    String peerId, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final peer = registry[peerId];
      if (peer != null) return peer;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return registry[peerId];
  }

  @override
  void dispose() {
    _controller.close();
  }
}

class _RecordingBundleReceiver implements AccountMigrationLocalBundleReceiver {
  final void Function(MigrationEncryptedSegment segment) onSegment;
  MigrationTransferManifest? acceptedManifest;
  int acceptManifestCalls = 0;
  int completeCalls = 0;

  _RecordingBundleReceiver({required this.onSegment});

  @override
  Future<bool> acceptTranscript({
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    return true;
  }

  @override
  Future<bool> acceptManifest({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    acceptManifestCalls += 1;
    acceptedManifest = manifest;
    return true;
  }

  @override
  Future<bool> acceptSegment({
    required MigrationTransferManifest manifest,
    required MigrationEncryptedSegment segment,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    onSegment(segment);
    return true;
  }

  @override
  Future<bool> complete({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    completeCalls += 1;
    return true;
  }
}

class _CutoverRecordingBundleReceiver extends _RecordingBundleReceiver
    implements AccountMigrationLocalBundleCutoverReceiver {
  MigrationCutoverRecord? oldBlockProof;
  MigrationCutoverRecord? newActiveProof;
  int oldBlockProofCalls = 0;

  _CutoverRecordingBundleReceiver() : super(onSegment: (_) {});

  @override
  Future<MigrationCutoverRecord?> acceptOldBlockProof({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
    required MigrationCutoverRecord oldBlockProof,
  }) async {
    oldBlockProofCalls += 1;
    this.oldBlockProof = oldBlockProof;
    if (!oldBlockProof.provesOldNetworkBlocked) {
      return null;
    }
    final now = _fixedNow();
    newActiveProof =
        MigrationCutoverRecord.initial(
          sessionId: manifest.sessionId,
          accountPeerId: transcript.oldPhonePeerId,
          devicePeerId: pendingSession.newPhoneEphemeralPublicKey,
          deviceRole: MigrationCutoverDeviceRole.newPhone,
          now: now,
        ).copyWith(
          phase: MigrationCutoverPhase.newActiveCommitted,
          oldNetworkBlocked: true,
          oldNetworkBlockedAt: oldBlockProof.oldNetworkBlockedAt,
          oldBlockProofReceived: true,
          oldBlockProofReceivedAt: now,
          newActiveCommitted: true,
          newActiveCommittedAt: now,
        );
    return newActiveProof;
  }
}

class _DeterministicSegmentCrypto implements MigrationSegmentCrypto {
  @override
  Future<MigrationEncryptedSegment> encryptSegment({
    required Uint8List plaintext,
    required String recipientMlKemPublicKey,
    required MigrationSegmentAssociatedData associatedData,
  }) async {
    final ciphertext =
        'ct:${associatedData.segmentIndex}:${base64Encode(plaintext)}:${associatedData.sha256Hex}';
    return MigrationEncryptedSegment(
      index: associatedData.segmentIndex,
      kem: 'kem-${associatedData.segmentIndex}',
      ciphertext: ciphertext,
      nonce: 'nonce-${associatedData.segmentIndex}',
      plaintextSha256: migrationTransferSha256Hex(plaintext),
      ciphertextSha256: migrationTransferStringSha256Hex(ciphertext),
      associatedDataSha256: associatedData.sha256Hex,
    );
  }

  @override
  Future<Uint8List> decryptSegment({
    required MigrationEncryptedSegment encryptedSegment,
    required String ownMlKemSecretKey,
    required MigrationSegmentAssociatedData associatedData,
  }) async {
    return Uint8List.fromList(
      base64Decode(encryptedSegment.ciphertext.split(':')[2]),
    );
  }
}

MigrationTransferManifest _manifestFor({
  required Map<int, Uint8List> plaintextSegments,
  required String sessionId,
  int segmentSize = 4,
}) {
  const bundleId = 'bundle-1';
  const manifestSha256 = 'manifest-hash';
  final descriptors = <MigrationTransferSegmentDescriptor>[];
  var offset = 0;
  for (final entry in plaintextSegments.entries) {
    final aad = MigrationSegmentAssociatedData(
      sessionId: sessionId,
      bundleId: bundleId,
      segmentIndex: entry.key,
      offset: offset,
      plaintextLength: entry.value.length,
      manifestSha256: manifestSha256,
    );
    final ciphertext =
        'ct:${entry.key}:${base64Encode(entry.value)}:${aad.sha256Hex}';
    descriptors.add(
      MigrationTransferSegmentDescriptor(
        index: entry.key,
        offset: offset,
        plaintextLength: entry.value.length,
        plaintextSha256: migrationTransferSha256Hex(entry.value),
        ciphertextSha256: migrationTransferStringSha256Hex(ciphertext),
        nonce: 'nonce-${entry.key}',
      ),
    );
    offset += entry.value.length;
  }
  return MigrationTransferManifest.legacyV1(
    sessionId: sessionId,
    bundleId: bundleId,
    segmentSize: segmentSize,
    totalBytes: offset,
    manifestSha256: manifestSha256,
    segments: descriptors,
  );
}

DateTime _fixedNow() => DateTime.utc(2026, 6, 8, 12);

MigrationCutoverLeaseCleanup _noopLeaseCleanup() {
  return MigrationCutoverLeaseCleanup(
    unregisterPersonalRendezvous: () async {},
    unregisterInboxPushToken: () async {},
    clearLocalStalePushToken: () async {},
  );
}

class _MemoryAuthorityRepository
    implements AccountMigrationAuthorityRepository {
  AccountMigrationAuthorityRecord? saved;
  final history = <AccountMigrationAuthorityRecord>[];

  @override
  Future<void> clearAuthority() async {
    saved = null;
  }

  @override
  Future<AccountMigrationAuthorityRecord?> loadAuthority() async => saved;

  @override
  Future<void> saveAuthority(AccountMigrationAuthorityRecord record) async {
    saved = record;
    history.add(record);
  }
}

class _ThrowingSaveAuthorityRepository extends _MemoryAuthorityRepository {
  bool Function(AccountMigrationAuthorityRecord record) shouldThrow = (_) =>
      false;

  @override
  Future<void> saveAuthority(AccountMigrationAuthorityRecord record) async {
    if (shouldThrow(record)) {
      throw StateError('secure store write failed');
    }
    await super.saveAuthority(record);
  }
}

class _MemoryCutoverRepository implements MigrationCutoverRepository {
  MigrationCutoverRecord? saved;

  @override
  Future<void> clearCutover() async {
    saved = null;
  }

  @override
  Future<MigrationCutoverRecord?> loadCutover() async => saved;

  @override
  Future<void> saveCutover(MigrationCutoverRecord record) async {
    saved = record;
  }
}
