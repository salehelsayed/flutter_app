import 'flow_event_emitter.dart';
import 'startup_timing.dart';

/// FDC-S1 Method 5(d) — cold notif-tap → node-ready correlation (observation-only).
///
/// On a cold notification tap the libp2p node is NOT running yet (the Go node
/// starts only after the main isolate boots and `node:start` returns — the iOS
/// NSE decrypts a preview out-of-process but never holds the libp2p host). This
/// anchor measures the floor a warm dial must respect: `node:start`-return on a
/// notif-tap launch.
///
/// Two independent signals arrive in an unspecified order on a cold launch:
///  * [recordNotifTap] — the initial push that launched the app was consumed
///    (iOS `consumeInitialNotificationOpen` / Android `getInitialMessage`).
///  * [recordNodeReady] — `node:start` returned on the main isolate.
///
/// `FDC_COLDSTART_NOTIF_TAP_NODE_READY` is emitted exactly once, when BOTH are
/// known, carrying an absolute `epochMs` so post-processing can compute the
/// NSE→main-isolate gap `G_nse = epochMs − FDC_NSE_PEERID_AVAILABLE.nseEpochMs`
/// (matched by `pushId`). The NSE epoch cannot be threaded inline — APNs
/// `userInfo` carries no timestamp — so the gap is reconstructed off-device.
class ColdStartNotifAnchor {
  ColdStartNotifAnchor._();
  static final ColdStartNotifAnchor instance = ColdStartNotifAnchor._();

  String? _pushId;
  bool _notifTapSeen = false;
  bool _nodeReady = false;
  bool _emitted = false;

  /// Record that the app was launched by a notification tap. [pushId] is the
  /// relay/message id carried in the push data (may be null on iOS where the
  /// FCM message id differs); null does not clear a previously-seen id.
  void recordNotifTap(String? pushId) {
    _notifTapSeen = true;
    _pushId ??= pushId;
    _maybeEmit('notif_tap');
  }

  /// Record that `node:start` returned on the main isolate (node is ready).
  void recordNodeReady() {
    _nodeReady = true;
    _maybeEmit('node_ready');
  }

  void _maybeEmit(String trigger) {
    if (_emitted) return;
    if (!_notifTapSeen || !_nodeReady) return;
    _emitted = true;
    emitFlowEvent(
      layer: 'FL',
      event: 'FDC_COLDSTART_NOTIF_TAP_NODE_READY',
      details: {
        'pushId': _pushId ?? 'unknown',
        'sinceProcessStartMs':
            StartupTiming.instance.sinceProcessStartMs() ?? -1,
        // Absolute epoch so G_nse can be reconstructed against the NSE's
        // nseEpochMs in post-processing (no inline thread of the NSE clock).
        'epochMs': DateTime.now().millisecondsSinceEpoch,
        // Which of the two signals arrived second (i.e. what unblocked the
        // emit) — tells us whether node-start or the notif-consume is the
        // long pole on the coldest path.
        'trigger': trigger,
      },
    );
  }

  /// Test-only reset so the one-shot latch can be re-exercised.
  void resetForTest() {
    _pushId = null;
    _notifTapSeen = false;
    _nodeReady = false;
    _emitted = false;
  }
}
