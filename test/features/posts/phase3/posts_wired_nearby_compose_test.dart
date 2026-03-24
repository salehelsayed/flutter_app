import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_wired.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
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
  Duration loadComposeAvailabilityDelay = Duration.zero;
  int loadComposeAvailabilityCallCount = 0;
  int refreshSilentlyOnStartupCallCount = 0;
  int refreshSilentlyOnResumeCallCount = 0;
  int refreshSilentlyOnPostsOpenCallCount = 0;
  int refreshInteractivelyFromSettingsCallCount = 0;
  int refreshInteractivelyFromComposeCallCount = 0;
  int handleSharingDisabledCallCount = 0;
  int openAppSettingsCallCount = 0;

  @override
  Future<NearbyComposeAvailability> loadComposeAvailability() async {
    loadComposeAvailabilityCallCount++;
    if (loadComposeAvailabilityDelay > Duration.zero) {
      await Future<void>.delayed(loadComposeAvailabilityDelay);
    }
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
    availability = composeRefreshResult;
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
  Future<bool> openAppSettings() async {
    openAppSettingsCallCount++;
    return true;
  }
}

class _DelayedContactRepository extends FakeContactRepository {
  Duration activeContactsDelay = Duration.zero;

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    if (activeContactsDelay > Duration.zero) {
      await Future<void>.delayed(activeContactsDelay);
    }
    return super.getActiveContacts();
  }
}

void main() {
  late FakeIdentityRepository identityRepository;
  late _DelayedContactRepository contactRepository;
  late InMemoryPostRepository postRepository;
  late InMemoryPostsPrivacySettingsRepository privacyRepository;
  late PendingPostTargetStore pendingTargetStore;
  late FakeP2PService p2pService;
  late _FakeNearbyLocationService nearbyLocationService;
  late FakeBridge bridge;
  late FakeSecureKeyStore secureKeyStore;
  late ImageProcessor imageProcessor;

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
    contactRepository = _DelayedContactRepository();
    postRepository = InMemoryPostRepository();
    privacyRepository = InMemoryPostsPrivacySettingsRepository();
    pendingTargetStore = PendingPostTargetStore();
    p2pService = FakeP2PService(peerId: 'peer-self', network: FakeP2PNetwork());
    nearbyLocationService = _FakeNearbyLocationService();
    bridge = FakeBridge();
    secureKeyStore = FakeSecureKeyStore();
    imageProcessor = ImageProcessor(
      compressFile:
          ({
            required path,
            required quality,
            required keepExif,
            minWidth = 1920,
            minHeight = 1080,
          }) async => null,
      compressVideo: ({required path, required compress, onProgress}) async =>
          null,
    );
  });

  tearDown(() {
    postRepository.dispose();
    privacyRepository.dispose();
  });

  Widget buildWidget({NearbyLocationService? nearbyLocationService}) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PostsWired(
        identityRepo: identityRepository,
        contactRepo: contactRepository,
        postRepo: postRepository,
        p2pService: p2pService,
        activeTab: 'posts',
        onSwitchView: (_) {},
        bridge: bridge,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
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
    expect(find.text('Open Settings'), findsOneWidget);
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

  testWidgets('compose opens after the slowest preflight, not their sum', (
    tester,
  ) async {
    contactRepository.activeContactsDelay = const Duration(milliseconds: 250);
    nearbyLocationService.availability = const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.ready,
    );
    nearbyLocationService.loadComposeAvailabilityDelay = const Duration(
      milliseconds: 250,
    );

    await tester.pumpWidget(
      buildWidget(nearbyLocationService: nearbyLocationService),
    );
    await tester.pump();

    await tester.tap(find.text('Share something with your friends'));
    await tester.pump();
    expect(find.byType(ComposePostSheet), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(ComposePostSheet), findsOneWidget);
    expect(nearbyLocationService.loadComposeAvailabilityCallCount, 1);
  });

  testWidgets(
    'settings shortcut opens nearby settings and returns to compose',
    (tester) async {
      await privacyRepository.save(
        const PostsPrivacySettings(sharingEnabled: false),
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

      expect(find.text('Open Settings'), findsOneWidget);

      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Share People Nearby'), findsOneWidget);

      await tester.ensureVisible(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        nearbyLocationService.refreshInteractivelyFromSettingsCallCount,
        1,
      );

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('People Nearby is ready'), findsOneWidget);
    },
  );
}
