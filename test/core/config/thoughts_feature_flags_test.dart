import 'package:flutter_app/core/config/thoughts_feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a build without the defines ships with thoughts and 3D off', () {
    expect(kThoughtsEnabled, isFalse);
    expect(kOrbitDepthEnabled, isFalse);

    debugThoughtsEnabledOverride = null;
    debugOrbitDepthEnabledOverride = null;
    expect(thoughtsEnabled, isFalse);
    expect(orbitDepthEnabled, isFalse);
  });
}
