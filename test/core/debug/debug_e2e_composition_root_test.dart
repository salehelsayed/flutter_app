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
    const plan397IosSetup = DebugE2EActivation(
      isDebugMode: false,
      e2eTestMode: true,
      directTextProofMode: false,
      installedSimsProfile: 'ios.device.group_reaction_notification_397',
    );

    expect(emptyDebug.constructsControllerRoot, isFalse);
    expect(emptyRelease.constructsControllerRoot, isFalse);

    for (final activation in <DebugE2EActivation>[
      debugE2E,
      directText,
      androidDisposable,
      iosDisposableRelease,
      iosProduction,
      plan397IosSetup,
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
    expect(plan397IosSetup.startsIntroPoller, isTrue);
    expect(iosProduction.startsIosSenderProjection, isTrue);
    expect(iosProduction.publishesIosReceiverBootstrap, isTrue);
    expect(iosProduction.decoratesIosGroupMediaProof, isFalse);
    expect(iosProduction.suppliesDisposableNodeStart, isFalse);
    expect(androidDisposable.suppliesDisposableNodeStart, isTrue);
    expect(iosDisposableRelease.suppliesDisposableNodeStart, isTrue);
    expect(iosDisposableRelease.decoratesIosGroupMediaProof, isTrue);
    expect(plan397IosSetup.suppliesDisposableNodeStart, isFalse);
    expect(plan397IosSetup.decoratesIosGroupMediaProof, isFalse);
  });

  test(
    'composition phases preserve reset root-build post-launch runtime-ready and poller ownership',
    () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final applicationRootSource = File(
        'lib/app/application_root.dart',
      ).readAsStringSync();
      final debugRootSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      final autoSetupSource = File(
        'lib/core/debug/auto_setup_config.dart',
      ).readAsStringSync();
      expect(
        mainSource,
        contains(
          'runApplicationBootstrap(\n'
          '    bootstrapFactory: ProductionApplicationBootstrap.new,',
        ),
        reason: 'the public entrypoint must delegate through the stable runner',
      );

      final reset = productionSource.indexOf('runDisposableResetIfRequested()');
      final appStart = productionSource.indexOf(
        "StartupTiming.instance.mark('app_start')",
      );
      final rootCreation = productionSource.indexOf(
        'DebugE2ECompositionRoot.tryCreate(',
      );
      final documentsReady = productionSource.indexOf(
        'final appDocDir = await appDocDirProbe;',
      );
      final autoSetup = productionSource.indexOf(
        'runSimulatorAutoSetupIfConfigured(',
      );
      final bridge = productionSource.indexOf('final Bridge bridge =');
      final localP2P = productionSource.indexOf('// Create local P2P service');
      final buildRootStart = productionSource.indexOf(
        'Future<Widget> _buildRootWidget() async {',
      );
      final buildRootEnd = productionSource.indexOf(
        'void _afterRunApp() {',
        buildRootStart,
      );
      final buildRoot = productionSource.substring(
        buildRootStart,
        buildRootEnd,
      );
      final prepopulate = buildRoot.indexOf('prepopulateContactsBeforeRunApp(');
      final myApp = buildRoot.indexOf('return MyApp(');
      final afterRunAppEnd = productionSource.indexOf(
        'return _CallbackPreparedApplication(',
        buildRootEnd,
      );
      final afterRunApp = productionSource.substring(
        buildRootEnd,
        afterRunAppEnd,
      );
      final sender = afterRunApp.indexOf(
        'startIosSenderProjectionAfterRunApp(',
      );
      final runAppCalled = afterRunApp.indexOf(
        "StartupTiming.instance.mark('run_app_called')",
      );
      final poller = afterRunApp.indexOf('startIntroPollerAfterColdRecovery(');

      expect(reset, greaterThanOrEqualTo(0));
      expect(reset, lessThan(appStart));
      expect(documentsReady, lessThan(rootCreation));
      expect(bridge, lessThan(autoSetup));
      expect(autoSetup, lessThan(localP2P));
      expect(prepopulate, greaterThanOrEqualTo(0));
      expect(myApp, greaterThan(prepopulate));
      expect(sender, greaterThanOrEqualTo(0));
      expect(sender, lessThan(runAppCalled));
      expect(runAppCalled, lessThan(poller));
      expect(
        afterRunApp,
        contains(
          'if (debugE2EComposition?.startsIntroPoller ?? false) {\n'
          '        debugE2EComposition!.startIntroPollerAfterColdRecovery(',
        ),
        reason:
            'the iOS production sender/receiver root must not build an '
            'inactive poller dependency bundle',
      );
      expect(
        applicationRootSource,
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
        applicationRootSource,
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
          debugRootSource,
          contains(token),
          reason: 'missing root token $token',
        );
      }
      expect(autoSetupSource, contains('AUTO_SETUP_USERNAME'));
      expect(autoSetupSource, contains('auto_setup.json'));
    },
  );
}
