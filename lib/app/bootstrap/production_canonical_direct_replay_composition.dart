import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/secure_storage/ml_kem_secret_ring.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/direct_conversation_notification_snapshot.dart';
import 'package:flutter_app/features/conversation/application/direct_notification_projection_owner.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart'
    show predecryptStagedInboxChatEntry;
import 'package:flutter_app/features/conversation/application/handle_incoming_message_deletion_use_case.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_chat_disposition.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_sibling_dispositions.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';

final class ProductionDirectReactionNotificationDependencies {
  const ProductionDirectReactionNotificationDependencies({
    required this.service,
    required this.appVisibility,
    required this.toneTracker,
    required this.durableCoordinator,
  });

  final NotificationService service;
  final AppVisibilitySuppressionReader appVisibility;
  final NotificationToneTracker toneTracker;
  final DurableNotificationToneLease durableCoordinator;
}

/// One exhaustive, UI-neutral direct-inbox adapter set used by foreground and
/// production headless recovery. P2P never receives a nullable current-family
/// handler from this owner.
final class ProductionCanonicalDirectReplayComposition {
  const ProductionCanonicalDirectReplayComposition({
    required this.loadIdentity,
    required this.chatMessageListener,
    required this.introductionListener,
    required this.contactRequestListener,
    required this.introductionRepository,
    required this.contactRepository,
    required this.messageRepository,
    required this.reactionRepository,
    required this.mediaAttachmentRepository,
    required this.transportAuthority,
    required this.bridge,
    required this.secureKeyStore,
    required this.mediaFileManager,
    required this.sendDeliveryReceipt,
    required this.notificationOwner,
    required this.reactionNotificationDependencies,
    this.pendingNotificationOverlay,
    this.forceSilentNotification = false,
    required this.publishPersistedReactionChange,
  });

  final Future<IdentityModel?> Function() loadIdentity;
  final ChatMessageListener Function() chatMessageListener;
  final IntroductionListener Function() introductionListener;
  final ContactRequestListener Function() contactRequestListener;
  final IntroductionRepository introductionRepository;
  final ContactRepository contactRepository;
  final MessageRepository messageRepository;
  final ReactionRepository reactionRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final DirectTransportAuthorityResolver transportAuthority;
  final Bridge bridge;
  final SecureKeyStore secureKeyStore;
  final MediaFileManager mediaFileManager;
  final Future<void> Function({
    required String contactPeerId,
    required List<String> messageIds,
    Map<String, String>? mutationEventIds,
  })
  sendDeliveryReceipt;
  final DirectNotificationProjectionOwner? Function() notificationOwner;
  final ProductionDirectReactionNotificationDependencies? Function()
  reactionNotificationDependencies;
  final PendingConversationNotificationOverlayStore? pendingNotificationOverlay;
  final bool forceSilentNotification;
  final void Function(ReactionChange change)? Function()
  publishPersistedReactionChange;

  Future<RecoveredInboxReplayOutcome> replayChatMessage(
    ChatMessage message, {
    String? stagedEntryId,
    bool suppressNotification = true,
  }) async {
    var outcome = await chatMessageListener().processIncomingMessage(
      message,
      suppressNotification: suppressNotification,
      forceSilentNotification: forceSilentNotification,
      stagedEntryId: stagedEntryId,
    );
    if (outcome.state == ChatMessageProcessState.unknownSender) {
      final ownPeerId = message.to;
      if (ownPeerId.isNotEmpty) {
        final resolution = await resolveUnknownInboxSender(
          introRepo: introductionRepository,
          contactRepo: contactRepository,
          ownPeerId: ownPeerId,
          senderPeerId: message.from,
        );
        if (resolution == UnknownInboxSenderResolution.contactRecovered) {
          outcome = await chatMessageListener().processIncomingMessage(
            message,
            suppressNotification: suppressNotification,
            forceSilentNotification: forceSilentNotification,
            stagedEntryId: stagedEntryId,
          );
        }
        if (outcome.state == ChatMessageProcessState.unknownSender) {
          return resolution == UnknownInboxSenderResolution.rejected
              ? (
                  disposition: RecoveredInboxChatDisposition.rejected,
                  reasonCode: 'unknown_sender_stranger',
                  reasonDetail: null,
                )
              : (
                  disposition: RecoveredInboxChatDisposition.retryable,
                  reasonCode: 'unknown_sender_intro_pending',
                  reasonDetail: null,
                );
        }
      }
    }
    return mapChatReplayOutcomeToDisposition(outcome);
  }

  Future<RecoveredInboxReplayOutcome> replayReaction(
    ChatMessage message, {
    String? stagedEntryId,
  }) async {
    final identity = await loadIdentity();
    final notify = reactionNotificationDependencies();
    final owner = notificationOwner();
    final (result, change) = await handleIncomingReaction(
      message: message,
      transportAuthority: transportAuthority,
      messageRepo: messageRepository,
      reactionRepo: reactionRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      ownMlKemSecretKey: identity?.mlKemSecretKey,
      forceSilentReactionNotification: forceSilentNotification,
      notificationService: notify?.service,
      appVisibility: notify?.appVisibility,
      notificationToneTracker: notify?.toneTracker,
      durableNotificationCoordinatorResolver: notify == null
          ? null
          : () async => notify.durableCoordinator,
      loadConversationNotificationSnapshot: () =>
          loadDirectConversationNotificationSnapshot(
            messageRepository: messageRepository,
            contactPeerId: message.from,
            mediaAttachmentRepository: mediaAttachmentRepository,
            pendingNotificationOverlay: pendingNotificationOverlay,
          ),
      consumeRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) =>
              recentRemoteNotificationGate.consumeIfRecentAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
      markRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) =>
              recentRemoteNotificationGate.markAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
      stageNotificationDisplayCustody: owner?.stageReaction,
      promoteNotificationDisplayCustody: owner?.promoteReactionReadyIfExact,
      commitNotificationRemove: owner?.onReactionRemoveCommitted,
      retryNotificationDisplays: owner?.retryNow,
    );
    if (result == HandleReactionResult.success && change != null) {
      publishPersistedReactionChange()?.call(change);
    }
    return mapReactionReplayResultToDisposition(result);
  }

  Future<RecoveredInboxReplayOutcome> replayMessageDeletion(
    ChatMessage message, {
    String? stagedEntryId,
  }) async {
    final identity = await loadIdentity();
    final (result, _) = await handleIncomingMessageDeletion(
      message: message,
      transportAuthority: transportAuthority,
      messageRepo: messageRepository,
      contactRepo: contactRepository,
      reactionRepo: reactionRepository,
      mediaAttachmentRepo: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
      bridge: bridge,
      ownMlKemSecretKey: identity?.mlKemSecretKey,
      sendDeliveryReceipt: (messageId) => sendDeliveryReceipt(
        contactPeerId: message.from,
        messageIds: <String>[messageId],
      ),
      sendMutationDeliveryReceipt: (messageId, {required mutationEventId}) =>
          sendDeliveryReceipt(
            contactPeerId: message.from,
            messageIds: <String>[messageId],
            mutationEventIds: <String, String>{messageId: mutationEventId},
          ),
      stagedEntryId: stagedEntryId,
    );
    return mapMessageDeletionReplayResultToDisposition(result);
  }

  Future<RecoveredInboxReplayOutcome> replayIntroduction(
    ChatMessage message,
  ) async {
    final outcome = await introductionListener().processIncomingMessage(
      message,
    );
    return switch (outcome.state) {
      IntroductionMessageProcessState.stored ||
      IntroductionMessageProcessState.deferred => (
        disposition: RecoveredInboxChatDisposition.committed,
        reasonCode: outcome.reasonCode,
        reasonDetail: outcome.reasonDetail,
      ),
      IntroductionMessageProcessState.retryableError => (
        disposition: RecoveredInboxChatDisposition.retryable,
        reasonCode: outcome.reasonCode,
        reasonDetail: outcome.reasonDetail,
      ),
      IntroductionMessageProcessState.blockedSender ||
      IntroductionMessageProcessState.rejected => (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: outcome.reasonCode,
        reasonDetail: outcome.reasonDetail,
      ),
    };
  }

  Future<RecoveredInboxReplayOutcome> replayContactRequest(
    ChatMessage message,
  ) async {
    try {
      await contactRequestListener().processIncomingMessage(message);
      return (
        disposition: RecoveredInboxChatDisposition.committed,
        reasonCode: 'contact_request_processed',
        reasonDetail: null,
      );
    } catch (error) {
      return (
        disposition: RecoveredInboxChatDisposition.retryable,
        reasonCode: 'contact_request_processing_error',
        reasonDetail: error.toString(),
      );
    }
  }

  Future<String?> predecryptChatMessage(ChatMessage message) =>
      predecryptStagedInboxChatEntry(
        message: message,
        contactRepo: contactRepository,
        bridge: bridge,
        loadOwnMlKemSecretKey: () async =>
            (await loadIdentity())?.mlKemSecretKey,
        loadOwnMlKemSecretKeyRing: () => loadMlKemSecretKeyRing(secureKeyStore),
      );
}
