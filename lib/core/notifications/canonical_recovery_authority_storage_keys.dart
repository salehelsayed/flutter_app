/// Secure values whose mutation can change the account, migration, or linked
/// transport authority used by Android canonical recovery.
///
/// Keep these names centralized so the production secure-store adapter can
/// fence every authority write before it reaches durable storage.
const canonicalRuntimeInstallationIdStorageKey =
    'canonical_runtime_installation_id_v1';
const canonicalRuntimeAccountBindingStorageKey =
    'canonical_runtime_account_binding_v1';
const canonicalRuntimeSharedAccountBindingStorageKey =
    'canonical_runtime_shared_account_binding_v1';
const linkedInstallationRoleStorageKey =
    'direct_linked_device_expected_role_v1';
const linkedInstallationTransportCredentialStorageKey =
    'direct_linked_device_transport_credential_v1';
const accountMigrationAuthorityStorageKeyPrefix = 'account_migration_authority';
const accountMigrationAuthorityStorageKey =
    '$accountMigrationAuthorityStorageKeyPrefix:v1';
const identityPrivateKeyStorageKey = 'identity_private_key';

const canonicalRecoveryAuthorityStorageKeys = <String>{
  canonicalRuntimeInstallationIdStorageKey,
  canonicalRuntimeAccountBindingStorageKey,
  canonicalRuntimeSharedAccountBindingStorageKey,
  linkedInstallationRoleStorageKey,
  linkedInstallationTransportCredentialStorageKey,
  accountMigrationAuthorityStorageKey,
  identityPrivateKeyStorageKey,
};

bool isCanonicalRecoveryAuthorityStorageKey(String key) =>
    canonicalRecoveryAuthorityStorageKeys.contains(key);
