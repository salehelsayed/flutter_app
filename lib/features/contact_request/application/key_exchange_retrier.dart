import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:clock/clock.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retry_coordinator.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_retry_journal.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Service that automatically retries incomplete ML-KEM key exchanges
/// when the P2P node reconnects.
///
/// Subscribes to [P2PService.stateStream] and detects transitions
/// to online state (isStarted && circuitAddresses.isNotEmpty).
/// Debounces by 5 seconds to avoid retrying during rapid state changes.
class KeyExchangeRetrier {
  final ValueNotifier<Set<String>> _stoppedPeerIds = ValueNotifier(const {});

  ValueListenable<Set<String>> get stoppedPeerIds => _stoppedPeerIds;

  Timer? _statusExpiryTimer;
  bool _disposed = false;
  late final Future<ContactRetryStatus> Function() _readStatus;
  late final Future<int> Function(String peerId) _retryInterest;

  Future<void> refreshRetryStatus() async {
    if (_disposed) return;
    try {
      _publishStatus(await _readStatus());
    } on Object {
      _publishStatus((stoppedPeerIds: const {}, nextChangeAtMs: null));
    }
  }

  Future<int> retryOnInterest(String peerId) async {
    if (_disposed || !await _allowsKeyExchangeRetry('contact_interest')) {
      return 0;
    }
    try {
      return await _retryInterest(peerId);
    } on Object {
      return 0;
    }
  }

  void _publishStatus(ContactRetryStatus status) {
    if (_disposed) return;
    _statusExpiryTimer?.cancel();
    if (!setEquals(_stoppedPeerIds.value, status.stoppedPeerIds)) {
      _stoppedPeerIds.value = status.stoppedPeerIds;
    }
    final next = status.nextChangeAtMs;
    if (next != null) {
      final delay = next - clock.now().millisecondsSinceEpoch;
      _statusExpiryTimer = Timer(
        Duration(milliseconds: delay > 0 ? delay : 1),
        refreshRetryStatus,
      );
    }
  }

  final P2PService p2pService;
  final ContactRepository contactRepo;
  final IdentityRepository identityRepo;
  final Bridge bridge;
  final AccountMigrationNetworkGate accountMigrationNetworkGate;
  late final KeyExchangeRetryCoordinator _coordinator;

  StreamSubscription? _stateSubscription;
  Timer? _debounceTimer;
  bool _wasOnline = false;

  KeyExchangeRetrier({
    required this.p2pService,
    required this.contactRepo,
    required this.identityRepo,
    required this.bridge,
    SecureKeyStore? secureKeyStore,
    this.accountMigrationNetworkGate = allowAccountMigrationNetworkSideEffects,
    KeyExchangeRetryCoordinator? coordinator,
    Future<void> Function()? beforeRetry,
    // FDC-09 §12 / CV-14: read-only wake-token resolver for the backfill drain
    // (an explicit rollback define may disable emission). Never mints/registers.
    Future<String?> Function(String peerId)? resolveWakeToken,
    LoadPendingCallWakeHandleContactIds? loadPendingCallWakeHandleContactIds,
    ResolveCallWakeHandle? resolveCallWakeHandle,
    OnCallWakeHandleDistributed? onCallWakeHandleDistributed,
    Future<bool> Function(String peerId)? shouldMarkAsNewRequest,
    Future<ContactRelationshipConsent?> Function(String peerId)? readConsent,
  }) {
    _readStatus = () => readContactRetryStatus(
      contactRepo: contactRepo,
      identityRepo: identityRepo,
      secureKeyStore: secureKeyStore,
      readConsent: readConsent,
    );
    _retryInterest = (peerId) => retryIncompleteKeyExchanges(
      contactRepo: contactRepo,
      identityRepo: identityRepo,
      p2pService: p2pService,
      bridge: bridge,
      secureKeyStore: secureKeyStore,
      resolveWakeToken: resolveWakeToken,
      loadPendingCallWakeHandleContactIds: loadPendingCallWakeHandleContactIds,
      resolveCallWakeHandle: resolveCallWakeHandle,
      onCallWakeHandleDistributed: onCallWakeHandleDistributed,
      shouldMarkAsNewRequest: shouldMarkAsNewRequest,
      readConsent: readConsent,
      interestPeerId: peerId,
      onRetryStatus: _publishStatus,
    );
    _coordinator =
        coordinator ??
        KeyExchangeRetryCoordinator(
          performRetry: () async {
            await beforeRetry?.call();
            return retryIncompleteKeyExchanges(
              contactRepo: contactRepo,
              identityRepo: identityRepo,
              p2pService: p2pService,
              bridge: bridge,
              secureKeyStore: secureKeyStore,
              resolveWakeToken: resolveWakeToken,
              loadPendingCallWakeHandleContactIds:
                  loadPendingCallWakeHandleContactIds,
              resolveCallWakeHandle: resolveCallWakeHandle,
              onCallWakeHandleDistributed: onCallWakeHandleDistributed,
              shouldMarkAsNewRequest: shouldMarkAsNewRequest,
              readConsent: readConsent,
              onRetryStatus: _publishStatus,
            );
          },
        );
  }

  /// Starts listening for state transitions.
  void start() {
    emitFlowEvent(
      layer: 'FL',
      event: 'KEY_EXCHANGE_RETRIER_START',
      details: {},
    );

    _wasOnline = _isOnline(p2pService.currentState);

    _stateSubscription = p2pService.stateStream.listen((state) {
      final nowOnline = _isOnline(state);

      if (nowOnline && !_wasOnline) {
        // Transition to online — schedule retry with debounce
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(seconds: 5), _retryIfNeeded);
      }

      _wasOnline = nowOnline;
      unawaited(refreshRetryStatus());
    });
  }

  bool _isOnline(dynamic state) {
    return state.isStarted && (state.circuitAddresses as List).isNotEmpty;
  }

  Future<int> retryNow({
    required String trigger,
    bool requireFresh = false,
  }) async {
    if (!await _allowsKeyExchangeRetry(trigger)) {
      return 0;
    }
    return _coordinator.retryNow(trigger: trigger, requireFresh: requireFresh);
  }

  Future<bool> _allowsKeyExchangeRetry(String trigger) async {
    final peerId = p2pService.currentState.peerId;
    final operation = 'key_exchange_retry_$trigger';
    final allowed = await accountMigrationNetworkGate(
      peerId: peerId,
      operation: operation,
    );
    if (!allowed) {
      emitFlowEvent(
        layer: 'FL',
        event: 'KEY_EXCHANGE_RETRIER_ACCOUNT_MIGRATION_BLOCKED',
        details: {'operation': operation, 'peerId': ?peerId},
      );
    }
    return allowed;
  }

  Future<void> _retryIfNeeded() async {
    try {
      final count = await retryNow(trigger: 'online_transition');

      if (count > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'KEY_EXCHANGE_RETRIER_RETRIED',
          details: {'count': count},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'KEY_EXCHANGE_RETRIER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  /// Stops listening and cleans up resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _statusExpiryTimer?.cancel();
    _stoppedPeerIds.dispose();
    emitFlowEvent(
      layer: 'FL',
      event: 'KEY_EXCHANGE_RETRIER_DISPOSE',
      details: {},
    );

    _debounceTimer?.cancel();
    _stateSubscription?.cancel();
    _stateSubscription = null;
  }
}
