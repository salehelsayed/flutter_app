import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/introduction/application/handle_incoming_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/introduction_copy.dart';
import 'package:flutter_app/features/introduction/application/insert_intro_system_message.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

enum IntroductionMessageProcessState {
  stored,
  deferred,
  blockedSender,
  rejected,
  retryableError,
}

class IntroductionMessageProcessOutcome {
  final IntroductionMessageProcessState state;
  final IntroductionModel? introduction;
  final String reasonCode;
  final String? reasonDetail;

  const IntroductionMessageProcessOutcome({
    required this.state,
    required this.reasonCode,
    this.introduction,
    this.reasonDetail,
  });
}

/// Listener service that monitors P2P messages for introductions.
///
/// Subscribes to the typed introduction stream (from IncomingMessageRouter),
/// decrypts V2 envelopes or parses V1 payloads, and dispatches to
/// handleIncomingIntroduction. Broadcasts results to the UI layer via
/// two output streams.
class IntroductionListener {
  final Stream<ChatMessage> introductionStream;
  final IntroductionRepository introRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final Future<String?> Function() getOwnMlKemSecretKey;
  final Future<String?> Function() getOwnPeerId;
  final MessageRepository? messageRepo;
  final NotificationService? notificationService;

  StreamSubscription<ChatMessage>? _subscription;
  final _introReceivedController =
      StreamController<IntroductionModel>.broadcast();
  final _introStatusChangedController =
      StreamController<IntroductionModel>.broadcast();

  IntroductionListener({
    required this.introductionStream,
    required this.introRepo,
    required this.contactRepo,
    required this.bridge,
    required this.getOwnMlKemSecretKey,
    required this.getOwnPeerId,
    this.messageRepo,
    this.notificationService,
  });

  /// Stream of newly received introductions (action == 'send').
  Stream<IntroductionModel> get introReceivedStream =>
      _introReceivedController.stream;

  /// Stream of introduction status updates (action == 'accept' or 'pass').
  Stream<IntroductionModel> get introStatusChangedStream =>
      _introStatusChangedController.stream;

  /// Starts listening for incoming introduction messages.
  void start() {
    if (_subscription != null) return;

    emitFlowEvent(layer: 'FL', event: 'INTRO_LISTENER_START', details: {});

    _subscription = introductionStream.listen(
      _onMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'INTRO_LISTENER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'INTRO_LISTENER_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  /// Stops listening.
  void stop() {
    emitFlowEvent(layer: 'FL', event: 'INTRO_LISTENER_STOP', details: {});

    _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _introReceivedController.close();
    _introStatusChangedController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    await processIncomingMessage(message);
  }

  bool? _confirmationValueForState(IntroductionMessageProcessState state) {
    switch (state) {
      case IntroductionMessageProcessState.stored:
      case IntroductionMessageProcessState.deferred:
      case IntroductionMessageProcessState.blockedSender:
        return true;
      case IntroductionMessageProcessState.rejected:
      case IntroductionMessageProcessState.retryableError:
        return false;
    }
  }

  Future<void> _maybeConfirmDirectNonce(
    ChatMessage message,
    IntroductionMessageProcessState state,
  ) async {
    final nonce = message.confirmNonce;
    final value = _confirmationValueForState(state);
    if (nonce == null || nonce.isEmpty || value == null) {
      return;
    }

    try {
      await callP2PConfirmDirectMessage(bridge, nonce: nonce, ok: value);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INTRO_LISTENER_CONFIRM_NONCE_ERROR',
        details: {'nonce': nonce, 'error': e.toString(), 'ok': value},
      );
    }
  }

  Future<IntroductionMessageProcessOutcome> processIncomingMessage(
    ChatMessage message,
  ) async {
    Future<IntroductionMessageProcessOutcome> finish(
      IntroductionMessageProcessOutcome outcome,
    ) async {
      await _maybeConfirmDirectNonce(message, outcome.state);
      return outcome;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'INTRO_LISTENER_MESSAGE_RECEIVED',
      details: {
        'from': message.from.length > 10
            ? message.from.substring(0, 10)
            : message.from,
        'contentLength': message.content.length,
      },
    );

    try {
      // 1. Try v2 decryption, fall back to v1 parsing
      String? innerJson;
      final envelope = IntroductionPayload.parseEncryptedEnvelope(
        message.content,
      );

      if (envelope != null) {
        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final ownSecretKey = await getOwnMlKemSecretKey();
        if (ownSecretKey != null) {
          final result = await callDecryptMessage(
            bridge: bridge,
            ownMlKemSecretKey: ownSecretKey,
            kem: encrypted['kem'] as String,
            ciphertext: encrypted['ciphertext'] as String,
            nonce: encrypted['nonce'] as String,
          );
          if (result['ok'] == true) {
            innerJson = result['plaintext'] as String;
          } else {
            emitFlowEvent(
              layer: 'FL',
              event: 'INTRO_LISTENER_DECRYPT_FAILED',
              details: {'errorCode': result['errorCode'] ?? 'unknown'},
            );
            return finish(
              const IntroductionMessageProcessOutcome(
                state: IntroductionMessageProcessState.rejected,
                reasonCode: 'decryption_failed',
              ),
            );
          }
        } else {
          emitFlowEvent(
            layer: 'FL',
            event: 'INTRO_LISTENER_NO_SECRET_KEY',
            details: {},
          );
          return finish(
            const IntroductionMessageProcessOutcome(
              state: IntroductionMessageProcessState.retryableError,
              reasonCode: 'missing_mlkem_secret',
            ),
          );
        }
      } else {
        // Try v1 envelope
        final parsed = IntroductionPayload.fromJson(message.content);
        if (parsed != null) {
          innerJson = parsed.toInnerJson();
        }
      }

      if (innerJson == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'INTRO_LISTENER_PARSE_FAILED',
          details: {'contentLength': message.content.length},
        );
        return finish(
          const IntroductionMessageProcessOutcome(
            state: IntroductionMessageProcessState.rejected,
            reasonCode: 'parse_failed',
          ),
        );
      }

      // 3. Parse IntroductionPayload from inner JSON
      final payload = IntroductionPayload.fromInnerJson(innerJson);
      if (payload == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'INTRO_LISTENER_INVALID_PAYLOAD',
          details: {},
        );
        return finish(
          const IntroductionMessageProcessOutcome(
            state: IntroductionMessageProcessState.rejected,
            reasonCode: 'invalid_payload',
          ),
        );
      }

      // 4. Block check: only reject new introduction offers from blocked
      //    contacts. Accept/pass messages must always pass through — they
      //    complete the mutual-acceptance handshake and are not user content.
      if (payload.action == 'send') {
        final senderPeerId = message.from;
        final senderContact = await contactRepo.getContact(senderPeerId);
        if (senderContact != null && senderContact.isBlocked) {
          emitFlowEvent(
            layer: 'FL',
            event: 'INTRO_LISTENER_BLOCKED_REJECT',
            details: {
              'from': senderPeerId.length > 10
                  ? senderPeerId.substring(0, 10)
                  : senderPeerId,
            },
          );
          return finish(
            const IntroductionMessageProcessOutcome(
              state: IntroductionMessageProcessState.blockedSender,
              reasonCode: 'blocked_sender',
            ),
          );
        }
      }

      // 5. Call handleIncomingIntroduction
      final ownPeerId = await getOwnPeerId();
      if (ownPeerId == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'INTRO_LISTENER_NO_OWN_PEER_ID',
          details: {},
        );
        return finish(
          const IntroductionMessageProcessOutcome(
            state: IntroductionMessageProcessState.retryableError,
            reasonCode: 'missing_own_peer_id',
          ),
        );
      }

      final (result, model) = await handleIncomingIntroduction(
        payload: payload,
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
        messageRepo: messageRepo,
        bridge: bridge,
      );

      if (result == HandleIntroductionResult.success && model != null) {
        // 5. Broadcast to appropriate stream based on action
        if (payload.action == 'send') {
          _introReceivedController.add(model);

          // Insert system message
          if (messageRepo != null) {
            final text = formatIncomingIntroductionMessage(
              introduction: model,
              ownPeerId: ownPeerId,
            );
            await insertIntroSystemMessage(
              messageRepo: messageRepo!,
              contactPeerId: model.introducerId,
              text: text,
              ownPeerId: ownPeerId,
            );
          }

          // Show local notification for new introduction
          if (notificationService != null) {
            final body = formatIncomingIntroductionMessage(
              introduction: model,
              ownPeerId: ownPeerId,
            );
            await notificationService!.showNotification(
              title: 'New Introduction',
              body: body,
              payload: 'intros',
            );
          }

          emitFlowEvent(
            layer: 'FL',
            event: 'INTRO_LISTENER_NEW_INTRO',
            details: {'introductionId': model.id},
          );
        } else if (payload.action == 'accept' || payload.action == 'pass') {
          _introStatusChangedController.add(model);

          // Show local notification on mutual acceptance
          if (payload.action == 'accept' &&
              model.status == IntroductionOverallStatus.mutualAccepted &&
              notificationService != null) {
            final responderName = payload.responderUsername ?? 'Someone';
            await notificationService!.showNotification(
              title: 'New Connection',
              body: '$responderName also accepted! You\'re now connected.',
              payload: 'intros',
            );
          }

          emitFlowEvent(
            layer: 'FL',
            event: 'INTRO_LISTENER_STATUS_CHANGED',
            details: {'introductionId': model.id, 'action': payload.action},
          );
        }

        return finish(
          IntroductionMessageProcessOutcome(
            state: IntroductionMessageProcessState.stored,
            reasonCode: 'stored',
            introduction: model,
          ),
        );
      }

      if (result == HandleIntroductionResult.alreadyExists) {
        if (model != null &&
            (payload.action == 'accept' || payload.action == 'pass')) {
          _introStatusChangedController.add(model);

          emitFlowEvent(
            layer: 'FL',
            event: 'INTRO_LISTENER_STATUS_REPLAY_IGNORED',
            details: {'introductionId': model.id, 'action': payload.action},
          );
        }
        return finish(
          IntroductionMessageProcessOutcome(
            state: IntroductionMessageProcessState.stored,
            reasonCode: 'already_exists',
            introduction: model,
          ),
        );
      }

      if (result == HandleIntroductionResult.deferred) {
        return finish(
          const IntroductionMessageProcessOutcome(
            state: IntroductionMessageProcessState.deferred,
            reasonCode: 'response_deferred',
          ),
        );
      }

      if (result == HandleIntroductionResult.rejected ||
          result == HandleIntroductionResult.blocked) {
        return finish(
          const IntroductionMessageProcessOutcome(
            state: IntroductionMessageProcessState.rejected,
            reasonCode: 'handler_rejected',
          ),
        );
      }

      return finish(
        const IntroductionMessageProcessOutcome(
          state: IntroductionMessageProcessState.retryableError,
          reasonCode: 'handler_error',
        ),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INTRO_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
      return finish(
        IntroductionMessageProcessOutcome(
          state: IntroductionMessageProcessState.retryableError,
          reasonCode: 'listener_error',
          reasonDetail: e.toString(),
        ),
      );
    }
  }
}
