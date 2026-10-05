import 'package:flutter_test/flutter_test.dart';

import '../../tool/sims/production_shared_xctest_criteria.dart';

const _selector =
    'RunnerUITests/NotificationTapUITests/testAirplaneToggleStateDecoderContract';
final _digest = 'a' * 64;

Map<String, Object?> _run(String id) => {
  'selector': _selector,
  'fixtureId': id,
  'deviceId': '00008030-001A6D2801BB802E',
  'profileId': 'ios.device.production',
  'artifactDigest': _digest,
  'childBuilds': 0,
  'resultBundle': '/proof/xctest-$id-x/result.xcresult',
  'fixtureEvidence': {'fixtureId': id, 'selector': _selector, 'status': 'PASS'},
  'status': 'PASS',
  'cleanup': {'status': 'PASS', 'fixtureId': id},
};

Map<String, Object?> _fixture() => {
  'profileId': 'ios.device.production',
  'selector': _selector,
  'deviceId': '00008030-001A6D2801BB802E',
  'artifactDigest': _digest,
  'sharedBuild': {
    'logicalBuildCount': 1,
    'centralCompileCommands': 1,
    'childBuildCount': 0,
  },
  'originalRoute': {'buildsPerSelectorRun': 1},
  'rejections': [
    {'case': 'changed bundle bytes', 'rejected': true, 'xcodebuildCalls': 0},
    {'case': 'wrong input digest', 'rejected': true, 'xcodebuildCalls': 0},
  ],
  'runs': [_run('shared_a'), _run('shared_b')],
  'xcodebuildActions': [
    'xcodebuild test-without-building',
    'xcodebuild test-without-building',
  ],
};

List<Map<String, Object?>> _runs(Map<String, Object?> p) =>
    (p['runs']! as List).cast<Map<String, Object?>>();

void main() {
  test('accepts one attested bundle serving two independent runs', () {
    expect(validateProductionSharedXCTest(_fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, Object?>)>{
    'a child build': (p) => (p['sharedBuild']! as Map)['childBuildCount'] = 1,
    'two central builds': (p) =>
        (p['sharedBuild']! as Map)['logicalBuildCount'] = 2,
    'tampered bundle accepted': (p) =>
        ((p['rejections']! as List).first as Map)['rejected'] = false,
    'xcodebuild before rejection': (p) =>
        ((p['rejections']! as List).last as Map)['xcodebuildCalls'] = 1,
    'digest rejection missing': (p) => (p['rejections']! as List).removeLast(),
    'one run only': (p) => (p['runs']! as List).removeLast(),
    'shared fixture': (p) => _runs(p).last['fixtureId'] = 'shared_a',
    'shared result bundle': (p) =>
        _runs(p).last['resultBundle'] = _runs(p).first['resultBundle'],
    'failed selector': (p) => _runs(p).first['status'] = 'FAIL',
    'foreign selector': (p) =>
        _runs(p).first['selector'] = 'RunnerUITests/NotificationTapUITests/x',
    'different bundle': (p) => _runs(p).last['artifactDigest'] = 'b' * 64,
    'unbound fixture evidence': (p) =>
        (_runs(p).first['fixtureEvidence']! as Map)['fixtureId'] = 'other',
    'cleanup failed': (p) =>
        (_runs(p).last['cleanup']! as Map)['status'] = 'FAIL',
    'a build action': (p) =>
        (p['xcodebuildActions']! as List)[0] = 'xcodebuild build-for-testing',
    'extra xcodebuild launch': (p) => (p['xcodebuildActions']! as List).add(
      'xcodebuild test-without-building',
    ),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _fixture();
      entry.value(proof);
      expect(validateProductionSharedXCTest(proof), isNotEmpty);
    });
  }
}
