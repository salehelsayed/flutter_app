import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;

  setUp(() {
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'hydrates incoming post media from pending to local-path-ready during ingest',
    () async {
      final hydratedBlobIds = <String>[];

      final (result, post) = await handleIncomingPost(
        message: _mediaPostMessage(),
        postRepo: posts,
        contactRepo: contacts,
        hydratePostMediaFn: ({required attachment, required postId}) async {
          hydratedBlobIds.add(attachment.blobId);
          return attachment.copyWith(
            localPath: 'post_media/$postId/${attachment.blobId}.jpg',
            downloadStatus: 'done',
          );
        },
      );

      expect(result, HandleIncomingPostResult.postCreated);
      expect(post, isNotNull);
      expect(hydratedBlobIds, ['blob-1']);

      final attachments = await posts.loadPostMediaAttachments('post-1');
      expect(attachments, hasLength(1));
      expect(attachments.single.downloadStatus, 'done');
      expect(attachments.single.localPath, 'post_media/post-1/blob-1.jpg');
    },
  );
}

ContactModel _contact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
  );
}

ChatMessage _mediaPostMessage() {
  const createdAt = '2026-03-15T10:15:30.000Z';
  return ChatMessage(
    from: 'peer-bob',
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': 'post_create',
      'version': '1',
      'event_id': 'evt-post-1',
      'created_at': createdAt,
      'sender_peer_id': 'peer-bob',
      'payload': <String, Object?>{
        'post_id': 'post-1',
        'snapshot': <String, Object?>{
          'post_id': 'post-1',
          'author_peer_id': 'peer-bob',
          'author_username': 'Bob',
          'post_created_at': createdAt,
          'audience': <String, Object?>{
            'kind': 'all_friends',
            'radius_m': null,
            'scope_label': null,
          },
          'text': 'Photo post',
          'media_kind': 'image',
          'media': <Object?>[
            <String, Object?>{
              'media_id': 'media-1',
              'blob_id': 'blob-1',
              'kind': 'image',
              'mime': 'image/jpeg',
              'size_bytes': 248120,
              'width': 1440,
              'height': 1080,
              'duration_ms': null,
              'waveform': null,
              'thumbnail_blob_id': null,
            },
          ],
          'keep_available': false,
          'expires_at': '2026-03-18T10:15:30.000Z',
        },
      },
    }),
    timestamp: createdAt,
    isIncoming: true,
  );
}
