/// Single dispatched group-lifecycle simulator entrypoint (124 Phase 5).
///
/// The four former group-lifecycle simulator suites were each refactored into a
/// pure library exposing a `register<X>Sim()` function that REGISTERS its
/// `testWidgets` case(s). This entrypoint selects which scenario library to
/// register via the `GROUP_SIM_SCENARIO` dart-define, e.g.:
///
///   flutter test integration_test/group_lifecycle_simulator_harness.dart \
///       -d DEVICE_ID --dart-define=GROUP_SIM_SCENARIO=ADMIN_METADATA
///
/// The `register<X>Sim()` calls run at `main()` top level so their `testWidgets`
/// cases register and `flutter test` runs them — each with its own fresh tester.
/// Binding: at least one of the converted suites is device-tagged / runs on the
/// integration binding, so the dispatcher uses
/// IntegrationTestWidgetsFlutterBinding and carries the `device` tag. The
/// dispatcher only routes on `GROUP_SIM_SCENARIO`; each scenario library reads
/// any additional configuration it needs independently.
@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'group_admin_metadata_convergence_simulator_test.dart';
import 'group_delete_preserves_friends_simulator_test.dart';
import 'group_invite_accept_spinner_simulator_test.dart';
import 'group_new_member_media_simulator_proof_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const s = String.fromEnvironment('GROUP_SIM_SCENARIO');

  switch (s) {
    case 'ADMIN_METADATA':
      registerAdminMetadataSim();
      break;
    case 'DELETE_PRESERVES_FRIENDS':
      registerDeletePreservesFriendsSim();
      break;
    case 'INVITE_ACCEPT_SPINNER':
      registerInviteAcceptSpinnerSim();
      break;
    case 'NEW_MEMBER_MEDIA':
      registerNewMemberMediaSim();
      break;
    default:
      testWidgets('unknown GROUP_SIM_SCENARIO', (tester) async {
        fail('Unknown GROUP_SIM_SCENARIO=$s');
      });
  }
}
