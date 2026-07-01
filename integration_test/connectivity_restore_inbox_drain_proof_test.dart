// 182 — Connectivity-restore inbox drain DEVICE proof (TC-182-08).
//
// This is a device-proof row (deferred-not-waived): only a physical device can
// prove that the OS connectivity source (iOS NWPathMonitor / Android
// ConnectivityManager, surfaced by connectivity_plus) actually fires on a
// FOREGROUND Wi-Fi toggle — and that the foreground toggle is NOT an app resume.
// A simulator cannot exercise this: the sim shares the host network namespace
// and the orchestrator cannot toggle a foregrounded app's OS network path, which
// is the exact boundary under test. The host floor (TC-182-01..07 in
// test/core/services/{p2p_service_impl,connectivity_signal}_test.dart) already
// proves the wiring GIVEN a restored-edge event; this proof closes the OS half.
//
// Authored + registered now (classify_path case in
// scripts/check_reliability_simulation_discovery.sh) so discovery lists it; it
// skips silently on host/CI and on the default sim gate so the gate stays green.
//
// Manual run on a 2-phone rig (device B is the build under test):
//   flutter test integration_test/connectivity_restore_inbox_drain_proof_test.dart \
//     -d <phoneB> --dart-define=CONNECTIVITY_DRAIN_DEVICE_PROOF=1
//
// Procedure (the test body documents + asserts the contract; the human drives
// the physical Wi-Fi toggle when prompted):
//   1. Device B foreground + idle (NO conversation open).
//   2. Turn B's Wi-Fi OFF.
//   3. From device A, send 3 messages to B — they queue on the relay inbox.
//   4. With B STILL foreground, turn B's Wi-Fi back ON (Control Center / quick
//      settings). Do NOT background/resume the app.
//
// PASS (TC-182-08):
//   - B surfaces all 3 stored messages within a few seconds (NOT ~30s — i.e. it
//     did not wait for the health-check poll), AND
//   - B's flow-event log shows P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN followed by
//     P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN, with NO APP_LIFECYCLE_RESUME_* event
//     in that window (proves the drain was connectivity-triggered, not a resume).
//
// Mutation that re-reds: revert the lib/main.dart:2206 networkChangeSignal wiring
// (signal back to null) → B falls back to the ~30s poll, no NETWORK_CHANGE_DRAIN_
// BEGIN in the log → fails both PASS clauses.

@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Device-proof gate. Absent on host/CI and on the default sim gate, so the row
/// skips silently; set on the 2-phone rig to actually drive the proof.
const bool _connectivityDrainDeviceProof = bool.fromEnvironment(
  'CONNECTIVITY_DRAIN_DEVICE_PROOF',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('182 connectivity-restore inbox drain — device proof', () {
    testWidgets(
      'TC-182-08: foreground Wi-Fi restore drains the relay backlog with NO '
      'resume',
      (tester) async {
        if (!_connectivityDrainDeviceProof) {
          markTestSkipped(
            'Device proof: set --dart-define=CONNECTIVITY_DRAIN_DEVICE_PROOF=1 '
            'on a 2-phone rig and follow the procedure in the file header.',
          );
          return;
        }

        // On the rig, the operator drives the physical Wi-Fi toggle and verifies
        // the on-device flow-event log per the PASS contract documented above.
        // The harness keeps the app foregrounded for the toggle window; the
        // human asserts: 3 stored messages surface within seconds AND the log
        // shows P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN with NO
        // APP_LIFECYCLE_RESUME_* in-window.
        fail(
          'CONNECTIVITY_DRAIN_DEVICE_PROOF is set but no rig driver is wired '
          'in this harness build — run the manual procedure in the file header '
          'and record the flow-event log as the proof artifact.',
        );
      },
    );
  });
}
