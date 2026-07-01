import 'dart:async';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// 183 — active-chat keepalive. While the app is FOREGROUND and a 1:1
/// conversation is open, this proactively pings that ONE peer on a short cadence
/// ([kKeepAliveInterval] ≈ 8 s, well under the ~30 s QUIC idle) via the injected
/// [PeerLivenessProbe]. That keeps the warm fast-send path alive mid-chat and
/// detects a peer drop in SECONDS — instead of waiting out the QUIC idle / the
/// 30 s relay-health poll, which is how a dead connection is noticed today.
///
/// Modeled VERBATIM on 181's `SetPresenceUseCase`: a foreground heartbeat
/// `Timer.periodic` ARMED on foreground ([onForegrounded]) and CANCELLED on
/// background ([onBackgrounded]) so it can NEVER fire while the app is suspended
/// (OS-suspended background timers + battery — foreground-only by design).
///
/// On [kKeepAliveMissThreshold] CONSECUTIVE missed pings it REUSES the existing
/// recovery primitives — [onDropReWarm] (= `warmPeer`) to re-dial and
/// [onDropDrain] (= the public `drainOfflineInbox`) to catch up — exactly once
/// per drop (a `KEEPALIVE_PEER_DROP` flow event marks it). A single miss never
/// re-dials (a momentarily-slow healthy peer must not trigger one); a successful
/// ping resets the streak; and once a drop has been handled it does not re-fire
/// until the peer recovers (no re-dial spam on a durably-gone/gated peer — the
/// existing `warmPeer` cooldown + the single-in-flight `drainOfflineInbox` are a
/// second backstop).
///
/// The probe is best-effort and NEVER load-bearing: a gated/failed/thrown ping
/// is just a miss — it never propagates, never blocks, never throws away a send
/// (push + the durable inbox + the 30 s health poll remain the guarantees).
/// Groups are out of scope (they have their own GossipSub/rendezvous liveness),
/// so a `group:` active peer is never probed.
class ActivePeerKeepAliveUseCase {
  ActivePeerKeepAliveUseCase({
    required PeerLivenessProbe probe,
    required String? Function() activePeerId,
    required Future<void> Function(String peerId) onDropReWarm,
    required Future<void> Function() onDropDrain,
    void Function(String peerId, bool suspectedDropped)? onLivenessChanged,
    Duration interval = kKeepAliveInterval,
    int missThreshold = kKeepAliveMissThreshold,
    Duration pingTimeout = kKeepAlivePingTimeout,
  }) : _probe = probe,
       _activePeerId = activePeerId,
       _onDropReWarm = onDropReWarm,
       _onDropDrain = onDropDrain,
       _onLivenessChanged = onLivenessChanged,
       _interval = interval,
       _missThreshold = missThreshold,
       _pingTimeout = pingTimeout;

  final PeerLivenessProbe _probe;
  final String? Function() _activePeerId;
  final Future<void> Function(String peerId) _onDropReWarm;
  final Future<void> Function() _onDropDrain;

  /// 187 — fired when this peer's suspected-liveness FLIPS: `(peer, true)` when a
  /// drop latches, `(peer, false)` when it clears (recovery / chat-close /
  /// peer-switch / background). Wired to `p2pService.setPeerDropSuspected` so the
  /// send path can skip the doomed direct dial to a peer known to be down.
  final void Function(String peerId, bool suspectedDropped)? _onLivenessChanged;
  final Duration _interval;
  final int _missThreshold;
  final Duration _pingTimeout;

  Timer? _timer;
  int _consecutiveMisses = 0;
  bool _dropHandled = false;

  /// 187 — the peer for which `(peer, true)` was last emitted and not yet
  /// cleared. Non-null exactly while a drop signal is outstanding; used to emit
  /// the matching `(peer, false)` on recovery / chat-close / peer-switch /
  /// background so a stale "dropped" mark can never survive to wrongly route a
  /// reachable peer to relay after re-entry.
  String? _lastSignalledPeer;

  /// Cadence ≈ 8 s — comfortably under the ~30 s quic-go idle default so each
  /// tick re-warms the connection before it can lapse (device-tunable on
  /// closure). The miss threshold debounces a momentarily-slow healthy peer; the
  /// ping timeout is kept under the interval so a hung probe cannot overlap ticks.
  static const Duration kKeepAliveInterval = Duration(seconds: 8);
  static const int kKeepAliveMissThreshold = 2;
  static const Duration kKeepAlivePingTimeout = Duration(seconds: 4);

  /// Whether the foreground keepalive loop is currently armed (test/diagnostic).
  bool get isProbeActive => _timer?.isActive ?? false;

  /// Called when the app FOREGROUNDS (resume): arm the keepalive loop. The
  /// connection is freshly warmed by the resume one-shot `warmPeer`, so the first
  /// probe waits one interval. Synchronous — adds no latency to the resume path.
  void onForegrounded() => _start();

  /// Called when the app BACKGROUNDS (pause): cancel the loop so it can NEVER
  /// fire while suspended (foreground-only; zero background pings).
  void onBackgrounded() => _stop();

  /// Cancels the loop without probing (dispose / teardown — no leaked Timer).
  void dispose() => _stop();

  void _start() {
    _timer?.cancel();
    _resetLiveness();
    _timer = Timer.periodic(_interval, (_) => unawaited(_tick()));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _resetLiveness();
  }

  void _resetLiveness() {
    _consecutiveMisses = 0;
    _dropHandled = false;
    // 187: recovery / arm / background / null-tick all reset liveness — any
    // outstanding drop signal is now stale, so clear it (no-op when none).
    _clearDropSignalIfAny();
  }

  /// 187 — emit `(peer, true)` and remember it so the matching clear can fire.
  void _signalDrop(String peer) {
    _lastSignalledPeer = peer;
    _onLivenessChanged?.call(peer, true);
  }

  /// 187 — if a drop signal is outstanding, emit `(peer, false)` and forget it.
  void _clearDropSignalIfAny() {
    final prev = _lastSignalledPeer;
    if (prev != null) {
      _lastSignalledPeer = null;
      _onLivenessChanged?.call(prev, false);
    }
  }

  Future<void> _tick() async {
    final peer = _activePeerId();
    // 187: if the tracked peer changed/cleared since the last drop signal, clear
    // the OLD peer's stale mark up front (the reset branches below only fire when
    // the tick returns early; a live SWITCH to another peer would otherwise leave
    // the previous peer wrongly latched-dropped).
    if (_lastSignalledPeer != null && _lastSignalledPeer != peer) {
      _clearDropSignalIfAny();
    }
    if (peer == null || peer.isEmpty || peer.startsWith('group:')) {
      // No active 1:1 peer (chat closed, roster, or a group): never probe, and
      // reset the streak so a closed-then-reopened chat starts clean.
      _resetLiveness();
      return;
    }

    bool alive;
    try {
      alive = await _probe.pingPeer(peer, timeoutMs: _pingTimeout.inMilliseconds);
    } catch (_) {
      // Non-load-bearing: a thrown probe is a miss, never propagates.
      alive = false;
    }

    if (alive) {
      _resetLiveness();
      return;
    }

    _consecutiveMisses++;
    if (_consecutiveMisses >= _missThreshold && !_dropHandled) {
      // Drop detected: handle ONCE (latched until recovery — no re-dial spam) by
      // REUSING warmPeer + the public drainOfflineInbox. The distinct
      // KEEPALIVE_PEER_DROP event (carrying the peer) discriminates this re-dial
      // from warmPeer's other one-shot triggers (chat-open/resume/notif).
      _dropHandled = true;
      _consecutiveMisses = 0;
      emitFlowEvent(
        layer: 'FL',
        event: 'KEEPALIVE_PEER_DROP',
        details: {'peerId': peer},
      );
      // 187: expose the latch to the send path so it can skip the doomed direct
      // dial to this peer (custody rides the concurrent durable inbox instead).
      _signalDrop(peer);
      unawaited(_onDropReWarm(peer));
      unawaited(_onDropDrain());
    }
  }
}
