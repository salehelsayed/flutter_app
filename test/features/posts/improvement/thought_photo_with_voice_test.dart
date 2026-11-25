import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';

import '../../../core/bridge/fake_bridge.dart';

void main() {
  const createdAt = '2026-11-25T10:00:00.000Z';

  PostMediaAttachmentModel item(String id, String kind) =>
      PostMediaAttachmentModel(
        mediaId: id,
        postId: 'post-1',
        blobId: 'blob-$id',
        kind: kind,
        mime: kind == 'voice' ? 'audio/aac' : 'image/jpeg',
        sizeBytes: 2048,
        createdAt: createdAt,
      );

  PostMediaCryptoEntry key(String id) => PostMediaCryptoEntry(
    keyBase64: 'key-$id',
    nonce: 'nonce-$id',
    blobId: 'blob-$id',
    scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    contentHash: 'f' * 64,
  );

  group('BL95 a thought carries photos and one voice note', () {
    test('the kind of photos plus a voice note is image_voice', () {
      expect(
        PostMediaAttachmentModel.deriveMediaKind([
          item('p1', 'image'),
          item('v1', 'voice'),
        ]),
        'image_voice',
      );
      expect(
        PostMediaAttachmentModel.deriveMediaKind([
          item('v1', 'voice'),
          item('p1', 'image'),
          item('p2', 'image'),
        ]),
        'image_voice',
      );
    });

    test('image_voice is valid only for photos plus exactly one voice', () {
      bool valid(List<PostMediaAttachmentModel> media) =>
          PostMediaAttachmentModel.isValidSnapshotMedia(
            mediaKind: 'image_voice',
            media: media,
          );
      expect(valid([item('p1', 'image'), item('v1', 'voice')]), isTrue);
      expect(
        valid([item('p1', 'image'), item('p2', 'image'), item('v1', 'voice')]),
        isTrue,
      );
      expect(valid([item('v1', 'voice')]), isFalse);
      expect(valid([item('p1', 'image'), item('p2', 'image')]), isFalse);
      expect(
        valid([item('p1', 'image'), item('v1', 'voice'), item('v2', 'voice')]),
        isFalse,
      );
      expect(valid([item('m1', 'video'), item('v1', 'voice')]), isFalse);
    });

    test('a receiver keeps both the photo and the voice note', () async {
      final media = [item('p1', 'image'), item('v1', 'voice')];
      final inner =
          PostCreateEnvelope(
            eventId: 'evt-1',
            createdAt: createdAt,
            senderPeerId: 'peer-alice',
            postId: 'post-1',
            authorPeerId: 'peer-alice',
            authorUsername: 'Alice',
            text: 'listen',
            mediaKind: 'image_voice',
            media: media,
            audience: PostAudience.allFriends(),
            expiresAt: '2026-11-28T10:00:00.000Z',
            keepAvailable: false,
            mediaKeys: {'p1': key('p1'), 'v1': key('v1')},
          ).toInnerJson(recipientPeerIds: const ['peer-bob']);
      final wire = PostCreateEnvelope.buildEncryptedEnvelope(
        eventId: 'evt-1',
        createdAt: createdAt,
        senderPeerId: 'peer-alice',
        postId: 'post-1',
        kem: 'fake-kem',
        ciphertext: inner,
        nonce: 'fake-nonce',
      );

      final parsed = await PostCreateEnvelope.fromEncryptedJson(
        jsonString: wire,
        bridge: PassthroughCryptoBridge(),
        ownMlKemSecretKey: 'own-sk',
      ).timeout(const Duration(seconds: 5));

      expect(parsed, isNotNull);
      expect(parsed!.mediaKind, 'image_voice');
      expect(parsed.media.map((m) => m.kind).toList(), ['image', 'voice']);
    });
  });
}
