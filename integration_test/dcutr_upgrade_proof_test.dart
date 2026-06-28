// FDC-12 / FDC-16 CV-11+CV-12 — DCUtR relay→direct upgrade DEVICE proof.
//
// These are device-proof rows (deferred-not-waived): a real relay→direct DCUtR
// hole-punch needs two phones behind real NAT + a real relay, which a host/sim
// run cannot exercise (a sim shares the host's network namespace, so there is no
// genuine NAT to punch). They are authored + registered now (FDC-16 CV-07) so
// scripts/check_reliability_simulation_discovery.sh lists them and `/sims 1to1
// --only N` can target them once the rig + flag are provisioned; until then they
// skip silently so the default gate stays green.
//
// Run on the rig (both phones same campaign, EnableDcutrUpgrade flipped ON for
// the build under test):
//   flutter test integration_test/dcutr_upgrade_proof_test.dart \
//     -d <phone> --dart-define=FDC_DCUTR_DEVICE_PROOF=1
//
// Closes: CV-11 (TC-12-12 upgrade positive), CV-12 (TC-12-13 symmetric-CGNAT
// negative). Gate to flip EnableDcutrUpgrade default-on: CV-13 (host lock).

@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Device-proof gate. Absent on host/CI and on the default sim gate, so both
/// rows skip silently; set on the 2-phone rig to actually drive the proof.
const bool _dcutrDeviceProof = bool.fromEnvironment(
  'FDC_DCUTR_DEVICE_PROOF',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'TC-12-12 dcutr relay->direct upgrade lights the direct transport badge',
    (tester) async {
      if (!_dcutrDeviceProof) {
        markTestSkipped(
          'CV-11 device-proof: needs a 2-phone rig behind real NAT + a real '
          'relay + EnableDcutrUpgrade ON. Set --dart-define='
          'FDC_DCUTR_DEVICE_PROOF=1 on the rig. Deferred-not-waived.',
        );
        return;
      }
      // RIG STEPS (manual/observed): pair two phones that can only reach each
      // other via the relay, send so a relay leg establishes, then confirm the
      // DCUtR hole-punch upgrades the session to a non-circuit direct conn and
      // the conversation transport badge flips relay -> direct (sticky).
      fail(
        'TC-12-12 must be observed on the 2-phone rig; no host assertion can '
        'stand in for a real relay->direct hole-punch (FDC-16 CV-11).',
      );
    },
  );

  testWidgets(
    'TC-12-13 symmetric-CGNAT pair stays on relay (no false direct badge)',
    (tester) async {
      if (!_dcutrDeviceProof) {
        markTestSkipped(
          'CV-12 device-proof: needs a symmetric-CGNAT 2-phone pair where the '
          'punch MUST fail; confirm the badge stays relay. Set --dart-define='
          'FDC_DCUTR_DEVICE_PROOF=1 on the rig. Deferred-not-waived.',
        );
        return;
      }
      fail(
        'TC-12-13 must be observed on a symmetric-CGNAT rig; the negative (no '
        'upgrade, badge stays relay) cannot be faked on host (FDC-16 CV-12).',
      );
    },
  );
}
