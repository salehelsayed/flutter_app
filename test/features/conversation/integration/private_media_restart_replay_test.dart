import 'dart:io';

import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  test(
    'reopen terminalizes opening and preserves monotonic expiry across rollback',
    () async {
      final temp = Directory.systemTemp.createTempSync('private-restart-');
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final dbPath = p.join(temp.path, 'identity.db');
      var fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: dbPath,
      );
      addTearDown(() async {
        try {
          await fixture.dispose();
        } catch (_) {}
      });

      await fixture.seedDirectParent('restart-view-once');
      await fixture.db.update(
        'messages',
        {
          'private_media_policy_version': 1,
          'private_media_mode': 'view_once',
          'private_media_state': 'opening',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1100,
        },
        where: 'id = ?',
        whereArgs: ['restart-view-once'],
      );
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: 'restart-view-once-att',
          messageId: 'restart-view-once',
          mime: 'image/jpeg',
          size: 1,
          mediaType: 'image',
          localPath: 'media/contact-1/restart-view-once-att.jpg',
          downloadStatus: 'done',
          createdAt: '2026-07-11T00:00:00.000Z',
          encryptionKeyBase64: 'a2V5',
          encryptionNonce: 'bm9uY2U=',
        ),
        owner: MediaOwnerLane.direct,
      );
      await fixture.seedDirectParent('restart-disappearing');
      await fixture.db.update(
        'messages',
        {
          'private_media_policy_version': 1,
          'private_media_mode': 'disappearing',
          'private_media_duration_seconds': 3600,
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_expires_at_ms': 2000,
          'private_media_clock_high_water_ms': 1500,
        },
        where: 'id = ?',
        whereArgs: ['restart-disappearing'],
      );
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: 'restart-disappearing-att',
          messageId: 'restart-disappearing',
          mime: 'image/jpeg',
          size: 1,
          mediaType: 'image',
          localPath: 'media/contact-1/restart-disappearing-att.jpg',
          downloadStatus: 'done',
          createdAt: '2026-07-11T00:00:00.000Z',
          encryptionKeyBase64: 'a2V5',
          encryptionNonce: 'bm9uY2U=',
        ),
        owner: MediaOwnerLane.direct,
      );

      fixture = await fixture.reopen();
      final adapter = DirectPrivateMediaLifecycle(
        messageRepository: fixture.messageRepo,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: FakeMediaFileManager(),
      );
      var currentTimeMs = 1000;
      final restarted = PrivateMediaLifecycleEngine(
        adapter: adapter,
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => currentTimeMs,
      );

      final first = await restarted.reconcileLocalLifecycle();
      final parent = await fixture.messageRepo.getMessage('restart-view-once');
      expect(
        first.terminalClaims,
        1,
        reason: 'only interrupted View Once is terminal at rollback time',
      );
      expect(
        first.cleanupCompleted,
        1,
        reason: 'unexpired disappearing residue remains locally available',
      );
      expect(parent!.privateMediaState.name, 'consumed');
      expect(await fixture.rawAttachmentRow('restart-view-once-att'), isNull);
      final rollbackParent = await fixture.messageRepo.getMessage(
        'restart-disappearing',
      );
      expect(rollbackParent!.privateMediaState.name, 'available');
      expect(rollbackParent.privateMediaClockHighWaterMs, 1500);
      expect(rollbackParent.privateMediaTerminalAtMs, isNull);
      expect(
        await fixture.rawAttachmentRow('restart-disappearing-att'),
        isNotNull,
      );
      expect(
        await fixture.messageRepo.claimPrivateMediaOpening(
          'restart-view-once',
          nowMs: 2100,
        ),
        isFalse,
        reason: 'replay cannot reopen a terminal parent or remint a lease',
      );

      final second = await restarted.reconcileLocalLifecycle();
      expect(second.terminalClaims, 0);
      expect(second.cleanupCompleted, 0);
      expect(second.retainedAfterError, 0);

      currentTimeMs = 2000;
      final atDeadline = await restarted.reconcileLocalLifecycle();
      expect(atDeadline.terminalClaims, 1);
      expect(atDeadline.cleanupCompleted, 1);
      final expired = await fixture.messageRepo.getMessage(
        'restart-disappearing',
      );
      expect(expired!.privateMediaState.name, 'expired');
      expect(expired.privateMediaClockHighWaterMs, 2000);
      expect(expired.privateMediaTerminalAtMs, 2000);
      expect(
        await fixture.rawAttachmentRow('restart-disappearing-att'),
        isNull,
      );

      final settled = await restarted.reconcileLocalLifecycle();
      expect(settled.terminalClaims, 0);
      expect(settled.cleanupCompleted, 0);
      expect(settled.retainedAfterError, 0);
    },
  );

  test(
    'restart reclaims an exclusive downloading claim and staged bytes',
    () async {
      final temp = Directory.systemTemp.createTempSync(
        'private-download-restart-',
      );
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final dbPath = p.join(temp.path, 'identity.db');
      var fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: dbPath,
      );
      addTearDown(() async {
        try {
          await fixture.dispose();
        } catch (_) {}
      });
      const messageId = 'restart-downloading';
      const attachmentId = 'restart-downloading-att';
      await fixture.seedDirectParent(messageId);
      await fixture.db.update(
        'messages',
        {
          'private_media_policy_version': 1,
          'private_media_mode': 'protected',
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          downloadStatus: 'downloading',
          createdAt: '2026-07-11T00:00:00.000Z',
          encryptionKeyBase64: 'cmVzdGFydC1rZXk=',
          encryptionNonce: 'bm9uY2U=',
        ),
        owner: MediaOwnerLane.direct,
      );
      final canonical = File(
        p.join(
          FakeMediaFileManager.testRootPath,
          'media/contact-1/$attachmentId.jpg',
        ),
      )..createSync(recursive: true);
      canonical.writeAsBytesSync(const [9, 9, 9]);
      final staged = File('${canonical.path}.part')
        ..writeAsBytesSync(const [1, 2]);

      fixture = await fixture.reopen();
      final restarted = PrivateMediaLifecycleEngine(
        adapter: DirectPrivateMediaLifecycle(
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: FakeMediaFileManager(),
        ),
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => 1100,
      );
      final result = await restarted.reconcileLocalLifecycle(limit: 1);

      expect(result.downloadClaimsRecovered, 1);
      expect(result.retainedAfterError, 0);
      expect(canonical.existsSync(), isFalse);
      expect(staged.existsSync(), isFalse);
      final row = await fixture.rawAttachmentRow(attachmentId);
      expect(row!['download_status'], 'failed');
      expect(row['download_retry_count'], 1);
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isTrue,
        reason: 'active parent retains decryptability for the next retry',
      );
      expect(
        await fixture.repo.beginDirectPrivateMediaDownload(
          attachmentId,
          messageId: messageId,
          nowMs: 1200,
        ),
        isTrue,
      );
    },
  );

  test('restart terminalizes viewer state without destroying unhanded-off '
      'outbox custody', () async {
    final temp = Directory.systemTemp.createTempSync('private-outbox-restart-');
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final dbPath = p.join(temp.path, 'identity.db');
    var fixture = await MediaRepositoryRealDbFixture.create(
      databasePath: dbPath,
    );
    addTearDown(() async {
      try {
        await fixture.dispose();
      } catch (_) {}
    });

    final seed = await _seedOutgoingPendingPrivateMedia(
      fixture,
      messageId: 'restart-outbox-no-handoff',
      attachmentId: 'restart-outbox-no-handoff-att',
      wireEnvelope: null,
    );
    addTearDown(() => _deleteSeedFiles(seed));
    final rowBeforeRestart = await fixture.rawAttachmentRow(seed.attachmentId);
    expect(rowBeforeRestart, isNotNull);

    fixture = await fixture.reopen();
    final first = await _restartEngine(fixture).reconcileLocalLifecycle();

    expect(first.terminalClaims, 1);
    final terminalParent = await fixture.messageRepo.getMessage(seed.messageId);
    expect(terminalParent!.privateMediaState.name, 'consumed');
    expect(
      await fixture.messageRepo.claimPrivateMediaOpening(
        seed.messageId,
        nowMs: 1300,
      ),
      isFalse,
      reason: 'retained transport custody must never restore viewer access',
    );
    expect(
      await fixture.rawAttachmentRow(seed.attachmentId),
      equals(rowBeforeRestart),
      reason: 'a null envelope has not durably handed off the outbound bytes',
    );
    expect(seed.pendingFile.existsSync(), isTrue);
    final messageBeforeHandoff = await _rawMessageRow(fixture, seed.messageId);
    expect(messageBeforeHandoff!['wire_envelope'], isNull);
    expect(messageBeforeHandoff['status'], 'sending');

    final canonicalRelative = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: 'contact-1',
      blobId: seed.attachmentId,
      mime: 'image/jpeg',
    );
    final canonicalFile = File(
      p.join(FakeMediaFileManager.testRootPath, canonicalRelative),
    );
    final identityRepository = FakeIdentityRepository()
      ..seed(
        FakeIdentityRepository.makeIdentity(
          peerId: 'self-peer',
          mlKemPublicKey: 'self-ml-kem-public',
          mlKemSecretKey: 'self-ml-kem-secret',
        ),
      );
    final contactRepository = FakeContactRepository()
      ..seed(<ContactModel>[
        const ContactModel(
          peerId: 'contact-1',
          publicKey: 'contact-public-key',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'Restart Contact',
          signature: 'contact-signature',
          scannedAt: '2026-07-20T00:00:00.000Z',
          mlKemPublicKey: 'contact-ml-kem-public',
        ),
      ]);
    final retried = await retryIncompleteUploads(
      mediaAttachmentRepo: fixture.repo,
      messageRepo: fixture.messageRepo,
      bridge: FakeBridge(),
      p2pService: FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'self-peer',
          circuitAddresses: <String>['/p2p-circuit/restart'],
        ),
        storeInInboxResult: true,
      ),
      identityRepo: identityRepository,
      contactRepo: contactRepository,
      mediaFileManager: FakeMediaFileManager(),
      uploadMediaFn:
          ({
            required bridge,
            required localFilePath,
            required mime,
            required recipientPeerId,
            mediaFileManager,
            width,
            height,
            durationMs,
            waveform,
            allowedPeers,
            blobId,
            deleteSourceWhenDone = false,
            preparedArtifact,
          }) async {
            canonicalFile.parent.createSync(recursive: true);
            canonicalFile.writeAsBytesSync(
              File(localFilePath).readAsBytesSync(),
              flush: true,
            );
            return UploadMediaSucceeded(
              MediaAttachment(
                id: seed.attachmentId,
                messageId: seed.messageId,
                mime: mime,
                size: canonicalFile.lengthSync(),
                mediaType: 'image',
                localPath: canonicalRelative,
                downloadStatus: 'done',
                createdAt: '2026-07-20T00:00:00.000Z',
                contentHash:
                    '0123456789abcdef0123456789abcdef'
                    '0123456789abcdef0123456789abcdef',
                encryptionKeyBase64: 'cmVzdGFydC10cmFuc3BvcnQta2V5',
                encryptionNonce: 'cmVzdGFydC10cmFuc3BvcnQtbm9uY2U=',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                ownerLane: MediaOwnerLane.direct,
              ),
            );
          },
    );
    expect(retried, 1);
    final handedOffParent = await fixture.messageRepo.getMessage(
      seed.messageId,
    );
    expect(handedOffParent!.privateMediaState.name, 'consumed');
    expect(handedOffParent.wireEnvelope, isNotNull);

    fixture = await fixture.reopen();

    final afterHandoff = await _restartEngine(
      fixture,
    ).reconcileLocalLifecycle();
    expect(afterHandoff.terminalClaims, 0);
    expect(await fixture.rawAttachmentRow(seed.attachmentId), isNull);
    expect(seed.pendingFile.existsSync(), isFalse);
    expect(canonicalFile.existsSync(), isFalse);
    final restartedParent = await fixture.messageRepo.getMessage(
      seed.messageId,
    );
    expect(restartedParent!.privateMediaState.name, 'consumed');
    expect(restartedParent.wireEnvelope, isNotNull);
  });

  test('restart retains a committed canonical outbox until a real failed retry '
      'persists the missing envelope', () async {
    final temp = Directory.systemTemp.createTempSync(
      'private-committed-outbox-restart-',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final dbPath = p.join(temp.path, 'identity.db');
    var fixture = await MediaRepositoryRealDbFixture.create(
      databasePath: dbPath,
    );
    addTearDown(() async {
      try {
        await fixture.dispose();
      } catch (_) {}
    });

    const messageId = 'restart-committed-no-handoff';
    const attachmentId = 'restart-committed-no-handoff-att';
    const completionKey = 'cmVzdGFydC1jb21taXR0ZWQta2V5';
    final seed = await _seedOutgoingPendingPrivateMedia(
      fixture,
      messageId: messageId,
      attachmentId: attachmentId,
      wireEnvelope: null,
      privateState: 'available',
      seedCanonicalResidue: true,
    );
    addTearDown(() => _deleteSeedFiles(seed));
    final pendingRelative =
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: messageId,
          attachmentId: attachmentId,
          mime: 'image/jpeg',
        );
    final canonicalRelative = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: 'contact-1',
      blobId: attachmentId,
      mime: 'image/jpeg',
    );
    final completed = MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: 'image/jpeg',
      size: seed.pendingFile.lengthSync(),
      mediaType: 'image',
      localPath: canonicalRelative,
      downloadStatus: 'done',
      createdAt: '2026-07-20T00:00:00.000Z',
      contentHash:
          '0123456789abcdef0123456789abcdef'
          '0123456789abcdef0123456789abcdef',
      encryptionKeyBase64: completionKey,
      encryptionNonce: 'cmVzdGFydC1jb21taXR0ZWQtbm9uY2U=',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      ownerLane: MediaOwnerLane.direct,
    );
    final committed = await fixture
        .repo
        .outgoingDirectPrivateMutationCoordinator
        .commitCompletion(
          attachment: completed,
          expectedPendingLocalPath: pendingRelative,
        );
    expect(committed.outcome, OutgoingDirectPrivateMutationOutcome.committed);
    expect(
      (await fixture.rawAttachmentRow(attachmentId))?['download_status'],
      'done',
    );
    expect(
      await fixture.secureKeyStore.read(seed.secureKeyName),
      completionKey,
    );

    // Model the durable first-frame/close transition after the available
    // completion committed, followed by a process death before the upload
    // caller can persist its freshly built wire envelope.
    expect(
      await fixture.db.update(
        'messages',
        <String, Object?>{
          'private_media_state': 'consumed',
          'private_media_revealed_at_ms': 1200,
          'private_media_terminal_at_ms': 1300,
          'private_media_clock_high_water_ms': 1300,
          'status': 'sending',
          'wire_envelope': null,
        },
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      ),
      1,
    );
    fixture = await fixture.reopen();

    await _restartEngine(fixture).reconcileLocalLifecycle();
    final retained = await fixture.rawAttachmentRow(attachmentId);
    expect(retained?['download_status'], 'done');
    expect(retained?['local_path'], canonicalRelative);
    expect(seed.pendingFile.existsSync(), isTrue);
    expect(seed.canonicalFile!.existsSync(), isTrue);
    expect(
      await fixture.secureKeyStore.read(seed.secureKeyName),
      completionKey,
    );
    expect(
      (await fixture.messageRepo.getMessage(messageId))?.wireEnvelope,
      isNull,
    );

    expect(
      await fixture.db.update(
        'messages',
        const <String, Object?>{'status': 'failed'},
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      ),
      1,
    );
    final identityRepository = FakeIdentityRepository()
      ..seed(
        FakeIdentityRepository.makeIdentity(
          peerId: 'self-peer',
          mlKemPublicKey: 'self-ml-kem-public',
          mlKemSecretKey: 'self-ml-kem-secret',
        ),
      );
    final contactRepository = FakeContactRepository()
      ..seed(<ContactModel>[
        const ContactModel(
          peerId: 'contact-1',
          publicKey: 'contact-public-key',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'Restart Contact',
          signature: 'contact-signature',
          scannedAt: '2026-07-20T00:00:00.000Z',
          mlKemPublicKey: 'contact-ml-kem-public',
        ),
      ]);
    final retried = await retryFailedMessage(
      messageId: messageId,
      messageRepo: fixture.messageRepo,
      identityRepo: identityRepository,
      contactRepo: contactRepository,
      p2pService: FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'self-peer',
          circuitAddresses: <String>['/p2p-circuit/restart'],
        ),
        storeInInboxResult: true,
      ),
      bridge: FakeBridge(),
      mediaAttachmentRepo: fixture.repo,
      mediaFileManager: FakeMediaFileManager(),
    );
    expect(retried, 1);
    expect(
      (await fixture.messageRepo.getMessage(messageId))?.wireEnvelope,
      isNotNull,
    );

    expect(await fixture.rawAttachmentRow(attachmentId), isNull);
    expect(seed.pendingFile.existsSync(), isFalse);
    expect(seed.canonicalFile!.existsSync(), isFalse);
    expect(
      await fixture.secureKeyStore.containsKey(seed.secureKeyName),
      isFalse,
    );
  });

  test(
    'restart with durable envelope handoff cleans terminal outbox custody',
    () async {
      final temp = Directory.systemTemp.createTempSync(
        'private-outbox-handed-off-',
      );
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final dbPath = p.join(temp.path, 'identity.db');
      var fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: dbPath,
      );
      addTearDown(() async {
        try {
          await fixture.dispose();
        } catch (_) {}
      });

      final seed = await _seedOutgoingPendingPrivateMedia(
        fixture,
        messageId: 'restart-outbox-handed-off',
        attachmentId: 'restart-outbox-handed-off-att',
        wireEnvelope: '{"type":"direct_message","custody":"already-durable"}',
        seedStoredKey: true,
      );
      addTearDown(() => _deleteSeedFiles(seed));
      expect(
        await fixture.secureKeyStore.containsKey(seed.secureKeyName),
        isTrue,
      );

      fixture = await fixture.reopen();
      final result = await _restartEngine(fixture).reconcileLocalLifecycle();

      expect(result.terminalClaims, 1);
      final parent = await fixture.messageRepo.getMessage(seed.messageId);
      expect(parent!.privateMediaState.name, 'consumed');
      expect(await fixture.rawAttachmentRow(seed.attachmentId), isNull);
      expect(seed.pendingFile.existsSync(), isFalse);
      expect(
        await fixture.secureKeyStore.containsKey(seed.secureKeyName),
        isFalse,
      );
    },
  );

  test(
    'explicit hidden and deleted intent clean pending outbox custody without '
    'an envelope',
    () async {
      final temp = Directory.systemTemp.createTempSync(
        'private-outbox-explicit-intent-',
      );
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final dbPath = p.join(temp.path, 'identity.db');
      var fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: dbPath,
      );
      addTearDown(() async {
        try {
          await fixture.dispose();
        } catch (_) {}
      });

      final hidden = await _seedOutgoingPendingPrivateMedia(
        fixture,
        messageId: 'restart-outbox-hidden',
        attachmentId: 'restart-outbox-hidden-att',
        wireEnvelope: null,
        privateState: 'available',
        hiddenAt: '2026-07-20T10:00:00.000Z',
        seedStoredKey: true,
      );
      final deleted = await _seedOutgoingPendingPrivateMedia(
        fixture,
        messageId: 'restart-outbox-deleted',
        attachmentId: 'restart-outbox-deleted-att',
        wireEnvelope: null,
        privateState: 'available',
        deletedAt: '2026-07-20T10:01:00.000Z',
        seedStoredKey: true,
      );
      addTearDown(() => _deleteSeedFiles(hidden));
      addTearDown(() => _deleteSeedFiles(deleted));

      fixture = await fixture.reopen();
      final result = await _restartEngine(fixture).reconcileLocalLifecycle();

      expect(result.terminalClaims, 0);
      for (final seed in [hidden, deleted]) {
        expect(await fixture.rawAttachmentRow(seed.attachmentId), isNull);
        expect(seed.pendingFile.existsSync(), isFalse);
        expect(
          await fixture.secureKeyStore.containsKey(seed.secureKeyName),
          isFalse,
        );
      }
      final hiddenRow = await _rawMessageRow(fixture, hidden.messageId);
      final deletedRow = await _rawMessageRow(fixture, deleted.messageId);
      expect(hiddenRow!['hidden_at'], isNotNull);
      expect(deletedRow!['deleted_at'], isNotNull);
    },
  );

  test('failed atomic rollback/finalize leaves opening and restart fails '
      'closed without inferring canonical completion', () async {
    final temp = Directory.systemTemp.createTempSync(
      'private-outbox-precommit-crash-',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final dbPath = p.join(temp.path, 'identity.db');
    var fixture = await MediaRepositoryRealDbFixture.create(
      databasePath: dbPath,
    );
    addTearDown(() async {
      try {
        await fixture.dispose();
      } catch (_) {}
    });

    // These are the only durable artifacts a transaction returning false or
    // throwing before commit may leave. No process-local completion token is
    // carried across reopen; same-sized canonical residue is deliberately
    // present so restart cannot infer a successful upload from bytes alone.
    final falseResult = await _seedOutgoingPendingPrivateMedia(
      fixture,
      messageId: 'restart-precommit-false',
      attachmentId: 'restart-precommit-false-att',
      wireEnvelope: null,
      status: 'sending',
      seedCanonicalResidue: true,
    );
    final thrownResult = await _seedOutgoingPendingPrivateMedia(
      fixture,
      messageId: 'restart-precommit-throw',
      attachmentId: 'restart-precommit-throw-att',
      wireEnvelope: null,
      status: 'failed',
      seedCanonicalResidue: true,
    );
    addTearDown(() => _deleteSeedFiles(falseResult));
    addTearDown(() => _deleteSeedFiles(thrownResult));
    final rowsBeforeRestart = <String, Map<String, Object?>?>{
      for (final seed in [falseResult, thrownResult])
        seed.attachmentId: await fixture.rawAttachmentRow(seed.attachmentId),
    };

    fixture = await fixture.reopen();
    final result = await _restartEngine(fixture).reconcileLocalLifecycle();

    expect(result.terminalClaims, 2);
    for (final seed in [falseResult, thrownResult]) {
      final parent = await fixture.messageRepo.getMessage(seed.messageId);
      expect(parent!.privateMediaState.name, 'consumed');
      expect(
        await fixture.rawAttachmentRow(seed.attachmentId),
        equals(rowsBeforeRestart[seed.attachmentId]),
        reason: 'canonical residue cannot fabricate a committed completion',
      );
      expect(seed.pendingFile.existsSync(), isTrue);
      expect(
        await fixture.messageRepo.claimPrivateMediaOpening(
          seed.messageId,
          nowMs: 1400,
        ),
        isFalse,
      );
    }
  });
  group('Plan 354 private strict restart', () {
    test('TC-354-03c private strict cutpoints and terminal retention survive '
        'file SQLite reopen', () async {
      final dir = Directory.systemTemp.createTempSync('tc354_03c_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final databasePath = p.join(dir.path, 'restart.db');
      const messageId = 'tc354-03c-private';
      const attachmentId = 'tc354-03c-private-att';
      const contentHash =
          '9999999999999999999999999999999999999999999999999999999999999999';

      DirectMediaBlobCustodyRow rowFor(DirectMediaBlobCustodyState state) =>
          DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: state,
            inboxCustodyIncarnationId: null,
            recipientPeerId: 'peer-bob',
            ciphertextRelativePath:
                'direct_media_blob_custody_v1/${'8' * 64}/$attachmentId.blob',
            contentHash: contentHash,
            ciphertextSize: 4096,
            expiresAtMs: state == DirectMediaBlobCustodyState.outgoingStored
                ? 2200000000000
                : null,
            custodyRelayPeerId:
                state == DirectMediaBlobCustodyState.outgoingStored
                ? 'relay-354-03c'
                : null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: '2026-08-10T14:00:00.000Z',
            updatedAt: '2026-08-10T14:00:00.000Z',
          );

      for (final cut in <DirectMediaBlobCustodyState>[
        DirectMediaBlobCustodyState.outgoingPrepared,
        DirectMediaBlobCustodyState.outgoingStored,
      ]) {
        // Cut N: the durable generation exists and the parent has already
        // become terminal (the sender consumed or hid it).
        final fixture = await MediaRepositoryRealDbFixture.create(
          databasePath: databasePath,
        );
        await fixture.db.insert('messages', <String, Object?>{
          'id': messageId,
          'contact_peer_id': 'peer-bob',
          'sender_peer_id': 'peer-alice',
          'text': '',
          'timestamp': '2026-08-10T14:00:00.000Z',
          'status': 'sending',
          'is_incoming': 0,
          'created_at': '2026-08-10T14:00:00.000Z',
          'dedup_key': messageId,
          'private_media_policy_version': 1,
          'private_media_mode': 'protected',
          'private_media_state': 'consumed',
          'private_media_terminal_at_ms': 1200,
        });
        await fixture.db.insert('media_attachments', <String, Object?>{
          'id': attachmentId,
          'message_id': messageId,
          'owner_lane': 'direct',
          'mime': 'image/jpeg',
          'size': 2048,
          'media_type': 'image',
          'local_path': 'pending_uploads/$messageId/$attachmentId.jpg',
          'download_status': 'upload_pending',
          'created_at': '2026-08-10T14:00:00.000Z',
          'content_hash': contentHash,
          'encryption_key_base64': secureStoreReferenceForKey(
            mediaAttachmentEncryptionKeyStoreName(attachmentId),
          ),
          'encryption_nonce': 'tc354-03c-nonce',
          'encryption_scheme': 'blob_aes_256_gcm_v1',
        });
        await fixture.db.insert(
          kDirectMediaBlobCustodyTable,
          rowFor(cut).toMap(),
        );
        await fixture.dispose();

        // Restart: reopen the SAME file database.
        final reopened = await MediaRepositoryRealDbFixture.create(
          databasePath: databasePath,
        );
        final custody =
            await (reopened.repo as DirectMediaBlobCustodyRepository)
                .loadDirectMediaBlobCustodyForAttachment(attachmentId);
        expect(
          custody?.state,
          cut,
          reason: 'the exact cutpoint survives a real file reopen',
        );
        expect(custody?.contentHash, contentHash);
        expect(
          custody?.expiresAtMs,
          cut == DirectMediaBlobCustodyState.outgoingStored
              ? 2200000000000
              : null,
        );
        // The complete private projection is still present for the retry
        // owner: attachment row, key reference, and pending plaintext path.
        final durable = await reopened.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        );
        expect(durable, hasLength(1));
        expect(durable.single.contentHash, contentHash);
        expect(durable.single.encryptionNonce, 'tc354-03c-nonce');
        expect(
          durable.single.localPath,
          'pending_uploads/$messageId/$attachmentId.jpg',
        );
        // The v111 obligation has no FK: it legitimately outlives its
        // terminal parent and is not cascaded away by the reopen.
        expect(
          (await reopened.db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          )).single['private_media_state'],
          'consumed',
        );
        await reopened.dispose();
        File(databasePath).deleteSync();
      }
    });

    test('TC-354-05c private strict decrypt crash leaves no plaintext and no '
        'resurrection', () {
      final owner = File(
        'lib/features/conversation/application/'
        'strict_direct_media_blob_download_ack_owner.dart',
      ).readAsStringSync();
      final lifecycle = File(
        'lib/features/conversation/application/'
        'direct_private_media_lifecycle.dart',
      ).readAsStringSync();

      // A crashed earlier attempt may leave the deterministic pair behind.
      // The next attempt removes BOTH before reusing them, so a decrypt-
      // before-commit crash can never be adopted as durable bytes.
      final reuse = owner.indexOf(
        'if (privateDeterministicStaging) {\n        // A crashed earlier attempt',
      );
      expect(reuse, greaterThan(-1));
      final reuseBody = owner.substring(reuse, reuse + 500);
      expect(
        reuseBody.contains('await _deleteRegularFile(relayCandidate);'),
        isTrue,
      );
      expect(reuseBody.contains('privateDecryptStagingPath('), isTrue);
      final firstNetwork = owner.indexOf('await callP2PMediaDownload(');
      expect(
        reuse,
        lessThan(firstNetwork),
        reason: 'stale staging is cleared before the network call',
      );

      // The canonical plaintext is only ever promoted INSIDE the custody
      // lifecycle, after the durable DB commit; a refused commit removes it.
      final decrypt = owner.indexOf('await callBlobDecrypt(');
      final commit = owner.indexOf('commitIncomingDirectMediaBlobLocalPath(');
      expect(decrypt, greaterThan(-1));
      expect(commit, greaterThan(decrypt));
      expect(
        owner.contains('await _deleteRegularFile(decrypted);'),
        isTrue,
        reason: 'a wrong-size decrypt leaves no plaintext behind',
      );

      // Restart recovery removes the same two exact siblings, so a crash
      // between decrypt and commit leaves nothing to resurrect.
      final wipe = lifecycle.indexOf(
        'Future<void> _deleteExactAppOwnedArtifacts({',
      );
      final wipeBody = lifecycle.substring(wipe, wipe + 3000);
      expect(wipeBody.contains(".path}.private.enc'"), isTrue);
      expect(wipeBody.contains(".path}.private.enc.dec'"), isTrue);
      // Interrupted-download recovery reuses that same exact wipe.
      final recovery = lifecycle.indexOf(
        'Future<int> recoverInterruptedDownloadsWithinLock(',
      );
      expect(recovery, greaterThan(-1));
      expect(
        lifecycle
            .substring(recovery, wipe > recovery ? wipe : recovery + 2500)
            .contains('_deleteExactAppOwnedArtifacts('),
        isTrue,
      );
    });

    test('TC-355-02b interrupted private strict download reopens without '
        'residue or v111 loss', () async {
      final temp = Directory.systemTemp.createTempSync(
        'private-strict-interrupted-',
      );
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final databasePath = p.join(temp.path, 'identity.db');
      const messageId = 'tc355-02b-message';
      const attachmentId = 'tc355-02b-attachment';
      const contactPeerId = 'tc355-02b-peer';
      const contentHash =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      const ciphertext = <int>[4, 2, 4, 2];
      final manager = FakeMediaFileManager();
      final canonicalPath = await manager.localPathForAttachment(
        contactPeerId: contactPeerId,
        blobId: attachmentId,
        mime: 'image/jpeg',
      );
      final lanSource = File('$canonicalPath.enc');
      final stagedCiphertext = File('$canonicalPath.private.enc');
      final stagedDecrypt = File('$canonicalPath.private.enc.dec');
      final unrelatedSibling = File(
        '${File(canonicalPath).parent.path}/tc355-02b-other.jpg',
      );
      for (final file in <File>[
        lanSource,
        stagedCiphertext,
        stagedDecrypt,
        unrelatedSibling,
      ]) {
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(ciphertext);
      }
      addTearDown(() {
        for (final file in <File>[
          lanSource,
          stagedCiphertext,
          stagedDecrypt,
          unrelatedSibling,
          File(canonicalPath),
        ]) {
          if (file.existsSync()) file.deleteSync();
        }
      });

      var fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: databasePath,
      );
      addTearDown(() async {
        try {
          await fixture.dispose();
        } catch (_) {}
      });
      await fixture.db.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': contactPeerId,
        'sender_peer_id': contactPeerId,
        'text': '',
        'timestamp': '2026-08-10T15:00:00.000Z',
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': '2026-08-10T15:00:00.000Z',
        'dedup_key': messageId,
        'private_media_policy_version': 1,
        'private_media_mode': 'protected',
        'private_media_state': 'available',
        'private_media_received_at_ms': 1000,
        'private_media_clock_high_water_ms': 1000,
      });
      // The crash cut: the DB claim is durable but no commit ever ran.
      await fixture.db.insert('media_attachments', <String, Object?>{
        'id': attachmentId,
        'message_id': messageId,
        'owner_lane': 'direct',
        'mime': 'image/jpeg',
        'size': 4,
        'media_type': 'image',
        'local_path': null,
        'download_status': 'downloading',
        'created_at': '2026-08-10T15:00:00.000Z',
        'content_hash': contentHash,
        'encryption_key_base64': secureStoreReferenceForKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        'encryption_nonce': 'tc355-02b-nonce',
        'encryption_scheme': 'blob_aes_256_gcm_v1',
      });
      final custody = DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: messageId,
        direction: DirectMediaBlobCustodyDirection.incoming,
        state: DirectMediaBlobCustodyState.incomingCommitted,
        inboxCustodyIncarnationId: null,
        recipientPeerId: null,
        ciphertextRelativePath: null,
        contentHash: contentHash,
        ciphertextSize: ciphertext.length,
        expiresAtMs: 2200000000000,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: '2026-08-10T15:00:00.000Z',
        updatedAt: '2026-08-10T15:00:00.000Z',
      );
      await fixture.db.insert(kDirectMediaBlobCustodyTable, custody.toMap());

      fixture = await fixture.reopen();
      final engine = PrivateMediaLifecycleEngine(
        adapter: DirectPrivateMediaLifecycle(
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: manager,
        ),
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => 1200,
      );
      final result = await engine.reconcileLocalLifecycle();

      expect(result.downloadClaimsRecovered, greaterThanOrEqualTo(1));
      // Only this attempt's deterministic staging pair is removed.
      expect(stagedCiphertext.existsSync(), isFalse);
      expect(stagedDecrypt.existsSync(), isFalse);
      expect(File(canonicalPath).existsSync(), isFalse);
      // The verified legacy LAN ciphertext is the ONLY retry source this
      // transfer has, so restart recovery must leave it byte-identical.
      expect(lanSource.existsSync(), isTrue);
      expect(lanSource.readAsBytesSync(), ciphertext);
      // Unrelated siblings are never in the exact expansion.
      expect(unrelatedSibling.existsSync(), isTrue);
      // The claim is released to a retryable status with no stale path.
      final row = await fixture.rawAttachmentRow(attachmentId);
      expect(row!['download_status'], isNot('downloading'));
      expect(row['download_status'], isNot('done'));
      expect(row['local_path'], isNull);
      // v111 survives the crash and the recovery untouched.
      final retained = await (fixture.repo as DirectMediaBlobCustodyRepository)
          .loadDirectMediaBlobCustodyForAttachment(attachmentId);
      expect(retained, isNotNull);
      expect(retained!.state, DirectMediaBlobCustodyState.incomingCommitted);
      expect(retained.contentHash, contentHash);
    });

    test(
      'TC-358-04b disappearing strict custody and local expiry remain '
      'independent across reopen',
      () async {
        final temp = Directory.systemTemp.createTempSync(
          'private-strict-disappearing-',
        );
        addTearDown(() {
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });
        const contactPeerId = 'tc358-04b-peer';
        const contentHash =
            'aaaabbbbccccddddeeeeffff00001111222233334444555566667777888899aa';
        const ciphertext = <int>[9, 9, 4, 2];
        const receivedAtMs = 1_800_000_000_000;
        const durationSeconds = 604800;
        const deadlineMs = receivedAtMs + durationSeconds * 1000;

        /// Seeds one durable incoming disappearing parent through the exact
        /// production strict-private stage, so its receiver clock and its
        /// independent v111 transport lease are authored by real code.
        Future<void> seed(
          MediaRepositoryRealDbFixture fixture, {
          required String messageId,
          required String attachmentId,
          required int blobExpiresAtMs,
        }) async {
          final custody = DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.incoming,
            state: DirectMediaBlobCustodyState.incomingCommitted,
            inboxCustodyIncarnationId: null,
            recipientPeerId: null,
            ciphertextRelativePath: null,
            contentHash: contentHash,
            ciphertextSize: ciphertext.length,
            expiresAtMs: blobExpiresAtMs,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: '2026-08-11T12:00:00.000Z',
            updatedAt: '2026-08-11T12:00:00.000Z',
          );
          final stage =
              await (fixture.repo
                      as IncomingDirectPrivateMediaBlobCustodyRepository)
                  .stageIncomingDirectPrivateMediaBlobCustody(
                    message: ConversationMessage(
                      id: messageId,
                      contactPeerId: contactPeerId,
                      senderPeerId: contactPeerId,
                      text: '',
                      timestamp: '2026-08-11T12:00:00.000Z',
                      status: 'delivered',
                      isIncoming: true,
                      createdAt: '2026-08-11T12:00:00.000Z',
                      dedupKey: messageId,
                      privateMediaPolicy: PrivateMediaPolicy.disappearing(
                        durationSeconds,
                      ),
                      privateMediaState: PrivateMediaLifecycleState.available,
                      privateMediaReceivedAtMs: receivedAtMs,
                      privateMediaExpiresAtMs: deadlineMs,
                      privateMediaClockHighWaterMs: receivedAtMs,
                    ),
                    attachment: MediaAttachment(
                      id: attachmentId,
                      messageId: messageId,
                      mime: 'image/jpeg',
                      size: 4,
                      mediaType: 'image',
                      downloadStatus: 'pending',
                      createdAt: '2026-08-11T12:00:00.000Z',
                      contentHash: contentHash,
                      encryptionKeyBase64: 'tc358-04b-raw-key',
                      encryptionNonce: 'tc358-04b-nonce',
                      encryptionScheme: 'blob_aes_256_gcm_v1',
                      ownerLane: MediaOwnerLane.direct,
                      blobCustody: DirectMediaBlobCustodyCommitment(
                        contentHash: contentHash,
                        ciphertextSize: ciphertext.length,
                        expiresAtMs: blobExpiresAtMs,
                      ),
                    ),
                    custodyRow: custody,
                  );
          expect(stage.outcome.name, 'applied', reason: messageId);
        }

        Future<Map<String, Object?>> parentOf(
          MediaRepositoryRealDbFixture fixture,
          String messageId,
        ) async => (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        )).single;

        // Order A: the CONTENT deadline passes first. It expires the parent
        // and lets terminal cleanup own the key/attachment, while the v111
        // transport lease survives untouched across a real reopen.
        {
          final databasePath = p.join(temp.path, 'content-first.db');
          var fixture = await MediaRepositoryRealDbFixture.create(
            databasePath: databasePath,
          );
          addTearDown(() async {
            try {
              await fixture.dispose();
            } catch (_) {}
          });
          const messageId = 'tc358-04b-content-first';
          const attachmentId = 'tc358-04b-content-first-att';
          await seed(
            fixture,
            messageId: messageId,
            attachmentId: attachmentId,
            blobExpiresAtMs: deadlineMs + 900_000,
          );

          fixture = await fixture.reopen();
          // The reopened process still sees the exact durable clock.
          final reopened = await parentOf(fixture, messageId);
          expect(reopened['private_media_received_at_ms'], receivedAtMs);
          expect(reopened['private_media_expires_at_ms'], deadlineMs);
          expect(reopened['private_media_clock_high_water_ms'], receivedAtMs);

          final engine = PrivateMediaLifecycleEngine(
            adapter: DirectPrivateMediaLifecycle(
              messageRepository: fixture.messageRepo,
              mediaAttachmentRepository: fixture.repo,
              mediaFileManager: FakeMediaFileManager(),
            ),
            lifecycleLock: fixture.repo.lifecycleLock,
            nowMs: () => deadlineMs + 1000,
          );
          await engine.reconcileLocalLifecycle();

          final expired = await parentOf(fixture, messageId);
          expect(expired['private_media_state'], 'expired');
          expect(
            expired['private_media_expires_at_ms'],
            deadlineMs,
            reason: 'content expiry never rewrites its own deadline',
          );
          final lease =
              await (fixture.repo as DirectMediaBlobCustodyRepository)
                  .loadDirectMediaBlobCustodyForAttachment(attachmentId);
          expect(
            lease,
            isNotNull,
            reason: 'the no-FK v111 lease outlives content expiry',
          );
          expect(lease!.expiresAtMs, deadlineMs + 900_000);
        }

        // Order B: the TRANSPORT lease expires first. Converging it removes
        // only v111; the unexpired local parent and its clock are untouched.
        {
          final databasePath = p.join(temp.path, 'transport-first.db');
          var fixture = await MediaRepositoryRealDbFixture.create(
            databasePath: databasePath,
          );
          addTearDown(() async {
            try {
              await fixture.dispose();
            } catch (_) {}
          });
          const messageId = 'tc358-04b-transport-first';
          const attachmentId = 'tc358-04b-transport-first-att';
          await seed(
            fixture,
            messageId: messageId,
            attachmentId: attachmentId,
            blobExpiresAtMs: receivedAtMs + 60_000,
          );

          fixture = await fixture.reopen();
          final incoming =
              fixture.repo as IncomingDirectMediaBlobCustodyRepository;
          final lease =
              await (fixture.repo as DirectMediaBlobCustodyRepository)
                  .loadDirectMediaBlobCustodyForAttachment(attachmentId);
          expect(
            await incoming.deleteIncomingDirectMediaBlobIfExpired(
              expected: lease!,
              nowMs: receivedAtMs + 120_000,
            ),
            isTrue,
          );
          expect(
            await (fixture.repo as DirectMediaBlobCustodyRepository)
                .loadDirectMediaBlobCustodyForAttachment(attachmentId),
            isNull,
          );

          final parent = await parentOf(fixture, messageId);
          expect(
            parent['private_media_state'],
            'available',
            reason: 'a blob-lease expiry never expires the local card',
          );
          expect(parent['private_media_received_at_ms'], receivedAtMs);
          expect(parent['private_media_expires_at_ms'], deadlineMs);
          expect(parent['private_media_clock_high_water_ms'], receivedAtMs);
          expect(
            await fixture.rawAttachmentRow(attachmentId),
            isNotNull,
            reason: 'transport convergence never deletes the local row',
          );
        }
      },
    );
  });
}

PrivateMediaLifecycleEngine _restartEngine(
  MediaRepositoryRealDbFixture fixture,
) {
  return PrivateMediaLifecycleEngine(
    adapter: DirectPrivateMediaLifecycle(
      messageRepository: fixture.messageRepo,
      mediaAttachmentRepository: fixture.repo,
      mediaFileManager: FakeMediaFileManager(),
    ),
    lifecycleLock: fixture.repo.lifecycleLock,
    nowMs: () => 1200,
  );
}

Future<_OutgoingPendingRestartSeed> _seedOutgoingPendingPrivateMedia(
  MediaRepositoryRealDbFixture fixture, {
  required String messageId,
  required String attachmentId,
  required String? wireEnvelope,
  String status = 'sending',
  String privateState = 'opening',
  String? hiddenAt,
  String? deletedAt,
  bool seedCanonicalResidue = false,
  bool seedStoredKey = false,
}) async {
  const mime = 'image/jpeg';
  const bytes = <int>[7, 8, 9, 10];
  final pendingRelative = MediaFilePathConvention.relativePathForPendingUpload(
    messageId: messageId,
    attachmentId: attachmentId,
    mime: mime,
  );
  final pendingFile = File(
    p.join(FakeMediaFileManager.testRootPath, pendingRelative),
  );
  pendingFile.createSync(recursive: true);
  pendingFile.writeAsBytesSync(bytes);

  File? canonicalFile;
  if (seedCanonicalResidue) {
    canonicalFile = File(
      p.join(
        FakeMediaFileManager.testRootPath,
        MediaFilePathConvention.relativePathForAttachment(
          contactPeerId: 'contact-1',
          blobId: attachmentId,
          mime: mime,
        ),
      ),
    );
    canonicalFile.createSync(recursive: true);
    canonicalFile.writeAsBytesSync(bytes);
  }

  await fixture.seedDirectParent(messageId);
  await fixture.repo.saveAttachment(
    MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: mime,
      size: bytes.length,
      mediaType: 'image',
      localPath: pendingRelative,
      downloadStatus: 'upload_pending',
      createdAt: '2026-07-20T00:00:00.000Z',
      contentHash: seedStoredKey
          ? '0123456789abcdef0123456789abcdef'
                '0123456789abcdef0123456789abcdef'
          : null,
      encryptionKeyBase64: seedStoredKey
          ? 'cmVzdGFydC1jdXN0b2R5LWtleQ=='
          : null,
      encryptionNonce: seedStoredKey ? 'cmVzdGFydC1ub25jZQ==' : null,
      encryptionScheme: seedStoredKey
          ? kMediaAttachmentEncryptionSchemeBlobAesGcmV1
          : null,
    ),
    owner: MediaOwnerLane.direct,
  );
  expect(
    await fixture.db.update(
      'messages',
      {
        'sender_peer_id': 'self-peer',
        'text': '',
        'status': status,
        'is_incoming': 0,
        'wire_envelope': wireEnvelope,
        'private_media_policy_version': 1,
        'private_media_mode': 'protected',
        'private_media_state': privateState,
        'private_media_received_at_ms': 1000,
        'private_media_clock_high_water_ms': 1100,
        'private_media_revealed_at_ms': null,
        'private_media_terminal_at_ms': null,
        'hidden_at': hiddenAt,
        'deleted_at': deletedAt,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    ),
    1,
  );

  return _OutgoingPendingRestartSeed(
    messageId: messageId,
    attachmentId: attachmentId,
    pendingFile: pendingFile,
    canonicalFile: canonicalFile,
    secureKeyName: mediaAttachmentEncryptionKeyStoreName(attachmentId),
  );
}

Future<Map<String, Object?>?> _rawMessageRow(
  MediaRepositoryRealDbFixture fixture,
  String messageId,
) async {
  final rows = await fixture.db.query(
    'messages',
    where: 'id = ?',
    whereArgs: [messageId],
  );
  return rows.isEmpty ? null : rows.single;
}

void _deleteSeedFiles(_OutgoingPendingRestartSeed seed) {
  for (final file in [seed.pendingFile, seed.canonicalFile]) {
    if (file != null && file.existsSync()) file.deleteSync();
  }
}

class _OutgoingPendingRestartSeed {
  const _OutgoingPendingRestartSeed({
    required this.messageId,
    required this.attachmentId,
    required this.pendingFile,
    required this.canonicalFile,
    required this.secureKeyName,
  });

  final String messageId;
  final String attachmentId;
  final File pendingFile;
  final File? canonicalFile;
  final String secureKeyName;
}
