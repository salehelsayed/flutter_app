/// Pure oracle for the Wave 4 shared-XCTest caller: one centrally built and
/// attested bundle serves several selector runs with independent fixtures and
/// results, rejects changed provenance before any xcodebuild launch, cleans
/// up exactly, and needs fewer builds than the original fresh-build route.
List<String> validateProductionSharedXCTest(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool ok, String message) {
    if (!ok) failures.add(message);
  }

  require(proof['profileId'] == 'ios.device.production', 'shared profile');
  final digest = proof['artifactDigest'];
  require(
    digest is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(digest),
    'attested artifact digest',
  );
  final shared = proof['sharedBuild'];
  require(
    shared is Map &&
        shared['logicalBuildCount'] == 1 &&
        shared['centralCompileCommands'] == 1 &&
        shared['childBuildCount'] == 0,
    'one central build, no child builds',
  );

  final rejections = proof['rejections'];
  require(
    rejections is List &&
        rejections.length >= 2 &&
        rejections.every(
          (r) => r is Map && r['rejected'] == true && r['xcodebuildCalls'] == 0,
        ) &&
        {
          for (final r in rejections.cast<Map>()) r['case'],
        }.containsAll({'changed bundle bytes', 'wrong input digest'}),
    'changed bundle and wrong digest rejected before xcodebuild',
  );

  final runs = proof['runs'];
  if (runs is! List || runs.length < 2) {
    failures.add('at least two selector runs from one bundle');
    return failures;
  }
  final selector = proof['selector'];
  final fixtures = <Object?>{};
  final results = <Object?>{};
  for (final raw in runs) {
    if (raw is! Map) {
      failures.add('malformed run');
      continue;
    }
    fixtures.add(raw['fixtureId']);
    results.add(raw['resultBundle']);
    final id = raw['fixtureId'];
    require(raw['status'] == 'PASS', '$id selector passed');
    require(raw['selector'] == selector, '$id exact selector');
    require(raw['childBuilds'] == 0, '$id no child build');
    require(raw['artifactDigest'] == digest, '$id same attested bundle');
    require(raw['profileId'] == proof['profileId'], '$id same profile');
    require(raw['deviceId'] == proof['deviceId'], '$id pinned device');
    final evidence = raw['fixtureEvidence'];
    require(
      evidence is Map &&
          evidence['fixtureId'] == id &&
          evidence['status'] == 'PASS',
      '$id fixture-bound assertion',
    );
    final cleanup = raw['cleanup'];
    require(
      cleanup is Map &&
          cleanup['status'] == 'PASS' &&
          cleanup['fixtureId'] == id,
      '$id exact cleanup',
    );
  }
  require(fixtures.length == runs.length, 'independent fixtures per run');
  require(results.length == runs.length, 'independent result bundles per run');

  final actions = proof['xcodebuildActions'];
  require(
    actions is List &&
        actions.length == runs.length &&
        actions.every((a) => a == 'xcodebuild test-without-building'),
    'only test-without-building, once per selector run',
  );
  final original = proof['originalRoute'];
  require(
    original is Map &&
        original['buildsPerSelectorRun'] == 1 &&
        shared is Map &&
        (shared['logicalBuildCount'] as int? ?? 99) <
            runs.length * (original['buildsPerSelectorRun'] as int),
    'fewer builds than the original route',
  );
  return failures;
}
