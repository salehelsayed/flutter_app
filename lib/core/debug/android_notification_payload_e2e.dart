import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/debug/android_notification_payload_e2e_protocol.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';

export 'package:flutter_app/core/debug/android_notification_payload_e2e_protocol.dart';

typedef AndroidNotificationE2EProgressWriter =
    Future<void> Function(Map<String, dynamic> value);
typedef AndroidNotificationFcmTokenProvider = Future<String?> Function();

/// Runs a production notification proof action inside the already-installed
/// main application. This never builds, installs, injects ciphertext, or
/// bypasses the ordinary relay/FCM/message-repository paths.
Future<Map<String, dynamic>> runAndroidNotificationPayloadE2EAction({
  required Map<String, dynamic> config,
  required P2PService p2pService,
  required Bridge bridge,
  required MessageRepository messageRepo,
  required PushEnvelopeStagingStore pushEnvelopeStagingStore,
  required AndroidNotificationE2EProgressWriter writeProgress,
  AndroidNotificationFcmTokenProvider? fcmTokenProvider,
}) async {
  final request = AndroidNotificationPayloadE2ERequest.fromConfig(config);
  Map<String, dynamic> receipt(Map<String, Object?> values) =>
      <String, dynamic>{
        'schema': androidNotificationPayloadE2EResultSchema,
        'transport_action': request.action,
        'scenario': androidNotificationPayloadE2EScenario,
        'stepId': request.stepId,
        'runId': request.runId,
        'nonce': request.nonce,
        ...values,
      };

  switch (request.action) {
    case androidNotificationUnregisterPushAction:
      final response = await callP2PInboxUnregisterToken(bridge);
      if (response['ok'] != true || response['unregistered'] != true) {
        throw StateError('production relay push unregistration failed');
      }
      return receipt(<String, Object?>{
        'status': 'complete',
        'success': true,
        'unregistered': true,
      });

    case androidNotificationRestorePushAction:
      final tokenProvider =
          fcmTokenProvider ?? FirebaseMessaging.instance.getToken;
      String? token;
      final deadline = DateTime.now().add(request.timeout);
      while (DateTime.now().isBefore(deadline)) {
        token = (await tokenProvider())?.trim();
        if (token != null && token.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (token == null || token.isEmpty) {
        throw StateError('production FCM token unavailable');
      }
      if (!await p2pService.registerPushToken(token, 'android')) {
        throw StateError('production relay push registration failed');
      }
      return receipt(<String, Object?>{
        'status': 'complete',
        'success': true,
        'registered': true,
      });

    case androidNotificationClearStagingAction:
    case androidNotificationStopNodeAndClearStagingAction:
      final entries = await pushEnvelopeStagingStore.readAll();
      for (final entry in entries) {
        await pushEnvelopeStagingStore.clear(entry.id);
      }
      var stopped = false;
      if (request.action == androidNotificationStopNodeAndClearStagingAction) {
        stopped = await p2pService.stopNode();
        if (!stopped) throw StateError('production P2P node did not stop');
      }
      return receipt(<String, Object?>{
        'status': 'complete',
        'success': true,
        'clearedEntries': entries.length,
        'nodeStopped': stopped,
      });

    case androidNotificationA6ObserveAction:
      return _observeReplayBeforeAck(
        request: request,
        p2pService: p2pService,
        bridge: bridge,
        messageRepo: messageRepo,
        writeProgress: writeProgress,
        receipt: receipt,
      );

    case androidNotificationPostTapObserveAction:
      return _observePostTap(
        request: request,
        messageRepo: messageRepo,
        pushEnvelopeStagingStore: pushEnvelopeStagingStore,
        writeProgress: writeProgress,
        receipt: receipt,
      );

    case androidNotificationDrainObserveAction:
      return _observeDrainConvergence(
        request: request,
        p2pService: p2pService,
        bridge: bridge,
        messageRepo: messageRepo,
        receipt: receipt,
      );
  }

  throw StateError('unreachable Android notification action');
}

Future<Map<String, dynamic>> _observeDrainConvergence({
  required AndroidNotificationPayloadE2ERequest request,
  required P2PService p2pService,
  required Bridge bridge,
  required MessageRepository messageRepo,
  required Map<String, dynamic> Function(Map<String, Object?>) receipt,
}) async {
  const timeoutMessage = 'post-restore relay drain convergence timed out';
  final deadline = DateTime.now().add(request.timeout);
  var consecutiveExactObservations = 0;

  while (DateTime.now().isBefore(deadline)) {
    try {
      await _runWithinDeadline<void>(
        deadline,
        (_) => p2pService.drainOfflineInbox(),
        timeoutMessage,
      );
      // The public drain entry point safely latches a deferred startup drain
      // while stopped, and a started drain establishes the inbox proof. Call
      // it before waiting for the full post-drain readiness state.
      final readinessAfterDrain = p2pService.currentState;
      if (!readinessAfterDrain.isStarted ||
          !readinessAfterDrain.inboxCapabilityReady) {
        consecutiveExactObservations = 0;
        await _delayWithinDeadline(deadline, timeoutMessage);
        continue;
      }
      final messages = await _runWithinDeadline<List<ConversationMessage>>(
        deadline,
        (_) => _matchingMessages(request, messageRepo),
        timeoutMessage,
      );
      if (messages.length > 1) {
        throw const _DuplicateDrainObservation();
      }

      final pending = await _runWithinDeadline<Map<String, dynamic>>(
        deadline,
        (operationTimeout) => callP2PInboxRetrievePending(
          bridge,
          timeoutMs: operationTimeout.inMilliseconds < 1
              ? 1
              : operationTimeout.inMilliseconds,
        ),
        timeoutMessage,
        maxRequestDuration: const Duration(seconds: 3),
      );
      final pendingMessages =
          (pending['messages'] as List?) ?? const <Object?>[];
      final stateAfterDrain = p2pService.currentState;
      final isExact =
          stateAfterDrain.isStarted &&
          stateAfterDrain.inboxCapabilityReady &&
          messages.length == 1 &&
          pending['ok'] == true &&
          pendingMessages.isEmpty;
      if (!isExact) {
        consecutiveExactObservations = 0;
        await _delayWithinDeadline(deadline, timeoutMessage);
        continue;
      }

      consecutiveExactObservations++;
      if (consecutiveExactObservations < 2) {
        // A second drain proves replay/ACK convergence remains exactly once.
        continue;
      }

      return receipt(<String, Object?>{
        'status': 'complete',
        'success': true,
        'messageCount': messages.length,
        'messageIdPrefix': _safeIdPrefix(messages.single.id),
        'pendingRelayEntries': pendingMessages.length,
      });
    } on _DuplicateDrainObservation {
      throw StateError('duplicate post-restore relay messages committed');
    } catch (_) {
      if (!DateTime.now().isBefore(deadline)) {
        throw TimeoutException(timeoutMessage);
      }
      consecutiveExactObservations = 0;
      await _delayWithinDeadline(deadline, timeoutMessage);
    }
  }

  throw TimeoutException(timeoutMessage);
}

Future<T> _runWithinDeadline<T>(
  DateTime deadline,
  Future<T> Function(Duration requestTimeout) operation,
  String timeoutMessage, {
  Duration? maxRequestDuration,
}) async {
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) throw TimeoutException(timeoutMessage);
  final requestTimeout =
      maxRequestDuration != null && remaining > maxRequestDuration
      ? maxRequestDuration
      : remaining;
  // The native timeout is per sequential relay candidate. Keep its request
  // budget small, but allow all candidates to finish within the action budget.
  return operation(requestTimeout).timeout(remaining);
}

Future<void> _delayWithinDeadline(
  DateTime deadline,
  String timeoutMessage,
) async {
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) throw TimeoutException(timeoutMessage);
  const interval = Duration(milliseconds: 250);
  await Future<void>.delayed(remaining < interval ? remaining : interval);
}

class _DuplicateDrainObservation implements Exception {
  const _DuplicateDrainObservation();
}

Future<Map<String, dynamic>> _observeReplayBeforeAck({
  required AndroidNotificationPayloadE2ERequest request,
  required P2PService p2pService,
  required Bridge bridge,
  required MessageRepository messageRepo,
  required AndroidNotificationE2EProgressWriter writeProgress,
  required Map<String, dynamic> Function(Map<String, Object?>) receipt,
}) async {
  final events = <Map<String, dynamic>>[];
  setE2EFlowEventSink(
    (payload) => events.add(Map<String, dynamic>.from(payload)),
  );
  try {
    await writeProgress(
      receipt(<String, Object?>{'status': 'armed', 'success': true}),
    );
    final deadline = DateTime.now().add(request.timeout);
    while (DateTime.now().isBefore(deadline)) {
      final messages = await _matchingMessages(request, messageRepo);
      final names = events
          .map((event) => event['event'])
          .whereType<String>()
          .toList(growable: false);
      final replayIndex = names.indexOf(
        'P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED',
      );
      final ackIndex = names.indexOf(
        'P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS',
      );
      if (messages.length == 1 && replayIndex >= 0 && ackIndex > replayIndex) {
        await p2pService.drainOfflineInbox();
        final afterSecondDrain = await _matchingMessages(request, messageRepo);
        final pending = await callP2PInboxRetrievePending(bridge);
        final pendingMessages =
            (pending['messages'] as List?) ?? const <Object?>[];
        if (afterSecondDrain.length != 1 ||
            pending['ok'] != true ||
            pendingMessages.isNotEmpty) {
          throw StateError('relay replay/ack did not remain exactly once');
        }
        final ackDetails = events[ackIndex]['details'];
        final acked = ackDetails is Map ? ackDetails['acked'] : null;
        if (acked is! num || acked < 1) {
          throw StateError('relay ACK did not report a purged entry');
        }
        return receipt(<String, Object?>{
          'status': 'complete',
          'success': true,
          'events': names,
          'messageCountAfterFirstDrain': messages.length,
          'messageCountAfterSecondDrain': afterSecondDrain.length,
          'messageIdPrefix': _safeIdPrefix(messages.single.id),
          'ackedEntries': acked.toInt(),
          'pendingRelayEntries': pendingMessages.length,
        });
      }
      if (messages.length > 1) {
        throw StateError('duplicate A6 message committed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('A6 replay/ack observation timed out');
  } finally {
    setE2EFlowEventSink(null);
  }
}

Future<Map<String, dynamic>> _observePostTap({
  required AndroidNotificationPayloadE2ERequest request,
  required MessageRepository messageRepo,
  required PushEnvelopeStagingStore pushEnvelopeStagingStore,
  required AndroidNotificationE2EProgressWriter writeProgress,
  required Map<String, dynamic> Function(Map<String, Object?>) receipt,
}) async {
  if (request.requireStagedBeforeTap) {
    final staged = await _matchingStaged(request, pushEnvelopeStagingStore);
    if (staged.length != 1) {
      throw StateError('warm tap did not observe one exact staged envelope');
    }
    await writeProgress(
      receipt(<String, Object?>{
        'status': 'armed',
        'success': true,
        'stagedEnvelopeObserved': true,
      }),
    );
  }

  final deadline = DateTime.now().add(request.timeout);
  while (DateTime.now().isBefore(deadline)) {
    final messages = await _matchingMessages(request, messageRepo);
    final staged = await _matchingStaged(request, pushEnvelopeStagingStore);
    if (messages.length == 1 && staged.isEmpty) {
      return receipt(<String, Object?>{
        'status': 'complete',
        'success': true,
        'messageCount': messages.length,
        'messageIdPrefix': _safeIdPrefix(messages.single.id),
        'stagedEnvelopeCleared': true,
      });
    }
    if (messages.length > 1 || staged.length > 1) {
      throw StateError('post-tap notification state duplicated');
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('post-tap message observation timed out');
}

Future<List<ConversationMessage>> _matchingMessages(
  AndroidNotificationPayloadE2ERequest request,
  MessageRepository messageRepo,
) async {
  final messages = await messageRepo.getMessagesForContact(
    request.contactPeerId!,
  );
  return messages
      .where(
        (message) =>
            message.isIncoming &&
            !message.isDeleted &&
            !message.isHidden &&
            message.transport != 'system' &&
            message.text == request.expectedText &&
            (request.expectedMessageId == null ||
                message.id == request.expectedMessageId),
      )
      .toList(growable: false);
}

Future<List<StagedPushEnvelope>> _matchingStaged(
  AndroidNotificationPayloadE2ERequest request,
  PushEnvelopeStagingStore store,
) async {
  final entries = await store.readAll();
  return entries
      .where(
        (entry) =>
            entry.kind == 'chat' &&
            entry.messageId == request.expectedMessageId,
      )
      .toList(growable: false);
}

String _safeIdPrefix(String value) =>
    value.length <= 8 ? value : value.substring(0, 8);
