import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/settings/application/download_profile_picture_use_case.dart';

/// Listener that monitors incoming profile_update messages and
/// automatically downloads updated profile pictures from contacts.
class ProfileUpdateListener {
  final Stream<ChatMessage> profileUpdateStream;
  final ContactRepository contactRepo;
  final Bridge bridge;

  StreamSubscription<ChatMessage>? _subscription;
  final _contactUpdatedController = StreamController<ContactModel>.broadcast();

  ProfileUpdateListener({
    required this.profileUpdateStream,
    required this.contactRepo,
    required this.bridge,
  });

  /// Stream of contacts whose profile picture was updated.
  Stream<ContactModel> get contactUpdatedStream =>
      _contactUpdatedController.stream;

  /// Starts listening for incoming profile update messages.
  void start() {
    if (_subscription != null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'PROFILE_UPDATE_LISTENER_START',
      details: {},
    );

    _subscription = profileUpdateStream.listen(
      _onMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PROFILE_UPDATE_LISTENER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'PROFILE_UPDATE_LISTENER_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  /// Stops listening.
  void stop() {
    emitFlowEvent(
      layer: 'FL',
      event: 'PROFILE_UPDATE_LISTENER_STOP',
      details: {},
    );

    _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _contactUpdatedController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    try {
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final payload = json['payload'] as Map<String, dynamic>?;
      if (payload == null) return;

      final peerId = payload['peerId'] as String?;
      final avatarVersion = payload['avatarVersion'] as String?;
      if (peerId == null || avatarVersion == null) return;

      // Look up the contact — skip if unknown sender
      final contact = await contactRepo.getContact(peerId);
      if (contact == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PROFILE_UPDATE_LISTENER_UNKNOWN_SENDER',
          details: {'peerId': peerId},
        );
        return;
      }

      // Skip if avatarVersion matches (already up to date)
      if (contact.avatarVersion == avatarVersion) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PROFILE_UPDATE_LISTENER_ALREADY_CURRENT',
          details: {'peerId': peerId, 'avatarVersion': avatarVersion},
        );
        return;
      }

      // Download the updated profile picture
      final updated = await downloadProfilePicture(
        bridge: bridge,
        contactRepo: contactRepo,
        ownerPeerId: peerId,
        avatarVersion: avatarVersion,
      );

      if (updated != null) {
        _contactUpdatedController.add(updated);

        emitFlowEvent(
          layer: 'FL',
          event: 'PROFILE_UPDATE_LISTENER_DOWNLOADED',
          details: {'peerId': peerId, 'avatarVersion': avatarVersion},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PROFILE_UPDATE_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
