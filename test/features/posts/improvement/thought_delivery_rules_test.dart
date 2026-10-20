import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_media_upload_retrier.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_upload_recovery_item.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/encrypted_media_test_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

ContactModel _contact(String peerId, {String? key = 'mlkem-key'}) =>
    ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: 'rendezvous',
      username: peerId,
      signature: 'signature',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: key,
    );

PostModel _post(DateTime createdAt, {String status = 'failed'}) => PostModel(
  id: 'thought',
  eventId: 'event',
  senderPeerId: 'author',
  authorPeerId: 'author',
  authorUsername: 'Author',
  text: 'A private thought',
  audience: PostAudience.allFriends(),
  createdAt: createdAt.toIso8601String(),
  visibleAt: createdAt.toIso8601String(),
  expiresAt: '2099-01-01T00:00:00.000Z',
  keepAvailable: true,
  deliveryStatus: status,
  isIncoming: false,
);

Future<void> _addFailedDelivery(InMemoryPostRepository posts) async {
  await posts.saveRecipientDelivery(
    PostRecipientDelivery(
      postId: 'thought',
      recipientPeerId: 'friend',
      deliveryStatus: 'failed',
      lastAttemptAt: DateTime.now().toUtc().toIso8601String(),
      deliveryPath: 'failed',
      lastError: 'recipient_missing_mlkem_key',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    ),
  );
}

Map<String, dynamic> _inner(String wire) {
  final outer = jsonDecode(wire) as Map<String, dynamic>;
  expect(outer['version'], '2');
  expect(outer.containsKey('payload'), isFalse);
  return jsonDecode(
        (outer['encrypted'] as Map<String, dynamic>)['ciphertext'] as String,
      )
      as Map<String, dynamic>;
}

void main() {
  late InMemoryPostRepository posts;
  late InMemoryContactRepository contacts;
  late FakeP2PNetwork network;
  late _CountingP2PService service;
  late FakeBridge bridge;

  setUp(() {
    posts = InMemoryPostRepository();
    contacts = InMemoryContactRepository();
    network = FakeP2PNetwork();
    service = _CountingP2PService(peerId: 'author', network: network);
    bridge = FakeBridge();
  });
  tearDown(() {
    posts.dispose();
    service.dispose();
  });

  test(
    'missing recipient key fails only that recipient without a plaintext copy',
    () async {
      contacts.addTestContact(_contact('friend', key: null));
      contacts.addTestContact(_contact('other-friend'));
      final (result, post) = await sendPost(
        p2pService: service,
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'author',
        senderUsername: 'Author',
        text: 'A private thought',
        audience: PostAudience.allFriends(),
        bridge: bridge,
      );
      expect(result, SendPostResult.partialSuccess);
      expect(post!.deliveryStatus, 'partial');
      final failed = (await posts.getRecipientDeliveries(
        post.id,
      )).singleWhere((row) => row.recipientPeerId == 'friend');
      expect(failed.deliveryStatus, 'failed');
      expect(failed.lastError, 'recipient_missing_mlkem_key');
      expect(network.inboxCount('friend'), 0);
      expect(service.sentTo, isEmpty);
      final wire =
          network.retrieveInbox('other-friend').single['message'] as String;
      final inner = _inner(wire);
      expect(inner.containsKey('recipient_peer_ids'), isFalse);
      expect(inner.containsKey('selected_peer_ids'), isFalse);
      expect(jsonEncode(inner), isNot(contains('"friend"')));
    },
  );

  for (final response in <Map<String, dynamic>>[
    {'ok': false, 'errorCode': 'bad_key'},
    {'ok': true, 'kem': 'kem', 'nonce': 'nonce'},
  ]) {
    test(
      'encryption failure ${response['errorCode'] ?? 'invalid response'} never sends',
      () async {
        contacts.addTestContact(_contact('friend'));
        bridge.responses['message.encrypt'] = response;
        final (result, post) = await sendPost(
          p2pService: service,
          postRepo: posts,
          contactRepo: contacts,
          senderPeerId: 'author',
          senderUsername: 'Author',
          text: 'secret',
          audience: PostAudience.allFriends(),
          bridge: bridge,
        );
        expect(result, SendPostResult.sendFailed);
        final delivery = (await posts.getRecipientDeliveries(post!.id)).single;
        expect(
          delivery.lastError,
          'thought_encrypt_failed:${response['errorCode'] ?? 'invalid_response'}',
        );
        expect(service.sentTo, isEmpty);
        expect(network.inboxCount('friend'), 0);
      },
    );
  }

  for (final malformed in [false, true]) {
    test(
      'a ${malformed ? 'malformed' : 'throwing'} bridge response fails only its recipient',
      () async {
        contacts.addTestContact(_contact('broken-friend', key: 'broken-key'));
        contacts.addTestContact(_contact('healthy-friend', key: 'healthy-key'));
        final (_, created) = await createLocalPost(
          postRepo: posts,
          contactRepo: contacts,
          senderPeerId: 'author',
          senderUsername: 'Author',
          text: 'secret',
          audience: PostAudience.allFriends(),
        );
        final (result, thought) = await PostDeliveryRunner(
          p2pService: service,
          postRepo: posts,
          bridge: _OneBadRecipientBridge(malformed: malformed),
          maxConcurrentRecipients: 1,
        ).execute(created!);
        expect(result, SendPostResult.partialSuccess);
        expect(thought.deliveryStatus, 'partial');
        final deliveries = await posts.getRecipientDeliveries(thought.id);
        final broken = deliveries.singleWhere(
          (row) => row.recipientPeerId == 'broken-friend',
        );
        expect(broken.lastError, 'thought_encrypt_failed:bridge_error');
        expect(network.inboxCount('broken-friend'), 0);
        expect(network.inboxCount('healthy-friend'), 1);
      },
    );
  }

  test(
    'retry loads the newly available contact key and does not repeat settled delivery',
    () async {
      contacts.addTestContact(_contact('friend', key: null));
      contacts.addTestContact(_contact('other-friend'));
      final (_, sent) = await sendPost(
        p2pService: service,
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'author',
        senderUsername: 'Author',
        text: 'secret',
        audience: PostAudience.allFriends(),
        bridge: bridge,
      );
      contacts.addTestContact(_contact('friend', key: 'new-key'));
      bridge.sentMessages.clear();
      expect(
        await retryPendingPostDeliveries(
          postRepo: posts,
          contactRepo: contacts,
          p2pService: service,
          bridge: bridge,
        ),
        1,
      );
      expect((await posts.getPost(sent!.id))!.deliveryStatus, 'sent');
      final encrypts = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((command) => command['cmd'] == 'message.encrypt');
      expect(encrypts, hasLength(1));
      expect(
        (encrypts.single['payload']
            as Map<String, dynamic>)['recipientPublicKey'],
        'new-key',
      );
      expect(network.inboxCount('friend'), 1);
      expect(network.inboxCount('other-friend'), 1);
    },
  );

  test(
    '100 friends with 90 disconnected incur no discovery or dial waits',
    () async {
      for (var index = 0; index < 100; index++) {
        final peerId = 'friend-$index';
        contacts.addTestContact(_contact(peerId));
        if (index < 10) service.connectedPeers.add(peerId);
      }
      final stopwatch = Stopwatch()..start();
      final (result, post) = await sendPost(
        p2pService: service,
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'author',
        senderUsername: 'Author',
        text: 'secret',
        audience: PostAudience.allFriends(),
        bridge: bridge,
      );
      stopwatch.stop();
      expect(result, SendPostResult.success);
      expect(service.discoveries, 0);
      expect(service.dials, 0);
      expect(service.sentTo, hasLength(10));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 4)));
      final deliveries = await posts.getRecipientDeliveries(post!.id);
      expect(
        deliveries.where((row) => row.deliveryStatus == 'inbox'),
        hasLength(90),
      );
      expect(
        deliveries.where((row) => row.deliveryStatus == 'delivered'),
        hasLength(10),
      );
    },
  );

  for (final status in ['failed', 'partial']) {
    test(
      'expired $status thought cannot retry even when the repository returns it',
      () async {
        final now = DateTime.now().toUtc();
        await posts.savePost(
          _post(now.subtract(ThoughtLifetime.duration), status: status),
        );
        await _addFailedDelivery(posts);
        contacts.addTestContact(_contact('friend'));
        expect(
          await retryPendingPostDeliveries(
            postRepo: posts,
            contactRepo: contacts,
            p2pService: service,
            bridge: bridge,
            nowProvider: () => now,
          ),
          0,
        );
        expect((await posts.getPost('thought'))!.deliveryStatus, status);
        expect(bridge.commandLog, isEmpty);
        expect(network.inboxCount('friend'), 0);
      },
    );
  }

  test('expiry is checked again after loading a retry contact', () async {
    var now = DateTime.now().toUtc();
    final createdAt = now.subtract(const Duration(hours: 23));
    final delayedContacts = _ContactLookupHook(() {
      now = ThoughtLifetime.expiresAt(createdAt);
    });
    delayedContacts.addTestContact(_contact('friend'));
    await posts.savePost(_post(createdAt));
    await _addFailedDelivery(posts);
    expect(
      await retryPendingPostDeliveries(
        postRepo: posts,
        contactRepo: delayedContacts,
        p2pService: service,
        bridge: bridge,
        nowProvider: () => now,
      ),
      0,
    );
    expect(bridge.commandLog, isEmpty);
    expect(network.inboxCount('friend'), 0);
  });

  test(
    'expired media recovery clears the recovery job before file or upload work',
    () async {
      final now = DateTime.now().toUtc();
      await posts.savePost(
        _post(
          now.subtract(ThoughtLifetime.duration),
        ).copyWith(mediaKind: 'image'),
      );
      await _addFailedDelivery(posts);
      await posts.replacePostMediaUploadRecoveryItems('thought', [
        PostMediaUploadRecoveryItem(
          postId: 'thought',
          position: 0,
          localFilePath: '/missing/never-read.jpg',
          mime: 'image/jpeg',
          kind: 'image',
          createdAt: now.toIso8601String(),
        ),
      ]);
      var uploads = 0;
      expect(
        await retryPendingPostMediaUploads(
          postRepo: posts,
          contactRepo: contacts,
          p2pService: service,
          secureKeyStore: FakeSecureKeyStore(),
          imageProcessor: ImageProcessor(),
          bridge: bridge,
          nowProvider: () => now,
          uploadPostMediaFn:
              ({
                required postId,
                required localFilePath,
                required mime,
                required allowedPeers,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
              }) async {
                uploads++;
                return null;
              },
        ),
        0,
      );
      expect(uploads, 0);
      expect(await posts.loadPostMediaUploadRecoveryItems('thought'), isEmpty);
      expect(await posts.loadPendingMediaUploadPosts(), isEmpty);
      expect(
        (await posts.getRecipientDeliveries('thought')).single.lastError,
        'recipient_missing_mlkem_key',
      );
      expect(bridge.commandLog, isEmpty);
    },
  );

  test(
    'a direct delivery completing after deletion cannot recreate the author copy',
    () async {
      var now = DateTime.now().toUtc();
      final createdAt = now.subtract(const Duration(hours: 23));
      final post = _post(createdAt);
      await posts.savePost(post);
      await _addFailedDelivery(posts);
      service.connectedPeers.add('friend');
      service.beforeSendCompletes = () async {
        now = ThoughtLifetime.expiresAt(createdAt);
        await posts.deletePostCascade(post.id);
      };
      await PostDeliveryRunner(
        p2pService: service,
        postRepo: posts,
        bridge: bridge,
        nowProvider: () => now,
      ).execute(
        CreatedLocalPost(
          post: post,
          resolvedRecipients: [
            CreatedLocalPostRecipient(contact: _contact('friend')),
          ],
        ),
      );
      expect(service.sentTo, ['friend']);
      expect(await posts.getPost(post.id), isNull);
      expect(await posts.getRecipientDeliveries(post.id), isEmpty);
    },
  );

  test(
    'hydration completing after expiry discards late files and never recreates rows',
    () async {
      var now = DateTime.now().toUtc();
      final createdAt = now.subtract(const Duration(hours: 23));
      contacts.addTestContact(_contact('author'));
      final temp = await Directory.systemTemp.createTemp(
        'thought-late-hydration',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final lateFile = File('${temp.path}/post_media/thought/late.jpg');
      final attachment = PostMediaAttachmentModel(
        mediaId: 'photo',
        postId: 'thought',
        blobId: 'blob',
        kind: 'image',
        mime: 'image/jpeg',
        sizeBytes: 8,
        createdAt: createdAt.toIso8601String(),
      );
      final incoming = _post(
        createdAt,
      ).copyWith(mediaKind: 'image', media: [attachment]);
      final (result, received) = await handleIncomingPost(
        message: ChatMessage(
          from: 'author',
          to: 'receiver',
          content: PostCreateEnvelope.fromPost(incoming).toJson(),
          timestamp: now.toIso8601String(),
          isIncoming: true,
        ),
        postRepo: posts,
        contactRepo: contacts,
        nowProvider: () => now,
        mediaFileManager: TempPostMediaFileManager(temp.path),
        hydratePostMediaFn: ({required attachment, required postId}) async {
          now = ThoughtLifetime.expiresAt(createdAt);
          await posts.deletePostCascade(postId);
          await lateFile.parent.create(recursive: true);
          await lateFile.writeAsString('late image');
          return attachment.copyWith(
            localPath: 'post_media/thought/late.jpg',
            downloadStatus: 'done',
          );
        },
      );
      expect(result, HandleIncomingPostResult.expired);
      expect(received, isNull);
      expect(await posts.getPost('thought'), isNull);
      expect(await posts.loadPostMediaAttachments('thought'), isEmpty);
      expect(await lateFile.exists(), isFalse);
      expect(await lateFile.parent.exists(), isFalse);
    },
  );

  test(
    'legacy recipient lists are ignored and incoming lifetime is capped',
    () async {
      final now = DateTime.now().toUtc();
      contacts.addTestContact(_contact('author'));
      final createdAt = now.subtract(const Duration(hours: 1));
      final raw =
          jsonDecode(PostCreateEnvelope.fromPost(_post(createdAt)).toJson())
              as Map<String, dynamic>;
      final payload = raw['payload'] as Map<String, dynamic>;
      payload['selected_peer_ids'] = ['secret-friend'];
      payload['recipient_peer_ids'] = ['secret-friend', 'another-friend'];
      (payload['snapshot'] as Map<String, dynamic>)['audience'] = {
        'kind': 'pick_people',
      };
      final (result, received) = await handleIncomingPost(
        message: ChatMessage(
          from: 'author',
          to: 'receiver',
          content: jsonEncode(raw),
          timestamp: now.toIso8601String(),
          isIncoming: true,
        ),
        postRepo: posts,
        contactRepo: contacts,
        nowProvider: () => now,
      );
      expect(result, HandleIncomingPostResult.postCreated);
      expect(
        received!.expiresAt,
        ThoughtLifetime.expiresAt(createdAt).toIso8601String(),
      );
      expect(received.keepAvailable, isFalse);
      expect(received.audience.selectedPeerIds, isEmpty);
      expect(await posts.getRecipientDeliveries('thought'), isEmpty);
    },
  );

  test(
    'a thought arriving exactly at its deadline stores no rows or media',
    () async {
      final now = DateTime.now().toUtc();
      contacts.addTestContact(_contact('author'));
      final expired = _post(now.subtract(ThoughtLifetime.duration));
      var hydrated = false;
      final (result, received) = await handleIncomingPost(
        message: ChatMessage(
          from: 'author',
          to: 'receiver',
          content: PostCreateEnvelope.fromPost(expired).toJson(),
          timestamp: now.toIso8601String(),
          isIncoming: true,
        ),
        postRepo: posts,
        contactRepo: contacts,
        nowProvider: () => now,
        hydratePostMediaFn: ({required attachment, required postId}) async {
          hydrated = true;
          return attachment;
        },
      );
      expect(result, HandleIncomingPostResult.expired);
      expect(received, isNull);
      expect(await posts.getPost('thought'), isNull);
      expect(await posts.loadPostMediaAttachments('thought'), isEmpty);
      expect(hydrated, isFalse);
    },
  );
}

class _ContactLookupHook extends InMemoryContactRepository {
  final void Function() beforeLookup;
  _ContactLookupHook(this.beforeLookup);
  @override
  Future<ContactModel?> getContact(String peerId) async {
    beforeLookup();
    return super.getContact(peerId);
  }
}

class _CountingP2PService extends FakeP2PService {
  int discoveries = 0;
  int dials = 0;
  final List<String> sentTo = [];
  Future<void> Function()? beforeSendCompletes;
  _CountingP2PService({required super.peerId, required super.network});
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    discoveries++;
    throw StateError('Disconnected thought must go straight to the inbox');
  }

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async {
    dials++;
    throw StateError('Disconnected thought must go straight to the inbox');
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    sentTo.add(targetPeerId);
    await beforeSendCompletes?.call();
    return const SendMessageResult(sent: true);
  }
}

class _OneBadRecipientBridge extends FakeBridge {
  final bool malformed;
  _OneBadRecipientBridge({required this.malformed});
  @override
  Future<String> send(String message) async {
    final command = jsonDecode(message) as Map<String, dynamic>;
    if (command['cmd'] == 'message.encrypt' &&
        (command['payload'] as Map<String, dynamic>)['recipientPublicKey'] ==
            'broken-key') {
      if (malformed) return 'invalid json';
      throw StateError('bridge unavailable');
    }
    return super.send(message);
  }
}
