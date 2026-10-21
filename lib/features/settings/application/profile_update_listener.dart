import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
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
  final DownloadProfilePictureFn downloadProfilePictureFn;
  final Duration retryDelay;
  final AccountMigrationNetworkGate accountMigrationNetworkGate;

  StreamSubscription<ChatMessage>? _subscription;
  Future<int>? _recoveryPass;
  bool _recoveryRequested = false;
  final _contactUpdatedController = StreamController<ContactModel>.broadcast();

  ProfileUpdateListener({
    required this.profileUpdateStream,
    required this.contactRepo,
    required this.bridge,
    this.retryDelay = const Duration(seconds: 5),
    this.accountMigrationNetworkGate = allowAccountMigrationNetworkSideEffects,
    DownloadProfilePictureFn? downloadProfilePictureFn,
  }) : downloadProfilePictureFn =
           downloadProfilePictureFn ?? downloadProfilePicture;

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
    unawaited(retryNow());
  }

  /// Startup, resume and relay readiness reuse this listener's recovery owner.
  Future<int> retryNow() {
    if (_subscription == null) return Future.value(0);
    if (_recoveryPass != null) {
      _recoveryRequested = true;
      return _recoveryPass!;
    }
    final pass = _recoverPendingDownloads();
    _recoveryPass = pass;
    return pass;
  }

  Future<int> _recoverPendingDownloads() async {
    var recoveredCount = 0;
    try {
      do {
        _recoveryRequested = false;
        if (!await accountMigrationNetworkGate(
          operation: 'pending_profile_picture_download_retry',
        )) {
          return recoveredCount;
        }
        if (_subscription == null) break;
        final updated = await retryPendingProfilePictureDownloads(
          bridge: bridge,
          contactRepo: contactRepo,
          downloadProfilePictureFn: downloadProfilePictureFn,
        );
        if (_subscription == null) break;
        for (final contact in updated) {
          _contactUpdatedController.add(contact);
          recoveredCount++;
        }
      } while (_recoveryRequested && _subscription != null);
      return recoveredCount;
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PROFILE_UPDATE_LISTENER_RECOVERY_ERROR',
        details: {'error': error.toString()},
      );
      return recoveredCount;
    } finally {
      _recoveryPass = null;
    }
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
    _recoveryRequested = false;
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

      final updated = await _downloadProfilePictureWithRetry(
        peerId: peerId,
        avatarVersion: avatarVersion,
      );

      if (updated != null) {
        _contactUpdatedController.add(updated);

        emitFlowEvent(
          layer: 'FL',
          event: 'PROFILE_UPDATE_LISTENER_DOWNLOADED',
          details: {'peerId': peerId, 'avatarVersion': avatarVersion},
        );
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'PROFILE_UPDATE_LISTENER_DOWNLOAD_FAILED',
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

  Future<ContactModel?> _downloadProfilePictureWithRetry({
    required String peerId,
    required String avatarVersion,
  }) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      final updated = await downloadProfilePictureFn(
        bridge: bridge,
        contactRepo: contactRepo,
        ownerPeerId: peerId,
        avatarVersion: avatarVersion,
      );
      if (updated != null) {
        return updated;
      }
      if (attempt == 1) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PROFILE_UPDATE_LISTENER_DOWNLOAD_RETRY',
          details: {
            'peerId': peerId,
            'avatarVersion': avatarVersion,
            'attempt': attempt + 1,
          },
        );
        await Future<void>.delayed(retryDelay);
      }
    }
    return null;
  }
}
