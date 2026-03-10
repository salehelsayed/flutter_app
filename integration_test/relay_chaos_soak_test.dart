import 'package:flutter_test/flutter_test.dart';

import 'soak_e2e_test.dart' as soak_e2e;

const _configuredRelayAddresses = String.fromEnvironment(
  'MKNOON_RELAY_ADDRESSES',
  defaultValue: '',
);

bool _hasConfiguredMultiRelayAddresses() {
  final addresses = _configuredRelayAddresses
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
  return addresses.length >= 2;
}

void main() {
  if (!_hasConfiguredMultiRelayAddresses()) {
    testWidgets(
      'background resume and send remain stable for 30 to 60 minutes under relay churn (requires MKNOON_RELAY_ADDRESSES)',
      (_) async {},
      skip: true,
    );
    return;
  }

  soak_e2e.main();
}
