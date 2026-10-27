import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_follow_on_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/thought_views_db_helpers.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_thought_view_use_case.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/application/publish_thought_view_use_case.dart';
import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_view_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/thought_view_receipt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/recording_fake_bridge.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';

const _postId = 'thought-1';
const _author = 'author-peer';
const _viewer = 'viewer-peer';

void main() {
  late Directory directory;
  late MediaRepositoryRealDbFixture fixture;
  late PostRepositoryImpl posts;
  late FakeContactRepository contacts;
  late FakeP2PNetwork network;
  late _InspectingService service;
  late RecordingFakeBridge bridge;
  late DateTime now;
  late DateTime created;
  late Map<String, Map<String, dynamic>> innerByCiphertext;

  ContactModel contact(
    String peer, {
    String? key = 'test-mlkem-key',
    bool blocked = false,
  }) => ContactModel(
    peerId: peer,
    publicKey: 'public-key-$peer',
    rendezvous: 'test-rendezvous',
    username: peer,
    signature: 'test-signature',
    scannedAt: created.toIso8601String(),
    mlKemPublicKey: key,
    isBlocked: blocked,
  );

  String encrypt(Map<String, dynamic>? request) {
    final ciphertext = 'opaque-view-ciphertext-${innerByCiphertext.length + 1}';
    innerByCiphertext[ciphertext] =
        jsonDecode(request!['plaintext'] as String) as Map<String, dynamic>;
    return jsonEncode({
      'ok': true,
      'kem': 'test-kem',
      'ciphertext': ciphertext,
      'nonce': 'test-nonce',
    });
  }

  PostRepositoryImpl repository() {
    final db = fixture.db;
    return PostRepositoryImpl(
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (id) => dbLoadPost(db, id, nowProvider: () => now),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db, nowProvider: () => now),
      dbDeletePostCascade: (id) => dbDeletePostCascade(db, id),
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (id) => dbLoadPostRecipientDeliveries(db, id),
      dbMarkPostFocused: (id) => dbMarkPostFocused(db, id),
      dbLoadThoughtViews: (id) => dbLoadThoughtViews(db, id),
      dbQueueThoughtView:
          ({
            required receipt,
            required event,
            required recipient,
            required authorPeerId,
            required nowIso,
          }) => dbQueueThoughtView(
            db,
            receipt: receipt,
            event: event,
            recipient: recipient,
            authorPeerId: authorPeerId,
            nowIso: nowIso,
          ),
      dbRecordIncomingThoughtView:
          ({required receipt, required localPeerId, required nowIso}) =>
              dbRecordIncomingThoughtView(
                db,
                receipt: receipt,
                localPeerId: localPeerId,
                nowIso: nowIso,
              ),
      dbLoadFollowOnOutboxEvent: (id) => dbLoadPostFollowOnOutboxEvent(db, id),
      dbDeleteFollowOnOutboxEvent: (id) =>
          dbDeletePostFollowOnOutboxEvent(db, id),
      dbUpsertFollowOnOutboxRecipientDelivery: (row) =>
          dbUpsertPostFollowOnOutboxRecipientDelivery(db, row),
      dbLoadFollowOnOutboxRecipientDeliveries: (id) =>
          dbLoadPostFollowOnOutboxRecipientDeliveries(db, id),
      dbLoadRetryableFollowOnOutboxEvents: () =>
          dbLoadRetryablePostFollowOnOutboxEvents(db),
      dbLoadRetryableFollowOnOutboxRecipientDeliveries: (ids) =>
          dbLoadRetryablePostFollowOnOutboxRecipientDeliveries(db, ids),
    );
  }

  setUp(() async {
    now = DateTime.now().toUtc();
    created = now.subtract(const Duration(hours: 1));
    directory = await Directory.systemTemp.createTemp('thought-view-delivery-');
    fixture = await MediaRepositoryRealDbFixture.create(
      databasePath: '${directory.path}/views.sqlite',
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
    );
    posts = repository();
    contacts = FakeContactRepository()
      ..seed([contact(_author), contact(_viewer)]);
    network = FakeP2PNetwork();
    service = _InspectingService(peerId: _viewer, network: network);
    innerByCiphertext = {};
    bridge = RecordingFakeBridge()
      ..whenCommand('message.encrypt', encrypt)
      ..whenCommand('message.decrypt', (request) {
        final inner = innerByCiphertext[request?['ciphertext']];
        return jsonEncode({
          'ok': inner != null,
          if (inner != null) 'plaintext': jsonEncode(inner),
        });
      });
  });

  tearDown(() async {
    posts.dispose();
    service.dispose();
    await fixture.dispose();
    await directory.delete(recursive: true);
  });

  Future<PostModel> seed({bool incoming = true}) async {
    final thought = PostModel(
      id: _postId,
      eventId: 'thought-event',
      senderPeerId: _author,
      authorPeerId: _author,
      authorUsername: 'Sam',
      text: 'At the lake',
      audience: PostAudience.allFriends(),
      createdAt: created.toIso8601String(),
      visibleAt: created.toIso8601String(),
      expiresAt: created.add(const Duration(hours: 24)).toIso8601String(),
      isIncoming: incoming,
    );
    await posts.savePost(thought);
    return thought;
  }

  Future<void> originalRecipient(String peer) => posts.saveRecipientDelivery(
    PostRecipientDelivery(
      postId: _postId,
      recipientPeerId: peer,
      deliveryStatus: 'inbox',
      lastAttemptAt: created.toIso8601String(),
      deliveryPath: 'inbox',
      createdAt: created.toIso8601String(),
      updatedAt: created.toIso8601String(),
    ),
  );

  Future<void> publish() => publishThoughtView(
    postId: _postId,
    viewerPeerId: _viewer,
    postRepo: posts,
    contactRepo: contacts,
    p2pService: service,
    bridge: bridge,
    nowProvider: () => now,
  );

  Future<ChatMessage> message({String viewer = _viewer}) async {
    final raw = await PostViewEnvelope(
      eventId: 'view-$viewer-${innerByCiphertext.length}',
      receipt: ThoughtViewReceipt(
        postId: _postId,
        viewerPeerId: viewer,
        viewedAt: now.toIso8601String(),
      ),
      postCreatedAt: created,
    ).toEncryptedJson(bridge: bridge, recipientMlKemPublicKey: 'author-key');
    return ChatMessage(
      from: viewer,
      to: _author,
      content: raw,
      timestamp: now.toIso8601String(),
      isIncoming: true,
      transport: 'direct',
    );
  }

  Future<bool> receive(ChatMessage incoming) => handleIncomingThoughtView(
    message: incoming,
    localPeerId: _author,
    postRepo: posts,
    contactRepo: contacts,
    bridge: bridge,
    ownMlKemSecretKey: 'author-secret-key',
    nowProvider: () => now,
  );

  test('a first view encrypts and commits before any relay fallback', () async {
    await seed();
    bridge.whenCommand('message.encrypt', (request) async {
      expect(await posts.loadThoughtViews(_postId), isEmpty);
      expect(await fixture.db.query('post_follow_on_outbox_events'), isEmpty);
      return encrypt(request);
    });
    var transportChecks = 0;
    service.beforeStore = (recipient, wire) async {
      transportChecks++;
      expect(recipient, _author);
      final views = await posts.loadThoughtViews(_postId);
      expect(views.single.viewerPeerId, _viewer);
      final event = (await fixture.db.query(
        'post_follow_on_outbox_events',
      )).single;
      final delivery = (await fixture.db.query(
        'post_follow_on_outbox_recipient_deliveries',
      )).single;
      expect(event['raw_envelope'], wire);
      expect(event['event_type'], PostViewEnvelope.type);
      expect(delivery['event_id'], event['event_id']);
      expect(delivery['recipient_peer_id'], _author);
      expect(delivery['delivery_status'], 'pending');
      final outer = jsonDecode(wire) as Map<String, dynamic>;
      expect(outer['version'], '2');
      expect(outer.containsKey('payload'), isFalse);
      expect(
        (outer['encrypted'] as Map<String, dynamic>)['ciphertext'],
        startsWith('opaque-view-ciphertext-'),
      );
    };

    await publish();

    expect(transportChecks, 1);
    expect(innerByCiphertext.values.single['viewer_peer_id'], _viewer);
    expect(network.deliverCallCount, 0);
    expect(network.inboxCount(_author), 1);
    expect(await posts.loadThoughtViews(_postId), hasLength(1));
    expect(await fixture.db.query('post_follow_on_outbox_events'), isEmpty);
    expect(
      await fixture.db.query('post_follow_on_outbox_recipient_deliveries'),
      isEmpty,
    );
  });

  test(
    'offline first view survives reopen, deduplicates, and retries its exact event',
    () async {
      await seed();
      network.inboxDisabled = true;
      await publish();
      final event = (await fixture.db.query(
        'post_follow_on_outbox_events',
      )).single;
      final wire = event['raw_envelope'] as String;
      expect(
        (await posts.loadThoughtViews(_postId)).single.viewerPeerId,
        _viewer,
      );
      expect(
        (await fixture.db.query(
          'post_follow_on_outbox_recipient_deliveries',
        )).single['delivery_status'],
        'failed',
      );
      final storesBeforeDuplicate = network.storeInInboxCallCount;

      posts.dispose();
      fixture = await fixture.reopen();
      posts = repository();
      await publish();

      expect(network.storeInInboxCallCount, storesBeforeDuplicate);
      expect(innerByCiphertext, hasLength(1));
      expect(
        (await fixture.db.query('post_follow_on_outbox_events')).single,
        event,
      );
      network.inboxDisabled = false;
      expect(
        await retryPendingPostFollowOns(
          postRepo: posts,
          p2pService: service,
          nowProvider: () => now,
        ),
        1,
      );
      expect(network.retrieveInbox(_author).single['message'], wire);
      expect(await fixture.db.query('post_follow_on_outbox_events'), isEmpty);
      expect(
        await fixture.db.query('post_follow_on_outbox_recipient_deliveries'),
        isEmpty,
      );
      expect(await posts.loadThoughtViews(_postId), hasLength(1));
      await publish();
      expect(innerByCiphertext, hasLength(1));
      expect(network.storeInInboxCallCount, storesBeforeDuplicate + 1);
    },
  );

  test(
    'missing keys and encryption failure cannot mark a view or send plaintext',
    () async {
      await seed();
      contacts.seed([contact(_author, key: null)]);
      await publish();
      expect(bridge.calledCommands, isEmpty);
      contacts.seed([contact(_author)]);
      bridge.whenCommand('message.encrypt', (_) => jsonEncode({'ok': false}));

      await expectLater(publish(), throwsStateError);

      expect(await posts.loadThoughtViews(_postId), isEmpty);
      expect(await fixture.db.query('post_follow_on_outbox_events'), isEmpty);
      expect(
        await fixture.db.query('post_follow_on_outbox_recipient_deliveries'),
        isEmpty,
      );
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'an authenticated original recipient records one first view and publishes its change',
    () async {
      await seed(incoming: false);
      await originalRecipient(_viewer);
      expect(await posts.loadThoughtViews(_postId), isEmpty);
      final incoming = await message();
      final firstViewedAt = now.toIso8601String();
      final changed = posts.postChanges.first;

      expect(await receive(incoming), isTrue);
      expect(await changed, _postId);
      now = now.add(const Duration(minutes: 1));
      expect(await receive(await message()), isFalse);

      final views = await posts.loadThoughtViews(_postId);
      expect(views, hasLength(1));
      expect(views.single.viewerPeerId, _viewer);
      expect(views.single.viewedAt, firstViewedAt);
      expect(await fixture.db.query('post_follow_on_outbox_events'), isEmpty);
    },
  );

  test(
    'blocked, unknown, and out-of-snapshot viewers cannot claim activity',
    () async {
      await seed(incoming: false);
      for (final peer in ['blocked-peer', 'unknown-peer']) {
        await originalRecipient(peer);
      }
      contacts.seed([
        contact(_author),
        contact('blocked-peer', blocked: true),
        contact('outside-peer'),
      ]);
      for (final peer in ['blocked-peer', 'unknown-peer', 'outside-peer']) {
        expect(
          await receive(await message(viewer: peer)),
          isFalse,
          reason: peer,
        );
      }
      expect(await posts.loadThoughtViews(_postId), isEmpty);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  for (final expire in [false, true]) {
    test(
      '${expire ? 'expiry' : 'retirement'} winning during decryption cannot resurrect a view',
      () async {
        final thought = await seed(incoming: false);
        await originalRecipient(_viewer);
        final incoming = await message();
        final outer = jsonDecode(incoming.content) as Map<String, dynamic>;
        final ciphertext =
            (outer['encrypted'] as Map<String, dynamic>)['ciphertext'];
        final plaintext = jsonEncode(innerByCiphertext[ciphertext]);
        final entered = Completer<void>();
        final decrypt = Completer<String>();
        addTearDown(() {
          if (!decrypt.isCompleted) {
            decrypt.complete(jsonEncode({'ok': true, 'plaintext': plaintext}));
          }
        });
        bridge.whenCommand('message.decrypt', (_) {
          entered.complete();
          return decrypt.future;
        });
        final pending = receive(incoming);
        await entered.future;
        if (expire) {
          now = DateTime.parse(thought.expiresAt);
        } else {
          await posts.deletePostCascade(_postId);
        }
        decrypt.complete(jsonEncode({'ok': true, 'plaintext': plaintext}));

        expect(await pending, isFalse);
        expect(await posts.loadThoughtViews(_postId), isEmpty);
        expect(await fixture.db.query('post_follow_on_outbox_events'), isEmpty);
      },
    );
  }
}

class _InspectingService extends FakeP2PService {
  _InspectingService({required super.peerId, required super.network});

  Future<void> Function(String recipient, String wire)? beforeStore;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    await beforeStore?.call(toPeerId, message);
    return super.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
  }
}
