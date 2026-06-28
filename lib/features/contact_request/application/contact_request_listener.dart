import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_auto_add_rate_limiter.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/settings/application/download_profile_picture_use_case.dart';

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
  final DownloadProfilePictureFn downloadProfilePictureFn;
  final bool Function(String peerId)? shouldSuppressPresentationForPeerId;
  final AttemptSilentIntroContactRequestRecovery? attemptSilentIntroRecovery;
  final void Function(IntroductionModel intro)? emitRecoveredIntroductionStatus;

  /// 171: when wired (non-null), a v2 [HandleMessageResult.contactAutoAdded]
  /// result is added tap-free by invoking this — it adds the scanner as a
  /// contact AND fires the reciprocal request (acceptAndReciprocate). When
  /// null (e.g. under kE2ETestMode, where the smoke-runner's auto_accept poll
  /// owns acceptance), the listener falls back to the manual dialog, so no
  /// auto-add happens here.
  final Future<AcceptContactRequestResult> Function(String peerId)?
  autoAcceptAndReciprocate;

  StreamSubscription<ChatMessage>? _subscription;
  final _requestController = StreamController<ContactRequestModel>.broadcast();
  final _contactKeyUpdatedController =
      StreamController<ContactModel>.broadcast();
  final _autoAddedController = StreamController<ContactModel>.broadcast();
  final ReplayCache _replayCache;
  final ContactAutoAddRateLimiter _autoAddRateLimiter;

  ContactRequestListener({
    required this.contactRequestStream,
    required this.requestRepo,
    required this.contactRepo,
    required this.bridge,
    required this.getOwnPeerId,
    this.getOwnPrivateKey,
    DownloadProfilePictureFn? downloadProfilePictureFn,
    ReplayCache? replayCache,
    this.shouldSuppressPresentationForPeerId,
    this.attemptSilentIntroRecovery,
    this.emitRecoveredIntroductionStatus,
    this.autoAcceptAndReciprocate,
    ContactAutoAddRateLimiter? autoAddRateLimiter,
  }) : downloadProfilePictureFn =
           downloadProfilePictureFn ?? downloadProfilePicture,
       _replayCache = replayCache ?? ReplayCache(),
       _autoAddRateLimiter =
           autoAddRateLimiter ?? ContactAutoAddRateLimiter();

  /// Stream of new contact requests for the UI to listen to.
  Stream<ContactRequestModel> get requestStream => _requestController.stream;

  /// Stream of contacts whose ML-KEM key was updated from a verified payload.
  Stream<ContactModel> get contactKeyUpdatedStream =>
      _contactKeyUpdatedController.stream;

  /// 171: stream of contacts auto-added tap-free from a one-scan v2 request.
  /// The UI listens to surface a NON-MODAL "added X" notice (block/undo) and
  /// refresh the contact list.
  Stream<ContactModel> get autoAddedStream => _autoAddedController.stream;

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
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_REQUEST_LISTENER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_REQUEST_LISTENER_STREAM_DONE',
          details: {},
        );
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
    _autoAddedController.close();
  }

  void _prefetchRequestAvatar(ContactRequestModel request) {
    () async {
      try {
        await downloadProfilePictureFn(
          bridge: bridge,
          contactRepo: contactRepo,
          ownerPeerId: request.peerId,
          avatarVersion: 'initial',
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_REQUEST_PREFETCH_AVATAR_ERROR',
          details: {'peerId': request.peerId, 'error': e.toString()},
        );
      }
    }();
  }

  /// Live broadcast handler. Delegates to the shared [processIncomingMessage]
  /// and swallows thrown errors (a stream listener must not throw); the inbox
  /// replay path instead lets the throw propagate so it can retry.
  Future<void> _onMessage(ChatMessage message) async {
    try {
      await processIncomingMessage(message);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  /// Processes one incoming contact-request message end-to-end: handle +
  /// dialog/auto-accept routing + deferred-ack confirm, returning the
  /// [HandleMessageResult].
  ///
  /// Public so the relay-inbox replay path (P2PServiceImpl) runs the IDENTICAL
  /// logic for a cold receiver whose live broadcast had no subscriber — the
  /// dominant 171 bug (mirrors chat/intro listeners' `processIncomingMessage`).
  /// On the live path [_onMessage] swallows a thrown error; on the inbox path
  /// the caller maps a throw to a retryable replay so the request is not lost.
  Future<HandleMessageResult> processIncomingMessage(
    ChatMessage message,
  ) async {
    try {
      // Resolve own private key for v2 decryption
      final ownPrivateKey = await getOwnPrivateKey?.call();
      IntroContactRequestRecoveryResult? recoveryResult;

      final (result, request, keyUpdatePeerId) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: getOwnPeerId(),
        ownPrivateKey: ownPrivateKey,
        seenMessageIds: _replayCache.ids,
        attemptSilentIntroRecovery: attemptSilentIntroRecovery == null
            ? null
            : (verifiedRequest) async {
                final result = await attemptSilentIntroRecovery!(
                  verifiedRequest,
                );
                recoveryResult = result;
                return result;
              },
      );

      // For successful v2 handling, add msgId to replay cache. INCLUDES the
      // 171 contactAutoAdded result — INV-6: without it a redelivered msgId
      // (e.g. relay re-push) re-runs the auto-add + reciprocal (double add).
      if (result == HandleMessageResult.contactRequest ||
          result == HandleMessageResult.contactAutoAdded ||
          result == HandleMessageResult.contactKeyUpdated ||
          result == HandleMessageResult.silentIntroRecovered ||
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
        _routeToDialog(request);
      } else if (result == HandleMessageResult.contactAutoAdded &&
          request != null) {
        await _routeAutoAdd(request);
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
      } else if (result == HandleMessageResult.silentIntroRecovered) {
        final recoveredIntro = recoveryResult?.introduction;
        if (recoveredIntro != null) {
          emitRecoveredIntroductionStatus?.call(recoveredIntro);
        }

        if (recoveryResult?.contactKeyUpdated == true &&
            recoveryResult?.contact != null) {
          _contactKeyUpdatedController.add(recoveryResult!.contact!);
        }
      }

      // Deferred-ack confirm (171 + doc 118). ok=true for EVERY returned
      // result (incl. terminal rejects, which are correctly final) so a live
      // direct sender's Go node releases its ACK; fired AFTER any auto-add so
      // the happy path never 2s-times-out. A thrown error below sends ok=false
      // instead (Go withholds the ack -> sender inboxes -> retried). A null
      // confirmNonce (e.g. an inbox-replayed entry) is a no-op.
      await _maybeConfirmDirectNonce(message, ok: true);
      return result;
    } catch (e) {
      await _maybeConfirmDirectNonce(message, ok: false);
      rethrow;
    }
  }

  /// Routes a verified request to the manual-accept dialog (presentation
  /// gate-aware). Used for v1 requests, and as the fallback when auto-add is
  /// not wired or is rate-limited.
  void _routeToDialog(ContactRequestModel request) {
    final peerIdPrefix = request.peerId.length > 10
        ? request.peerId.substring(0, 10)
        : request.peerId;

    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_LISTENER_NEW_REQUEST',
      details: {'peerId': peerIdPrefix, 'username': request.username},
    );

    _prefetchRequestAvatar(request);
    final shouldSuppressPresentation =
        shouldSuppressPresentationForPeerId?.call(request.peerId) ?? false;
    if (shouldSuppressPresentation) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_LISTENER_PRESENTATION_SUPPRESSED',
        details: {'peerId': peerIdPrefix},
      );
    } else {
      _requestController.add(request);
    }
  }

  /// 171: adds the scanner tap-free (add + reciprocal) for an eligible v2
  /// request. Falls back to the manual dialog — never a silent drop — when
  /// auto-add is not wired (null callback, e.g. kE2ETestMode) or the global
  /// flood cap is reached.
  Future<void> _routeAutoAdd(ContactRequestModel request) async {
    final peerIdPrefix = request.peerId.length > 10
        ? request.peerId.substring(0, 10)
        : request.peerId;

    final accept = autoAcceptAndReciprocate;
    if (accept == null || !_autoAddRateLimiter.tryAcquire()) {
      emitFlowEvent(
        layer: 'FL',
        event: accept == null
            ? 'CONTACT_AUTO_ADD_NOT_WIRED_DIALOG_FALLBACK'
            : 'CONTACT_AUTO_ADD_RATE_LIMITED_DIALOG_FALLBACK',
        details: {'peerId': peerIdPrefix},
      );
      _routeToDialog(request);
      return;
    }

    // One add + one reciprocal. handleIncomingMessage already stored the
    // request pending, so the local accept can proceed.
    final acceptResult = await accept(request.peerId);
    if (acceptResult != AcceptContactRequestResult.success &&
        acceptResult != AcceptContactRequestResult.notPending) {
      // The local accept failed (e.g. a transient DB write error). Do NOT
      // silently lose the request — it is durably stored pending, so surface
      // it on the manual dialog as a graceful fallback (the user taps to
      // accept) instead of committing-and-deleting a never-added contact.
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_AUTO_ADD_ACCEPT_FAILED_DIALOG_FALLBACK',
        details: {'peerId': peerIdPrefix, 'result': acceptResult.name},
      );
      _routeToDialog(request);
      return;
    }

    // Tap-free success — emit the notice + refresh. Intentionally NO
    // _requestController.add (no dialog).
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_AUTO_ADDED',
      details: {'peerId': peerIdPrefix, 'username': request.username},
    );
    _prefetchRequestAvatar(request);

    // Surface the new contact for a non-modal notice + contact-list refresh.
    final added = await contactRepo.getContact(request.peerId);
    if (added != null && !_autoAddedController.isClosed) {
      _autoAddedController.add(added);
    }
  }

  /// Confirms the receiver-side terminal result of a deferred direct ack so
  /// the sender's Go node releases (ok=true) or withholds (ok=false) its ACK.
  /// No-op when the message carries no confirmNonce (e.g. relay-inbox replay).
  Future<void> _maybeConfirmDirectNonce(
    ChatMessage message, {
    required bool ok,
  }) async {
    final nonce = message.confirmNonce;
    if (nonce == null || nonce.isEmpty) {
      return;
    }
    try {
      await callP2PConfirmDirectMessage(bridge, nonce: nonce, ok: ok);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REQUEST_LISTENER_CONFIRM_NONCE_ERROR',
        details: {'nonce': nonce, 'error': e.toString(), 'ok': ok},
      );
    }
  }
}
