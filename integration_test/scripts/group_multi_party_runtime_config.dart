const groupMultiPartyRuntimeConfigFileName =
    'group_multi_party_runtime_config.json';
const groupMultiPartyRuntimeConfigStagingMechanism = 'documents-file';

const groupMultiPartySharedDirKey = 'E2E_SHARED_DIR';
const groupMultiPartyDbNameKey = 'E2E_DB_NAME';
const groupMultiPartyRoleKey = 'GROUP_MULTI_PARTY_ROLE';
const groupMultiPartyScenarioKey = 'GROUP_MULTI_PARTY_SCENARIO';
const groupMultiPartyRunIdKey = 'GROUP_MULTI_PARTY_RUN_ID';
const groupMultiPartyModeKey = 'GROUP_MULTI_PARTY_MODE';
const groupMultiPartyRestoreMnemonicKey = 'GROUP_MULTI_PARTY_RESTORE_MNEMONIC';
const groupMultiPartyRestoreIdentityPathKey =
    'GROUP_MULTI_PARTY_RESTORE_IDENTITY_PATH';
const groupMultiPartyReuseExistingIdentityKey =
    'GROUP_MULTI_PARTY_REUSE_EXISTING_IDENTITY';

class GroupMultiPartyRuntimeConfig {
  const GroupMultiPartyRuntimeConfig({
    required this.sharedDir,
    required this.role,
    required this.scenario,
    required this.runId,
    required this.mode,
    required this.restoreMnemonic,
    required this.restoreIdentityPath,
    required this.reuseExistingIdentity,
    required this.dbName,
  });

  final String sharedDir;
  final String role;
  final String scenario;
  final String runId;
  final String mode;
  final String restoreMnemonic;
  final String restoreIdentityPath;
  final bool reuseExistingIdentity;
  final String dbName;

  String get stagingMechanism => groupMultiPartyRuntimeConfigStagingMechanism;

  Map<String, Object> toJson() => <String, Object>{
    groupMultiPartySharedDirKey: sharedDir,
    groupMultiPartyRoleKey: role,
    groupMultiPartyScenarioKey: scenario,
    groupMultiPartyRunIdKey: runId,
    groupMultiPartyModeKey: mode,
    groupMultiPartyRestoreMnemonicKey: restoreMnemonic,
    groupMultiPartyRestoreIdentityPathKey: restoreIdentityPath,
    groupMultiPartyReuseExistingIdentityKey: reuseExistingIdentity,
    groupMultiPartyDbNameKey: dbName,
  };
}

GroupMultiPartyRuntimeConfig resolveGroupMultiPartyConfig(
  Map<String, String> values,
) {
  return GroupMultiPartyRuntimeConfig(
    sharedDir: _stringValue(values, groupMultiPartySharedDirKey, '/tmp'),
    role: _stringValue(values, groupMultiPartyRoleKey, 'alice'),
    scenario: _stringValue(values, groupMultiPartyScenarioKey, 'gm001'),
    runId: _stringValue(values, groupMultiPartyRunIdKey, 'adhoc'),
    mode: _stringValue(values, groupMultiPartyModeKey, 'proof'),
    restoreMnemonic: _stringValue(
      values,
      groupMultiPartyRestoreMnemonicKey,
      '',
    ),
    restoreIdentityPath: _stringValue(
      values,
      groupMultiPartyRestoreIdentityPathKey,
      '',
    ),
    reuseExistingIdentity: _boolValue(
      values,
      groupMultiPartyReuseExistingIdentityKey,
    ),
    dbName: _stringValue(values, groupMultiPartyDbNameKey, ''),
  );
}

String _stringValue(
  Map<String, String> values,
  String key,
  String defaultValue,
) {
  return values[key]?.trim() ?? defaultValue;
}

bool _boolValue(Map<String, String> values, String key) {
  return values[key]?.trim().toLowerCase() == 'true';
}
