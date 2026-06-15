import 'package:flutter_test/flutter_test.dart';

import '../test/features/groups/integration/group_admin_metadata_convergence_test.dart'
    as group_admin_metadata_convergence;

void registerAdminMetadataSim() {
  testWidgets('ADMIN_METADATA 1', (tester) async {
    await group_admin_metadata_convergence
        .runGroupAdminMetadataConvergenceScenario();
  });

  testWidgets('ADMIN_METADATA 2', (tester) async {
    await group_admin_metadata_convergence
        .runGroupAdminMetadataConvergenceScenario(
          charlieAdder: group_admin_metadata_convergence
              .GroupAdminMetadataMemberAdder
              .bob,
        );
  });

  testWidgets('ADMIN_METADATA 3', (tester) async {
    await group_admin_metadata_convergence
        .runExactScenario4AdminDemotionEnforcementJourney();
  });

  testWidgets('ADMIN_METADATA 4', (tester) async {
    await group_admin_metadata_convergence
        .runPromotedAdminRecoverySaveConvergenceScenario();
  });
}
