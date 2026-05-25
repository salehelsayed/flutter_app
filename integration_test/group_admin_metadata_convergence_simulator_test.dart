import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/groups/integration/group_admin_metadata_convergence_test.dart'
    as group_admin_metadata_convergence;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Group admin metadata convergence', () {
    testWidgets(
      'A/B/C metadata, admin promotion, member add, fanout, and avatar updates converge',
      (_) async {
        await group_admin_metadata_convergence
            .runGroupAdminMetadataConvergenceScenario();
      },
    );

    testWidgets(
      'promoted admin can add C and A/B/C metadata, fanout, and avatar updates converge',
      (_) async {
        await group_admin_metadata_convergence
            .runGroupAdminMetadataConvergenceScenario(
              charlieAdder: group_admin_metadata_convergence
                  .GroupAdminMetadataMemberAdder
                  .bob,
            );
      },
    );
  });
}
