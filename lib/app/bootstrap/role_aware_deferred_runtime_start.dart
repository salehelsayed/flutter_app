import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';

/// What the role-aware deferred start actually did.
enum RoleAwareRuntimeStartOutcome {
  /// Identity restoration/setup has not committed yet. Returning false keeps
  /// the application startup latch re-armable for setup success.
  deferredNoIdentity,

  /// Ordinary primary: the incumbent full runtime startup ran.
  primaryRuntimeStarted,

  /// Active linked secondary: ONLY the foundation prerequisites ran
  /// (credential/peer/node/status/QR). Generic runtime startup ran zero times.
  linkedFoundationStarted,

  /// Partial, corrupt, or cross-account linked authority: NEITHER path ran.
  refused,
}

/// Role-aware owner of the deferred runtime start, decided BEFORE the router.
///
/// `MyApp.initState` invokes one unconditional `deferredRuntimeStartup`
/// callback. Plan 360 keeps that callback and its `Future<bool> Function()`
/// signature exactly as-is, and delegates the decision here instead.
///
/// Deciding pre-router is the whole point. A linked secondary must never reach
/// generic runtime startup — Firebase/push registration, the ~25 listeners,
/// contact-request and key-exchange retry, group recovery, message retry and
/// inbox drain. Those owners all assume a single primary installation on one
/// account mailbox, which is precisely the assumption a linked secondary
/// breaks; they become safe only when Plan 361 makes event fanout
/// device-aware. Gating them later, at navigation time, would be a race: the
/// deferred start already fired.
///
/// Partial authority starts NEITHER path. A half-written credential must not
/// silently behave like a primary — that would put both installations back on
/// one shared relay mailbox, which is the exact failure this plan exists to
/// prevent.
class RoleAwareDeferredRuntimeStart {
  RoleAwareDeferredRuntimeStart({
    required Future<LinkedInstallationAuthoritySnapshot> Function()
    loadLinkedAuthority,
    required Future<bool> Function() startPrimaryRuntimeServices,
    required Future<bool> Function() startLinkedFoundationPrerequisites,
    Future<bool> Function()? hasIdentity,
  }) : _loadLinkedAuthority = loadLinkedAuthority,
       _startPrimaryRuntimeServices = startPrimaryRuntimeServices,
       _startLinkedFoundationPrerequisites = startLinkedFoundationPrerequisites,
       _hasIdentity = hasIdentity;

  final Future<LinkedInstallationAuthoritySnapshot> Function()
  _loadLinkedAuthority;
  final Future<bool> Function() _startPrimaryRuntimeServices;
  final Future<bool> Function() _startLinkedFoundationPrerequisites;
  final Future<bool> Function()? _hasIdentity;

  RoleAwareRuntimeStartOutcome? _lastOutcome;
  String? _activeLinkedTransportPeerId;
  String? _activeLinkedAccountPeerId;

  /// The outcome of the most recent [start], for diagnostics and proofs.
  RoleAwareRuntimeStartOutcome? get lastOutcome => _lastOutcome;

  /// The exact transport peer an ACTIVE linked credential names, or null on an
  /// ordinary primary (and before [start] has run).
  ///
  /// This is the SYNCHRONOUS seam `P2PServiceImpl` needs: reading secure
  /// storage is async, but the qualification happens inside `startNode`. The
  /// ordering that makes the cache correct is the incumbent startup ordering —
  /// `MyApp.initState` fires the deferred start, and `StartupRouter._doStartP2P`
  /// awaits `ensureRuntimeServicesReady` before it calls `startP2PNode`. So by
  /// the time any node start happens, [start] has already resolved authority.
  ///
  /// Null is the safe default: the qualification is a no-op, which is exactly
  /// the incumbent primary behavior.
  String? get activeLinkedTransportPeerId => _activeLinkedTransportPeerId;

  /// The LOGICAL account peer an ACTIVE linked credential is bound to, or null
  /// on an ordinary primary.
  ///
  /// The P2P service asks the account-migration gate about THIS peer, never the
  /// transport peer: migration authority is account-level, and asking it about a
  /// per-device identity it does not cover would let a migrated-out account keep
  /// transmitting from its linked device.
  String? get activeLinkedAccountPeerId => _activeLinkedAccountPeerId;

  /// Runs the correct startup for this installation's persisted role.
  ///
  /// Returns whether runtime services this installation is entitled to are
  /// now up — matching the incumbent `deferredRuntimeStartup` contract.
  Future<bool> start() async {
    final hasIdentity = _hasIdentity;
    if (hasIdentity != null && !await hasIdentity()) {
      _activeLinkedTransportPeerId = null;
      _activeLinkedAccountPeerId = null;
      _lastOutcome = RoleAwareRuntimeStartOutcome.deferredNoIdentity;
      emitFlowEvent(
        layer: 'FL',
        event: 'ROLE_AWARE_RUNTIME_START_DEFERRED_NO_IDENTITY',
        details: const {},
      );
      return false;
    }
    final LinkedInstallationAuthoritySnapshot snapshot;
    try {
      snapshot = await _loadLinkedAuthority();
    } catch (error) {
      // An unreadable authority is fail-closed, never "assume primary".
      _activeLinkedTransportPeerId = null;
      _activeLinkedAccountPeerId = null;
      emitFlowEvent(
        layer: 'FL',
        event: 'ROLE_AWARE_RUNTIME_START_AUTHORITY_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      _lastOutcome = RoleAwareRuntimeStartOutcome.refused;
      return false;
    }

    if (snapshot.isOrdinaryPrimary) {
      _activeLinkedTransportPeerId = null;
      _activeLinkedAccountPeerId = null;
      _lastOutcome = null;
      final started = await _startPrimaryRuntimeServices();
      if (started) {
        _lastOutcome = RoleAwareRuntimeStartOutcome.primaryRuntimeStarted;
      }
      return started;
    }

    if (snapshot.isActiveLinkedSecondary) {
      // Publish the exact transport peer BEFORE starting anything, so the node
      // start that follows is qualified against it.
      _activeLinkedTransportPeerId = snapshot.credential?.transportPeerId;
      _activeLinkedAccountPeerId = snapshot.credential?.accountPeerId;
      emitFlowEvent(
        layer: 'FL',
        event: 'ROLE_AWARE_RUNTIME_START_LINKED_FOUNDATION',
        details: const {},
      );
      _lastOutcome = null;
      final started = await _startLinkedFoundationPrerequisites();
      if (started) {
        _lastOutcome = RoleAwareRuntimeStartOutcome.linkedFoundationStarted;
      }
      return started;
    }

    _activeLinkedTransportPeerId = null;
    _activeLinkedAccountPeerId = null;
    emitFlowEvent(
      layer: 'FL',
      event: 'ROLE_AWARE_RUNTIME_START_REFUSED',
      details: {
        'disposition': snapshot.disposition.name,
        if (snapshot.failClosedReason != null)
          'reason': snapshot.failClosedReason,
      },
    );
    _lastOutcome = RoleAwareRuntimeStartOutcome.refused;
    return false;
  }
}
