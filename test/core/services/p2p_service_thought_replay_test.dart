import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bridge/fake_bridge.dart';
import '../../shared/fakes/in_memory_contact_repository.dart';
import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../../shared/fakes/in_memory_post_repository.dart';

final _now = DateTime.now().toUtc();
const _author = 'synthetic-author';
const _postId = 'synthetic-post';
const _entryId = 'synthetic-entry';

String _wire({
  bool media = false,
  bool encrypted = false,
  DateTime? authoredAt,
}) {
  final createdAt = authoredAt ?? _now;
  final post = PostModel(
    id: _postId,
    eventId: 'synthetic-event',
    senderPeerId: _author,
    authorPeerId: _author,
    authorUsername: 'Synthetic author',
    text: 'Synthetic thought',
    audience: const PostAudience(kind: PostAudienceKind.allFriends),
    createdAt: createdAt.toIso8601String(),
    visibleAt: createdAt.toIso8601String(),
    expiresAt: createdAt.add(const Duration(hours: 24)).toIso8601String(),
    mediaKind: media ? 'image_carousel' : 'none',
    media: [
      if (media)
        for (var i = 1; i <= 2; i++)
          PostMediaAttachmentModel(
            mediaId: 'synthetic-media-$i',
            postId: _postId,
            blobId: 'synthetic-blob-$i',
            kind: 'image',
            mime: 'image/jpeg',
            sizeBytes: 32,
            position: i - 1,
            createdAt: _now.toIso8601String(),
          ),
    ],
  );
  final envelope =
      jsonDecode(PostCreateEnvelope.fromPost(post).toJson())
          as Map<String, dynamic>;
  if (!encrypted) return jsonEncode(envelope);
  final payload = envelope.remove('payload') as Map<String, dynamic>;
  if (media) {
    payload['media_keys'] = {
      for (var i = 1; i <= 2; i++)
        'synthetic-media-$i': {
          'key_base64': 'synthetic-key-$i',
          'nonce': 'synthetic-nonce-$i',
          'blob_id': 'synthetic-blob-$i',
          'scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          'content_hash': 'f' * 64,
        },
    };
  }
  envelope['version'] = '2';
  envelope['encrypted'] = {
    'kem': 'synthetic-kem',
    'ciphertext': jsonEncode(payload),
    'nonce': 'synthetic-nonce',
  };
  return jsonEncode(envelope);
}

class _RelayBridge extends FakeBridge {
  _RelayBridge(this.wire);

  String wire;
  bool hasCopy = true;
  bool failAck = false;
  int ackCalls = 0;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final command = request['cmd'];
    if (command == 'inbox:retrieve_pending' || command == 'inbox:ack') {
      final payload = request['payload'] as Map<String, dynamic>;
      expect(payload['custodyContract'], ackOrExpiryInboxCustodyContract);
      if (command == 'inbox:retrieve_pending') {
        return jsonEncode({
          'ok': true,
          'custodyContract': ackOrExpiryInboxCustodyContract,
          'hasMore': false,
          'messages': [
            if (hasCopy)
              {
                'id': _entryId,
                'from': _author,
                'message': wire,
                'timestamp': _now.toIso8601String(),
              },
          ],
        });
      }
      ackCalls++;
      expect(payload['entryIds'], [_entryId]);
      if (failAck) return jsonEncode({'ok': false});
      hasCopy = false;
      return jsonEncode({
        'ok': true,
        'custodyContract': ackOrExpiryInboxCustodyContract,
        'acked': 1,
      });
    }
    return super.send(message);
  }
}

class _MediaRepository extends InMemoryPostRepository {
  final secondRowStarted = Completer<void>();
  Completer<void>? releaseSecondRow;
  bool failSecondRowOnce = false;
  bool failPostWrites = false;
  final rowWrites = <String, int>{};
  int postWrites = 0;

  @override
  Future<void> savePost(PostModel post) async {
    postWrites++;
    if (failPostWrites) throw StateError('synthetic post write failure');
    await super.savePost(post);
  }

  @override
  Future<void> savePostMediaAttachment(
    PostMediaAttachmentModel attachment,
  ) async {
    rowWrites.update(attachment.mediaId, (n) => n + 1, ifAbsent: () => 1);
    if (attachment.mediaId == 'synthetic-media-2' &&
        rowWrites[attachment.mediaId] == 1) {
      secondRowStarted.complete();
      await releaseSecondRow?.future;
      if (failSecondRowOnce) throw StateError('synthetic media write failure');
    }
    await super.savePostMediaAttachment(attachment);
  }
}

class _Fixture {
  _Fixture({bool media = false, bool encrypted = false})
    : bridge = _RelayBridge(_wire(media: media, encrypted: encrypted));

  final _RelayBridge bridge;
  final posts = _MediaRepository();
  final staging = InMemoryInboxStagingRepository();
  final contacts = InMemoryContactRepository();
  late P2PServiceImpl service;
  late IncomingMessageRouter router;
  PostListener? listener;
  String? secret = 'synthetic-secret';
  DateTime now = _now;

  Future<void> start({bool withListener = true}) async {
    contacts.addTestContact(
      ContactModel(
        peerId: _author,
        publicKey: 'synthetic-public',
        rendezvous: '/dns4/example.invalid/tcp/443',
        username: 'Synthetic author',
        signature: 'synthetic-signature',
        scannedAt: _now.toIso8601String(),
      ),
    );
    bridge.responses['node:start'] = {
      'ok': true,
      'peerId': 'synthetic-self',
      'isStarted': true,
      'listenAddresses': <String>[],
      'circuitAddresses': <String>[],
      'connections': <String>[],
    };
    service = P2PServiceImpl(bridge: bridge, inboxStagingRepository: staging);
    await service.startNodeCore('c3ludGhldGlj', 'synthetic-self');
    router = IncomingMessageRouter(p2pService: service)..start();
    if (withListener) startListener();
  }

  void startListener({Completer<void>? downloadGate}) {
    listener = PostListener(
      postCreateStream: router.postCreateStream,
      postRepo: posts,
      contactRepo: contacts,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => secret,
      nowProvider: () => now,
      hydratePostMediaFn: downloadGate == null
          ? null
          : ({required attachment, required postId}) async {
              await downloadGate.future;
              return attachment;
            },
    )..start();
  }

  Future<void> dispose() async {
    listener?.dispose();
    router.dispose();
    service.dispose();
    posts.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Thought relay ACK waits for every media key row, not its download',
    () async {
      final f = _Fixture(media: true, encrypted: true);
      final rows = Completer<void>();
      final download = Completer<void>();
      f.posts.releaseSecondRow = rows;
      await f.start(withListener: false);
      f.startListener(downloadGate: download);
      final received = f.listener!.incomingPostStream.first;
      try {
        final drain = f.service.drainOfflineInbox();
        await f.posts.secondRowStarted.future.timeout(
          const Duration(seconds: 2),
        );
        expect(await f.posts.getPost(_postId), isNotNull);
        expect(await f.posts.loadPostMediaAttachments(_postId), hasLength(1));
        expect(f.staging.entry(_entryId), isNotNull);
        expect(f.bridge.hasCopy, isTrue);
        expect(f.bridge.ackCalls, 0);

        rows.complete();
        await drain.timeout(const Duration(seconds: 2));
        expect(download.isCompleted, isFalse);
        expect(f.bridge.hasCopy, isFalse);
        expect(f.staging.entry(_entryId), isNull);
        final media = await f.posts.loadPostMediaAttachments(_postId);
        expect(media, hasLength(2));
        for (var i = 0; i < media.length; i++) {
          expect(media[i].encryptionKeyBase64, 'synthetic-key-${i + 1}');
          expect(media[i].encryptionNonce, 'synthetic-nonce-${i + 1}');
          expect(media[i].isEncrypted, isTrue);
          expect(media[i].downloadStatus, 'pending');
        }
      } finally {
        if (!rows.isCompleted) rows.complete();
        download.complete();
        await received;
        await f.dispose();
      }
    },
  );

  test(
    'Thought retry completes partial media rows and preserves saved keys',
    () async {
      final f = _Fixture(media: true, encrypted: true);
      f.posts.failSecondRowOnce = true;
      await f.start();
      try {
        await f.service.drainOfflineInbox();
        expect(await f.posts.getPost(_postId), isNotNull);
        expect(await f.posts.loadPostMediaAttachments(_postId), hasLength(1));
        expect(f.staging.entry(_entryId)?.status, 'retryable');
        expect(f.bridge.hasCopy, isTrue);
        expect(f.bridge.ackCalls, 0);

        await f.service.drainOfflineInbox();
        final media = await f.posts.loadPostMediaAttachments(_postId);
        expect(media, hasLength(2));
        expect(media.map((row) => row.encryptionKeyBase64), [
          'synthetic-key-1',
          'synthetic-key-2',
        ]);
        expect(f.posts.rowWrites['synthetic-media-1'], 1);
        expect(f.posts.rowWrites['synthetic-media-2'], 2);
        expect(f.posts.postWrites, 1);
        expect(f.bridge.hasCopy, isFalse);
        expect(f.staging.entry(_entryId), isNull);
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'Thought without an active listener retains both custody copies',
    () async {
      final f = _Fixture();
      await f.start(withListener: false);
      try {
        await f.service.drainOfflineInbox();
        expect(f.staging.entry(_entryId)?.status, 'retryable');
        expect(f.bridge.hasCopy, isTrue);
        expect(f.bridge.ackCalls, 0);
        f.startListener();
        f.listener!.stop();
        await f.service.drainOfflineInbox();
        expect(f.bridge.hasCopy, isTrue);
        expect(await f.posts.getPost(_postId), isNull);
        f.listener!.start();
        await f.service.drainOfflineInbox();
        expect(await f.posts.getPost(_postId), isNotNull);
        expect(f.bridge.hasCopy, isFalse);
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'Thought local key and bridge unavailability remain retryable',
    () async {
      final f = _Fixture(encrypted: true);
      await f.start();
      try {
        f.secret = null;
        await f.service.drainOfflineInbox();
        expect(
          f.staging.entry(_entryId)?.rejectReasonCode,
          'crypto_unavailable',
        );
        expect(f.bridge.ackCalls, 0);

        f.secret = 'synthetic-secret';
        f.bridge.responses['message.decrypt'] = {
          'ok': false,
          'errorCode': 'BRIDGE_UNAVAILABLE',
        };
        await f.service.drainOfflineInbox();
        expect(f.staging.entry(_entryId)?.status, 'retryable');
        expect(f.bridge.hasCopy, isTrue);
        expect(f.bridge.ackCalls, 0);

        f.bridge.responses.remove('message.decrypt');
        await f.service.drainOfflineInbox();
        expect(await f.posts.getPost(_postId), isNotNull);
        expect(f.bridge.hasCopy, isFalse);
      } finally {
        await f.dispose();
      }
    },
  );

  for (final prerequisite in ['local key', 'bridge', 'post storage']) {
    test(
      'Thought recovers after more than 10 failed $prerequisite attempts',
      () async {
        final f = _Fixture(encrypted: true);
        await f.start();
        try {
          if (prerequisite == 'local key') {
            f.secret = null;
          } else if (prerequisite == 'bridge') {
            f.bridge.responses['message.decrypt'] = {
              'ok': false,
              'errorCode': 'BRIDGE_UNAVAILABLE',
            };
          } else {
            f.posts.failPostWrites = true;
          }
          for (var attempt = 0; attempt < 12; attempt++) {
            await f.service.drainOfflineInbox();
          }
          expect(await f.posts.getPost(_postId), isNull);
          expect(f.staging.entry(_entryId), isNotNull);
          expect(f.bridge.hasCopy, isTrue);
          expect(f.bridge.ackCalls, 0);

          f.secret = 'synthetic-secret';
          f.bridge.responses.remove('message.decrypt');
          f.posts.failPostWrites = false;
          await f.service.drainOfflineInbox();

          expect(await f.posts.getPost(_postId), isNotNull);
          expect(f.bridge.ackCalls, 1);
          expect(f.bridge.hasCopy, isFalse);
          expect(f.staging.entry(_entryId), isNull);
        } finally {
          await f.dispose();
        }
      },
    );
  }

  test(
    'Thought missing crypto expires after staged lifetime and retries terminal ACK',
    () async {
      final f = _Fixture(encrypted: true)..secret = null;
      await withClock(Clock(() => f.now), () async {
        await f.start();
        try {
          await f.service.drainOfflineInbox();
          final stagedAt = DateTime.parse(f.staging.entry(_entryId)!.stagedAt);
          f.now = stagedAt.add(const Duration(hours: 24, seconds: -1));
          await f.service.drainOfflineInbox();
          expect(f.staging.entry(_entryId)?.status, 'retryable');
          expect(f.bridge.ackCalls, 0);

          f.now = stagedAt.add(const Duration(hours: 24));
          f.bridge.failAck = true;
          await f.service.drainOfflineInbox();
          expect(f.staging.entry(_entryId)?.status, 'rejected');
          expect(f.staging.entry(_entryId)?.rejectReasonCode, 'post_expired');
          expect(f.bridge.ackCalls, 1);
          expect(f.bridge.hasCopy, isTrue);
          expect(f.posts.postWrites, 0);

          f.bridge.failAck = false;
          await f.service.drainOfflineInbox();
          expect(f.bridge.ackCalls, 2);
          expect(f.bridge.hasCopy, isFalse);
          expect(f.staging.entry(_entryId), isNull);
        } finally {
          await f.dispose();
        }
      });
    },
  );

  test(
    'Thought without a listener releases custody at readable authored expiry',
    () async {
      final f = _Fixture()
        ..now = _now.add(const Duration(hours: 24, seconds: -1));
      await withClock(Clock(() => f.now), () async {
        await f.start(withListener: false);
        try {
          await f.service.drainOfflineInbox();
          expect(f.staging.entry(_entryId)?.status, 'retryable');
          expect(f.bridge.ackCalls, 0);

          f.now = _now.add(const Duration(hours: 24));
          await f.service.drainOfflineInbox();
          expect(f.bridge.ackCalls, 1);
          expect(f.bridge.hasCopy, isFalse);
          expect(f.staging.entry(_entryId), isNull);
          expect(f.posts.postWrites, 0);
        } finally {
          await f.dispose();
        }
      });
    },
  );

  test(
    'Thought expired oldest batch releases the later healthy staged row',
    () async {
      final f = _Fixture()
        ..secret = null
        ..now = _now.add(const Duration(hours: 24, seconds: -1));
      f.bridge.hasCopy = false;
      await withClock(Clock(() => f.now), () async {
        await f.start();
        try {
          for (var i = 0; i < 500; i++) {
            f.staging.seed(
              InboxStagingEntry(
                entryId: 'expired-entry-$i',
                ownerPeerId: 'synthetic-self',
                senderPeerId: _author,
                messageType: 'post_create',
                relayTimestamp: _now
                    .add(Duration(milliseconds: i))
                    .toIso8601String(),
                envelope: _wire(
                  encrypted: true,
                ).replaceAll(_postId, 'expired-post-$i'),
                stagedAt: _now.toIso8601String(),
                status: 'retryable',
                attemptCount: 12,
                rejectReasonCode: 'crypto_unavailable',
              ),
            );
          }
          f.staging.seed(
            InboxStagingEntry(
              entryId: _entryId,
              ownerPeerId: 'synthetic-self',
              senderPeerId: _author,
              messageType: 'post_create',
              relayTimestamp: f.now.toIso8601String(),
              envelope: _wire(authoredAt: f.now),
              stagedAt: f.now.toIso8601String(),
            ),
          );
          await f.service.drainOfflineInbox();
          expect(await f.posts.getPost(_postId), isNull);
          expect(f.staging.entry('expired-entry-0')?.status, 'retryable');

          f.now = _now.add(const Duration(hours: 24));
          await f.service.drainOfflineInbox();
          await f.service.drainOfflineInbox();
          expect(await f.posts.getPost(_postId), isNotNull);
          expect(f.posts.postWrites, 1);
          expect(await f.staging.getRecoverableEntries(), isEmpty);
          for (var i = 0; i < 500; i++) {
            expect(f.staging.entry('expired-entry-$i')?.status, 'rejected');
          }
        } finally {
          await f.dispose();
        }
      });
    },
  );

  test('Thought permanent decrypt rejection releases relay custody', () async {
    final f = _Fixture(encrypted: true);
    await f.start();
    try {
      f.bridge.responses['message.decrypt'] = {
        'ok': false,
        'errorCode': 'AUTH_FAILED',
      };
      await f.service.drainOfflineInbox();
      expect(await f.posts.getPost(_postId), isNull);
      expect(f.bridge.ackCalls, 1);
      expect(f.bridge.hasCopy, isFalse);
      expect(f.staging.entry(_entryId), isNull);
    } finally {
      await f.dispose();
    }
  });

  test(
    'Thought duplicate after a failed relay ACK does not save a second post',
    () async {
      final f = _Fixture();
      await f.start();
      try {
        f.bridge.failAck = true;
        await f.service.drainOfflineInbox();
        expect(f.bridge.hasCopy, isTrue);
        expect(await f.posts.getPost(_postId), isNotNull);
        f.bridge.failAck = false;
        await f.service.drainOfflineInbox();
        expect(f.bridge.ackCalls, 2);
        expect(f.bridge.hasCopy, isFalse);
        expect(f.posts.postWrites, 1);
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'Thought terminal rejection survives ACK failure and rejects entry-id collision',
    () async {
      final f = _Fixture();
      await f.start();
      try {
        await f.contacts.blockContact(_author);
        f.bridge.failAck = true;
        await f.service.drainOfflineInbox();
        expect(f.staging.entry(_entryId)?.status, 'rejected');
        expect(f.bridge.ackCalls, 1);
        final original = f.bridge.wire;
        f.bridge.wire = original.replaceFirst(
          'synthetic-event',
          'different-event',
        );
        f.bridge.failAck = false;
        await f.service.drainOfflineInbox();
        expect(f.bridge.ackCalls, 1);
        expect(f.bridge.hasCopy, isTrue);
        f.bridge.wire = original;
        await f.service.drainOfflineInbox();
        expect(f.bridge.ackCalls, 2);
        expect(f.bridge.hasCopy, isFalse);
        expect(f.staging.entry(_entryId), isNull);
        expect(f.posts.postWrites, 0);
      } finally {
        await f.dispose();
      }
    },
  );
}
