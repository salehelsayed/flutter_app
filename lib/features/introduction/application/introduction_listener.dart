import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/introduction/application/handle_incoming_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/insert_intro_system_message.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

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

    emitFlowEvent(
      layer: 'FL',
      event: 'INTRO_LISTENER_START',
      details: {},
    );

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
    emitFlowEvent(
      layer: 'FL',
      event: 'INTRO_LISTENER_STOP',
      details: {},
    );

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
      // 1. Check if sender is blocked
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
        return;
      }

      // 2. Try v2 decryption, fall back to v1 parsing
      String? innerJson;
      final envelope =
          IntroductionPayload.parseEncryptedEnvelope(message.content);

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
              details: {
                'errorCode': result['errorCode'] ?? 'unknown',
              },
            );
            return;
          }
        } else {
          emitFlowEvent(
            layer: 'FL',
            event: 'INTRO_LISTENER_NO_SECRET_KEY',
            details: {},
          );
          return;
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
        return;
      }

      // 3. Parse IntroductionPayload from inner JSON
      final payload = IntroductionPayload.fromInnerJson(innerJson);
      if (payload == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'INTRO_LISTENER_INVALID_PAYLOAD',
          details: {},
        );
        return;
      }

      // 4. Call handleIncomingIntroduction
      final ownPeerId = await getOwnPeerId();
      if (ownPeerId == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'INTRO_LISTENER_NO_OWN_PEER_ID',
          details: {},
        );
        return;
      }

      final (result, model) = await handleIncomingIntroduction(
        payload: payload,
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
        messageRepo: messageRepo,
      );

      if (result == HandleIntroductionResult.success && model != null) {
        // 5. Broadcast to appropriate stream based on action
        if (payload.action == 'send') {
          _introReceivedController.add(model);

          // Insert system message: "[introducer] introduced [introduced] to you"
          if (messageRepo != null) {
            final introducerName =
                model.introducerUsername ?? 'Someone';
            final introducedName =
                model.introducedUsername ?? 'someone';
            await insertIntroSystemMessage(
              messageRepo: messageRepo!,
              contactPeerId: model.introducerId,
              text: '$introducerName introduced $introducedName to you',
              ownPeerId: ownPeerId,
            );
          }

          // Show local notification for new introduction
          if (notificationService != null) {
            final introducerName =
                payload.introducerUsername ?? 'Someone';
            await notificationService!.showNotification(
              title: 'New Introduction',
              body:
                  '$introducerName introduced you to ${payload.introducedUsername ?? "someone"}',
              payload: 'intros',
            );
          }

          emitFlowEvent(
            layer: 'FL',
            event: 'INTRO_LISTENER_NEW_INTRO',
            details: {'introductionId': model.id},
          );
        } else if (payload.action == 'accept' ||
            payload.action == 'pass') {
          _introStatusChangedController.add(model);

          // Show local notification on mutual acceptance
          if (payload.action == 'accept' &&
              model.status == IntroductionOverallStatus.mutualAccepted &&
              notificationService != null) {
            final responderName =
                payload.responderUsername ?? 'Someone';
            await notificationService!.showNotification(
              title: 'New Connection',
              body:
                  '$responderName also accepted! You\'re now connected.',
              payload: 'intros',
            );
          }

          emitFlowEvent(
            layer: 'FL',
            event: 'INTRO_LISTENER_STATUS_CHANGED',
            details: {
              'introductionId': model.id,
              'action': payload.action,
            },
          );
        }
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INTRO_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
