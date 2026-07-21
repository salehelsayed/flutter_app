import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

import '../../../../shared/fixtures/media_repository_real_db_fixture.dart';

class _FailFirstDeleteSecureKeyStore extends RecordingSecureKeyStore {
  String? failOnceFor;

  @override
  Future<void> delete(String key) async {
    if (failOnceFor == key) {
      failOnceFor = null;
      throw StateError('injected first secure-key delete failure');
    }
    await super.delete(key);
  }
}

class _FailingSnapshotSecureKeyStore extends RecordingSecureKeyStore {
  bool failContains = false;
  bool failRead = false;

  @override
  Future<bool> containsKey(String key) {
    if (failContains) {
      throw StateError('injected containsKey failure');
    }
    return super.containsKey(key);
  }

  @override
  Future<String?> read(String key) {
    if (failRead) {
      throw StateError('injected read failure');
    }
    return super.read(key);
  }
}

void main() {
  // 228: the repository fixture is a REAL in-memory database built through
  // the shared production registry (current schema), not a hand-rolled map
  // store — so owner filtering, the CHECK constraint and the atomic
  // local-state-preserving merge are exercised for real.
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  Future<Map<String, Object?>?> rawRow(String id) =>
      fixture.rawAttachmentRow(id);

  MediaAttachment makeAttachment({
    String id = 'blob-001',
    String messageId = 'msg-001',
    String mime = 'image/jpeg',
    int size = 245000,
    String mediaType = 'image',
    int? width = 1920,
    int? height = 1080,
    int? durationMs,
    String downloadStatus = 'pending',
    String createdAt = '2026-02-20T10:00:00.000Z',
    String? localPath,
    String? encryptionKeyBase64,
    String? encryptionNonce,
    String? encryptionScheme,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: size,
      mediaType: mediaType,
      width: width,
      height: height,
      durationMs: durationMs,
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: createdAt,
      encryptionKeyBase64: encryptionKeyBase64,
      encryptionNonce: encryptionNonce,
      encryptionScheme: encryptionScheme,
    );
  }

  Future<void> saveDirect(MediaAttachment attachment) =>
      fixture.repo.saveAttachment(attachment, owner: MediaOwnerLane.direct);

  group('MediaAttachmentRepositoryImpl', () {
    test(
      'all public row writers queue behind exact lifecycle qualification',
      () async {
        final lock = MediaAttachmentLifecycleLock();
        await fixture.dispose();
        fixture = await MediaRepositoryRealDbFixture.create(
          lifecycleLock: lock,
        );

        Future<void> expectQueued<T>({
          required String attachmentId,
          required Future<T> Function() mutate,
          required Future<void> Function() whileHeld,
          required Future<void> Function(T result) afterRelease,
        }) async {
          final entered = Completer<void>();
          final release = Completer<void>();
          final holder = lock.synchronized(attachmentId, () async {
            entered.complete();
            await release.future;
          });
          await entered.future;

          var completed = false;
          final mutation = mutate().whenComplete(() => completed = true);
          await Future<void>.delayed(Duration.zero);
          await whileHeld();
          expect(completed, isFalse);

          release.complete();
          await holder;
          final result = await mutation;
          expect(completed, isTrue);
          await afterRelease(result);
        }

        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'queued-direct',
            messageId: 'queued-direct-parent',
            size: 100,
          ),
          owner: MediaOwnerLane.direct,
        );

        await expectQueued<void>(
          attachmentId: 'queued-direct',
          mutate: () => fixture.repo.updateLocalPath(
            'queued-direct',
            'media/direct/queued-direct.jpg',
          ),
          whileHeld: () async {
            expect((await rawRow('queued-direct'))!['local_path'], isNull);
          },
          afterRelease: (_) async {
            final row = await rawRow('queued-direct');
            expect(row!['local_path'], 'media/direct/queued-direct.jpg');
            expect(row['download_status'], 'done');
          },
        );

        await expectQueued<void>(
          attachmentId: 'queued-direct',
          mutate: () =>
              fixture.repo.updateDownloadStatus('queued-direct', 'failed'),
          whileHeld: () async {
            expect((await rawRow('queued-direct'))!['download_status'], 'done');
          },
          afterRelease: (_) async {
            expect(
              (await rawRow('queued-direct'))!['download_status'],
              'failed',
            );
          },
        );

        await expectQueued<void>(
          attachmentId: 'queued-direct',
          mutate: () => fixture.repo.saveAttachment(
            makeAttachment(
              id: 'queued-direct',
              messageId: 'queued-direct-parent',
              size: 999,
              downloadStatus: 'done',
            ),
            owner: MediaOwnerLane.direct,
          ),
          whileHeld: () async {
            expect((await rawRow('queued-direct'))!['size'], 100);
          },
          afterRelease: (_) async {
            expect((await rawRow('queued-direct'))!['size'], 999);
          },
        );

        await expectQueued<int>(
          attachmentId: 'queued-direct',
          mutate: () => fixture.repo.deleteAttachmentsForMessage(
            'queued-direct-parent',
            owner: MediaOwnerLane.direct,
          ),
          whileHeld: () async {
            expect(await rawRow('queued-direct'), isNotNull);
          },
          afterRelease: (deleted) async {
            expect(deleted, 1);
            expect(await rawRow('queued-direct'), isNull);
          },
        );

        await fixture.repo.saveAttachment(
          makeAttachment(id: 'queued-group', messageId: 'queued-group-parent'),
          owner: MediaOwnerLane.group,
        );
        await expectQueued<void>(
          attachmentId: 'queued-group',
          mutate: () =>
              fixture.repo.updateDownloadStatus('queued-group', 'failed'),
          whileHeld: () async {
            expect(
              (await rawRow('queued-group'))!['download_status'],
              'pending',
            );
          },
          afterRelease: (_) async {
            expect(
              (await rawRow('queued-group'))!['download_status'],
              'failed',
            );
          },
        );
      },
    );

    test(
      'authorization stream emits exact path status eviction and delete mutations',
      () async {
        final changes = <MediaAttachmentAuthorizationChange>[];
        final subscription = fixture.repo.authorizationChanges.listen(
          changes.add,
        );
        addTearDown(subscription.cancel);
        await saveDirect(
          makeAttachment(
            id: 'pip-attachment',
            messageId: 'pip-parent',
            mediaType: 'video',
            mime: 'video/mp4',
            downloadStatus: 'done',
            localPath: 'media/direct/pip-attachment.mp4',
          ),
        );
        changes.clear();

        await fixture.repo.updateLocalPath(
          'pip-attachment',
          'media/direct/pip-attachment-v2.mp4',
        );
        await fixture.repo.updateDownloadStatus('pip-attachment', 'failed');
        await fixture.repo.updateDownloadStatus('pip-attachment', 'done');
        expect(
          await fixture.repo.claimMediaEvicted(
            'pip-attachment',
            owner: MediaOwnerLane.direct,
            expectedLocalPath: 'media/direct/pip-attachment-v2.mp4',
          ),
          1,
        );
        expect(
          await fixture.repo.deleteAttachmentsForMessage(
            'pip-parent',
            owner: MediaOwnerLane.direct,
          ),
          1,
        );

        expect(
          changes.map((change) => change.kind),
          <MediaAttachmentAuthorizationMutation>[
            MediaAttachmentAuthorizationMutation.localPathChanged,
            MediaAttachmentAuthorizationMutation.downloadStatusChanged,
            MediaAttachmentAuthorizationMutation.downloadStatusChanged,
            MediaAttachmentAuthorizationMutation.evicted,
            MediaAttachmentAuthorizationMutation.removed,
          ],
        );
        for (final change in changes) {
          expect(change.owner, MediaOwnerLane.direct);
          expect(change.messageId, 'pip-parent');
          expect(change.attachmentId, 'pip-attachment');
        }
      },
    );

    test('saveAttachment persists to store', () async {
      await saveDirect(makeAttachment());

      final row = await rawRow('blob-001');
      expect(row, isNotNull);
      expect(row!['mime'], 'image/jpeg');
      expect(row['message_id'], 'msg-001');
      expect(row['size'], 245000);
      expect(row['owner_lane'], 'direct');
    });

    test(
      'ordinary new direct upload rows bypass private pending preparation',
      () async {
        await saveDirect(
          makeAttachment(
            id: 'ordinary-source-upload',
            messageId: 'ordinary-source-parent',
            downloadStatus: 'upload_pending',
            localPath: '/tmp/ordinary-source.jpg',
          ),
        );

        final row = await rawRow('ordinary-source-upload');
        expect(row, isNotNull);
        expect(row!['download_status'], 'upload_pending');
        expect(row['local_path'], '/tmp/ordinary-source.jpg');
        expect(row['owner_lane'], MediaOwnerLane.direct.dbValue);

        await saveDirect(
          makeAttachment(
            id: 'ordinary-source-upload',
            messageId: 'ordinary-source-parent',
            downloadStatus: 'upload_failed',
            localPath: '/tmp/ordinary-source.jpg',
          ),
        );
        expect(
          (await rawRow('ordinary-source-upload'))!['download_status'],
          'upload_failed',
        );
      },
    );

    test('saveAttachment updates transport metadata in place', () async {
      await saveDirect(makeAttachment(downloadStatus: 'pending'));
      await saveDirect(makeAttachment(downloadStatus: 'done'));

      expect((await fixture.db.query('media_attachments')).length, 1);
      expect((await rawRow('blob-001'))!['download_status'], 'done');
    });

    test(
      'ordinary pending direct replay may correct media type and rotate key',
      () async {
        const id = 'ordinary-direct-correction';
        await saveDirect(
          makeAttachment(
            id: id,
            mime: 'image/jpeg',
            mediaType: 'image',
            encryptionKeyBase64: 'b2xkLWtleQ==',
            encryptionNonce: 'b2xkLW5vbmNl',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: id,
            mime: 'video/mp4',
            mediaType: 'video',
            width: null,
            height: null,
            durationMs: 900,
            encryptionKeyBase64: 'bmV3LWtleQ==',
            encryptionNonce: 'bmV3LW5vbmNl',
          ),
        );

        final row = await rawRow(id);
        expect(row!['mime'], 'video/mp4');
        expect(row['media_type'], 'video');
        expect(row['duration_ms'], 900);
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(id),
          ),
          'bmV3LWtleQ==',
        );
      },
    );

    test(
      'saveAttachment preserves a completed local path from stale pending saves',
      () async {
        await saveDirect(makeAttachment(downloadStatus: 'pending'));
        await fixture.repo.updateLocalPath(
          'blob-001',
          'media/peer/blob-001.jpg',
        );

        await saveDirect(makeAttachment(downloadStatus: 'pending'));

        final row = await rawRow('blob-001');
        expect(row!['local_path'], 'media/peer/blob-001.jpg');
        expect(row['download_status'], 'done');
      },
    );

    test(
      'saveAttachment preserves completed media state over stale upload pending saves',
      () async {
        await saveDirect(
          makeAttachment(
            downloadStatus: 'done',
            localPath: 'media/peer/blob-001.jpg',
          ),
        );

        await saveDirect(
          makeAttachment(
            downloadStatus: 'upload_pending',
            localPath: 'pending_uploads/msg-001/blob-001.jpg',
          ),
        );

        final row = await rawRow('blob-001');
        expect(row!['local_path'], 'media/peer/blob-001.jpg');
        expect(row['download_status'], 'done');
      },
    );

    test(
      'saveAttachment still allows terminal failure to clear a completed path',
      () async {
        await saveDirect(
          makeAttachment(
            downloadStatus: 'done',
            localPath: 'media/peer/blob-001.jpg',
          ),
        );

        await saveDirect(makeAttachment(downloadStatus: 'failed'));

        final row = await rawRow('blob-001');
        expect(row!['local_path'], isNull);
        expect(row['download_status'], 'failed');
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING saveAttachment stores media key in secure storage and only a reference in SQL',
      () async {
        await saveDirect(
          makeAttachment(
            encryptionKeyBase64: 'plain-media-key-base64',
            encryptionNonce: 'nonce-base64',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );

        final rawKey =
            (await rawRow('blob-001'))!['encryption_key_base64'] as String?;
        expect(rawKey, isNot('plain-media-key-base64'));
        expect(isSecureStoreReference(rawKey), isTrue);
        expect(
          rawKey,
          secureStoreReferenceForKey(
            mediaAttachmentEncryptionKeyStoreName('blob-001'),
          ),
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName('blob-001'),
          ),
          'plain-media-key-base64',
        );
      },
    );

    test(
      'failed attachment DB save compensates a new key and restores a pre-existing key',
      () async {
        await fixture.dispose();
        fixture = await MediaRepositoryRealDbFixture.create(
          dbSaveMediaAttachmentOverride: (_) async {
            throw StateError('injected DB save failure');
          },
        );

        const newId = 'blob-failed-new-key';
        await expectLater(
          fixture.repo.saveAttachment(
            makeAttachment(
              id: newId,
              encryptionKeyBase64: 'new-key-value',
              encryptionNonce: 'nonce-new',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            owner: MediaOwnerLane.group,
          ),
          throwsStateError,
        );
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(newId),
          ),
          isFalse,
        );

        const existingId = 'blob-failed-existing-key';
        final existingKeyName = mediaAttachmentEncryptionKeyStoreName(
          existingId,
        );
        await fixture.secureKeyStore.write(existingKeyName, 'original-key');
        await expectLater(
          fixture.repo.saveAttachment(
            makeAttachment(
              id: existingId,
              encryptionKeyBase64: 'replacement-key',
              encryptionNonce: 'nonce-existing',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            owner: MediaOwnerLane.group,
          ),
          throwsStateError,
        );
        expect(
          await fixture.secureKeyStore.read(existingKeyName),
          'original-key',
        );
      },
    );

    test(
      'secure-key snapshot failures leave the existing row and key untouched',
      () async {
        for (final failure in const ['contains', 'read']) {
          await fixture.dispose();
          final secureStore = _FailingSnapshotSecureKeyStore();
          fixture = await MediaRepositoryRealDbFixture.create(
            secureKeyStore: secureStore,
          );
          final id = 'snapshot-failure-$failure';
          final keyName = mediaAttachmentEncryptionKeyStoreName(id);
          await fixture.repo.saveAttachment(
            makeAttachment(
              id: id,
              mime: 'image/jpeg',
              encryptionKeyBase64: 'original-key-$failure',
              encryptionNonce: 'original-nonce-$failure',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            owner: MediaOwnerLane.group,
          );
          final originalRow = Map<String, Object?>.from((await rawRow(id))!);
          secureStore.failContains = failure == 'contains';
          secureStore.failRead = failure == 'read';

          await expectLater(
            fixture.repo.saveAttachment(
              makeAttachment(
                id: id,
                mime: 'image/png',
                encryptionKeyBase64: 'replacement-key-$failure',
                encryptionNonce: 'replacement-nonce-$failure',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              ),
              owner: MediaOwnerLane.group,
            ),
            throwsStateError,
          );

          secureStore.failContains = false;
          secureStore.failRead = false;
          expect(await rawRow(id), originalRow);
          expect(await secureStore.read(keyName), 'original-key-$failure');
        }
      },
    );

    test(
      'guarded group save restores replaced keys on refusal and every throw',
      () async {
        await fixture.dispose();
        var guardThrows = false;
        fixture = await MediaRepositoryRealDbFixture.create(
          dbSaveGroupMediaAttachmentGuardedOverride:
              (row, {required groupId}) async {
                if (guardThrows) {
                  throw StateError('injected guarded group save failure');
                }
                return false;
              },
        );

        Future<bool> guardedSave(String id, String key) =>
            fixture.repo.saveGroupAttachmentGuarded(
              makeAttachment(
                id: id,
                messageId: 'guarded-group-parent',
                encryptionKeyBase64: key,
                encryptionNonce: 'guarded-group-nonce',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              ),
              groupId: 'guarded-group',
            );

        const existingId = 'guarded-group-existing-key';
        final existingKeyName = mediaAttachmentEncryptionKeyStoreName(
          existingId,
        );
        await fixture.secureKeyStore.write(existingKeyName, 'original-key');
        expect(await guardedSave(existingId, 'replacement-on-false'), isFalse);
        expect(
          await fixture.secureKeyStore.read(existingKeyName),
          'original-key',
        );
        expect(await rawRow(existingId), isNull);

        guardThrows = true;
        await expectLater(
          guardedSave(existingId, 'replacement-on-throw'),
          throwsStateError,
        );
        expect(
          await fixture.secureKeyStore.read(existingKeyName),
          'original-key',
        );
        expect(await rawRow(existingId), isNull);

        const newId = 'guarded-group-new-key';
        final newKeyName = mediaAttachmentEncryptionKeyStoreName(newId);
        await expectLater(
          guardedSave(newId, 'new-key-on-throw'),
          throwsStateError,
        );
        expect(await fixture.secureKeyStore.containsKey(newKeyName), isFalse);
        expect(await rawRow(newId), isNull);
      },
    );

    test(
      'exact group upload completion stores only a secure reference and compensates CAS refusal',
      () async {
        Future<({Map<String, Object?> parent, MediaAttachment attachment})>
        seedPending(String suffix) async {
          final messageId = 'group-upload-$suffix';
          final attachmentId = 'group-upload-attachment-$suffix';
          await fixture.seedGroupParent(messageId);
          await fixture.db.update(
            'group_messages',
            {'status': 'failed', 'is_incoming': 0},
            where: 'id = ?',
            whereArgs: [messageId],
          );
          await fixture.repo.saveAttachment(
            makeAttachment(
              id: attachmentId,
              messageId: messageId,
              localPath: 'pending_uploads/$attachmentId.jpg',
              downloadStatus: 'upload_pending',
            ),
            owner: MediaOwnerLane.group,
          );
          final parent = (await fixture.db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: [messageId],
          )).single;
          final attachment = (await fixture.repo.getAttachmentById(
            attachmentId,
          ))!;
          return (parent: parent, attachment: attachment);
        }

        final success = await seedPending('success');
        const rawKey = 'raw-group-upload-key';
        final completed = success.attachment.copyWith(
          downloadStatus: 'done',
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          encryptionKeyBase64: rawKey,
          encryptionNonce: 'group-upload-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        expect(
          await fixture.repo.completeGroupUploadRetrySecurely(
            expectedParent: success.parent,
            expectedAttachment: success.attachment,
            completedAttachment: completed,
          ),
          isTrue,
        );
        final keyName = mediaAttachmentEncryptionKeyStoreName(completed.id);
        expect(await fixture.secureKeyStore.read(keyName), rawKey);
        expect(
          (await rawRow(completed.id))!['encryption_key_base64'],
          secureStoreReferenceForKey(keyName),
        );
        expect(
          (await rawRow(completed.id))!['encryption_key_base64'],
          isNot(rawKey),
        );

        final refused = await seedPending('refused');
        await fixture.db.update(
          'group_messages',
          {'status': 'send_failed'},
          where: 'id = ?',
          whereArgs: [refused.parent['id']],
        );
        final refusedCompletion = refused.attachment.copyWith(
          downloadStatus: 'done',
          contentHash:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          encryptionKeyBase64: 'refused-raw-key',
          encryptionNonce: 'refused-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        expect(
          await fixture.repo.completeGroupUploadRetrySecurely(
            expectedParent: refused.parent,
            expectedAttachment: refused.attachment,
            completedAttachment: refusedCompletion,
          ),
          isFalse,
        );
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(refusedCompletion.id),
          ),
          isFalse,
        );
        expect(
          (await rawRow(refusedCompletion.id))!['download_status'],
          'upload_pending',
        );
      },
    );

    test(
      'new-message rollback removes exact group rows and secure keys only',
      () async {
        for (final id in const ['rollback-a', 'rollback-b']) {
          await fixture.repo.saveAttachment(
            makeAttachment(
              id: id,
              messageId: 'new-group-message',
              encryptionKeyBase64: 'key-$id',
              encryptionNonce: 'nonce-$id',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            owner: MediaOwnerLane.group,
          );
        }
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'preserved-sibling',
            messageId: 'other-group-message',
            encryptionKeyBase64: 'key-preserved',
            encryptionNonce: 'nonce-preserved',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          owner: MediaOwnerLane.group,
        );

        final deleted = await fixture.repo.rollbackNewMessageAttachments(
          messageId: 'new-group-message',
          attachmentIds: const {
            'rollback-a',
            'rollback-b',
            'preserved-sibling',
          },
          owner: MediaOwnerLane.group,
        );

        expect(deleted, 2);
        expect(await rawRow('rollback-a'), isNull);
        expect(await rawRow('rollback-b'), isNull);
        expect(await rawRow('preserved-sibling'), isNotNull);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName('rollback-a'),
          ),
          isFalse,
        );
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName('rollback-b'),
          ),
          isFalse,
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName('preserved-sibling'),
          ),
          'key-preserved',
        );
      },
    );

    test(
      'new-message rollback retries a transient secure-key delete failure',
      () async {
        await fixture.dispose();
        final secureStore = _FailFirstDeleteSecureKeyStore();
        fixture = await MediaRepositoryRealDbFixture.create(
          secureKeyStore: secureStore,
        );
        const attachmentId = 'rollback-delete-retry';
        final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: attachmentId,
            messageId: 'rollback-delete-message',
            encryptionKeyBase64: 'rollback-delete-key',
            encryptionNonce: 'rollback-delete-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          owner: MediaOwnerLane.group,
        );
        secureStore.failOnceFor = keyName;

        final deleted = await fixture.repo.rollbackNewMessageAttachments(
          messageId: 'rollback-delete-message',
          attachmentIds: const {attachmentId},
          owner: MediaOwnerLane.group,
        );

        expect(deleted, 1);
        expect(await rawRow(attachmentId), isNull);
        expect(await secureStore.containsKey(keyName), isFalse);
      },
    );

    test(
      'empty new-message rollback excludes a concurrent attachment insertion',
      () async {
        await fixture.dispose();
        final loadEntered = Completer<void>();
        final releaseLoad = Completer<void>();
        fixture = await MediaRepositoryRealDbFixture.create(
          dbLoadMediaForMessageAround: (messageId, ownerLane, load) async {
            if (messageId == 'rollback-insertion-race') {
              loadEntered.complete();
              await releaseLoad.future;
            }
            return load();
          },
        );

        final rollback = fixture.repo.rollbackNewMessageAttachments(
          messageId: 'rollback-insertion-race',
          attachmentIds: const <String>{},
          owner: MediaOwnerLane.group,
        );
        await loadEntered.future;

        var insertionCompleted = false;
        final insertion = fixture.repo
            .saveAttachment(
              makeAttachment(
                id: 'concurrent-insertion',
                messageId: 'rollback-insertion-race',
                encryptionKeyBase64: 'concurrent-key',
                encryptionNonce: 'concurrent-nonce',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              ),
              owner: MediaOwnerLane.group,
            )
            .whenComplete(() => insertionCompleted = true);
        await Future<void>.delayed(Duration.zero);
        expect(
          insertionCompleted,
          isFalse,
          reason:
              'the insertion must queue behind rollback exclusive authority',
        );
        expect(await rawRow('concurrent-insertion'), isNull);

        releaseLoad.complete();
        expect(await rollback, 0);
        await insertion;
        expect(insertionCompleted, isTrue);
        expect(await rawRow('concurrent-insertion'), isNotNull);
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName('concurrent-insertion'),
          ),
          'concurrent-key',
        );
      },
    );

    test(
      'same-id failed and succeeding saves serialize key compensation',
      () async {
        await fixture.dispose();
        final firstReplacementEnteredDb = Completer<void>();
        final releaseFirstReplacement = Completer<void>();
        var dbSaveCount = 0;
        fixture = await MediaRepositoryRealDbFixture.create(
          dbSaveMediaAttachmentAround: (row, persist) async {
            dbSaveCount++;
            if (dbSaveCount == 2) {
              firstReplacementEnteredDb.complete();
              await releaseFirstReplacement.future;
              throw StateError('injected late first-save DB failure');
            }
            await persist();
          },
        );
        const attachmentId = 'serialized-key-compensation';
        final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
        await saveDirect(
          makeAttachment(
            id: attachmentId,
            encryptionKeyBase64: 'base-key',
            encryptionNonce: 'base-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );

        final failedSave = saveDirect(
          makeAttachment(
            id: attachmentId,
            encryptionKeyBase64: 'first-replacement-key',
            encryptionNonce: 'first-replacement-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );
        await firstReplacementEnteredDb.future;
        final succeedingSave = saveDirect(
          makeAttachment(
            id: attachmentId,
            encryptionKeyBase64: 'second-replacement-key',
            encryptionNonce: 'second-replacement-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          dbSaveCount,
          2,
          reason: 'the second save must wait on the ID lock',
        );

        releaseFirstReplacement.complete();
        await expectLater(failedSave, throwsStateError);
        await succeedingSave;

        expect(
          await fixture.secureKeyStore.read(keyName),
          'second-replacement-key',
        );
        final hydrated = await fixture.repo.getAttachmentById(attachmentId);
        expect(hydrated?.encryptionKeyBase64, 'second-replacement-key');
        expect(hydrated?.encryptionNonce, 'second-replacement-nonce');
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessage hydrates media key from secure storage',
      () async {
        await saveDirect(
          makeAttachment(
            encryptionKeyBase64: 'message-media-key-base64',
            encryptionNonce: 'nonce-base64',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );

        final result = await fixture.repo.getAttachmentsForMessage(
          'msg-001',
          owner: MediaOwnerLane.direct,
        );

        expect(result.single.encryptionKeyBase64, 'message-media-key-base64');
        expect(
          (await rawRow('blob-001'))!['encryption_key_base64'],
          isNot('message-media-key-base64'),
        );
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessages hydrates secure media keys',
      () async {
        await saveDirect(
          makeAttachment(
            id: 'blob-A',
            messageId: 'msg-A',
            encryptionKeyBase64: 'media-key-A',
            encryptionNonce: 'nonce-A',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-B',
            messageId: 'msg-B',
            encryptionKeyBase64: 'media-key-B',
            encryptionNonce: 'nonce-B',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );

        final result = await fixture.repo.getAttachmentsForMessages([
          'msg-A',
          'msg-B',
        ], owner: MediaOwnerLane.direct);

        expect(result['msg-A']!.single.encryptionKeyBase64, 'media-key-A');
        expect(result['msg-B']!.single.encryptionKeyBase64, 'media-key-B');
        expect(
          isSecureStoreReference(
            (await rawRow('blob-A'))!['encryption_key_base64'] as String?,
          ),
          isTrue,
        );
        expect(
          isSecureStoreReference(
            (await rawRow('blob-B'))!['encryption_key_base64'] as String?,
          ),
          isTrue,
        );
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessage clears missing secure media key reference',
      () async {
        final secureStoreKey = mediaAttachmentEncryptionKeyStoreName(
          'blob-missing',
        );
        final row = makeAttachment(
          id: 'blob-missing',
          encryptionKeyBase64: secureStoreReferenceForKey(secureStoreKey),
          encryptionNonce: 'nonce-missing',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ).toMap();
        row['owner_lane'] = 'direct';
        await fixture.db.insert('media_attachments', row);

        final result = await fixture.repo.getAttachmentsForMessage(
          'msg-001',
          owner: MediaOwnerLane.direct,
        );

        expect(result.single.encryptionKeyBase64, isNull);
        expect(
          isSecureStoreReference(result.single.encryptionKeyBase64),
          false,
        );
        expect(result.single.hasEncryptionMetadata, isFalse);
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessages clears missing secure media key references',
      () async {
        final keyA = mediaAttachmentEncryptionKeyStoreName('blob-missing-A');
        final keyB = mediaAttachmentEncryptionKeyStoreName('blob-missing-B');
        final rowA = makeAttachment(
          id: 'blob-missing-A',
          messageId: 'msg-A',
          encryptionKeyBase64: secureStoreReferenceForKey(keyA),
          encryptionNonce: 'nonce-A',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ).toMap();
        rowA['owner_lane'] = 'direct';
        await fixture.db.insert('media_attachments', rowA);
        final rowB = makeAttachment(
          id: 'blob-missing-B',
          messageId: 'msg-B',
          encryptionKeyBase64: secureStoreReferenceForKey(keyB),
          encryptionNonce: 'nonce-B',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ).toMap();
        rowB['owner_lane'] = 'direct';
        await fixture.db.insert('media_attachments', rowB);

        final result = await fixture.repo.getAttachmentsForMessages([
          'msg-A',
          'msg-B',
        ], owner: MediaOwnerLane.direct);

        expect(result['msg-A']!.single.encryptionKeyBase64, isNull);
        expect(result['msg-B']!.single.encryptionKeyBase64, isNull);
        expect(result['msg-A']!.single.hasEncryptionMetadata, isFalse);
        expect(result['msg-B']!.single.hasEncryptionMetadata, isFalse);
      },
    );

    test('getAttachmentsForMessage returns empty list when none', () async {
      final result = await fixture.repo.getAttachmentsForMessage(
        'nonexistent',
        owner: MediaOwnerLane.direct,
      );
      expect(result, isEmpty);
    });

    test('getAttachmentById returns failed attachment by blob id', () async {
      await saveDirect(
        makeAttachment(id: 'blob-failed', downloadStatus: 'failed'),
      );

      final result = await fixture.repo.getAttachmentById('blob-failed');

      expect(result, isNotNull);
      expect(result!.id, 'blob-failed');
      expect(result.downloadStatus, 'failed');
    });

    test('getAttachmentsForMessage returns matching attachments', () async {
      await saveDirect(
        makeAttachment(
          id: 'blob-1',
          messageId: 'msg-A',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      );
      await saveDirect(
        makeAttachment(
          id: 'blob-2',
          messageId: 'msg-A',
          createdAt: '2026-02-20T10:01:00.000Z',
        ),
      );
      await saveDirect(makeAttachment(id: 'blob-3', messageId: 'msg-B'));

      final result = await fixture.repo.getAttachmentsForMessage(
        'msg-A',
        owner: MediaOwnerLane.direct,
      );
      expect(result.length, 2);
      expect(result[0].id, 'blob-1');
      expect(result[1].id, 'blob-2');
    });

    test('getAttachmentsForMessage returns MediaAttachment objects', () async {
      await saveDirect(
        makeAttachment(
          id: 'blob-typed',
          mime: 'video/mp4',
          size: 5000000,
          mediaType: 'video',
          width: 1280,
          height: 720,
        ),
      );

      final result = await fixture.repo.getAttachmentsForMessage(
        'msg-001',
        owner: MediaOwnerLane.direct,
      );
      expect(result.length, 1);
      expect(result[0], isA<MediaAttachment>());
      expect(result[0].mime, 'video/mp4');
      expect(result[0].size, 5000000);
      expect(result[0].width, 1280);
    });

    group('getAttachmentsForMessages', () {
      test('returns empty map for empty messageIds', () async {
        final result = await fixture.repo.getAttachmentsForMessages(
          [],
          owner: MediaOwnerLane.direct,
        );
        expect(result, isEmpty);
      });

      test('groups attachments by messageId', () async {
        await saveDirect(
          makeAttachment(
            id: 'blob-1',
            messageId: 'msg-A',
            createdAt: '2026-02-20T10:00:00.000Z',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-2',
            messageId: 'msg-A',
            createdAt: '2026-02-20T10:01:00.000Z',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-3',
            messageId: 'msg-B',
            createdAt: '2026-02-20T10:02:00.000Z',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-4',
            messageId: 'msg-C',
            createdAt: '2026-02-20T10:03:00.000Z',
          ),
        );

        final result = await fixture.repo.getAttachmentsForMessages([
          'msg-A',
          'msg-B',
        ], owner: MediaOwnerLane.direct);

        expect(result.length, 2);
        expect(result['msg-A']!.length, 2);
        expect(result['msg-A']![0].id, 'blob-1');
        expect(result['msg-A']![1].id, 'blob-2');
        expect(result['msg-B']!.length, 1);
        expect(result['msg-B']![0].id, 'blob-3');
        // msg-C not requested, should not appear
        expect(result.containsKey('msg-C'), isFalse);
      });

      test('returns empty map when no matches', () async {
        await saveDirect(makeAttachment(id: 'blob-1', messageId: 'msg-X'));

        final result = await fixture.repo.getAttachmentsForMessages([
          'msg-A',
          'msg-B',
        ], owner: MediaOwnerLane.direct);
        expect(result, isEmpty);
      });
    });

    test('updateLocalPath updates path and sets status to done', () async {
      await saveDirect(makeAttachment(downloadStatus: 'downloading'));

      await fixture.repo.updateLocalPath('blob-001', '/path/to/file.jpg');

      final row = await rawRow('blob-001');
      expect(row!['local_path'], '/path/to/file.jpg');
      expect(row['download_status'], 'done');
    });

    test('updateDownloadStatus changes status', () async {
      await saveDirect(makeAttachment(downloadStatus: 'pending'));

      await fixture.repo.updateDownloadStatus('blob-001', 'downloading');
      expect((await rawRow('blob-001'))!['download_status'], 'downloading');

      await fixture.repo.updateDownloadStatus('blob-001', 'failed');
      expect((await rawRow('blob-001'))!['download_status'], 'failed');
    });

    test('deleteAttachmentsForMessage removes matching rows', () async {
      await saveDirect(makeAttachment(id: 'blob-1', messageId: 'msg-A'));
      await saveDirect(makeAttachment(id: 'blob-2', messageId: 'msg-A'));
      await saveDirect(makeAttachment(id: 'blob-3', messageId: 'msg-B'));

      final count = await fixture.repo.deleteAttachmentsForMessage(
        'msg-A',
        owner: MediaOwnerLane.direct,
      );
      expect(count, 2);
      final remaining = await fixture.db.query('media_attachments');
      expect(remaining.length, 1);
      expect(remaining.single['id'], 'blob-3');
    });

    test('deleteAttachmentsForMessage returns 0 when no matches', () async {
      final count = await fixture.repo.deleteAttachmentsForMessage(
        'nonexistent',
        owner: MediaOwnerLane.direct,
      );
      expect(count, 0);
    });

    test(
      'markUploadPendingAttachmentsFailedForMessage only terminalizes pending rows for the target message',
      () async {
        await saveDirect(
          makeAttachment(
            id: 'blob-target-pending',
            messageId: 'msg-target',
            downloadStatus: 'upload_pending',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-target-done',
            messageId: 'msg-target',
            downloadStatus: 'done',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-other-pending',
            messageId: 'msg-other',
            downloadStatus: 'upload_pending',
          ),
        );

        final count = await fixture.repo
            .markUploadPendingAttachmentsFailedForMessage(
              'msg-target',
              owner: MediaOwnerLane.direct,
            );

        expect(count, 1);
        expect(
          (await rawRow('blob-target-pending'))!['download_status'],
          'upload_failed',
        );
        expect((await rawRow('blob-target-done'))!['download_status'], 'done');
        expect(
          (await rawRow('blob-other-pending'))!['download_status'],
          'upload_pending',
        );
      },
    );

    test('getPendingDownloads returns only pending attachments', () async {
      await saveDirect(
        makeAttachment(
          id: 'blob-1',
          downloadStatus: 'pending',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      );
      await saveDirect(
        makeAttachment(
          id: 'blob-2',
          downloadStatus: 'done',
          createdAt: '2026-02-20T10:01:00.000Z',
        ),
      );
      await saveDirect(
        makeAttachment(
          id: 'blob-3',
          downloadStatus: 'pending',
          createdAt: '2026-02-20T10:02:00.000Z',
        ),
      );

      final pending = await fixture.repo.getPendingDownloads();
      expect(pending.length, 2);
      expect(pending[0].id, 'blob-1');
      expect(pending[1].id, 'blob-3');
    });

    test('getPendingDownloads returns empty list when none pending', () async {
      await saveDirect(makeAttachment(id: 'blob-1', downloadStatus: 'done'));

      final pending = await fixture.repo.getPendingDownloads();
      expect(pending, isEmpty);
    });

    // --- 228 TC-228-05B (repository slice) ---

    test(
      'owner scoped terminalization and pending limits isolate collision lanes',
      () async {
        await fixture.seedDirectParent('msg-shared');
        await fixture.seedGroupParent('msg-shared');

        // Same message id, one upload-pending attachment per lane.
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-d',
            messageId: 'msg-shared',
            downloadStatus: 'upload_pending',
            createdAt: '2026-02-20T10:00:00.000Z',
          ),
          owner: MediaOwnerLane.direct,
        );
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-g',
            messageId: 'msg-shared',
            downloadStatus: 'upload_pending',
            createdAt: '2026-02-20T09:00:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        // Per-lane pending loads see only their own row.
        final directPending = await fixture.repo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(directPending.map((a) => a.id), ['att-d']);
        final groupPending = await fixture.repo.getUploadPendingAttachments(
          owner: MediaOwnerLane.group,
        );
        expect(groupPending.map((a) => a.id), ['att-g']);

        // Direct terminalization leaves the group sibling untouched.
        final flipped = await fixture.repo
            .markUploadPendingAttachmentsFailedForMessage(
              'msg-shared',
              owner: MediaOwnerLane.direct,
            );
        expect(flipped, 1);
        expect((await rawRow('att-d'))!['download_status'], 'upload_failed');
        expect((await rawRow('att-g'))!['download_status'], 'upload_pending');
      },
    );

    // --- 228 TC-228-08 ---

    test('ordinary replay preserves local viewer state and path while explicit '
        'clears win', () async {
      await fixture.seedDirectParent('msg-shared');
      await fixture.seedGroupParent('msg-shared');

      Future<void> runLaneScenario({
        required MediaOwnerLane owner,
        required String id,
      }) async {
        // Completed video with viewer state.
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: id,
            messageId: 'msg-shared',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 10000,
            downloadStatus: 'done',
            localPath: 'media/peer/$id.mp4',
          ),
          owner: owner,
        );
        await fixture.repo.setBookmarked(id, bookmarked: true);
        await fixture.repo.updatePlaybackPosition(id, 4000);

        // Ordinary transport replay: non-terminal status, no local path,
        // updated metadata (width).
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: id,
            messageId: 'msg-shared',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 10000,
            width: 640,
            downloadStatus: 'pending',
          ),
          owner: owner,
        );

        final row = await rawRow(id);
        // Transport metadata updated...
        expect(row!['width'], 640);
        // ...but local viewer state and the completed path survive.
        expect(row['is_bookmarked'], 1);
        expect(row['last_playback_position_ms'], 4000);
        expect(row['local_path'], 'media/peer/$id.mp4');
        expect(row['download_status'], 'done');
        expect(row['owner_lane'], owner.dbValue);

        // Explicit clears win and do NOT get merged back by a replay.
        await fixture.repo.setBookmarked(id, bookmarked: false);
        await fixture.repo.updatePlaybackPosition(id, 0);
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: id,
            messageId: 'msg-shared',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 10000,
            downloadStatus: 'pending',
          ),
          owner: owner,
        );
        final cleared = await rawRow(id);
        expect(cleared!['is_bookmarked'], 0);
        expect(cleared['last_playback_position_ms'], 0);
      }

      await runLaneScenario(owner: MediaOwnerLane.direct, id: 'att-d');
      await runLaneScenario(owner: MediaOwnerLane.group, id: 'att-g');
    });

    // --- 229 TC-229-12 ---

    test('ordinary replay preserves evicted and viewer state until explicit '
        'owner-aware retry', () async {
      await fixture.seedDirectParent('msg-evict');
      await fixture.seedGroupParent('msg-evict');

      // Collision fixture: both lanes carry attachments under the SAME
      // parent message id, plus a fail-closed unresolved legacy row.
      Future<void> seedEvictedLane(MediaOwnerLane owner, String id) async {
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: id,
            messageId: 'msg-evict',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 9000,
            downloadStatus: 'done',
            localPath: 'media/peer/$id.mp4',
          ),
          owner: owner,
        );
        await fixture.repo.setBookmarked(id, bookmarked: true);
        await fixture.repo.updatePlaybackPosition(id, 3000);
        // The owner-aware eviction claim retains the path for deletion...
        expect(
          await fixture.repo.claimMediaEvicted(
            id,
            owner: owner,
            expectedLocalPath: 'media/peer/$id.mp4',
          ),
          1,
        );
        // ...and the post-delete finalize nulls it.
        expect(
          await fixture.repo.finalizeMediaEvictedPathCleared(id, owner: owner),
          1,
        );
      }

      await seedEvictedLane(MediaOwnerLane.direct, 'att-evict-d');
      await seedEvictedLane(MediaOwnerLane.group, 'att-evict-g');
      await fixture.db.insert('media_attachments', {
        'id': 'att-evict-u',
        'message_id': 'msg-evict',
        'mime': 'video/mp4',
        'size': 10,
        'media_type': 'video',
        'download_status': 'done',
        'local_path': 'media/peer/att-evict-u.mp4',
        'created_at': '2026-02-20T10:00:00.000Z',
        'owner_lane': 'unresolved',
      });

      // Ordinary wire replay (pending, no path, default local fields) in
      // BOTH lanes: transport metadata updates, but evicted status, null
      // path, owner, bookmark and playback all survive.
      for (final (owner, id) in [
        (MediaOwnerLane.direct, 'att-evict-d'),
        (MediaOwnerLane.group, 'att-evict-g'),
      ]) {
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: id,
            messageId: 'msg-evict',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 9000,
            width: 640,
            downloadStatus: 'pending',
          ),
          owner: owner,
        );
        final row = await rawRow(id);
        expect(
          row!['download_status'],
          'evicted',
          reason: '$owner replay must not re-arm an evicted row',
        );
        expect(row['local_path'], isNull);
        expect(row['is_bookmarked'], 1);
        expect(row['last_playback_position_ms'], 3000);
        expect(row['owner_lane'], owner.dbValue);
        expect(row['width'], 640);
      }

      // A blind `done` replay through the ordinary save path cannot
      // resurrect the local copy either.
      await fixture.repo.saveAttachment(
        makeAttachment(
          id: 'att-evict-d',
          messageId: 'msg-evict',
          mime: 'video/mp4',
          mediaType: 'video',
          durationMs: 9000,
          downloadStatus: 'done',
          localPath: 'media/peer/att-evict-d.mp4',
        ),
        owner: MediaOwnerLane.direct,
      );
      final blind = await rawRow('att-evict-d');
      expect(blind!['download_status'], 'evicted');
      expect(blind['local_path'], isNull);

      // The unresolved legacy row is untouched by every lane-scoped
      // operation above.
      final unresolved = await rawRow('att-evict-u');
      expect(unresolved!['download_status'], 'done');
      expect(unresolved['owner_lane'], 'unresolved');
      expect(unresolved['local_path'], 'media/peer/att-evict-u.mp4');

      // A cross-lane retry claim is a lost claim (0 rows), never a
      // mutation of the sibling.
      expect(
        await fixture.repo.beginMediaDownload(
          'att-evict-g',
          owner: MediaOwnerLane.direct,
        ),
        isFalse,
      );
      expect((await rawRow('att-evict-g'))!['download_status'], 'evicted');

      // The explicit matching-owner retry transitions ONLY its row, and
      // the CAS commit from that claim settles done with the fresh path.
      expect(
        await fixture.repo.beginMediaDownload(
          'att-evict-d',
          owner: MediaOwnerLane.direct,
        ),
        isTrue,
      );
      expect((await rawRow('att-evict-d'))!['download_status'], 'downloading');
      expect((await rawRow('att-evict-g'))!['download_status'], 'evicted');
      expect(
        await fixture.repo.commitMediaDownloadLocalPath(
          'att-evict-d',
          owner: MediaOwnerLane.direct,
          localPath: 'media/peer/att-evict-d-new.mp4',
        ),
        isTrue,
      );
      final settled = await rawRow('att-evict-d');
      expect(settled!['download_status'], 'done');
      expect(settled['local_path'], 'media/peer/att-evict-d-new.mp4');
      expect(
        settled['is_bookmarked'],
        1,
        reason: 'viewer state survives the full evict/retry journey',
      );

      // A late commit whose claim was lost (row no longer downloading)
      // affects zero rows.
      expect(
        await fixture.repo.commitMediaDownloadLocalPath(
          'att-evict-d',
          owner: MediaOwnerLane.direct,
          localPath: 'media/peer/att-evict-d-stale.mp4',
        ),
        isFalse,
      );
      expect(
        (await rawRow('att-evict-d'))!['local_path'],
        'media/peer/att-evict-d-new.mp4',
      );
    });

    // --- 228 TC-228-10 ---

    test(
      'video resume handles unknown duration revalidation and completion',
      () async {
        // Unknown-duration video.
        await saveDirect(
          makeAttachment(
            id: 'vid-unknown',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: null,
            downloadStatus: 'done',
          ),
        );

        // Negative clamps to zero.
        await fixture.repo.updatePlaybackPosition('vid-unknown', -50);
        expect((await rawRow('vid-unknown'))!['last_playback_position_ms'], 0);

        // Unknown duration stores any non-negative position.
        await fixture.repo.updatePlaybackPosition('vid-unknown', 123456);
        expect(
          (await rawRow('vid-unknown'))!['last_playback_position_ms'],
          123456,
        );

        // A later replay that supplies the duration re-clamps the stored
        // overshoot to the new known duration.
        await saveDirect(
          makeAttachment(
            id: 'vid-unknown',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 9000,
            downloadStatus: 'done',
          ),
        );
        expect(
          (await rawRow('vid-unknown'))!['last_playback_position_ms'],
          9000,
        );

        // Known duration: in-range stores, end-or-past resets to 0
        // (completion).
        await fixture.repo.updatePlaybackPosition('vid-unknown', 4500);
        expect(
          (await rawRow('vid-unknown'))!['last_playback_position_ms'],
          4500,
        );
        await fixture.repo.updatePlaybackPosition('vid-unknown', 12000);
        expect((await rawRow('vid-unknown'))!['last_playback_position_ms'], 0);
        await fixture.repo.updatePlaybackPosition('vid-unknown', 4500);
        await fixture.repo.updatePlaybackPosition('vid-unknown', 9000);
        expect((await rawRow('vid-unknown'))!['last_playback_position_ms'], 0);

        // Non-video rejection: playback state never applies to images.
        await saveDirect(
          makeAttachment(id: 'img-1', mediaType: 'image', mime: 'image/jpeg'),
        );
        await expectLater(
          () => fixture.repo.updatePlaybackPosition('img-1', 1000),
          throwsA(isA<ArgumentError>()),
        );
        expect((await rawRow('img-1'))!['last_playback_position_ms'], 0);

        // Bookmarks apply to image and video, never audio/file.
        await fixture.repo.setBookmarked('img-1', bookmarked: true);
        expect((await rawRow('img-1'))!['is_bookmarked'], 1);
        await saveDirect(
          makeAttachment(id: 'aud-1', mediaType: 'audio', mime: 'audio/mp4'),
        );
        await expectLater(
          () => fixture.repo.setBookmarked('aud-1', bookmarked: true),
          throwsA(isA<ArgumentError>()),
        );
        expect((await rawRow('aud-1'))!['is_bookmarked'], 0);
      },
    );

    // --- 228 TC-228-11 ---

    test('parent helpers retain but hide orphan media and preserve collision '
        'siblings', () async {
      // Collision: the same parent id exists in both lanes, each with an
      // attachment carrying local viewer state.
      await fixture.seedDirectParent(
        'msg-shared',
        timestamp: '2026-07-01T10:00:00.000Z',
      );
      await fixture.seedGroupParent(
        'msg-shared',
        timestamp: '2026-07-01T10:00:00.000Z',
      );
      await fixture.repo.saveAttachment(
        makeAttachment(
          id: 'att-d',
          messageId: 'msg-shared',
          downloadStatus: 'done',
          localPath: '/media/att-d.jpg',
        ),
        owner: MediaOwnerLane.direct,
      );
      await fixture.repo.saveAttachment(
        makeAttachment(
          id: 'att-g-sib',
          messageId: 'msg-shared',
          mime: 'video/mp4',
          mediaType: 'video',
          durationMs: 10000,
          downloadStatus: 'done',
          localPath: '/media/att-g-sib.mp4',
        ),
        owner: MediaOwnerLane.group,
      );
      await fixture.repo.setBookmarked('att-g-sib', bookmarked: true);
      await fixture.repo.updatePlaybackPosition('att-g-sib', 3000);

      const directScope = MediaLibraryScope.direct('contact-1');
      const groupScope = MediaLibraryScope.group('group-1');
      expect(
        (await fixture.repo.getMediaLibraryPage(
          scope: directScope,
        )).entries.map((e) => e.attachment.id),
        ['att-d'],
      );
      expect(
        (await fixture.repo.getMediaLibraryPage(
          scope: groupScope,
        )).entries.map((e) => e.attachment.id),
        ['att-g-sib'],
      );

      // Generic DIRECT parent-only deletion: no attachment cascade — the
      // raw row is retained but becomes library-invisible (no live
      // parent). The same-ID group sibling and its viewer state survive.
      await dbDeleteMessage(fixture.db, 'msg-shared');
      expect(await rawRow('att-d'), isNotNull);
      expect(
        (await fixture.repo.getMediaLibraryPage(scope: directScope)).entries,
        isEmpty,
      );
      final sib = await rawRow('att-g-sib');
      expect(sib!['is_bookmarked'], 1);
      expect(sib['last_playback_position_ms'], 3000);
      expect(
        (await fixture.repo.getMediaLibraryPage(
          scope: groupScope,
        )).entries.map((e) => e.attachment.id),
        ['att-g-sib'],
      );

      // Real GROUP tombstone helper: records the durable tombstone and
      // deletes the parent; the attachment row is retained but hidden, and
      // an attempted parent reinsertion cannot resurface it.
      await dbDeleteGroupMessage(fixture.db, 'msg-shared');
      expect(await rawRow('att-g-sib'), isNotNull);
      expect(
        (await fixture.repo.getMediaLibraryPage(scope: groupScope)).entries,
        isEmpty,
      );
      await fixture.seedGroupParent(
        'msg-shared',
        timestamp: '2026-07-01T10:00:00.000Z',
      );
      expect(
        (await fixture.repo.getMediaLibraryPage(scope: groupScope)).entries,
        isEmpty,
      );

      // Both retained orphans still hold their bytes/state (fail-safe
      // retention, invisible through predicates — not a product-visible
      // resurrection).
      expect((await rawRow('att-d'))!['local_path'], '/media/att-d.jpg');
      expect((await rawRow('att-g-sib'))!['last_playback_position_ms'], 3000);
    });

    test(
      'exact direct bookmark loses a parent privacy race with zero write',
      () async {
        await fixture.seedDirectParent('msg-bookmark-race');
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-bookmark-race',
            messageId: 'msg-bookmark-race',
            mediaType: 'image',
            mime: 'image/jpeg',
          ),
          owner: MediaOwnerLane.direct,
        );
        final directState = fixture.repo as DirectMediaLibraryStateRepository;

        expect(
          await directState.setDirectBookmarkedIfOrdinary(
            messageId: 'msg-bookmark-race',
            attachmentId: 'att-bookmark-race',
            bookmarked: true,
          ),
          isTrue,
        );
        expect((await rawRow('att-bookmark-race'))!['is_bookmarked'], 1);

        await fixture.db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': 'protected',
            'private_media_state': 'available',
          },
          where: 'id = ?',
          whereArgs: ['msg-bookmark-race'],
        );
        expect(
          await directState.setDirectBookmarkedIfOrdinary(
            messageId: 'msg-bookmark-race',
            attachmentId: 'att-bookmark-race',
            bookmarked: false,
          ),
          isFalse,
        );
        expect(
          (await rawRow('att-bookmark-race'))!['is_bookmarked'],
          1,
          reason: 'privacy race must not mutate the stale loaded row',
        );
      },
    );

    test(
      'exact direct bookmark rejects identity owner terminal visibility and corrupt races',
      () async {
        final directState = fixture.repo as DirectMediaLibraryStateRepository;

        Future<void> seedDirect(
          String messageId,
          String attachmentId, {
          String? hiddenAt,
          String? deletedAt,
        }) async {
          await fixture.seedDirectParent(
            messageId,
            hiddenAt: hiddenAt,
            deletedAt: deletedAt,
          );
          await fixture.repo.saveAttachment(
            makeAttachment(
              id: attachmentId,
              messageId: messageId,
              mediaType: 'image',
              mime: 'image/jpeg',
            ),
            owner: MediaOwnerLane.direct,
          );
        }

        await seedDirect('msg-exact-a', 'att-exact-a');
        await seedDirect('msg-exact-b', 'att-exact-b');
        await seedDirect('msg-terminal', 'att-terminal');
        await seedDirect(
          'msg-hidden',
          'att-hidden',
          hiddenAt: '2026-07-11T10:00:00.000Z',
        );
        await seedDirect(
          'msg-deleted',
          'att-deleted',
          deletedAt: '2026-07-11T10:00:00.000Z',
        );
        await seedDirect('msg-corrupt', 'att-corrupt');
        await seedDirect('msg-corrupt-lifecycle', 'att-corrupt-lifecycle');
        await seedDirect('msg-unresolved', 'att-unresolved');
        await fixture.db.update(
          'media_attachments',
          {'owner_lane': 'unresolved'},
          where: 'id = ?',
          whereArgs: ['att-unresolved'],
        );

        await fixture.seedGroupParent('msg-group-bookmark');
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-group-bookmark',
            messageId: 'msg-group-bookmark',
            mediaType: 'image',
            mime: 'image/jpeg',
          ),
          owner: MediaOwnerLane.group,
        );
        await fixture.repo.setBookmarked(
          'att-group-bookmark',
          bookmarked: true,
        );

        await fixture.db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': 'view_once',
            'private_media_state': 'expired',
            'private_media_terminal_at_ms': 1_800_000_000_000,
          },
          where: 'id = ?',
          whereArgs: ['msg-terminal'],
        );
        await fixture.db.update(
          'messages',
          {'private_media_policy_version': 1},
          where: 'id = ?',
          whereArgs: ['msg-corrupt'],
        );
        await fixture.db.update(
          'messages',
          {'private_media_expires_at_ms': 1_800_000_000_000},
          where: 'id = ?',
          whereArgs: ['msg-corrupt-lifecycle'],
        );

        final denied = <({String messageId, String attachmentId})>[
          (messageId: 'msg-exact-b', attachmentId: 'att-exact-a'),
          (messageId: 'msg-exact-a', attachmentId: 'missing-attachment'),
          (messageId: 'msg-terminal', attachmentId: 'att-terminal'),
          (messageId: 'msg-hidden', attachmentId: 'att-hidden'),
          (messageId: 'msg-deleted', attachmentId: 'att-deleted'),
          (messageId: 'msg-corrupt', attachmentId: 'att-corrupt'),
          (
            messageId: 'msg-corrupt-lifecycle',
            attachmentId: 'att-corrupt-lifecycle',
          ),
          (messageId: 'msg-unresolved', attachmentId: 'att-unresolved'),
          (messageId: 'msg-group-bookmark', attachmentId: 'att-group-bookmark'),
        ];
        for (final identity in denied) {
          expect(
            await directState.setDirectBookmarkedIfOrdinary(
              messageId: identity.messageId,
              attachmentId: identity.attachmentId,
              bookmarked: true,
            ),
            isFalse,
            reason: identity.toString(),
          );
        }

        for (final attachmentId in const [
          'att-exact-a',
          'att-exact-b',
          'att-terminal',
          'att-hidden',
          'att-deleted',
          'att-corrupt',
          'att-corrupt-lifecycle',
          'att-unresolved',
        ]) {
          expect((await rawRow(attachmentId))!['is_bookmarked'], 0);
        }
        expect((await rawRow('att-group-bookmark'))!['is_bookmarked'], 1);
      },
    );
  });
}
