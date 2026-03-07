import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Listener service that monitors P2P messages for emoji reactions.
///
/// Subscribes to the typed reaction stream (from IncomingMessageRouter),
/// calls handleIncomingReaction, and broadcasts persisted
/// MessageReactions to the UI layer.
class ReactionListener {
  final Stream<ChatMessage> reactionStream;
  final ReactionRepository reactionRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final Future<String?> Function() getOwnMlKemSecretKey;

  StreamSubscription<ChatMessage>? _subscription;
  final _reactionController = StreamController<MessageReaction>.broadcast();
  final _reactionChangeController =
      StreamController<ReactionChange>.broadcast();

  ReactionListener({
    required this.reactionStream,
    required this.reactionRepo,
    required this.contactRepo,
    required this.bridge,
    required this.getOwnMlKemSecretKey,
  });

  /// Stream of incoming reactions for the UI.
  Stream<MessageReaction> get incomingReactionStream =>
      _reactionController.stream;

  /// Stream of incoming reaction changes, including removals.
  Stream<ReactionChange> get incomingReactionChangeStream =>
      _reactionChangeController.stream;

  /// Starts listening for incoming reactions.
  void start() {
    if (_subscription != null) return;

    emitFlowEvent(layer: 'FL', event: 'REACTION_LISTENER_START', details: {});

    _subscription = reactionStream.listen(
      _onMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'REACTION_LISTENER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'REACTION_LISTENER_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  /// Stops listening.
  void stop() {
    emitFlowEvent(layer: 'FL', event: 'REACTION_LISTENER_STOP', details: {});

    _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _reactionController.close();
    _reactionChangeController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    try {
      // Check if sender is blocked
      final senderPeerId = message.from;
      final senderContact = await contactRepo.getContact(senderPeerId);
      if (senderContact != null && senderContact.isBlocked) {
        emitFlowEvent(
          layer: 'FL',
          event: 'REACTION_LISTENER_BLOCKED_REJECT',
          details: {
            'from': senderPeerId.length > 10
                ? senderPeerId.substring(0, 10)
                : senderPeerId,
          },
        );
        return;
      }

      final ownSecretKey = await getOwnMlKemSecretKey();

      final (result, change) = await handleIncomingReaction(
        message: message,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: ownSecretKey,
      );

      if (result == HandleReactionResult.success && change != null) {
        if (change.type == ReactionChangeType.upserted &&
            change.reaction != null) {
          final reaction = change.reaction!;
          emitFlowEvent(
            layer: 'FL',
            event: 'REACTION_LISTENER_NEW_REACTION',
            details: {
              'id': reaction.id.length > 8
                  ? reaction.id.substring(0, 8)
                  : reaction.id,
              'emoji': reaction.emoji,
            },
          );
          _reactionController.add(reaction);
        }
        _reactionChangeController.add(change);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
