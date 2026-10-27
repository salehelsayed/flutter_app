import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/authored_direct_text_intent.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/posts/application/send_thought_reply_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/recording_fake_bridge.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _local = 'local-peer-0001';
const _author = 'author-peer-0001';
const _postId = 'thought-1';
const _messageId = '8ad53b87-3d4f-4abd-9f55-52ae557979c6';
const _quoteId = 'thought:thought-1';

void main() {
  late Directory directory;
  late MediaRepositoryRealDbFixture fixture;
  late InMemoryPostRepository posts;
  late FakeContactRepository contacts;
  late FakeIdentityRepository identities;
  late FakeP2PNetwork network;
  late _NodeControlledService service;
  late FakeP2PService authorService;
  late RecordingFakeBridge bridge;
  late DateTime now;
  late ContactModel author;
  late PostModel thought;
  late List<Map<String, dynamic>> encryptedPayloads;

  void allowEncryption() {
    bridge.whenCommand('message.encrypt', (request) {
      encryptedPayloads.add(
        jsonDecode(request!['plaintext'] as String) as Map<String, dynamic>,
      );
      return jsonEncode({
        'ok': true,
        'kem': 'test-kem',
        'ciphertext': 'opaque-test-ciphertext-${encryptedPayloads.length}',
        'nonce': 'test-nonce',
      });
    });
  }

  setUp(() async {
    now = DateTime.now().toUtc();
    directory = await Directory.systemTemp.createTemp('thought-reply-');
    fixture = await MediaRepositoryRealDbFixture.create(
      databasePath: '${directory.path}/messages.sqlite',
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
    );
    posts = InMemoryPostRepository();
    contacts = FakeContactRepository();
    identities = FakeIdentityRepository()
      ..seed(FakeIdentityRepository.makeIdentity(peerId: _local));
    author = ContactModel(
      peerId: _author,
      publicKey: 'author-public-key',
      rendezvous: 'test-rendezvous',
      username: 'Sam',
      signature: 'test-signature',
      scannedAt: now.toIso8601String(),
      mlKemPublicKey: 'author-mlkem-key',
    );
    contacts.seed([author]);
    await fixture.db.insert('contacts', author.toMap());
    await fixture.db.insert('identity', {
      'id': 1,
      'peer_id': _local,
      'public_key': 'local-public-key',
      'username': 'Me',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    thought = PostModel(
      id: _postId,
      eventId: 'thought-event',
      senderPeerId: _author,
      authorPeerId: _author,
      authorUsername: 'Sam',
      text: 'At the lake',
      audience: PostAudience.allFriends(),
      createdAt: now.subtract(const Duration(hours: 1)).toIso8601String(),
      visibleAt: now.subtract(const Duration(hours: 1)).toIso8601String(),
      expiresAt: now.add(const Duration(hours: 23)).toIso8601String(),
      isIncoming: true,
    );
    await posts.savePost(thought);
    network = FakeP2PNetwork();
    service = _NodeControlledService(peerId: _local, network: network)
      ..connectedPeers.add(_author);
    authorService = FakeP2PService(peerId: _author, network: network);
    bridge = RecordingFakeBridge();
    encryptedPayloads = [];
    allowEncryption();
  });

  tearDown(() async {
    posts.dispose();
    service.dispose();
    authorService.dispose();
    await fixture.dispose();
    await directory.delete(recursive: true);
  });

  Future<ThoughtReplyStatus> send({
    String id = _messageId,
    String postId = _postId,
    String authorId = _author,
    String text = 'Count me in',
  }) => sendThoughtReply(
    messageId: id,
    postId: postId,
    authorPeerId: authorId,
    text: text,
    postRepo: posts,
    messageRepo: fixture.messageRepo,
    identityRepo: identities,
    contactRepo: contacts,
    p2pService: service,
    bridge: bridge,
    nowProvider: () => now,
  );

  Future<void> expectNoEgressOrIntent() async {
    expect(await fixture.db.query('messages'), isEmpty);
    expect(await fixture.messageRepo.loadAuthoredDirectTextIntents(), isEmpty);
    expect(encryptedPayloads, isEmpty);
    expect(network.deliverCallCount, 0);
    expect(network.storeInInboxCallCount, 0);
  }

  test(
    'offline authored reply survives reopen and retries the same action',
    () async {
      service.started = false;
      bridge.whenCommand('message.encrypt', (_) => jsonEncode({'ok': false}));

      expect(await send(text: '  Count me in  '), ThoughtReplyStatus.queued);
      final intent =
          (await fixture.messageRepo.loadAuthoredDirectTextIntents()).single;
      expect(intent.id, _messageId);
      expect(intent.text, 'Count me in');
      expect(intent.contactPeerId, _author);
      expect(intent.quotedMessageId, _quoteId);
      expect(await fixture.db.query('messages'), isEmpty);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);

      fixture = await fixture.reopen();
      final reopened =
          (await fixture.messageRepo.loadAuthoredDirectTextIntents()).single;
      expect(reopened.toMap(), intent.toMap());
      service.started = true;
      allowEncryption();

      expect(await send(), ThoughtReplyStatus.sent);
      final rows = await fixture.db.query('messages');
      expect(rows, hasLength(1));
      expect(rows.single['id'], _messageId);
      expect(rows.single['quoted_message_id'], _quoteId);
      expect(rows.single['text'], 'Count me in');
      expect(
        await fixture.messageRepo.loadAuthoredDirectTextIntents(),
        isEmpty,
      );
      expect(encryptedPayloads.single['id'], _messageId);
      expect(encryptedPayloads.single['quotedMessageId'], _quoteId);

      expect(await send(), ThoughtReplyStatus.sent);
      expect(await fixture.db.query('messages'), hasLength(1));
      expect(encryptedPayloads, hasLength(1));
    },
  );

  test(
    'fresh reply refuses egress until message and encrypted custody commit together',
    () async {
      await fixture.db.execute('''
        CREATE TRIGGER reject_thought_reply_custody
        BEFORE INSERT ON direct_inbox_custody_outbox
        BEGIN
          SELECT RAISE(ABORT, 'test-only custody admission refusal');
        END
      ''');

      expect(await send(), ThoughtReplyStatus.queued);
      final intent =
          (await fixture.messageRepo.loadAuthoredDirectTextIntents()).single;
      expect(intent.id, _messageId);
      expect(intent.quotedMessageId, _quoteId);
      expect(await fixture.db.query('messages'), isEmpty);
      expect(await fixture.messageRepo.loadDirectInboxCustody(), isEmpty);
      expect(encryptedPayloads, hasLength(1));
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);

      fixture = await fixture.reopen();
      expect(
        (await fixture.messageRepo.loadAuthoredDirectTextIntents()).single
            .toMap(),
        intent.toMap(),
      );
      await fixture.db.execute('DROP TRIGGER reject_thought_reply_custody');
      expect(await send(), ThoughtReplyStatus.sent);
      final message = (await fixture.messageRepo.getMessage(_messageId))!;
      expect(message.text, intent.text);
      expect(message.quotedMessageId, _quoteId);
      expect(await fixture.db.query('messages'), hasLength(1));
      expect(
        await fixture.messageRepo.loadAuthoredDirectTextIntents(),
        isEmpty,
      );
      // A live ACK does not discharge the independent inbox obligation.
      final custody =
          (await fixture.messageRepo.loadDirectInboxCustody()).single;
      expect(custody.messageId, _messageId);
      expect(custody.recipientPeerId, _author);
      // Ciphertext belongs to the immutable custody owner, independently of
      // the mutable chat-message projection.
      final envelope = jsonDecode(custody.wireEnvelope) as Map<String, dynamic>;
      expect(envelope['type'], 'chat_message');
      expect(envelope['version'], '2');
      expect(envelope['id'], _messageId);
      expect(envelope['senderPeerId'], _local);
      expect(envelope.containsKey('payload'), isFalse);
      expect(envelope['encrypted']['ciphertext'], 'opaque-test-ciphertext-2');
      expect(encryptedPayloads.last['quotedMessageId'], _quoteId);
      expect(message.status, 'delivered');
      expect(encryptedPayloads, hasLength(2));

      fixture = await fixture.reopen();
      expect(
        (await fixture.messageRepo.loadDirectInboxCustody()).single.toMap(),
        custody.toMap(),
      );
      expect(
        await drainDirectInboxCustodyOutbox(
          custodyRepository: fixture.messageRepo,
          storeInAckCustodyInboxDetailed:
              service.storeInAckCustodyInboxDetailed,
        ),
        1,
      );
      expect(await fixture.messageRepo.loadDirectInboxCustody(), isEmpty);
      expect(
        network.retrieveInbox(_author).single['message'],
        custody.wireEnvelope,
      );
      expect(
        (await fixture.messageRepo.getMessage(_messageId))!.status,
        'delivered',
      );
      expect(encryptedPayloads, hasLength(2));
      final deliveries = network.deliverCallCount;
      final stores = network.storeInInboxCallCount;
      final encryptions = encryptedPayloads.length;

      expect(await send(), ThoughtReplyStatus.sent);
      expect(await fixture.db.query('messages'), hasLength(1));
      expect(network.deliverCallCount, deliveries);
      expect(network.storeInInboxCallCount, stores);
      expect(encryptedPayloads, hasLength(encryptions));
    },
  );

  test(
    'failed staged reply retries its exact encrypted custody without a new message',
    () async {
      service.started = false;

      expect(await send(), ThoughtReplyStatus.failed);
      final failed = (await fixture.messageRepo.getMessage(_messageId))!;
      expect(failed.status, 'failed');
      final custody =
          (await fixture.messageRepo.loadDirectInboxCustody()).single;
      final envelope = custody.wireEnvelope;
      expect(jsonDecode(envelope)['version'], '2');
      expect(jsonDecode(envelope).containsKey('payload'), isFalse);
      expect(encryptedPayloads, hasLength(1));

      // The retry must replay committed ciphertext; changed encryption output
      // would expose a forbidden reconstruction if it were called again.
      bridge.whenCommand(
        'message.encrypt',
        (_) => throw StateError('must not re-encrypt'),
      );
      service.started = true;

      expect(await send(), ThoughtReplyStatus.sent);
      final settled = (await fixture.messageRepo.getMessage(_messageId))!;
      expect(settled.status, 'inboxed');
      expect(await fixture.db.query('messages'), hasLength(1));
      expect(await fixture.messageRepo.loadDirectInboxCustody(), isEmpty);
      expect(network.retrieveInbox(_author).single['message'], envelope);
      expect(encryptedPayloads, hasLength(1));
    },
  );

  test(
    'encryption failure retains the authored reply and sends no plaintext',
    () async {
      bridge.whenCommand(
        'message.encrypt',
        (_) => jsonEncode({'ok': false, 'errorCode': 'KEY_UNAVAILABLE'}),
      );

      expect(await send(), ThoughtReplyStatus.queued);
      expect(
        await fixture.messageRepo.loadAuthoredDirectTextIntents(),
        hasLength(1),
      );
      expect(await fixture.db.query('messages'), isEmpty);
      expect(await fixture.messageRepo.loadDirectInboxCustody(), isEmpty);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test('an accepted reaction is an ordinary quoted chat message', () async {
    expect(await send(text: '🔥'), ThoughtReplyStatus.sent);
    final message = (await fixture.messageRepo.getMessage(_messageId))!;
    expect(message.text, '🔥');
    expect(message.quotedMessageId, _quoteId);
    expect(message.isIncoming, isFalse);
    expect(message.contactPeerId, _author);
    expect(encryptedPayloads.single['text'], '🔥');
    expect(encryptedPayloads.single['quotedMessageId'], _quoteId);
    expect(await fixture.db.query('post_reactions'), isEmpty);
  });

  test('empty text or identifiers never admit a durable action', () async {
    expect(await send(text: ' \n '), ThoughtReplyStatus.failed);
    expect(await send(id: ''), ThoughtReplyStatus.failed);
    expect(await send(postId: ''), ThoughtReplyStatus.failed);
    await expectNoEgressOrIntent();
  });

  test(
    'a missing encryption key retains the reply without any egress',
    () async {
      contacts.seed([
        ContactModel(
          peerId: _author,
          publicKey: author.publicKey,
          rendezvous: author.rendezvous,
          username: author.username,
          signature: author.signature,
          scannedAt: author.scannedAt,
        ),
      ]);

      expect(await send(), ThoughtReplyStatus.queued);
      expect(
        await fixture.messageRepo.loadAuthoredDirectTextIntents(),
        hasLength(1),
      );
      expect(await fixture.db.query('messages'), isEmpty);
      expect(bridge.calledCommands, isEmpty);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  for (final blocked in [true, false]) {
    test(
      '${blocked ? 'blocked' : 'archived'} author cannot receive a card reply',
      () async {
        contacts.seed([
          author.copyWith(isBlocked: blocked, isArchived: !blocked),
        ]);

        expect(await send(), ThoughtReplyStatus.failed);
        await expectNoEgressOrIntent();
      },
    );
  }

  test('a retired thought cannot admit a fresh reply', () async {
    await posts.deletePostCascade(_postId);

    expect(await send(), ThoughtReplyStatus.failed);
    await expectNoEgressOrIntent();
  });

  test('a thought at its exact expiry cannot admit a fresh reply', () async {
    now = DateTime.parse(thought.expiresAt);

    expect(await send(), ThoughtReplyStatus.failed);
    await expectNoEgressOrIntent();
  });

  test('own thought and a crossed author cannot admit a reply', () async {
    expect(await send(authorId: 'different-author'), ThoughtReplyStatus.failed);
    await posts.savePost(thought.copyWith(isIncoming: false));
    expect(await send(), ThoughtReplyStatus.failed);
    await expectNoEgressOrIntent();
  });

  test('retry refuses a message ID already used by another action', () async {
    final original = ConversationMessage(
      id: _messageId,
      contactPeerId: _author,
      senderPeerId: _local,
      text: 'A different reply',
      quotedMessageId: _quoteId,
      timestamp: now.toIso8601String(),
      createdAt: now.toIso8601String(),
      status: 'failed',
      isIncoming: false,
    );
    await fixture.db.insert('messages', original.toMap());

    expect(await send(), ThoughtReplyStatus.failed);
    expect(
      (await fixture.messageRepo.getMessage(_messageId))!.text,
      original.text,
    );
    expect(await fixture.db.query('messages'), hasLength(1));
    expect(await fixture.messageRepo.loadAuthoredDirectTextIntents(), isEmpty);
    expect(encryptedPayloads, isEmpty);
    expect(network.deliverCallCount, 0);
    expect(network.storeInInboxCallCount, 0);
  });

  test(
    'retry refuses a crossed authored intent without replacing it',
    () async {
      final original = AuthoredDirectTextIntent(
        id: _messageId,
        contactPeerId: _author,
        text: 'A different reply',
        quotedMessageId: _quoteId,
        timestamp: now.toIso8601String(),
        token: 'original-token',
      );
      expect(
        await fixture.messageRepo.saveAuthoredDirectTextIntent(original),
        isTrue,
      );

      expect(await send(), ThoughtReplyStatus.failed);
      final pending = await fixture.messageRepo.loadAuthoredDirectTextIntents();
      expect(pending.single.toMap(), original.toMap());
      expect(await fixture.db.query('messages'), isEmpty);
      expect(encryptedPayloads, isEmpty);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test('written-only transport never claims that the reply is Sent', () async {
    await fixture.db.insert(
      'messages',
      ConversationMessage(
        id: _messageId,
        contactPeerId: _author,
        senderPeerId: _local,
        text: 'Count me in',
        quotedMessageId: _quoteId,
        timestamp: now.toIso8601String(),
        createdAt: now.toIso8601String(),
        status: 'sent',
        isIncoming: false,
      ).toMap(),
    );

    expect(await send(), ThoughtReplyStatus.queued);
    expect(encryptedPayloads, isEmpty);
    expect(network.deliverCallCount, 0);
    expect(network.storeInInboxCallCount, 0);
    expect(await fixture.db.query('messages'), hasLength(1));
  });
}

class _NodeControlledService extends FakeP2PService {
  _NodeControlledService({required super.peerId, required super.network});

  bool started = true;

  @override
  NodeState get currentState => NodeState(
    peerId: peerId,
    isStarted: started,
    connections: testConnections,
  );
}
