import 'dart:async';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/posts/application/legacy_post_feature_gate.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_job.dart';
import 'package:flutter_app/features/posts/domain/models/post_retract_envelope.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PendingPostFollowOnRetrier {
  final P2PService p2pService;
  final PostRepository postRepo;
  final AccountMigrationNetworkGate accountMigrationNetworkGate;
  final Duration retryDebounce;
  final Duration periodicRetryInterval;

  StreamSubscription? _stateSubscription;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  bool _wasOnline = false;
  bool _isRetrying = false;

  PendingPostFollowOnRetrier({
    required this.p2pService,
    required this.postRepo,
    this.accountMigrationNetworkGate = allowAccountMigrationNetworkSideEffects,
    this.retryDebounce = const Duration(seconds: 5),
    this.periodicRetryInterval = const Duration(minutes: 5),
  });

  void start() {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_POST_FOLLOW_ON_RETRIER_START',
      details: {},
    );

    _wasOnline = _isOnline(p2pService.currentState);
    if (_wasOnline) {
      _scheduleRetry();
      _periodicTimer?.cancel();
      _periodicTimer = Timer.periodic(
        periodicRetryInterval,
        (_) => unawaited(_retryIfNeeded()),
      );
    }
    _stateSubscription = p2pService.stateStream.listen((state) {
      final nowOnline = _isOnline(state);

      if (nowOnline && !_wasOnline) {
        _scheduleRetry();
        _periodicTimer?.cancel();
        _periodicTimer = Timer.periodic(
          periodicRetryInterval,
          (_) => unawaited(_retryIfNeeded()),
        );
      } else if (!nowOnline && _wasOnline) {
        _periodicTimer?.cancel();
        _periodicTimer = null;
      }

      _wasOnline = nowOnline;
    });
  }

  bool _isOnline(dynamic state) {
    return state.isStarted && (state.circuitAddresses as List).isNotEmpty;
  }

  void _scheduleRetry() {
    _debounceTimer?.cancel();
    if (retryDebounce == Duration.zero) {
      unawaited(_retryIfNeeded());
    } else {
      _debounceTimer = Timer(retryDebounce, () {
        unawaited(_retryIfNeeded());
      });
    }
  }

  Future<void> _retryIfNeeded() async {
    if (_isRetrying) {
      return;
    }
    _isRetrying = true;

    try {
      final retried = await retryPendingPostFollowOns(
        postRepo: postRepo,
        p2pService: p2pService,
        accountMigrationNetworkGate: accountMigrationNetworkGate,
      );
      if (retried > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_POST_FOLLOW_ON_RETRIER_RETRIED',
          details: {'count': retried},
        );
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_POST_FOLLOW_ON_RETRIER_ERROR',
        details: {'error': error.toString()},
      );
    } finally {
      _isRetrying = false;
    }
  }

  void dispose() {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_POST_FOLLOW_ON_RETRIER_DISPOSE',
      details: {},
    );
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _stateSubscription?.cancel();
    _stateSubscription = null;
  }
}

/// Retries queued thought retractions. Every other follow-on type is legacy
/// Posts and is dropped unsent.
Future<int> retryPendingPostFollowOns({
  required PostRepository postRepo,
  required P2PService p2pService,
  AccountMigrationNetworkGate accountMigrationNetworkGate =
      allowAccountMigrationNetworkSideEffects,
  DateTime Function()? nowProvider,
}) async {
  final now = (nowProvider ?? DateTime.now)().toUtc();
  final retractions = <PostFollowOnOutboxJob>[];
  for (final job in await postRepo.loadRetryableFollowOnOutboxJobs()) {
    if (job.event.eventType != PostRetractEnvelope.type) {
      rejectLegacyPostFeature(job.event.eventType);
      continue;
    }
    final retraction = PostRetractEnvelope.fromJson(job.event.rawEnvelope);
    if (retraction == null ||
        ThoughtLifetime.isExpired(retraction.postCreatedAt, now)) {
      // Every copy of the thought has expired on its own by now.
      await postRepo.deleteFollowOnOutboxEvent(job.event.eventId);
      continue;
    }
    retractions.add(job);
  }
  if (retractions.isEmpty) {
    return 0;
  }

  if (!await _allowsPostFollowOnNetworkSideEffects(
    p2pService: p2pService,
    accountMigrationNetworkGate: accountMigrationNetworkGate,
    operation: 'pending_post_follow_on_retry',
  )) {
    return 0;
  }

  for (final job in retractions) {
    await deliverQueuedPostFollowOn(
      postRepo: postRepo,
      p2pService: p2pService,
      eventId: job.event.eventId,
      envelope: job.event.rawEnvelope,
      deliveries: job.recipientDeliveries,
    );
  }
  return retractions.length;
}

Future<bool> _allowsPostFollowOnNetworkSideEffects({
  required P2PService p2pService,
  required AccountMigrationNetworkGate accountMigrationNetworkGate,
  required String operation,
}) async {
  final peerId = p2pService.currentState.peerId;
  final allowed = await accountMigrationNetworkGate(
    peerId: peerId,
    operation: operation,
  );
  if (!allowed) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_POST_FOLLOW_ON_RETRIER_ACCOUNT_MIGRATION_BLOCKED',
      details: {'operation': operation, 'peerId': ?peerId},
    );
  }
  return allowed;
}
