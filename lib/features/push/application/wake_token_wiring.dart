import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';

/// FDC-09 §12 / CV-14 (217 §C2) — the SINGLE production emission gate.
///
/// The sender-side `wt` emission ships DARK: it is a compile-time
/// `--dart-define` defaulting OFF. The whole fleet must saturate on
/// receiver-tolerant builds (which land 217's receive leg) BEFORE this is
/// flipped, or a new sender would emit `wt` to un-saturated pre-217 receivers
/// and drop their contact_request. Both this factory AND the wake-token wiring
/// in `main.dart` call it — a test asserting emission-off (A17) MUST import THIS
/// function (never a test-local `bool.fromEnvironment` copy, which would pass
/// regardless of the production default and be a fake lock).
bool shouldEmitWakeToken() =>
    const bool.fromEnvironment('MKNOON_EMIT_WAKE_TOKEN', defaultValue: false);

/// Builds the read-only per-send wake-token resolver used by `sendContactRequest`.
///
/// When emission is gated OFF (the dark-landing default), the resolver yields
/// `null` for every peer, so no `wt` is ever emitted. When ON, it reads the
/// recipient-minted token this node issued for [peerId] from [wakeTokenStore]
/// (the send half of the CV-14 loop — this node distributing to its contact the
/// token that contact should present to wake it). The resolver NEVER mints or
/// registers — minting/registering is once-per-cycle (INV-5).
Future<String?> Function(String peerId) buildWakeTokenResolver(
  WakeTokenStore wakeTokenStore,
) {
  if (!shouldEmitWakeToken()) {
    return (_) async => null;
  }
  return (peerId) async => (await wakeTokenStore.readTokens())[peerId];
}

/// FDC-09 §12 / CV-14 (217 §F4) — the TOTAL register callback wrapper.
///
/// Wraps [callP2PRegisterWakeTokens] so a throwing/timing-out bridge degrades to
/// `false` (NET-REL-07) instead of propagating — [IssueWakeTokensUseCase] treats
/// `false` as "old relay / failed", persists the minted tokens client-side, and
/// never spams. The totality lives HERE (not in the use-case, whose register
/// call is deliberately un-guarded), so a mutation removing this try/catch reds
/// the throw-path lock (A08).
Future<bool> registerWakeTokensViaBridge(
  Bridge bridge,
  List<String> tokens,
) async {
  try {
    final response = await callP2PRegisterWakeTokens(bridge, tokens: tokens);
    return response['ok'] == true;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'WAKE_TOKEN_REGISTER_BRIDGE_ERROR',
      details: {'error': e.toString()},
    );
    return false;
  }
}
