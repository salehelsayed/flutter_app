import 'package:geolocator/geolocator.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';

const Duration _nearbyFreshnessTtl = Duration(minutes: 30);

typedef PublishPostPresenceUpdateFn =
    Future<void> Function({
      required String status,
      required String capturedAt,
      int? latE3,
      int? lngE3,
      double? accuracyM,
      String? reason,
    });

enum NearbyComposeAvailabilityState {
  sharingOff,
  permissionRequired,
  permissionDeniedForever,
  servicesOff,
  stale,
  ready,
}

class NearbyComposeAvailability {
  final NearbyComposeAvailabilityState state;

  const NearbyComposeAvailability({required this.state});

  bool get canRefresh {
    return switch (state) {
      NearbyComposeAvailabilityState.permissionRequired ||
      NearbyComposeAvailabilityState.servicesOff ||
      NearbyComposeAvailabilityState.stale => true,
      _ => false,
    };
  }

  bool get canOpenSettings =>
      state == NearbyComposeAvailabilityState.permissionDeniedForever;
}

class NearbyDevicePosition {
  final double latitude;
  final double longitude;
  final double accuracyM;
  final DateTime capturedAt;

  const NearbyDevicePosition({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.capturedAt,
  });
}

abstract class NearbyLocationPlatformAdapter {
  Future<bool> isLocationServiceEnabled();

  Future<PostsLocationPermissionState> checkPermissionState();

  Future<PostsLocationPermissionState> requestPermission();

  Future<NearbyDevicePosition?> getCurrentPosition();

  Future<bool> openAppSettings();
}

abstract class NearbyLocationService {
  Future<NearbyComposeAvailability> loadComposeAvailability();

  Future<NearbyComposeAvailability> refreshSilentlyOnStartup();

  Future<NearbyComposeAvailability> refreshSilentlyOnResume();

  Future<NearbyComposeAvailability> refreshSilentlyOnPostsOpen();

  Future<NearbyComposeAvailability> refreshInteractivelyFromSettings();

  Future<NearbyComposeAvailability> refreshInteractivelyFromCompose();

  Future<void> handleSharingDisabled();

  Future<bool> openAppSettings();
}

class NearbyLocationServiceImpl implements NearbyLocationService {
  final PostsPrivacySettingsRepository settingsRepository;
  final NearbyLocationPlatformAdapter platformAdapter;
  final PublishPostPresenceUpdateFn? publishPostPresenceUpdate;
  final DateTime Function() now;

  NearbyLocationServiceImpl({
    required this.settingsRepository,
    required this.platformAdapter,
    this.publishPostPresenceUpdate,
    DateTime Function()? now,
  }) : now = now ?? (() => DateTime.now().toUtc());

  @override
  Future<NearbyComposeAvailability> loadComposeAvailability() async {
    final settings = await settingsRepository.load();
    return _availabilityForSettings(
      settings,
      servicesEnabled: await platformAdapter.isLocationServiceEnabled(),
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnStartup() {
    return _refresh(allowPrompt: false);
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnResume() {
    return _refresh(allowPrompt: false);
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnPostsOpen() async {
    final settings = await settingsRepository.load();
    final availability = _availabilityForSettings(
      settings,
      servicesEnabled: await platformAdapter.isLocationServiceEnabled(),
    );
    if (availability.state != NearbyComposeAvailabilityState.stale) {
      return availability;
    }
    return _refresh(allowPrompt: false);
  }

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromSettings() {
    return _refresh(allowPrompt: true);
  }

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromCompose() {
    return _refresh(allowPrompt: true);
  }

  @override
  Future<void> handleSharingDisabled() async {
    final current = await settingsRepository.load();
    if (!_hasPublishedSnapshot(current)) {
      return;
    }
    await publishPostPresenceUpdate?.call(
      status: 'inactive',
      capturedAt: now().toUtc().toIso8601String(),
      reason: 'sharing_disabled',
    );
  }

  @override
  Future<bool> openAppSettings() {
    return platformAdapter.openAppSettings();
  }

  Future<NearbyComposeAvailability> _refresh({
    required bool allowPrompt,
  }) async {
    final current = await settingsRepository.load();
    final refreshAttemptAt = now().toUtc().toIso8601String();

    if (!current.sharingEnabled) {
      return const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.sharingOff,
      );
    }

    final servicesEnabled = await platformAdapter.isLocationServiceEnabled();
    if (!servicesEnabled) {
      await settingsRepository.save(
        current.copyWith(
          clearSnapshot: true,
          lastRefreshAttemptAt: refreshAttemptAt,
        ),
      );
      await _publishInactiveIfNeeded(
        current,
        reason: 'services_disabled',
        capturedAt: refreshAttemptAt,
      );
      return const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.servicesOff,
      );
    }

    final permissionState = allowPrompt
        ? await _requestPermissionIfNeeded()
        : await platformAdapter.checkPermissionState();

    if (permissionState != PostsLocationPermissionState.granted) {
      await settingsRepository.save(
        current.copyWith(
          permissionState: permissionState,
          clearSnapshot: true,
          lastRefreshAttemptAt: refreshAttemptAt,
        ),
      );
      await _publishInactiveIfNeeded(
        current,
        reason: 'permission_revoked',
        capturedAt: refreshAttemptAt,
      );
      return NearbyComposeAvailability(
        state: permissionState == PostsLocationPermissionState.deniedForever
            ? NearbyComposeAvailabilityState.permissionDeniedForever
            : NearbyComposeAvailabilityState.permissionRequired,
      );
    }

    final position = await platformAdapter.getCurrentPosition();
    if (position == null) {
      await settingsRepository.save(
        current.copyWith(
          permissionState: permissionState,
          lastRefreshAttemptAt: refreshAttemptAt,
        ),
      );
      return const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.stale,
      );
    }

    final updated = current.copyWith(
      permissionState: permissionState,
      lastLocalLatE3: (position.latitude * 1000).round(),
      lastLocalLngE3: (position.longitude * 1000).round(),
      lastLocalCapturedAt: position.capturedAt.toUtc().toIso8601String(),
      lastLocalAccuracyM: position.accuracyM,
      lastRefreshAttemptAt: refreshAttemptAt,
    );
    await settingsRepository.save(updated);
    await _publishActiveIfPossible(updated);

    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.ready,
    );
  }

  Future<void> _publishActiveIfPossible(PostsPrivacySettings settings) async {
    final latE3 = settings.lastLocalLatE3;
    final lngE3 = settings.lastLocalLngE3;
    final capturedAt = settings.lastLocalCapturedAt;
    final accuracyM = settings.lastLocalAccuracyM;
    if (latE3 == null ||
        lngE3 == null ||
        capturedAt == null ||
        accuracyM == null) {
      return;
    }
    await publishPostPresenceUpdate?.call(
      status: 'active',
      capturedAt: capturedAt,
      latE3: latE3,
      lngE3: lngE3,
      accuracyM: accuracyM,
    );
  }

  Future<void> _publishInactiveIfNeeded(
    PostsPrivacySettings current, {
    required String reason,
    required String capturedAt,
  }) async {
    if (!_hasPublishedSnapshot(current)) {
      return;
    }
    await publishPostPresenceUpdate?.call(
      status: 'inactive',
      capturedAt: capturedAt,
      reason: reason,
    );
  }

  bool _hasPublishedSnapshot(PostsPrivacySettings current) {
    return current.lastLocalCapturedAt != null &&
        current.lastLocalLatE3 != null &&
        current.lastLocalLngE3 != null &&
        current.lastLocalAccuracyM != null;
  }

  Future<PostsLocationPermissionState> _requestPermissionIfNeeded() async {
    final currentPermission = await platformAdapter.checkPermissionState();
    if (currentPermission == PostsLocationPermissionState.granted ||
        currentPermission == PostsLocationPermissionState.deniedForever) {
      return currentPermission;
    }
    return platformAdapter.requestPermission();
  }

  NearbyComposeAvailability _availabilityForSettings(
    PostsPrivacySettings settings, {
    required bool servicesEnabled,
  }) {
    if (!settings.sharingEnabled) {
      return const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.sharingOff,
      );
    }
    if (!servicesEnabled) {
      return const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.servicesOff,
      );
    }
    if (settings.permissionState ==
        PostsLocationPermissionState.deniedForever) {
      return const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.permissionDeniedForever,
      );
    }
    if (settings.permissionState != PostsLocationPermissionState.granted) {
      return const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.permissionRequired,
      );
    }
    if (!settings.hasFreshSnapshotAt(now(), ttl: _nearbyFreshnessTtl)) {
      return const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.stale,
      );
    }
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.ready,
    );
  }
}

class GeolocatorNearbyLocationPlatformAdapter
    implements NearbyLocationPlatformAdapter {
  @override
  Future<PostsLocationPermissionState> checkPermissionState() async {
    return _mapPermission(await Geolocator.checkPermission());
  }

  @override
  Future<NearbyDevicePosition?> getCurrentPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.medium),
    );
    return NearbyDevicePosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
      capturedAt: position.timestamp.toUtc(),
    );
  }

  @override
  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<bool> openAppSettings() {
    return Geolocator.openAppSettings();
  }

  @override
  Future<PostsLocationPermissionState> requestPermission() async {
    return _mapPermission(await Geolocator.requestPermission());
  }

  PostsLocationPermissionState _mapPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.denied => PostsLocationPermissionState.denied,
      LocationPermission.deniedForever =>
        PostsLocationPermissionState.deniedForever,
      LocationPermission.always ||
      LocationPermission.whileInUse => PostsLocationPermissionState.granted,
      _ => PostsLocationPermissionState.unknown,
    };
  }
}
