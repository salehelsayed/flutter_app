import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Service that automatically retries failed outgoing messages
/// when the P2P node reconnects.
///
/// Subscribes to [P2PService.stateStream] and detects transitions
/// to online state (isStarted && circuitAddresses.isNotEmpty).
/// Debounces by 5 seconds to avoid retrying during rapid state changes.
class PendingMessageRetrier {
  final P2PService p2pService;
  final MessageRepository messageRepo;
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final MediaAttachmentRepository? mediaAttachmentRepo;

  // Injectable recovery callbacks for correct ordering
  final Future<int> Function()? recoverStuckSendingMessagesFn; // Part A
  final Future<int> Function()? retryIncompleteUploadsFn; // Part G -- NEW

  StreamSubscription? _stateSubscription;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  bool _wasOnline = false;
  bool _isRetrying = false;

  PendingMessageRetrier({
    required this.p2pService,
    required this.messageRepo,
    required this.identityRepo,
    required this.contactRepo,
    required this.bridge,
    this.mediaAttachmentRepo,
    this.recoverStuckSendingMessagesFn, // Part A
    this.retryIncompleteUploadsFn, // Part G -- NEW
  });

  /// Starts listening for state transitions.
  void start() {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_RETRIER_START',
      details: {},
    );

    _wasOnline = _isOnline(p2pService.currentState);

    _stateSubscription = p2pService.stateStream.listen((state) {
      final nowOnline = _isOnline(state);

      if (nowOnline && !_wasOnline) {
        // Transition to online — schedule retry with debounce
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(seconds: 5), _retryIfNeeded);
        // Periodic retry every 5 minutes while online
        _periodicTimer?.cancel();
        _periodicTimer = Timer.periodic(
          const Duration(minutes: 5),
          (_) => _retryIfNeeded(),
        );
      } else if (!nowOnline && _wasOnline) {
        // Went offline — cancel periodic
        _periodicTimer?.cancel();
        _periodicTimer = null;
      }

      _wasOnline = nowOnline;
    });

    // If already online when start() is called, schedule an initial sweep.
    // Handles cold-start where the Go node reports already-running.
    if (_wasOnline) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 5), _retryIfNeeded);
      _periodicTimer?.cancel();
      _periodicTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => _retryIfNeeded(),
      );
    }
  }

  bool _isOnline(dynamic state) {
    return state.isStarted && (state.circuitAddresses as List).isNotEmpty;
  }

  Future<void> _retryIfNeeded() async {
    if (_isRetrying) return;
    _isRetrying = true;

    try {
      // ORDERING CONTRACT (matches handleAppResumed Step 8):
      //   1. recoverStuckSendingMessages  -- 'sending' -> 'failed'
      //   2. retryIncompleteUploads       -- re-upload 'upload_pending' attachments
      //   3. retryFailedMessages          -- retry 'failed' messages
      //   4. retryUnackedMessages         -- retry 'sent' but unacked

      // Step 1: Recover stuck sending messages
      if (recoverStuckSendingMessagesFn != null) {
        try {
          final count = await recoverStuckSendingMessagesFn!();
          if (count > 0) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_RECOVERED_STUCK',
              details: {'count': count},
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_RECOVER_STUCK_ERROR',
            details: {'error': e.toString()},
          );
        }
      }

      // Step 2: Re-upload incomplete attachments (Part G)
      if (retryIncompleteUploadsFn != null) {
        try {
          final count = await retryIncompleteUploadsFn!();
          if (count > 0) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_INCOMPLETE_UPLOADS_RETRIED',
              details: {'count': count},
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_INCOMPLETE_UPLOAD_ERROR',
            details: {'error': e.toString()},
          );
          // Non-fatal: continue to retryFailedMessages
        }
      }

      // Step 3: Retry failed messages
      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      if (count > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_RETRIED',
          details: {'count': count},
        );
      }

      // Step 4: Retry unacked messages
      final unackedCount = await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );

      if (unackedCount > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_UNACKED_RETRIED',
          details: {'count': unackedCount},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_ERROR',
        details: {'error': e.toString()},
      );
    } finally {
      _isRetrying = false;
    }
  }

  /// Stops listening and cleans up resources.
  void dispose() {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_RETRIER_DISPOSE',
      details: {},
    );

    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _stateSubscription?.cancel();
    _stateSubscription = null;
  }
}
