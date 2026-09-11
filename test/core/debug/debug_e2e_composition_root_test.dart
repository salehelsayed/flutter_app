import 'dart:io';

import 'package:flutter_app/app/bootstrap/android_production_audio_call_e2e_observer.dart';
import 'package:flutter_app/core/debug/android_production_audio_call_e2e.dart';
import 'package:flutter_app/core/debug/group_media_ios_background_e2e.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e.dart';
import 'package:flutter_app/debug/debug_e2e_composition_root.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'P269 ordinary Android mode uses normal startup while iOS stays distinct',
    () {
      for (final profile in <String>[
        'android.e2e.group_media_269',
        'ios.device.group_media_269',
      ]) {
        final activation = DebugE2EActivation(
          isDebugMode: true,
          e2eTestMode: true,
          directTextProofMode: false,
          installedSimsProfile: profile,
          groupMediaAuthorityModeName: 'accountBoundLegacy',
        );
        expect(
          activation.suppliesDisposableNodeStart,
          profile.startsWith('ios'),
        );
        expect(
          activation.groupMediaAuthorityMode.name,
          profile.startsWith('ios')
              ? 'distinctAccountAndTransport'
              : 'accountBoundLegacy',
        );
        expect(activation.constructsControllerRoot, isTrue);
        expect(activation.startsIntroPoller, isTrue);
      }
      const invalid = DebugE2EActivation(
        isDebugMode: true,
        e2eTestMode: true,
        directTextProofMode: false,
        installedSimsProfile: 'android.e2e.group_media_269',
        groupMediaAuthorityModeName: 'unknown',
      );
      expect(() => invalid.suppliesDisposableNodeStart, throwsFormatException);
    },
  );

  test(
    'intro E2E conversation routing carries the process-owned outgoing call capability',
    () {
      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final debugRootSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      final dependencyDeclaration = debugRootSource.substring(
        debugRootSource.indexOf('final class DebugE2EPollerDependencies'),
        debugRootSource.indexOf('/// Pure compile-time activation policy'),
      );
      final productionPollerDependencies = productionSource.substring(
        productionSource.indexOf('DebugE2EPollerDependencies('),
        productionSource.indexOf(
          '\n          ),',
          productionSource.indexOf('DebugE2EPollerDependencies('),
        ),
      );
      final debugConversationRoute = debugRootSource.substring(
        debugRootSource.indexOf('openConversationByPeerId:'),
        debugRootSource.indexOf(
          '\n      },',
          debugRootSource.indexOf('openConversationByPeerId:'),
        ),
      );

      expect(
        dependencyDeclaration,
        contains('required this.outgoingCallCapability,'),
        reason: 'the debug poller must own an explicit call-capability seam',
      );
      expect(
        productionPollerDependencies,
        contains('outgoingCallCapability: callSignalingComposition,'),
        reason:
            'production must supply its process-owned call-signaling composition',
      );
      expect(
        debugConversationRoute,
        contains(
          'outgoingCallCapability: dependencies.outgoingCallCapability,',
        ),
        reason:
            'the debug-created ConversationWired must receive that capability',
      );
      expect(
        debugConversationRoute,
        isNot(contains('directRouteAuthority:')),
        reason:
            'debug routing deliberately has no linked-device route authority',
      );
    },
  );

  test(
    'intro E2E call-wake distribution uses production signaling callbacks',
    () {
      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final debugRootSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      final dependencyDeclaration = debugRootSource.substring(
        debugRootSource.indexOf('final class DebugE2EPollerDependencies'),
        debugRootSource.indexOf('/// Pure compile-time activation policy'),
      );
      final startPoller = debugRootSource.substring(
        debugRootSource.indexOf('startIntroE2EPoller('),
        debugRootSource.indexOf(
          '\n    );',
          debugRootSource.indexOf('startIntroE2EPoller('),
        ),
      );
      final productionPollerDependencies = productionSource.substring(
        productionSource.indexOf('DebugE2EPollerDependencies('),
        productionSource.indexOf(
          '\n          ),',
          productionSource.indexOf('DebugE2EPollerDependencies('),
        ),
      );
      final normalizedProductionPollerDependencies =
          productionPollerDependencies.replaceAll(RegExp(r'\s+'), ' ');

      for (final callback in const [
        'resolveCallWakeHandle',
        'onCallWakeHandleDistributed',
      ]) {
        expect(dependencyDeclaration, contains('required this.$callback,'));
        expect(startPoller, contains('$callback: dependencies.$callback,'));
        expect(
          normalizedProductionPollerDependencies,
          contains('$callback: callSignalingComposition.$callback,'),
        );
      }
    },
  );

  test('default composition invokes zero harness controller factories', () {
    var reliabilityFactoryCalls = 0;
    var iosBackgroundFactoryCalls = 0;
    var productionCallObserverFactoryCalls = 0;

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
      productionCallObserverFactory: () {
        productionCallObserverFactoryCalls++;
        throw StateError('default production-call observer was invoked');
      },
    );

    expect(root, isNull);
    expect(reliabilityFactoryCalls, 0);
    expect(iosBackgroundFactoryCalls, 0);
    expect(productionCallObserverFactoryCalls, 0);
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
      var productionCallObserverFactoryCalls = 0;

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
        productionCallObserverFactory: () {
          productionCallObserverFactoryCalls++;
          throw StateError('unrelated profile constructed call observer');
        },
      );

      expect(root, isNotNull);
      expect(reliabilityFactoryCalls, 1);
      expect(iosBackgroundFactoryCalls, 1);
      expect(productionCallObserverFactoryCalls, 0);
    },
  );

  test(
    'dedicated Android production-call profile constructs one observer only',
    () {
      final stateDirectory = Directory.systemTemp.createTempSync(
        'production-call-observer-root-',
      );
      addTearDown(() => stateDirectory.deleteSync(recursive: true));
      var observerFactoryCalls = 0;

      final root = DebugE2ECompositionRoot.tryCreate(
        stateDirectory: stateDirectory,
        activation: const DebugE2EActivation(
          isDebugMode: true,
          isAndroid: true,
          e2eTestMode: true,
          directTextProofMode: false,
          androidProductionAudioCallE2EEnabled: true,
          installedSimsProfile: androidProductionAudioCallE2EBuildProfile,
        ),
        productionCallObserverFactory: () {
          observerFactoryCalls++;
          return AndroidProductionAudioCallE2EObserver.tryCreate(
            enabled: true,
            isAndroid: true,
            installedProfileId: androidProductionAudioCallE2EBuildProfile,
          )!;
        },
      );

      expect(root, isNotNull);
      expect(root!.startsIntroPoller, isTrue);
      expect(observerFactoryCalls, 1);
      final firstDispose = root.dispose();
      final secondDispose = root.dispose();
      expect(identical(firstDispose, secondDispose), isTrue);
      return firstDispose;
    },
  );

  test('component policy preserves every independent proof activation', () {
    const emptyDebug = DebugE2EActivation(
      isDebugMode: true,
      e2eTestMode: false,
      directTextProofMode: false,
      installedSimsProfile: '',
    );
    const productionCall = DebugE2EActivation(
      isDebugMode: true,
      isAndroid: true,
      e2eTestMode: true,
      directTextProofMode: false,
      androidProductionAudioCallE2EEnabled: true,
      installedSimsProfile: androidProductionAudioCallE2EBuildProfile,
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
      productionCall,
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
    expect(productionCall.startsIntroPoller, isTrue);
    expect(productionCall.constructsProductionAudioCallObserver, isTrue);
    expect(debugE2E.constructsProductionAudioCallObserver, isFalse);
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
      final appDelegateSource = File(
        'ios/Runner/AppDelegate.swift',
      ).readAsStringSync();
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
        RegExp(
          r'\bawait\s+runApplicationBootstrap\s*\(\s*'
          r'bootstrapFactory:\s*ProductionApplicationBootstrap\.new\s*,',
        ).allMatches(mainSource),
        hasLength(1),
        reason: 'the public entrypoint must delegate through the stable runner',
      );
      final dartMainEntry = mainSource.indexOf(
        'acknowledgeGroupReactionNotificationIosDartMainEntryIfConfigured()',
      );
      final applicationBootstrap = mainSource.indexOf(
        'runApplicationBootstrap(',
      );
      expect(dartMainEntry, greaterThanOrEqualTo(0));
      expect(
        dartMainEntry,
        lessThan(applicationBootstrap),
        reason:
            'the exact Plan-398 Dart entry receipt must close before '
            'production bootstrap',
      );

      final nativeEntry = appDelegateSource.indexOf(
        'iosSetupReadinessEntryCoordinator.armNativeLaunch(',
      );
      final didFinishSuper = appDelegateSource.indexOf(
        'super.application(application, didFinishLaunchingWithOptions:',
      );
      final implicitEngine = appDelegateSource.indexOf(
        'func didInitializeImplicitFlutterEngine(',
      );
      final entryBridge = appDelegateSource.indexOf(
        'setupIosSetupReadinessEntryBridge(messenger: messenger)',
        implicitEngine,
      );
      expect(nativeEntry, greaterThanOrEqualTo(0));
      expect(nativeEntry, lessThan(didFinishSuper));
      expect(implicitEngine, greaterThanOrEqualTo(0));
      expect(
        entryBridge,
        greaterThan(implicitEngine),
        reason:
            'the Dart-main acknowledgement channel must use the existing '
            'implicit-engine messenger boundary',
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
        'armGroupReactionNotificationIosSetupBootstrapReadinessIfConfigured',
        'runSimulatorAutoSetupIfConfigured',
        'resolveGroupReactionNotificationIosSetupReadinessAttempt(',
        'buildGroupReactionNotificationIosSetupBootstrapReadinessReceipt(',
        'runGroupReactionNotificationIosSetupReadiness<IdentityModel>(',
        'writeGroupReactionNotificationIosSetupReadinessReceipt(',
        'unawaited(\n      runIosSenderProjectionFixtureLoop(',
        'publishIosReceiverBootstrapIdentityWhenReady(',
        'startIntroE2EPoller(',
        'runAndroidProductionAudioCallE2E:',
        'bindAndroidProductionAudioCallObservationSource',
      ]) {
        expect(
          debugRootSource,
          contains(token),
          reason: 'missing root token $token',
        );
      }
      expect(autoSetupSource, contains('AUTO_SETUP_USERNAME'));
      expect(autoSetupSource, contains('auto_setup.json'));
      expect(
        productionSource,
        contains('onGraphBuilt: (graph) {'),
        reason: 'production graph must bind only read-only call observations',
      );
      expect(productionSource, contains('graph.readActiveConnectionSnapshot'));
      expect(
        productionSource,
        contains('await debugE2EComposition?.dispose();'),
        reason: 'app detach must stop observer and poller after call shutdown',
      );
      final graphCallback = productionSource.indexOf('onGraphBuilt: (graph) {');
      final graphCallbackTry = productionSource.indexOf('try {', graphCallback);
      final graphBinding = productionSource.indexOf(
        'bindAndroidProductionAudioCallObservationSource(',
        graphCallbackTry,
      );
      final graphCallbackCatch = productionSource.indexOf(
        '} catch (_)',
        graphBinding,
      );
      expect(graphCallback, greaterThanOrEqualTo(0));
      expect(graphCallbackTry, greaterThan(graphCallback));
      expect(graphBinding, greaterThan(graphCallbackTry));
      expect(
        graphCallbackCatch,
        greaterThan(graphBinding),
        reason: 'debug observation cannot throw into production graph build',
      );
      final detachCallback = productionSource.indexOf(
        'onAppDetached: () async {',
      );
      final callShutdown = productionSource.indexOf(
        'await callSignalingComposition.shutdown();',
        detachCallback,
      );
      final detachFinally = productionSource.indexOf(
        '} finally {',
        callShutdown,
      );
      final debugDispose = productionSource.indexOf(
        'await debugE2EComposition?.dispose();',
        detachFinally,
      );
      expect(detachCallback, greaterThanOrEqualTo(0));
      expect(callShutdown, greaterThan(detachCallback));
      expect(detachFinally, greaterThan(callShutdown));
      expect(
        debugDispose,
        greaterThan(detachFinally),
        reason: 'detach must preserve call shutdown and always tear down E2E',
      );
      expect(debugRootSource, contains('await stopIntroE2EPoller();'));
      expect(
        debugRootSource,
        contains('await _productionAudioCallObserver?.dispose();'),
      );
    },
  );
}
