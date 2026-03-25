import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';

/// Result of the pause handler.
class AppPausedResult {
  final int transitionedCount;
  final int groupTransitionedCount;

  const AppPausedResult({
    required this.transitionedCount,
    required this.groupTransitionedCount,
  });
}

/// Handles app pause lifecycle cleanup.
///
/// Transitions in-flight 'sending' messages to 'failed' so they can be
/// retried on resume. Does LOCAL DB work only — no network calls, no
/// P2PService interaction.
///
/// Returns [AppPausedResult] with the count of transitioned messages.
/// Catches all errors so callers never see exceptions.
Future<AppPausedResult> handleAppPaused({
  required MessageRepository messageRepo,
  GroupMessageRepository? groupMsgRepo,
}) async {
  if (kDebugMode) {
    debugPrint('[PAUSE] ====== APP PAUSE BEGIN ======');
  }

  emitFlowEvent(layer: 'FL', event: 'APP_LIFECYCLE_PAUSE_BEGIN', details: {});

  try {
    // Step 1: Find all in-flight sending messages
    final sendingMessages = await messageRepo.getSendingOutgoingMessages();
    var transitionedCount = 0;

    if (sendingMessages.isEmpty) {
      if (kDebugMode) {
        debugPrint('[PAUSE] No sending messages found — nothing to transition');
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_PAUSE_NO_SENDING_MESSAGES',
        details: {},
      );
    } else {
      if (kDebugMode) {
        debugPrint('[PAUSE] Found ${sendingMessages.length} sending messages');
      }

      // Step 2: Transition each sending message to failed
      for (final msg in sendingMessages) {
        try {
          final updated = await messageRepo.conditionalTransitionStatus(
            msg.id,
            fromStatus: 'sending',
            toStatus: 'failed',
          );
          if (updated > 0) transitionedCount++;
          emitFlowEvent(
            layer: 'FL',
            event: 'APP_LIFECYCLE_PAUSE_TRANSITION',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
              'hasWireEnvelope': msg.wireEnvelope != null,
            },
          );
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'APP_LIFECYCLE_PAUSE_TRANSITION_ERROR',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
              'error': e.toString(),
            },
          );
          // Continue to next message — do not abort batch on single failure.
        }
      }
    }

    var groupTransitionedCount = 0;
    if (groupMsgRepo != null) {
      try {
        groupTransitionedCount = await groupMsgRepo.transitionSendingToFailed();
        if (kDebugMode) {
          debugPrint(
            '[PAUSE] Group pause transition complete '
            'transitioned=$groupTransitionedCount',
          );
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'APP_LIFECYCLE_PAUSE_GROUP_TRANSITION',
          details: {'transitionedCount': groupTransitionedCount},
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[PAUSE] Group pause transition ERROR: $e');
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'APP_LIFECYCLE_PAUSE_GROUP_TRANSITION_ERROR',
          details: {'error': e.toString()},
        );
      }
    }

    if (kDebugMode) {
      debugPrint(
        '[PAUSE] ====== APP PAUSE COMPLETE ====== '
        'transitioned=$transitionedCount '
        'groupTransitioned=$groupTransitionedCount',
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_PAUSE_COMPLETE',
      details: {
        'transitionedCount': transitionedCount,
        'groupTransitionedCount': groupTransitionedCount,
      },
    );

    return AppPausedResult(
      transitionedCount: transitionedCount,
      groupTransitionedCount: groupTransitionedCount,
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[PAUSE] ====== APP PAUSE ERROR ====== $e');
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_PAUSE_ERROR',
      details: {'error': e.toString()},
    );
    return const AppPausedResult(
      transitionedCount: 0,
      groupTransitionedCount: 0,
    );
  }
}
