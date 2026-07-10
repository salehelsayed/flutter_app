import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../../../../shared/fixtures/media_repository_real_db_fixture.dart';

/// Key-sensitive sentinel "cipher" for TC-228-04K: decryption succeeds ONLY
/// with the byte-identical original key, so a hydration that silently swapped
/// keys cannot pass.
String encryptSentinel(String plaintext, String key) => 'enc:$key:$plaintext';

String decryptSentinel(String ciphertext, String key) {
  final prefix = 'enc:$key:';
  if (!ciphertext.startsWith(prefix)) {
    throw StateError('sentinel decrypt failed: wrong key');
  }
  return ciphertext.substring(prefix.length);
}

void main() {
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  MediaAttachment makeAttachment({
    required String id,
    required String messageId,
    String mime = 'image/jpeg',
    String mediaType = 'image',
    String downloadStatus = 'pending',
    String createdAt = '2026-07-01T00:00:01.000Z',
    String? encryptionKeyBase64,
    String? encryptionNonce,
    MediaOwnerLane? ownerLane,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: 1000,
      mediaType: mediaType,
      downloadStatus: downloadStatus,
      createdAt: createdAt,
      encryptionKeyBase64: encryptionKeyBase64,
      encryptionNonce: encryptionNonce,
      ownerLane: ownerLane,
    );
  }

  test('direct and group write seams require stable local ownership', () async {
    // Same-parent-ID collision is legal: one direct, one group.
    await fixture.seedDirectParent('msg-shared');
    await fixture.seedGroupParent('msg-shared');

    // Direct and group saves stamp their lane on the raw row.
    await fixture.repo.saveAttachment(
      makeAttachment(id: 'att-direct', messageId: 'msg-shared'),
      owner: MediaOwnerLane.direct,
    );
    await fixture.repo.saveAttachment(
      makeAttachment(id: 'att-group', messageId: 'msg-shared'),
      owner: MediaOwnerLane.group,
    );
    expect(
      (await fixture.rawAttachmentRow('att-direct'))!['owner_lane'],
      'direct',
    );
    expect(
      (await fixture.rawAttachmentRow('att-group'))!['owner_lane'],
      'group',
    );

    // Owner-scoped reads do not cross lanes despite the equal parent ID.
    final directRead = await fixture.repo.getAttachmentsForMessage(
      'msg-shared',
      owner: MediaOwnerLane.direct,
    );
    expect(directRead.map((a) => a.id), ['att-direct']);
    expect(directRead.single.ownerLane, MediaOwnerLane.direct);
    final groupRead = await fixture.repo.getAttachmentsForMessage(
      'msg-shared',
      owner: MediaOwnerLane.group,
    );
    expect(groupRead.map((a) => a.id), ['att-group']);
    expect(groupRead.single.ownerLane, MediaOwnerLane.group);

    // A same-ID save cannot switch owner lane.
    await expectLater(
      () => fixture.repo.saveAttachment(
        makeAttachment(id: 'att-direct', messageId: 'msg-shared'),
        owner: MediaOwnerLane.group,
      ),
      throwsA(isA<MediaAttachmentOwnerViolation>()),
    );
    expect(
      (await fixture.rawAttachmentRow('att-direct'))!['owner_lane'],
      'direct',
    );

    // A same-ID save cannot re-parent to another message either.
    await fixture.seedDirectParent('msg-other');
    await expectLater(
      () => fixture.repo.saveAttachment(
        makeAttachment(id: 'att-direct', messageId: 'msg-other'),
        owner: MediaOwnerLane.direct,
      ),
      throwsA(isA<MediaAttachmentOwnerViolation>()),
    );
    expect(
      (await fixture.rawAttachmentRow('att-direct'))!['message_id'],
      'msg-shared',
    );

    // A model already stamped with a DIFFERENT lane than the caller's typed
    // owner is a caller bug and fails closed.
    await expectLater(
      () => fixture.repo.saveAttachment(
        makeAttachment(
          id: 'att-conflicted',
          messageId: 'msg-shared',
          ownerLane: MediaOwnerLane.group,
        ),
        owner: MediaOwnerLane.direct,
      ),
      throwsA(isA<MediaAttachmentOwnerViolation>()),
    );
    expect(await fixture.rawAttachmentRow('att-conflicted'), isNull);

    // Legacy unresolved rows are invisible to owner-scoped reads and cannot
    // be adopted by an owner-scoped save.
    await fixture.db.insert('media_attachments', {
      'id': 'att-legacy',
      'message_id': 'msg-shared',
      'mime': 'image/jpeg',
      'size': 1,
      'media_type': 'image',
      'download_status': 'done',
      'created_at': '2026-07-01T00:00:00.500Z',
      'owner_lane': 'unresolved',
    });
    final directAfterLegacy = await fixture.repo.getAttachmentsForMessage(
      'msg-shared',
      owner: MediaOwnerLane.direct,
    );
    expect(directAfterLegacy.map((a) => a.id), ['att-direct']);
    await expectLater(
      () => fixture.repo.saveAttachment(
        makeAttachment(id: 'att-legacy', messageId: 'msg-shared'),
        owner: MediaOwnerLane.direct,
      ),
      throwsA(isA<MediaAttachmentOwnerViolation>()),
    );
    expect(
      (await fixture.rawAttachmentRow('att-legacy'))!['owner_lane'],
      'unresolved',
    );

    // Owner-scoped delete removes only its lane; the collision sibling and
    // the unresolved legacy row survive.
    final deleted = await fixture.repo.deleteAttachmentsForMessage(
      'msg-shared',
      owner: MediaOwnerLane.direct,
    );
    expect(deleted, 1);
    expect(await fixture.rawAttachmentRow('att-direct'), isNull);
    expect(await fixture.rawAttachmentRow('att-group'), isNotNull);
    expect(await fixture.rawAttachmentRow('att-legacy'), isNotNull);
  });

  test(
    'rejected cross owner save preserves original secure key and '
    'decryptability',
    () async {
      await fixture.seedDirectParent('msg-shared');
      await fixture.seedGroupParent('msg-shared');
      await fixture.seedDirectParent('msg-other');

      const keyA = 'key-A-original-0123456789';
      const keyB = 'key-B-attacker-9876543210';
      final ciphertext = encryptSentinel('sentinel-04k', keyA);

      // Original save: key A lands in the secure store under the
      // attachment-ID-derived name; the row holds a secure reference.
      await fixture.repo.saveAttachment(
        makeAttachment(
          id: 'att-k',
          messageId: 'msg-shared',
          encryptionKeyBase64: keyA,
          encryptionNonce: 'nonce-a',
        ),
        owner: MediaOwnerLane.direct,
      );
      final storeName = mediaAttachmentEncryptionKeyStoreName('att-k');
      expect(await fixture.secureKeyStore.read(storeName), keyA);
      final rawAfterSave = await fixture.rawAttachmentRow('att-k');
      expect(
        isSecureStoreReference(rawAfterSave!['encryption_key_base64'] as String?),
        isTrue,
      );
      final writesAfterSave = fixture.secureKeyStore.writtenKeys
          .where((k) => k == storeName)
          .length;
      expect(writesAfterSave, 1);

      // Rejected cross-owner save with key B: validation precedes ANY
      // secure-store side effect.
      await expectLater(
        () => fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-k',
            messageId: 'msg-shared',
            encryptionKeyBase64: keyB,
            encryptionNonce: 'nonce-b',
          ),
          owner: MediaOwnerLane.group,
        ),
        throwsA(isA<MediaAttachmentOwnerViolation>()),
      );
      // Rejected cross-parent save with key B, same lane.
      await expectLater(
        () => fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-k',
            messageId: 'msg-other',
            encryptionKeyBase64: keyB,
            encryptionNonce: 'nonce-b',
          ),
          owner: MediaOwnerLane.direct,
        ),
        throwsA(isA<MediaAttachmentOwnerViolation>()),
      );

      // No second write of the attachment key name happened; the stored
      // value is still key A; no key-B orphan write exists anywhere.
      expect(
        fixture.secureKeyStore.writtenKeys
            .where((k) => k == storeName)
            .length,
        writesAfterSave,
      );
      expect(await fixture.secureKeyStore.read(storeName), keyA);

      // The raw row is unchanged and the repository still hydrates and
      // decrypts the ORIGINAL sentinel with key A.
      final rawAfterReject = await fixture.rawAttachmentRow('att-k');
      expect(rawAfterReject!['owner_lane'], 'direct');
      expect(rawAfterReject['message_id'], 'msg-shared');
      expect(
        rawAfterReject['encryption_key_base64'],
        rawAfterSave['encryption_key_base64'],
      );
      final hydrated = await fixture.repo.getAttachmentById('att-k');
      expect(hydrated!.encryptionKeyBase64, keyA);
      expect(decryptSentinel(ciphertext, hydrated.encryptionKeyBase64!),
          'sentinel-04k');
    },
  );
}
