import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Bounded replay cache that stores message IDs with timestamps.
///
/// Evicts entries older than [ttl] or beyond [maxSize] (LRU order).
/// Prevents unbounded memory growth from a flood of v2 messages.
class ReplayCache {
  final int maxSize;
  final Duration ttl;
  final LinkedHashMap<String, DateTime> _entries = LinkedHashMap();

  ReplayCache({this.maxSize = 1000, this.ttl = const Duration(hours: 25)});

  /// Returns the set of currently cached message IDs.
  Set<String> get ids => _entries.keys.toSet();

  /// Returns the current number of entries.
  int get length => _entries.length;

  /// Adds a message ID to the cache, evicting stale/overflow entries.
  void add(String msgId) {
    _evictStale();
    // If already present, move to end (most recent)
    _entries.remove(msgId);
    _entries[msgId] = DateTime.now().toUtc();
    // Evict oldest if over max size
    while (_entries.length > maxSize) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Checks if a message ID is in the cache.
  bool contains(String msgId) {
    _evictStale();
    return _entries.containsKey(msgId);
  }

  void _evictStale() {
    final cutoff = DateTime.now().toUtc().subtract(ttl);
    _entries.removeWhere((_, ts) => ts.isBefore(cutoff));
  }
}

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
  final Future<String?> Function()? getOwnPrivateKey;

  StreamSubscription<ChatMessage>? _subscription;
  final _requestController = StreamController<ContactRequestModel>.broadcast();
  final _contactKeyUpdatedController = StreamController<ContactModel>.broadcast();
  final ReplayCache _replayCache;

  ContactRequestListener({
    required this.contactRequestStream,
    required this.requestRepo,
    required this.contactRepo,
    required this.bridge,
    required this.getOwnPeerId,
    this.getOwnPrivateKey,
    ReplayCache? replayCache,
  }) : _replayCache = replayCache ?? ReplayCache();

  /// Stream of new contact requests for the UI to listen to.
  Stream<ContactRequestModel> get requestStream => _requestController.stream;

  /// Stream of contacts whose ML-KEM key was updated from a verified payload.
  Stream<ContactModel> get contactKeyUpdatedStream =>
      _contactKeyUpdatedController.stream;

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
    _contactKeyUpdatedController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    try {
      // Resolve own private key for v2 decryption
      final ownPrivateKey = await getOwnPrivateKey?.call();

      final (result, request, keyUpdatePeerId) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: getOwnPeerId(),
        ownPrivateKey: ownPrivateKey,
        seenMessageIds: _replayCache.ids,
      );

      // For successful v2 handling, add msgId to replay cache
      if (result == HandleMessageResult.contactRequest ||
          result == HandleMessageResult.contactKeyUpdated ||
          result == HandleMessageResult.duplicateRequest ||
          result == HandleMessageResult.alreadyContact) {
        // Extract msgId from v2 messages
        try {
          final json = jsonDecode(message.content) as Map<String, dynamic>;
          if (json['version'] == '2') {
            final msgId = json['msgId'] as String?;
            if (msgId != null) {
              _replayCache.add(msgId);
            }
          }
        } catch (_) {}
      }

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
      } else if (result == HandleMessageResult.contactKeyUpdated &&
          keyUpdatePeerId != null) {
        final peerPrefix = keyUpdatePeerId.length > 10
            ? keyUpdatePeerId.substring(0, 10)
            : keyUpdatePeerId;

        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_REQUEST_LISTENER_KEY_UPDATED',
          details: {'peerId': peerPrefix},
        );

        // Broadcast the updated contact so UI screens refresh their
        // cached copy (e.g. ConversationWired picks up the new ML-KEM key).
        final updatedContact = await contactRepo.getContact(keyUpdatePeerId);
        if (updatedContact != null) {
          _contactKeyUpdatedController.add(updatedContact);
        }
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
