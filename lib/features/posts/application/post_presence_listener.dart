import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_presence_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/contact_presence_snapshot.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository.dart';

class PostPresenceListener {
  final Stream<ChatMessage> postPresenceStream;
  final ContactRepository contactRepo;
  final ContactPresenceSnapshotRepository snapshotRepo;

  StreamSubscription<ChatMessage>? _subscription;
  final StreamController<ContactPresenceSnapshot> _presenceController =
      StreamController<ContactPresenceSnapshot>.broadcast();

  PostPresenceListener({
    required this.postPresenceStream,
    required this.contactRepo,
    required this.snapshotRepo,
  });

  Stream<ContactPresenceSnapshot> get incomingPresenceStream =>
      _presenceController.stream;

  void start() {
    if (_subscription != null) {
      return;
    }
    _subscription = postPresenceStream.listen(_onMessage);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
    _presenceController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    try {
      final (result, snapshot) = await handleIncomingPostPresence(
        message: message,
        contactRepo: contactRepo,
        snapshotRepo: snapshotRepo,
      );
      if (result == HandleIncomingPostPresenceResult.snapshotUpdated &&
          snapshot != null) {
        _presenceController.add(snapshot);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_PRESENCE_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
