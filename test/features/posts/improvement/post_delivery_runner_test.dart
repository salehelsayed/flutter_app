import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/test_user.dart';

ContactModel _contact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    mlKemPublicKey: 'mlkem-$peerId',
  );
}

void main() {
  late FakeP2PNetwork network;
  late _RecordingPostRepository posts;
  late InMemoryContactRepository contacts;

  setUp(() {
    network = FakeP2PNetwork();
    posts = _RecordingPostRepository();
    contacts = InMemoryContactRepository();
  });

  tearDown(() {
    posts.dispose();
  });

  group('compact photo push', () {
    test('encrypts a minimal snapshot for each relay recipient without changing the canonical photo', () async {
      final recipients = [_contact('peer-bob', 'Bob'), _contact('peer-cara', 'Cara')];
      final created = await _createdForCompactPhotoPush(
        posts: posts,
        recipients: recipients,
        mediaKinds: const ['image', 'image'],
        metricsOptOut: true,
      );
      final bridge = FakeBridge();
      final service = FakeP2PService(peerId: 'peer-alice', network: network);
      final canonicalInner = PostCreateEnvelope.fromPost(created.post).toInnerJson();
      final canonical = jsonDecode(canonicalInner) as Map<String, dynamic>;
      expect((canonical['snapshot'] as Map)['text'], created.post.text);
      expect((canonical['snapshot'] as Map)['media'], hasLength(2));
      expect(canonical['media_keys'], {
        for (var i = 0; i < 2; i++) 'photo-media-$i': {
          'key_base64': 'fixture-key-$i',
          'nonce': 'fixture-media-nonce-$i',
          'blob_id': 'photo-blob-$i',
          'scheme': 'blob_aes_256_gcm_v1',
          'content_hash': 'f' * 64,
          'preview': 'A' * 4096,
        },
      });

      final (result, delivered) = await PostDeliveryRunner(
        p2pService: service,
        postRepo: posts,
        bridge: bridge,
        nowProvider: () => _compactPhotoPushNow,
      ).execute(created);

      expect(result, SendPostResult.success);
      expect(delivered.deliveryStatus, 'sent');
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 2);
      final minimal = <String, Object?>{
        'snapshot': {
          'post_id': created.post.id,
          'author_peer_id': created.post.authorPeerId,
          'text': '',
          'media': [{'kind': 'image'}],
        },
      };
      for (final recipient in recipients) {
        final wireString = network.retrieveInbox(recipient.peerId).single['message'] as String;
        final wire = jsonDecode(wireString) as Map<String, dynamic>;
        expect(wire['encrypted'], {
          'kem': 'fake-kem', 'ciphertext': canonicalInner, 'nonce': 'fake-nonce',
        });
        expect(wire['thoughts_metrics_opt_out'], isTrue);
        final withoutPush = Map<String, dynamic>.from(wire)..remove('push_encrypted');
        expect(jsonEncode(withoutPush), _canonicalPhotoWire(created.post, canonicalInner));
        expect(wire['push_encrypted'], {
          'kem': 'fake-kem', 'ciphertext': jsonEncode(minimal), 'nonce': 'fake-nonce',
        });
        final requests = _photoEncryptRequests(bridge).where(
          (payload) => payload['recipientPublicKey'] == recipient.mlKemPublicKey,
        ).toList();
        expect(requests, hasLength(2));
        expect(requests.first['plaintext'], canonicalInner);
        expect(jsonDecode(requests.last['plaintext'] as String), minimal);
      }
      expect((await posts.getRecipientDeliveries(created.post.id)).map(
        (delivery) => delivery.deliveryPath,
      ), everyElement('inbox'));
    });

    for (final failure in <String, Map<String, dynamic>>{
      'error response': {'ok': false, 'errorCode': 'COMPACT_FAILED'},
      'missing kem': {'ok': true, 'ciphertext': 'push-cipher', 'nonce': 'push-nonce'},
      'empty ciphertext': {'ok': true, 'kem': 'push-kem', 'ciphertext': '', 'nonce': 'push-nonce'},
      'non-string nonce': {'ok': true, 'kem': 'push-kem', 'ciphertext': 'push-cipher', 'nonce': 7},
    }.entries) {
      test('keeps canonical inbox delivery after optional ${failure.key}', () async {
        final created = await _createdForCompactPhotoPush(posts: posts);
        final bridge = FakeBridge(initialResponses: {
          'message.encrypt': _canonicalPhotoEncryptResult,
        });
        bridge.responseSequences['message.encrypt'] = [
          _canonicalPhotoEncryptResult, failure.value,
        ];
        final (result, delivered) = await PostDeliveryRunner(
          p2pService: FakeP2PService(peerId: 'peer-alice', network: network),
          postRepo: posts,
          bridge: bridge,
          nowProvider: () => _compactPhotoPushNow,
        ).execute(created);

        expect(result, SendPostResult.success);
        expect(delivered.deliveryStatus, 'sent');
        final wire = network.retrieveInbox('peer-bob').single['message'] as String;
        expect(wire, _canonicalPhotoWire(created.post, 'canonical-ciphertext',
          kem: 'canonical-kem', nonce: 'canonical-nonce'));
        expect((jsonDecode(wire) as Map).containsKey('push_encrypted'), isFalse);
        expect((await posts.getRecipientDeliveries(created.post.id)).single.deliveryPath, 'inbox');
        expect(_photoEncryptRequests(bridge), hasLength(2));
      });
    }

    test('keeps canonical inbox delivery when optional encryption throws', () async {
      final created = await _createdForCompactPhotoPush(posts: posts);
      final bridge = _ThrowOnSecondPhotoEncryptionBridge();
      final (result, delivered) = await PostDeliveryRunner(
        p2pService: FakeP2PService(peerId: 'peer-alice', network: network),
        postRepo: posts,
        bridge: bridge,
        nowProvider: () => _compactPhotoPushNow,
      ).execute(created);

      expect(result, SendPostResult.success);
      expect(delivered.deliveryStatus, 'sent');
      expect(network.retrieveInbox('peer-bob').single['message'],
        _canonicalPhotoWire(created.post, 'canonical-ciphertext',
          kem: 'canonical-kem', nonce: 'canonical-nonce'));
      expect((await posts.getRecipientDeliveries(created.post.id)).single.deliveryPath, 'inbox');
      expect(bridge.encryptionAttempts, 2);
    });

    for (final kind in ['text', 'empty-image', 'video', 'voice', 'mixed']) {
      test('leaves $kind canonical-only with one encryption', () async {
        final kinds = kind == 'text' || kind == 'empty-image'
            ? <String>[] : kind == 'mixed' ? <String>['image', 'video'] : <String>[kind];
        final declaredKind = kind == 'text' ? 'none'
            : kind == 'empty-image' || kind == 'mixed' ? 'image' : kind;
        final created = await _createdForCompactPhotoPush(
          posts: posts, mediaKinds: kinds, mediaKind: declaredKind,
        );
        final bridge = FakeBridge();
        final inner = PostCreateEnvelope.fromPost(created.post).toInnerJson();
        final (result, _) = await PostDeliveryRunner(
          p2pService: FakeP2PService(peerId: 'peer-alice', network: network),
          postRepo: posts,
          bridge: bridge,
          nowProvider: () => _compactPhotoPushNow,
        ).execute(created);

        expect(result, SendPostResult.success);
        expect(network.retrieveInbox('peer-bob').single['message'],
          _canonicalPhotoWire(created.post, inner));
        expect(_photoEncryptRequests(bridge), hasLength(1));
      });
    }
  });

  test(
    'execute updates recipient rows as results arrive and recomputes post status after each update',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      contacts.addTestContact(_contact('peer-cara', 'Cara'));
      FakeP2PService(peerId: 'peer-bob', network: network);
      final aliceService = _PolicyFakeP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-cara': _PeerPolicy(
            sendResult: false,
            storeInInboxResult: false,
          ),
        },
      );

      aliceService.connectedPeers.add('peer-bob');
      final created = await _createLocalPost(
        posts: posts,
        contacts: contacts,
        recipientPeerIds: const ['peer-bob', 'peer-cara'],
      );
      posts.clearWriteLog();

      final (result, post) = await PostDeliveryRunner(
        p2pService: aliceService,
        postRepo: posts,
        bridge: FakeBridge(),
      ).execute(created);

      expect(result, SendPostResult.partialSuccess);
      expect(post.deliveryStatus, 'partial');
      expect(posts.writeLog, hasLength(4));
      expect(posts.writeLog[1], 'post:sending');
      expect(posts.writeLog[3], 'post:partial');
      expect(
        <String>{posts.writeLog[0], posts.writeLog[2]},
        <String>{'delivery:peer-bob:delivered', 'delivery:peer-cara:failed'},
      );

      final deliveries = await posts.getRecipientDeliveries(post.id);
      expect(
        deliveries.map(
          (entry) => '${entry.recipientPeerId}:${entry.deliveryStatus}',
        ),
        <String>['peer-bob:delivered', 'peer-cara:failed'],
      );
    },
  );

  test('execute marks post sent when all recipients succeed', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-cara', 'Cara'));
    FakeP2PService(peerId: 'peer-bob', network: network);
    final aliceService = FakeP2PService(peerId: 'peer-alice', network: network);

    aliceService.connectedPeers.add('peer-bob');
    final created = await _createLocalPost(
      posts: posts,
      contacts: contacts,
      recipientPeerIds: const ['peer-bob', 'peer-cara'],
    );

    final (result, post) = await PostDeliveryRunner(
      p2pService: aliceService,
      postRepo: posts,
      bridge: FakeBridge(),
    ).execute(created);

    expect(result, SendPostResult.success);
    expect(post.deliveryStatus, 'sent');

    final deliveries = await posts.getRecipientDeliveries(post.id);
    expect(
      deliveries.map(
        (entry) => '${entry.recipientPeerId}:${entry.deliveryStatus}',
      ),
      <String>['peer-bob:delivered', 'peer-cara:inbox'],
    );
    expect(network.inboxCount('peer-cara'), 1);
  });

  test(
    'an unacknowledged direct send falls back to the inbox, not delivered',
    () async {
      // A paused receiver can leave the connection looking live: the frame is
      // written but its node never acknowledges, so the copy must also wait in
      // the inbox or the friend never gets the thought.
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      FakeP2PService(peerId: 'peer-bob', network: network);
      final aliceService = FakeP2PService(peerId: 'peer-alice', network: network)
        ..directReplyBuilder = (_, _, _) =>
            const SendMessageResult(sent: true, acked: false);
      aliceService.connectedPeers.add('peer-bob');
      final created = await _createLocalPost(
        posts: posts,
        contacts: contacts,
        recipientPeerIds: const ['peer-bob'],
      );

      final (_, post) = await PostDeliveryRunner(
        p2pService: aliceService,
        postRepo: posts,
        bridge: FakeBridge(),
      ).execute(created);

      final deliveries = await posts.getRecipientDeliveries(post.id);
      expect(
        deliveries.map((d) => '${d.recipientPeerId}:${d.deliveryStatus}'),
        <String>['peer-bob:inbox'],
      );
      expect(network.inboxCount('peer-bob'), 1);
    },
  );

  test('execute marks post failed when all recipients fail', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-cara', 'Cara'));
    final aliceService = _PolicyFakeP2PService(
      peerId: 'peer-alice',
      network: network,
      policies: const {
        'peer-bob': _PeerPolicy(sendResult: false, storeInInboxResult: false),
        'peer-cara': _PeerPolicy(sendResult: false, storeInInboxResult: false),
      },
    );

    aliceService.connectedPeers.add('peer-bob');
    final created = await _createLocalPost(
      posts: posts,
      contacts: contacts,
      recipientPeerIds: const ['peer-bob', 'peer-cara'],
    );

    final (result, post) = await PostDeliveryRunner(
      p2pService: aliceService,
      postRepo: posts,
      bridge: FakeBridge(),
    ).execute(created);

    expect(result, SendPostResult.sendFailed);
    expect(post.deliveryStatus, 'failed');

    final deliveries = await posts.getRecipientDeliveries(post.id);
    expect(
      deliveries.every((entry) => entry.deliveryStatus == 'failed'),
      isTrue,
    );
  });

  test(
    'execute catches internal exceptions and persists terminal post failure',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final aliceService = _PolicyFakeP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': _PeerPolicy(sendResult: false, throwOnInbox: true),
        },
      );

      aliceService.connectedPeers.add('peer-bob');
      final created = await _createLocalPost(
        posts: posts,
        contacts: contacts,
        recipientPeerIds: const ['peer-bob'],
      );

      final (result, post) = await PostDeliveryRunner(
        p2pService: aliceService,
        postRepo: posts,
        bridge: FakeBridge(),
      ).execute(created);

      expect(result, SendPostResult.sendFailed);
      expect(post.deliveryStatus, 'failed');

      final storedPost = await posts.getPost(post.id);
      expect(storedPost, isNotNull);
      expect(storedPost!.deliveryStatus, 'failed');
    },
  );

  test('execute does not write conversation messages', () async {
    final bob = TestUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
      withReactions: true,
    );
    addTearDown(bob.dispose);
    bob.start();
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    final aliceService = FakeP2PService(peerId: 'peer-alice', network: network);

    aliceService.connectedPeers.add('peer-bob');
    final created = await _createLocalPost(
      posts: posts,
      contacts: contacts,
      recipientPeerIds: const ['peer-bob'],
    );

    final (result, _) = await PostDeliveryRunner(
      p2pService: aliceService,
      postRepo: posts,
      bridge: FakeBridge(),
    ).execute(created);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(result, SendPostResult.success);
    expect(bob.messageRepo.count, 0);
  });

  test(
    'execute sends disconnected recipients to inbox without discovery or dial',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      addTearDown(bobService.dispose);
      final aliceService = _PolicyFakeP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': _PeerPolicy(requireDiscoverAndDialBeforeSend: true),
        },
      );
      addTearDown(aliceService.dispose);

      final created = await _createLocalPost(
        posts: posts,
        contacts: contacts,
        recipientPeerIds: const ['peer-bob'],
      );

      final (result, post) = await PostDeliveryRunner(
        p2pService: aliceService,
        postRepo: posts,
        bridge: FakeBridge(),
      ).execute(created);

      expect(result, SendPostResult.success);
      expect(post.deliveryStatus, 'sent');
      expect(aliceService.discoverAttempts, isEmpty);
      expect(aliceService.dialAttempts, isEmpty);
      expect(network.inboxCount('peer-bob'), 1);

      final deliveries = await posts.getRecipientDeliveries(post.id);
      expect(deliveries.single.deliveryStatus, 'inbox');
      expect(deliveries.single.deliveryPath, 'inbox');
    },
  );

  test(
    'execute stores an inbox envelope whose top-level post_id names the post',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      addTearDown(bobService.dispose);
      final aliceService = _PolicyFakeP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': _PeerPolicy(requireDiscoverAndDialBeforeSend: true),
        },
      );
      addTearDown(aliceService.dispose);

      final created = await _createLocalPost(
        posts: posts,
        contacts: contacts,
        recipientPeerIds: const ['peer-bob'],
      );

      final (result, post) = await PostDeliveryRunner(
        p2pService: aliceService,
        postRepo: posts,
        bridge: FakeBridge(),
      ).execute(created);

      expect(result, SendPostResult.success);
      final stored = network.retrieveInbox('peer-bob').single;
      final envelope =
          jsonDecode(stored['message'] as String) as Map<String, dynamic>;
      expect(envelope['type'], 'post_create');
      expect(envelope['post_id'], post.id);
      expect(envelope['event_id'], post.eventId);
    },
  );

  test(
    'executePostPass encrypts repost payloads for each recipient and persists sent status',
    () async {
      final bridge = PassthroughCryptoBridge();
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      contacts.addTestContact(_contact('peer-cara', 'Cara'));
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      addTearDown(bobService.dispose);
      final caraService = FakeP2PService(peerId: 'peer-cara', network: network);
      addTearDown(caraService.dispose);
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      addTearDown(aliceService.dispose);

      const pass = PostPassModel(
        passId: 'pass-enc-1',
        eventId: 'evt-pass-enc-1',
        postId: 'post-pass-source',
        senderPeerId: 'peer-alice',
        passerPeerId: 'peer-alice',
        passerUsername: 'Alice',
        passedAt: '2026-03-15T10:00:02.000Z',
        createdAt: '2026-03-15T10:00:02.000Z',
        isIncoming: false,
      );
      final snapshotPost = _post(
        id: 'post-pass-source',
        deliveryStatus: 'available',
        isIncoming: true,
      ).copyWith(authorPeerId: 'peer-bob', authorUsername: 'Bob');
      final receivedByBob = bobService.messageStream.first;
      final receivedByCara = caraService.messageStream.first;

      final (result, deliveredPass) =
          await PostDeliveryRunner(
            p2pService: aliceService,
            postRepo: posts,
            bridge: bridge,
          ).executePostPass(
            pass: pass,
            snapshotPost: snapshotPost,
            resolvedRecipients: const <CreatedLocalPostRecipient>[
              CreatedLocalPostRecipient(
                contact: ContactModel(
                  peerId: 'peer-bob',
                  publicKey: 'pk-peer-bob',
                  rendezvous: '/dns4/example.invalid/tcp/443',
                  username: 'Bob',
                  signature: 'sig-peer-bob',
                  scannedAt: '2026-03-15T10:00:00.000Z',
                  mlKemPublicKey: 'mlkem-peer-bob',
                ),
              ),
              CreatedLocalPostRecipient(
                contact: ContactModel(
                  peerId: 'peer-cara',
                  publicKey: 'pk-peer-cara',
                  rendezvous: '/dns4/example.invalid/tcp/443',
                  username: 'Cara',
                  signature: 'sig-peer-cara',
                  scannedAt: '2026-03-15T10:00:00.000Z',
                  mlKemPublicKey: 'mlkem-peer-cara',
                ),
              ),
            ],
          );

      expect(result, SendPostResult.success);
      expect(deliveredPass.deliveryStatus, 'sent');
      expect(
        bridge.commandLog.where((command) => command == 'message.encrypt'),
        hasLength(2),
      );

      final bobJson =
          jsonDecode(
                (await receivedByBob.timeout(
                  const Duration(seconds: 1),
                )).content,
              )
              as Map<String, dynamic>;
      final caraJson =
          jsonDecode(
                (await receivedByCara.timeout(
                  const Duration(seconds: 1),
                )).content,
              )
              as Map<String, dynamic>;
      expect(bobJson['version'], '2');
      expect(caraJson['version'], '2');
      expect(
        (bobJson['encrypted'] as Map<String, dynamic>)['ciphertext'],
        isNotEmpty,
      );
      expect(
        (caraJson['encrypted'] as Map<String, dynamic>)['ciphertext'],
        isNotEmpty,
      );
    },
  );

  test(
    'executePostPass marks the repost delivery failed instead of downgrading to plaintext when encryption is unavailable',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      addTearDown(aliceService.dispose);

      const pass = PostPassModel(
        passId: 'pass-fail-1',
        eventId: 'evt-pass-fail-1',
        postId: 'post-pass-fail',
        senderPeerId: 'peer-alice',
        passerPeerId: 'peer-alice',
        passerUsername: 'Alice',
        passedAt: '2026-03-15T10:00:02.000Z',
        createdAt: '2026-03-15T10:00:02.000Z',
        isIncoming: false,
      );
      final snapshotPost = _post(
        id: 'post-pass-fail',
        deliveryStatus: 'available',
        isIncoming: true,
      ).copyWith(authorPeerId: 'peer-bob', authorUsername: 'Bob');

      final (
        result,
        deliveredPass,
      ) = await PostDeliveryRunner(p2pService: aliceService, postRepo: posts)
          .executePostPass(
            pass: pass,
            snapshotPost: snapshotPost,
            resolvedRecipients: const <CreatedLocalPostRecipient>[
              CreatedLocalPostRecipient(
                contact: ContactModel(
                  peerId: 'peer-bob',
                  publicKey: 'pk-peer-bob',
                  rendezvous: '/dns4/example.invalid/tcp/443',
                  username: 'Bob',
                  signature: 'sig-peer-bob',
                  scannedAt: '2026-03-15T10:00:00.000Z',
                  mlKemPublicKey: 'mlkem-peer-bob',
                ),
              ),
            ],
          );

      expect(result, SendPostResult.sendFailed);
      expect(deliveredPass.deliveryStatus, 'failed');
      expect(network.deliverCallCount, 0);
      final deliveries = await posts.getPostPassRecipientDeliveries(
        pass.passId,
      );
      expect(deliveries, hasLength(1));
      expect(deliveries.single.deliveryStatus, 'failed');
      expect(deliveries.single.lastError, 'repost_encryption_unavailable');
    },
  );

  test(
    'executePostPass with null innerPayloadJson and encrypted attachments fails closed instead of rebuilding without media_keys',
    () async {
      final bridge = PassthroughCryptoBridge();
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      addTearDown(aliceService.dispose);

      // Legacy/imported pass row that pre-dates innerPayloadJson.
      const pass = PostPassModel(
        passId: 'pass-keydrop-1',
        eventId: 'evt-pass-keydrop-1',
        postId: 'post-pass-keydrop',
        senderPeerId: 'peer-alice',
        passerPeerId: 'peer-alice',
        passerUsername: 'Alice',
        passedAt: '2026-03-15T10:00:02.000Z',
        createdAt: '2026-03-15T10:00:02.000Z',
        isIncoming: false,
      );
      final snapshotPost =
          _post(
            id: 'post-pass-keydrop',
            deliveryStatus: 'available',
            isIncoming: true,
          ).copyWith(
            authorPeerId: 'peer-bob',
            authorUsername: 'Bob',
            mediaKind: 'image',
            media: const <PostMediaAttachmentModel>[
              PostMediaAttachmentModel(
                mediaId: 'media-1',
                postId: 'post-pass-keydrop',
                blobId: 'blob-enc-1',
                kind: 'image',
                mime: 'image/jpeg',
                sizeBytes: 2048,
                createdAt: '2026-03-15T10:00:00.000Z',
                encryptionKeyBase64: 'row-key-b64',
                encryptionNonce: 'row-nonce-b64',
                isEncrypted: true,
              ),
            ],
          );

      final (result, deliveredPass) =
          await PostDeliveryRunner(
            p2pService: aliceService,
            postRepo: posts,
            bridge: bridge,
          ).executePostPass(
            pass: pass,
            snapshotPost: snapshotPost,
            resolvedRecipients: const <CreatedLocalPostRecipient>[
              CreatedLocalPostRecipient(
                contact: ContactModel(
                  peerId: 'peer-bob',
                  publicKey: 'pk-peer-bob',
                  rendezvous: '/dns4/example.invalid/tcp/443',
                  username: 'Bob',
                  signature: 'sig-peer-bob',
                  scannedAt: '2026-03-15T10:00:00.000Z',
                  mlKemPublicKey: 'mlkem-peer-bob',
                ),
              ),
            ],
          );

      // Recipients must NOT receive encrypted blobIds with no keys.
      expect(result, SendPostResult.sendFailed);
      expect(deliveredPass.deliveryStatus, 'failed');
      expect(network.deliverCallCount, 0);
      expect(bridge.commandLog, isNot(contains('message.encrypt')));
      final deliveries = await posts.getPostPassRecipientDeliveries(
        pass.passId,
      );
      expect(deliveries.single.deliveryStatus, 'failed');
      expect(deliveries.single.lastError, 'repost_payload_missing');
    },
  );

  test('PostDeliveryRunner stays widget agnostic', () async {
    final source = await File(
      'lib/features/posts/application/post_delivery_runner.dart',
    ).readAsString();

    expect(source, isNot(contains('package:flutter/')));
    expect(source, isNot(contains('BuildContext')));
    expect(source, isNot(contains('StatefulWidget')));
    expect(source, isNot(contains('setState(')));
  });
}

Future<CreatedLocalPost> _createLocalPost({
  required _RecordingPostRepository posts,
  required InMemoryContactRepository contacts,
  required List<String> recipientPeerIds,
}) async {
  final (result, created) = await createLocalPost(
    postRepo: posts,
    contactRepo: contacts,
    senderPeerId: 'peer-alice',
    senderUsername: 'Alice',
    text: 'Hello from Posts',
    audience: PostAudience.pickPeople(recipientPeerIds),
  );

  expect(result, SendPostResult.success);
  expect(created, isNotNull);
  return created!;
}

final _compactPhotoPushNow = DateTime.utc(2026, 11, 3, 12);
const _canonicalPhotoEncryptResult = <String, dynamic>{
  'ok': true, 'kem': 'canonical-kem',
  'ciphertext': 'canonical-ciphertext', 'nonce': 'canonical-nonce',
};

Future<CreatedLocalPost> _createdForCompactPhotoPush({
  required _RecordingPostRepository posts,
  List<ContactModel>? recipients,
  List<String> mediaKinds = const ['image'],
  String mediaKind = 'image',
  bool metricsOptOut = false,
}) async {
  final createdAt = _compactPhotoPushNow.toIso8601String();
  final post = _post(id: 'compact-photo', deliveryStatus: 'sending').copyWith(
    createdAt: createdAt,
    visibleAt: createdAt,
    expiresAt: _compactPhotoPushNow.add(const Duration(hours: 24)).toIso8601String(),
    text: 'Caption stays in the full photo Thought',
    mediaKind: mediaKind,
    metricsOptOut: metricsOptOut,
    media: [
      for (var i = 0; i < mediaKinds.length; i++) PostMediaAttachmentModel(
        mediaId: 'photo-media-$i', postId: 'compact-photo', blobId: 'photo-blob-$i',
        kind: mediaKinds[i],
        mime: mediaKinds[i] == 'image' ? 'image/jpeg' : mediaKinds[i] == 'video' ? 'video/mp4' : 'audio/mp4',
        sizeBytes: 1024, position: i, createdAt: createdAt,
        encryptionKeyBase64: 'fixture-key-$i',
        encryptionNonce: 'fixture-media-nonce-$i',
        encryptionScheme: 'blob_aes_256_gcm_v1', contentHash: 'f' * 64,
        previewBase64: mediaKinds[i] == 'image' ? 'A' * 4096 : null,
      ),
    ],
  );
  await posts.savePost(post);
  return CreatedLocalPost(post: post, resolvedRecipients: [
    for (final contact in recipients ?? [_contact('peer-bob', 'Bob')])
      CreatedLocalPostRecipient(contact: contact),
  ]);
}

List<Map<String, dynamic>> _photoEncryptRequests(FakeBridge bridge) => bridge
    .sentMessages
    .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
    .where((request) => request['cmd'] == 'message.encrypt')
    .map((request) => request['payload'] as Map<String, dynamic>)
    .toList(growable: false);

String _canonicalPhotoWire(PostModel post, String ciphertext, {
  String kem = 'fake-kem', String nonce = 'fake-nonce',
}) => PostCreateEnvelope.buildEncryptedEnvelope(
  eventId: post.eventId, createdAt: post.createdAt,
  senderPeerId: post.senderPeerId, postId: post.id,
  kem: kem, ciphertext: ciphertext, nonce: nonce,
  metricsOptOut: post.metricsOptOut,
);

class _ThrowOnSecondPhotoEncryptionBridge extends FakeBridge {
  _ThrowOnSecondPhotoEncryptionBridge() : super(initialResponses: {
    'message.encrypt': _canonicalPhotoEncryptResult,
  });
  int encryptionAttempts = 0;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (request['cmd'] == 'message.encrypt' && ++encryptionAttempts == 2) {
      throw StateError('optional compact encryption failed');
    }
    return super.send(message);
  }
}

PostModel _post({
  required String id,
  required String deliveryStatus,
  bool isIncoming = false,
}) {
  return PostModel(
    id: id,
    eventId: 'evt-$id',
    senderPeerId: 'peer-alice',
    authorPeerId: 'peer-alice',
    authorUsername: 'Alice',
    text: 'Hello from Posts',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:00:00.000Z',
    visibleAt: '2026-03-15T10:00:00.000Z',
    expiresAt: '2026-03-18T10:00:00.000Z',
    isIncoming: isIncoming,
    deliveryStatus: deliveryStatus,
  );
}

class _RecordingPostRepository extends InMemoryPostRepository {
  final List<String> writeLog = <String>[];

  @override
  Future<void> savePost(PostModel post) async {
    writeLog.add('post:${post.deliveryStatus}');
    await super.savePost(post);
  }

  @override
  Future<void> saveRecipientDelivery(PostRecipientDelivery delivery) async {
    writeLog.add(
      'delivery:${delivery.recipientPeerId}:${delivery.deliveryStatus}',
    );
    await super.saveRecipientDelivery(delivery);
  }

  void clearWriteLog() {
    writeLog.clear();
  }
}

class _PolicyFakeP2PService extends FakeP2PService {
  final Map<String, _PeerPolicy> policies;
  final List<String> discoverAttempts = <String>[];
  final List<String> dialAttempts = <String>[];
  final Set<String> _dialedPeers = <String>{};

  _PolicyFakeP2PService({
    required super.peerId,
    required super.network,
    this.policies = const <String, _PeerPolicy>{},
  });

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final policy = policies[targetPeerId];
    if (policy?.requireDiscoverAndDialBeforeSend == true &&
        !_dialedPeers.contains(targetPeerId)) {
      return const SendMessageResult(sent: false);
    }
    if (policy?.throwOnSend == true) {
      throw StateError('send failed for $targetPeerId');
    }
    if (policy?.sendResult != null) {
      final sent = policy!.sendResult!;
      return SendMessageResult(
        sent: sent,
        reply: sent ? 'received: $message' : null,
      );
    }
    return super.sendMessageWithReply(
      targetPeerId,
      message,
      timeoutMs: timeoutMs,
    );
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    discoverAttempts.add(peerId);
    return DiscoveredPeer(
      id: peerId,
      addresses: <String>['/ip4/127.0.0.1/tcp/4001/p2p/$peerId'],
    );
  }

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async {
    dialAttempts.add(peerId);
    _dialedPeers.add(peerId);
    return true;
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final policy = policies[toPeerId];
    if (policy?.throwOnInbox == true) {
      throw StateError('inbox failed for $toPeerId');
    }
    if (policy?.storeInInboxResult != null) {
      return policy!.storeInInboxResult!;
    }
    return super.storeInInbox(toPeerId, message);
  }
}

class _PeerPolicy {
  final bool? sendResult;
  final bool? storeInInboxResult;
  final bool throwOnSend = false;
  final bool throwOnInbox;
  final bool requireDiscoverAndDialBeforeSend;

  const _PeerPolicy({
    this.sendResult,
    this.storeInInboxResult,
    this.throwOnInbox = false,
    this.requireDiscoverAndDialBeforeSend = false,
  });
}
