import 'dart:async';

import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';

typedef AccountMigrationNetworkGate =
    Future<bool> Function({String? peerId, required String operation});

class AccountMigrationRuntimeStartupSteps {
  final Set<String> _completedSteps = <String>{};

  Future<void> runAsync(String step, Future<void> Function() action) async {
    if (_completedSteps.contains(step)) {
      return;
    }
    await action();
    _completedSteps.add(step);
  }

  void runSync(String step, void Function() action) {
    if (_completedSteps.contains(step)) {
      return;
    }
    action();
    _completedSteps.add(step);
  }
}

class AccountMigrationRuntimeStartupLatch {
  final Future<bool> Function()? startRuntime;
  final void Function()? onAttemptStarted;
  final FutureOr<void> Function()? onStarted;

  Future<void>? _startedOrInFlight;

  AccountMigrationRuntimeStartupLatch({
    required this.startRuntime,
    this.onAttemptStarted,
    this.onStarted,
  });

  Future<void> ensureStarted() {
    final existing = _startedOrInFlight;
    if (existing != null) {
      return existing;
    }

    final completer = Completer<void>();
    final published = completer.future;
    _startedOrInFlight = published;

    final start = startRuntime;
    if (start == null) {
      completer.complete();
      return published;
    }

    onAttemptStarted?.call();
    Future<bool> outcome;
    try {
      outcome = start();
    } catch (error, stackTrace) {
      if (identical(_startedOrInFlight, published)) {
        _startedOrInFlight = null;
      }
      completer.completeError(error, stackTrace);
      return published;
    }

    outcome.then(
      (started) async {
        if (!started && identical(_startedOrInFlight, published)) {
          _startedOrInFlight = null;
        }
        if (!started) {
          completer.complete();
          return;
        }

        try {
          await onStarted?.call();
          completer.complete();
        } catch (error, stackTrace) {
          if (identical(_startedOrInFlight, published)) {
            _startedOrInFlight = null;
          }
          completer.completeError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_startedOrInFlight, published)) {
          _startedOrInFlight = null;
        }
        completer.completeError(error, stackTrace);
      },
    );
    return published;
  }
}

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
