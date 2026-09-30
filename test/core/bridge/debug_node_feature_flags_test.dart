import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/bridge/debug_node_feature_flags.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';

void main() {
  tearDown(() => debugNodeFeatureFlagOverrides = const {});

  test('node start flags carry no debug override by default', () {
    expect(debugNodeFeatureFlagOverrides, isEmpty);
    expect(
      defaultResilienceFeatureFlags().containsKey('debugAdvertiseRelayOnly'),
      isFalse,
    );
  });

  test('a debug override is merged into the node start flags', () {
    debugNodeFeatureFlagOverrides = const {'debugAdvertiseRelayOnly': true};
    final flags = defaultResilienceFeatureFlags();
    expect(flags['debugAdvertiseRelayOnly'], isTrue);
    expect(flags['enableSharedRelayBackend'], isNotNull);
  });
}
