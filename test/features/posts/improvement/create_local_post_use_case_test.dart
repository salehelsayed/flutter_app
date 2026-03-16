import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/contact_presence_snapshot.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';

import '../../../shared/fakes/in_memory_contact_presence_snapshot_repository.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';

ContactModel _contact(
  String peerId,
  String username, {
  bool blocked = false,
  bool archived = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    isBlocked: blocked,
    isArchived: archived,
  );
}

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late InMemoryContactPresenceSnapshotRepository snapshots;
  late InMemoryPostsPrivacySettingsRepository privacySettings;

  setUp(() {
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    snapshots = InMemoryContactPresenceSnapshotRepository();
    privacySettings = InMemoryPostsPrivacySettingsRepository();
  });

  tearDown(() {
    posts.dispose();
    snapshots.dispose();
    privacySettings.dispose();
  });

  test(
    'createLocalPost persists sending post and pending recipient rows',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      contacts.addTestContact(_contact('peer-cara', 'Cara', blocked: true));
      contacts.addTestContact(_contact('peer-dan', 'Dan', archived: true));

      final (result, created) = await createLocalPost(
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'Hello everyone',
        audience: PostAudience.allFriends(),
      );

      expect(result, SendPostResult.success);
      expect(created, isNotNull);
      expect(created!.post.deliveryStatus, 'sending');

      final storedPost = await posts.getPost(created.post.id);
      expect(storedPost, isNotNull);
      expect(storedPost!.deliveryStatus, 'sending');

      final deliveries = await posts.getRecipientDeliveries(created.post.id);
      expect(deliveries, hasLength(1));
      expect(deliveries.single.recipientPeerId, 'peer-bob');
      expect(deliveries.single.deliveryStatus, 'pending');
      expect(deliveries.single.deliveryPath, 'pending');
    },
  );

  test(
    'createLocalPost returns resolved recipient context for nearby delivery',
    () async {
      final freshIso = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      await snapshots.save(
        ContactPresenceSnapshot(
          peerId: 'peer-bob',
          status: ContactPresenceSnapshotStatus.active,
          latE3: 52524,
          lngE3: 13405,
          capturedAt: freshIso,
          accuracyM: 80,
          updatedAt: freshIso,
        ),
      );
      await privacySettings.save(
        PostsPrivacySettings(
          sharingEnabled: true,
          permissionState: PostsLocationPermissionState.granted,
          lastLocalLatE3: 52520,
          lastLocalLngE3: 13405,
          lastLocalCapturedAt: freshIso,
          lastLocalAccuracyM: 120,
        ),
      );

      final (result, created) = await createLocalPost(
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'Nearby post',
        audience: PostAudience.peopleNearby(radiusM: 500),
        contactPresenceSnapshotRepository: snapshots,
        postsPrivacySettingsRepository: privacySettings,
      );

      expect(result, SendPostResult.success);
      expect(created, isNotNull);
      expect(created!.resolvedRecipients, hasLength(1));
      expect(created.resolvedRecipients.single.contact.peerId, 'peer-bob');
      expect(created.resolvedRecipients.single.nearbyDistanceM, isNotNull);
      expect(created.post.nearbySenderLatE3, 52520);
      expect(created.post.nearbySenderLngE3, 13405);
    },
  );

  test(
    'createLocalPost keeps media upload recovery durable if local creation is interrupted after the skeleton is saved',
    () async {
      final failingPosts = _FailAfterPostSaveRepository();
      contacts.addTestContact(_contact('peer-bob', 'Bob'));

      await expectLater(
        () => createLocalPost(
          postRepo: failingPosts,
          contactRepo: contacts,
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          text: '',
          audience: PostAudience.allFriends(),
          mediaDrafts: const [
            PostMediaDraft(localFilePath: '/tmp/photo.jpg', mime: 'image/jpeg'),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      final savedPostId = failingPosts.lastSavedPostId;
      expect(savedPostId, isNotNull);
      final storedPost = await failingPosts.getPost(savedPostId!);
      expect(storedPost, isNotNull);
      expect(storedPost!.mediaKind, 'image');
      expect(storedPost.media, isEmpty);

      final recovery = await failingPosts.loadPostMediaUploadRecoveryItems(
        savedPostId,
      );
      expect(recovery, hasLength(1));
      expect(recovery.single.postId, savedPostId);
      expect(recovery.single.position, 0);
      expect(recovery.single.localFilePath, '/tmp/photo.jpg');
      expect(recovery.single.mime, 'image/jpeg');
      expect(recovery.single.kind, 'image');

      failingPosts.dispose();
    },
  );
}

class _FailAfterPostSaveRepository extends InMemoryPostRepository {
  String? lastSavedPostId;

  @override
  Future<void> savePost(PostModel post) async {
    lastSavedPostId = post.id;
    await super.savePost(post);
  }

  @override
  Future<void> saveRecipientDelivery(PostRecipientDelivery delivery) async {
    throw StateError('simulated recipient persistence interruption');
  }
}
