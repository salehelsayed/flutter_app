import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_wired.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

class _FakeNearbyLocationService implements NearbyLocationService {
  NearbyComposeAvailability availability = const NearbyComposeAvailability(
    state: NearbyComposeAvailabilityState.sharingOff,
  );
  NearbyComposeAvailability composeRefreshResult =
      const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.ready,
      );
  int loadComposeAvailabilityCallCount = 0;
  int refreshSilentlyOnStartupCallCount = 0;
  int refreshSilentlyOnResumeCallCount = 0;
  int refreshSilentlyOnPostsOpenCallCount = 0;
  int refreshInteractivelyFromSettingsCallCount = 0;
  int refreshInteractivelyFromComposeCallCount = 0;
  int handleSharingDisabledCallCount = 0;

  @override
  Future<NearbyComposeAvailability> loadComposeAvailability() async {
    loadComposeAvailabilityCallCount++;
    return availability;
  }

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromCompose() async {
    refreshInteractivelyFromComposeCallCount++;
    availability = composeRefreshResult;
    return availability;
  }

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromSettings() async {
    refreshInteractivelyFromSettingsCallCount++;
    return availability;
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnPostsOpen() async {
    refreshSilentlyOnPostsOpenCallCount++;
    return availability;
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnResume() async {
    refreshSilentlyOnResumeCallCount++;
    return availability;
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnStartup() async {
    refreshSilentlyOnStartupCallCount++;
    return availability;
  }

  @override
  Future<void> handleSharingDisabled() async {
    handleSharingDisabledCallCount++;
  }

  @override
  Future<bool> openAppSettings() async => true;
}

void main() {
  late FakeIdentityRepository identityRepository;
  late FakeContactRepository contactRepository;
  late InMemoryPostRepository postRepository;
  late InMemoryPostsPrivacySettingsRepository privacyRepository;
  late PendingPostTargetStore pendingTargetStore;
  late FakeP2PService p2pService;
  late _FakeNearbyLocationService nearbyLocationService;

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
    postRepository = InMemoryPostRepository();
    privacyRepository = InMemoryPostsPrivacySettingsRepository();
    pendingTargetStore = PendingPostTargetStore();
    p2pService = FakeP2PService(peerId: 'peer-self', network: FakeP2PNetwork());
    nearbyLocationService = _FakeNearbyLocationService();
  });

  tearDown(() {
    postRepository.dispose();
    privacyRepository.dispose();
  });

  Widget buildWidget({NearbyLocationService? nearbyLocationService}) {
    return MaterialApp(
      home: PostsWired(
        identityRepo: identityRepository,
        contactRepo: contactRepository,
        postRepo: postRepository,
        p2pService: p2pService,
        activeTab: 'posts',
        onSwitchView: (_) {},
        pendingTargetStore: pendingTargetStore,
        postsPrivacySettingsRepository: privacyRepository,
        nearbyLocationService: nearbyLocationService,
      ),
    );
  }

  testWidgets('compose reflects nearby sharing disabled from the repository', (
    tester,
  ) async {
    await privacyRepository.save(
      const PostsPrivacySettings(sharingEnabled: false),
    );

    await tester.pumpWidget(buildWidget());
    await tester.pump();

    await tester.tap(find.text('Share something with your friends'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('People Nearby is off in Settings'), findsOneWidget);
  });

  testWidgets('compose reflects nearby sharing enabled from the repository', (
    tester,
  ) async {
    await privacyRepository.save(
      const PostsPrivacySettings(sharingEnabled: true),
    );

    await tester.pumpWidget(buildWidget());
    await tester.pump();

    await tester.tap(find.text('Share something with your friends'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('People Nearby is ready'), findsOneWidget);
  });

  testWidgets('compose refresh uses the interactive nearby path', (
    tester,
  ) async {
    await privacyRepository.save(
      const PostsPrivacySettings(
        sharingEnabled: true,
        permissionState: PostsLocationPermissionState.denied,
      ),
    );
    nearbyLocationService.availability = const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.stale,
    );
    nearbyLocationService.composeRefreshResult =
        const NearbyComposeAvailability(
          state: NearbyComposeAvailabilityState.ready,
        );

    await tester.pumpWidget(
      buildWidget(nearbyLocationService: nearbyLocationService),
    );
    await tester.pump();

    await tester.tap(find.text('Share something with your friends'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Refresh nearby before posting'), findsOneWidget);
    await tester.tap(find.text('Refresh nearby'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(nearbyLocationService.refreshInteractivelyFromComposeCallCount, 1);
    expect(find.text('People Nearby is ready'), findsOneWidget);
  });
}
