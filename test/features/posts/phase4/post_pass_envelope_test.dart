import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';

import '../../../core/bridge/fake_bridge.dart';

void main() {
  test('parses a renderable original snapshot from post_pass', () {
    final envelope = PostPassEnvelope.fromJson(jsonEncode(_postPassJson()));

    expect(envelope, isNotNull);
    expect(envelope!.postId, 'post-1');
    expect(envelope.passId, 'pass-1');
    expect(envelope.passerPeerId, 'peer-james');
    expect(envelope.originalSnapshot.authorPeerId, 'peer-sarah');
    expect(
      envelope.originalSnapshot.audience.kind,
      PostAudienceKind.peopleNearby,
    );
    expect(envelope.originalSnapshot.audience.radiusM, 2000);
    expect(
      envelope.originalSnapshot.originalAuthorAvatarBase64,
      base64Encode(_avatarBytes),
    );
    expect(envelope.toPostModel().visibleAt, '2026-03-15T11:15:00.000Z');
  });

  test('parses legacy post_pass snapshots when avatar snapshot is omitted', () {
    final envelope = PostPassEnvelope.fromJson(
      jsonEncode(_postPassJson(includeAvatar: false)),
    );

    expect(envelope, isNotNull);
    expect(envelope!.originalSnapshot.originalAuthorAvatarBase64, isNull);
  });

  test('rejects post_pass when the original snapshot is not renderable', () {
    final json = _postPassJson();
    final payload = json['payload'] as Map<String, Object?>;
    payload.remove('original_snapshot');

    final envelope = PostPassEnvelope.fromJson(jsonEncode(json));

    expect(envelope, isNull);
  });

  test(
    'rejects post_pass when the original snapshot audience is pick_people',
    () {
      final json = _postPassJson();
      final payload = json['payload'] as Map<String, Object?>;
      final snapshot = payload['original_snapshot'] as Map<String, Object?>;
      snapshot['audience'] = <String, Object?>{
        'kind': 'pick_people',
        'scope_label': 'Shared with you',
      };

      final envelope = PostPassEnvelope.fromJson(jsonEncode(json));

      expect(envelope, isNull);
    },
  );

  test('buildJson includes original_author_avatar_base64 when present', () {
    const pass = PostPassModel(
      passId: 'pass-1',
      eventId: 'evt-pass-1',
      postId: 'post-1',
      senderPeerId: 'peer-james',
      passerPeerId: 'peer-james',
      passerUsername: 'James',
      passedAt: '2026-03-15T11:15:00.000Z',
      createdAt: '2026-03-15T11:15:00.000Z',
    );
    final json =
        jsonDecode(
              PostPassEnvelope.buildJson(
                pass: pass,
                participantPeerIds: const <String>['peer-james', 'peer-sarah'],
                activeHeartPeerIds: const <String>['peer-dana'],
                repostTotalBaseline: 3,
                post: PostModel(
                  id: 'post-1',
                  eventId: 'evt-post-1',
                  senderPeerId: 'peer-sarah',
                  authorPeerId: 'peer-sarah',
                  authorUsername: 'Sarah',
                  text: 'Lost dog near Neckar bridge.',
                  audience: PostAudience.peopleNearby(radiusM: 2000),
                  createdAt: '2026-03-15T10:15:30.000Z',
                  visibleAt: '2026-03-15T10:15:30.000Z',
                  expiresAt: '2026-03-18T10:15:30.000Z',
                  mediaKind: 'image',
                  media: const <PostMediaAttachmentModel>[
                    PostMediaAttachmentModel(
                      mediaId: 'media-1',
                      postId: 'post-1',
                      blobId: 'blob-original-1',
                      kind: 'image',
                      mime: 'image/jpeg',
                      sizeBytes: 248120,
                      width: 1440,
                      height: 1080,
                      localPath: 'post_media/post-1/blob-original-1.jpg',
                      downloadStatus: 'done',
                      createdAt: '2026-03-15T10:20:00.000Z',
                    ),
                  ],
                  originalAuthorAvatarBytes: Uint8List.fromList(_avatarBytes),
                ),
              ),
            )
            as Map<String, dynamic>;
    final payload = json['payload'] as Map<String, dynamic>;
    final snapshot = payload['original_snapshot'] as Map<String, dynamic>;
    final media = (snapshot['media'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(
      snapshot['original_author_avatar_base64'],
      base64Encode(_avatarBytes),
    );
    expect(json['version'], '1');
    expect(json.containsKey('ciphertext'), isFalse);
    expect(json.containsKey('kem'), isFalse);
    expect(payload['participant_peer_ids'], <String>[
      'peer-james',
      'peer-sarah',
    ]);
    expect(payload['heart_baseline'], <String, Object?>{
      'active_peer_ids': const <String>['peer-dana'],
    });
    expect(payload['repost_total_baseline'], 3);
    expect(media, hasLength(1));
    expect(media.single['blob_id'], 'blob-original-1');
  });

  test('buildJson omits original_author_avatar_base64 when avatar is null', () {
    const pass = PostPassModel(
      passId: 'pass-1',
      eventId: 'evt-pass-1',
      postId: 'post-1',
      senderPeerId: 'peer-james',
      passerPeerId: 'peer-james',
      passerUsername: 'James',
      passedAt: '2026-03-15T11:15:00.000Z',
      createdAt: '2026-03-15T11:15:00.000Z',
    );
    final json =
        jsonDecode(
              PostPassEnvelope.buildJson(
                pass: pass,
                participantPeerIds: const <String>['peer-james', 'peer-sarah'],
                activeHeartPeerIds: const <String>['peer-dana'],
                repostTotalBaseline: 3,
                post: PostModel(
                  id: 'post-1',
                  eventId: 'evt-post-1',
                  senderPeerId: 'peer-sarah',
                  authorPeerId: 'peer-sarah',
                  authorUsername: 'Sarah',
                  text: 'Lost dog near Neckar bridge.',
                  audience: PostAudience.peopleNearby(radiusM: 2000),
                  createdAt: '2026-03-15T10:15:30.000Z',
                  visibleAt: '2026-03-15T10:15:30.000Z',
                  expiresAt: '2026-03-18T10:15:30.000Z',
                ),
              ),
            )
            as Map<String, dynamic>;
    final payload = json['payload'] as Map<String, dynamic>;
    final snapshot = payload['original_snapshot'] as Map<String, dynamic>;

    expect(snapshot.containsKey('original_author_avatar_base64'), isFalse);
  });

  test(
    'decrypts a v2 post_pass envelope back into the repost snapshot',
    () async {
      const pass = PostPassModel(
        passId: 'pass-1',
        eventId: 'evt-pass-1',
        postId: 'post-1',
        senderPeerId: 'peer-james',
        passerPeerId: 'peer-james',
        passerUsername: 'James',
        passedAt: '2026-03-15T11:15:00.000Z',
        createdAt: '2026-03-15T11:15:00.000Z',
      );
      final envelope = PostPassEnvelope.fromPass(
        pass: pass,
        post: PostModel(
          id: 'post-1',
          eventId: 'evt-post-1',
          senderPeerId: 'peer-sarah',
          authorPeerId: 'peer-sarah',
          authorUsername: 'Sarah',
          text: 'Lost dog near Neckar bridge.',
          audience: PostAudience.peopleNearby(radiusM: 2000),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
        ),
        participantPeerIds: const <String>['peer-james', 'peer-sarah'],
        activeHeartPeerIds: const <String>['peer-dana'],
        repostTotalBaseline: 2,
        originalAuthorAvatarBase64: base64Encode(_avatarBytes),
      );
      final encryptedEnvelope = PostPassEnvelope.buildEncryptedEnvelope(
        eventId: envelope.eventId,
        createdAt: envelope.createdAt,
        senderPeerId: envelope.senderPeerId,
        kem: 'fake-kem',
        ciphertext: envelope.toInnerJson(),
        nonce: 'fake-nonce',
      );

      final decrypted = await PostPassEnvelope.fromEncryptedJson(
        jsonString: encryptedEnvelope,
        bridge: PassthroughCryptoBridge(),
        ownMlKemSecretKey: 'own-secret-key',
      );

      expect(decrypted, isNotNull);
      expect(decrypted!.participantPeerIds, <String>[
        'peer-james',
        'peer-sarah',
      ]);
      expect(decrypted.activeHeartPeerIds, <String>['peer-dana']);
      expect(decrypted.repostTotalBaseline, 2);
      expect(decrypted.originalSnapshot.authorPeerId, 'peer-sarah');
      expect(
        decrypted.originalSnapshot.originalAuthorAvatarBase64,
        base64Encode(_avatarBytes),
      );
    },
  );

  test('toPostModel decodes avatar base64 into originalAuthorAvatarBytes', () {
    final envelope = PostPassEnvelope.fromJson(jsonEncode(_postPassJson()));

    final post = envelope!.toPostModel();

    expect(post.originalAuthorAvatarBytes, isNotNull);
    expect(post.originalAuthorAvatarBytes!, orderedEquals(_avatarBytes));
  });

  test(
    'toPostModel leaves originalAuthorAvatarBytes null when avatar is absent',
    () {
      final envelope = PostPassEnvelope.fromJson(
        jsonEncode(_postPassJson(includeAvatar: false)),
      );

      final post = envelope!.toPostModel();

      expect(post.originalAuthorAvatarBytes, isNull);
    },
  );
}

const List<int> _avatarBytes = <int>[1, 2, 3, 4, 5, 6];

Map<String, Object?> _postPassJson({bool includeAvatar = true}) {
  return <String, Object?>{
    'type': 'post_pass',
    'version': '1',
    'event_id': 'evt-pass-1',
    'created_at': '2026-03-15T11:15:00.000Z',
    'sender_peer_id': 'peer-james',
    'payload': <String, Object?>{
      'pass_id': 'pass-1',
      'post_id': 'post-1',
      'passed_at': '2026-03-15T11:15:00.000Z',
      'passer_peer_id': 'peer-james',
      'passer_username': 'James',
      'original_snapshot': <String, Object?>{
        'post_id': 'post-1',
        'author_peer_id': 'peer-sarah',
        'author_username': 'Sarah',
        'post_created_at': '2026-03-15T10:15:30.000Z',
        'audience': <String, Object?>{
          'kind': 'people_nearby',
          'radius_m': 2000,
          'scope_label': 'Shared nearby',
        },
        'text': 'Lost dog near Neckar bridge.',
        'media_kind': 'none',
        'media': const <Object?>[],
        'keep_available': false,
        'expires_at': '2026-03-18T10:15:30.000Z',
        if (includeAvatar)
          'original_author_avatar_base64': base64Encode(_avatarBytes),
      },
    },
  };
}
