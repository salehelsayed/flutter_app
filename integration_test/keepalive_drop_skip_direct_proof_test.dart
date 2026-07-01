// 187 — Keepalive-informed send: skip the doomed direct dial DEVICE proof
// (TC-187-32).
//
// This is a device-proof row (deferred-not-waived): only a physical 2-phone rig
// can prove that a send to a peer the 183 keepalive has latched-dropped actually
// SKIPS the WAN direct discover/dial leg ON THE WIRE — i.e. the ~1.5 s
// DIAL_PEER_ERROR captured on 2026-07-01 is gone — while custody still lands via
// the concurrent durable inbox and the queued message still delivers on peer
// recovery. A host test cannot exercise this: the real discover/dial legs and
// their timing only exist against the live Go bridge + relay, which is the exact
// boundary under test. The host floor already closes the LOGIC:
//   - test/features/conversation/application/send_chat_message_use_case_test.dart
//     (TC-187-01/02/03/10/11/20/21/30/31 — skip predicate, custody, retriable
//     inbox, no over-reach, normalized-key match, no false delivered, one write),
//   - test/core/services/active_peer_keepalive_use_case_test.dart
//     (TC-187-12/40 — the latch is exposed + cleared on recovery/close/switch/bg),
//   - test/core/services/p2p_service_peer_liveness_test.dart
//     (PeerDropSignal off base P2PService + impl normalization).
// This proof closes the on-wire half.
//
// Authored + registered now (classify_path case in
// scripts/check_reliability_simulation_discovery.sh) so discovery lists it; it
// skips silently on host/CI and on the default sim gate so the gate stays green.
//
// Manual run on a 2-phone rig (device B / the recipient is the drop target; the
// build under test is device A / the sender):
//   flutter test integration_test/keepalive_drop_skip_direct_proof_test.dart \
//     -d <phoneA> --dart-define=KEEPALIVE_DROP_SKIP_DEVICE_PROOF=1
//   # Reuse the 183 rig: FDC_FLOW_LOG=1 + MKNOON_ENABLE_NATIVE_MDNS=true.
//
// Procedure (reproduces the 2026-07-01 capture, Pixel 6 → iPhone 11):
//   1. A and B are in an OPEN 1:1 conversation, foreground, connected — the 183
//      keepalive is pinging B on its ~8 s cadence (P2P_SERVICE_PEER_PING_SUCCESS
//      in A's log).
//   2. Hard-drop B (airplane mode / force-kill the app) and keep A foregrounded
//      on the chat. Within ~2 misses (~16 s) A logs KEEPALIVE_PEER_DROP{peerId:B}
//      — the drop is now LATCHED and the send path's PeerDropSignal reads true.
//   3. From A, send a message to B (still latched-dropped).
//
// PASS (TC-187-32):
//   - A's flow log shows SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP for that send AND
//     NO P2P_SERVICE_DISCOVER_PEER_BEGIN / P2P_SERVICE_DIAL_PEER_BEGIN /
//     P2P_SERVICE_DIAL_PEER_ERROR in that send's window (the ~1.5 s doomed dial
//     is GONE), AND
//   - custody still lands sub-second via the concurrent inbox
//     (CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN → CHAT_MSG_SEND_CUSTODY_CONFIRMED,
//     ~sub-200 ms as measured), AND
//   - on B's recovery (airplane mode off / relaunch) the queued message DELIVERS
//     (A logs DELIVERY_RECEIPT_APPLIED for that messageId) — the skip lost
//     nothing, and the keepalive re-arms so the NEXT send runs direct again.
//
// Mutation that re-reds: revert the _tryDirectSend skipForKeepaliveDrop short-
// circuit (send_chat_message_use_case.dart) → A dials B again → the ~1.5 s
// DISCOVER/DIAL/DIAL_PEER_ERROR sequence reappears and
// SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP is absent → fails the first PASS clause.

@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Device-proof gate. Absent on host/CI and on the default sim gate, so the row
/// skips silently; set on the 2-phone rig to actually drive the proof.
const bool _keepaliveDropSkipDeviceProof = bool.fromEnvironment(
  'KEEPALIVE_DROP_SKIP_DEVICE_PROOF',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('187 keepalive-informed send: skip doomed direct dial — device proof', () {
    testWidgets(
      'TC-187-32: a send to a latched-dropped active peer skips the direct '
      'discover/dial leg (no ~1.5s DIAL_PEER_ERROR), custody stays sub-second, '
      'and the queued message delivers on recovery',
      (tester) async {
        if (!_keepaliveDropSkipDeviceProof) {
          markTestSkipped(
            'Device proof: set --dart-define=KEEPALIVE_DROP_SKIP_DEVICE_PROOF=1 '
            'on a 2-phone rig and follow the procedure in the file header.',
          );
          return;
        }

        // On the rig, the operator drops the recipient, waits out the latch, then
        // sends and verifies A's on-device flow-event log against the PASS
        // contract documented above (skip event present; NO DISCOVER/DIAL for the
        // send; custody sub-second; delivery on recovery).
        fail(
          'KEEPALIVE_DROP_SKIP_DEVICE_PROOF is set but no rig driver is wired in '
          'this harness build — run the manual procedure in the file header and '
          'record the flow-event log as the proof artifact.',
        );
      },
    );
  });
}
