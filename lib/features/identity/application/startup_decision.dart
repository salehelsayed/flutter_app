import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Represents the startup routing decision based on identity and contacts.
enum StartupDecision {
  /// Migration authority forbids normal account startup on this device.
  accountMigrationBlocked,

  /// Identity exists and at least one contact is stored.
  hasIdentityWithContacts,

  /// Identity exists but no contacts are stored yet.
  hasIdentityNoContacts,

  /// No identity exists; show identity onboarding flow.
  needsIdentity,
}

/// Determines startup route from identity and contact count.
///
/// Flow events emitted:
/// - `ID_STARTUP_DECIDE_ROUTE_CALL`
/// - `ID_STARTUP_NEEDS_ID`
/// - `ID_STARTUP_HAS_ID_NO_CONTACTS`
/// - `ID_STARTUP_HAS_ID_WITH_CONTACTS`
Future<StartupDecision> decideStartupRoute({
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  AccountMigrationAuthorityRepository? migrationAuthorityRepository,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_STARTUP_DECIDE_ROUTE_CALL',
    details: {},
  );

  final identity = await identityRepo.loadIdentity();
  var migrationAuthority = await migrationAuthorityRepository?.loadAuthority();

  if (migrationAuthority != null &&
      !migrationAuthority.isFailClosed &&
      migrationAuthority.state ==
          AccountMigrationAuthorityState.migrationExportingNetworkPaused) {
    // An export pause is only meaningful while a Move Account transfer run is
    // alive in this process; finding it at startup means the app died (or was
    // killed) mid-export. Restore active authority so the old phone neither
    // blocks startup nor stays silently offline behind the network gate.
    final restored = AccountMigrationAuthorityRecord(
      state: AccountMigrationAuthorityState.migrationFailedActiveRestored,
      accountPeerId: migrationAuthority.accountPeerId,
    );
    await migrationAuthorityRepository!.saveAuthority(restored);
    migrationAuthority = restored;
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_MIGRATION_EXPORT_PAUSE_RECOVERED',
      details: {},
    );
  }

  if (migrationAuthority != null &&
      migrationAuthority.state.blocksNormalStartup) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_MIGRATION_BLOCKED',
      details: {'state': migrationAuthority.state.wireName},
    );
    return StartupDecision.accountMigrationBlocked;
  }

  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_NEEDS_ID',
      details: {'hasIdentity': false},
    );
    return StartupDecision.needsIdentity;
  }

  final contactCount = await contactRepo.getContactCount();
  if (contactCount > 0) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_HAS_ID_WITH_CONTACTS',
      details: {'hasIdentity': true, 'contactCount': contactCount},
    );
    return StartupDecision.hasIdentityWithContacts;
  } else {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_HAS_ID_NO_CONTACTS',
      details: {'hasIdentity': true, 'contactCount': 0},
    );
    return StartupDecision.hasIdentityNoContacts;
  }
}
