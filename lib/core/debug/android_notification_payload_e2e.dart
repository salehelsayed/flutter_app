import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
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
typedef AndroidNotificationFcmTokenInvalidator = Future<void> Function();

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
  AndroidNotificationFcmTokenInvalidator? fcmTokenInvalidator,
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
      await _unregisterPushTokenWithinDeadline(
        request: request,
        bridge: bridge,
      );
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

    case androidNotificationTransportReadyAction:
      return _awaitNotificationTransportReady(
        request: request,
        p2pService: p2pService,
        receipt: receipt,
      );

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

    case androidNotificationDeletePushTokenAction:
      return _rotatePushToken(
        request: request,
        tokenProvider: fcmTokenProvider ?? FirebaseMessaging.instance.getToken,
        tokenInvalidator:
            fcmTokenInvalidator ?? FirebaseMessaging.instance.deleteToken,
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

Future<Map<String, dynamic>> _awaitNotificationTransportReady({
  required AndroidNotificationPayloadE2ERequest request,
  required P2PService p2pService,
  required Map<String, dynamic> Function(Map<String, Object?>) receipt,
}) async {
  const timeoutMessage = 'notification transport readiness timed out';
  final deadline = DateTime.now().add(request.timeout);
  var consecutiveReadySamples = 0;

  while (DateTime.now().isBefore(deadline)) {
    try {
      await _runWithinDeadline<void>(
        deadline,
        (_) => p2pService.performImmediateHealthCheck(),
        timeoutMessage,
        maxRequestDuration: const Duration(seconds: 10),
      );
    } catch (_) {
      consecutiveReadySamples = 0;
    }

    final state = p2pService.currentState;
    final ready = state.isStarted && state.usabilityReady && state.relayReady;
    consecutiveReadySamples = ready ? consecutiveReadySamples + 1 : 0;
    if (consecutiveReadySamples >= 2) {
      return receipt(<String, Object?>{
        'status': 'complete',
        'success': true,
        'transportReady': true,
        'nodeStarted': state.isStarted,
        'sendCapabilityReady': state.sendCapabilityReady,
        'inboxCapabilityReady': state.inboxCapabilityReady,
        'relayReady': state.relayReady,
      });
    }

    await _delayWithinDeadline(deadline, timeoutMessage);
  }

  throw TimeoutException(timeoutMessage);
}

Future<void> _unregisterPushTokenWithinDeadline({
  required AndroidNotificationPayloadE2ERequest request,
  required Bridge bridge,
}) async {
  const timeoutMessage = 'production relay push unregistration timed out';
  final deadline = DateTime.now().add(request.timeout);

  while (DateTime.now().isBefore(deadline)) {
    try {
      final response = await _runWithinDeadline<Map<String, dynamic>>(
        deadline,
        (_) => callP2PInboxUnregisterToken(bridge),
        timeoutMessage,
        maxRequestDuration: const Duration(seconds: 10),
      );
      if (response['ok'] == true && response['unregistered'] == true) {
        return;
      }
    } on Object {
      // A newly relaunched receiver can observe the relay between local node
      // startup and route readiness. Unregister is idempotent, so retry the
      // production command inside the request's existing bounded budget.
    }

    if (!DateTime.now().isBefore(deadline)) break;
    await _delayWithinDeadline(deadline, timeoutMessage);
  }

  throw TimeoutException(timeoutMessage);
}

/// Deletes the installed app's FCM token and waits for the provider to mint a
/// DIFFERENT one.
///
/// `deleteToken` on its own is not proof of rotation — the next `getToken` can
/// legitimately return the same value — so the action polls until the token
/// hash actually changes and fails closed if it never does. Only hash
/// PREFIXES leave this function; the raw provider token never appears in a
/// receipt.
Future<Map<String, dynamic>> _rotatePushToken({
  required AndroidNotificationPayloadE2ERequest request,
  required AndroidNotificationFcmTokenProvider tokenProvider,
  required AndroidNotificationFcmTokenInvalidator tokenInvalidator,
  required Map<String, dynamic> Function(Map<String, Object?>) receipt,
}) async {
  final before = (await tokenProvider())?.trim();
  if (before == null || before.isEmpty) {
    throw StateError('production FCM token unavailable before rotation');
  }

  await tokenInvalidator();

  String? rotated;
  final deadline = DateTime.now().add(request.timeout);
  while (DateTime.now().isBefore(deadline)) {
    final candidate = (await tokenProvider())?.trim();
    if (candidate != null && candidate.isNotEmpty && candidate != before) {
      rotated = candidate;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  if (rotated == null) {
    throw StateError('production FCM token did not rotate after deletion');
  }

  return receipt(<String, Object?>{
    'status': 'complete',
    'success': true,
    'tokenRotated': true,
    'tokenHashPrefixBefore': _tokenHashPrefix(before),
    'tokenHashPrefixAfter': _tokenHashPrefix(rotated),
  });
}

/// Hash prefix wide enough to distinguish two tokens, narrow enough that the
/// receipt carries no recoverable provider material.
String _tokenHashPrefix(String token) =>
    sha256.convert(utf8.encode(token)).toString().substring(0, 12);

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
        if (afterSecondDrain.length != 1) {
          throw StateError('relay replay/ack did not remain exactly once');
        }
        final pending = await callP2PInboxRetrievePending(bridge);
        final pendingMessages =
            (pending['messages'] as List?) ?? const <Object?>[];
        if (pending['ok'] != true || pendingMessages.isNotEmpty) {
          // Neither reading is a custody verdict, and this is the same
          // contract `_observeDrainConvergence` already applies to these two
          // fields (`:243-250`, where both are convergence inputs, not
          // throws). `ok != true` is libp2p dial backoff moments after the
          // receiver's radio returns. A NON-EMPTY list is the relay still
          // re-serving an entry whose ACK has not landed yet: the relay keeps
          // offering an entry until it is purged, so a single sample taken
          // inside a replay window reads non-empty for a delivery that is
          // converging exactly once. Measured on device 2026-08-19 — two
          // `P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS {requested:1,acked:1}`
          // 0.8 s apart against ONE `INBOX_STAGED_CHAT_COMMITTED` — which
          // failed A6 as a relay-custody defect on a correct delivery.
          // Duplicate COMMITS above still fail closed on the first sample,
          // and the action deadline still enforces convergence.
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
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
