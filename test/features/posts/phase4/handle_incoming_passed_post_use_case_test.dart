import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_passed_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;

  setUp(() {
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'rejects post_pass when the transport sender mismatches the payload sender',
    () async {
      contacts.addTestContact(_contact('peer-james', 'James'));

      final (result, post) = await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(),
          transportSender: 'peer-mallory',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPassedPostResult.notPostPass);
      expect(post, isNull);
      expect((await posts.loadFeed()), isEmpty);
    },
  );

  test(
    'rejects post_pass from an unknown passing friend before persistence',
    () async {
      final (result, post) = await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(),
          transportSender: 'peer-james',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPassedPostResult.unknownSender);
      expect(post, isNull);
      expect((await posts.loadFeed()), isEmpty);
    },
  );

  test(
    'stores a passed-along post from the embedded original snapshot',
    () async {
      contacts.addTestContact(_contact('peer-james', 'James'));

      final (result, post) = await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(),
          transportSender: 'peer-james',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPassedPostResult.passAccepted);
      expect(post, isNotNull);
      expect(post!.id, 'post-1');
      expect(post.senderPeerId, 'peer-james');
      expect(post.authorPeerId, 'peer-sarah');
      expect(post.authorUsername, 'Sarah');
      expect(post.visibleAt, '2026-03-15T11:15:00.000Z');
      expect(post.audience.radiusM, 2000);
    },
  );

  test(
    'persists renderable snapshot media attachments for passed-along posts',
    () async {
      contacts.addTestContact(_contact('peer-james', 'James'));

      final (result, post) = await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(
            mediaKind: 'image',
            media: <Object?>[
              <String, Object?>{
                'media_id': 'media-1',
                'blob_id': 'blob-1',
                'kind': 'image',
                'mime': 'image/jpeg',
                'size_bytes': 248120,
                'width': 1440,
                'height': 1080,
              },
            ],
          ),
          transportSender: 'peer-james',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPassedPostResult.passAccepted);
      expect(post, isNotNull);
      final attachments = await posts.loadPostMediaAttachments('post-1');
      expect(attachments, hasLength(1));
      expect(attachments.single.blobId, 'blob-1');
      expect(attachments.single.downloadStatus, 'pending');
    },
  );

  test(
    'hydrates passed-along media attachments when a media hydrator is provided',
    () async {
      contacts.addTestContact(_contact('peer-james', 'James'));
      final hydratedBlobIds = <String>[];

      final (result, post) = await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(
            mediaKind: 'image',
            media: <Object?>[
              <String, Object?>{
                'media_id': 'media-1',
                'blob_id': 'blob-1',
                'kind': 'image',
                'mime': 'image/jpeg',
                'size_bytes': 248120,
                'width': 1440,
                'height': 1080,
              },
            ],
          ),
          transportSender: 'peer-james',
        ),
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

      expect(result, HandleIncomingPassedPostResult.passAccepted);
      expect(post, isNotNull);
      expect(hydratedBlobIds, ['blob-1']);
      expect(post!.media, hasLength(1));
      expect(post.media.single.localPath, 'post_media/post-1/blob-1.jpg');
      expect(post.media.single.downloadStatus, 'done');

      final attachments = await posts.loadPostMediaAttachments('post-1');
      expect(attachments, hasLength(1));
      expect(attachments.single.downloadStatus, 'done');
      expect(attachments.single.localPath, 'post_media/post-1/blob-1.jpg');
    },
  );

  test(
    'resurfaces an existing post again when a later distinct repost arrives',
    () async {
      contacts.addTestContact(_contact('peer-james', 'James'));
      contacts.addTestContact(_contact('peer-maria', 'Maria'));
      await posts.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-direct-1',
          senderPeerId: 'peer-sarah',
          authorPeerId: 'peer-sarah',
          authorUsername: 'Sarah',
          text: 'Lost dog near Neckar bridge.',
          audience: PostAudience.peopleNearby(radiusM: 2000),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
        ),
      );

      final first = await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(),
          transportSender: 'peer-james',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      final secondJson = _postPassJson(
        senderPeerId: 'peer-maria',
        passerPeerId: 'peer-maria',
        passerUsername: 'Maria',
        passId: 'pass-2',
        eventId: 'evt-pass-2',
        passedAt: '2026-03-15T11:25:00.000Z',
      );
      final second = await handleIncomingPassedPost(
        message: _messageFromJson(secondJson, transportSender: 'peer-maria'),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(first.$1, HandleIncomingPassedPostResult.passAccepted);
      expect(second.$1, HandleIncomingPassedPostResult.passAccepted);
      expect((await posts.loadFeed()), hasLength(1));
      final feed = await posts.loadFeed();
      final resurfacedPost = await posts.getPost('post-1');
      final origin = await posts.getPostOrigin('post-1');
      expect(feed.single.id, 'post-1');
      expect(feed.single.visibleAt, '2026-03-15T11:25:00.000Z');
      expect(resurfacedPost, isNotNull);
      expect(resurfacedPost!.passedByUsername, 'Maria');
      expect(resurfacedPost.passedAt, '2026-03-15T11:25:00.000Z');
      expect(resurfacedPost.visibleAt, '2026-03-15T11:25:00.000Z');
      expect(await posts.loadPostPasses('post-1'), hasLength(2));
      expect(origin, isNotNull);
      expect(origin!.originKind, PostOriginKind.direct);
      expect(origin.passerUsername, 'Maria');
      expect(origin.passCreatedAt, '2026-03-15T11:25:00.000Z');
    },
  );

  test(
    'resurfaces an existing direct post for each distinct later repost without creating a duplicate row',
    () async {
      contacts.addTestContact(_contact('peer-james', 'James'));
      contacts.addTestContact(_contact('peer-maria', 'Maria'));
      await posts.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-direct-1',
          senderPeerId: 'peer-sarah',
          authorPeerId: 'peer-sarah',
          authorUsername: 'Sarah',
          text: 'Lost dog near Neckar bridge.',
          audience: PostAudience.peopleNearby(radiusM: 2000),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
        ),
      );
      await posts.savePost(
        PostModel(
          id: 'post-2',
          eventId: 'evt-direct-2',
          senderPeerId: 'peer-ava',
          authorPeerId: 'peer-ava',
          authorUsername: 'Ava',
          text: 'Can someone lend jumper cables?',
          audience: PostAudience.allFriends(),
          createdAt: '2026-03-15T10:45:00.000Z',
          visibleAt: '2026-03-15T10:45:00.000Z',
          expiresAt: '2026-03-18T10:45:00.000Z',
        ),
      );

      final (result, post) = await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(),
          transportSender: 'peer-james',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      final second = await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(
            senderPeerId: 'peer-maria',
            passerPeerId: 'peer-maria',
            passerUsername: 'Maria',
            passId: 'pass-2',
            eventId: 'evt-pass-2',
            passedAt: '2026-03-15T11:25:00.000Z',
          ),
          transportSender: 'peer-maria',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPassedPostResult.passAccepted);
      expect(second.$1, HandleIncomingPassedPostResult.passAccepted);
      expect(post, isNotNull);
      final feed = await posts.loadFeed();
      final origin = await posts.getPostOrigin('post-1');
      expect(feed, hasLength(2));
      expect(feed.first.id, 'post-1');
      expect(feed.first.visibleAt, '2026-03-15T11:25:00.000Z');
      expect(await posts.loadPostPasses('post-1'), hasLength(2));
      expect((await posts.getPost('post-1'))?.senderPeerId, 'peer-sarah');
      expect((await posts.getPost('post-1'))?.passedByUsername, 'Maria');
      expect(
        (await posts.getPost('post-1'))?.visibleAt,
        '2026-03-15T11:25:00.000Z',
      );
      expect((await posts.getPost('post-1'))?.shareCount, 2);
      expect(origin, isNotNull);
      expect(origin!.originKind, PostOriginKind.direct);
      expect(origin.passerUsername, 'Maria');
      expect(origin.passCreatedAt, '2026-03-15T11:25:00.000Z');
    },
  );

  test(
    'keeps latest repost attribution when an older distinct repost arrives afterward',
    () async {
      contacts.addTestContact(_contact('peer-james', 'James'));
      contacts.addTestContact(_contact('peer-maria', 'Maria'));
      contacts.addTestContact(_contact('peer-nora', 'Nora'));
      await posts.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-direct-1',
          senderPeerId: 'peer-sarah',
          authorPeerId: 'peer-sarah',
          authorUsername: 'Sarah',
          text: 'Lost dog near Neckar bridge.',
          audience: PostAudience.peopleNearby(radiusM: 2000),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
        ),
      );

      await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(),
          transportSender: 'peer-james',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(
            senderPeerId: 'peer-maria',
            passerPeerId: 'peer-maria',
            passerUsername: 'Maria',
            passId: 'pass-2',
            eventId: 'evt-pass-2',
            passedAt: '2026-03-15T11:25:00.000Z',
          ),
          transportSender: 'peer-maria',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      final olderThird = await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(
            senderPeerId: 'peer-nora',
            passerPeerId: 'peer-nora',
            passerUsername: 'Nora',
            passId: 'pass-3',
            eventId: 'evt-pass-3',
            passedAt: '2026-03-15T11:20:00.000Z',
          ),
          transportSender: 'peer-nora',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      final resurfacedPost = await posts.getPost('post-1');
      final origin = await posts.getPostOrigin('post-1');
      expect(olderThird.$1, HandleIncomingPassedPostResult.passAccepted);
      expect((await posts.loadFeed()), hasLength(1));
      expect(await posts.loadPostPasses('post-1'), hasLength(3));
      expect(resurfacedPost, isNotNull);
      expect(resurfacedPost!.visibleAt, '2026-03-15T11:25:00.000Z');
      expect(resurfacedPost.passedByUsername, 'Maria');
      expect(resurfacedPost.passedAt, '2026-03-15T11:25:00.000Z');
      expect(resurfacedPost.shareCount, 3);
      expect(origin, isNotNull);
      expect(origin!.passerUsername, 'Maria');
      expect(origin.passCreatedAt, '2026-03-15T11:25:00.000Z');
    },
  );

  test(
    'keeps duplicate pass ids idempotent after resurfacing an existing direct post',
    () async {
      contacts.addTestContact(_contact('peer-james', 'James'));
      await posts.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-direct-1',
          senderPeerId: 'peer-sarah',
          authorPeerId: 'peer-sarah',
          authorUsername: 'Sarah',
          text: 'Lost dog near Neckar bridge.',
          audience: PostAudience.peopleNearby(radiusM: 2000),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
        ),
      );

      final first = await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(),
          transportSender: 'peer-james',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      final second = await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(),
          transportSender: 'peer-james',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(first.$1, HandleIncomingPassedPostResult.passAccepted);
      expect(second.$1, HandleIncomingPassedPostResult.duplicate);
      expect((await posts.loadFeed()), hasLength(1));
      expect(await posts.loadPostPasses('post-1'), hasLength(1));
      expect((await posts.getPost('post-1'))?.passedByUsername, 'James');
      expect(
        (await posts.getPost('post-1'))?.visibleAt,
        '2026-03-15T11:15:00.000Z',
      );
    },
  );

  test(
    'updates the original author share count after new pass events',
    () async {
      contacts.addTestContact(_contact('peer-james', 'James'));
      contacts.addTestContact(_contact('peer-maria', 'Maria'));
      await posts.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-direct-1',
          senderPeerId: 'peer-sarah',
          authorPeerId: 'peer-sarah',
          authorUsername: 'Sarah',
          text: 'Lost dog near Neckar bridge.',
          audience: PostAudience.peopleNearby(radiusM: 2000),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
        ),
      );

      await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(),
          transportSender: 'peer-james',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect((await posts.getPost('post-1'))?.shareCount, 1);

      await handleIncomingPassedPost(
        message: _messageFromJson(
          _postPassJson(
            senderPeerId: 'peer-maria',
            passerPeerId: 'peer-maria',
            passerUsername: 'Maria',
            passId: 'pass-2',
            eventId: 'evt-pass-2',
            passedAt: '2026-03-15T11:25:00.000Z',
          ),
          transportSender: 'peer-maria',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect((await posts.getPost('post-1'))?.shareCount, 2);
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

ChatMessage _messageFromJson(
  Map<String, Object?> json, {
  required String transportSender,
}) {
  return ChatMessage(
    from: transportSender,
    to: 'peer-self',
    content: jsonEncode(json),
    timestamp: '2026-03-15T11:15:00.000Z',
    isIncoming: true,
  );
}

Map<String, Object?> _postPassJson({
  String senderPeerId = 'peer-james',
  String passerPeerId = 'peer-james',
  String passerUsername = 'James',
  String passId = 'pass-1',
  String eventId = 'evt-pass-1',
  String passedAt = '2026-03-15T11:15:00.000Z',
  String mediaKind = 'none',
  List<Object?> media = const <Object?>[],
}) {
  return <String, Object?>{
    'type': 'post_pass',
    'version': '1',
    'event_id': eventId,
    'created_at': passedAt,
    'sender_peer_id': senderPeerId,
    'payload': <String, Object?>{
      'pass_id': passId,
      'post_id': 'post-1',
      'passed_at': passedAt,
      'passer_peer_id': passerPeerId,
      'passer_username': passerUsername,
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
        'media_kind': mediaKind,
        'media': media,
        'keep_available': false,
        'expires_at': '2026-03-18T10:15:30.000Z',
      },
    },
  };
}
