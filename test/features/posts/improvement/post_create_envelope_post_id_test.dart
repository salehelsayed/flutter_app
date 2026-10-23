import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';

import '../../../core/bridge/fake_bridge.dart';

void main() {
  const createdAt = '2026-06-12T10:00:00.000Z';

  String innerPayload() {
    return PostCreateEnvelope(
      eventId: 'evt-1',
      createdAt: createdAt,
      senderPeerId: 'peer-alice',
      postId: 'post-1',
      authorPeerId: 'peer-alice',
      authorUsername: 'Alice',
      text: 'hello',
      mediaKind: 'none',
      media: <PostMediaAttachmentModel>[],
      audience: PostAudience.allFriends(),
      expiresAt: '2026-06-15T10:00:00.000Z',
      keepAvailable: false,
    ).toInnerJson(recipientPeerIds: const <String>['peer-bob']);
  }

  test('buildEncryptedEnvelope puts post_id beside the encrypted block', () {
    final wire = PostCreateEnvelope.buildEncryptedEnvelope(
      eventId: 'evt-1',
      createdAt: createdAt,
      senderPeerId: 'peer-alice',
      postId: 'post-1',
      kem: 'fake-kem',
      ciphertext: 'fake-ciphertext',
      nonce: 'fake-nonce',
    );

    expect(jsonDecode(wire), <String, Object>{
      'type': 'post_create',
      'version': '2',
      'event_id': 'evt-1',
      'created_at': createdAt,
      'sender_peer_id': 'peer-alice',
      'post_id': 'post-1',
      'encrypted': <String, Object>{
        'kem': 'fake-kem',
        'ciphertext': 'fake-ciphertext',
        'nonce': 'fake-nonce',
      },
    });
  });

  test('an envelope with post_id still decrypts to the same post', () async {
    final wire = PostCreateEnvelope.buildEncryptedEnvelope(
      eventId: 'evt-1',
      createdAt: createdAt,
      senderPeerId: 'peer-alice',
      postId: 'post-1',
      kem: 'fake-kem',
      ciphertext: innerPayload(),
      nonce: 'fake-nonce',
    );

    final parsed = await PostCreateEnvelope.fromEncryptedJson(
      jsonString: wire,
      bridge: PassthroughCryptoBridge(),
      ownMlKemSecretKey: 'own-sk',
    );

    expect(parsed?.postId, 'post-1');
    expect(parsed?.eventId, 'evt-1');
  });

  test('an envelope without post_id (older sender) still parses', () async {
    final legacyWire = jsonEncode(<String, Object>{
      'type': 'post_create',
      'version': '2',
      'event_id': 'evt-1',
      'created_at': createdAt,
      'sender_peer_id': 'peer-alice',
      'encrypted': <String, Object>{
        'kem': 'fake-kem',
        'ciphertext': innerPayload(),
        'nonce': 'fake-nonce',
      },
    });

    expect(PostCreateEnvelope.parseEncryptedEnvelope(legacyWire), isNotNull);
    final parsed = await PostCreateEnvelope.fromEncryptedJson(
      jsonString: legacyWire,
      bridge: PassthroughCryptoBridge(),
      ownMlKemSecretKey: 'own-sk',
    );
    expect(parsed?.postId, 'post-1');
  });
}
