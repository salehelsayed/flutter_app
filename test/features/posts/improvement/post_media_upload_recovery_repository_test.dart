import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_feed_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_media_upload_recovery_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/post_recipients_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/034_posts_media_upload_recovery.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/pending_post_media_upload_retrier.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_upload_recovery_item.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runPostsCoreMigration(db);
    await runPostsEngagementMigration(db);
    await runPostsPassAlongMigration(db);
    await runPostsMediaUploadRecoveryMigration(db);
    await runPostsRepostEngagementStateMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  PostRepositoryImpl buildRepository({DateTime Function()? nowProvider}) {
    final now = nowProvider ?? () => DateTime.utc(2026, 3, 15, 12);
    return PostRepositoryImpl(
      dbInsertPost: (row) => dbInsertPost(db, row),
      dbLoadPost: (postId) => dbLoadPost(db, postId, nowProvider: now),
      dbLoadPostsFeed: () => dbLoadPostsFeed(db, nowProvider: now),
      dbLoadExpiredPosts: (nowIso) => dbLoadExpiredPosts(db, nowIso),
      dbLoadExpiredOwnPosts: (String nowIso, {int? limit, int offset = 0}) =>
          dbLoadExpiredOwnPosts(db, nowIso, limit: limit, offset: offset),
      dbUpsertRecipientDelivery: (row) =>
          dbUpsertPostRecipientDelivery(db, row),
      dbLoadRecipientDeliveries: (postId) =>
          dbLoadPostRecipientDeliveries(db, postId),
      dbMarkPostFocused: (postId) => dbMarkPostFocused(db, postId),
      dbLoadPostMedia: (postId) => dbLoadPostMediaAttachments(db, postId),
      dbReplacePostMedia: (postId, rows) =>
          dbReplacePostMediaAttachments(db, postId, rows),
      dbReplacePostMediaUploadRecoveryItems: (postId, rows) =>
          dbReplacePostMediaUploadRecoveryItems(db, postId, rows),
      dbLoadPostMediaUploadRecoveryItems: (postId) =>
          dbLoadPostMediaUploadRecoveryItems(db, postId),
      dbLoadPendingMediaUploadPosts: () =>
          dbLoadPendingPostMediaUploadPosts(db, nowProvider: now),
    );
  }

  test(
    'expired own failed photo stays readable in history after pending upload selection',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'expired-own-photo-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final source = File('${tempDir.path}/photo.jpg');
      const sourceBytes = <int>[1, 2, 3, 4];
      await source.writeAsBytes(sourceBytes);
      final createdAt = DateTime.utc(2026, 3, 15, 12);
      var now = createdAt;
      final repository = buildRepository(nowProvider: () => now);
      addTearDown(repository.dispose);
      final network = FakeP2PNetwork();
      final service = FakeP2PService(peerId: 'peer-alice', network: network);
      addTearDown(service.dispose);
      final contacts = InMemoryContactRepository();
      final contact = ContactModel(
        peerId: 'peer-bob',
        publicKey: 'pk-bob',
        rendezvous: '/dns4/example.invalid/tcp/443',
        username: 'Bob',
        signature: 'sig-bob',
        scannedAt: createdAt.toIso8601String(),
        mlKemPublicKey: 'mlkem-bob',
      );
      contacts.addTestContact(contact);
      final post = PostModel(
        id: 'expired-own-photo',
        eventId: 'event-expired-own-photo',
        senderPeerId: 'peer-alice',
        authorPeerId: 'peer-alice',
        authorUsername: 'Alice',
        text: 'Keep this photo',
        audience: PostAudience.allFriends(),
        createdAt: createdAt.toIso8601String(),
        visibleAt: createdAt.toIso8601String(),
        expiresAt: ThoughtLifetime.expiresAt(createdAt).toIso8601String(),
        mediaKind: 'image',
        isIncoming: false,
        deliveryStatus: 'sending',
      );
      await repository.savePost(post);
      await repository.saveRecipientDelivery(
        PostRecipientDelivery(
          postId: post.id,
          recipientPeerId: contact.peerId,
          deliveryStatus: 'pending',
          lastAttemptAt: post.createdAt,
          deliveryPath: 'pending',
          createdAt: post.createdAt,
          updatedAt: post.createdAt,
        ),
      );
      await repository.replacePostMediaUploadRecoveryItems(post.id, [
        PostMediaUploadRecoveryItem(
          postId: post.id,
          position: 0,
          localFilePath: source.path,
          mime: 'image/jpeg',
          kind: 'image',
          createdAt: post.createdAt,
        ),
      ]);
      final secureKeyStore = FakeSecureKeyStore();
      final imageProcessor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => XFile('${path}_processed'),
      );
      var uploadAttempts = 0;
      Future<PostMediaAttachmentModel?> upload({
        required String postId,
        required String localFilePath,
        required String mime,
        required List<String> allowedPeers,
        MediaFileManager? mediaFileManager,
        int? width,
        int? height,
        int? durationMs,
        List<double>? waveform,
      }) async {
        uploadAttempts++;
        return null;
      }

      final (result, prepared) = await prepareCreatedLocalPostMedia(
        created: CreatedLocalPost(
          post: post,
          resolvedRecipients: [CreatedLocalPostRecipient(contact: contact)],
        ),
        postRepo: repository,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        uploadPostMediaFn: upload,
        nowProvider: () => now,
      );
      expect(result, SendPostResult.sendFailed);
      expect(prepared!.post.mediaKind, 'image');
      expect(uploadAttempts, 1);
      expect(
        await repository.loadPostMediaUploadRecoveryItems(post.id),
        hasLength(1),
      );

      // Restoring a clock that was two days behind expires delivery, while
      // the author's history must keep the selected photo.
      now = createdAt.add(const Duration(hours: 48, minutes: 1));
      expect(await repository.loadPendingMediaUploadPosts(), isEmpty);
      final bridge = FakeBridge();
      expect(
        await retryPendingPostMediaUploads(
          postRepo: repository,
          contactRepo: contacts,
          p2pService: service,
          secureKeyStore: secureKeyStore,
          imageProcessor: imageProcessor,
          uploadPostMediaFn: upload,
          bridge: bridge,
          nowProvider: () => now,
        ),
        0,
      );
      expect(uploadAttempts, 1);
      expect(bridge.commandLog, isEmpty);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);

      final recreated = buildRepository(nowProvider: () => now);
      addTearDown(recreated.dispose);
      final history = await recreated.loadExpiredOwnPosts(
        now.toIso8601String(),
      );
      expect(history.map((entry) => entry.id), [post.id]);
      expect(history.single.eventId, post.eventId);
      expect(history.single.expiresAt, post.expiresAt);
      expect(await recreated.loadPostMediaAttachments(post.id), isEmpty);
      final retained = await recreated.loadPostMediaUploadRecoveryItems(
        post.id,
      );
      expect(retained, hasLength(1));
      expect(retained.single.localFilePath, source.path);
      expect(
        await File(retained.single.localFilePath).readAsBytes(),
        sourceBytes,
      );
      expect(await recreated.loadPendingMediaUploadPosts(), isEmpty);
    },
  );

  test(
    'photo upload failing after expiry keeps source when live lookup hides own history',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('late-own-photo-');
      addTearDown(() => tempDir.delete(recursive: true));
      final source = File('${tempDir.path}/photo.jpg');
      const sourceBytes = <int>[1, 2, 3, 4];
      await source.writeAsBytes(sourceBytes);
      final createdAt = DateTime.utc(2026, 3, 15, 12);
      var now = createdAt;
      final repository = buildRepository(nowProvider: () => now);
      addTearDown(repository.dispose);
      final post = PostModel(
        id: 'late-own-photo',
        eventId: 'event-late-own-photo',
        senderPeerId: 'peer-alice',
        authorPeerId: 'peer-alice',
        authorUsername: 'Alice',
        text: 'My local photo',
        audience: PostAudience.allFriends(),
        createdAt: createdAt.toIso8601String(),
        visibleAt: createdAt.toIso8601String(),
        expiresAt: ThoughtLifetime.expiresAt(createdAt).toIso8601String(),
        mediaKind: 'image',
        isIncoming: false,
        deliveryStatus: 'sending',
      );
      await repository.savePost(post);
      await repository.saveRecipientDelivery(
        PostRecipientDelivery(
          postId: post.id,
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'pending',
          lastAttemptAt: post.createdAt,
          deliveryPath: 'pending',
          createdAt: post.createdAt,
          updatedAt: post.createdAt,
        ),
      );
      await repository.replacePostMediaUploadRecoveryItems(post.id, [
        PostMediaUploadRecoveryItem(
          postId: post.id,
          position: 0,
          localFilePath: source.path,
          mime: 'image/jpeg',
          kind: 'image',
          createdAt: post.createdAt,
        ),
      ]);
      final secureKeyStore = FakeSecureKeyStore();
      final imageProcessor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => XFile('${path}_processed'),
      );
      var uploadAttempts = 0;
      Future<PostMediaAttachmentModel?> upload({
        required String postId,
        required String localFilePath,
        required String mime,
        required List<String> allowedPeers,
        MediaFileManager? mediaFileManager,
        int? width,
        int? height,
        int? durationMs,
        List<double>? waveform,
      }) async {
        uploadAttempts++;
        now = createdAt.add(const Duration(hours: 48, minutes: 1));
        return null;
      }

      final (result, _) = await prepareCreatedLocalPostMedia(
        created: CreatedLocalPost(post: post, resolvedRecipients: const []),
        postRepo: repository,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        uploadPostMediaFn: upload,
        nowProvider: () => now,
      );
      expect(result, SendPostResult.sendFailed);
      expect(uploadAttempts, 1);
      expect(await repository.getPost(post.id), isNull);
      final history = await repository.loadExpiredOwnPosts(
        now.toIso8601String(),
      );
      expect(history.map((entry) => entry.id), [post.id]);
      expect(history.single.expiresAt, post.expiresAt);

      final network = FakeP2PNetwork();
      final service = FakeP2PService(peerId: 'peer-alice', network: network);
      addTearDown(service.dispose);
      final bridge = FakeBridge();
      expect(
        await retryPendingPostMediaUploads(
          postRepo: repository,
          contactRepo: InMemoryContactRepository(),
          p2pService: service,
          secureKeyStore: secureKeyStore,
          imageProcessor: imageProcessor,
          uploadPostMediaFn: upload,
          bridge: bridge,
          nowProvider: () => now,
        ),
        0,
      );
      expect(uploadAttempts, 1);
      expect(bridge.commandLog, isEmpty);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
      expect(await repository.loadPostMediaAttachments(post.id), isEmpty);
      final retained = await repository.loadPostMediaUploadRecoveryItems(
        post.id,
      );
      expect(retained, hasLength(1));
      expect(retained.single.localFilePath, source.path);
      expect(await source.readAsBytes(), sourceBytes);
    },
  );

  test(
    'repository round-trip preserves recovery metadata order and pending-post discovery across recreation',
    () async {
      final firstRepository = buildRepository();
      const imagePost = PostModel(
        id: 'post-image',
        eventId: 'evt-image',
        senderPeerId: 'peer-alice',
        authorPeerId: 'peer-alice',
        authorUsername: 'Alice',
        text: '',
        audience: PostAudience(kind: PostAudienceKind.allFriends),
        createdAt: '2026-03-16T11:00:00.000Z',
        visibleAt: '2026-03-16T11:00:00.000Z',
        expiresAt: '2026-03-19T11:00:00.000Z',
        mediaKind: 'image_carousel',
        isIncoming: false,
        deliveryStatus: 'sending',
      );
      const voicePost = PostModel(
        id: 'post-voice',
        eventId: 'evt-voice',
        senderPeerId: 'peer-alice',
        authorPeerId: 'peer-alice',
        authorUsername: 'Alice',
        text: '',
        audience: PostAudience(kind: PostAudienceKind.allFriends),
        createdAt: '2026-03-16T11:05:00.000Z',
        visibleAt: '2026-03-16T11:05:00.000Z',
        expiresAt: '2026-03-19T11:05:00.000Z',
        mediaKind: 'voice',
        isIncoming: false,
        deliveryStatus: 'failed',
      );

      await firstRepository.savePost(imagePost);
      await firstRepository.savePost(voicePost);
      await firstRepository.replacePostMediaUploadRecoveryItems(
        imagePost.id,
        const <PostMediaUploadRecoveryItem>[
          PostMediaUploadRecoveryItem(
            postId: 'post-image',
            position: 0,
            localFilePath: '/tmp/photo-1.jpg',
            mime: 'image/jpeg',
            kind: 'image',
            width: 1080,
            height: 1440,
            createdAt: '2026-03-16T11:00:00.000Z',
          ),
          PostMediaUploadRecoveryItem(
            postId: 'post-image',
            position: 1,
            localFilePath: '/tmp/photo-2.jpg',
            mime: 'image/jpeg',
            kind: 'image',
            width: 1440,
            height: 1080,
            createdAt: '2026-03-16T11:00:01.000Z',
          ),
        ],
      );
      await firstRepository.replacePostMediaUploadRecoveryItems(
        voicePost.id,
        const <PostMediaUploadRecoveryItem>[
          PostMediaUploadRecoveryItem(
            postId: 'post-voice',
            position: 0,
            localFilePath: '/tmp/voice.m4a',
            mime: 'audio/mp4',
            kind: 'voice',
            durationMs: 4200,
            waveform: <double>[0.1, 0.2, 0.4],
            createdAt: '2026-03-16T11:05:00.000Z',
          ),
        ],
      );
      firstRepository.dispose();

      final secondRepository = buildRepository();
      final imageRecovery = await secondRepository
          .loadPostMediaUploadRecoveryItems(imagePost.id);
      final voiceRecovery = await secondRepository
          .loadPostMediaUploadRecoveryItems(voicePost.id);
      final pendingPosts = await secondRepository.loadPendingMediaUploadPosts();

      expect(
        imageRecovery.map((item) => item.position).toList(growable: false),
        <int>[0, 1],
      );
      expect(
        imageRecovery.map((item) => item.localFilePath).toList(growable: false),
        <String>['/tmp/photo-1.jpg', '/tmp/photo-2.jpg'],
      );
      expect(imageRecovery.first.mime, 'image/jpeg');
      expect(imageRecovery.first.kind, 'image');
      expect(imageRecovery.first.width, 1080);
      expect(imageRecovery.first.height, 1440);

      expect(voiceRecovery, hasLength(1));
      expect(voiceRecovery.single.localFilePath, '/tmp/voice.m4a');
      expect(voiceRecovery.single.mime, 'audio/mp4');
      expect(voiceRecovery.single.kind, 'voice');
      expect(voiceRecovery.single.durationMs, 4200);
      expect(voiceRecovery.single.waveform, <double>[0.1, 0.2, 0.4]);

      expect(
        pendingPosts.map((post) => post.id).toList(growable: false),
        <String>['post-image', 'post-voice'],
      );

      secondRepository.dispose();
    },
  );
}
