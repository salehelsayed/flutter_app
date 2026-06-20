import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_multi_party_runtime_config.dart';

void main() {
  group('resolveGroupMultiPartyConfig', () {
    test('maps a full runtime value set into typed config', () {
      final config = resolveGroupMultiPartyConfig(<String, String>{
        groupMultiPartySharedDirKey: '/tmp/gmp',
        groupMultiPartyRoleKey: 'charlie',
        groupMultiPartyScenarioKey: 'ge014',
        groupMultiPartyRunIdKey: 'run-123',
        groupMultiPartyModeKey: 'restartSeed',
        groupMultiPartyRestoreMnemonicKey: 'alpha beta gamma',
        groupMultiPartyRestoreIdentityPathKey: '/tmp/identity.json',
        groupMultiPartyReuseExistingIdentityKey: 'true',
        groupMultiPartyDbNameKey: 'scenario.db',
      });

      expect(config.sharedDir, '/tmp/gmp');
      expect(config.role, 'charlie');
      expect(config.scenario, 'ge014');
      expect(config.runId, 'run-123');
      expect(config.mode, 'restartSeed');
      expect(config.restoreMnemonic, 'alpha beta gamma');
      expect(config.restoreIdentityPath, '/tmp/identity.json');
      expect(config.reuseExistingIdentity, isTrue);
      expect(config.dbName, 'scenario.db');
      expect(
        config.stagingMechanism,
        groupMultiPartyRuntimeConfigStagingMechanism,
      );
    });

    test('defaults missing values to legacy harness values', () {
      final config = resolveGroupMultiPartyConfig(const <String, String>{});

      expect(config.sharedDir, '/tmp');
      expect(config.role, 'alice');
      expect(config.scenario, 'gm001');
      expect(config.runId, 'adhoc');
      expect(config.mode, 'proof');
      expect(config.restoreMnemonic, isEmpty);
      expect(config.restoreIdentityPath, isEmpty);
      expect(config.reuseExistingIdentity, isFalse);
      expect(config.dbName, isEmpty);
    });

    test(
      'parses bools case-insensitively and preserves empty restore fields',
      () {
        final config = resolveGroupMultiPartyConfig(<String, String>{
          groupMultiPartyRestoreMnemonicKey: '',
          groupMultiPartyRestoreIdentityPathKey: '',
          groupMultiPartyReuseExistingIdentityKey: ' TRUE ',
        });

        expect(config.restoreMnemonic, isEmpty);
        expect(config.restoreIdentityPath, isEmpty);
        expect(config.reuseExistingIdentity, isTrue);

        final falseConfig = resolveGroupMultiPartyConfig(<String, String>{
          groupMultiPartyReuseExistingIdentityKey: 'yes',
        });
        expect(falseConfig.reuseExistingIdentity, isFalse);
      },
    );
  });
}
