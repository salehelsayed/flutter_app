import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';

typedef AccountMigrationNetworkGate =
    Future<bool> Function({String? peerId, required String operation});

class AccountMigrationRuntimeNetworkGate {
  final AccountMigrationAuthorityRepository _authorityRepository;

  const AccountMigrationRuntimeNetworkGate({
    required AccountMigrationAuthorityRepository authorityRepository,
  }) : _authorityRepository = authorityRepository;

  Future<bool> allowsAccountNetworkSideEffects({
    String? peerId,
    required String operation,
  }) async {
    final authority = await _authorityRepository.loadAuthority();
    if (authority == null) {
      return true;
    }
    if (authority.isFailClosed) {
      return false;
    }
    if (authority.accountPeerId != null &&
        peerId != null &&
        authority.accountPeerId != peerId) {
      return false;
    }
    return authority.state.allowsRuntimeNetworkSideEffects;
  }

  /// Whether incoming-push NOTIFICATION DISPLAY is allowed. Display has no
  /// relay side effects (nothing is drained or ACKed), so it stays allowed
  /// during a Move Account export pause — only states where this device has
  /// genuinely ceded or not yet owned the account (cutover pending, migrated
  /// out, import staging, fail-closed) suppress it.
  Future<bool> allowsAccountNotificationDisplay({String? peerId}) async {
    final authority = await _authorityRepository.loadAuthority();
    if (authority == null) {
      return true;
    }
    if (authority.isFailClosed) {
      return false;
    }
    if (authority.accountPeerId != null &&
        peerId != null &&
        authority.accountPeerId != peerId) {
      return false;
    }
    return authority.state.allowsBackgroundNotificationDisplay;
  }
}

extension AccountMigrationRuntimeNetworkPolicy
    on AccountMigrationAuthorityState {
  bool get allowsRuntimeNetworkSideEffects {
    return switch (this) {
      AccountMigrationAuthorityState.noAccount ||
      AccountMigrationAuthorityState.active ||
      AccountMigrationAuthorityState.migrationFailedActiveRestored => true,
      _ => false,
    };
  }

  bool get allowsBackgroundNotificationDisplay {
    return switch (this) {
      AccountMigrationAuthorityState.noAccount ||
      AccountMigrationAuthorityState.active ||
      AccountMigrationAuthorityState.migrationFailedActiveRestored ||
      AccountMigrationAuthorityState.migrationExportingNetworkPaused => true,
      _ => false,
    };
  }
}

Future<bool> allowAccountMigrationNetworkSideEffects({
  String? peerId,
  required String operation,
}) async {
  return true;
}
