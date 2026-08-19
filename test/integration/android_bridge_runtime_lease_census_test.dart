// Plan 390 (gap G15) — Android integration harnesses and the canonical-runtime
// lease.
//
// On Android the native `GoBridge` is constructed only inside MainActivity's
// `attachRuntimeOwner` lambda (`MainActivity.kt:89-92`), which the Dart
// `mknoon/canonical_runtime_lease` channel triggers. A harness that constructs
// `GoBridgeClient()` without first acquiring that lease never gets the
// `com.mknoon/go_bridge` channel: every bridge call returns `ok:false` (both
// `invokeMethod` sites share one `on MissingPluginException` catch,
// `go_bridge_client.dart:921-954`) and `generateNewIdentity` collapses it into
// `GenerateIdentityResult.coreLibError` about a second into setup, naming no
// cause.
//
// This census is a REGRESSION TRIPWIRE, not a proof. It cannot execute Android,
// so it cannot show that the lease makes the bridge reachable — the device leg
// does that. What it does prove is structural:
//
//   1. Exactly one owner takes the process-wide writable lease on any one
//      runtime path. Two owners with different bindings is not "extra safety":
//      the native broker re-returns a live token ONLY for an identical
//      (ownerId, binding, role) triple (`CanonicalRuntimeLease.kt:55-62`) and
//      otherwise answers `lease_unavailable` (`:185-188`), which
//      `MethodChannelCanonicalRuntimeLeaseGateway.acquire` does not catch — so
//      the second acquire throws out of `setUpAll` and kills the run.
//   2. Every `GoBridgeClient()` construction under `integration_test/` is
//      covered, either by the constructing file itself or by EVERY entrypoint
//      that can reach it.
//
// Known escapes, recorded rather than papered over: a lease reference in a dead
// helper, a comment or a string constant; a bridge constructed in `main()`'s
// body before `setUpAll` runs; a lease inside `group(skip: true)`; and — the
// dominant one — dispatch-conditional reachability, where an entrypoint imports
// a covered library on one code path and an uncovered one on another. The
// coverage rule below is deliberately import-level and conservative about that
// last case: transitive reachability of a seam does NOT count for an
// entrypoint, only self-guarding of the constructing file does.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Pinned scope
// ---------------------------------------------------------------------------

/// Only `integration_test/` is censused. `lib/` holds two production bridge
/// constructions whose lease is held by their caller (the production bootstrap),
/// and widening the walk to cover them would report both as offenders.
const String _scanRoot = 'integration_test';

/// A floor, not the exact count — 227 `.dart` files at authoring (2026-08-19).
/// Without this the whole census passes vacuously when the walk finds nothing.
const int _minimumScannedDartFiles = 200;

/// Entrypoints exempted from the lease requirement.
///
/// Must stay disjoint from [_executedEntrypoints]: an allow-list that may name
/// a file a real command runs is a tautology, since seeding it with every
/// offender would turn the census green with nothing repaired.
const Set<String> _allowList = <String>{};

/// Entrypoints a real repo command runs, derived at execution time (Plan 390
/// Step 1) rather than asserted from the plan. An entry qualifies when one of:
///
///   (a) a `run_test_gates.sh` array or gate that is actually dispatched —
///       NOT `NIGHTLY_ONLY_TESTS` / `OPTIONAL_MANUAL_TESTS` / `OUT_OF_GATE_TESTS`,
///       which are read only inside `classify_path` (`:1441`, `:1446`, `:1451`)
///       and never run;
///   (b) an `active` capability in `tool/sims/critical_features.json`;
///   (c) selection by `run_reliability_simulations.sh`'s filter over
///       `check_reliability_simulation_discovery.sh --records-tsv` (category in
///       {1to1, group, intro, move-feature} AND type in {runner, test}), or
///       being the harness such a selected runner launches;
///   (d) a repo script that `flutter test`s / `dart run`s it directly.
const Set<String> _executedEntrypoints = <String>{
  // (c) 1to1/runner run_1to1_reaction_notification_device.dart -> capture
  // driver -> `flutter build apk --target` + install + launch.
  'integration_test/android_background_crypto_preflight_app.dart',
  // (a) `run_test_gates.sh benchmark-sim` dispatches it once per BENCHMARK key.
  'integration_test/benchmark_harness.dart',
  // (c) records 1to1/test.
  'integration_test/cold_start_sendable_no_user_action_test.dart',
  'integration_test/conversation_bridge_test.dart',
  'integration_test/soak_e2e_test.dart',
  // (c) records group/test.
  'integration_test/group_invite_reliability_proof_test.dart',
  'integration_test/group_real_crypto_onboarding_test.dart',
  'integration_test/group_removal_rotation_keyless_converge_proof_test.dart',
  'integration_test/group_removal_rotation_keyless_proof_test.dart',
  // (c) records group/test; also (a) `run_test_gates.sh
  // group-real-network-nightly`, conditional on CLI_PEER_FIXTURE.
  'integration_test/group_recovery_cli_e2e_test.dart',
  // (c) launched by run_routing_smoke_e2e.dart (1to1/runner + group/runner).
  'integration_test/routing_smoke_harness.dart',
  // (b) capability `performance.device.critical` builds profile
  // `android.e2e.standard`, whose target is this dispatcher.
  'integration_test/sims_dispatcher.dart',
  // (d) `scripts/run_transport_census.sh` flutter-tests it directly.
  'integration_test/transport_census_harness.dart',
};

/// The three harnesses that already held the seam before this plan. They must
/// stay singly-leased — a second acquire here is the same defect the census
/// exists to stop.
const List<String> _preExistingLeasedHarnesses = <String>[
  'integration_test/background_reconnect_test.dart',
  'integration_test/transport_e2e_test.dart',
  'integration_test/wifi_relay_fallback_smoke_test.dart',
];

/// The shared joiner inside the group harness. It runs on paths that may or may
/// not already hold the lease, so it must consult status before acquiring.
const String _groupHarness =
    'integration_test/group_multi_device_real_harness.dart';
const String _joinerName = 'ensureCanonicalRuntimeAttachedForTest';

// ---------------------------------------------------------------------------
// Matchers
// ---------------------------------------------------------------------------

/// Type-exact. A token matcher on `Lease` or `acquire` would clear
/// `android_background_crypto_preflight_app.dart`, which carries 17 unrelated
/// `DurableNotificationToneLease` hits plus an unrelated `acquire`.
final RegExp _leaseSeam = RegExp(
  r'\bCanonicalRuntimeDeviceTestLease\b|\b' + _joinerName + r'\b',
);

/// Construction of the process-wide lease owner. One per runtime path.
final RegExp _leaseOwnerConstruction = RegExp(
  r'\bCanonicalRuntimeDeviceTestLease\s*\(',
);

/// Any bridge client construction, including subclasses such as
/// `RecordingGoBridgeClient` — a subclass needs the same native channel.
final RegExp _bridgeConstruction = RegExp(r'\b\w*GoBridgeClient\s*\(');

final RegExp _mainDeclaration = RegExp(
  r'^(?:void|Future<void>|Future)\s+main\s*\(',
  multiLine: true,
);

final RegExp _relativeDirective = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

// ---------------------------------------------------------------------------
// Census model
// ---------------------------------------------------------------------------

class _Census {
  _Census({
    required this.scannedFiles,
    required this.entrypoints,
    required this.constructionSites,
    required this.selfGuardedSites,
    required this.closures,
    required this.sources,
  });

  final List<String> scannedFiles;
  final Set<String> entrypoints;
  final Set<String> constructionSites;
  final Set<String> selfGuardedSites;
  final Map<String, Set<String>> closures;
  final Map<String, String> sources;

  bool _leases(String file) => _leaseSeam.hasMatch(sources[file] ?? '');

  /// `(construction site, entrypoint)` pairs the census reports as unrepaired.
  ///
  /// A site is covered when the constructing file itself holds a seam
  /// (self-guarded — it takes or joins the lease next to the construction), or
  /// when the entrypoint that reaches it holds one. Transitive reachability of
  /// a seam through some OTHER file does not count: whether that file's seam
  /// actually runs is dispatch-dependent, and a census cannot see which branch
  /// a `--dart-define` selects.
  List<String> unleasedPairs({Set<String> allowList = _allowList}) {
    final findings = <String>[];
    for (final site in constructionSites.toList()..sort()) {
      if (selfGuardedSites.contains(site)) continue;
      final reaching =
          entrypoints.where((e) => closures[e]!.contains(site)).toList()
            ..sort();
      if (reaching.isEmpty) {
        findings.add('$site <- (no entrypoint reaches it; nothing can lease)');
        continue;
      }
      for (final entrypoint in reaching) {
        if (allowList.contains(entrypoint)) continue;
        if (_leases(entrypoint)) continue;
        findings.add('$site <- $entrypoint');
      }
    }
    return findings;
  }

  /// Files that construct a lease owner. The file DECLARING the class is not
  /// one of them — `CanonicalRuntimeDeviceTestLease({required this.binding});`
  /// is a constructor declaration, not a construction.
  int _ownersConstructedIn(String file) {
    final source = sources[file] ?? '';
    if (RegExp(r'class\s+CanonicalRuntimeDeviceTestLease\b').hasMatch(source)) {
      return 0;
    }
    return _leaseOwnerConstruction.allMatches(source).length;
  }

  /// Entrypoints whose runtime path constructs more than one lease owner.
  ///
  /// A construction inside ANOTHER entrypoint's file does not count: only one
  /// `main()` runs per process, so an imported entrypoint's `main()`-scoped
  /// lease never executes. Seven harnesses import
  /// `group_multi_device_real_harness.dart` for `setupGroupMultiDeviceStack`
  /// without running its `main()`, and charging them for its lease would be
  /// wrong.
  List<String> multiOwnerEntrypoints() {
    final findings = <String>[];
    for (final entrypoint in entrypoints.toList()..sort()) {
      final owners = <String>[];
      for (final file in closures[entrypoint]!.toList()..sort()) {
        if (file != entrypoint && entrypoints.contains(file)) continue;
        for (var index = 0; index < _ownersConstructedIn(file); index += 1) {
          owners.add(file);
        }
      }
      if (owners.length > 1) {
        findings.add('$entrypoint owns ${owners.length} leases: $owners');
      }
    }
    return findings;
  }

  /// Files whose lease owner is acquired without being released, or acquired
  /// more than once. A `runApp` entrypoint has no test teardown, so a missing
  /// release is only a finding for files that use the `flutter_test` lifecycle.
  List<String> unpairedLeaseFiles() {
    final findings = <String>[];
    for (final file in scannedFiles) {
      final source = sources[file]!;
      if (_ownersConstructedIn(file) == 0) continue;
      final acquires = RegExp(r'\.acquire\b').allMatches(source).length;
      final releases = RegExp(r'\.release\b').allMatches(source).length;
      final hasTestLifecycle = source.contains('setUpAll(');
      if (acquires != 1) {
        findings.add('$file: expected 1 lease acquire, found $acquires');
      }
      if (hasTestLifecycle && releases != 1) {
        findings.add('$file: expected 1 lease release, found $releases');
      }
    }
    return findings;
  }
}

_Census _censusOf(String root) {
  final sources = <String, String>{};
  final directory = Directory(root);
  if (directory.existsSync()) {
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      sources[entity.path] = entity.readAsStringSync();
    }
  }
  final scannedFiles = sources.keys.toList()..sort();

  final edges = <String, Set<String>>{
    for (final file in scannedFiles) file: <String>{},
  };
  for (final file in scannedFiles) {
    for (final match in _relativeDirective.allMatches(sources[file]!)) {
      final uri = match.group(1)!;
      if (uri.startsWith('package:') || uri.startsWith('dart:')) continue;
      final target = _normalize('${_dirname(file)}/$uri');
      if (sources.containsKey(target)) edges[file]!.add(target);
    }
  }

  final closures = <String, Set<String>>{};
  for (final file in scannedFiles) {
    final seen = <String>{file};
    final stack = <String>[file];
    while (stack.isNotEmpty) {
      for (final next in edges[stack.removeLast()]!) {
        if (seen.add(next)) stack.add(next);
      }
    }
    closures[file] = seen;
  }

  return _Census(
    scannedFiles: scannedFiles,
    entrypoints: scannedFiles
        .where((f) => _mainDeclaration.hasMatch(sources[f]!))
        .toSet(),
    constructionSites: scannedFiles
        .where((f) => _bridgeConstruction.hasMatch(sources[f]!))
        .toSet(),
    selfGuardedSites: scannedFiles
        .where(
          (f) =>
              _bridgeConstruction.hasMatch(sources[f]!) &&
              _leaseSeam.hasMatch(sources[f]!),
        )
        .toSet(),
    closures: closures,
    sources: sources,
  );
}

String _dirname(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? '.' : path.substring(0, index);
}

String _normalize(String path) {
  final absolute = path.startsWith('/');
  final parts = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  // An absolute root must stay absolute: fixture trees live under an absolute
  // temp path, and dropping the leading slash silently resolves every import
  // to nothing, which reads as "no entrypoint reaches this library".
  return (absolute ? '/' : '') + parts.join('/');
}

/// Body of a top-level function, by brace matching from its declaration.
String _functionBody(String source, String name) {
  final declaration = RegExp(
    r'^(?:void|Future<void>|Future)\s+' + name + r'\s*\([^)]*\)\s*(?:async\s*)?\{',
    multiLine: true,
  ).firstMatch(source);
  if (declaration == null) return '';
  var depth = 0;
  for (var index = declaration.end - 1; index < source.length; index += 1) {
    if (source[index] == '{') depth += 1;
    if (source[index] == '}') {
      depth -= 1;
      if (depth == 0) return source.substring(declaration.end, index);
    }
  }
  return '';
}

// ---------------------------------------------------------------------------
// Fixtures (only where a synthetic tree is the point — TC-390-01/02/03)
// ---------------------------------------------------------------------------

Directory _fixture(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('lease_census_fixture');
  addTearDown(() => root.deleteSync(recursive: true));
  files.forEach((relative, contents) {
    final file = File('${root.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  return root;
}

const String _bareEntrypoint = '''
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';

void main() {
  testWidgets('bare', (tester) async {
    final bridge = GoBridgeClient();
    await bridge.initialize();
  });
}
''';

const String _leasedEntrypointImportingLibrary = '''
import 'package:flutter_test/flutter_test.dart';

import '_support/canonical_runtime_device_test_lease.dart';
import 'shared_library.dart';

void main() {
  final runtimeLease = CanonicalRuntimeDeviceTestLease(
    binding: 'fixture-device-test',
  );
  setUpAll(runtimeLease.acquire);
  tearDownAll(runtimeLease.release);

  testWidgets('leased', (tester) async {
    await createFixtureNode();
  });
}
''';

const String _unleasedEntrypointImportingLibrary = '''
import 'package:flutter_test/flutter_test.dart';

import 'shared_library.dart';

void main() {
  testWidgets('unleased', (tester) async {
    await createFixtureNode();
  });
}
''';

/// No `main()`, so it cannot host `setUpAll` and cannot repair itself.
const String _libraryConstructingBridge = '''
library;

import 'package:flutter_app/core/bridge/go_bridge_client.dart';

Future<void> createFixtureNode() async {
  final bridge = GoBridgeClient();
  await bridge.initialize();
}
''';

// ---------------------------------------------------------------------------

void main() {
  final census = _censusOf(_scanRoot);

  test('no harness acquires the runtime lease twice', () {
    // The shared joiner runs on paths that already hold the lease (an
    // entrypoint's own `CanonicalRuntimeDeviceTestLease`) and on paths that do
    // not. Acquiring unconditionally under its own fixed binding collides with
    // the first kind: same ownerId and role, different binding, so the
    // identical-triple branch does not match, state is ACTIVE not RELEASED, the
    // broker returns null and Kotlin answers `lease_unavailable`.
    final body = _functionBody(census.sources[_groupHarness]!, _joinerName);
    expect(
      body,
      isNotEmpty,
      reason: '$_joinerName must exist in $_groupHarness',
    );
    final statusAt = body.indexOf('.status(');
    final acquireAt = body.indexOf('.acquire(');
    expect(
      acquireAt,
      isNot(-1),
      reason: '$_joinerName must still be able to acquire',
    );
    expect(
      statusAt,
      isNot(-1),
      reason:
          '$_joinerName must consult the lease status before acquiring, so an '
          'entrypoint that already owns the lease is joined rather than '
          'collided with',
    );
    expect(
      statusAt < acquireAt,
      isTrue,
      reason: 'the status check must precede the acquire, not follow it',
    );

    expect(
      census.multiOwnerEntrypoints(),
      isEmpty,
      reason: 'exactly one lease owner may exist on any one runtime path',
    );
    expect(
      census.unpairedLeaseFiles(),
      isEmpty,
      reason: 'every lease owner is acquired once and released once',
    );
  });

  test(
    'a new unleased bridge construction is reported and the scan is non-empty',
    () {
      expect(
        census.scannedFiles.length,
        greaterThanOrEqualTo(_minimumScannedDartFiles),
        reason:
            'the census must prove it scanned a real tree; a walk that finds '
            'nothing reports zero offenders and passes for the wrong reason',
      );

      final root = _fixture(<String, String>{
        'new_harness_test.dart': _bareEntrypoint,
      });
      final findings = _censusOf(root.path).unleasedPairs();
      expect(findings, hasLength(1));
      expect(findings.single, contains('new_harness_test.dart'));

      // The scan-count assertion is what a misdirected root trips.
      expect(_censusOf('${root.path}/does_not_exist').scannedFiles, isEmpty);
    },
  );

  test('the lease matcher is type-exact and scans every dart file', () {
    // A token matcher on `Lease` / `acquire` clears this file. The real
    // `android_background_crypto_preflight_app.dart` is exactly this shape.
    const decoyEntrypoint = '''
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';

void main() {
  testWidgets('decoy', (tester) async {
    final tone = DurableNotificationToneLease();
    await tone.acquire();
    final bridge = GoBridgeClient();
    await bridge.initialize();
  });
}
''';
    final decoyRoot = _fixture(<String, String>{
      'decoy_app.dart': decoyEntrypoint,
    });
    expect(
      _censusOf(decoyRoot.path).unleasedPairs(),
      hasLength(1),
      reason:
          'unrelated `Lease` and `acquire` tokens must not satisfy the census',
    );

    // 9 of the 20 real offender files are not `*_test.dart`, including every
    // no-`main()` library. A walk filtered to `_test.dart` would scan neither
    // the library nor the harness entrypoint below.
    final libraryRoot = _fixture(<String, String>{
      'shared_library.dart': _libraryConstructingBridge,
      'consumer_harness.dart': _unleasedEntrypointImportingLibrary,
    });
    final libraryCensus = _censusOf(libraryRoot.path);
    expect(
      libraryCensus.scannedFiles.where((f) => f.endsWith('shared_library.dart')),
      isNotEmpty,
    );
    expect(
      libraryCensus.entrypoints.where((f) => f.endsWith('consumer_harness.dart')),
      isNotEmpty,
      reason: 'a non-`_test.dart` entrypoint must still be walked',
    );
    final libraryFindings = libraryCensus.unleasedPairs();
    expect(libraryFindings, hasLength(1));
    expect(libraryFindings.single, contains('shared_library.dart'));
    expect(libraryFindings.single, contains('consumer_harness.dart'));
  });

  test('a no-main library requires all of its entrypoints to lease', () {
    final root = _fixture(<String, String>{
      '_support/canonical_runtime_device_test_lease.dart':
          'class CanonicalRuntimeDeviceTestLease {}',
      'shared_library.dart': _libraryConstructingBridge,
      'covered_entrypoint_test.dart': _leasedEntrypointImportingLibrary,
      'bare_entrypoint_test.dart': _unleasedEntrypointImportingLibrary,
    });
    final findings = _censusOf(root.path).unleasedPairs();
    expect(
      findings,
      hasLength(1),
      reason:
          'the library cannot repair itself; charging it, or clearing it as '
          'soon as ONE entrypoint leases, both leave a real path unleased',
    );
    expect(findings.single, contains('bare_entrypoint_test.dart'));
    expect(findings.single, isNot(contains('covered_entrypoint_test.dart')));
  });

  test('the allow-list contains no executed harness', () {
    expect(
      _allowList.intersection(_executedEntrypoints),
      isEmpty,
      reason:
          'an allow-list that may name an executed harness is a tautology — '
          'seeding it with every offender would turn this census green with '
          'nothing repaired',
    );
    for (final entrypoint in _executedEntrypoints) {
      expect(
        File(entrypoint).existsSync(),
        isTrue,
        reason: 'the executed list must name real files',
      );
    }
    expect(
      census.unleasedPairs(),
      isEmpty,
      reason:
          'every bridge construction under $_scanRoot is covered by its own '
          'file or by every entrypoint that reaches it',
    );
  });

  test('the leased transport harnesses hold exactly one acquire', () {
    for (final harness in _preExistingLeasedHarnesses) {
      final source = census.sources[harness];
      expect(source, isNotNull, reason: '$harness must exist');
      expect(
        _leaseOwnerConstruction.allMatches(source!).length,
        1,
        reason: '$harness must construct exactly one lease owner',
      );
      expect(RegExp(r'\.acquire\b').allMatches(source).length, 1);
      expect(RegExp(r'\.release\b').allMatches(source).length, 1);
      expect(census.multiOwnerEntrypoints(), isEmpty);
    }

    // `BENCHMARK=GROUP_PUBLISH` reaches `setupGroupMultiDeviceStack`, which
    // joins the runtime through the group harness. Leasing the benchmark
    // entrypoint must therefore not create a second owner on that path.
    const benchmarkEntrypoint = 'integration_test/benchmark_harness.dart';
    expect(census.entrypoints, contains(benchmarkEntrypoint));
    expect(
      _leaseSeam.hasMatch(census.sources[benchmarkEntrypoint]!),
      isTrue,
      reason: 'the single dispatched benchmark entrypoint must hold the lease',
    );
    expect(
      census.closures[benchmarkEntrypoint]!.contains(_groupHarness),
      isTrue,
      reason: 'GROUP_PUBLISH still reaches the group stack',
    );

    // Discovery-only check of the benchmark dispatch — never a full perf run.
    expect(
      File('scripts/run_test_gates.sh').readAsStringSync(),
      contains(benchmarkEntrypoint),
      reason: 'the benchmark gate must still dispatch this entrypoint',
    );
  });

  test('production bridge constructions are not censused', () {
    expect(
      census.scannedFiles.where((f) => f.startsWith('lib/')),
      isEmpty,
      reason: 'widening the walk to lib/ would report the production bootstrap',
    );
    const productionSite =
        'lib/app/bootstrap/production_canonical_inbox_projection_composition.dart';
    expect(File(productionSite).existsSync(), isTrue);
    expect(
      census.unleasedPairs().where((f) => f.contains(productionSite)),
      isEmpty,
    );
  });
}
