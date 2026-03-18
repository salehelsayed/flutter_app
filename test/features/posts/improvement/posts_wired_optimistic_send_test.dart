import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_wired.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

late FakeIdentityRepository identityRepository;
late FakeContactRepository contactRepository;
late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
late FakeP2PNetwork network;
late FakeP2PService p2pService;

void main() {
  setUp(() {
    identityRepository = FakeIdentityRepository()
      ..seed(
        IdentityModel(
          peerId: 'peer-self',
          publicKey: 'pk-self',
          privateKey: 'sk-self',
          mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
          username: 'Alice',
          createdAt: '2026-03-15T10:00:00.000Z',
          updatedAt: '2026-03-15T10:00:00.000Z',
        ),
      );
    contactRepository = FakeContactRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    network = FakeP2PNetwork();
    p2pService = FakeP2PService(peerId: 'peer-self', network: network);
  });

  tearDown(() {
    postsPrivacySettingsRepository.dispose();
  });

  testWidgets(
    'text-only send dismisses after local save, shows sending, then settles to sent',
    (tester) async {
      final posts = InMemoryPostRepository();
      addTearDown(posts.dispose);
      contactRepository.seed(<ContactModel>[_contact('peer-bob', 'Bob')]);
      network.ackDelay = const Duration(seconds: 3);
      FakeP2PService(peerId: 'peer-bob', network: network);

      await tester.pumpWidget(_buildWidget(postRepo: posts));
      await tester.pump();
      expect(identityRepository.loadIdentityCallCount, 1);

      await tester.tap(find.text('Share something with your friends'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'Optimistic hello');
      await tester.pump();

      await tester.tap(find.text('Post'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(identityRepository.loadIdentityCallCount, 1);
      expect(find.byType(ComposePostSheet), findsNothing);
      expect(find.text('Optimistic hello'), findsOneWidget);
      expect(find.text('Sending...'), findsOneWidget);

      final sendingPost = (await posts.loadFeed()).single;
      expect(sendingPost.deliveryStatus, 'sending');

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 200));

      final storedPost = await posts.getPost(sendingPost.id);
      expect(storedPost, isNotNull);
      expect(storedPost!.deliveryStatus, 'sent');
      expect(find.text('Sending...'), findsNothing);
    },
  );

  testWidgets(
    'media-only send dismisses after local save, shows an upload placeholder, and completes in the background',
    (tester) async {
      final posts = InMemoryPostRepository();
      addTearDown(posts.dispose);
      final secureKeyStore = FakeSecureKeyStore();
      final uploadCompleter = Completer<PostMediaAttachmentModel?>();
      final uploadStarted = Completer<void>();
      contactRepository.seed(<ContactModel>[_contact('peer-bob', 'Bob')]);
      network.ackDelay = const Duration(seconds: 1);
      FakeP2PService(peerId: 'peer-bob', network: network);

      await tester.pumpWidget(
        _buildWidget(
          postRepo: posts,
          secureKeyStore: secureKeyStore,
          imageProcessor: ImageProcessor(
            compressFile:
                ({
                  required path,
                  required quality,
                  required keepExif,
                  minWidth = 1920,
                  minHeight = 1080,
                }) async {
                  return XFile('${path}_processed');
                },
          ),
          onAttachMedia: () async => const [
            PostMediaDraft(localFilePath: '/tmp/photo.jpg', mime: 'image/jpeg'),
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
                if (!uploadStarted.isCompleted) {
                  uploadStarted.complete();
                }
                return uploadCompleter.future;
              },
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Share something with your friends'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Media'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('1 attachments'), findsOneWidget);

      await tester.ensureVisible(find.text('Post'));
      await tester.tap(find.text('Post'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ComposePostSheet), findsNothing);
      expect(find.text('Uploading media...'), findsOneWidget);
      expect(find.text('Photo pending upload'), findsOneWidget);
      await uploadStarted.future;

      final sendingPost = (await posts.loadFeed()).single;
      expect(sendingPost.text, isEmpty);
      expect(sendingPost.mediaKind, 'image');
      expect(sendingPost.media, isEmpty);
      expect(sendingPost.deliveryStatus, 'sending');
      expect(network.retrieveInbox('peer-bob'), isEmpty);

      uploadCompleter.complete(
        PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: sendingPost.id,
          blobId: 'blob-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: 248120,
          localPath: 'post_media/${sendingPost.id}/blob-1.jpg',
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 200));

      final storedPost = await posts.getPost(sendingPost.id);
      expect(storedPost, isNotNull);
      expect(storedPost!.media, hasLength(1));
      expect(storedPost.deliveryStatus, 'sent');
      expect(find.text('Uploading media...'), findsNothing);
    },
  );

  testWidgets(
    'multi-image upload failure keeps the failed post in the upload placeholder state',
    (tester) async {
      final posts = InMemoryPostRepository();
      addTearDown(posts.dispose);
      final secureKeyStore = FakeSecureKeyStore();
      contactRepository.seed(<ContactModel>[_contact('peer-bob', 'Bob')]);

      var uploadCount = 0;
      await tester.pumpWidget(
        _buildWidget(
          postRepo: posts,
          secureKeyStore: secureKeyStore,
          imageProcessor: ImageProcessor(
            compressFile:
                ({
                  required path,
                  required quality,
                  required keepExif,
                  minWidth = 1920,
                  minHeight = 1080,
                }) async {
                  return XFile('${path}_processed');
                },
          ),
          onAttachMedia: () async => const [
            PostMediaDraft(
              localFilePath: '/tmp/photo-1.jpg',
              mime: 'image/jpeg',
            ),
            PostMediaDraft(
              localFilePath: '/tmp/photo-2.jpg',
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
                uploadCount++;
                if (uploadCount == 2) {
                  return null;
                }
                return PostMediaAttachmentModel(
                  mediaId: 'media-1',
                  postId: postId,
                  blobId: 'blob-1',
                  kind: 'image',
                  mime: mime,
                  sizeBytes: 248120,
                  localPath: 'post_media/$postId/blob-1.jpg',
                  downloadStatus: 'done',
                  createdAt: '2026-03-15T10:20:00.000Z',
                );
              },
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Share something with your friends'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Media'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('2 attachments'), findsOneWidget);

      await tester.ensureVisible(find.text('Post'));
      await tester.tap(find.text('Post'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byType(ComposePostSheet), findsNothing);

      await tester.pump(const Duration(milliseconds: 300));

      final storedPost = (await posts.loadFeed()).single;
      expect(storedPost.deliveryStatus, 'failed');
      expect(storedPost.media, isEmpty);
      expect(find.text('Upload failed'), findsOneWidget);
      expect(find.text('Photo upload failed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('post-media-skeleton-placeholder')),
        findsOneWidget,
      );
      expect(find.text('Send failed'), findsNothing);
    },
  );

  testWidgets(
    'text-only local-create failure keeps the composer open without bubbling an exception',
    (tester) async {
      final posts = InMemoryPostRepository();
      addTearDown(posts.dispose);

      await tester.pumpWidget(_buildWidget(postRepo: posts));
      await tester.pump();

      await tester.tap(find.text('Share something with your friends'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'No recipients yet');
      await tester.pump();

      await tester.tap(find.text('Post'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(ComposePostSheet), findsOneWidget);
      expect(await posts.loadFeed(), isEmpty);

      final postButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Post'),
      );
      expect(postButton.onPressed, isNotNull);
    },
  );

  testWidgets('background delivery updates the feed to partial', (
    tester,
  ) async {
    final posts = InMemoryPostRepository();
    addTearDown(posts.dispose);
    contactRepository.seed(<ContactModel>[
      _contact('peer-bob', 'Bob'),
      _contact('peer-cara', 'Cara'),
    ]);
    network.ackDelay = const Duration(seconds: 1);
    network.inboxDisabled = true;
    FakeP2PService(peerId: 'peer-bob', network: network);

    await tester.pumpWidget(_buildWidget(postRepo: posts));
    await tester.pump();

    await tester.tap(find.text('Share something with your friends'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'Mixed result');
    await tester.pump();

    await tester.tap(find.text('Post'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ComposePostSheet), findsNothing);
    expect(
      find.text('Sending...').evaluate().isNotEmpty ||
          find.text('Send failed').evaluate().isNotEmpty,
      isTrue,
    );

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));

    final post = (await posts.loadFeed()).single;
    expect(post.deliveryStatus, 'partial');
    expect(find.text('Partially sent'), findsOneWidget);
  });

  testWidgets('background delivery updates the feed to failed', (tester) async {
    final posts = InMemoryPostRepository();
    addTearDown(posts.dispose);
    contactRepository.seed(<ContactModel>[_contact('peer-cara', 'Cara')]);
    network.ackDelay = const Duration(seconds: 1);
    network.inboxDisabled = true;

    await tester.pumpWidget(_buildWidget(postRepo: posts));
    await tester.pump();

    await tester.tap(find.text('Share something with your friends'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'No delivery path');
    await tester.pump();

    await tester.tap(find.text('Post'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ComposePostSheet), findsNothing);
    expect(
      find.text('Sending...').evaluate().isNotEmpty ||
          find.text('Send failed').evaluate().isNotEmpty,
      isTrue,
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));

    final post = (await posts.loadFeed()).single;
    expect(post.deliveryStatus, 'failed');
    expect(find.text('Send failed'), findsOneWidget);
  });

  testWidgets('opening the surface reconciles stale sending posts', (
    tester,
  ) async {
    final posts = InMemoryPostRepository();
    addTearDown(posts.dispose);
    await posts.savePost(
      _post(
        id: 'post-stale',
        text: 'Recovered state',
        deliveryStatus: 'sending',
      ),
    );
    await posts.saveRecipientDelivery(
      _delivery(postId: 'post-stale', peerId: 'peer-bob', status: 'failed'),
    );

    await tester.pumpWidget(_buildWidget(postRepo: posts));
    await tester.pump();

    expect(find.text('Recovered state'), findsOneWidget);
    expect(find.text('Send failed'), findsOneWidget);
    expect((await posts.getPost('post-stale'))!.deliveryStatus, 'failed');
  });

  testWidgets(
    'coalesces recipient delivery bursts into serialized trailing reloads',
    (tester) async {
      final posts = _CountingPostRepository();
      addTearDown(posts.dispose);
      await posts.savePost(
        _post(
          id: 'post-burst',
          text: 'Burst target',
          deliveryStatus: 'sending',
        ),
      );

      await tester.pumpWidget(_buildWidget(postRepo: posts));
      await tester.pump();

      final baselineLoads = posts.loadFeedCallCount;
      posts.loadFeedBlocker = Completer<void>();

      await posts.saveRecipientDelivery(
        _delivery(
          postId: 'post-burst',
          peerId: 'peer-bob',
          status: 'delivered',
        ),
      );
      await posts.saveRecipientDelivery(
        _delivery(postId: 'post-burst', peerId: 'peer-cara', status: 'failed'),
      );
      await posts.saveRecipientDelivery(
        _delivery(postId: 'post-burst', peerId: 'peer-dan', status: 'failed'),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(posts.loadFeedCallCount, baselineLoads + 1);

      await posts.saveRecipientDelivery(
        _delivery(postId: 'post-burst', peerId: 'peer-erin', status: 'failed'),
      );
      await posts.saveRecipientDelivery(
        _delivery(postId: 'post-burst', peerId: 'peer-finn', status: 'failed'),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(posts.loadFeedCallCount, baselineLoads + 1);

      posts.loadFeedBlocker!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(posts.loadFeedCallCount, baselineLoads + 2);
    },
  );
}

class _CountingPostRepository extends InMemoryPostRepository {
  int loadFeedCallCount = 0;
  Completer<void>? loadFeedBlocker;

  @override
  Future<List<PostModel>> loadFeed() async {
    loadFeedCallCount++;
    final blocker = loadFeedBlocker;
    if (blocker != null && !blocker.isCompleted) {
      await blocker.future;
    }
    return super.loadFeed();
  }
}

Widget _buildWidget({
  required InMemoryPostRepository postRepo,
  Future<List<PostMediaDraft>> Function()? onAttachMedia,
  UploadPostMediaFn? uploadPostMediaFn,
  FakeSecureKeyStore? secureKeyStore,
  ImageProcessor? imageProcessor,
}) {
  return MaterialApp(
    home: PostsWired(
      identityRepo: identityRepository,
      contactRepo: contactRepository,
      postRepo: postRepo,
      p2pService: p2pService,
      activeTab: 'posts',
      onSwitchView: (_) {},
      postsPrivacySettingsRepository: postsPrivacySettingsRepository,
      onAttachMedia: onAttachMedia,
      uploadPostMediaFn: uploadPostMediaFn,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
    ),
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

PostModel _post({
  required String id,
  required String text,
  required String deliveryStatus,
}) {
  return PostModel(
    id: id,
    eventId: 'evt-$id',
    senderPeerId: 'peer-self',
    authorPeerId: 'peer-self',
    authorUsername: 'Alice',
    text: text,
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    isIncoming: false,
    deliveryStatus: deliveryStatus,
  );
}

PostRecipientDelivery _delivery({
  required String postId,
  required String peerId,
  required String status,
}) {
  return PostRecipientDelivery(
    postId: postId,
    recipientPeerId: peerId,
    deliveryStatus: status,
    lastAttemptAt: '2026-03-15T10:16:00.000Z',
    deliveryPath: status,
    createdAt: '2026-03-15T10:15:30.000Z',
    updatedAt: '2026-03-15T10:16:00.000Z',
  );
}
