import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';

import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';

class _FakeNearbyLocationPlatformAdapter
    implements NearbyLocationPlatformAdapter {
  bool servicesEnabled = true;
  PostsLocationPermissionState checkedPermissionState =
      PostsLocationPermissionState.unknown;
  PostsLocationPermissionState requestedPermissionState =
      PostsLocationPermissionState.unknown;
  NearbyDevicePosition? currentPosition;
  int checkPermissionCallCount = 0;
  int requestPermissionCallCount = 0;
  int isLocationServiceEnabledCallCount = 0;
  int getCurrentPositionCallCount = 0;
  int openAppSettingsCallCount = 0;

  @override
  Future<PostsLocationPermissionState> checkPermissionState() async {
    checkPermissionCallCount++;
    return checkedPermissionState;
  }

  @override
  Future<NearbyDevicePosition?> getCurrentPosition() async {
    getCurrentPositionCallCount++;
    return currentPosition;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    isLocationServiceEnabledCallCount++;
    return servicesEnabled;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCallCount++;
    return true;
  }

  @override
  Future<PostsLocationPermissionState> requestPermission() async {
    requestPermissionCallCount++;
    checkedPermissionState = requestedPermissionState;
    return requestedPermissionState;
  }
}

class _PresenceCall {
  final String status;
  final String capturedAt;
  final int? latE3;
  final int? lngE3;
  final double? accuracyM;
  final String? reason;

  const _PresenceCall({
    required this.status,
    required this.capturedAt,
    this.latE3,
    this.lngE3,
    this.accuracyM,
    this.reason,
  });
}

void main() {
  late InMemoryPostsPrivacySettingsRepository repository;
  late _FakeNearbyLocationPlatformAdapter platformAdapter;
  late List<_PresenceCall> presenceCalls;
  late NearbyLocationServiceImpl service;

  setUp(() {
    repository = InMemoryPostsPrivacySettingsRepository(
      initialSettings: const PostsPrivacySettings(sharingEnabled: true),
    );
    platformAdapter = _FakeNearbyLocationPlatformAdapter();
    presenceCalls = <_PresenceCall>[];
    service = NearbyLocationServiceImpl(
      settingsRepository: repository,
      platformAdapter: platformAdapter,
      publishPostPresenceUpdate:
          ({
            required status,
            required capturedAt,
            latE3,
            lngE3,
            accuracyM,
            reason,
          }) async {
            presenceCalls.add(
              _PresenceCall(
                status: status,
                capturedAt: capturedAt,
                latE3: latE3,
                lngE3: lngE3,
                accuracyM: accuracyM,
                reason: reason,
              ),
            );
          },
      now: () => DateTime.parse('2026-03-15T10:00:00.000Z'),
    );
  });

  tearDown(() {
    repository.dispose();
  });

  test(
    'startup silent refresh never prompts when permission is denied',
    () async {
      platformAdapter.checkedPermissionState =
          PostsLocationPermissionState.denied;

      final availability = await service.refreshSilentlyOnStartup();

      expect(platformAdapter.requestPermissionCallCount, 0);
      expect(
        availability.state,
        NearbyComposeAvailabilityState.permissionRequired,
      );
      expect(
        (await repository.load()).permissionState,
        PostsLocationPermissionState.denied,
      );
    },
  );

  test(
    'settings interactive refresh may prompt and stores coarse snapshot',
    () async {
      platformAdapter.checkedPermissionState =
          PostsLocationPermissionState.denied;
      platformAdapter.requestedPermissionState =
          PostsLocationPermissionState.granted;
      platformAdapter.currentPosition = NearbyDevicePosition(
        latitude: 52.52,
        longitude: 13.405,
        accuracyM: 120,
        capturedAt: DateTime.parse('2026-03-15T10:00:00.000Z'),
      );

      final availability = await service.refreshInteractivelyFromSettings();

      final settings = await repository.load();
      expect(platformAdapter.requestPermissionCallCount, 1);
      expect(availability.state, NearbyComposeAvailabilityState.ready);
      expect(settings.permissionState, PostsLocationPermissionState.granted);
      expect(settings.lastLocalLatE3, 52520);
      expect(settings.lastLocalLngE3, 13405);
      expect(presenceCalls, hasLength(1));
      expect(presenceCalls.single.status, 'active');
      expect(presenceCalls.single.latE3, 52520);
      expect(presenceCalls.single.lngE3, 13405);
    },
  );

  test('compose interactive refresh keeps denied-forever state', () async {
    platformAdapter.checkedPermissionState =
        PostsLocationPermissionState.deniedForever;

    final availability = await service.refreshInteractivelyFromCompose();

    expect(platformAdapter.requestPermissionCallCount, 0);
    expect(
      availability.state,
      NearbyComposeAvailabilityState.permissionDeniedForever,
    );
    expect(
      (await repository.load()).permissionState,
      PostsLocationPermissionState.deniedForever,
    );
  });

  test('posts-open silent refresh reuses a fresh snapshot', () async {
    await repository.save(
      const PostsPrivacySettings(
        sharingEnabled: true,
        permissionState: PostsLocationPermissionState.granted,
        lastLocalLatE3: 52520,
        lastLocalLngE3: 13405,
        lastLocalCapturedAt: '2026-03-15T09:50:00.000Z',
        lastLocalAccuracyM: 120,
      ),
    );

    final availability = await service.refreshSilentlyOnPostsOpen();

    expect(availability.state, NearbyComposeAvailabilityState.ready);
    expect(platformAdapter.getCurrentPositionCallCount, 0);
    expect(platformAdapter.requestPermissionCallCount, 0);
  });

  test('silent refresh publishes inactive when services turn off', () async {
    await repository.save(
      const PostsPrivacySettings(
        sharingEnabled: true,
        permissionState: PostsLocationPermissionState.granted,
        lastLocalLatE3: 52520,
        lastLocalLngE3: 13405,
        lastLocalCapturedAt: '2026-03-15T09:50:00.000Z',
        lastLocalAccuracyM: 120,
      ),
    );
    platformAdapter.servicesEnabled = false;

    final availability = await service.refreshSilentlyOnResume();

    expect(availability.state, NearbyComposeAvailabilityState.servicesOff);
    expect(presenceCalls, hasLength(1));
    expect(presenceCalls.single.status, 'inactive');
    expect(presenceCalls.single.reason, 'services_disabled');
    expect((await repository.load()).lastLocalCapturedAt, isNull);
  });

  test(
    'silent refresh publishes inactive when permission is revoked',
    () async {
      await repository.save(
        const PostsPrivacySettings(
          sharingEnabled: true,
          permissionState: PostsLocationPermissionState.granted,
          lastLocalLatE3: 52520,
          lastLocalLngE3: 13405,
          lastLocalCapturedAt: '2026-03-15T09:50:00.000Z',
          lastLocalAccuracyM: 120,
        ),
      );
      platformAdapter.checkedPermissionState =
          PostsLocationPermissionState.denied;

      final availability = await service.refreshSilentlyOnResume();

      expect(
        availability.state,
        NearbyComposeAvailabilityState.permissionRequired,
      );
      expect(presenceCalls, hasLength(1));
      expect(presenceCalls.single.status, 'inactive');
      expect(presenceCalls.single.reason, 'permission_revoked');
      expect((await repository.load()).lastLocalCapturedAt, isNull);
    },
  );

  test('sharing disabled publishes inactive immediately', () async {
    await repository.save(
      const PostsPrivacySettings(
        sharingEnabled: true,
        permissionState: PostsLocationPermissionState.granted,
        lastLocalLatE3: 52520,
        lastLocalLngE3: 13405,
        lastLocalCapturedAt: '2026-03-15T09:50:00.000Z',
        lastLocalAccuracyM: 120,
      ),
    );

    await service.handleSharingDisabled();

    expect(presenceCalls, hasLength(1));
    expect(presenceCalls.single.status, 'inactive');
    expect(presenceCalls.single.reason, 'sharing_disabled');
  });
}
