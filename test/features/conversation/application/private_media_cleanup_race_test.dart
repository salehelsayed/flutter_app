import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' show ConflictAlgorithm;

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

class _UnreadableExistingKeyStore extends RecordingSecureKeyStore {
  String? unreadableKey;
  var deleteCalls = 0;

  @override
  Future<String?> read(String key) async =>
      key == unreadableKey ? null : super.read(key);

  @override
  Future<void> delete(String key) async {
    deleteCalls++;
    await super.delete(key);
  }
}

class _ThrowingReadKeyStore extends RecordingSecureKeyStore {
  @override
  Future<String?> read(String key) async =>
      throw StateError('corrupt secure key read');
}

class _FailOnceMediaFileManager extends FakeMediaFileManager {
  bool failNext = true;

  @override
  Future<void> deleteFile(
    String localPath, {
    String caller = 'MediaFileManager.deleteFile',
    String reason = 'media_file_delete',
    String? storedPath,
    Map<String, Object?> details = const {},
    bool redactTelemetry = false,
  }) async {
    if (failNext) {
      failNext = false;
      throw FileSystemException('injected cleanup failure', localPath);
    }
    return super.deleteFile(
      localPath,
      caller: caller,
      reason: reason,
      storedPath: storedPath,
      details: details,
      redactTelemetry: redactTelemetry,
    );
  }
}

void main() {
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  Future<void> seedTerminalParent(String id) async {
    await fixture.seedDirectParent(id);
    await fixture.db.update(
      'messages',
      {
        'private_media_policy_version': 1,
        'private_media_mode': 'view_once',
        'private_media_state': 'consumed',
        'private_media_received_at_ms': 1000,
        'private_media_terminal_at_ms': 2000,
        'private_media_clock_high_water_ms': 2000,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  MediaAttachment attachment({
    required String id,
    required String messageId,
    required String localPath,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 4,
      mediaType: 'image',
      localPath: localPath,
      downloadStatus: 'done',
      createdAt: '2026-07-11T00:00:00.000Z',
      encryptionKeyBase64: 'cHJpdmF0ZS1rZXk=',
      encryptionNonce: 'bm9uY2U=',
      encryptionScheme: 'blob_aes_256_gcm_v1',
      isBookmarked: true,
      lastPlaybackPositionMs: 321,
    );
  }

  test(
    'terminal cleanup removes every exact direct artifact and preserves siblings',
    () async {
      const messageId = 'private-cleanup';
      const directId = 'private-cleanup-direct';
      const groupId = 'private-cleanup-group';
      const unresolvedId = 'private-cleanup-unresolved';
      final externalRoot = Directory.systemTemp.createTempSync(
        'private-cleanup-external-',
      );
      addTearDown(() {
        if (externalRoot.existsSync()) externalRoot.deleteSync(recursive: true);
      });
      final maliciousPendingPath = p.join(
        externalRoot.path,
        'pending_uploads/$messageId/$directId.jpg',
      );
      File(maliciousPendingPath).createSync(recursive: true);
      await seedTerminalParent(messageId);
      await fixture.seedGroupParent(messageId);
      await fixture.repo.saveAttachment(
        attachment(
          id: directId,
          messageId: messageId,
          localPath: maliciousPendingPath,
        ),
        owner: MediaOwnerLane.direct,
      );
      await fixture.repo.saveAttachment(
        attachment(
          id: directId,
          messageId: messageId,
          localPath: maliciousPendingPath,
        ).copyWith(mime: 'image/png'),
        owner: MediaOwnerLane.direct,
      );
      expect(
        (await fixture.rawAttachmentRow(directId))!['mime'],
        'image/jpeg',
        reason: 'same-ID direct replay cannot orphan the existing .jpg path',
      );
      await fixture.repo.saveAttachment(
        attachment(
          id: groupId,
          messageId: messageId,
          localPath: 'media/group-1/$groupId.jpg',
        ),
        owner: MediaOwnerLane.group,
      );
      await fixture.db.insert('media_attachments', {
        'id': unresolvedId,
        'message_id': messageId,
        'mime': 'image/jpeg',
        'size': 4,
        'media_type': 'image',
        'download_status': 'done',
        'local_path': 'media/contact-1/$unresolvedId.jpg',
        'created_at': '2026-07-11T00:00:00.000Z',
        'owner_lane': 'unresolved',
      });

      final files = <String>[
        p.join(
          FakeMediaFileManager.testRootPath,
          'media/contact-1/$directId.jpg',
        ),
        p.join(
          FakeMediaFileManager.testRootPath,
          'media/contact-1/$directId.jpg.part',
        ),
        p.join(
          FakeMediaFileManager.testRootPath,
          'media/contact-1/$directId.jpg.enc',
        ),
        p.join(
          FakeMediaFileManager.testRootPath,
          'pending_uploads/$messageId/$directId.jpg',
        ),
      ];
      for (final path in files) {
        File(path).createSync(recursive: true);
      }
      final manager = FakeMediaFileManager();
      final adapter = DirectPrivateMediaLifecycle(
        messageRepository: fixture.messageRepo,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: manager,
      );
      final engine = PrivateMediaLifecycleEngine(
        adapter: adapter,
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => 3000,
      );

      final result = await engine.reconcileLocalLifecycle();

      expect(result.cleanupCompleted, 1);
      expect(await fixture.rawAttachmentRow(directId), isNull);
      expect(await fixture.rawAttachmentRow(groupId), isNotNull);
      expect(await fixture.rawAttachmentRow(unresolvedId), isNotNull);
      for (final path in files) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
      expect(
        File(maliciousPendingPath).existsSync(),
        isTrue,
        reason: 'suffix-matching paths outside current app storage are unsafe',
      );
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(directId),
        ),
        isFalse,
      );
    },
  );

  test(
    'cleanup failure retains terminal row/key metadata and retry converges',
    () async {
      const messageId = 'private-cleanup-retry';
      const attachmentId = 'private-cleanup-retry-att';
      await seedTerminalParent(messageId);
      await fixture.repo.saveAttachment(
        attachment(
          id: attachmentId,
          messageId: messageId,
          localPath: 'media/contact-1/$attachmentId.jpg',
        ),
        owner: MediaOwnerLane.direct,
      );
      final manager = _FailOnceMediaFileManager();
      final adapter = DirectPrivateMediaLifecycle(
        messageRepository: fixture.messageRepo,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: manager,
      );
      final engine = PrivateMediaLifecycleEngine(
        adapter: adapter,
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => 3000,
      );

      final first = await engine.reconcileLocalLifecycle();
      expect(first.retainedAfterError, 1);
      expect(await fixture.rawAttachmentRow(attachmentId), isNotNull);
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isTrue,
      );

      final second = await engine.reconcileLocalLifecycle();
      expect(second.cleanupCompleted, 1);
      expect(await fixture.rawAttachmentRow(attachmentId), isNull);
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isFalse,
      );
    },
  );

  test(
    'direct cleanup finalize requires durable terminal or hidden parent authority',
    () async {
      const activeMessageId = 'private-cleanup-active';
      const activeAttachmentId = 'private-cleanup-active-att';
      await fixture.seedDirectParent(activeMessageId);
      await fixture.db.update(
        'messages',
        {
          'private_media_policy_version': 1,
          'private_media_mode': 'view_once',
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
        },
        where: 'id = ?',
        whereArgs: [activeMessageId],
      );
      await fixture.repo.saveAttachment(
        attachment(
          id: activeAttachmentId,
          messageId: activeMessageId,
          localPath: 'media/contact-1/$activeAttachmentId.jpg',
        ),
        owner: MediaOwnerLane.direct,
      );
      final activeKeyName = mediaAttachmentEncryptionKeyStoreName(
        activeAttachmentId,
      );
      expect(await fixture.secureKeyStore.containsKey(activeKeyName), isTrue);

      expect(
        await fixture.repo.deleteDirectPrivateMediaEncryptionKeyWithinLock(
          messageId: activeMessageId,
          attachmentId: activeAttachmentId,
        ),
        isFalse,
        reason: 'an active parent cannot authorize direct key deletion',
      );
      expect(await fixture.secureKeyStore.containsKey(activeKeyName), isTrue);

      expect(
        await fixture.repo.deleteDirectPrivateMediaAttachmentWithinLock(
          messageId: activeMessageId,
          attachmentId: activeAttachmentId,
        ),
        0,
        reason: 'an active parent is not cleanup authority',
      );
      expect(await fixture.rawAttachmentRow(activeAttachmentId), isNotNull);

      await fixture.db.update(
        'messages',
        {
          'private_media_state': 'expired',
          'private_media_terminal_at_ms': 2000,
          'private_media_clock_high_water_ms': 2000,
        },
        where: 'id = ?',
        whereArgs: [activeMessageId],
      );
      expect(
        await fixture.repo.deleteDirectPrivateMediaEncryptionKeyWithinLock(
          messageId: 'wrong-private-parent',
          attachmentId: activeAttachmentId,
        ),
        isFalse,
        reason: 'terminal authority must belong to the exact parent',
      );
      expect(await fixture.secureKeyStore.containsKey(activeKeyName), isTrue);
      expect(
        await fixture.repo.deleteDirectPrivateMediaEncryptionKeyWithinLock(
          messageId: activeMessageId,
          attachmentId: activeAttachmentId,
        ),
        isTrue,
      );
      expect(await fixture.secureKeyStore.containsKey(activeKeyName), isFalse);
      expect(
        await fixture.repo.deleteDirectPrivateMediaAttachmentWithinLock(
          messageId: activeMessageId,
          attachmentId: activeAttachmentId,
        ),
        1,
      );
      expect(await fixture.rawAttachmentRow(activeAttachmentId), isNull);

      const hiddenMessageId = 'private-cleanup-hidden';
      const hiddenAttachmentId = 'private-cleanup-hidden-att';
      const wrongLaneAttachmentId = 'private-cleanup-hidden-group';
      await fixture.seedDirectParent(hiddenMessageId);
      await fixture.seedGroupParent(hiddenMessageId);
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
        whereArgs: [hiddenMessageId],
      );
      await fixture.repo.saveAttachment(
        attachment(
          id: hiddenAttachmentId,
          messageId: hiddenMessageId,
          localPath: 'media/contact-1/$hiddenAttachmentId.jpg',
        ),
        owner: MediaOwnerLane.direct,
      );
      await fixture.repo.saveAttachment(
        attachment(
          id: wrongLaneAttachmentId,
          messageId: hiddenMessageId,
          localPath: 'media/group-1/$wrongLaneAttachmentId.jpg',
        ),
        owner: MediaOwnerLane.group,
      );
      await fixture.db.update(
        'messages',
        {'hidden_at': '2026-07-11T00:00:02.000Z'},
        where: 'id = ?',
        whereArgs: [hiddenMessageId],
      );

      final hiddenKeyName = mediaAttachmentEncryptionKeyStoreName(
        hiddenAttachmentId,
      );
      final wrongLaneKeyName = mediaAttachmentEncryptionKeyStoreName(
        wrongLaneAttachmentId,
      );
      expect(
        await fixture.repo.deleteDirectPrivateMediaEncryptionKeyWithinLock(
          messageId: hiddenMessageId,
          attachmentId: wrongLaneAttachmentId,
        ),
        isFalse,
        reason: 'hidden authority never broadens to a group-owned key',
      );
      expect(
        await fixture.secureKeyStore.containsKey(wrongLaneKeyName),
        isTrue,
      );
      expect(
        await fixture.repo.deleteDirectPrivateMediaEncryptionKeyWithinLock(
          messageId: hiddenMessageId,
          attachmentId: hiddenAttachmentId,
        ),
        isTrue,
      );
      expect(await fixture.secureKeyStore.containsKey(hiddenKeyName), isFalse);
      expect(
        await fixture.repo.deleteDirectPrivateMediaAttachmentWithinLock(
          messageId: hiddenMessageId,
          attachmentId: hiddenAttachmentId,
        ),
        1,
      );
      expect(await fixture.rawAttachmentRow(hiddenAttachmentId), isNull);
      expect(await fixture.rawAttachmentRow(wrongLaneAttachmentId), isNotNull);
      expect(
        await fixture.repo.deleteDirectPrivateMediaAttachmentWithinLock(
          messageId: hiddenMessageId,
          attachmentId: wrongLaneAttachmentId,
        ),
        0,
        reason: 'hidden authority never broadens the exact direct lane',
      );
      expect(await fixture.rawAttachmentRow(wrongLaneAttachmentId), isNotNull);

      const ordinaryHiddenId = 'ordinary-hidden-cleanup-denied';
      const ordinaryAttachmentId = 'ordinary-hidden-cleanup-att';
      await fixture.seedDirectParent(
        ordinaryHiddenId,
        hiddenAt: '2026-07-11T00:00:03.000Z',
      );
      await fixture.repo.saveAttachment(
        attachment(
          id: ordinaryAttachmentId,
          messageId: ordinaryHiddenId,
          localPath: 'media/contact-1/$ordinaryAttachmentId.jpg',
        ),
        owner: MediaOwnerLane.direct,
      );
      expect(
        await fixture.repo.deleteDirectPrivateMediaEncryptionKeyWithinLock(
          messageId: ordinaryHiddenId,
          attachmentId: ordinaryAttachmentId,
        ),
        isFalse,
      );
      expect(
        await fixture.repo.deleteDirectPrivateMediaAttachmentWithinLock(
          messageId: ordinaryHiddenId,
          attachmentId: ordinaryAttachmentId,
        ),
        0,
      );

      const futureUnsupportedId = 'future-unsupported-cleanup';
      const futureUnsupportedAttachmentId = 'future-unsupported-cleanup-att';
      await fixture.seedDirectParent(futureUnsupportedId);
      await fixture.db.update(
        'messages',
        {
          'private_media_policy_version': 9,
          'private_media_mode': 'unsupported',
          'private_media_state': 'unsupported',
          'private_media_received_at_ms': 1000,
          'private_media_terminal_at_ms': 2000,
          'private_media_clock_high_water_ms': 2000,
        },
        where: 'id = ?',
        whereArgs: [futureUnsupportedId],
      );
      await fixture.repo.saveAttachment(
        attachment(
          id: futureUnsupportedAttachmentId,
          messageId: futureUnsupportedId,
          localPath: 'media/contact-1/$futureUnsupportedAttachmentId.jpg',
        ),
        owner: MediaOwnerLane.direct,
      );
      expect(
        await fixture.repo.deleteDirectPrivateMediaEncryptionKeyWithinLock(
          messageId: futureUnsupportedId,
          attachmentId: futureUnsupportedAttachmentId,
        ),
        isTrue,
      );
      expect(
        await fixture.repo.deleteDirectPrivateMediaAttachmentWithinLock(
          messageId: futureUnsupportedId,
          attachmentId: futureUnsupportedAttachmentId,
        ),
        1,
      );
    },
  );

  test(
    'cleanup repository boundary exposes no generic secret-store access',
    () {
      final source = File(
        'lib/features/conversation/domain/repositories/'
        'media_attachment_repository.dart',
      ).readAsStringSync();
      final cleanupStart = source.indexOf(
        'abstract class DirectPrivateMediaCleanupRepository',
      );
      final cleanupEnd = source.indexOf(
        'abstract class DirectPrivateMediaCleanupRuntime',
        cleanupStart,
      );
      expect(cleanupStart, greaterThanOrEqualTo(0));
      expect(cleanupEnd, greaterThan(cleanupStart));
      final cleanupApi = source.substring(cleanupStart, cleanupEnd);

      expect(
        cleanupApi,
        contains('deleteDirectPrivateMediaEncryptionKeyWithinLock'),
      );
      expect(cleanupApi, isNot(contains('SecureKeyStore')));
      expect(cleanupApi, isNot(contains('Future<String?> read')));
      expect(cleanupApi, isNot(contains('Future<void> write')));
      expect(source, isNot(contains('directPrivateMediaSecureKeyStore')));
    },
  );

  test('unsafe path identifiers retain every file key and row', () async {
    final external = Directory.systemTemp.createTempSync(
      'private-cleanup-unsafe-id-',
    );
    addTearDown(() {
      if (external.existsSync()) external.deleteSync(recursive: true);
    });
    final absoluteAttachmentId = p.join(external.path, 'absolute-att');
    final cases = <({String contactId, String messageId, String attachmentId})>[
      (contactId: '..', messageId: 'unsafe-contact', attachmentId: 'att-a'),
      (
        contactId: 'contact-1',
        messageId: '../unsafe-message',
        attachmentId: 'att-b',
      ),
      (
        contactId: 'contact-1',
        messageId: 'unsafe-traversal',
        attachmentId: '../att-c',
      ),
      (
        contactId: 'contact-1',
        messageId: 'unsafe-absolute',
        attachmentId: absoluteAttachmentId,
      ),
      (
        contactId: 'contact-1',
        messageId: 'unsafe-slash',
        attachmentId: 'nested/att-d',
      ),
      (
        contactId: 'contact-1',
        messageId: 'unsafe-backslash',
        attachmentId: r'nested\att-e',
      ),
    ];

    for (final testCase in cases) {
      await fixture.seedDirectParent(
        testCase.messageId,
        contactPeerId: testCase.contactId,
      );
      await fixture.db.update(
        'messages',
        {
          'private_media_policy_version': 1,
          'private_media_mode': 'view_once',
          'private_media_state': 'consumed',
          'private_media_received_at_ms': 1000,
          'private_media_terminal_at_ms': 2000,
          'private_media_clock_high_water_ms': 2000,
        },
        where: 'id = ?',
        whereArgs: [testCase.messageId],
      );
      await fixture.repo.saveAttachment(
        attachment(
          id: testCase.attachmentId,
          messageId: testCase.messageId,
          localPath: 'untrusted',
        ),
        owner: MediaOwnerLane.direct,
      );
    }
    final absoluteSentinel = File('$absoluteAttachmentId.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync(const [9, 8, 7]);

    final engine = PrivateMediaLifecycleEngine(
      adapter: DirectPrivateMediaLifecycle(
        messageRepository: fixture.messageRepo,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: FakeMediaFileManager(),
      ),
      lifecycleLock: fixture.repo.lifecycleLock,
      nowMs: () => 3000,
    );
    final result = await engine.reconcileLocalLifecycle();

    expect(result.retainedAfterError, cases.length);
    expect(absoluteSentinel.readAsBytesSync(), const [9, 8, 7]);
    for (final testCase in cases) {
      expect(
        await fixture.rawAttachmentRow(testCase.attachmentId),
        isNotNull,
        reason: testCase.attachmentId,
      );
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(testCase.attachmentId),
        ),
        isTrue,
        reason: testCase.attachmentId,
      );
    }
  });

  test(
    'symlinked canonical target fails closed before any cleanup mutation',
    () async {
      const messageId = 'private-cleanup-symlink';
      const attachmentId = 'private-cleanup-symlink-att';
      await seedTerminalParent(messageId);
      await fixture.repo.saveAttachment(
        attachment(
          id: attachmentId,
          messageId: messageId,
          localPath: 'media/contact-1/$attachmentId.jpg',
        ),
        owner: MediaOwnerLane.direct,
      );
      final external = Directory.systemTemp.createTempSync(
        'private-cleanup-symlink-external-',
      );
      addTearDown(() {
        if (external.existsSync()) external.deleteSync(recursive: true);
      });
      final externalFile = File(p.join(external.path, 'keep.jpg'))
        ..writeAsBytesSync(const [4, 2]);
      final canonical = p.join(
        FakeMediaFileManager.testRootPath,
        'media/contact-1/$attachmentId.jpg',
      );
      File(canonical).parent.createSync(recursive: true);
      if (FileSystemEntity.typeSync(canonical, followLinks: false) !=
          FileSystemEntityType.notFound) {
        File(canonical).deleteSync();
      }
      Link(canonical).createSync(externalFile.path);
      addTearDown(() {
        final link = Link(canonical);
        if (link.existsSync()) link.deleteSync();
      });

      final engine = PrivateMediaLifecycleEngine(
        adapter: DirectPrivateMediaLifecycle(
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: FakeMediaFileManager(),
        ),
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => 3000,
      );
      final result = await engine.reconcileLocalLifecycle();

      expect(result.retainedAfterError, 1);
      expect(Link(canonical).existsSync(), isTrue);
      expect(externalFile.readAsBytesSync(), const [4, 2]);
      expect(await fixture.rawAttachmentRow(attachmentId), isNotNull);
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isTrue,
      );
    },
  );

  Future<void> seedActivePrivateParent(String messageId) async {
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
  }

  MediaAttachment guardedAttachment({
    required String id,
    required String messageId,
    required String key,
  }) => MediaAttachment(
    id: id,
    messageId: messageId,
    mime: 'image/jpeg',
    size: 3,
    mediaType: 'image',
    downloadStatus: 'pending',
    createdAt: '2026-07-11T00:00:00.000Z',
    encryptionKeyBase64: key,
    encryptionNonce: 'bm9uY2U=',
  );

  test('guard refusal restores an overwritten existing secure key', () async {
    const messageId = 'guard-key-restore';
    const attachmentId = 'guard-key-restore-att';
    const oldKey = 'b2xkLWtleQ==';
    const newKey = 'bmV3LWtleQ==';
    await seedTerminalParent(messageId);
    await fixture.repo.saveAttachment(
      guardedAttachment(id: attachmentId, messageId: messageId, key: oldKey),
      owner: MediaOwnerLane.direct,
    );

    expect(
      await fixture.repo.saveDirectPrivateAttachmentGuarded(
        guardedAttachment(id: attachmentId, messageId: messageId, key: newKey),
        messageId: messageId,
        nowMs: 3000,
      ),
      isFalse,
    );
    expect(
      await fixture.secureKeyStore.read(
        mediaAttachmentEncryptionKeyStoreName(attachmentId),
      ),
      oldKey,
    );
  });

  test('guard exception restores the previous secure key', () async {
    await fixture.dispose();
    fixture = await MediaRepositoryRealDbFixture.create(
      dbSaveDirectPrivateMediaAttachmentGuardedOverride:
          (row, {required messageId, required nowMs}) async =>
              throw StateError('injected guarded DB failure'),
    );
    const messageId = 'guard-key-throw';
    const attachmentId = 'guard-key-throw-att';
    const oldKey = 'b2xkLWtleQ==';
    await seedActivePrivateParent(messageId);
    await fixture.repo.saveAttachment(
      guardedAttachment(id: attachmentId, messageId: messageId, key: oldKey),
      owner: MediaOwnerLane.direct,
    );

    expect(
      fixture.repo.saveDirectPrivateAttachmentGuarded(
        guardedAttachment(
          id: attachmentId,
          messageId: messageId,
          key: 'bmV3LWtleQ==',
        ),
        messageId: messageId,
        nowMs: 1100,
      ),
      throwsStateError,
    );
    expect(
      await fixture.secureKeyStore.read(
        mediaAttachmentEncryptionKeyStoreName(attachmentId),
      ),
      oldKey,
    );
  });

  test('cross-owner collision fails before secure key mutation', () async {
    const messageId = 'guard-owner-collision';
    const attachmentId = 'guard-owner-collision-att';
    const oldKey = 'Z3JvdXAta2V5';
    await seedActivePrivateParent(messageId);
    await fixture.seedGroupParent(messageId);
    await fixture.repo.saveAttachment(
      guardedAttachment(id: attachmentId, messageId: messageId, key: oldKey),
      owner: MediaOwnerLane.group,
    );
    final writesBefore = fixture.secureKeyStore.writtenKeys.length;

    expect(
      fixture.repo.saveDirectPrivateAttachmentGuarded(
        guardedAttachment(
          id: attachmentId,
          messageId: messageId,
          key: 'ZGlyZWN0LW5ldy1rZXk=',
        ),
        messageId: messageId,
        nowMs: 1100,
      ),
      throwsA(isA<MediaAttachmentOwnerViolation>()),
    );
    expect(fixture.secureKeyStore.writtenKeys.length, writesBefore);
    expect(
      await fixture.secureKeyStore.read(
        mediaAttachmentEncryptionKeyStoreName(attachmentId),
      ),
      oldKey,
    );
  });

  test('unreadable existing secure key fails before write or delete', () async {
    await fixture.dispose();
    final store = _UnreadableExistingKeyStore();
    fixture = await MediaRepositoryRealDbFixture.create(secureKeyStore: store);
    const messageId = 'guard-unreadable-key';
    const attachmentId = 'guard-unreadable-key-att';
    final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
    await seedActivePrivateParent(messageId);
    await store.write(keyName, 'b2xkLWtleQ==');
    store.unreadableKey = keyName;
    final writesBefore = store.writtenKeys.length;

    expect(
      fixture.repo.saveDirectPrivateAttachmentGuarded(
        guardedAttachment(
          id: attachmentId,
          messageId: messageId,
          key: 'bmV3LWtleQ==',
        ),
        messageId: messageId,
        nowMs: 1100,
      ),
      throwsStateError,
    );
    expect(store.writtenKeys.length, writesBefore);
    expect(store.deleteCalls, 0);
    expect(await store.containsKey(keyName), isTrue);
  });

  test('missing parent guard refusal deletes a newly staged key', () async {
    const attachmentId = 'guard-new-key-att';
    expect(
      await fixture.repo.saveDirectPrivateAttachmentGuarded(
        guardedAttachment(
          id: attachmentId,
          messageId: 'missing-parent',
          key: 'bmV3LWtleQ==',
        ),
        messageId: 'missing-parent',
        nowMs: 1100,
      ),
      isFalse,
    );
    expect(
      await fixture.secureKeyStore.containsKey(
        mediaAttachmentEncryptionKeyStoreName(attachmentId),
      ),
      isFalse,
    );
    expect(await fixture.rawAttachmentRow(attachmentId), isNull);
  });

  test('view-once open rejects zero and truncated canonical files', () async {
    const messageId = 'private-open-size';
    const attachmentId = 'private-open-size-att';
    await fixture.seedDirectParent(messageId);
    await fixture.db.update(
      'messages',
      {
        'private_media_policy_version': 1,
        'private_media_mode': 'view_once',
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
        size: 4,
        mediaType: 'image',
        localPath: 'media/contact-1/private-open-size-att.jpg',
        downloadStatus: 'done',
        createdAt: '2026-07-11T00:00:00.000Z',
      ),
      owner: MediaOwnerLane.direct,
    );
    final canonical = File(
      p.join(
        FakeMediaFileManager.testRootPath,
        'media/contact-1/private-open-size-att.jpg',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (canonical.existsSync()) canonical.deleteSync();
    });
    final engine = PrivateMediaLifecycleEngine(
      adapter: DirectPrivateMediaLifecycle(
        messageRepository: fixture.messageRepo,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: FakeMediaFileManager(),
      ),
      lifecycleLock: fixture.repo.lifecycleLock,
      nowMs: () => 1100,
    );

    for (final bytes in const <List<int>>[
      [],
      [1, 2, 3],
    ]) {
      canonical.writeAsBytesSync(bytes);
      expect(await engine.openViewOnce(messageId), isNull);
      expect(
        (await fixture.messageRepo.getMessage(
          messageId,
        ))!.privateMediaState.name,
        'available',
      );
    }
  });

  test(
    'limit-one recovery rotates a persistent failure and reaches the next row',
    () async {
      await seedTerminalParent('a-persistent-cleanup-failure');
      await seedTerminalParent('b-recoverable-cleanup');
      await fixture.repo.saveAttachment(
        attachment(
          id: '../unsafe-persistent',
          messageId: 'a-persistent-cleanup-failure',
          localPath: 'media/contact-1/unsafe.jpg',
        ),
        owner: MediaOwnerLane.direct,
      );
      await fixture.repo.saveAttachment(
        attachment(
          id: 'recoverable-cleanup-att',
          messageId: 'b-recoverable-cleanup',
          localPath: 'media/contact-1/recoverable-cleanup-att.jpg',
        ),
        owner: MediaOwnerLane.direct,
      );
      final engine = PrivateMediaLifecycleEngine(
        adapter: DirectPrivateMediaLifecycle(
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: FakeMediaFileManager(),
        ),
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => 5000,
      );

      final first = await engine.reconcileLocalLifecycle(limit: 1);
      expect(first.retainedAfterError, 1);
      expect(await fixture.rawAttachmentRow('../unsafe-persistent'), isNotNull);
      final second = await engine.reconcileLocalLifecycle(limit: 1);
      expect(second.cleanupCompleted, 1);
      expect(await fixture.rawAttachmentRow('recoverable-cleanup-att'), isNull);
      expect(await fixture.rawAttachmentRow('../unsafe-persistent'), isNotNull);
    },
  );

  test(
    'one cleanup failure does not block later interrupted or due candidates',
    () async {
      Future<void> seedLifecycle(
        String id, {
        required String mode,
        required String state,
        int? expiresAtMs,
      }) async {
        await fixture.seedDirectParent(id);
        await fixture.db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': mode,
            'private_media_duration_seconds': mode == 'disappearing'
                ? 3600
                : null,
            'private_media_state': state,
            'private_media_received_at_ms': 1000,
            'private_media_expires_at_ms': expiresAtMs,
            'private_media_clock_high_water_ms': 1000,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      await seedLifecycle(
        'a-interrupted-unsafe',
        mode: 'view_once',
        state: 'opening',
      );
      await seedLifecycle(
        'b-interrupted-safe',
        mode: 'view_once',
        state: 'opening',
      );
      await seedLifecycle(
        'c-due-expiry',
        mode: 'disappearing',
        state: 'available',
        expiresAtMs: 1500,
      );
      for (final item in const [
        (messageId: 'a-interrupted-unsafe', attachmentId: '../unsafe-first'),
        (messageId: 'b-interrupted-safe', attachmentId: 'safe-second-att'),
        (messageId: 'c-due-expiry', attachmentId: 'due-third-att'),
      ]) {
        await fixture.repo.saveAttachment(
          attachment(
            id: item.attachmentId,
            messageId: item.messageId,
            localPath: 'media/contact-1/${item.attachmentId}.jpg',
          ),
          owner: MediaOwnerLane.direct,
        );
      }
      final engine = PrivateMediaLifecycleEngine(
        adapter: DirectPrivateMediaLifecycle(
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: FakeMediaFileManager(),
        ),
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => 2000,
      );

      final result = await engine.reconcileLocalLifecycle(limit: 10);
      expect(result.terminalClaims, 3);
      expect(result.cleanupCompleted, 2);
      expect(result.retainedAfterError, greaterThanOrEqualTo(1));
      expect(await fixture.rawAttachmentRow('../unsafe-first'), isNotNull);
      expect(await fixture.rawAttachmentRow('safe-second-att'), isNull);
      expect(await fixture.rawAttachmentRow('due-third-att'), isNull);
    },
  );

  test(
    'secure-key read corruption cannot starve later expiry cleanup',
    () async {
      await fixture.dispose();
      fixture = await MediaRepositoryRealDbFixture.create(
        secureKeyStore: _ThrowingReadKeyStore(),
      );
      await seedTerminalParent('a-corrupt-key-terminal');
      await fixture.seedDirectParent('b-corrupt-key-due');
      await fixture.db.update(
        'messages',
        {
          'private_media_policy_version': 1,
          'private_media_mode': 'disappearing',
          'private_media_duration_seconds': 3600,
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_expires_at_ms': 1500,
          'private_media_clock_high_water_ms': 1000,
        },
        where: 'id = ?',
        whereArgs: ['b-corrupt-key-due'],
      );
      for (final item in const [
        (messageId: 'a-corrupt-key-terminal', attachmentId: 'corrupt-key-a'),
        (messageId: 'b-corrupt-key-due', attachmentId: 'corrupt-key-b'),
      ]) {
        await fixture.repo.saveAttachment(
          attachment(
            id: item.attachmentId,
            messageId: item.messageId,
            localPath: 'media/contact-1/${item.attachmentId}.jpg',
          ),
          owner: MediaOwnerLane.direct,
        );
      }
      final engine = PrivateMediaLifecycleEngine(
        adapter: DirectPrivateMediaLifecycle(
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: FakeMediaFileManager(),
        ),
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => 2000,
      );

      final result = await engine.reconcileLocalLifecycle(limit: 10);
      expect(result.cleanupCompleted, 2);
      expect(result.retainedAfterError, 0);
      expect(await fixture.rawAttachmentRow('corrupt-key-a'), isNull);
      expect(await fixture.rawAttachmentRow('corrupt-key-b'), isNull);
    },
  );

  group('Plan 354 private strict retention and download convergence', () {
    test(
      'TC-354-03d private terminal retention drain and later cleanup converge',
      () {
        final lifecycle = File(
          'lib/features/conversation/application/'
          'direct_private_media_lifecycle.dart',
        ).readAsStringSync();

        // 1. Terminal cleanup consults live v111 FIRST and returns without
        //    destroying anything while a prepared/stored generation exists.
        final cleanup = lifecycle.indexOf(
          'Future<void> cleanupTerminalWithinLock(',
        );
        expect(cleanup, greaterThan(-1));
        final retentionCheck = lifecycle.indexOf(
          'if (await _mustRetainLivePrivateBlobCustody(parent, attachments)) {',
          cleanup,
        );
        final firstDelete = lifecycle.indexOf(
          'await _deleteExactAppOwnedArtifacts(',
          cleanup,
        );
        final keyDelete = lifecycle.indexOf(
          'deleteDirectPrivateMediaEncryptionKeyWithinLock(',
          cleanup,
        );
        final rowDelete = lifecycle.indexOf(
          'deleteDirectPrivateMediaAttachmentWithinLock(',
          cleanup,
        );
        expect(retentionCheck, greaterThan(cleanup));
        expect(
          retentionCheck,
          lessThan(firstDelete),
          reason: 'retention is decided before any artifact is removed',
        );
        expect(retentionCheck, lessThan(keyDelete));
        expect(retentionCheck, lessThan(rowDelete));
        expect(
          lifecycle
              .substring(retentionCheck, retentionCheck + 200)
              .contains('return;'),
          isTrue,
          reason: 'a live generation retains the complete projection',
        );

        // 2. The predicate covers BOTH live outgoing states and every terminal
        //    parent shape (hidden, deleted, consumed), and fails safe when
        //    custody authority cannot be read.
        final predicate = lifecycle.indexOf(
          'Future<bool> _mustRetainLivePrivateBlobCustody(',
        );
        expect(predicate, greaterThan(-1));
        final predicateEnd = lifecycle.indexOf(
          'Future<bool> _mustRetainUnhandedOffOutgoingCustody(',
          predicate,
        );
        final predicateBody = lifecycle.substring(predicate, predicateEnd);
        expect(
          predicateBody.contains(
            'DirectMediaBlobCustodyState.outgoingPrepared',
          ),
          isTrue,
        );
        expect(
          predicateBody.contains('DirectMediaBlobCustodyState.outgoingStored'),
          isTrue,
        );
        expect(
          predicateBody.contains('return true;'),
          isTrue,
          reason:
              'unresolved custody authority retains rather than destroying '
              'the only resumable bytes',
        );
        // It is retention-only: no message-wide transition from inside this
        // per-attachment lock, and no new owner.
        for (final forbidden in <String>[
          'synchronizedAll',
          'terminalizeOutgoingDirectMediaBlobGeneration',
          'DirectMediaBlobCustodyDrain',
        ]) {
          expect(
            predicateBody.contains(forbidden),
            isFalse,
            reason: 'retention must not $forbidden',
          );
        }
        // Hidden/deleted parents are NOT excluded here — unlike the older
        // unhanded-off predicate, which is consumed-only.
        expect(predicateBody.contains("parent.hiddenAt != null"), isFalse);
        expect(
          lifecycle
              .substring(predicateEnd, predicateEnd + 700)
              .contains('parent.hiddenAt != null'),
          isTrue,
          reason:
              'the pre-existing consumed-only predicate is unchanged and '
              'still excludes hidden/deleted parents',
        );
      },
    );

    test('TC-354-05b private strict download and terminal cleanup converge', () {
      final lifecycle = File(
        'lib/features/conversation/application/'
        'direct_private_media_lifecycle.dart',
      ).readAsStringSync();
      final owner = File(
        'lib/features/conversation/application/'
        'strict_direct_media_blob_download_ack_owner.dart',
      ).readAsStringSync();

      // Private cleanup enumerates the EXACT deterministic staging pair the
      // strict private download uses — both orders converge without a
      // wildcard directory scan.
      final wipe = lifecycle.indexOf(
        'Future<void> _deleteExactAppOwnedArtifacts({',
      );
      expect(wipe, greaterThan(-1));
      final wipeBody = lifecycle.substring(wipe, wipe + 3600);
      expect(wipeBody.contains(".path}.private.enc'"), isTrue);
      expect(wipeBody.contains(".path}.private.enc.dec'"), isTrue);
      // Every target is path-authorized before the first unlink.
      final preflight = wipeBody.indexOf(
        'DirectPrivateMediaPathGuard.authorizeTarget(',
      );
      final firstUnlink = wipeBody.indexOf('mediaFileManager.deleteFile(');
      expect(preflight, greaterThan(-1));
      expect(preflight, lessThan(firstUnlink));
      expect(
        wipeBody.contains('Directory(') || wipeBody.contains('.list('),
        isFalse,
        reason: 'cleanup must never wildcard-scan a directory',
      );

      // The download owner removes the same two exact siblings on EVERY
      // exit, including a decrypt-before-commit failure, and a losing commit
      // scrubs only its own canonical plaintext.
      final finallyBlock = owner.indexOf(
        'if (privateDeterministicStaging) {\n        // Both deterministic siblings',
      );
      expect(finallyBlock, greaterThan(-1));
      final finallyBody = owner.substring(finallyBlock, finallyBlock + 700);
      expect(finallyBody.contains('privateCiphertextStagingPath('), isTrue);
      expect(finallyBody.contains('privateDecryptStagingPath('), isTrue);
      expect(
        owner.contains(
          'if (!didCommit) {\n              // The DB refused this promotion',
        ),
        isTrue,
      );
      expect(
        owner.contains('await _deleteRegularFile(canonical);'),
        isTrue,
        reason: 'a losing attempt scrubs only its own plaintext candidate',
      );
      // v111 is never deleted by the losing attempt: it converges by exact
      // ACK or expiry alone.
      final commitScope = owner.substring(
        owner.indexOf('if (!didCommit) {'),
        owner.indexOf('if (!didCommit) {') + 600,
      );
      expect(
        commitScope.contains('deleteIncomingDirectMediaBlobAckIfExact'),
        isFalse,
      );
    });
  });

  group('Plan 356 private deletion custody lifecycle serialization', () {
    const sender = 'peer-alice';
    const recipient = 'contact-1';
    const recipientMlKemPublicKey = 'recipient-mlkem-public-key';

    /// Seeds one delivered v1 Protected parent whose single pending attachment
    /// is still awaiting its initial private handoff.
    Future<ConversationMessage> seedLivePrivateParent(
      MediaRepositoryRealDbFixture target,
      String messageId,
      String attachmentId,
    ) async {
      await target.seedDirectParent(messageId, contactPeerId: recipient);
      await target.db.update(
        'messages',
        <String, Object?>{
          'sender_peer_id': sender,
          'status': 'delivered',
          'is_incoming': 0,
          'private_media_policy_version': 1,
          'private_media_mode': 'protected',
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
        },
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      );
      await target.repo.saveAttachment(
        MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
          downloadStatus: 'upload_pending',
          createdAt: '2026-08-10T12:00:00.000Z',
        ),
        owner: MediaOwnerLane.direct,
      );
      return (await target.messageRepo.getMessage(messageId))!;
    }

    /// The real private initial handoff body, run under the incumbent
    /// per-attachment lifecycle lease exactly as production claims it.
    Future<OutgoingDirectPrivateInboxCustodyDbResult> runInitialHandoff(
      MediaRepositoryRealDbFixture target, {
      required String messageId,
      required String attachmentId,
      void Function()? onEnter,
      Future<void> Function()? gate,
    }) {
      return target.repo.lifecycleLock.synchronized(attachmentId, () async {
        onEnter?.call();
        if (gate != null) await gate();
        return dbCommitOutgoingDirectPrivateWireEnvelopeWithInboxCustody(
          target.db,
          <String, Object?>{
            'id': attachmentId,
            'message_id': messageId,
            'owner_lane': 'direct',
            'mime': 'image/jpeg',
            'size': 2048,
            'media_type': 'image',
            'local_path': MediaFilePathConvention.relativePathForAttachment(
              contactPeerId: recipient,
              blobId: attachmentId,
              mime: 'image/jpeg',
            ),
            'download_status': 'done',
            'created_at': '2026-08-10T12:00:00.000Z',
            'content_hash': 'a' * 64,
            'encryption_key_base64': 'ref',
            'encryption_nonce': 'nonce',
            'encryption_scheme': 'blob_aes_256_gcm_v1',
          },
          expectedPendingLocalPath:
              'pending_uploads/$messageId/$attachmentId.jpg',
          envelope: '{"type":"chat_message"}',
          hasOwnedPendingCompletion: false,
          wireMediaBlobManifestHash: 'f' * 64,
          wireMediaBlobExpiresAtMs: 2100000000000,
        );
      });
    }

    /// In-memory fixtures share one SQLite instance in a test file, so every
    /// v109 assertion here is scoped to its own deletion target.
    Future<List<Map<String, Object?>>> v109RowsFor(
      MediaRepositoryRealDbFixture target,
      String messageId,
    ) async => (await target.db.query('direct_reaction_inbox_custody_outbox'))
        .where((row) => (row['wire_envelope']! as String).contains(messageId))
        .toList(growable: false);

    Future<List<Map<String, Object?>>> v108Rows(
      MediaRepositoryRealDbFixture target,
      String messageId,
    ) => target.db.query(
      'direct_inbox_custody_outbox',
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
    );

    Future<void> seedInitializedMutationRoster(
      MediaRepositoryRealDbFixture target,
    ) async {
      await target.db.insert('contacts', const <String, Object?>{
        'peer_id': recipient,
        'public_key': 'tc366-contact-signing-key',
        'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
        'username': 'TC366 Contact',
        'signature': 'tc366-signature',
        'scanned_at': '2026-08-14T12:00:00.000Z',
        'ml_kem_public_key': 'tc366-legacy-mlkem',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await target.db.insert(
        'direct_contact_device_roster_metadata',
        const <String, Object?>{
          'contact_account_peer_id': recipient,
          'roster_initialized': 1,
          'legacy_target_state': 'revoked',
          'initialized_at': '2026-08-14T12:00:00.000Z',
          'legacy_revoked_at': '2026-08-14T12:00:00.000Z',
          'updated_at': '2026-08-14T12:00:00.000Z',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      for (final device in const <(String, String, String, String)>[
        (
          'tc366-device-a',
          'tc366-transport-a',
          'tc366-mlkem-a',
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
        (
          'tc366-device-b',
          'tc366-transport-b',
          'tc366-mlkem-b',
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
      ]) {
        await target.db.insert(
          'direct_contact_device_bindings',
          <String, Object?>{
            'contact_account_peer_id': recipient,
            'device_id': device.$1,
            'verified_account_signing_public_key': 'tc366-contact-signing-key',
            'transport_peer_id': device.$2,
            'transport_public_key': 'transport-key-${device.$1}',
            'device_ml_kem_public_key': device.$3,
            'binding_fingerprint': device.$4,
            'state': 'active',
            'staged_at': '2026-08-14T12:00:00.000Z',
            'decided_at': '2026-08-14T12:00:00.000Z',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    DirectEventFanoutAuthoring mutationFanout(
      MediaRepositoryRealDbFixture target, {
      Future<void> Function()? beforeFirstEncrypt,
      Future<void> Function()? beforeStage,
    }) {
      var encryptHookRan = false;
      Never unreachable() => throw StateError(
        'private deletion fanout reached an unrelated event owner',
      );
      return DirectEventFanoutAuthoring(
        selector: const DirectLinkedEventFanoutSelector.enabled(),
        linkedOrigin: false,
        senderTransportPeerId: sender,
        readSnapshot: (contactAccountPeerId) =>
            dbReadDirectContactFanoutSnapshot(
              target.db,
              contactAccountPeerId: contactAccountPeerId,
            ),
        encrypt:
            ({required recipientMlKemPublicKey, required plaintext}) async {
              if (!encryptHookRan) {
                encryptHookRan = true;
                await beforeFirstEncrypt?.call();
              }
              return (
                kem: 'kem-$recipientMlKemPublicKey',
                ciphertext: plaintext,
                nonce: 'nonce-$recipientMlKemPublicKey',
              );
            },
        loadTextSiblings: (_) async => unreachable(),
        stageTextFanout:
            ({
              required stagedRow,
              required messageId,
              required contactAccountPeerId,
              required senderTransportPeerId,
              required expectedSnapshot,
              required candidates,
            }) async => unreachable(),
        loadEventSiblings: (eventId) =>
            dbLoadDirectReactionInboxCustodyOutboxRowsForEventId(
              target.db,
              eventId: eventId,
            ),
        stageMutationFanout:
            ({
              required expectedRow,
              required stagedRow,
              required kind,
              required eventId,
              required parentMessageId,
              required contactAccountPeerId,
              required senderTransportPeerId,
              required expectedSnapshot,
              required candidates,
            }) async {
              await beforeStage?.call();
              return dbStageOutgoingDirectTextMutationFanoutInboxCustody(
                target.db,
                expectedRow: expectedRow,
                stagedRow: stagedRow,
                kind: kind,
                eventId: eventId,
                parentMessageId: parentMessageId,
                contactAccountPeerId: contactAccountPeerId,
                senderTransportPeerId: senderTransportPeerId,
                expectedSnapshot: expectedSnapshot,
                candidates: candidates,
              );
            },
        stageReactionFanout:
            ({
              required reactionRow,
              required action,
              required parentMessageId,
              required contactAccountPeerId,
              required senderTransportPeerId,
              required expectedSnapshot,
              required candidates,
            }) async => unreachable(),
      );
    }

    Future<List<Map<String, Object?>>> fanoutRowsFor(
      MediaRepositoryRealDbFixture target,
      String messageId,
    ) => target.db.query(
      'direct_reaction_inbox_custody_outbox',
      where: 'parent_message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'recipient_peer_id ASC',
    );

    test(
      'TC-366-02b private DFE fanout stages or performs zero cleanup under the lease',
      () async {
        // Applied arm: N physical events commit before cleanup, and an
        // incumbent per-attachment contender cannot enter between them.
        final appliedLock = _SignallingLifecycleLock();
        final applied = await MediaRepositoryRealDbFixture.create(
          lifecycleLock: appliedLock,
        );
        addTearDown(applied.dispose);
        await seedInitializedMutationRoster(applied);
        const appliedMessageId = 'tc366-02b-private-applied';
        const appliedAttachmentId = '$appliedMessageId-att';
        final appliedParent = await seedLivePrivateParent(
          applied,
          appliedMessageId,
          appliedAttachmentId,
        );
        final cleanupEntered = Completer<void>();
        final releaseCleanup = Completer<void>();
        addTearDown(() {
          if (!releaseCleanup.isCompleted) releaseCleanup.complete();
        });
        final appliedManager = _GatedCleanupMediaFileManager(
          onFirstDelete: () async {
            expect(
              await fanoutRowsFor(applied, appliedMessageId),
              hasLength(2),
              reason: 'every target is durable before private cleanup',
            );
            if (!cleanupEntered.isCompleted) cleanupEntered.complete();
            await releaseCleanup.future;
          },
        );
        final appliedNetwork = FakeP2PNetwork();
        // Keep the staged siblings in sender custody after the lease releases
        // so the final assertion observes the stage itself. The integration
        // fake otherwise accepts protected inbox custody for offline peers and
        // the production drain correctly retires both v109 rows.
        appliedNetwork.inboxDisabled = true;
        final appliedService = _StoppedPrivateDeleteP2PService(
          peerId: sender,
          network: appliedNetwork,
        );
        addTearDown(appliedService.dispose);
        final deletion = deleteMessageForEveryone(
          p2pService: appliedService,
          messageRepo: applied.messageRepo,
          originalMessage: appliedParent,
          mediaAttachmentRepo: applied.repo,
          mediaFileManager: appliedManager,
          directEventFanout: mutationFanout(applied),
        );
        await cleanupEntered.future.timeout(const Duration(seconds: 10));

        var contenderEntered = false;
        final contenderAttempted = appliedLock.nextSharedAttempt();
        final contender = Zone.root.run(
          () => appliedLock.synchronized(appliedAttachmentId, () async {
            contenderEntered = true;
          }),
        );
        await contenderAttempted.timeout(const Duration(seconds: 10));
        expect(
          contenderEntered,
          isFalse,
          reason: 'stage and cleanup share the incumbent exclusive lease',
        );
        expect(appliedNetwork.deliverCallCount, 0);

        releaseCleanup.complete();
        final (appliedResult, appliedTombstone) = await deletion.timeout(
          const Duration(seconds: 10),
        );
        await contender.timeout(const Duration(seconds: 10));
        expect(appliedResult, SendChatMessageResult.success);
        expect(appliedTombstone?.isDeleted, isTrue);
        expect(contenderEntered, isTrue);
        expect(await fanoutRowsFor(applied, appliedMessageId), hasLength(2));

        // Refused arm: introduce a durable race after route qualification but
        // before the locked stage. The DB refuses the stale parent; no private
        // cleanup, v109 row, or network effect is allowed.
        final refusedLock = _SignallingLifecycleLock();
        final refused = await MediaRepositoryRealDbFixture.create(
          lifecycleLock: refusedLock,
        );
        addTearDown(refused.dispose);
        await seedInitializedMutationRoster(refused);
        const refusedMessageId = 'tc366-02b-private-refused';
        const refusedAttachmentId = '$refusedMessageId-att';
        final refusedParent = await seedLivePrivateParent(
          refused,
          refusedMessageId,
          refusedAttachmentId,
        );
        var refusedCleanupCalls = 0;
        final refusedManager = _GatedCleanupMediaFileManager(
          onFirstDelete: () async => refusedCleanupCalls++,
        );
        var stageContenderEntered = false;
        Future<void>? stageContender;
        final refusedNetwork = FakeP2PNetwork();
        final refusedService = _StoppedPrivateDeleteP2PService(
          peerId: sender,
          network: refusedNetwork,
        );
        addTearDown(refusedService.dispose);
        final refusedAuthoring = mutationFanout(
          refused,
          beforeFirstEncrypt: () => refused.db.update(
            'messages',
            const <String, Object?>{'status': 'failed'},
            where: 'id = ?',
            whereArgs: const <Object?>[refusedMessageId],
          ),
          beforeStage: () async {
            final attempted = refusedLock.nextSharedAttempt();
            stageContender = Zone.root.run(
              () => refusedLock.synchronized(refusedAttachmentId, () async {
                stageContenderEntered = true;
              }),
            );
            await attempted;
            expect(
              stageContenderEntered,
              isFalse,
              reason: 'even a refusing DB stage executes under the lease',
            );
          },
        );

        final (
          refusedResult,
          refusedTombstone,
        ) = await deleteMessageForEveryone(
          p2pService: refusedService,
          messageRepo: refused.messageRepo,
          originalMessage: refusedParent,
          mediaAttachmentRepo: refused.repo,
          mediaFileManager: refusedManager,
          directEventFanout: refusedAuthoring,
        ).timeout(const Duration(seconds: 10));
        await stageContender?.timeout(const Duration(seconds: 10));
        expect(refusedResult, SendChatMessageResult.sendFailed);
        expect(refusedTombstone, isNull);
        expect(stageContenderEntered, isTrue);
        expect(refusedCleanupCalls, 0);
        expect(await fanoutRowsFor(refused, refusedMessageId), isEmpty);
        expect(
          await refused.repo.getAttachmentsForMessage(
            refusedMessageId,
            owner: MediaOwnerLane.direct,
          ),
          hasLength(1),
        );
        expect(refusedNetwork.deliverCallCount, 0);
      },
    );

    test('TC-356-02 private initial and deletion custody converge in both '
        'lifecycle lock orders', () async {
      // ORDER A — the deletion owns the exclusive lease first.
      final firstLock = _SignallingLifecycleLock();
      final first = await MediaRepositoryRealDbFixture.create(
        lifecycleLock: firstLock,
      );
      addTearDown(first.dispose);
      // Every ordering claim below is proven from the lock's own attempt /
      // entry / release signals; this test contains no clock delay.
      final orderA = <String>[];
      const messageIdA = 'tc356-02-delete-first';
      const attachmentIdA = '$messageIdA-att';
      final parentA = await seedLivePrivateParent(
        first,
        messageIdA,
        attachmentIdA,
      );

      final deletionHoldsLease = Completer<void>();
      final releaseDeletion = Completer<void>();
      final gatedManager = _GatedCleanupMediaFileManager(
        onFirstDelete: () async {
          orderA.add('deletion-entered');
          if (!deletionHoldsLease.isCompleted) deletionHoldsLease.complete();
          await releaseDeletion.future;
        },
      );
      final networkA = FakeP2PNetwork();
      final stoppedA = _StoppedPrivateDeleteP2PService(
        peerId: sender,
        network: networkA,
      );
      addTearDown(stoppedA.dispose);

      final deletionA = deleteMessageForEveryone(
        p2pService: stoppedA,
        messageRepo: first.messageRepo,
        originalMessage: parentA,
        mediaAttachmentRepo: first.repo,
        mediaFileManager: gatedManager,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );
      addTearDown(() {
        if (!releaseDeletion.isCompleted) releaseDeletion.complete();
      });
      await Future.any(<Future<Object?>>[
        deletionHoldsLease.future,
        deletionA,
      ]).timeout(const Duration(seconds: 10));
      expect(
        deletionHoldsLease.isCompleted,
        isTrue,
        reason:
            'a node-off private deletion must stage its exact v109 event and '
            'run incumbent cleanup under the private lifecycle lease',
      );

      var handoffStarted = false;
      // The contender's OWN acquisition attempt is the signal; the deletion is
      // still inside its exclusive section here, so these are exact.
      final handoffAttempted = firstLock.nextSharedAttempt();
      final handoffA = runInitialHandoff(
        first,
        messageId: messageIdA,
        attachmentId: attachmentIdA,
        onEnter: () {
          orderA.add('handoff-entered');
          handoffStarted = true;
        },
      );
      await handoffAttempted.timeout(const Duration(seconds: 10));
      orderA.add('handoff-attempted');
      expect(
        handoffStarted,
        isFalse,
        reason:
            'the competing initial handoff may not even start while the '
            'deletion holds the repository-wide private lifecycle lease',
      );
      expect(await v108Rows(first, messageIdA), isEmpty);
      expect(
        await first.db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: const <Object?>[messageIdA],
        ),
        isEmpty,
      );
      expect(networkA.deliverCallCount, 0);
      expect(networkA.storeInInboxCallCount, 0);

      orderA.add('deletion-released');
      releaseDeletion.complete();
      final (resultA, tombstoneA) = await deletionA.timeout(
        const Duration(seconds: 10),
      );
      expect(resultA, SendChatMessageResult.nodeNotRunning);
      expect(tombstoneA?.isDeleted, isTrue);
      expect(
        await v109RowsFor(first, messageIdA),
        hasLength(1),
        reason: 'the exact deletion event is retained across the race',
      );

      // The later handoff now observes the tombstone and refuses before any
      // new v108/v111 obligation or network work.
      final handoffResultA = await handoffA.timeout(
        const Duration(seconds: 10),
      );
      expect(handoffStarted, isTrue);
      expect(handoffResultA.authorizesTransport, isFalse);
      expect(await v108Rows(first, messageIdA), isEmpty);
      expect(networkA.deliverCallCount, 0);
      expect(orderA, <String>[
        'deletion-entered',
        'handoff-attempted',
        'deletion-released',
        'handoff-entered',
      ], reason: 'the contender entered only after the lease was released');

      // ORDER B — the incumbent initial handoff owns the lease first.
      final secondLock = _SignallingLifecycleLock();
      final second = await MediaRepositoryRealDbFixture.create(
        lifecycleLock: secondLock,
      );
      addTearDown(second.dispose);
      final orderB = <String>[];
      const messageIdB = 'tc356-02-handoff-first';
      const attachmentIdB = '$messageIdB-att';
      final parentB = await seedLivePrivateParent(
        second,
        messageIdB,
        attachmentIdB,
      );

      final handoffHoldsLease = Completer<void>();
      final releaseHandoff = Completer<void>();
      final handoffB = runInitialHandoff(
        second,
        messageId: messageIdB,
        attachmentId: attachmentIdB,
        onEnter: () {
          orderB.add('handoff-entered');
          if (!handoffHoldsLease.isCompleted) handoffHoldsLease.complete();
        },
        gate: () => releaseHandoff.future,
      );
      await handoffHoldsLease.future.timeout(const Duration(seconds: 5));

      final networkB = FakeP2PNetwork();
      final stoppedB = _StoppedPrivateDeleteP2PService(
        peerId: sender,
        network: networkB,
      );
      addTearDown(stoppedB.dispose);
      final observingManager = _GatedCleanupMediaFileManager(
        onFirstDelete: () async => orderB.add('deletion-entered'),
      );
      // The deletion's own exclusive acquisition attempt is the signal.
      final deletionAttempted = secondLock.nextExclusiveAttempt();
      final deletionB = deleteMessageForEveryone(
        p2pService: stoppedB,
        messageRepo: second.messageRepo,
        originalMessage: parentB,
        mediaAttachmentRepo: second.repo,
        mediaFileManager: observingManager,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );
      await deletionAttempted.timeout(const Duration(seconds: 10));
      orderB.add('deletion-attempted');

      expect(
        (await second.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[messageIdB],
        )).single['deleted_at'],
        isNull,
        reason:
            'no tombstone may commit while the incumbent initial handoff '
            'still owns the private lifecycle lease',
      );
      expect(await v109RowsFor(second, messageIdB), isEmpty);
      expect(observingManager.deletedFilePaths, isEmpty);
      expect(networkB.deliverCallCount, 0);
      expect(networkB.storeInInboxCallCount, 0);

      orderB.add('handoff-released');
      releaseHandoff.complete();
      await handoffB.timeout(const Duration(seconds: 10));
      final (resultB, tombstoneB) = await deletionB.timeout(
        const Duration(seconds: 10),
      );
      expect(resultB, SendChatMessageResult.nodeNotRunning);
      expect(tombstoneB?.isDeleted, isTrue);
      expect(await v109RowsFor(second, messageIdB), hasLength(1));
      expect(
        orderB,
        <String>[
          'handoff-entered',
          'deletion-attempted',
          'handoff-released',
          'deletion-entered',
        ],
        reason: 'the deletion entered only after the incumbent lease released',
      );
    });
  });

  group('Plan 359 disappearing deletion custody and live initial retention', () {
    const sender = 'peer-alice';
    const recipient = 'contact-1';
    const recipientMlKemPublicKey = 'recipient-mlkem-public-key';
    const t0 = '2026-08-11T09:00:00.000Z';
    const nowMs = 1900000000000;
    const contentHash =
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

    /// Seeds one delivered outgoing v1 disappearing parent with the exact Plan
    /// 358 sender shape and one coherent image attachment. [live] additionally
    /// binds a stored v111 generation to a live v108 incarnation; otherwise the
    /// per-attachment fingerprint is the only surviving proof (post-drain).
    Future<
      ({ConversationMessage parent, String attachmentId, String localPath})
    >
    seedDisappearingParent(
      MediaRepositoryRealDbFixture target,
      String messageId, {
      required bool live,
    }) async {
      final attachmentId = '$messageId-att';
      final localPath = MediaFilePathConvention.relativePathForAttachment(
        contactPeerId: recipient,
        blobId: attachmentId,
        mime: 'image/jpeg',
      );
      final initialEnvelope =
          '{"type":"chat_message","version":"2","id":"$messageId",'
          '"senderPeerId":"$sender","encrypted":{"kem":"k","ciphertext":"c",'
          '"nonce":"n"}}';
      await target.db.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': recipient,
        'sender_peer_id': sender,
        'text': '',
        'timestamp': t0,
        'status': 'delivered',
        'is_incoming': 0,
        'created_at': t0,
        'wire_envelope': initialEnvelope,
        'private_media_policy_version': 1,
        'private_media_mode': 'disappearing',
        'private_media_duration_seconds': 3600,
        'private_media_state': 'available',
      });
      await target.repo.saveAttachment(
        MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          localPath: localPath,
          downloadStatus: 'done',
          createdAt: t0,
          contentHash: contentHash,
          encryptionKeyBase64: 'cHJpdmF0ZS1rZXk=',
          encryptionNonce: 'bm9uY2U=',
          encryptionScheme: 'blob_aes_256_gcm_v1',
        ),
        owner: MediaOwnerLane.direct,
      );
      const ciphertextSize = 4096;
      const expiresAtMs = nowMs + 600000;
      final commitment = DirectMediaBlobCustodyCommitment(
        contentHash: contentHash,
        ciphertextSize: ciphertextSize,
        expiresAtMs: expiresAtMs,
      );
      await target.db.update(
        'media_attachments',
        <String, Object?>{
          'direct_media_blob_custody_fingerprint':
              computeDirectMediaBlobCommitmentFingerprint(
                attachmentId: attachmentId,
                commitment: commitment,
              ),
        },
        where: 'id = ?',
        whereArgs: <Object?>[attachmentId],
      );
      if (live) {
        const incarnationId = 'd0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0';
        await target.db.insert(
          kDirectMediaBlobCustodyTable,
          DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: DirectMediaBlobCustodyState.outgoingStored,
            inboxCustodyIncarnationId: incarnationId,
            recipientPeerId: recipient,
            ciphertextRelativePath:
                'direct_media_blob_custody_v1/${'d' * 64}/$attachmentId.blob',
            contentHash: contentHash,
            ciphertextSize: ciphertextSize,
            expiresAtMs: expiresAtMs,
            custodyRelayPeerId: 'relay-359',
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: t0,
            updatedAt: t0,
          ).toMap(),
        );
        await target.db.insert('direct_inbox_custody_outbox', <String, Object?>{
          'recipient_peer_id': recipient,
          'message_id': messageId,
          'incarnation_id': incarnationId,
          'wire_envelope': initialEnvelope,
          'retry_count': 0,
          'created_at': t0,
          'updated_at': t0,
          'media_blob_manifest_hash': computeDirectMediaBlobManifestHash(
            <DirectMediaBlobManifestProjection>[
              DirectMediaBlobManifestProjection(
                attachmentId: attachmentId,
                commitment: commitment,
              ),
            ],
          ),
          'media_blob_expires_at_ms': expiresAtMs,
        });
      }
      return (
        parent: (await target.messageRepo.getMessage(messageId))!,
        attachmentId: attachmentId,
        localPath: localPath,
      );
    }

    Future<List<Map<String, Object?>>> v109RowsFor(
      MediaRepositoryRealDbFixture target,
      String messageId,
    ) async => (await target.db.query('direct_reaction_inbox_custody_outbox'))
        .where((row) => (row['wire_envelope']! as String).contains(messageId))
        .toList(growable: false);

    test('TC-359-02b disappearing DFE serializes stage to cleanup and retains '
        'live initial custody', () async {
      // --- ORDER A: the deletion owns the exclusive lease first; no contender
      // and no network may enter between the selected stage and cleanup. ---
      final firstLock = _SignallingLifecycleLock();
      final first = await MediaRepositoryRealDbFixture.create(
        lifecycleLock: firstLock,
      );
      addTearDown(first.dispose);
      final orderA = <String>[];
      const messageIdA = 'tc359-02b-post-drain';
      final seededA = await seedDisappearingParent(
        first,
        messageIdA,
        live: false,
      );

      final deletionHoldsLease = Completer<void>();
      final releaseDeletion = Completer<void>();
      final gatedManager = _GatedCleanupMediaFileManager(
        onFirstDelete: () async {
          orderA.add('deletion-entered');
          if (!deletionHoldsLease.isCompleted) deletionHoldsLease.complete();
          await releaseDeletion.future;
        },
      );
      final networkA = FakeP2PNetwork();
      final stoppedA = _StoppedPrivateDeleteP2PService(
        peerId: sender,
        network: networkA,
      );
      addTearDown(stoppedA.dispose);

      final deletionA = deleteMessageForEveryone(
        p2pService: stoppedA,
        messageRepo: first.messageRepo,
        originalMessage: seededA.parent,
        mediaAttachmentRepo: first.repo,
        mediaFileManager: gatedManager,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );
      addTearDown(() {
        if (!releaseDeletion.isCompleted) releaseDeletion.complete();
      });
      await Future.any(<Future<Object?>>[
        deletionHoldsLease.future,
        deletionA,
      ]).timeout(const Duration(seconds: 10));
      expect(
        deletionHoldsLease.isCompleted,
        isTrue,
        reason:
            'a node-off disappearing deletion must stage its exact v109 event '
            'and run private cleanup under the same lifecycle lease',
      );
      // The stage already committed before the first artifact removal.
      expect(await v109RowsFor(first, messageIdA), hasLength(1));
      expect(
        (await first.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[messageIdA],
        )).single['deleted_at'],
        isNotNull,
      );

      var contenderStarted = false;
      final contenderAttempted = firstLock.nextSharedAttempt();
      final contenderA = first.repo.lifecycleLock.synchronized(
        seededA.attachmentId,
        () async {
          orderA.add('contender-entered');
          contenderStarted = true;
        },
      );
      await contenderAttempted.timeout(const Duration(seconds: 10));
      orderA.add('contender-attempted');
      expect(
        contenderStarted,
        isFalse,
        reason:
            'no competing lifecycle section may interleave between the '
            'selected stage and its private cleanup',
      );
      expect(networkA.deliverCallCount, 0);
      expect(networkA.storeInInboxCallCount, 0);

      orderA.add('deletion-released');
      releaseDeletion.complete();
      final (resultA, tombstoneA) = await deletionA.timeout(
        const Duration(seconds: 10),
      );
      await contenderA.timeout(const Duration(seconds: 10));
      expect(resultA, SendChatMessageResult.nodeNotRunning);
      expect(tombstoneA?.isDeleted, isTrue);
      expect(orderA, <String>[
        'deletion-entered',
        'contender-attempted',
        'deletion-released',
        'contender-entered',
      ]);
      // Post-drain lineage owns nothing live, so its artifacts are cleaned.
      expect(
        await first.repo.getAttachmentsForMessage(
          messageIdA,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
      expect(
        await first.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(seededA.attachmentId),
        ),
        isFalse,
      );
      expect(gatedManager.deletedFilePaths, isNotEmpty);

      // --- ORDER B: the incumbent lifecycle contender owns the lease FIRST,
      // so no tombstone, v109 or cleanup may commit until it releases. The
      // same run proves that a LIVE v108/bound v111 generation retains its
      // exact attachment, key and artifacts through the deletion. ---
      final secondLock = _SignallingLifecycleLock();
      final second = await MediaRepositoryRealDbFixture.create(
        lifecycleLock: secondLock,
      );
      addTearDown(second.dispose);
      final orderB = <String>[];
      const messageIdB = 'tc359-02b-live-custody';
      final seededB = await seedDisappearingParent(
        second,
        messageIdB,
        live: true,
      );

      final contenderHoldsLease = Completer<void>();
      final releaseContender = Completer<void>();
      addTearDown(() {
        if (!releaseContender.isCompleted) releaseContender.complete();
      });
      final contenderB = second.repo.lifecycleLock.synchronized(
        seededB.attachmentId,
        () async {
          orderB.add('contender-entered');
          if (!contenderHoldsLease.isCompleted) contenderHoldsLease.complete();
          await releaseContender.future;
        },
      );
      await contenderHoldsLease.future.timeout(const Duration(seconds: 10));

      final networkB = FakeP2PNetwork();
      final stoppedB = _StoppedPrivateDeleteP2PService(
        peerId: sender,
        network: networkB,
      );
      addTearDown(stoppedB.dispose);
      final managerB = _GatedCleanupMediaFileManager(
        onFirstDelete: () async => orderB.add('deletion-entered'),
      );
      // The deletion's OWN exclusive acquisition attempt is the signal.
      final deletionAttempted = secondLock.nextExclusiveAttempt();
      final deletionB = deleteMessageForEveryone(
        p2pService: stoppedB,
        messageRepo: second.messageRepo,
        originalMessage: seededB.parent,
        mediaAttachmentRepo: second.repo,
        mediaFileManager: managerB,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );
      await deletionAttempted.timeout(const Duration(seconds: 10));
      orderB.add('deletion-attempted');

      expect(
        (await second.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[messageIdB],
        )).single['deleted_at'],
        isNull,
        reason:
            'no tombstone may commit while the incumbent lifecycle contender '
            'still owns the private lease',
      );
      expect(await v109RowsFor(second, messageIdB), isEmpty);
      expect(managerB.deletedFilePaths, isEmpty);
      expect(networkB.deliverCallCount, 0);
      expect(networkB.storeInInboxCallCount, 0);

      orderB.add('contender-released');
      releaseContender.complete();
      await contenderB.timeout(const Duration(seconds: 10));
      final (resultB, tombstoneB) = await deletionB.timeout(
        const Duration(seconds: 10),
      );
      expect(orderB, <String>[
        'contender-entered',
        'deletion-attempted',
        'contender-released',
      ], reason: 'the deletion never entered artifact cleanup at all');

      expect(resultB, SendChatMessageResult.nodeNotRunning);
      expect(tombstoneB?.isDeleted, isTrue);
      expect(await v109RowsFor(second, messageIdB), hasLength(1));
      expect(networkB.deliverCallCount, 0);
      expect(networkB.storeInInboxCallCount, 0);
      // The independent initial owner keeps everything it can still need.
      expect(
        await second.repo.getAttachmentsForMessage(
          messageIdB,
          owner: MediaOwnerLane.direct,
        ),
        hasLength(1),
        reason: 'a live v108/bound v111 generation retains its attachment',
      );
      expect(
        await second.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(seededB.attachmentId),
        ),
        isTrue,
        reason: 'the live generation still needs its exact media key',
      );
      expect(
        managerB.deletedFilePaths,
        isEmpty,
        reason: 'no artifact of a live initial generation may be destroyed',
      );
      expect(
        await second.db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: const <Object?>[messageIdB],
        ),
        hasLength(1),
      );
      expect(
        (await second.db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: const <Object?>[messageIdB],
        )).single['state'],
        'outgoing_stored',
      );
    });
  });
}

/// Signals every acquisition ATTEMPT on the real repository-wide private
/// lifecycle lock, so a competing contender is observed deterministically
/// instead of by a wall-clock delay.
class _SignallingLifecycleLock extends MediaAttachmentLifecycleLock {
  final List<Completer<void>> _exclusiveWaiters = <Completer<void>>[];
  final List<Completer<void>> _sharedWaiters = <Completer<void>>[];

  Future<void> nextExclusiveAttempt() {
    final waiter = Completer<void>();
    _exclusiveWaiters.add(waiter);
    return waiter.future;
  }

  Future<void> nextSharedAttempt() {
    final waiter = Completer<void>();
    _sharedWaiters.add(waiter);
    return waiter.future;
  }

  static void _release(List<Completer<void>> waiters) {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    waiters.clear();
  }

  @override
  Future<T> synchronizedAll<T>(Future<T> Function() action) {
    _release(_exclusiveWaiters);
    return super.synchronizedAll(action);
  }

  @override
  Future<T> synchronized<T>(String attachmentId, Future<T> Function() action) {
    _release(_sharedWaiters);
    return super.synchronized(attachmentId, action);
  }
}

/// Pauses inside the deletion's private artifact cleanup, which runs under the
/// same repository-wide exclusive lease that owns its atomic stage.
class _GatedCleanupMediaFileManager extends FakeMediaFileManager {
  _GatedCleanupMediaFileManager({required this.onFirstDelete});

  final Future<void> Function() onFirstDelete;
  bool _observed = false;

  @override
  Future<void> deleteFile(
    String localPath, {
    String caller = 'MediaFileManager.deleteFile',
    String reason = 'media_file_delete',
    String? storedPath,
    Map<String, Object?> details = const {},
    bool redactTelemetry = false,
  }) async {
    if (!_observed) {
      _observed = true;
      await onFirstDelete();
    }
    return super.deleteFile(
      localPath,
      caller: caller,
      reason: reason,
      storedPath: storedPath,
      details: details,
      redactTelemetry: redactTelemetry,
    );
  }
}

class _StoppedPrivateDeleteP2PService extends FakeP2PService {
  _StoppedPrivateDeleteP2PService({
    required super.peerId,
    required super.network,
  });

  @override
  NodeState get currentState => NodeState(isStarted: false, peerId: peerId);
}
