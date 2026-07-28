import 'dart:io';

import 'package:flutter_app/core/debug/group_media_ios_background_e2e.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e.dart';
import 'package:flutter_app/debug/debug_e2e_composition_root.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default composition invokes zero harness controller factories', () {
    var reliabilityFactoryCalls = 0;
    var iosBackgroundFactoryCalls = 0;

    final root = DebugE2ECompositionRoot.tryCreate(
      stateDirectory: Directory.systemTemp,
      activation: const DebugE2EActivation(
        isDebugMode: false,
        e2eTestMode: false,
        directTextProofMode: false,
        installedSimsProfile: '',
      ),
      reliabilityControllerFactory: (_) {
        reliabilityFactoryCalls++;
        throw StateError('default reliability factory was invoked');
      },
      iosBackgroundControllerFactory: (_) {
        iosBackgroundFactoryCalls++;
        throw StateError('default iOS factory was invoked');
      },
    );

    expect(root, isNull);
    expect(reliabilityFactoryCalls, 0);
    expect(iosBackgroundFactoryCalls, 0);
  });

  test(
    'authorized debug E2E composition invokes both controller factories',
    () {
      final stateDirectory = Directory.systemTemp.createTempSync(
        'dtr13-active-root-',
      );
      addTearDown(() => stateDirectory.deleteSync(recursive: true));
      var reliabilityFactoryCalls = 0;
      var iosBackgroundFactoryCalls = 0;

      final root = DebugE2ECompositionRoot.tryCreate(
        stateDirectory: stateDirectory,
        activation: const DebugE2EActivation(
          isDebugMode: true,
          e2eTestMode: true,
          directTextProofMode: false,
          installedSimsProfile: 'android.e2e.main',
        ),
        reliabilityControllerFactory: (directory) {
          reliabilityFactoryCalls++;
          return GroupMediaReliabilityE2EController.forInstalledProfile(
            stateDirectory: directory,
            installedProfileId: 'android.e2e.main',
          );
        },
        iosBackgroundControllerFactory: (directory) {
          iosBackgroundFactoryCalls++;
          return GroupMediaIosBackgroundE2EController.forInstalledProfile(
            stateDirectory: directory,
            installedProfileId: 'android.e2e.main',
          );
        },
      );

      expect(root, isNotNull);
      expect(reliabilityFactoryCalls, 1);
      expect(iosBackgroundFactoryCalls, 1);
    },
  );

  test('component policy preserves every independent proof activation', () {
    const emptyDebug = DebugE2EActivation(
      isDebugMode: true,
      e2eTestMode: false,
      directTextProofMode: false,
      installedSimsProfile: '',
    );
    const emptyRelease = DebugE2EActivation(
      isDebugMode: false,
      e2eTestMode: false,
      directTextProofMode: false,
      installedSimsProfile: '',
    );
    const debugE2E = DebugE2EActivation(
      isDebugMode: true,
      e2eTestMode: true,
      directTextProofMode: false,
      installedSimsProfile: 'android.e2e.main',
    );
    const directText = DebugE2EActivation(
      isDebugMode: true,
      e2eTestMode: false,
      directTextProofMode: true,
      installedSimsProfile: '',
    );
    const androidDisposable = DebugE2EActivation(
      isDebugMode: true,
      e2eTestMode: true,
      directTextProofMode: false,
      installedSimsProfile: 'android.e2e.group_media_269',
    );
    const iosDisposableRelease = DebugE2EActivation(
      isDebugMode: false,
      e2eTestMode: true,
      directTextProofMode: false,
      installedSimsProfile: 'ios.device.group_media_269',
    );
    const iosProduction = DebugE2EActivation(
      isDebugMode: false,
      e2eTestMode: false,
      directTextProofMode: false,
      installedSimsProfile: 'ios.device.production',
    );

    expect(emptyDebug.constructsControllerRoot, isFalse);
    expect(emptyRelease.constructsControllerRoot, isFalse);

    for (final activation in <DebugE2EActivation>[
      debugE2E,
      directText,
      androidDisposable,
      iosDisposableRelease,
      iosProduction,
    ]) {
      expect(activation.constructsControllerRoot, isTrue);
      expect(activation.constructsPrivateMediaController, isTrue);
      expect(activation.constructsWakeTokenObserver, isTrue);
    }

    expect(debugE2E.startsIntroPoller, isTrue);
    expect(directText.startsIntroPoller, isTrue);
    expect(androidDisposable.startsIntroPoller, isTrue);
    expect(iosDisposableRelease.startsIntroPoller, isTrue);
    expect(iosProduction.startsIntroPoller, isFalse);
    expect(iosProduction.startsIosSenderProjection, isTrue);
    expect(iosProduction.publishesIosReceiverBootstrap, isTrue);
    expect(iosProduction.decoratesIosGroupMediaProof, isFalse);
    expect(iosProduction.suppliesDisposableNodeStart, isFalse);
    expect(androidDisposable.suppliesDisposableNodeStart, isTrue);
    expect(iosDisposableRelease.suppliesDisposableNodeStart, isTrue);
    expect(iosDisposableRelease.decoratesIosGroupMediaProof, isTrue);
  });

  test(
    'composition phases preserve reset auto-setup runApp fixture runtime-ready and poller ownership',
    () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final rootSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      final autoSetupSource = File(
        'lib/core/debug/auto_setup_config.dart',
      ).readAsStringSync();
      final reset = mainSource.indexOf('runDisposableResetIfRequested(');
      final appStart = mainSource.indexOf(
        "StartupTiming.instance.mark('app_start')",
      );
      final rootCreation = mainSource.indexOf(
        'DebugE2ECompositionRoot.tryCreate(',
      );
      final documentsReady = mainSource.indexOf(
        'final appDocDir = await appDocDirProbe;',
      );
      final autoSetup = mainSource.indexOf(
        'runSimulatorAutoSetupIfConfigured(',
      );
      final bridge = mainSource.indexOf('final Bridge bridge =');
      final localP2P = mainSource.indexOf('// Create local P2P service');
      final runApp = mainSource.indexOf('runApp(\n    MyApp(');
      final sender = mainSource.indexOf('startIosSenderProjectionAfterRunApp(');
      final runAppCalled = mainSource.indexOf(
        "StartupTiming.instance.mark('run_app_called')",
      );
      final poller = mainSource.indexOf('startIntroPollerAfterColdRecovery(');

      expect(reset, greaterThanOrEqualTo(0));
      expect(reset, lessThan(appStart));
      expect(documentsReady, lessThan(rootCreation));
      expect(bridge, lessThan(autoSetup));
      expect(autoSetup, lessThan(localP2P));
      expect(runApp, lessThan(sender));
      expect(sender, lessThan(runAppCalled));
      expect(runAppCalled, lessThan(poller));
      expect(
        mainSource,
        contains(
          'if (debugE2EComposition?.startsIntroPoller ?? false) {\n'
          '    debugE2EComposition!.startIntroPollerAfterColdRecovery(',
        ),
        reason:
            'the iOS production sender/receiver root must not build an '
            'inactive poller dependency bundle',
      );
      expect(
        mainSource,
        contains(
          'final debugE2EAfterRuntimeReady = '
          'widget.debugE2EAfterRuntimeReady;\n'
          '    if (debugE2EAfterRuntimeReady != null) {',
        ),
        reason:
            'default composition must not create a runtime-ready harness '
            'closure',
      );
      expect(
        mainSource,
        contains(
          '_ensureRuntimeServicesReady().then((_) => '
          'debugE2EAfterRuntimeReady())',
        ),
      );
      for (final token in const <String>[
        'runSimulatorAutoSetupIfConfigured',
        'unawaited(\n      runIosSenderProjectionFixtureLoop(',
        'publishIosReceiverBootstrapIdentityWhenReady(',
        'startIntroE2EPoller(',
      ]) {
        expect(
          rootSource,
          contains(token),
          reason: 'missing root token $token',
        );
      }
      expect(autoSetupSource, contains('AUTO_SETUP_USERNAME'));
      expect(autoSetupSource, contains('auto_setup.json'));
    },
  );
}
