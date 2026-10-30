import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/settings/application/thoughts_metrics_preference_use_cases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

const _todayEnvelope =
    '{"type":"post_create","version":"2","event_id":"evt-1",'
    '"created_at":"2026-10-30T10:00:00.000Z","sender_peer_id":"peer-alice",'
    '"post_id":"post-1","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';

String _envelope({bool? metricsOptOut}) => metricsOptOut == null
    ? PostCreateEnvelope.buildEncryptedEnvelope(
        eventId: 'evt-1',
        createdAt: '2026-10-30T10:00:00.000Z',
        senderPeerId: 'peer-alice',
        postId: 'post-1',
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      )
    : PostCreateEnvelope.buildEncryptedEnvelope(
        eventId: 'evt-1',
        createdAt: '2026-10-30T10:00:00.000Z',
        senderPeerId: 'peer-alice',
        postId: 'post-1',
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
        metricsOptOut: metricsOptOut,
      );

ContactModel _contact(String peerId) => ContactModel(
  peerId: peerId,
  publicKey: 'pk-$peerId',
  rendezvous: '/dns4/example.invalid/tcp/443',
  username: peerId,
  signature: 'sig-$peerId',
  scannedAt: '2026-10-30T10:00:00.000Z',
  mlKemPublicKey: 'mlkem-$peerId',
);

void main() {
  group('post_create envelope', () {
    test('switch on: byte-identical to the envelope before build 129', () {
      expect(_envelope(), _todayEnvelope);
      expect(_envelope(metricsOptOut: false), _todayEnvelope);
    });

    test('switch off: outer key true, outside "encrypted"', () {
      final wire = _envelope(metricsOptOut: true);
      final json = jsonDecode(wire) as Map<String, dynamic>;

      expect(json['thoughts_metrics_opt_out'], true);
      expect(json['encrypted'], {'kem': 'k', 'ciphertext': 'c', 'nonce': 'n'});
      expect(
        wire,
        '${_todayEnvelope.substring(0, _todayEnvelope.length - 1)}'
        ',"thoughts_metrics_opt_out":true}',
      );
      expect(PostCreateEnvelope.parseEncryptedEnvelope(wire), isNotNull);
    });
  });

  group('Thoughts metrics switch', () {
    late FakeP2PNetwork network;
    late FakeP2PService alice;
    late InMemoryPostRepository posts;
    late InMemoryContactRepository contacts;
    late FakeSecureKeyStore store;

    setUp(() {
      network = FakeP2PNetwork();
      alice = FakeP2PService(peerId: 'peer-alice', network: network);
      posts = InMemoryPostRepository();
      contacts = InMemoryContactRepository()..addTestContact(_contact('bob'));
      store = FakeSecureKeyStore();
    });

    tearDown(() => posts.dispose());

    Future<CreatedLocalPost> createThought() async {
      final (result, created) = await createLocalPost(
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'Thought',
        audience: PostAudience.allFriends(),
        secureKeyStore: store,
      );
      expect(result, SendPostResult.success);
      return created!;
    }

    Future<void> send(CreatedLocalPost created) => PostDeliveryRunner(
      p2pService: alice,
      postRepo: posts,
      bridge: FakeBridge(),
    ).execute(created);

    Map<String, dynamic> bobWire() =>
        jsonDecode(network.retrieveInbox('bob').single['message'] as String)
            as Map<String, dynamic>;

    Future<int> retry() => retryPendingPostDeliveries(
      postRepo: posts,
      contactRepo: contacts,
      p2pService: alice,
      bridge: FakeBridge(),
      accountMigrationNetworkGate: ({peerId, required operation}) async => true,
    );

    test('default on: no stored value, unmarked row, no key', () async {
      expect(await loadThoughtsMetricsEnabled(secureKeyStore: store), isTrue);
      final created = await createThought();
      expect((await posts.getPost(created.post.id))!.metricsOptOut, isFalse);

      await send(created);

      expect(bobWire().containsKey('thoughts_metrics_opt_out'), isFalse);
    });

    test(
      'created while off: row marked and the envelope carries the key',
      () async {
        await saveThoughtsMetricsEnabled(secureKeyStore: store, enabled: false);
        final created = await createThought();
        expect((await posts.getPost(created.post.id))!.metricsOptOut, isTrue);

        await send(created);

        expect(bobWire()['thoughts_metrics_opt_out'], true);
      },
    );

    test('a retry after switching off carries the key', () async {
      network.inboxDisabled = true;
      final created = await createThought();
      await send(created);
      expect((await posts.getPost(created.post.id))!.deliveryStatus, 'failed');

      await saveThoughtsMetricsEnabled(
        secureKeyStore: store,
        enabled: false,
        postRepository: posts,
      );
      expect((await posts.getPost(created.post.id))!.metricsOptOut, isTrue);

      network.inboxDisabled = false;
      expect(await retry(), 1);

      expect(bobWire()['thoughts_metrics_opt_out'], true);
    });

    test('switching on does not clear the mark', () async {
      network.inboxDisabled = true;
      final created = await createThought();
      await send(created);
      await saveThoughtsMetricsEnabled(
        secureKeyStore: store,
        enabled: false,
        postRepository: posts,
      );

      await saveThoughtsMetricsEnabled(
        secureKeyStore: store,
        enabled: true,
        postRepository: posts,
      );

      expect(await loadThoughtsMetricsEnabled(secureKeyStore: store), isTrue);
      expect((await posts.getPost(created.post.id))!.metricsOptOut, isTrue);
      network.inboxDisabled = false;
      expect(await retry(), 1);
      expect(bobWire()['thoughts_metrics_opt_out'], true);
    });
  });

  group('Thoughts metrics ordering', () {
    late FakeP2PNetwork network;
    late FakeP2PService alice;
    late _GatedPostRepository posts;
    late InMemoryContactRepository contacts;
    late FakeSecureKeyStore store;

    setUp(() {
      network = FakeP2PNetwork();
      alice = FakeP2PService(peerId: 'peer-alice', network: network);
      posts = _GatedPostRepository();
      contacts = InMemoryContactRepository()..addTestContact(_contact('bob'));
      store = FakeSecureKeyStore();
    });

    tearDown(() => posts.dispose());

    Future<(SendPostResult, CreatedLocalPost?)> create() => createLocalPost(
      postRepo: posts,
      contactRepo: contacts,
      senderPeerId: 'peer-alice',
      senderUsername: 'Alice',
      text: 'Thought',
      audience: PostAudience.allFriends(),
      secureKeyStore: store,
    );

    Map<String, dynamic> bobWire() =>
        jsonDecode(network.retrieveInbox('bob').single['message'] as String)
            as Map<String, dynamic>;

    test(
      'a Thought saved while switching off is marked and sends the key',
      () async {
        posts.holdSave = Completer<void>();
        final creating = create();
        await posts.saveReached.future;

        final off = saveThoughtsMetricsEnabled(
          secureKeyStore: store,
          enabled: false,
          postRepository: posts,
        );
        await pumpEventQueue();
        expect(await loadThoughtsMetricsEnabled(secureKeyStore: store), isTrue);

        posts.holdSave!.complete();
        final (result, created) = await creating;
        await off;

        expect(result, SendPostResult.success);
        expect((await posts.getPost(created!.post.id))!.metricsOptOut, isTrue);
        await PostDeliveryRunner(
          p2pService: alice,
          postRepo: posts,
          bridge: FakeBridge(),
        ).execute(created);
        expect(bobWire()['thoughts_metrics_opt_out'], true);
      },
    );

    test('a Thought created while switching off reads off', () async {
      posts.holdMark = Completer<void>();
      final off = saveThoughtsMetricsEnabled(
        secureKeyStore: store,
        enabled: false,
        postRepository: posts,
      );
      await posts.markReached.future;

      final creating = create();
      await pumpEventQueue();
      expect(posts.saved, isEmpty);

      posts.holdMark!.complete();
      await off;
      final (_, created) = await creating;

      expect((await posts.getPost(created!.post.id))!.metricsOptOut, isTrue);
    });

    test('a failed off keeps the switch on', () async {
      posts.failMark = true;

      await expectLater(
        saveThoughtsMetricsEnabled(
          secureKeyStore: store,
          enabled: false,
          postRepository: posts,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await loadThoughtsMetricsEnabled(secureKeyStore: store), isTrue);
    });
  });

  group('posts table', () {
    late Database db;
    late PostRepositoryImpl posts;

    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
        ),
      );
      posts = PostRepositoryImpl(
        dbInsertPost: (row) => dbInsertPost(db, row),
        dbLoadPost: (postId) => dbLoadPost(db, postId),
        dbLoadPostsFeed: () => dbLoadPostsFeed(db),
        dbLoadRetryableOutgoingPosts: () => dbLoadRetryableOutgoingPosts(db),
        dbUpsertRecipientDelivery: (row) =>
            dbUpsertPostRecipientDelivery(db, row),
        dbLoadRecipientDeliveries: (postId) =>
            dbLoadPostRecipientDeliveries(db, postId),
        dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
      );
    });

    tearDown(() => db.close());

    PostModel thought(String id, String deliveryStatus) {
      final now = DateTime.now().toUtc();
      return PostModel(
        id: id,
        eventId: 'evt-$id',
        senderPeerId: 'peer-alice',
        authorPeerId: 'peer-alice',
        authorUsername: 'Alice',
        text: 'Thought',
        audience: PostAudience.allFriends(),
        createdAt: now.toIso8601String(),
        visibleAt: now.toIso8601String(),
        expiresAt: now.add(const Duration(hours: 24)).toIso8601String(),
        isIncoming: false,
        deliveryStatus: deliveryStatus,
      );
    }

    Future<Map<String, Object?>> row(String id) async => (await db.query(
      'posts',
      columns: ['metrics_opt_out', 'delivery_status'],
      where: 'post_id = ?',
      whereArgs: [id],
    )).single;

    test(
      'marks only undelivered own Thoughts; an older copy keeps the mark',
      () async {
        final pending = thought('pending', 'sending');
        await posts.savePost(pending);
        await posts.savePost(thought('sent', 'sent'));

        await posts.markUndeliveredOwnThoughtsMetricsOptOut();

        expect(await row('pending'), {
          'metrics_opt_out': 1,
          'delivery_status': 'sending',
        });
        expect(await row('sent'), {
          'metrics_opt_out': 0,
          'delivery_status': 'sent',
        });

        // A fanout still holding the unmarked copy persists its status.
        await posts.savePost(pending.copyWith(deliveryStatus: 'partial'));

        expect(await row('pending'), {
          'metrics_opt_out': 1,
          'delivery_status': 'partial',
        });
        expect((await posts.getPost('pending'))!.metricsOptOut, isTrue);
      },
    );

    PostRepositoryImpl failingMarks() => PostRepositoryImpl(
      dbInsertPost: (row) async {
        if (row.length == 2 && row.containsKey('metrics_opt_out')) {
          throw StateError('disk full');
        }
        await dbInsertPost(db, row);
      },
      dbLoadPost: (postId) => dbLoadPost(db, postId),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db),
      dbLoadRetryableOutgoingPosts: () => dbLoadRetryableOutgoingPosts(db),
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (postId) =>
          dbLoadPostRecipientDeliveries(db, postId),
      dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
    );

    test('a mark that fails on a live Thought is reported', () async {
      await posts.savePost(thought('pending', 'sending'));

      await expectLater(
        failingMarks().markUndeliveredOwnThoughtsMetricsOptOut(),
        throwsA(isA<StateError>()),
      );
      expect(await row('pending'), {
        'metrics_opt_out': 0,
        'delivery_status': 'sending',
      });
    });

    test('a Thought deleted before its mark is skipped', () async {
      await posts.savePost(thought('gone', 'sending'));
      final repo = PostRepositoryImpl(
        dbInsertPost: (row) async {
          if (row.length == 2 && row.containsKey('metrics_opt_out')) {
            await db.delete('posts', where: 'post_id = ?', whereArgs: ['gone']);
            throw StateError('no such row');
          }
          await dbInsertPost(db, row);
        },
        dbLoadPost: (postId) => dbLoadPost(db, postId),
        dbLoadPostsFeed: () => dbLoadPostsFeed(db),
        dbLoadRetryableOutgoingPosts: () => dbLoadRetryableOutgoingPosts(db),
        dbUpsertRecipientDelivery: (row) =>
            dbUpsertPostRecipientDelivery(db, row),
        dbLoadRecipientDeliveries: (postId) =>
            dbLoadPostRecipientDeliveries(db, postId),
        dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
      );

      await repo.markUndeliveredOwnThoughtsMetricsOptOut();

      expect(await repo.getPost('gone'), isNull);
    });
  });
}

class _GatedPostRepository extends InMemoryPostRepository {
  Completer<void>? holdSave;
  final saveReached = Completer<void>();
  Completer<void>? holdMark;
  final markReached = Completer<void>();
  bool failMark = false;
  final saved = <String>[];

  @override
  Future<void> savePost(PostModel post) async {
    final hold = holdSave;
    if (hold != null && !post.isIncoming && !saveReached.isCompleted) {
      saveReached.complete();
      await hold.future;
    }
    saved.add(post.id);
    await super.savePost(post);
  }

  @override
  Future<void> markUndeliveredOwnThoughtsMetricsOptOut() async {
    if (failMark) throw StateError('disk full');
    final hold = holdMark;
    if (hold != null) {
      markReached.complete();
      await hold.future;
    }
    await super.markUndeliveredOwnThoughtsMetricsOptOut();
  }
}
