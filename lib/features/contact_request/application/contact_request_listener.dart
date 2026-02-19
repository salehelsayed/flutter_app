import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Listener service that monitors P2P messages for contact requests.
///
/// Subscribes to a typed contact request stream (from IncomingMessageRouter)
/// and broadcasts new contact requests to the UI layer for display.
class ContactRequestListener {
  final Stream<ChatMessage> contactRequestStream;
  final ContactRequestRepository requestRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final String Function() getOwnPeerId;

  StreamSubscription<ChatMessage>? _subscription;
  final _requestController = StreamController<ContactRequestModel>.broadcast();

  ContactRequestListener({
    required this.contactRequestStream,
    required this.requestRepo,
    required this.contactRepo,
    required this.bridge,
    required this.getOwnPeerId,
  });

  /// Stream of new contact requests for the UI to listen to.
  Stream<ContactRequestModel> get requestStream => _requestController.stream;

  /// Starts listening for incoming P2P messages.
  void start() {
    if (_subscription != null) {
      return;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_LISTENER_START',
      details: {},
    );

    _subscription = contactRequestStream.listen(
      _onMessage,
      onError: (error) {
        emitFlowEvent(layer: 'FL', event: 'CONTACT_REQUEST_LISTENER_STREAM_ERROR', details: {'error': error.toString()});
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'CONTACT_REQUEST_LISTENER_STREAM_DONE', details: {});
      },
    );
  }

  /// Stops listening and cleans up resources.
  void stop() {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_LISTENER_STOP',
      details: {},
    );

    _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _requestController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    try {
      final (result, request) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: getOwnPeerId(),
      );

      if (result == HandleMessageResult.contactRequest && request != null) {
        final peerIdPrefix = request.peerId.length > 10
            ? request.peerId.substring(0, 10)
            : request.peerId;

        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_REQUEST_LISTENER_NEW_REQUEST',
          details: {
            'peerId': peerIdPrefix,
            'username': request.username,
          },
        );

        _requestController.add(request);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
