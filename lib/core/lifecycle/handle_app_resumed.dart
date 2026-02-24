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
  emitFlowEvent(
    layer: 'FL',
    event: 'APP_LIFECYCLE_RESUME_BEGIN',
    details: {},
  );

  try {
    // 1. Check bridge health — reinitialize if dead
    final bridgeOk = await bridge.checkHealth();
    if (!bridgeOk) {
      await bridge.reinitialize();
    }

    // 2. Immediate health check (re-dials relay, re-registers FCM)
    await p2pService.performImmediateHealthCheck();

    // 3. Drain offline inbox (messages queued while backgrounded)
    await p2pService.drainOfflineInbox();

    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_RESUME_COMPLETE',
      details: {'bridgeWasHealthy': bridgeOk},
    );

    return bridgeOk;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_RESUME_ERROR',
      details: {'error': e.toString()},
    );
    return null;
  }
}
