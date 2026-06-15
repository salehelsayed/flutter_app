import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_bundle_transfer.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_local_transfer_runtime.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_entry_stream_source.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_file_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_pairing_session_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

const _benchMb = int.fromEnvironment('MIGRATION_BENCH_MB', defaultValue: 1);
const _segmentBytes = 1024 * 1024;
const _syntheticWriteBlockBytes = 768 * 1024;
const _benchmarkFileRelativePath = 'media/scale/benchmark.bin';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'P0-7 scale benchmark emits production receiver metrics',
    (_) async {
      final registry = <String, LocalPeer>{};
      final pairingRepo = _MemoryPairingSessionRepository();
      final newPhoneServer = LocalWsServer();
      final oldPhoneServer = LocalWsServer();
      final newPhoneDiscovery = _SharedFakeDiscovery(registry);
      final oldPhoneDiscovery = _SharedFakeDiscovery(registry);
      final flowEvents = <Map<String, dynamic>>[];
      _BenchmarkBundleArtifacts? artifacts;
      var outcome = 'not_started';
      var segmentCount = 0;
      final rssSamples = <int>[ProcessInfo.currentRss];
      final wall = Stopwatch()..start();
      Timer? sampler;
      debugSetFlowEventSink(flowEvents.add);

      try {
        final output = await _savePendingSession(pairingRepo);
        artifacts = await _buildDiskBackedBenchmarkBundle(
          sessionId: output.payload.sessionId,
          targetPayloadBytes: _benchMb * _segmentBytes,
        );
        segmentCount = artifacts.bundle.manifest.totalChunkCount;

        final destinationStore = _MemorySecureKeyStore();
        final secureStorageStaging = MigrationSecureStorageStaging(
          primaryStore: destinationStore,
        );
        final receiver = AccountMigrationProductionBundleReceiver(
          streamCrypto: _BenchmarkStreamCrypto(),
          secureStorageStaging: secureStorageStaging,
          databaseImportStaging: _BenchmarkDatabaseImportStaging(
            secureStorageStaging: secureStorageStaging,
          ),
          stagingDirectoryPath: p.join(artifacts.tempDir.path, 'incoming'),
          documentsRootPath: p.join(
            artifacts.tempDir.path,
            'receiver-documents',
          ),
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

        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: (_) async => artifacts!.bundle,
          streamCrypto: _BenchmarkStreamCrypto(),
          maxCommandTimeout: const Duration(minutes: 10),
        );

        sampler = Timer.periodic(const Duration(milliseconds: 250), (_) {
          rssSamples.add(ProcessInfo.currentRss);
        });
        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );
        outcome = result.isSuccess
            ? 'success'
            : 'failure:${result.failureCode?.name ?? 'unknown'}';
        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(
          _receiverCompleteStages(
            flowEvents,
            sessionId: output.payload.sessionId,
          ),
          containsAll(<String>[
            'ledgerCheck',
            'secureStaging',
            'stagedDbOpen',
            'importFiles',
            'authorityRecord',
          ]),
        );
        final imported = File(
          p.join(
            artifacts.tempDir.path,
            'receiver-documents',
            _benchmarkFileRelativePath,
          ),
        );
        expect(imported.existsSync(), isTrue);
        expect(imported.lengthSync(), artifacts.syntheticFileBytes);
      } catch (error) {
        outcome = 'error:${error.runtimeType}';
        rethrow;
      } finally {
        debugSetFlowEventSink(null);
        sampler?.cancel();
        rssSamples.add(ProcessInfo.currentRss);
        wall.stop();
        await newPhoneServer.stop();
        await oldPhoneServer.stop();
        newPhoneDiscovery.dispose();
        oldPhoneDiscovery.dispose();
        final payloadBytes = artifacts?.payloadBytes ?? 0;
        final syntheticFileBytes = artifacts?.syntheticFileBytes ?? 0;
        final receiverStages = _receiverCompleteStages(
          flowEvents,
          sessionId: artifacts?.bundle.manifest.sessionId,
        );
        await artifacts?.dispose();
        final peakRss = rssSamples.reduce((a, b) => a > b ? a : b);
        // The release evidence is the JSON payload after
        // ACCOUNT_MIGRATION_SCALE_BENCHMARK, captured from device logs.
        // ignore: avoid_print
        print(
          'ACCOUNT_MIGRATION_SCALE_BENCHMARK '
          '${jsonEncode({'benchMb': _benchMb, 'wallMs': wall.elapsedMilliseconds, 'segmentCount': segmentCount, 'payloadBytes': payloadBytes, 'syntheticFileBytes': syntheticFileBytes, 'rssStart': rssSamples.first, 'rssPeak': peakRss, 'rssEnd': rssSamples.last, 'outcome': outcome, 'receiverCompleteStages': receiverStages})}',
        );
      }
    },
    // Scaled for multi-GB runs: ~4 MB/s measured loopback throughput means
    // 10 GB needs ~45 min of transfer plus generation/hash overhead.
    timeout: const Timeout(Duration(minutes: 30 + _benchMb ~/ 75)),
  );
}

Future<_BenchmarkBundleArtifacts> _buildDiskBackedBenchmarkBundle({
  required String sessionId,
  required int targetPayloadBytes,
}) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'account_migration_scale_',
  );
  try {
    // Protocol v2 streams raw entry bytes (no base64 envelope), so the
    // synthetic file carries the full target size.
    final syntheticFileBytes = math.max(1024, targetPayloadBytes - 64 * 1024);
    final mediaFile = File(p.join(tempDir.path, 'export', 'benchmark.bin'));
    final fileSha256 = await _writeSyntheticFile(
      mediaFile,
      syntheticFileBytes,
    );

    final dbBytes = Uint8List.fromList(
      utf8.encode('benchmark-staged-db:$sessionId'),
    );
    final dbFile = File(p.join(tempDir.path, 'export', 'snapshot.db'));
    await dbFile.writeAsBytes(dbBytes, flush: true);
    final dbManifest = MigrationDatabaseManifest.current(
      sourceAppVersion: 'benchmark',
      sourceBuildNumber: 'benchmark',
      schemaInventory: MigrationDatabaseSchemaInventory.fromTables({
        'identity': const ['id', 'peer_id', 'public_key', 'username'],
      }),
      databaseChecksumSha256: migrationTransferSha256Hex(dbBytes),
      cipherMetadata: const MigrationDatabaseCipherMetadata(
        cipherVersion: 'benchmark',
        policy: MigrationDatabaseCipherPolicy.compatible,
      ),
    );

    final metadataFile = File(p.join(tempDir.path, 'export', 'metadata.json'));
    await metadataFile.writeAsString(
      migrationTransferCanonicalJson({
        'version': 2,
        'session_id': sessionId,
        'database': {'manifest': dbManifest.toJson()},
        'secure_storage': _secureStorageEntries(),
        'files': {
          'manifest': MigrationFileManifest(
            items: [
              MigrationFileManifestItem(
                kind: MigrationFileManifestItemKind.chatMedia,
                criticality: MigrationFileCriticality.critical,
                relativePath: _benchmarkFileRelativePath,
                sizeBytes: syntheticFileBytes,
                sha256: fileSha256,
                sourceTable: 'benchmark',
                sourceId: 'scale-file',
              ),
            ],
          ).toJson(),
        },
      }),
      flush: true,
    );

    final bundle = await MigrationEntryStreamSource(
      fileReader: const IoMigrationEntryFileReader(),
      chunkSize: _segmentBytes,
    ).build(
      sessionId: sessionId,
      bundleId:
          'scale-benchmark-${migrationTransferStringSha256Hex(sessionId).substring(0, 16)}',
      entries: [
        MigrationEntryStreamInput(
          entryId: 'database',
          kind: MigrationTransferEntryKind.database,
          filePath: dbFile.path,
        ),
        MigrationEntryStreamInput(
          entryId: 'file-0',
          kind: MigrationTransferEntryKind.file,
          filePath: mediaFile.path,
          relativePath: _benchmarkFileRelativePath,
          sizeBytes: syntheticFileBytes,
          sha256: fileSha256,
        ),
        MigrationEntryStreamInput(
          entryId: 'secure-values',
          kind: MigrationTransferEntryKind.secureValues,
          filePath: metadataFile.path,
        ),
      ],
    );
    return _BenchmarkBundleArtifacts(
      tempDir: tempDir,
      bundle: bundle,
      payloadBytes: bundle.manifest.totalBytes,
      syntheticFileBytes: syntheticFileBytes,
    );
  } catch (_) {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    rethrow;
  }
}

List<Map<String, Object?>> _secureStorageEntries() {
  final keys = [
    MigrationSecureStorageRegistry.fixedKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: MigrationSecureStorageRegistry.dbEncryptionKey,
    )!,
    MigrationSecureStorageRegistry.fixedKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: MigrationSecureStorageRegistry.identityPrivateKey,
    )!,
  ];
  return [
    for (final key in keys)
      {
        'key': _secureStorageKeyJson(key),
        'value_base64': base64Encode(utf8.encode('benchmark:${key.activeKey}')),
      },
  ];
}

Map<String, Object?> _secureStorageKeyJson(MigrationSecureStorageKey key) {
  return {
    'scope': key.scope.name,
    'active_key': key.activeKey,
    'category': key.category.name,
    'policy': key.policy.name,
    'criticality': key.criticality.name,
    'include_in_export_payload': key.includeInExportPayload,
  };
}

/// Streams a deterministic synthetic file to disk and returns its sha256
/// (never holding more than one write block in memory).
Future<String> _writeSyntheticFile(File file, int byteCount) async {
  await file.parent.create(recursive: true);
  final digestSink = _DigestSink();
  final hashSink = sha256.startChunkedConversion(digestSink);
  final block = Uint8List(_syntheticWriteBlockBytes);
  for (var i = 0; i < block.length; i += 1) {
    block[i] = (i * 31 + 17) & 0xff;
  }
  final sink = file.openWrite();
  try {
    var remaining = byteCount;
    var sinceFlush = 0;
    while (remaining > 0) {
      final size = math.min(remaining, block.length);
      final view = Uint8List.sublistView(block, 0, size);
      hashSink.add(view);
      sink.add(view);
      remaining -= size;
      sinceFlush += size;
      // Yield to the event loop every ~32 MiB: a multi-GB synchronous loop
      // on the main isolate starves input dispatch and ANR-kills the app
      // (and unbounded sink buffering would defeat the RSS measurement).
      if (sinceFlush >= 32 * 1024 * 1024) {
        sinceFlush = 0;
        await sink.flush();
      }
    }
  } finally {
    await sink.close();
  }
  hashSink.close();
  return digestSink.value.toString();
}

List<String> _receiverCompleteStages(
  List<Map<String, dynamic>> events, {
  required String? sessionId,
}) {
  if (sessionId == null) {
    return const [];
  }
  return events
      .where(
        (event) =>
            event['event'] ==
            'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_COMPLETE_STAGE',
      )
      .map((event) => Map<String, dynamic>.from(event['details'] as Map))
      .where((details) => details['sessionId'] == sessionId)
      .map((details) => details['stage'] as String)
      .toList(growable: false);
}

class _BenchmarkBundleArtifacts {
  final Directory tempDir;
  final AccountMigrationLocalTransferBundle bundle;
  final int payloadBytes;
  final int syntheticFileBytes;

  const _BenchmarkBundleArtifacts({
    required this.tempDir,
    required this.bundle,
    required this.payloadBytes,
    required this.syntheticFileBytes,
  });

  Future<void> dispose() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final digest = _value;
    if (digest == null) {
      throw StateError('digest was not completed');
    }
    return digest;
  }

  @override
  void add(Digest data) {
    _value = data;
  }

  @override
  void close() {}
}

class _BenchmarkDatabaseImportStaging extends MigrationDatabaseImportStaging {
  _BenchmarkDatabaseImportStaging({required super.secureStorageStaging});

  @override
  Future<MigrationDatabaseImportStagingResult> openVerifiedStagedDatabase({
    required String sessionId,
    required String stagedDatabasePath,
    required MigrationDatabaseManifest manifest,
  }) async {
    final dbKey = MigrationSecureStorageRegistry.fixedKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: MigrationSecureStorageRegistry.dbEncryptionKey,
    )!;
    final stagedKey = await secureStorageStaging.readStagedValue(
      sessionId: sessionId,
      key: dbKey,
    );
    if (stagedKey == null || stagedKey.isEmpty) {
      throw StateError('benchmark staged database key missing');
    }
    final stagedDatabase = File(stagedDatabasePath);
    if (!await stagedDatabase.exists()) {
      throw StateError('benchmark staged database missing');
    }
    final checksum =
        await MigrationDatabaseSnapshotExporter.computeFileChecksum(
          stagedDatabasePath,
        );
    if (checksum != manifest.databaseChecksumSha256) {
      throw StateError('benchmark staged database checksum mismatch');
    }
    return MigrationDatabaseImportStagingResult(
      database: _UnusedDatabase(),
      manifest: manifest,
      stagedDatabasePath: stagedDatabasePath,
    );
  }
}

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Deterministic reversible stream crypto with realistic wire shapes (XOR
/// keystream + GCM-sized tag + 1088-byte KEM blob), bridge-free so the
/// benchmark isolates transport + import costs.
class _BenchmarkStreamCrypto implements MigrationStreamCrypto {
  static const int kemCiphertextBytes = 1088;
  static const int tagBytes = 16;

  int _keyByte(int chunkIndex, int position) =>
      (chunkIndex * 7 + position * 13 + 31) & 0xff;

  Uint8List _xor(int chunkIndex, Uint8List input) {
    final output = Uint8List(input.length);
    for (var i = 0; i < input.length; i++) {
      output[i] = input[i] ^ _keyByte(chunkIndex, i);
    }
    return output;
  }

  String _kemFor(String sessionId, String bundleId) {
    final seed = '$sessionId|$bundleId'.codeUnits;
    return base64Encode(
      Uint8List.fromList(
        List<int>.generate(
          kemCiphertextBytes,
          (i) => (seed[i % seed.length] + i) & 0xff,
        ),
      ),
    );
  }

  @override
  Future<MigrationStreamEncryptSession> encapsulateSession({
    required String recipientMlKemPublicKey,
    required String sessionId,
    required String bundleId,
    required MigrationStreamDirection direction,
  }) async {
    return MigrationStreamEncryptSession(
      sessionId: sessionId,
      bundleId: bundleId,
      direction: direction,
      sessionKey: base64Encode(Uint8List(32)),
      kemCiphertext: _kemFor(sessionId, bundleId),
    );
  }

  @override
  Future<MigrationStreamDecryptSession> decapsulateSession({
    required String ownMlKemSecretKey,
    required String sessionId,
    required String bundleId,
    required MigrationStreamDirection direction,
    required String kemCiphertext,
  }) async {
    return MigrationStreamDecryptSession(
      sessionId: sessionId,
      bundleId: bundleId,
      direction: direction,
      sessionKey: base64Encode(Uint8List(32)),
      kemCiphertext: kemCiphertext,
    );
  }

  @override
  Future<MigrationEncryptedChunk> encryptChunk({
    required MigrationStreamEncryptSession session,
    required Uint8List plaintext,
    required MigrationChunkAssociatedData associatedData,
    required String nonce,
  }) async {
    final index = associatedData.chunkIndex;
    final body = BytesBuilder(copy: false)
      ..add(_xor(index, plaintext))
      ..add(
        Uint8List.fromList(
          List<int>.generate(tagBytes, (i) => _keyByte(index, i + 1) ^ 0x5a),
        ),
      );
    final ciphertext = base64Encode(body.takeBytes());
    return MigrationEncryptedChunk(
      entryId: associatedData.entryId,
      chunkIndex: index,
      offset: associatedData.offset,
      isFinal: associatedData.isFinal,
      kemCiphertext: session.kemCiphertext,
      ciphertext: ciphertext,
      nonce: nonce,
      plaintextSha256: migrationTransferSha256Hex(plaintext),
      ciphertextSha256: migrationTransferStringSha256Hex(ciphertext),
      associatedDataSha256: associatedData.sha256Hex,
    );
  }

  @override
  Future<Uint8List> decryptChunk({
    required MigrationStreamDecryptSession session,
    required MigrationEncryptedChunk encryptedChunk,
    required MigrationChunkAssociatedData associatedData,
  }) async {
    if (encryptedChunk.associatedDataSha256 != associatedData.sha256Hex) {
      throw const MigrationStreamCryptoException('associated data mismatch');
    }
    final body = base64Decode(encryptedChunk.ciphertext);
    final encrypted = Uint8List.sublistView(body, 0, body.length - tagBytes);
    return _xor(encryptedChunk.chunkIndex, encrypted);
  }
}

class _MemorySecureKeyStore implements SecureKeyStore {
  final _values = <String, String>{};

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

Future<MigrationQrBuildOutput> _savePendingSession(
  _MemoryPairingSessionRepository repo,
) async {
  final createdAt = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
  final payload = MigrationQrPayload(
    sessionId: 'scale-benchmark-session',
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(minutes: 30)),
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
    authenticatedChannelBinding: 'scale-benchmark-binding',
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
  final Map<String, LocalPeer> registry;
  final _controller = StreamController<Map<String, LocalPeer>>.broadcast();
  String? advertisedPeerId;

  _SharedFakeDiscovery(this.registry);

  @override
  Future<void> startAdvertising(String peerId, int wsPort) async {
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
