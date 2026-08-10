import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../shared/fakes/fake_media_file_manager.dart';
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
      final wipeBody = lifecycle.substring(wipe, wipe + 3000);
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
}
