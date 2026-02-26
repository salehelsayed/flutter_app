import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Handles app resume lifecycle recovery.
///
/// Checks bridge health (reinitializes if dead), triggers P2P health check,
/// and drains the offline inbox. Returns whether the bridge was healthy.
/// Catches all errors so callers never see exceptions.
Future<bool?> handleAppResumed({
  required Bridge bridge,
  required P2PService p2pService,
}) async {
  final resumeStart = DateTime.now();
  debugPrint('[RESUME] ====== APP RESUME BEGIN ====== ${resumeStart.toIso8601String()}');
  debugPrint('[RESUME] currentState before resume: '
      'isStarted=${p2pService.currentState.isStarted}, '
      'circuitAddresses=${p2pService.currentState.circuitAddresses.length}, '
      'connections=${p2pService.currentState.connections.length}');

  emitFlowEvent(
    layer: 'FL',
    event: 'APP_LIFECYCLE_RESUME_BEGIN',
    details: {},
  );

  try {
    // 1. Check bridge health — reinitialize if dead
    final healthStart = DateTime.now();
    debugPrint('[RESUME] Step 1: bridge.checkHealth() starting...');
    final bridgeOk = await bridge.checkHealth();
    final healthMs = DateTime.now().difference(healthStart).inMilliseconds;
    debugPrint('[RESUME] Step 1: bridge.checkHealth() = $bridgeOk (took ${healthMs}ms)');

    if (!bridgeOk) {
      final reinitStart = DateTime.now();
      debugPrint('[RESUME] Step 1b: bridge.reinitialize() starting...');
      await bridge.reinitialize();
      final reinitMs = DateTime.now().difference(reinitStart).inMilliseconds;
      debugPrint('[RESUME] Step 1b: bridge.reinitialize() done (took ${reinitMs}ms)');
    }

    // 2. Immediate health check (re-dials relay, re-registers FCM)
    final hcStart = DateTime.now();
    debugPrint('[RESUME] Step 2: performImmediateHealthCheck() starting...');
    debugPrint('[RESUME] Step 2: state BEFORE health check: '
        'isStarted=${p2pService.currentState.isStarted}, '
        'circuitAddresses=${p2pService.currentState.circuitAddresses.length}');
    await p2pService.performImmediateHealthCheck();
    final hcMs = DateTime.now().difference(hcStart).inMilliseconds;
    debugPrint('[RESUME] Step 2: performImmediateHealthCheck() done (took ${hcMs}ms)');
    debugPrint('[RESUME] Step 2: state AFTER health check: '
        'isStarted=${p2pService.currentState.isStarted}, '
        'circuitAddresses=${p2pService.currentState.circuitAddresses.length}');

    // 3. Drain offline inbox (messages queued while backgrounded)
    final drainStart = DateTime.now();
    debugPrint('[RESUME] Step 3: drainOfflineInbox() starting...');
    await p2pService.drainOfflineInbox();
    final drainMs = DateTime.now().difference(drainStart).inMilliseconds;
    debugPrint('[RESUME] Step 3: drainOfflineInbox() done (took ${drainMs}ms)');

    final totalMs = DateTime.now().difference(resumeStart).inMilliseconds;
    debugPrint('[RESUME] ====== APP RESUME COMPLETE ====== total ${totalMs}ms, bridgeWasHealthy=$bridgeOk');
    debugPrint('[RESUME] Final state: '
        'isStarted=${p2pService.currentState.isStarted}, '
        'circuitAddresses=${p2pService.currentState.circuitAddresses.length}, '
        'connections=${p2pService.currentState.connections.length}');

    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_RESUME_COMPLETE',
      details: {'bridgeWasHealthy': bridgeOk, 'totalMs': totalMs},
    );

    return bridgeOk;
  } catch (e) {
    final totalMs = DateTime.now().difference(resumeStart).inMilliseconds;
    debugPrint('[RESUME] ====== APP RESUME ERROR ====== after ${totalMs}ms: $e');

    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_RESUME_ERROR',
      details: {'error': e.toString()},
    );
    return null;
  }
}
