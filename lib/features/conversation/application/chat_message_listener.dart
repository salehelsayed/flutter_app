import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/direct_conversation_notification_snapshot.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:flutter_app/features/settings/application/download_profile_picture_use_case.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';

enum ChatMessageProcessState {
  stored,
  blockedSender,
  notChatMessage,
  missingMlKemSecret,
  decryptionFailed,
  decryptionDeferred,
  unknownSender,
  duplicate,

  /// Plan 354: a durable same-author private terminal parent already owned
  /// this target. The event is durably settled and its initial receipt was
  /// emitted, but nothing was published — and unlike [duplicate] this must
  /// NEVER trigger the global message-display retry, which would re-stage a
  /// notification for content the receiver has already consumed or removed.
  durablySuperseded,
  ignoredEdit,
  editMissingOriginal,

  /// 361: an authenticated linked transport carried a modality the restricted
  /// linked role does not support. Terminal rejection: the staged envelope is
  /// durably rejected/quarantined with zero apply/receipt/publication/
  /// notification and must never redrive the display retry.
  linkedModalityRefused,
  accountMigrationBlocked,
  error,
}

class ChatMessageProcessOutcome {
  final ChatMessageProcessState state;
  final ConversationMessage? conversationMessage;
  final ContactModel? updatedContact;
  final String? reasonDetail;

  /// 172 TC-03: true only when a [ChatMessageProcessState.duplicate] outcome
  /// was produced by the real handler, which verifies a durable prior row
  /// (same-id / dedupKey / content query) before returning duplicate. The
  /// disposition mapper keeps `duplicate` terminal ONLY under this flag; an
  /// unverified duplicate claim (synthetic producers, future drift) stays
  /// recoverable instead of becoming silent post-ACK loss.
  final bool duplicatePriorPersisted;

  const ChatMessageProcessOutcome({
    required this.state,
    this.conversationMessage,
    this.updatedContact,
    this.reasonDetail,
    this.duplicatePriorPersisted = false,
  });
}

/// Listener service that monitors P2P messages for chat messages.
///
/// Subscribes to a typed chat message stream (from IncomingMessageRouter),
/// calls handleIncomingChatMessage, and broadcasts persisted
/// ConversationMessages to the UI layer.
class ChatMessageListener {
  final Stream<ChatMessage> chatMessageStream;
  final MessageRepository messageRepo;
  final ContactRepository contactRepo;

  /// 361: shared physical->logical reverse authority (null = incumbent).
  final DirectTransportAuthorityResolver? transportAuthority;
  final Bridge? bridge;
  final Future<String?> Function()? getOwnMlKemSecretKey;

  /// Resolves the ring of PRIOR ML-KEM secrets (newest first) used as
  /// decrypt fallbacks after a same-device key regeneration (P0-B).
  final Future<List<String>> Function()? getOwnMlKemSecretKeyRing;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final MediaFileManager? mediaFileManager;
  final NotificationService? notificationService;
  final AppVisibilitySuppressionReader? appVisibility;
  // 118 Phase 4: shared per-conversation tone debounce (direct + group keys are
  // disjoint, so one tracker serves both listeners).
  final NotificationToneTracker? notificationToneTracker;
  final Future<DurableNotificationToneLease> Function()
  _durableNotificationCoordinatorResolver;
  final DownloadProfilePictureFn? downloadProfilePictureFn;
  final RecentRemoteNotificationGate? remoteNotificationGate;
  final Duration backgroundNotificationDuplicateGuardDelay;
  final AccountMigrationNetworkGate accountMigrationNetworkGate;
  final StageDirectMessageNotificationDisplayCustody?
  stageNotificationDisplayCustody;
  final PromoteDirectMessageNotificationDisplayCustody?
  promoteNotificationDisplayCustody;
  final Future<void> Function()? retryNotificationDisplays;

  /// 229: user auto-download policy consulted immediately before every
  /// automatic direct media transfer. Null preserves HEAD behavior (allowed);
  /// a denied attachment stays `pending` with zero transfer and remains
  /// reachable through the explicit user retry affordance.
  final MediaAutoDownloadDecider? autoDownloadDecider;

  /// 115 P2: optional delivery-receipt sender. When set, relay-inbox
  /// arrivals (per the shared origin contract) confirm durable persist back
  /// to the message sender. Live direct/LAN messages never mint receipts —
  /// their own acks carry the confirmation.
  final Future<void> Function({
    required String contactPeerId,
    required List<String> messageIds,
    Map<String, String>? mutationEventIds,
  })?
  sendDeliveryReceipt;

  StreamSubscription<ChatMessage>? _subscription;
  Future<DurableNotificationToneLease?>? _durableNotificationCoordinatorFuture;
  final _messageController = StreamController<ConversationMessage>.broadcast();
  final _contactUpdatedController = StreamController<ContactModel>.broadcast();

  ChatMessageListener({
    required this.chatMessageStream,
    required this.messageRepo,
    required this.contactRepo,
    this.transportAuthority,
    this.bridge,
    this.getOwnMlKemSecretKey,
    this.getOwnMlKemSecretKeyRing,
    this.mediaAttachmentRepo,
    this.mediaFileManager,
    this.notificationService,
    this.appVisibility,
    this.notificationToneTracker,
    Future<DurableNotificationToneLease> Function()?
    durableNotificationCoordinatorResolver,
    this.downloadProfilePictureFn,
    this.remoteNotificationGate,
    this.backgroundNotificationDuplicateGuardDelay = const Duration(seconds: 2),
    this.accountMigrationNetworkGate = allowAccountMigrationNetworkSideEffects,
    this.sendDeliveryReceipt,
    this.autoDownloadDecider,
    this.stageNotificationDisplayCustody,
    this.promoteNotificationDisplayCustody,
    this.retryNotificationDisplays,
  }) : _durableNotificationCoordinatorResolver =
           durableNotificationCoordinatorResolver ??
           DurableNotificationToneLease.openMobileDefault;

  Future<DurableNotificationToneLease?>
  _resolveDurableNotificationCoordinator() {
    return _durableNotificationCoordinatorFuture ??=
        _openDurableNotificationCoordinator();
  }

  Future<DurableNotificationToneLease?>
  _openDurableNotificationCoordinator() async {
    try {
      return await _durableNotificationCoordinatorResolver();
    } catch (error) {
      // Claim storage is a duplicate-suppression optimization. If the mobile
      // support/app-group directory is unavailable, preserve legacy delivery
      // and tone behavior instead of dropping the notification.
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_NOTIFICATION_CLAIM_STORAGE_UNAVAILABLE',
        details: {'error': error.toString()},
      );
      return null;
    }
  }

  Future<ConversationNotificationSnapshot?>
  _loadDirectConversationNotificationSnapshot(String contactPeerId) =>
      loadDirectConversationNotificationSnapshot(
        messageRepository: messageRepo,
        contactPeerId: contactPeerId,
        mediaAttachmentRepository: mediaAttachmentRepo,
      );

  /// Stream of new incoming chat messages for the UI to listen to.
  Stream<ConversationMessage> get incomingMessageStream =>
      _messageController.stream;

  /// Stream of contacts updated from an incoming message (username or avatar).
  Stream<ContactModel> get contactUpdatedStream =>
      _contactUpdatedController.stream;

  /// Emits a contact update from an external source (e.g. ProfileUpdateListener).
  void emitContactUpdate(ContactModel contact) {
    _contactUpdatedController.add(contact);
  }

  /// Starts listening for incoming P2P messages.
  void start() {
    if (_subscription != null) return;

    emitFlowEvent(layer: 'FL', event: 'CHAT_LISTENER_START', details: {});

    _subscription = chatMessageStream.listen(
      _onMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  /// Stops listening and cleans up resources.
  void stop() {
    emitFlowEvent(layer: 'FL', event: 'CHAT_LISTENER_STOP', details: {});

    _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _messageController.close();
    _contactUpdatedController.close();
  }

  Future<void> _autoDownloadMedia(ConversationMessage message) async {
    if (!message.privateMediaPolicy.allowsAutomaticDownload) return;
    try {
      final attachments = await mediaAttachmentRepo!.getAttachmentsForMessage(
        message.id,
        owner: MediaOwnerLane.direct,
      );
      if (attachments.isEmpty) return;

      final downloadedMedia = <MediaAttachment>[];
      for (final attachment in attachments) {
        if (attachment.downloadStatus != 'pending') {
          downloadedMedia.add(attachment);
          continue;
        }
        try {
          // 229: consult the user policy immediately before transfer; the
          // storage owner is the typed lane this row was addressed under.
          final decider =
              autoDownloadDecider ?? defaultMediaAutoDownloadDecider;
          if (decider != null &&
              !await decider.shouldAutoDownload(
                conversationKind: MediaConversationKind.oneToOne,
                storageOwner: MediaOwnerLane.direct,
                mediaType: attachment.mediaType,
                downloadStatus: attachment.downloadStatus,
              )) {
            downloadedMedia.add(attachment);
            continue;
          }
          final result = await downloadMedia(
            bridge: bridge!,
            mediaAttachmentRepo: mediaAttachmentRepo!,
            mediaFileManager: mediaFileManager!,
            attachment: attachment,
            contactPeerId: message.contactPeerId,
            owner: MediaOwnerLane.direct,
            messageRepo: messageRepo,
          );
          if (result != null) {
            downloadedMedia.add(result);
          } else {
            // Re-read the authoritative persisted status so a terminal
            // download_failed (relay not-found / budget exhausted) isn't shown
            // as a retryable `failed` (INV-DL-1).
            final persisted = await mediaAttachmentRepo!
                .getAttachmentsForMessage(
                  message.id,
                  owner: MediaOwnerLane.direct,
                );
            final match = persisted.where((a) => a.id == attachment.id);
            downloadedMedia.add(
              match.isEmpty
                  ? attachment.copyWith(downloadStatus: 'failed')
                  : match.first,
            );
          }
        } catch (e) {
          downloadedMedia.add(attachment.copyWith(downloadStatus: 'failed'));
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_LISTENER_DOWNLOAD_ERROR',
            details: {
              'blobId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
              'error': e.toString(),
            },
          );
        }
      }

      // Re-emit with media hydrated — ConversationWired._upsertMessageById
      // replaces by ID so the UI updates seamlessly.
      _messageController.add(message.copyWith(media: downloadedMedia));
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_LISTENER_AUTO_DOWNLOAD_ERROR',
        details: {
          'messageId': message.id.length > 8
              ? message.id.substring(0, 8)
              : message.id,
          'error': e.toString(),
        },
      );
    }
  }

  /// Checks if a contact's avatar file exists on disk. If not, triggers
  /// a fire-and-forget download from the relay. Naturally retries on each
  /// incoming message until the avatar is successfully downloaded.
  void _ensureAvatarDownloaded(ContactModel contact) {
    if (bridge == null) return;

    final docsDir = UserAvatar.documentsDir;
    if (docsDir != null) {
      final file = File('$docsDir/media/avatars/${contact.peerId}.jpg');
      if (file.existsSync()) return;
    }

    () async {
      try {
        final dlFn = downloadProfilePictureFn ?? downloadProfilePicture;
        final updated = await dlFn(
          bridge: bridge!,
          contactRepo: contactRepo,
          ownerPeerId: contact.peerId,
          avatarVersion: 'initial',
        );
        if (updated != null) {
          emitContactUpdate(updated);
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_AVATAR_RETRY_ERROR',
          details: {'peerId': contact.peerId, 'error': e.toString()},
        );
      }
    }();
  }

  Future<void> _onMessage(ChatMessage message) async {
    await processIncomingMessage(message);
  }

  bool? _confirmationValueForState(ChatMessageProcessState state) {
    switch (state) {
      case ChatMessageProcessState.stored:
      case ChatMessageProcessState.blockedSender:
      case ChatMessageProcessState.duplicate:
      case ChatMessageProcessState.durablySuperseded:
      case ChatMessageProcessState.ignoredEdit:
      // 361: a terminally refused linked modality releases transport custody
      // exactly like the other durable rejections.
      case ChatMessageProcessState.linkedModalityRefused:
        return true;
      case ChatMessageProcessState.notChatMessage:
      case ChatMessageProcessState.missingMlKemSecret:
      case ChatMessageProcessState.decryptionFailed:
      case ChatMessageProcessState.decryptionDeferred:
      case ChatMessageProcessState.unknownSender:
      case ChatMessageProcessState.editMissingOriginal:
      case ChatMessageProcessState.accountMigrationBlocked:
      case ChatMessageProcessState.error:
        return false;
    }
  }

  Future<bool> _allowsInboundAccountSideEffects(ChatMessage message) async {
    const operation = 'chat_listener_inbound_message';
    try {
      final peerId = message.to.trim().isEmpty ? null : message.to;
      final allowed = await accountMigrationNetworkGate(
        peerId: peerId,
        operation: operation,
      );
      if (!allowed) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_INBOUND_EVENT_BLOCKED',
          details: {
            'operation': operation,
            'family': 'direct_chat',
            'peerId': ?peerId,
          },
        );
      }
      return allowed;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_INBOUND_EVENT_BLOCKED',
        details: {
          'operation': operation,
          'family': 'direct_chat',
          'reason': 'gate_error',
          'error': e.toString(),
        },
      );
      return false;
    }
  }

  Future<void> _maybeConfirmDirectNonce(
    ChatMessage message,
    ChatMessageProcessState state,
  ) async {
    final nonce = message.confirmNonce;
    final value = _confirmationValueForState(state);
    if (bridge == null || nonce == null || nonce.isEmpty || value == null) {
      return;
    }

    try {
      await callP2PConfirmDirectMessage(bridge!, nonce: nonce, ok: value);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_LISTENER_CONFIRM_NONCE_ERROR',
        details: {'nonce': nonce, 'error': e.toString(), 'ok': value},
      );
    }
  }

  Future<ChatMessageProcessOutcome> processIncomingMessage(
    ChatMessage message, {
    bool suppressNotification = false,
    bool forceSilentNotification = false,
    String? stagedEntryId,
  }) async {
    Future<ChatMessageProcessOutcome> finish(
      ChatMessageProcessOutcome outcome,
    ) async {
      await _maybeConfirmDirectNonce(message, outcome.state);
      return outcome;
    }

    try {
      if (!await _allowsInboundAccountSideEffects(message)) {
        return const ChatMessageProcessOutcome(
          state: ChatMessageProcessState.accountMigrationBlocked,
        );
      }

      // Check if sender is blocked — reject message entirely (don't persist).
      // 361: with a transport authority present, the blocked policy applies
      // to the RESOLVED logical contact before decrypt; an unresolvable
      // transport falls through to the handler's own fail-closed identity
      // checks.
      final senderPeerId = message.from;
      String blockedLookupPeerId = senderPeerId;
      if (transportAuthority != null) {
        final resolution = await transportAuthority!
            .resolveDirectTransportAuthority(senderPeerId);
        if (resolution.authorized) {
          blockedLookupPeerId = resolution.contactAccountPeerId!;
        }
      }
      final senderContact = await contactRepo.getContact(blockedLookupPeerId);
      if (senderContact != null && senderContact.isBlocked) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_BLOCKED_REJECT',
          details: {
            'from': senderPeerId.length > 10
                ? senderPeerId.substring(0, 10)
                : senderPeerId,
          },
        );
        return finish(
          const ChatMessageProcessOutcome(
            state: ChatMessageProcessState.blockedSender,
          ),
        );
      }

      // Opportunistically download avatar if missing
      if (senderContact != null) {
        _ensureAvatarDownloaded(senderContact);
      }

      // 147: on a prefetch HIT (predecryptedText already supplied by the
      // inbox-drain fan-out) the handler skips its own decrypt, so the ML-KEM
      // secret + ring it would consult are unused — don't pay the serial
      // keystore reads on the drain hot path. Null on every live path keeps the
      // legacy decrypt behaviour.
      final hasPredecryptedText = message.predecryptedText != null;
      final ownSecretKey =
          (!hasPredecryptedText && getOwnMlKemSecretKey != null)
          ? await getOwnMlKemSecretKey!()
          : null;
      final ownSecretKeyRing =
          (!hasPredecryptedText && getOwnMlKemSecretKeyRing != null)
          ? await getOwnMlKemSecretKeyRing!()
          : null;

      final (
        result,
        conversationMessage,
        updatedContact,
      ) = await handleIncomingChatMessage(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: ownSecretKey,
        fallbackMlKemSecretKeys: ownSecretKeyRing,
        // 147: if the inbox-drain prefetch already decrypted this message's
        // envelope (concurrently, ahead of the serial commit loop), use that
        // plaintext and skip the bridge decrypt. Null on every live path.
        predecryptedText: message.predecryptedText,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        transport: message.transport,
        stagedEntryId: stagedEntryId,
        sendDeliveryReceipt: sendDeliveryReceipt == null
            ? null
            : (messageId) => sendDeliveryReceipt!(
                contactPeerId: message.from,
                messageIds: [messageId],
              ),
        sendMutationDeliveryReceipt: sendDeliveryReceipt == null
            ? null
            : (messageId, {required mutationEventId}) => sendDeliveryReceipt!(
                contactPeerId: message.from,
                messageIds: [messageId],
                mutationEventIds: <String, String>{messageId: mutationEventId},
              ),
        stageNotificationDisplayCustody: stageNotificationDisplayCustody,
        promoteNotificationDisplayCustody: promoteNotificationDisplayCustody,
        transportAuthority: transportAuthority,
      );

      if (updatedContact != null) {
        _contactUpdatedController.add(updatedContact);
      }

      if (result == HandleChatMessageResult.missingMlKemSecret) {
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.missingMlKemSecret,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.decryptionFailed) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_DECRYPT_FAILED',
          details: {
            'from': senderPeerId.length > 10
                ? senderPeerId.substring(0, 10)
                : senderPeerId,
          },
        );
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.decryptionFailed,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.decryptionDeferred) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_DECRYPT_DEFERRED',
          details: {
            'from': senderPeerId.length > 10
                ? senderPeerId.substring(0, 10)
                : senderPeerId,
          },
        );
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.decryptionDeferred,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.unknownSender) {
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.unknownSender,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.duplicate) {
        await retryNotificationDisplays?.call();
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.duplicate,
            updatedContact: updatedContact,
            // 172 TC-03: every duplicate return in handleIncomingChatMessage
            // verified a durable prior row (same-id getMessage / dedupKey /
            // content query) before returning — so this duplicate is safe to
            // treat as terminal in the disposition mapper.
            duplicatePriorPersisted: true,
          ),
        );
      }

      if (result == HandleChatMessageResult.durablySuperseded) {
        // Deliberately NOT `retryNotificationDisplays`: this terminal replay
        // must produce zero display effects.
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.durablySuperseded,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.ignoredEdit) {
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.ignoredEdit,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.linkedModalityRefused) {
        // 361: terminal — zero publication, zero display retry.
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.linkedModalityRefused,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.editMissingOriginal) {
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.editMissingOriginal,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.notChatMessage) {
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.notChatMessage,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.chatMessage &&
          conversationMessage != null) {
        // Check if sender is archived — suppress UI notification but message is already persisted
        final contact = await contactRepo.getContact(
          conversationMessage.contactPeerId,
        );
        if (contact != null && contact.isArchived) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_LISTENER_ARCHIVED_SUPPRESS',
            details: {
              'id': conversationMessage.id.length > 8
                  ? conversationMessage.id.substring(0, 8)
                  : conversationMessage.id,
              'from': conversationMessage.senderPeerId.length > 10
                  ? conversationMessage.senderPeerId.substring(0, 10)
                  : conversationMessage.senderPeerId,
            },
          );
          // The handler already promoted marker-first custody. Retire it from
          // current policy immediately instead of waiting for a future resume.
          await retryNotificationDisplays?.call();
          return finish(
            ChatMessageProcessOutcome(
              state: ChatMessageProcessState.stored,
              conversationMessage: conversationMessage,
              updatedContact: updatedContact,
            ),
          );
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_NEW_MESSAGE',
          details: {
            'id': conversationMessage.id.length > 8
                ? conversationMessage.id.substring(0, 8)
                : conversationMessage.id,
            'from': conversationMessage.senderPeerId.length > 10
                ? conversationMessage.senderPeerId.substring(0, 10)
                : conversationMessage.senderPeerId,
          },
        );

        _messageController.add(conversationMessage);

        // Show local notification (suppressed if viewing this conversation)
        if (retryNotificationDisplays != null) {
          await retryNotificationDisplays!.call();
        } else if (notificationService != null && appVisibility != null) {
          final username =
              senderContact?.username ??
              (updatedContact?.username) ??
              'Unknown';
          try {
            await maybeShowNotification(
              notificationService: notificationService!,
              appVisibility: appVisibility!,
              contactPeerId: conversationMessage.contactPeerId,
              senderUsername: username,
              messageText: notificationBodyForMessage(
                conversationMessage.text,
                conversationMessage.media,
                privateMediaPolicy: conversationMessage.privateMediaPolicy,
              ),
              suppressNotification: suppressNotification,
              forceSilent: forceSilentNotification,
              messageId: conversationMessage.id,
              toneTracker: notificationToneTracker,
              durableNotificationCoordinatorResolver:
                  _resolveDurableNotificationCoordinator,
              loadConversationNotificationSnapshot: () =>
                  _loadDirectConversationNotificationSnapshot(
                    conversationMessage.contactPeerId,
                  ),
              notificationEventType: 'new_message',
              consumeRecentRemoteNotificationAnnouncement:
                  ({required payload, String? messageId}) =>
                      (remoteNotificationGate ?? recentRemoteNotificationGate)
                          .consumeIfRecentAnnouncement(
                            payload: payload,
                            messageId: messageId,
                          ),
              // 118 Phase 2: live-wins handshake — a live direct notification
              // writes a dedup marker so a late FCM isolate for the same message
              // suppresses instead of double-alerting.
              markRecentRemoteNotificationAnnouncement:
                  ({required payload, String? messageId}) =>
                      (remoteNotificationGate ?? recentRemoteNotificationGate)
                          .markAnnouncement(
                            payload: payload,
                            messageId: messageId,
                          ),
              backgroundDuplicateGuardDelay:
                  backgroundNotificationDuplicateGuardDelay,
            );
          } catch (error) {
            // Message persistence already succeeded. A local-notification
            // failure must release its claim but never downgrade stored state.
            emitFlowEvent(
              layer: 'FL',
              event: 'CHAT_LISTENER_NOTIFICATION_ERROR',
              details: {'error': error.toString()},
            );
          }
        }

        // Fire-and-forget: auto-download media attachments
        if (bridge != null &&
            mediaAttachmentRepo != null &&
            mediaFileManager != null &&
            conversationMessage.privateMediaPolicy.allowsAutomaticDownload) {
          _autoDownloadMedia(conversationMessage);
        }

        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.stored,
            conversationMessage: conversationMessage,
            updatedContact: updatedContact,
          ),
        );
      }

      return finish(
        ChatMessageProcessOutcome(
          state: ChatMessageProcessState.error,
          updatedContact: updatedContact,
          reasonDetail: 'missing conversation message for chatMessage result',
        ),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
      return finish(
        ChatMessageProcessOutcome(
          state: ChatMessageProcessState.error,
          reasonDetail: e.toString(),
        ),
      );
    }
  }
}
