import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/posts/application/post_engagement_follow_on_support.dart';
import 'package:flutter_app/features/posts/application/post_pass_follow_on_support.dart';
import 'package:flutter_app/features/posts/application/post_pin_delivery_support.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PendingPostFollowOnRetrier {
  final P2PService p2pService;
  final PostRepository postRepo;
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

Future<int> retryPendingPostFollowOns({
  required PostRepository postRepo,
  required P2PService p2pService,
}) async {
  final jobs = await postRepo.loadRetryableFollowOnOutboxJobs();
  var retriedCount = 0;

  for (final job in jobs) {
    if (job.recipientDeliveries.isEmpty) {
      continue;
    }
    if (isPostPinFollowOnEventType(job.event.eventType)) {
      retriedCount++;
      await retryPostPinFollowOnJob(
        postRepo: postRepo,
        p2pService: p2pService,
        job: job,
      );
      continue;
    }
    if (!isPostEngagementFollowOnEventType(job.event.eventType)) {
      if (!isPostPassFollowOnEventType(job.event.eventType)) {
        continue;
      }
      retriedCount++;
      await retryPostPassFollowOnJob(
        postRepo: postRepo,
        p2pService: p2pService,
        job: job,
      );
      continue;
    }
    retriedCount++;
    await retryPostEngagementFollowOnJob(
      postRepo: postRepo,
      p2pService: p2pService,
      job: job,
    );
  }

  return retriedCount;
}
