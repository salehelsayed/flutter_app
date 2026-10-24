import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/run_direct_media_blob_custody_sims.dart';

void main() {
  test('campaigns keep the 45 minute fixture timeout by default', () {
    expect(fixtureGoTestTimeout(const {}), '45m');
  });

  test('a hand-driven run may raise it in whole minutes up to 4 hours', () {
    expect(
      fixtureGoTestTimeout(const {'PLAN347_FIXTURE_GO_TIMEOUT': '180m'}),
      '180m',
    );
    expect(
      fixtureGoTestTimeout(const {'PLAN347_FIXTURE_GO_TIMEOUT': '240m'}),
      '240m',
    );
  });

  test('anything else falls back to the default', () {
    for (final bad in ['241m', '0m', '3h', '90', 'm', '45m;rm', ' ']) {
      expect(
        fixtureGoTestTimeout({'PLAN347_FIXTURE_GO_TIMEOUT': bad}),
        '45m',
        reason: bad,
      );
    }
  });
}
