import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';

class _FakeNearbyLocationService implements NearbyLocationService {
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
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.sharingOff,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromCompose() async {
    refreshInteractivelyFromComposeCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.ready,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromSettings() async {
    refreshInteractivelyFromSettingsCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.ready,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnPostsOpen() async {
    refreshSilentlyOnPostsOpenCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.stale,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnResume() async {
    refreshSilentlyOnResumeCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.stale,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnStartup() async {
    refreshSilentlyOnStartupCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.stale,
    );
  }

  @override
  Future<void> handleSharingDisabled() async {
    handleSharingDisabledCallCount++;
  }

  @override
  Future<bool> openAppSettings() async => true;
}

void main() {
  test('resume uses silent nearby refresh when service is provided', () async {
    final service = _FakeNearbyLocationService();

    await handleAppResumed(
      bridge: FakeBridge(),
      p2pService: FakeP2PService(),
      nearbyLocationService: service,
    );

    expect(service.refreshSilentlyOnResumeCallCount, 1);
    expect(service.refreshInteractivelyFromSettingsCallCount, 0);
    expect(service.refreshInteractivelyFromComposeCallCount, 0);
  });
}
