import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_upload_recovery_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';

// A replaced own Thought keeps its row: expiry pulled in to the replacement's
// creation, status terminal. These tests put a row in that state and check
// that no late send, upload or save makes it live or retryable again, with
// the phone clock both after and before the replacement time.
void main() {
  sqfliteFfiInit();
  late Database db;
  final now = DateTime.utc(2026, 11, 10, 12);
  final created = now.subtract(const Duration(hours: 2));
  final clocks = <String, DateTime>{
    'clock after the replacement': now.subtract(const Duration(minutes: 30)),
    'clock behind the replacement': now.add(const Duration(minutes: 30)),
  };

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        onCreate: runProductionOnCreate,
      ),
    );
  });
  tearDown(() => db.close());

  PostRepositoryImpl repository() {
    final posts = PostRepositoryImpl(
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (id) => dbLoadPost(db, id, nowProvider: () => now),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db, nowProvider: () => now),
      dbLoadRetryableOutgoingPosts: () =>
          dbLoadRetryableOutgoingPosts(db, nowProvider: () => now),
      dbLoadExpiredOwnPosts: (iso, {limit, offset = 0}) =>
          dbLoadExpiredOwnPosts(db, iso, limit: limit, offset: offset),
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (id) => dbLoadPostRecipientDeliveries(db, id),
      dbMarkPostFocused: (id) => dbMarkPostFocused(db, id),
      dbReplacePostMedia: (id, rows) =>
          dbReplacePostMediaAttachments(db, id, rows),
      dbReplacePostMediaUploadRecoveryItems: (id, rows) =>
          dbReplacePostMediaUploadRecoveryItems(db, id, rows),
    );
    addTearDown(posts.dispose);
    return posts;
  }

  Future<void> seedOwnThought(PostRepositoryImpl posts) async {
    await dbInsertPost(db, <String, Object?>{
      'post_id': 'old',
      'event_id': 'evt-old',
      'sender_peer_id': 'me',
      'author_peer_id': 'me',
      'author_username': 'Me',
      'text': 'old thought',
      'audience_kind': 'all_friends',
      'post_created_at': created.toIso8601String(),
      'visible_at': created.toIso8601String(),
      'expires_at': created.add(const Duration(hours: 24)).toIso8601String(),
      'is_incoming': 0,
      'delivery_status': 'sending',
      'keep_available': 0,
    });
    for (final friend in ['friend-1', 'friend-2']) {
      await posts.saveRecipientDelivery(
        PostRecipientDelivery(
          postId: 'old',
          recipientPeerId: friend,
          deliveryStatus: 'pending',
          lastAttemptAt: created.toIso8601String(),
          deliveryPath: 'pending',
          createdAt: created.toIso8601String(),
          updatedAt: created.toIso8601String(),
        ),
      );
    }
  }

  // The state the author's newer Thought leaves the old one in.
  Future<void> retire(DateTime replacedAt) => db.rawUpdate(
    "UPDATE posts SET expires_at = ?, delivery_status = 'sent' "
    'WHERE post_id = ?',
    [replacedAt.toIso8601String(), 'old'],
  );

  Future<Map<String, Object?>> storedRow() async => (await db.query(
    'posts',
    columns: ['expires_at', 'delivery_status'],
    where: 'post_id = ?',
    whereArgs: ['old'],
  )).single;

  for (final MapEntry(key: clock, value: replacedAt) in clocks.entries) {
    group(clock, () {
      test('a stale save after retirement leaves the row retired', () async {
        final posts = repository();
        await seedOwnThought(posts);
        final stale = (await posts.getPost('old'))!;

        await retire(replacedAt);
        await posts.savePost(stale.copyWith(deliveryStatus: 'partial'));

        expect(await storedRow(), {
          'expires_at': replacedAt.toIso8601String(),
          'delivery_status': 'sent',
        });
        expect(await posts.getPost('old'), isNull);
        expect((await posts.loadFeed()).map((post) => post.id), isEmpty);
        expect(await posts.loadRetryableOutgoingPosts(), isEmpty);
        expect(
          (await posts.loadExpiredOwnPosts(
            now.toIso8601String(),
          )).map((post) => post.id),
          ['old'],
        );
      });

      test(
        'a send suspended across retirement sends no queued recipient',
        () async {
          final posts = repository();
          await seedOwnThought(posts);
          final post = (await posts.getPost('old'))!;
          final service = _HoldFirstSend(
            peerId: 'me',
            network: FakeP2PNetwork(),
          )..connectedPeers.addAll(['friend-1', 'friend-2']);

          final run =
              PostDeliveryRunner(
                p2pService: service,
                postRepo: posts,
                bridge: FakeBridge(),
                nowProvider: () => now,
                maxConcurrentRecipients: 1,
              ).execute(
                CreatedLocalPost(
                  post: post,
                  resolvedRecipients: [
                    for (final friend in ['friend-1', 'friend-2'])
                      CreatedLocalPostRecipient(contact: _contact(friend)),
                  ],
                ),
              );
          await service.firstSendStarted.future;
          await retire(replacedAt);
          service.releaseFirstSend.complete();
          await run;

          expect(service.sentTo, ['friend-1']);
          expect(await storedRow(), {
            'expires_at': replacedAt.toIso8601String(),
            'delivery_status': 'sent',
          });
        },
      );

      test('media prepared across retirement uploads no later draft', () async {
        final posts = repository();
        await seedOwnThought(posts);
        final uploads = <String>[];
        final firstUploadStarted = Completer<void>();
        final releaseFirstUpload = Completer<void>();

        final attach = attachPostMedia(
          postId: 'old',
          postRepo: posts,
          secureKeyStore: FakeSecureKeyStore(),
          imageProcessor: ImageProcessor(
            compressFile:
                ({
                  required path,
                  required quality,
                  required keepExif,
                  minWidth = 1920,
                  minHeight = 1080,
                }) async => XFile('${path}_processed'),
          ),
          photoPreview: (_) async => null,
          mediaFileManager: FakeMediaFileManager(),
          nowProvider: () => now,
          drafts: const [
            PostMediaDraft(localFilePath: '/tmp/first.jpg', mime: 'image/jpeg'),
            PostMediaDraft(
              localFilePath: '/tmp/second.jpg',
              mime: 'image/jpeg',
            ),
          ],
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
                uploads.add(localFilePath);
                if (!firstUploadStarted.isCompleted) {
                  firstUploadStarted.complete();
                  await releaseFirstUpload.future;
                }
                return PostMediaAttachmentModel(
                  mediaId: 'media-${uploads.length}',
                  postId: postId,
                  blobId: 'blob-${uploads.length}',
                  kind: 'image',
                  mime: mime,
                  sizeBytes: 10,
                  createdAt: now.toIso8601String(),
                );
              },
        );
        await firstUploadStarted.future;
        await retire(replacedAt);
        releaseFirstUpload.complete();
        final (result, attachments) = await attach;

        expect(uploads, ['/tmp/first.jpg_processed']);
        expect(result, AttachPostMediaResult.expired);
        expect(attachments, isEmpty);
        expect(await storedRow(), {
          'expires_at': replacedAt.toIso8601String(),
          'delivery_status': 'sent',
        });
      });
    });
  }
}

ContactModel _contact(String peerId) => ContactModel(
  peerId: peerId,
  publicKey: 'pk-$peerId',
  rendezvous: 'rendezvous',
  username: peerId,
  signature: 'signature',
  scannedAt: '2026-11-10T09:00:00.000Z',
  mlKemPublicKey: 'mlkem-$peerId',
);

class _HoldFirstSend extends FakeP2PService {
  _HoldFirstSend({required super.peerId, required super.network});
  final sentTo = <String>[];
  final firstSendStarted = Completer<void>();
  final releaseFirstSend = Completer<void>();

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    sentTo.add(targetPeerId);
    if (!firstSendStarted.isCompleted) {
      firstSendStarted.complete();
      await releaseFirstSend.future;
    }
    return const SendMessageResult(sent: true, acked: true);
  }
}
