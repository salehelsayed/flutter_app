import 'package:flutter_test/flutter_test.dart';

import 'group_recovery_cli_e2e_test.dart' as group_recovery_e2e;
import 'transport_e2e_test.dart' as transport_e2e;

const _configuredRelayAddresses = String.fromEnvironment(
  'MKNOON_RELAY_ADDRESSES',
  defaultValue: '',
);
const _requireConfiguredMultiRelayAddresses = bool.fromEnvironment(
  'MKNOON_REQUIRE_MULTI_RELAY',
);

List<String> _configuredMultiRelayAddresses() {
  return _configuredRelayAddresses
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

bool _hasConfiguredMultiRelayAddresses() {
  final addresses = _configuredMultiRelayAddresses();
  return addresses.length >= 2;
}

void main() {
  if (!_hasConfiguredMultiRelayAddresses()) {
    if (_requireConfiguredMultiRelayAddresses) {
      testWidgets('multi-relay fixture is required for this closure run', (
        _,
      ) async {
        fail(
          'MKNOON_REQUIRE_MULTI_RELAY=true requires at least two comma-separated '
          'MKNOON_RELAY_ADDRESSES entries via --dart-define.',
        );
      });
      return;
    }

    testWidgets(
      'two relay failover keeps 1:1 delivery working (requires MKNOON_RELAY_ADDRESSES)',
      (_) async {},
      skip: true,
    );
    testWidgets(
      'two relay failover keeps group recovery working (requires MKNOON_RELAY_ADDRESSES)',
      (_) async {},
      skip: true,
    );
    return;
  }

  transport_e2e.main();
  group_recovery_e2e.main();
}
