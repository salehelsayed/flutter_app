import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

// 164 (cold-start-5): the share-intent probe and the documents-directory probe
// are independent and must overlap (Future.wait). The discriminator also guards
// against a "parallelize by hoisting Firebase back onto the critical path"
// anti-fix: Firebase must stay UNIFORMLY DEFERRED (no eager top-level
// ensureFirebaseReady() await re-introduced).
void main() {
  test(
    'TC-164-03 share-intent probe and docs-dir run concurrently (Future.wait); '
    'Firebase stays uniformly deferred',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final productionSource = await File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsString();

      // (i) the two probes overlap via Future.wait inside the share-launch-probe
      // window, and neither call is awaited inline before the join.
      final probeStart = productionSource.indexOf(
        "StartupTiming.instance.mark('share_launch_probe_begin')",
      );
      final probeEnd = productionSource.indexOf(
        "StartupTiming.instance.mark('share_launch_probe_complete')",
      );
      expect(probeStart, isNonNegative);
      expect(probeEnd, greaterThan(probeStart));
      final probeBlock = productionSource.substring(probeStart, probeEnd);
      expect(
        probeBlock,
        contains('Future.wait'),
        reason: 'the two independent launch probes must overlap',
      );

      final rootBuildIndex = productionSource.indexOf(
        'Future<Widget> _buildRootWidget() async {',
      );
      expect(rootBuildIndex, isNonNegative);
      final preRootBuild = productionSource.substring(0, rootBuildIndex);
      expect(
        preRootBuild,
        isNot(contains('await shareIntentService.captureInitialIntent()')),
        reason: 'the share-intent probe must not be awaited inline before join',
      );
      expect(
        preRootBuild,
        isNot(contains('await getApplicationDocumentsDirectory()')),
        reason: 'the docs-dir probe must not be awaited inline before join',
      );

      // (ii) no eager top-level ensureFirebaseReady() await is re-introduced —
      // the only surviving call site is inside startLiveServices (deferred).
      final startLiveIndex = productionSource.indexOf(
        'Future<void> startLiveServices()',
      );
      expect(startLiveIndex, isNonNegative);
      final preStartLive = productionSource.substring(0, startLiveIndex);
      expect(
        preStartLive,
        isNot(contains('await ensureFirebaseReady()')),
        reason:
            'parallelizing must not hoist Firebase back onto the critical path '
            '(that would undo cold-start-1)',
      );

      // (iii) the StartupTiming marks survive.
      expect(
        productionSource,
        contains("StartupTiming.instance.mark('share_launch_probe_begin')"),
      );
      expect(
        productionSource,
        contains("StartupTiming.instance.mark('share_launch_probe_complete')"),
      );
      expect(
        productionSource,
        contains("StartupTiming.instance.mark('documents_dir_ready')"),
      );
    },
  );
}
