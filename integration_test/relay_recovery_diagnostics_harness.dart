// Real Go/MethodChannel recovery with the actual native diagnostic spool.
// REQUIRE_OS_BACKGROUND adds externally driven OS background/foreground proof;
// the default invokes lifecycle handlers directly. Neither proves deep sleep.
// All diagnostic uploads terminate in the local test callback. Only ordinary
// node startup, relay recovery and readiness probes contact the configured relay.
@Tags(['device'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';

import '../test/shared/fakes/in_memory_message_repository.dart';
import '_support/canonical_runtime_device_test_lease.dart';
import 'benchmark_helpers.dart';

const _nativeDiagnostics = MethodChannel('mknoon/app_diagnostics');
const _operationLimit = Duration(seconds: 45);
const _requireOsBackground = bool.fromEnvironment('REQUIRE_OS_BACKGROUND');

final class _ObservedLifecycle with WidgetsBindingObserver {
  _ObservedLifecycle(this.diagnostics);

  final AppDiagnostics diagnostics;
  final paused = Completer<DateTime>();
  final resumed = Completer<DateTime>();
  final states = <String>[];
  bool armed = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // installForTesting intentionally omits observer registration. Forward the
    // real callback, including the production collector's flush behavior.
    diagnostics.didChangeAppLifecycleState(state);
    if (!armed) return;
    states.add(state.name);
    if (state == AppLifecycleState.paused && !paused.isCompleted) {
      paused.complete(DateTime.now());
    }
    if (state == AppLifecycleState.resumed &&
        paused.isCompleted &&
        !resumed.isCompleted) {
      resumed.complete(DateTime.now());
    }
  }

  Future<int> requireBackgroundAndResume({
    required int repetition,
    required bool enabled,
  }) async {
    armed = true;
    print(
      'RELAY_DIAGNOSTICS_OS_BACKGROUND_READY ${jsonEncode({'repetition': repetition, 'diagnosticsEnabled': enabled})}',
    );
    return (() async {
      final pausedAt = await paused.future;
      final resumedAt = await resumed.future;
      print(
        'RELAY_DIAGNOSTICS_OS_BACKGROUND_OBSERVED ${jsonEncode({'repetition': repetition, 'diagnosticsEnabled': enabled, 'states': states})}',
      );
      return resumedAt.difference(pausedAt).inMilliseconds;
    })().timeout(const Duration(seconds: 60));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final lease = CanonicalRuntimeDeviceTestLease(
    binding: 'relay-recovery-diagnostics-device-test',
  );
  setUpAll(lease.acquire);
  tearDownAll(lease.release);

  testWidgets(
    'real relay recovery completes with native diagnostics and pending upload',
    (tester) async {
      final results = <Map<String, Object?>>[];
      // Rotate order so the enabled case is not always the warmed second run.
      for (final trial in <({int repetition, bool enabled})>[
        (repetition: 0, enabled: false),
        (repetition: 0, enabled: true),
        (repetition: 1, enabled: true),
        (repetition: 1, enabled: false),
      ]) {
        final result = await _runTrial(
          repetition: trial.repetition,
          enabled: trial.enabled,
        );
        results.add(result);
        print('RELAY_DIAGNOSTICS_TRIAL ${jsonEncode(result)}');
      }
      print('RELAY_DIAGNOSTICS_DONE ${jsonEncode(results)}');
    },
    timeout: const Timeout(Duration(minutes: 12)),
    skip: !Platform.isAndroid && !Platform.isIOS,
  );
}

Future<Map<String, Object?>> _runTrial({
  required int repetition,
  required bool enabled,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'relay-diagnostics-device-',
  );
  final nativeRows = <Map<String, Object?>>[];
  final localUploadEntered = Completer<void>();
  final releaseLocalUpload = Completer<void>();
  var holdLocalUpload = false;
  var localUploadCompleted = false;
  var localUploadCalls = 0;
  var nativeConfigureSucceeded = false;
  var nativeDrainCalls = 0;
  AppDiagnostics? diagnostics;
  BenchmarkNode? node;
  Future<void>? heldFlush;
  _ObservedLifecycle? lifecycle;
  int? osBackgroundMs;
  try {
    diagnostics = await AppDiagnostics.installForTesting(
      directory: directory,
      enabled: enabled,
      // Never attach the actual Go bridge as a diagnostics transport.
      networkAllowed: () async => false,
      upload: (events) async {
        localUploadCalls++;
        if (holdLocalUpload) {
          if (!localUploadEntered.isCompleted) localUploadEntered.complete();
          await releaseLocalUpload.future;
          localUploadCompleted = true;
        }
        return events.map((event) => event['eventId']! as String).toSet();
      },
      native: (method, arguments) async {
        final response = await _nativeDiagnostics
            .invokeMethod<dynamic>(method, arguments)
            .timeout(const Duration(seconds: 2));
        if (method == 'configure') nativeConfigureSucceeded = response == true;
        if (method == 'drain' && response is Map) {
          nativeDrainCalls++;
          final events = response['events'];
          if (events is List) {
            nativeRows.addAll(
              events.whereType<Map>().map((event) {
                return Map<String, Object?>.from(event);
              }),
            );
          }
        }
        return response;
      },
    ).timeout(const Duration(seconds: 20));
    await diagnostics.clear().timeout(const Duration(seconds: 10));
    await diagnostics.flush().timeout(const Duration(seconds: 10));
    nativeRows.clear();
    expect(nativeConfigureSucceeded, isTrue);
    expect((await diagnostics.status())['nativeStorageHealthy'], isTrue);
    if (_requireOsBackground) {
      lifecycle = _ObservedLifecycle(diagnostics);
      WidgetsBinding.instance.addObserver(lifecycle);
    }

    node = await createBenchmarkNode().timeout(_operationLimit);
    final startup = Stopwatch()..start();
    expect(
      await node.startAndWaitRelayReady().timeout(_operationLimit),
      isTrue,
      reason: 'The actual Go node must first establish usable relay readiness.',
    );
    startup.stop();
    expect(node.service.currentState.sendCapabilityReady, isTrue);
    expect(node.service.currentState.inboxCapabilityReady, isTrue);

    // nodeStatus is instrumented by both native collectors, but requires no
    // relay traffic. Populate a bounded backlog without synthesizing native
    // timestamps or bypassing the native admission/persistence implementation.
    final populate = Stopwatch()..start();
    for (var index = 0; index < 64; index++) {
      final response =
          jsonDecode(
                await node.bridge
                    .send(jsonEncode({'cmd': 'node:status'}))
                    .timeout(const Duration(seconds: 3)),
              )
              as Map;
      expect(response['ok'], isTrue);
    }
    populate.stop();
    await diagnostics.flush().timeout(const Duration(seconds: 10));
    final seededNativeRows = nativeRows.length;
    if (enabled) {
      expect(seededNativeRows, greaterThan(0));
      expect(
        nativeRows.any(
          (event) =>
              event['source'] == (Platform.isIOS ? 'ios' : 'android') &&
              (event['values'] as Map?)?['operation'] == 'other',
        ),
        isTrue,
        reason: 'The actual native nodeStatus observations must be retained.',
      );
      holdLocalUpload = true;
      diagnostics.record(
        feature: 'runtime',
        stage: 'snapshot',
        outcome: 'ok',
        values: {'count': 1},
      );
      heldFlush = diagnostics.flush();
      await localUploadEntered.future.timeout(const Duration(seconds: 10));
      expect(localUploadCompleted, isFalse);
    }

    await handleAppPaused(
      messageRepo: InMemoryMessageRepository(),
    ).timeout(const Duration(seconds: 10));
    final configuredRelays = defaultRelayAddresses();
    final relayPeers = configuredRelays
        .map((address) => address.split('/p2p/').last)
        .toSet();
    for (final peer in relayPeers) {
      final result =
          jsonDecode(
                await node.bridge
                    .send(
                      jsonEncode({
                        'cmd': 'peer:disconnect',
                        'payload': {'peerId': peer},
                      }),
                    )
                    .timeout(const Duration(seconds: 5)),
              )
              as Map;
      expect(result['ok'], isTrue);
    }
    if (lifecycle != null) {
      osBackgroundMs = await lifecycle.requireBackgroundAndResume(
        repetition: repetition,
        enabled: enabled,
      );
    }
    node.service.markResumeStarted();
    node.service.noteTransportSessionReset(
      trigger: 'native_diagnostics_device_recovery',
    );
    final recovery = Stopwatch()..start();
    final reconnected = await callP2PRelayReconnect(
      node.bridge,
    ).timeout(_operationLimit);
    expect(reconnected['ok'], isTrue);
    await handleAppResumed(
      bridge: node.bridge,
      p2pService: node.service,
    ).timeout(_operationLimit);
    expect(
      await waitForRelayReadyBadge(
        node.service,
        timeout: const Duration(seconds: 30),
      ),
      isTrue,
    );
    recovery.stop();
    expect(node.service.currentState.sendCapabilityReady, isTrue);
    expect(node.service.currentState.inboxCapabilityReady, isTrue);
    if (enabled) {
      expect(
        localUploadCompleted,
        isFalse,
        reason:
            'Relay readiness must complete while the upload remains pending.',
      );
    }

    if (!releaseLocalUpload.isCompleted) releaseLocalUpload.complete();
    await heldFlush?.timeout(const Duration(seconds: 10));
    holdLocalUpload = false;
    // Drain through the production Dart/native ACK path. The finite loop also
    // leaves room for bridge completion observations behind the seeded page.
    for (var page = 0; page < 6; page++) {
      await diagnostics.flush().timeout(const Duration(seconds: 10));
    }
    final observedReconnect = nativeRows.any(
      (event) =>
          (event['values'] as Map?)?['operation'] == 'relay_reconnect' &&
          event['outcome'] == 'ok',
    );
    if (enabled) expect(observedReconnect, isTrue);
    final status = await diagnostics.status();
    expect(status['storageHealthy'], isTrue);
    expect(status['nativeStorageHealthy'], isTrue);
    return {
      'platform': Platform.operatingSystem,
      'repetition': repetition,
      'diagnosticsEnabled': enabled,
      'startupMs': startup.elapsedMilliseconds,
      'nativePopulateMs': populate.elapsedMilliseconds,
      'recoveryMs': recovery.elapsedMilliseconds,
      'nativeSeedRowsDrained': seededNativeRows,
      'nativeDrainCalls': nativeDrainCalls,
      'nativeReconnectObserved': observedReconnect,
      'localUploadCalls': localUploadCalls,
      'recoveredBeforeUploadRelease': enabled,
      'diagnosticRelayUploads': 0,
      'sendReady': node.service.currentState.sendCapabilityReady,
      'inboxReady': node.service.currentState.inboxCapabilityReady,
      'relayReady': node.service.currentState.relayReady,
      'lifecycleMode': _requireOsBackground
          ? 'observed_os_background_foreground_without_deep_sleep_claim'
          : 'direct_handlers_without_os_suspension',
      'osPauseObserved': lifecycle?.paused.isCompleted ?? false,
      'osResumeObserved': lifecycle?.resumed.isCompleted ?? false,
      'osBackgroundMs': osBackgroundMs,
      'osLifecycleStates': lifecycle?.states ?? <String>[],
    };
  } finally {
    if (lifecycle != null) WidgetsBinding.instance.removeObserver(lifecycle);
    if (!releaseLocalUpload.isCompleted) releaseLocalUpload.complete();
    await heldFlush?.timeout(const Duration(seconds: 10));
    if (node != null) await node.dispose().timeout(_operationLimit);
    if (diagnostics != null) {
      await diagnostics.setEnabled(false).timeout(const Duration(seconds: 10));
      await diagnostics.dispose().timeout(const Duration(seconds: 10));
    }
    await directory.delete(recursive: true);
  }
}
