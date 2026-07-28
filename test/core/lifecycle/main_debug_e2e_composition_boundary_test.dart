import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production entry and bootstrap own no concrete debug E2E harness', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final productionSource = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final rootFile = File('lib/debug/debug_e2e_composition_root.dart');

    const forbiddenMainFragments = <String>[
      'GroupMediaReliabilityE2EController.forInstalledProfile(',
      'GroupMediaIosBackgroundE2EController.forInstalledProfile(',
      'PrivateMediaOutboxE2EController(',
      'WakeTokenAcceptedAttachmentObserver()',
      'runGroupMediaIosDisposableResetIfRequested(',
      'resolveAutoSetupUsername(',
      'exportIdentityForIntroE2E(',
      'IosSenderProjectionFixtureStore(',
      'runIosSenderProjectionFixtureLoop(',
      'startIntroE2EPoller(',
      'publishIosReceiverBootstrapIdentityWhenReady(',
      'GroupMediaIosBackgroundE2EOverlay(',
      'startGroupMediaDisposableTransportNode(',
    ];

    for (final fragment in forbiddenMainFragments) {
      expect(
        mainSource,
        isNot(contains(fragment)),
        reason: 'lib/main.dart still constructs or starts $fragment',
      );
      expect(
        productionSource,
        isNot(contains(fragment)),
        reason:
            'production bootstrap bypasses the debug composition root for '
            '$fragment',
      );
    }

    expect(rootFile.existsSync(), isTrue);
    final rootSource = rootFile.readAsStringSync();
    for (final fragment in forbiddenMainFragments) {
      expect(
        rootSource,
        contains(fragment),
        reason: 'the separate composition root must own $fragment',
      );
    }
    expect(
      rootSource,
      isNot(contains("import 'package:flutter_app/main.dart'")),
      reason: 'the debug root must receive navigation/dependencies as ports',
    );
  });
}
