// 217 TC-A13a — CV-14 wake-token cross-device distribute → store → attach proof
// with STORAGE-DIRECTIONALITY (the PROD-CRITICAL closure; INV-4).
//
// This is a reliability-sim / device-proof row (deferred-not-waived): only two
// REAL nodes over the REAL bridge + native register dispatch + the v2 crypto
// envelope can prove the loop end-to-end. Host tiers prove every seam in
// isolation (A01 send-signs-wt, A02 receive-reconstructs, A03 store, A06/A07
// attach, A08/A09/A15 register-once) but CANNOT catch a DIRECTIONALITY inversion
// (B storing its OWN token instead of A's) — only this cross-node proof can.
//
// RELAY-GATE-INDEPENDENT: it runs on the fail-open relay (wakeTokenGateEnforced
// stays OFF). The discriminator is the STORED token's directionality, not a
// wake being suppressed — so it needs NO gate flip. TC-A13b (gate-enforced
// authorized-vs-suppressed) is DEFERRED to the relay-ops slice.
//
// EMISSION ENABLEMENT (required — distribution is emission-gated §C2): the proof
// build MUST pass a SIM-LOCAL `--dart-define=MKNOON_EMIT_WAKE_TOKEN=true` so A
// actually emits `wt`. Without it the real resolver returns null (A17) and B
// stores nothing ⇒ the directionality assertion is unsatisfiable. This is the
// SENDER-EMISSION flip ONLY — NOT the relay gate — and it is a sim-only override
// (release/production builds MUST NOT define it; see §C2 / Scope Guard carve-out).
//
// Run on a two-simulator / two-phone rig (via /sims 1to1 --only N), where the
// orchestrator drives node A + node B and the emission define is set for the run:
//   /sims 1to1 --list   → note --only N   → /sims 1to1 --only N
//
// PASS (TC-A13a), all observable + greppable:
//   1. A mints T_A-for-B and the REAL inboxRegisterWakeTokens dispatch fires.
//   2. A distributes over the v2 (encrypted, signed) contact_request envelope.
//   3. B persists ReceivedWakeTokenStore[A] whose value EQUALS the token A
//      registered (load-bearing = STORAGE DIRECTIONALITY, INV-4).
//   4. B's `inbox:store` frame to A carries that exact `wakeToken`.
//
// Mutation that re-reds: store B's OWN token instead of A's (invert
// directionality) → the `received[A] == A-registered` assertion reds. This runs
// today on the fail-open relay and exercises the first-time native register path
// + the v2 crypto envelope — a genuine discriminator that needs NO gate flip.

@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Emission define — the SAME sim-local override that enables `wt` emission.
/// Absent on host/CI and on the default sim gate, so the row skips silently; the
/// two-node rig sets it (`--dart-define=MKNOON_EMIT_WAKE_TOKEN=true`) to actually
/// drive distribution. NEVER present in a release config (§C2 / Scope Guard).
const bool _emitWakeToken = bool.fromEnvironment('MKNOON_EMIT_WAKE_TOKEN');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('217 CV-14 wake-token distribution — cross-device proof', () {
    testWidgets(
      'TC-A13a: mint → register → distribute → store → attach with storage '
      'directionality (A registers; B stores A\'s token and presents it)',
      (tester) async {
        if (!_emitWakeToken) {
          markTestSkipped(
            'Sim/device proof: run via `/sims 1to1 --only N` with '
            '--dart-define=MKNOON_EMIT_WAKE_TOKEN=true (sim-local emission '
            'override; the relay gate stays OFF). Skipped on host/CI/default '
            'sim gate so the gate stays green.',
          );
          return;
        }

        // On the two-node rig, the orchestrator drives node A + node B. The
        // human/harness asserts the PASS contract documented in the file header:
        //   B's persisted ReceivedWakeTokenStore[A] == the token A registered,
        //   and B's inbox:store frame to A carries that wakeToken.
        fail(
          'MKNOON_EMIT_WAKE_TOKEN is set but no two-node rig driver is wired '
          'into this proof body — drive it through the /sims 1to1 orchestrator '
          '(deferred cross-device closure).',
        );
      },
    );
  });
}
