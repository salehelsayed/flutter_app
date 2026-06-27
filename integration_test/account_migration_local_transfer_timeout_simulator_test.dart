import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_local_transfer_runtime.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_pairing_session_repository.dart';

/// Simulator proof for the Move Account local transfer timeout plan (test 6):
/// a Pixel -> iPhone-sized bundle (>= 34 prepared encrypted segments) driven
/// through the full old-phone + new-phone
/// [AccountMigrationLocalTransferRuntime] pair over real loopback HTTP, with a
/// deterministic injectable per-segment receiver delay.
///
/// Closure preference: the near-budget delay scenario must SUCCEED with the
/// scaled command budget; the over-budget scenario must fail TYPED
/// (localTransferTimedOut + POST_FAILED diagnostics), never as an escaped
/// exception or a bundleSourceFailed mislabel.
const _segmentCount = 34;
const _segmentBytes = 768;
const _segmentProgressEvent =
    'ACCOUNT_MIGRATION_LOCAL_TRANSFER_SEGMENT_PROGRESS';
const _postFailedEvent = 'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_FAILED';
const _bundleSourceFailedEvent =
    'ACCOUNT_MIGRATION_TRANSFER_BUNDLE_SOURCE_FAILED';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('account migration local transfer timeout simulator', () {
    late Map<String, LocalPeer> registry;
    late _MemoryPairingSessionRepository pairingRepo;
    late LocalWsServer newPhoneServer;
    late LocalWsServer oldPhoneServer;
    late _SharedFakeDiscovery newPhoneDiscovery;
    late _SharedFakeDiscovery oldPhoneDiscovery;
    late List<Map<String, dynamic>> events;

    setUp(() {
      registry = <String, LocalPeer>{};
      pairingRepo = _MemoryPairingSessionRepository();
      newPhoneServer = LocalWsServer();
      oldPhoneServer = LocalWsServer();
      newPhoneDiscovery = _SharedFakeDiscovery(registry);
      oldPhoneDiscovery = _SharedFakeDiscovery(registry);
      events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
    });

    tearDown(() async {
      debugSetFlowEventSink(null);
      await newPhoneServer.stop();
      await oldPhoneServer.stop();
      newPhoneDiscovery.dispose();
      oldPhoneDiscovery.dispose();
    });

    testWidgets(
      'near-budget receiver delay still completes a 34-segment transfer '
      'with monotonic segment progress',
      (_) async {
        final output = await _savePendingSession(pairingRepo);
        final receiver = _DelayingBundleReceiver(
          segmentDelay: (segmentIndex) => segmentIndex == 7
              ? const Duration(milliseconds: 600)
              : Duration.zero,
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

        final bundle = _prepareEncryptedBundle(
          sessionId: output.payload.sessionId,
        );
        // A ~1KB+ segment POST with a 1000 B/s floor scales the
        // closeAwaitResponse budget well past the 600ms receiver delay even
        // though the flat httpTimeout (200ms) alone would have failed it.
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => bundle,
          httpTimeout: const Duration(milliseconds: 200),
          transferBytesPerSecondFloor: 1000,
          maxCommandTimeout: const Duration(seconds: 5),
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );
        await receiver.drainPendingDelays();

        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(
          receiver.acceptedSegmentIndexes,
          List<int>.generate(_segmentCount, (index) => index),
        );

        final progressDetails = _eventDetails(events, _segmentProgressEvent);
        expect(
          progressDetails.map((details) => details['sentCount']).toList(),
          List<int>.generate(_segmentCount, (index) => index + 1),
          reason: 'segment progress sentCount must be monotonic 1..N',
        );
        for (final details in progressDetails) {
          expect(details['sessionId'], output.payload.sessionId);
          expect(details['segmentCount'], _segmentCount);
        }
        expect(_eventDetails(events, _postFailedEvent), isEmpty);
        expect(_eventDetails(events, _bundleSourceFailedEvent), isEmpty);
      },
    );

    testWidgets(
      'over-budget receiver delay fails typed as localTransferTimedOut '
      'with segment POST diagnostics',
      (_) async {
        final output = await _savePendingSession(pairingRepo);
        const failingSegmentIndex = 3;
        final receiver = _DelayingBundleReceiver(
          segmentDelay: (segmentIndex) => segmentIndex == failingSegmentIndex
              ? const Duration(milliseconds: 900)
              : Duration.zero,
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

        final bundle = _prepareEncryptedBundle(
          sessionId: output.payload.sessionId,
        );
        // With the default 64KiB/s floor a ~1KB segment adds only ~20ms to
        // the 150ms httpTimeout and the budget is clamped by
        // maxCommandTimeout(300ms), so the 900ms receiver delay is over
        // budget and must produce a TYPED timeout failure.
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => bundle,
          httpTimeout: const Duration(milliseconds: 150),
          transferBytesPerSecondFloor: 64 * 1024,
          maxCommandTimeout: const Duration(milliseconds: 300),
        );

        // Must complete with a typed failure result, never throw.
        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );
        // Let the stalled receiver handler settle inside the test scope so a
        // late response write cannot escape as an unhandled async error.
        await receiver.drainPendingDelays();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(result.isSuccess, isFalse);
        expect(
          result.failureCode,
          AccountMigrationTransferFailureCode.localTransferTimedOut,
        );
        expect(
          result.safeMessage,
          accountMigrationLocalTransferStalledSafeMessage,
        );

        final segmentFailures = _eventDetails(events, _postFailedEvent)
            .where((details) => details['command'] == 'segment')
            .toList();
        expect(
          segmentFailures,
          isNotEmpty,
          reason: 'segment timeout must emit $_postFailedEvent diagnostics',
        );
        final failure = segmentFailures.first;
        expect(failure['sessionId'], output.payload.sessionId);
        expect(failure['commandStage'], 'segmentTransfer');
        expect(failure['segmentIndex'], failingSegmentIndex);
        expect(failure['segmentCount'], _segmentCount);
        expect(failure['phase'], 'closeAwaitResponse');
        expect(failure['elapsedMs'], isA<int>());
        expect(failure['reason'], 'timeout');
        expect(failure['errorType'], 'TimeoutException');

        // Segments before the injected stall were posted successfully.
        expect(
          _eventDetails(events, _segmentProgressEvent)
              .map((details) => details['sentCount'])
              .toList(),
          List<int>.generate(failingSegmentIndex, (index) => index + 1),
        );

        // The transfer-phase stall must never be mislabeled as a bundle
        // source failure.
        expect(_eventDetails(events, _bundleSourceFailedEvent), isEmpty);
        expect(
          events.where((event) {
            final details = event['details'];
            return details is Map && details['reason'] == 'bundleSourceFailed';
          }),
          isEmpty,
        );
      },
    );
  });
}

List<Map<String, dynamic>> _eventDetails(
  List<Map<String, dynamic>> events,
  String eventName,
) {
  return [
    for (final event in events)
      if (event['event'] == eventName)
        Map<String, dynamic>.from(
          event['details'] as Map? ?? const <String, dynamic>{},
        ),
  ];
}

AccountMigrationLocalTransferBundle _prepareEncryptedBundle({
  required String sessionId,
}) {
  final plaintextSegments = <int, Uint8List>{
    for (var index = 0; index < _segmentCount; index++)
      index: Uint8List.fromList(
        List<int>.generate(
          _segmentBytes,
          (byte) => (index * 31 + byte) % 251,
        ),
      ),
  };
  final manifest = _manifestFor(
    plaintextSegments: plaintextSegments,
    sessionId: sessionId,
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

MigrationTransferManifest _manifestFor({
  required Map<int, Uint8List> plaintextSegments,
  required String sessionId,
}) {
  const bundleId = 'bundle-timeout-sim';
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
  // The simulator pins the v1 prepared-segment wire path (its typed timeout
  // contracts are protocol-independent); the plain constructor now defaults
  // to protocol v2, which would route the sender into the chunk stream.
  return MigrationTransferManifest.legacyV1(
    sessionId: sessionId,
    bundleId: bundleId,
    segmentSize: _segmentBytes,
    totalBytes: offset,
    manifestSha256: manifestSha256,
    segments: descriptors,
  );
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
  _MemoryPairingSessionRepository repo,
) async {
  final createdAt = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
  final payload = MigrationQrPayload(
    sessionId: 'session-timeout-sim',
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(minutes: 5)),
    newPhoneEphemeralPublicKey: 'new-phone-public-key',
    channelNonce: 'channel-nonce',
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
  return MigrationQrBuildOutput(payload: payload, qrJson: payload.toJsonString());
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

/// Bundle receiver with a deterministic injectable per-segment delay so the
/// simulator can hold one segment near or over the sender's command budget.
class _DelayingBundleReceiver implements AccountMigrationLocalBundleReceiver {
  _DelayingBundleReceiver({required this.segmentDelay});

  final Duration Function(int segmentIndex) segmentDelay;
  final acceptedSegmentIndexes = <int>[];
  final _pendingDelays = <Future<void>>[];

  /// Awaits every injected delay so late receiver work settles inside the
  /// test scope instead of leaking past tearDown.
  Future<void> drainPendingDelays() => Future.wait(_pendingDelays);

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
    return true;
  }

  @override
  Future<bool> acceptSegment({
    required MigrationTransferManifest manifest,
    required MigrationEncryptedSegment segment,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    final delay = segmentDelay(segment.index);
    if (delay > Duration.zero) {
      final pending = Future<void>.delayed(delay);
      _pendingDelays.add(pending);
      await pending;
    }
    acceptedSegmentIndexes.add(segment.index);
    return true;
  }

  @override
  Future<bool> complete({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    return true;
  }
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
  final Map<String, LocalPeer> registry;
  final _controller = StreamController<Map<String, LocalPeer>>.broadcast();
  String? advertisedPeerId;

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
