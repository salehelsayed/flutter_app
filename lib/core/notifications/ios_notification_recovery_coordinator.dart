import 'dart:async';

import '../database/helpers/canonical_notification_badge_state_db_helpers.dart';
import 'ios_notification_recovery_bridge.dart';

typedef ActiveNotificationAccountLoader = Future<String?> Function();
typedef CanonicalNotificationBadgeStateLoader =
    Future<CanonicalNotificationBadgeState> Function();

final class IosNotificationRecoveryMutationScope {
  const IosNotificationRecoveryMutationScope._(
    this.id, {
    this.mailboxAlertDrainContext,
  });

  final int id;
  final IosMailboxAlertDrainContext? mailboxAlertDrainContext;
}

/// Native recovery boundary owned by one actual serialized P2P inbox drain.
///
/// A drain that starts inside a wider application mutation contributes its
/// fixed-point result to that wider mutation. An autonomous warm/health/UI
/// drain still captures the native lease before its first replay, but cannot
/// by itself claim that every canonical notification family was exhausted.
final class IosNotificationRecoveryDrainGeneration {
  const IosNotificationRecoveryDrainGeneration._(
    this.scope, {
    required this.contributesToOuterCompleteness,
  });

  final IosNotificationRecoveryMutationScope scope;
  final bool contributesToOuterCompleteness;

  IosMailboxAlertDrainContext? get mailboxAlertDrainContext =>
      scope.mailboxAlertDrainContext;
}

/// One begin-token-bound silent repair authority shared across every page of
/// the existing inbox drain generation. It is one-shot and only the P2P drain
/// fixed point may consume it.
final class IosMailboxAlertDrainContext {
  IosMailboxAlertDrainContext._({
    required IosNotificationRecoveryBridge bridge,
    required this.begin,
    required this.lease,
  }) : _bridge = bridge;

  final IosNotificationRecoveryBridge _bridge;
  final IosNotificationReconciliationToken begin;
  final IosMailboxAlertLease lease;
  Future<void>? _consumption;

  String get identity =>
      '${begin.token}\u0000${begin.watermark}\u0000'
      '${lease.generation}\u0000${lease.sequence}';

  Future<void> consumeAtFixedPoint() => _consumption ??= _bridge
      .consumeMailboxAlertLease(begin: begin, lease: lease)
      .catchError((Object error, StackTrace stackTrace) {
        _consumption = null;
        Error.throwWithStackTrace(error, stackTrace);
      });
}

final class _IosNotificationRecoveryMutationBoundary {
  late final Future<void> ready;
  String? accountPeerId;
  IosNotificationReconciliationToken? begin;
  IosMailboxAlertDrainContext? mailboxAlertDrainContext;
}

final class _IosNotificationRecoveryPassRequest {
  const _IosNotificationRecoveryPassRequest.passive({
    required this.canonicalStateComplete,
    required this.globallyExhaustive,
  }) : accountPeerId = null,
       begin = null;

  const _IosNotificationRecoveryPassRequest.preCaptured({
    required this.accountPeerId,
    required this.begin,
    required this.canonicalStateComplete,
    required this.globallyExhaustive,
  });

  final String? accountPeerId;
  final IosNotificationReconciliationToken? begin;
  final bool canonicalStateComplete;
  final bool globallyExhaustive;

  bool get hasPreCapturedBoundary => accountPeerId != null && begin != null;
}

/// Coalesces lifecycle and notification settlement triggers into canonical,
/// two-phase iOS recovery passes.
final class IosNotificationRecoveryCoordinator {
  IosNotificationRecoveryCoordinator({
    required bool platformEnabled,
    required IosNotificationRecoveryBridge bridge,
    required ActiveNotificationAccountLoader loadActiveAccountPeerId,
    required CanonicalNotificationBadgeStateLoader loadCanonicalState,
  }) : _platformEnabled = platformEnabled,
       _bridge = bridge,
       _loadActiveAccountPeerId = loadActiveAccountPeerId,
       _loadCanonicalState = loadCanonicalState;

  final bool _platformEnabled;
  final IosNotificationRecoveryBridge _bridge;
  final ActiveNotificationAccountLoader _loadActiveAccountPeerId;
  final CanonicalNotificationBadgeStateLoader _loadCanonicalState;

  Future<void>? _activeDrain;
  bool _rerunRequested = false;
  _IosNotificationRecoveryPassRequest? _nextPassRequest;
  var _nextMutationScopeId = 1;
  var _canonicalMutationEpoch = 0;
  var _incompleteStateEpoch = 0;
  final Set<int> _activeMutationScopes = <int>{};
  final Set<int> _returnedMutationScopes = <int>{};
  bool _mutationScopesComplete = true;
  bool _mutationScopesIncludeExhaustivePass = false;
  bool _canonicalStateKnownIncomplete = false;
  Completer<void>? _mutationScopesDrained;
  _IosNotificationRecoveryMutationBoundary? _mutationBoundary;
  Future<void>? _mutationBoundaryInitialization;
  Future<void>? _activeClear;
  bool _accountClearFenced = false;
  bool _accountClearRequiresRetry = false;
  var _accountClearGeneration = 0;
  String? _clearedAccountPeerId;

  /// Captures the native watermark/optional mailbox lease for one real P2P
  /// drain generation. This must run after P2P serialization elects an owner
  /// and before that owner replays either staged or freshly retrieved rows.
  Future<IosNotificationRecoveryDrainGeneration>
  beginInboxDrainGeneration() async {
    final contributesToOuterCompleteness = _activeMutationScopes.isNotEmpty;
    final scope = await beginCanonicalMutation();
    return IosNotificationRecoveryDrainGeneration._(
      scope,
      contributesToOuterCompleteness: contributesToOuterCompleteness,
    );
  }

  /// Ends the exact drain-owned scope. Autonomous drains are deliberately
  /// incomplete as a global canonical snapshot; nested drains may contribute
  /// their fixed-point result while the wider owner accounts for other lanes.
  Future<void> endInboxDrainGeneration(
    IosNotificationRecoveryDrainGeneration generation, {
    required bool reachedFixedPoint,
  }) => endCanonicalMutation(
    generation.scope,
    canonicalStateComplete:
        generation.contributesToOuterCompleteness && reachedFixedPoint,
  );

  /// Fences a canonical ingress/drain mutation against settlement callbacks.
  /// The scope is registered before awaiting an older recovery pass, so a new
  /// default-complete callback cannot overtake the mutation.
  Future<IosNotificationRecoveryMutationScope> beginCanonicalMutation({
    bool globallyExhaustive = false,
    bool canReactivateAfterAccountClear = false,
    bool allowClearedAccountPeerReactivation = false,
  }) async {
    if (!_platformEnabled) {
      return const IosNotificationRecoveryMutationScope._(0);
    }
    if (_accountClearFenced) {
      if (!canReactivateAfterAccountClear) {
        return const IosNotificationRecoveryMutationScope._(0);
      }
      var observedClearGeneration = _accountClearGeneration;
      final clear = _activeClear;
      if (clear != null) await clear;
      if (_accountClearRequiresRetry) {
        await clearAccount();
        observedClearGeneration = _accountClearGeneration;
      }
      final activeAccountPeerId = (await _loadActiveAccountPeerId())?.trim();
      if (_accountClearGeneration != observedClearGeneration) {
        return const IosNotificationRecoveryMutationScope._(0);
      }
      if (_accountClearFenced) {
        if (activeAccountPeerId == null ||
            activeAccountPeerId.isEmpty ||
            (!allowClearedAccountPeerReactivation &&
                activeAccountPeerId == _clearedAccountPeerId)) {
          return const IosNotificationRecoveryMutationScope._(0);
        }
        _accountClearFenced = false;
      }
    }
    final isFirstScope = _activeMutationScopes.isEmpty;
    final scope = IosNotificationRecoveryMutationScope._(
      _nextMutationScopeId++,
    );
    if (isFirstScope) {
      _mutationScopesDrained = Completer<void>();
      final boundary = _IosNotificationRecoveryMutationBoundary();
      _mutationBoundary = boundary;
      boundary.ready = _initializeMutationBoundary(boundary);
      _mutationBoundaryInitialization = boundary.ready;
    }
    _activeMutationScopes.add(scope.id);
    // Any pass that started before this mutation must remain incomplete even
    // if the scope closes between its SQLite snapshot and native commit.
    _canonicalMutationEpoch += 1;
    _mutationScopesIncludeExhaustivePass =
        _mutationScopesIncludeExhaustivePass || globallyExhaustive;
    final boundary = _mutationBoundary!;
    try {
      await boundary.ready;
    } catch (_) {
      _removeFailedMutationScope(scope, boundary);
      rethrow;
    }
    if (!_activeMutationScopes.contains(scope.id) ||
        !identical(_mutationBoundary, boundary) ||
        _accountClearFenced) {
      _removeFailedMutationScope(scope, boundary);
      throw StateError('iOS notification recovery mutation was superseded');
    }
    _returnedMutationScopes.add(scope.id);
    return IosNotificationRecoveryMutationScope._(
      scope.id,
      mailboxAlertDrainContext: boundary.mailboxAlertDrainContext,
    );
  }

  Future<void> _initializeMutationBoundary(
    _IosNotificationRecoveryMutationBoundary boundary,
  ) async {
    final active = _activeDrain;
    if (active != null) {
      try {
        await active;
      } catch (_) {
        // A pre-existing failed pass does not prevent the new scope from
        // capturing its own native boundary.
      }
    }
    if (!identical(_mutationBoundary, boundary) || _accountClearFenced) {
      throw StateError('iOS notification recovery mutation was superseded');
    }
    final accountPeerId = (await _loadActiveAccountPeerId())?.trim();
    if (!identical(_mutationBoundary, boundary) || _accountClearFenced) {
      throw StateError('iOS notification recovery mutation was superseded');
    }
    if (accountPeerId == null || accountPeerId.isEmpty) return;
    boundary.accountPeerId = accountPeerId;
    boundary.begin = await _bridge.beginReconciliation(accountPeerId);
    final begin = boundary.begin!;
    final lease = begin.mailboxAlertLease;
    if (lease != null) {
      boundary.mailboxAlertDrainContext = IosMailboxAlertDrainContext._(
        bridge: _bridge,
        begin: begin,
        lease: lease,
      );
    }
    if (!identical(_mutationBoundary, boundary) || _accountClearFenced) {
      throw StateError('iOS notification recovery mutation was superseded');
    }
  }

  void _removeFailedMutationScope(
    IosNotificationRecoveryMutationScope scope,
    _IosNotificationRecoveryMutationBoundary boundary,
  ) {
    _activeMutationScopes.remove(scope.id);
    _returnedMutationScopes.remove(scope.id);
    _canonicalStateKnownIncomplete = true;
    _incompleteStateEpoch += 1;
    if (_activeMutationScopes.isNotEmpty) return;
    if (identical(_mutationBoundary, boundary)) _mutationBoundary = null;
    _mutationBoundaryInitialization = null;
    _mutationScopesComplete = true;
    _mutationScopesIncludeExhaustivePass = false;
    final drained = _mutationScopesDrained;
    _mutationScopesDrained = null;
    drained?.complete();
  }

  Future<void> endCanonicalMutation(
    IosNotificationRecoveryMutationScope scope, {
    required bool canonicalStateComplete,
  }) {
    if (scope.id == 0) return Future<void>.value();
    if (!_activeMutationScopes.remove(scope.id)) return Future<void>.value();
    _returnedMutationScopes.remove(scope.id);
    _mutationScopesComplete = _mutationScopesComplete && canonicalStateComplete;
    if (_activeMutationScopes.isNotEmpty) return Future<void>.value();

    final complete = _mutationScopesComplete;
    final globallyExhaustive = _mutationScopesIncludeExhaustivePass;
    final boundary = _mutationBoundary;
    _mutationBoundary = null;
    _mutationBoundaryInitialization = null;
    _mutationScopesComplete = true;
    _mutationScopesIncludeExhaustivePass = false;
    if (!complete) {
      _canonicalStateKnownIncomplete = true;
      _incompleteStateEpoch += 1;
    }
    final Future<void> reconciliation;
    if (boundary?.accountPeerId != null && boundary?.begin != null) {
      reconciliation = _enqueuePass(
        _IosNotificationRecoveryPassRequest.preCaptured(
          accountPeerId: boundary!.accountPeerId!,
          begin: boundary.begin!,
          canonicalStateComplete: complete,
          globallyExhaustive: globallyExhaustive,
        ),
      );
    } else {
      // No account existed at scope entry, so there is no safe pre-mutation
      // watermark. A post-mutation pass may update additive state but must not
      // claim destructive completeness.
      if (complete) {
        _canonicalStateKnownIncomplete = true;
        _incompleteStateEpoch += 1;
      }
      reconciliation = _enqueuePass(
        const _IosNotificationRecoveryPassRequest.passive(
          canonicalStateComplete: false,
          globallyExhaustive: false,
        ),
      );
    }
    final drained = _mutationScopesDrained;
    _mutationScopesDrained = null;
    drained?.complete();
    return reconciliation;
  }

  /// Runs one canonical pass. Triggers arriving during it collapse into one
  /// final pass using the completeness value from the newest trigger.
  Future<void> reconcile({
    bool canonicalStateComplete = true,
    bool globallyExhaustive = false,
  }) {
    if (!_platformEnabled || _accountClearFenced) {
      return Future<void>.value();
    }

    if (_activeMutationScopes.isNotEmpty) {
      _mutationScopesComplete =
          _mutationScopesComplete && canonicalStateComplete;
      _mutationScopesIncludeExhaustivePass =
          _mutationScopesIncludeExhaustivePass || globallyExhaustive;
      if (!canonicalStateComplete) {
        _canonicalStateKnownIncomplete = true;
        _incompleteStateEpoch += 1;
      }
      return Future<void>.value();
    }

    if (!canonicalStateComplete) {
      _canonicalStateKnownIncomplete = true;
      _incompleteStateEpoch += 1;
    }

    return _enqueuePass(
      _IosNotificationRecoveryPassRequest.passive(
        canonicalStateComplete: canonicalStateComplete,
        globallyExhaustive: globallyExhaustive,
      ),
    );
  }

  Future<void> _enqueuePass(_IosNotificationRecoveryPassRequest request) {
    if (!_platformEnabled || _accountClearFenced) {
      return Future<void>.value();
    }

    final active = _activeDrain;
    if (active != null) {
      _rerunRequested = true;
      _nextPassRequest = request;
      return active;
    }

    _nextPassRequest = request;
    final completer = Completer<void>();
    _activeDrain = completer.future;
    unawaited(_drain(completer));
    return completer.future;
  }

  Future<void> _drain(Completer<void> completer) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    do {
      _rerunRequested = false;
      final request = _nextPassRequest!;
      final incompleteStateEpoch = _incompleteStateEpoch;
      try {
        final committedComplete = await _runOnce(
          request: request,
          incompleteStateEpoch: incompleteStateEpoch,
        );
        if (committedComplete &&
            request.globallyExhaustive &&
            _incompleteStateEpoch == incompleteStateEpoch) {
          // Promotion is transactional: a failed or overlapped exhaustive pass
          // never clears the sticky incomplete latch.
          _canonicalStateKnownIncomplete = false;
        }
        lastError = null;
        lastStackTrace = null;
      } catch (error, stackTrace) {
        _canonicalStateKnownIncomplete = true;
        _incompleteStateEpoch += 1;
        lastError = error;
        lastStackTrace = stackTrace;
      }
    } while (_rerunRequested);
    _activeDrain = null;
    if (lastError == null) {
      completer.complete();
    } else {
      completer.completeError(lastError, lastStackTrace!);
    }
  }

  Future<bool> _runOnce({
    required _IosNotificationRecoveryPassRequest request,
    required int incompleteStateEpoch,
  }) async {
    final mutationEpoch = _canonicalMutationEpoch;
    final currentAccountPeerId = (await _loadActiveAccountPeerId())?.trim();
    final accountPeerId = request.accountPeerId ?? currentAccountPeerId;
    if (accountPeerId == null || accountPeerId.isEmpty) {
      await _bridge.clearAccount();
      return request.canonicalStateComplete;
    }
    if (request.hasPreCapturedBoundary &&
        currentAccountPeerId != accountPeerId) {
      throw StateError(
        'iOS notification recovery account changed during mutation',
      );
    }

    // Mutation scopes carry a watermark captured before ingress/drain work.
    // Passive settlement passes capture immediately before the SQLite read.
    final begin =
        request.begin ?? await _bridge.beginReconciliation(accountPeerId);
    late final CanonicalNotificationBadgeState canonicalState;
    try {
      canonicalState = await _loadCanonicalState();
    } catch (error, stackTrace) {
      // Consume the one-shot native token without granting destructive
      // authority. This keeps a transient SQLite failure retryable without
      // stranding an outstanding native reconciliation session.
      try {
        await _bridge.commitReconciliation(
          begin: begin,
          accountPeerId: accountPeerId,
          canonicalState: CanonicalNotificationBadgeState(
            unreadCount: 0,
            identities: const <CanonicalNotificationIdentity>[],
          ),
          canonicalStateComplete: false,
        );
      } catch (_) {
        // Preserve the causal SQLite error; the next native begin invalidates
        // any token that could not be consumed.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    final accountAfterLoad = (await _loadActiveAccountPeerId())?.trim();
    if (accountAfterLoad != accountPeerId) {
      throw StateError(
        'iOS notification recovery account changed before commit',
      );
    }
    final commitComplete =
        request.canonicalStateComplete &&
        (request.globallyExhaustive || !_canonicalStateKnownIncomplete) &&
        mutationEpoch == _canonicalMutationEpoch &&
        incompleteStateEpoch == _incompleteStateEpoch &&
        _activeMutationScopes.isEmpty;
    await _bridge.commitReconciliation(
      begin: begin,
      accountPeerId: accountPeerId,
      canonicalState: canonicalState,
      canonicalStateComplete: commitComplete,
    );
    return commitComplete;
  }

  Future<void> retireConversation({
    required CanonicalNotificationLane lane,
    required String conversationId,
  }) async {
    if (!_platformEnabled || _accountClearFenced) return;
    final accountPeerId = (await _loadActiveAccountPeerId())?.trim();
    if (accountPeerId == null || accountPeerId.isEmpty) {
      await _bridge.clearAccount();
      return;
    }
    await _bridge.retireConversation(
      accountPeerId: accountPeerId,
      lane: lane,
      conversationId: conversationId,
    );
  }

  Future<void> clearAccount() async {
    if (!_platformEnabled) return;
    _accountClearFenced = true;
    _accountClearRequiresRetry = true;
    _canonicalMutationEpoch += 1;
    _canonicalStateKnownIncomplete = true;
    _incompleteStateEpoch += 1;
    final existing = _activeClear;
    if (existing != null) {
      await existing;
      return;
    }
    _accountClearGeneration += 1;
    final aborted = _abortMutationBatchForAccountClear();
    final clear = _clearAccountAfterActiveWork(
      boundaryInitialization: aborted.boundaryInitialization,
      returnedScopesDrained: aborted.returnedScopesDrained,
    );
    _activeClear = clear;
    try {
      await clear;
    } finally {
      if (identical(_activeClear, clear)) _activeClear = null;
    }
  }

  ({Future<void>? boundaryInitialization, Future<void>? returnedScopesDrained})
  _abortMutationBatchForAccountClear() {
    final boundaryInitialization = _mutationBoundaryInitialization;
    final acquiringScopes = _activeMutationScopes.difference(
      _returnedMutationScopes,
    );
    _activeMutationScopes.removeAll(acquiringScopes);
    _mutationBoundary = null;
    _mutationBoundaryInitialization = null;
    Future<void>? returnedScopesDrained;
    if (_returnedMutationScopes.isEmpty) {
      _mutationScopesComplete = true;
      _mutationScopesIncludeExhaustivePass = false;
      final drained = _mutationScopesDrained;
      _mutationScopesDrained = null;
      drained?.complete();
    } else {
      returnedScopesDrained = _mutationScopesDrained?.future;
    }
    return (
      boundaryInitialization: boundaryInitialization,
      returnedScopesDrained: returnedScopesDrained,
    );
  }

  Future<void> _clearAccountAfterActiveWork({
    required Future<void>? boundaryInitialization,
    required Future<void>? returnedScopesDrained,
  }) async {
    if (boundaryInitialization != null) {
      try {
        await boundaryInitialization;
      } catch (_) {
        // Account clear supersedes a failed or aborted boundary acquisition.
      }
    }
    if (returnedScopesDrained != null) await returnedScopesDrained;
    final active = _activeDrain;
    if (active != null) {
      try {
        await active;
      } catch (_) {
        // Exact account clear supersedes a failed canonical pass.
      }
    }
    String? clearedAccountPeerId;
    try {
      final loaded = (await _loadActiveAccountPeerId())?.trim();
      if (loaded != null && loaded.isNotEmpty) {
        clearedAccountPeerId = loaded;
      }
    } catch (_) {
      // Native clear remains authoritative even if the outgoing identity can
      // no longer be loaded. A future non-empty identity may then reactivate.
    }
    if (clearedAccountPeerId != null) {
      _clearedAccountPeerId = clearedAccountPeerId;
    }
    await _bridge.clearAccount();
    _accountClearRequiresRetry = false;
    _canonicalStateKnownIncomplete = false;
    _incompleteStateEpoch += 1;
  }
}
