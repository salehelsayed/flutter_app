import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

const _createdAt = '2026-06-12T10:00:00.000Z';

void main() {
  late FakeP2PNetwork network;
  late P2PService p2pService;
  late InMemoryPostRepository posts;
  late FakeBridge bridge;

  setUp(() {
    network = FakeP2PNetwork();
    p2pService = FakeP2PService(peerId: 'peer-self', network: network);
    posts = InMemoryPostRepository();
    bridge = PassthroughCryptoBridge();
  });

  tearDown(() {
    posts.dispose();
    (p2pService as FakeP2PService).dispose();
  });

  ContactModel contact(String peerId, {bool withMlKemKey = true}) {
    return ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/dns4/example.invalid/tcp/443',
      username: peerId,
      signature: 'sig-$peerId',
      scannedAt: _createdAt,
      mlKemPublicKey: withMlKemKey ? 'mlkem-$peerId' : null,
    );
  }

  PostMediaAttachmentModel keyedAttachment() {
    return PostMediaAttachmentModel(
      mediaId: 'media-1',
      postId: 'post-1',
      blobId: 'blob-enc-1',
      kind: 'image',
      mime: 'image/jpeg',
      sizeBytes: 2048,
      localPath: 'post_media/post-1/blob-enc-1.jpg',
      downloadStatus: 'done',
      createdAt: _createdAt,
      encryptionKeyBase64: 'row-key-b64',
      encryptionNonce: 'row-nonce-b64',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      contentHash: 'f' * 64,
      isEncrypted: true,
    );
  }

  PostMediaAttachmentModel keylessLegacyAttachment() {
    return const PostMediaAttachmentModel(
      mediaId: 'media-1',
      postId: 'post-1',
      blobId: 'blob-plain-1',
      kind: 'image',
      mime: 'image/jpeg',
      sizeBytes: 2048,
      localPath: 'post_media/post-1/blob-plain-1.jpg',
      downloadStatus: 'done',
      createdAt: _createdAt,
    );
  }

  PostModel mediaPost(List<PostMediaAttachmentModel> media) {
    return PostModel(
      id: 'post-1',
      eventId: 'evt-post-1',
      senderPeerId: 'peer-self',
      authorPeerId: 'peer-self',
      authorUsername: 'Alice',
      text: 'media post',
      audience: PostAudience.allFriends(),
      createdAt: _createdAt,
      visibleAt: _createdAt,
      expiresAt: '2026-06-15T10:00:00.000Z',
      isIncoming: false,
      deliveryStatus: 'sending',
      mediaKind: media.isEmpty ? 'none' : 'image',
      media: media,
    );
  }

  Future<void> seed(PostModel post) async {
    await posts.savePost(post);
    for (final attachment in post.media) {
      await posts.savePostMediaAttachment(attachment);
    }
  }

  Future<(SendPostResult, PostModel)> deliver(
    PostModel post,
    List<ContactModel> recipients,
  ) {
    return PostDeliveryRunner(
      p2pService: p2pService,
      postRepo: posts,
      bridge: bridge,
    ).execute(
      CreatedLocalPost(
        post: post,
        resolvedRecipients: recipients
            .map((recipient) => CreatedLocalPostRecipient(contact: recipient))
            .toList(growable: false),
      ),
    );
  }

  Map<String, dynamic> inboxEnvelope(String peerId) {
    final message =
        network.retrieveInbox(peerId).single['message'] as String;
    return jsonDecode(message) as Map<String, dynamic>;
  }

  test(
    'delivered v2 inner payload carries media_keys keyed by mediaId with blob_id, scheme, and content_hash',
    () async {
      final post = mediaPost(<PostMediaAttachmentModel>[keyedAttachment()]);
      await seed(post);

      final (result, _) = await deliver(post, <ContactModel>[
        contact('peer-bob'),
      ]);

      expect(result, SendPostResult.success);
      final envelope = inboxEnvelope('peer-bob');
      expect(envelope['version'], '2');
      final innerPayload =
          jsonDecode(
                (envelope['encrypted'] as Map<String, dynamic>)['ciphertext']
                    as String,
              )
              as Map<String, dynamic>;
      final mediaKeys = innerPayload['media_keys'] as Map<String, dynamic>?;
      expect(mediaKeys, isNotNull);
      final entry = mediaKeys!['media-1'] as Map<String, dynamic>;
      expect(entry['key_base64'], 'row-key-b64');
      expect(entry['nonce'], 'row-nonce-b64');
      expect(entry['blob_id'], 'blob-enc-1');
      expect(entry['scheme'], kMediaAttachmentEncryptionSchemeBlobAesGcmV1);
      expect(entry['content_hash'], 'f' * 64);

      // The renderable snapshot stays crypto-free.
      final snapshotMedia =
          ((innerPayload['snapshot'] as Map<String, dynamic>)['media']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(
        snapshotMedia.single.keys,
        isNot(contains('encryption_key_base64')),
      );
    },
  );

  test(
    'recipient without an ML-KEM key: media post fails closed per recipient — no envelope sent, delivery row failed with post_recipient_missing_mlkem_key',
    () async {
      final post = mediaPost(<PostMediaAttachmentModel>[keyedAttachment()]);
      await seed(post);

      final (result, _) = await deliver(post, <ContactModel>[
        contact('peer-bob', withMlKemKey: false),
      ]);

      expect(result, SendPostResult.sendFailed);
      expect(network.retrieveInbox('peer-bob'), isEmpty,
          reason: 'no v1 plaintext envelope may ship a keyed media post');

      final delivery = (await posts.getRecipientDeliveries('post-1')).single;
      expect(delivery.deliveryStatus, 'failed');
      expect(
        delivery.lastError,
        contains('post_recipient_missing_mlkem_key'),
      );
    },
  );

  test(
    'callEncryptMessage failure fails closed for media posts (no plaintext downgrade)',
    () async {
      // Plain FakeBridge honors pre-canned responses for message.encrypt
      // (PassthroughCryptoBridge would short-circuit it).
      bridge = FakeBridge(
        initialResponses: <String, Map<String, dynamic>>{
          'message.encrypt': <String, dynamic>{
            'ok': false,
            'errorCode': 'ENCRYPT_UNAVAILABLE',
          },
        },
      );
      final post = mediaPost(<PostMediaAttachmentModel>[keyedAttachment()]);
      await seed(post);

      final (result, _) = await deliver(post, <ContactModel>[
        contact('peer-bob'),
      ]);

      expect(result, SendPostResult.sendFailed);
      expect(network.retrieveInbox('peer-bob'), isEmpty);

      final delivery = (await posts.getRecipientDeliveries('post-1')).single;
      expect(delivery.deliveryStatus, 'failed');
      expect(delivery.lastError, contains('post_media_encrypt_failed'));
    },
  );

  test('text-only post to a keyless recipient still delivers v1', () async {
    final post = mediaPost(const <PostMediaAttachmentModel>[]);
    await seed(post);

    final (result, _) = await deliver(post, <ContactModel>[
      contact('peer-bob', withMlKemKey: false),
    ]);

    expect(result, SendPostResult.success);
    final envelope = inboxEnvelope('peer-bob');
    expect(envelope['version'], '1');
    expect(envelope['type'], 'post_create');
  });

  test(
    'media post with keyless legacy attachment rows (pre-flip plaintext upload) still delivers v1 plaintext',
    () async {
      final post = mediaPost(<PostMediaAttachmentModel>[
        keylessLegacyAttachment(),
      ]);
      await seed(post);

      final (result, _) = await deliver(post, <ContactModel>[
        contact('peer-bob', withMlKemKey: false),
      ]);

      // G3 scoping: empty mediaKeys leaves the legacy fallback live — the
      // blob is already plaintext on the relay (TTL-bounded residual).
      expect(result, SendPostResult.success);
      final envelope = inboxEnvelope('peer-bob');
      expect(envelope['version'], '1');
      expect(jsonEncode(envelope), isNot(contains('media_keys')));
    },
  );

  test(
    'inbox fallback stores the same encrypted envelope (media_keys reach offline recipients)',
    () async {
      final post = mediaPost(<PostMediaAttachmentModel>[keyedAttachment()]);
      await seed(post);

      final (result, _) = await deliver(post, <ContactModel>[
        contact('peer-bob'),
      ]);

      expect(result, SendPostResult.success);
      final delivery = (await posts.getRecipientDeliveries('post-1')).single;
      expect(delivery.deliveryStatus, 'inbox');

      final envelope = inboxEnvelope('peer-bob');
      expect(envelope['version'], '2');
      final innerPayload =
          jsonDecode(
                (envelope['encrypted'] as Map<String, dynamic>)['ciphertext']
                    as String,
              )
              as Map<String, dynamic>;
      expect(innerPayload['media_keys'], isNotNull);
    },
  );
}
