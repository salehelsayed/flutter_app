import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_presence_listener.dart';
import 'package:flutter_app/features/posts/application/publish_post_presence_update_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';

import '../test/shared/fakes/fake_p2p_network.dart';
import '../test/shared/fakes/fake_p2p_service_integration.dart';
import '../test/shared/fakes/in_memory_contact_presence_snapshot_repository.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_post_repository.dart';
import '../test/shared/fakes/in_memory_posts_privacy_settings_repository.dart';

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

class _FakeNearbyLocationPlatformAdapter
    implements NearbyLocationPlatformAdapter {
  PostsLocationPermissionState checkedPermissionState =
      PostsLocationPermissionState.denied;
  PostsLocationPermissionState requestedPermissionState =
      PostsLocationPermissionState.granted;
  NearbyDevicePosition? currentPosition;

  @override
  Future<PostsLocationPermissionState> checkPermissionState() async {
    return checkedPermissionState;
  }

  @override
  Future<NearbyDevicePosition?> getCurrentPosition() async => currentPosition;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<PostsLocationPermissionState> requestPermission() async {
    checkedPermissionState = requestedPermissionState;
    return requestedPermissionState;
  }
}

void main() {
  testWidgets(
    'nearby fanout stays radius-qualified and replay-safe after send time',
    (tester) async {
      final freshTime = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      final movedTime = DateTime.now().toUtc().subtract(
        const Duration(minutes: 2),
      );
      final network = FakeP2PNetwork();
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      final caraService = FakeP2PService(peerId: 'peer-cara', network: network);

      final aliceContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-bob', 'Bob'))
        ..addTestContact(_contact('peer-cara', 'Cara'));
      final bobContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-alice', 'Alice'));
      final caraContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-alice', 'Alice'));

      final aliceSnapshots = InMemoryContactPresenceSnapshotRepository();
      final alicePrivacySettings = InMemoryPostsPrivacySettingsRepository(
        initialSettings: const PostsPrivacySettings(sharingEnabled: true),
      );
      final bobPrivacySettings = InMemoryPostsPrivacySettingsRepository(
        initialSettings: const PostsPrivacySettings(sharingEnabled: true),
      );
      final caraPrivacySettings = InMemoryPostsPrivacySettingsRepository(
        initialSettings: const PostsPrivacySettings(sharingEnabled: true),
      );

      final alicePlatform = _FakeNearbyLocationPlatformAdapter()
        ..currentPosition = NearbyDevicePosition(
          latitude: 52.52,
          longitude: 13.405,
          accuracyM: 120,
          capturedAt: freshTime,
        );
      final bobPlatform = _FakeNearbyLocationPlatformAdapter()
        ..currentPosition = NearbyDevicePosition(
          latitude: 52.52,
          longitude: 13.412,
          accuracyM: 80,
          capturedAt: freshTime,
        );
      final caraPlatform = _FakeNearbyLocationPlatformAdapter()
        ..currentPosition = NearbyDevicePosition(
          latitude: 52.52,
          longitude: 13.42,
          accuracyM: 80,
          capturedAt: freshTime,
        );

      Future<void> publishFrom({
        required FakeP2PService service,
        required InMemoryContactRepository contacts,
        required String status,
        required String capturedAt,
        int? latE3,
        int? lngE3,
        double? accuracyM,
        String? reason,
      }) {
        return publishPostPresenceUpdate(
          p2pService: service,
          contactRepo: contacts,
          status: status,
          capturedAt: capturedAt,
          latE3: latE3,
          lngE3: lngE3,
          accuracyM: accuracyM,
          reason: reason,
        );
      }

      final aliceNearbyService = NearbyLocationServiceImpl(
        settingsRepository: alicePrivacySettings,
        platformAdapter: alicePlatform,
        publishPostPresenceUpdate:
            ({
              required status,
              required capturedAt,
              latE3,
              lngE3,
              accuracyM,
              reason,
            }) {
              return publishFrom(
                service: aliceService,
                contacts: aliceContacts,
                status: status,
                capturedAt: capturedAt,
                latE3: latE3,
                lngE3: lngE3,
                accuracyM: accuracyM,
                reason: reason,
              );
            },
      );
      final bobNearbyService = NearbyLocationServiceImpl(
        settingsRepository: bobPrivacySettings,
        platformAdapter: bobPlatform,
        publishPostPresenceUpdate:
            ({
              required status,
              required capturedAt,
              latE3,
              lngE3,
              accuracyM,
              reason,
            }) {
              return publishFrom(
                service: bobService,
                contacts: bobContacts,
                status: status,
                capturedAt: capturedAt,
                latE3: latE3,
                lngE3: lngE3,
                accuracyM: accuracyM,
                reason: reason,
              );
            },
      );
      final caraNearbyService = NearbyLocationServiceImpl(
        settingsRepository: caraPrivacySettings,
        platformAdapter: caraPlatform,
        publishPostPresenceUpdate:
            ({
              required status,
              required capturedAt,
              latE3,
              lngE3,
              accuracyM,
              reason,
            }) {
              return publishFrom(
                service: caraService,
                contacts: caraContacts,
                status: status,
                capturedAt: capturedAt,
                latE3: latE3,
                lngE3: lngE3,
                accuracyM: accuracyM,
                reason: reason,
              );
            },
      );

      final alicePosts = InMemoryPostRepository();
      final bobPosts = InMemoryPostRepository();
      final caraPosts = InMemoryPostRepository();
      final aliceRouter = IncomingMessageRouter(p2pService: aliceService)
        ..start();
      final bobRouter = IncomingMessageRouter(p2pService: bobService)..start();
      final caraRouter = IncomingMessageRouter(p2pService: caraService)
        ..start();
      final alicePresenceListener = PostPresenceListener(
        postPresenceStream: aliceRouter.postPresenceStream,
        contactRepo: aliceContacts,
        snapshotRepo: aliceSnapshots,
      )..start();
      final bobListener = PostListener(
        postCreateStream: bobRouter.postCreateStream,
        postRepo: bobPosts,
        contactRepo: bobContacts,
      )..start();
      final caraListener = PostListener(
        postCreateStream: caraRouter.postCreateStream,
        postRepo: caraPosts,
        contactRepo: caraContacts,
      )..start();

      addTearDown(() {
        alicePresenceListener.dispose();
        bobListener.dispose();
        caraListener.dispose();
        aliceRouter.dispose();
        bobRouter.dispose();
        caraRouter.dispose();
        aliceSnapshots.dispose();
        alicePrivacySettings.dispose();
        bobPrivacySettings.dispose();
        caraPrivacySettings.dispose();
        alicePosts.dispose();
        bobPosts.dispose();
        caraPosts.dispose();
      });

      await bobNearbyService.refreshInteractivelyFromSettings();
      await caraNearbyService.refreshInteractivelyFromSettings();
      await aliceNearbyService.refreshInteractivelyFromSettings();
      await tester.pump(const Duration(milliseconds: 50));

      expect((await aliceSnapshots.load('peer-bob'))?.lngE3, 13412);
      expect((await aliceSnapshots.load('peer-cara'))?.lngE3, 13420);

      bobService.setOnline(false);

      final (result, sentPost) = await sendPost(
        p2pService: aliceService,
        postRepo: alicePosts,
        contactRepo: aliceContacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'Lost dog near the bridge.',
        audience: PostAudience.peopleNearby(radiusM: 500),
        contactPresenceSnapshotRepository: aliceSnapshots,
        postsPrivacySettingsRepository: alicePrivacySettings,
      );

      expect(result, SendPostResult.success);
      expect(sentPost, isNotNull);
      expect(network.inboxCount('peer-bob'), 1);
      expect(network.inboxCount('peer-cara'), 0);
      expect(await caraPosts.loadFeed(), isEmpty);

      bobService.setOnline(true);
      bobPlatform.currentPosition = NearbyDevicePosition(
        latitude: 52.52,
        longitude: 13.422,
        accuracyM: 80,
        capturedAt: movedTime,
      );
      await bobNearbyService.refreshInteractivelyFromCompose();
      await tester.pump(const Duration(milliseconds: 50));

      expect((await aliceSnapshots.load('peer-bob'))?.lngE3, 13422);

      await bobService.drainOfflineInbox();
      await tester.pump(const Duration(milliseconds: 50));

      final bobFeed = await loadPostsFeed(postRepo: bobPosts);
      expect(bobFeed, hasLength(1));
      expect(bobFeed.single.audience.kind, PostAudienceKind.peopleNearby);
      expect(bobFeed.single.nearbyDistanceM, 474);
      expect(bobFeed.single.nearbyDistanceLabel, '450m away');
      expect(bobFeed.single.nearbySenderLatE3, 52520);
      expect(bobFeed.single.nearbySenderLngE3, 13405);
      expect(
        (await bobPosts.getRecipientDeliveries(
          bobFeed.single.id,
        )).map((entry) => entry.recipientPeerId),
        <String>['peer-bob'],
      );
      expect(await caraPosts.loadFeed(), isEmpty);
    },
  );
}
