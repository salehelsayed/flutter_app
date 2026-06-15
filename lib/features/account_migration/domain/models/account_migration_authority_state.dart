import 'dart:convert';

enum AccountMigrationAuthorityState {
  noAccount('no_account'),
  migrationPairing('migration_pairing'),
  migrationImportStaging('migration_import_staging'),
  migrationVerifiedWaitingForCutover('migration_verified_waiting_for_cutover'),
  active('active'),
  migrationFailedCleanupRequired('migration_failed_cleanup_required'),
  migrationExportingNetworkPaused('migration_exporting_network_paused'),
  migrationCutoverPendingBlocked('migration_cutover_pending_blocked'),
  migratedOut('migrated_out'),
  migrationFailedActiveRestored('migration_failed_active_restored');

  const AccountMigrationAuthorityState(this.wireName);

  final String wireName;

  static AccountMigrationAuthorityState? fromWireName(String wireName) {
    for (final state in values) {
      if (state.wireName == wireName) {
        return state;
      }
    }
    return null;
  }

  bool get allowsNormalStartup {
    return switch (this) {
      AccountMigrationAuthorityState.noAccount ||
      AccountMigrationAuthorityState.active ||
      AccountMigrationAuthorityState.migrationFailedActiveRestored => true,
      _ => false,
    };
  }

  bool get blocksNormalStartup => !allowsNormalStartup;

  bool get isImportStaging {
    return this == AccountMigrationAuthorityState.migrationImportStaging ||
        this ==
            AccountMigrationAuthorityState.migrationVerifiedWaitingForCutover;
  }

  bool get isMigratedOut => this == AccountMigrationAuthorityState.migratedOut;

  bool get isActiveAccountAuthority {
    return this == AccountMigrationAuthorityState.active ||
        this == AccountMigrationAuthorityState.migrationFailedActiveRestored;
  }
}

class AccountMigrationAuthorityRecord {
  static const int currentVersion = 1;

  final AccountMigrationAuthorityState state;
  final String? accountPeerId;
  final bool isFailClosed;

  const AccountMigrationAuthorityRecord({
    required this.state,
    this.accountPeerId,
    this.isFailClosed = false,
  });

  factory AccountMigrationAuthorityRecord.failClosed() {
    return const AccountMigrationAuthorityRecord(
      state: AccountMigrationAuthorityState.migrationFailedCleanupRequired,
      isFailClosed: true,
    );
  }

  factory AccountMigrationAuthorityRecord.fromPersistedJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return AccountMigrationAuthorityRecord.failClosed();
      }

      if (decoded['version'] != currentVersion) {
        return AccountMigrationAuthorityRecord.failClosed();
      }

      final stateWireName = decoded['state'];
      if (stateWireName is! String) {
        return AccountMigrationAuthorityRecord.failClosed();
      }

      final state = AccountMigrationAuthorityState.fromWireName(stateWireName);
      if (state == null) {
        return AccountMigrationAuthorityRecord.failClosed();
      }

      final accountPeerId = decoded['accountPeerId'];
      if (accountPeerId != null && accountPeerId is! String) {
        return AccountMigrationAuthorityRecord.failClosed();
      }

      return AccountMigrationAuthorityRecord(
        state: state,
        accountPeerId: accountPeerId as String?,
      );
    } catch (_) {
      return AccountMigrationAuthorityRecord.failClosed();
    }
  }

  String toPersistedJson() {
    return jsonEncode({
      'version': currentVersion,
      'state': state.wireName,
      if (accountPeerId != null) 'accountPeerId': accountPeerId,
    });
  }

  bool get allowsNormalStartup => state.allowsNormalStartup;

  bool get blocksNormalStartup => state.blocksNormalStartup;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AccountMigrationAuthorityRecord &&
            other.state == state &&
            other.accountPeerId == accountPeerId &&
            other.isFailClosed == isFailClosed;
  }

  @override
  int get hashCode => Object.hash(state, accountPeerId, isFailClosed);

  @override
  String toString() {
    return 'AccountMigrationAuthorityRecord('
        'state: ${state.wireName}, '
        'accountPeerId: $accountPeerId, '
        'isFailClosed: $isFailClosed'
        ')';
  }
}
