import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart' as intl;
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/conversation/application/direct_media_fanout_admission.dart';
import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/debug/private_media_outbox_e2e.dart';
import 'package:flutter_app/core/debug/private_media_outbox_e2e_conversation.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_blob_terminalization.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/permissions/mic_permission_prompt.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/notification_tap_timing.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/contacts/application/direct_contact_device_trust.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/contact_profile/presentation/screens/contact_profile_screen.dart';
import 'package:flutter_app/features/contacts/application/block_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/unblock_contact_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/build_direct_media_library_batch_forward.dart';
import 'package:flutter_app/features/conversation/application/build_received_media_forward.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/confirmation_dialog.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';
import 'package:flutter_app/features/conversation/application/media_viewer_repository_resume_store.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/core/config/direct_linked_media_fanout_flag.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_conversation_modality_gate.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/direct_private_media_route_observer.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/utils/message_window_cap.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_rejection.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/application/load_reactions_use_case.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_actions.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_delete.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/application/private_media_action_eligibility.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/remove_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/presentation/controllers/reaction_optimistic_attempt_guard.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/application/check_intro_banner_use_case.dart';
import 'package:flutter_app/features/introduction/application/introduction_copy.dart';
import 'package:flutter_app/features/introduction/application/insert_intro_system_message.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/presentation/screens/friend_picker_wired.dart';
import 'package:flutter_app/features/introduction/presentation/screens/sent_confirmation_wired.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/share/presentation/navigation/share_target_picker_route.dart';
import 'package:flutter_app/features/share/application/direct_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/presentation/navigation/direct_media_batch_forward_picker_route.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_composer_controller.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_reaction_projection_controller.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_upload_activity_controller.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_voice_capture_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';
import 'package:flutter_app/shared/widgets/media/media_picture_in_picture_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'conversation_screen.dart';
import 'direct_shared_media_library_screen.dart';
import 'direct_private_media_viewer.dart';

typedef SendChatMessageFn =
    Future<(SendChatMessageResult, ConversationMessage?)> Function({
      required P2PService p2pService,
      required MessageRepository messageRepo,
      required String targetPeerId,
      required String text,
      required String senderPeerId,
      required String senderUsername,
      String? messageId,
      required bool preassignedMessageIdIsFresh,
      String? timestamp,
      Bridge? bridge,
      String? recipientMlKemPublicKey,
      String? quotedMessageId,
      List<MediaAttachment>? mediaAttachments,
      PrivateMediaPolicy? privateMediaPolicy,
      MediaAttachmentRepository? mediaAttachmentRepo,
      TransportMetrics? transportMetrics,
      DirectEventFanoutAuthoring? directEventFanout,
    });

typedef SendPrivateMediaFanoutChatMessageFn =
    Future<(SendChatMessageResult, ConversationMessage?)> Function({
      required P2PService p2pService,
      required MessageRepository messageRepo,
      required String targetPeerId,
      required String text,
      required String senderPeerId,
      required String senderUsername,
      String? messageId,
      required bool preassignedMessageIdIsFresh,
      String? timestamp,
      Bridge? bridge,
      String? recipientMlKemPublicKey,
      String? quotedMessageId,
      List<MediaAttachment>? mediaAttachments,
      PrivateMediaPolicy? privateMediaPolicy,
      MediaAttachmentRepository? mediaAttachmentRepo,
      TransportMetrics? transportMetrics,
      DirectEventFanoutAuthoring? directEventFanout,
      required DirectPrivateMediaFanoutContext directPrivateMediaFanout,
    });

typedef SendVoiceMessageFn =
    Future<(SendVoiceMessageResult, ConversationMessage?)> Function({
      required P2PService p2pService,
      required MessageRepository messageRepo,
      required String targetPeerId,
      required String senderPeerId,
      required String senderUsername,
      required AudioRecording recording,
      required Bridge bridge,
      String? recipientMlKemPublicKey,
      MediaAttachmentRepository? mediaAttachmentRepo,
      MediaFileManager? mediaFileManager,
      String? text,
      String? quotedMessageId,
      List<double>? waveform,
      String? messageId,
      String? timestamp,
      String? blobId,
      EncryptedMediaArtifact? preparedArtifact,
      DirectMediaFanoutAdmission? mediaAdmission,
    });

typedef SendReactionFn =
    Future<(SendReactionResult, MessageReaction?)> Function({
      required P2PService p2pService,
      required Bridge bridge,
      required ReactionRepository reactionRepo,
      required String targetPeerId,
      required String messageId,
      required String emoji,
      required String senderPeerId,
      required String recipientMlKemPublicKey,
      DirectEventFanoutAuthoring? directEventFanout,
    });

typedef RemoveReactionFn =
    Future<RemoveReactionResult> Function({
      required P2PService p2pService,
      required Bridge bridge,
      required ReactionRepository reactionRepo,
      required String targetPeerId,
      required String messageId,
      required String emoji,
      required String senderPeerId,
      required String recipientMlKemPublicKey,
      DirectEventFanoutAuthoring? directEventFanout,
    });

typedef DownloadMediaFn =
    Future<MediaAttachment?> Function({
      required Bridge bridge,
      required MediaAttachmentRepository mediaAttachmentRepo,
      required MediaFileManager mediaFileManager,
      required MediaAttachment attachment,
      required String contactPeerId,
      required MediaOwnerLane owner,
      MessageRepository? messageRepo,
      MediaDownloadIntent? intent,
    });

typedef EditChatMessageFn =
    Future<(SendChatMessageResult, ConversationMessage?)> Function({
      required P2PService p2pService,
      required MessageRepository messageRepo,
      required ConversationMessage originalMessage,
      required String updatedText,
      required String senderUsername,
      Bridge? bridge,
      String? recipientMlKemPublicKey,
      MediaAttachmentRepository? mediaAttachmentRepo,
      bool emitTimingEvent,
      DirectEventFanoutAuthoring? directEventFanout,
    });

typedef DeleteMessageForMeFn =
    Future<int> Function({
      required ConversationMessage message,
      required MessageRepository messageRepo,
      ReactionRepository? reactionRepo,
      MediaAttachmentRepository? mediaAttachmentRepo,
      MediaFileManager? mediaFileManager,
    });

class _PreparedConversationMediaUpload {
  final PendingComposerMedia source;
  final MediaAttachment pendingAttachment;
  final String absoluteDurablePath;

  const _PreparedConversationMediaUpload({
    required this.source,
    required this.pendingAttachment,
    required this.absoluteDurablePath,
  });
}

class _ForegroundDirectPrivateTransferLease {
  _ForegroundDirectPrivateTransferLease({
    required this.messageId,
    required this.coordinator,
    required this.envelopeRepository,
    required this.lifecycleMessageRepository,
    required this.tokens,
  });

  final String messageId;
  final OutgoingDirectPrivateMutationCoordinator coordinator;
  final OutgoingDirectPrivateEnvelopeCustodyRepository envelopeRepository;
  final DirectPrivateMediaLifecycleRepository lifecycleMessageRepository;
  final Map<String, Object> tokens;
  final Map<String, String> expectedPendingPaths = <String, String>{};
  final Map<String, OutgoingDirectPrivateMutationResult> completions =
      <String, OutgoingDirectPrivateMutationResult>{};
}

class _RejectedPendingMediaException implements Exception {
  const _RejectedPendingMediaException();
}

typedef DeleteMessageForEveryoneFn =
    Future<(SendChatMessageResult, ConversationMessage?)> Function({
      required P2PService p2pService,
      required MessageRepository messageRepo,
      required ConversationMessage originalMessage,
      ReactionRepository? reactionRepo,
      MediaAttachmentRepository? mediaAttachmentRepo,
      MediaFileManager? mediaFileManager,
      Bridge? bridge,
      String? recipientMlKemPublicKey,
      bool emitTimingEvent,
      DirectEventFanoutAuthoring? directEventFanout,
    });

typedef DeleteContactFn = Future<void> Function(String peerId);

typedef DirectMediaBatchForwardPickerLauncher =
    Future<DirectMediaBatchForwardCompletion?> Function(
      BuildContext context,
      DirectMediaLibraryBatchForwardDraft draft,
      DirectMediaBatchForwardDeliveryCoordinator deliveryCoordinator,
    );

Stream<void> _mergeDirectPictureInPictureAuthorizationStreams(
  Iterable<Stream<void>> streams,
) => Stream<void>.multi((controller) {
  final subscriptions = streams
      .map(
        (stream) => stream.listen(
          (_) => controller.addSync(null),
          onError: controller.addErrorSync,
        ),
      )
      .toList(growable: false);
  controller.onCancel = () async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  };
});

bool _directAttachmentChangeMatchesCurrent({
  required MediaAttachmentAuthorizationChange change,
  required String contactPeerId,
  required MediaViewerItem? Function()? currentItem,
}) {
  if (change.owner != MediaOwnerLane.direct) return false;
  if (change.scopeId != null && change.scopeId != contactPeerId) return false;
  final current = currentItem?.call();
  if (current == null) return true;
  if (current.owner != MediaOwnerLane.direct) return false;
  if (change.messageId != null && change.messageId != current.messageId) {
    return false;
  }
  if (change.attachmentId != null &&
      change.attachmentId != current.attachmentId) {
    return false;
  }
  return true;
}

/// Exact-current view of durable direct parent, removal, and attachment
/// mutations. Stream errors remain errors so the controller fails closed.
Stream<void> directPictureInPictureAuthorizationChanges(
  Stream<ConversationMessage> messageChanges, {
  required String contactPeerId,
  Stream<DirectMessageRemoval> messageRemovals =
      const Stream<DirectMessageRemoval>.empty(),
  Stream<MediaAttachmentAuthorizationChange> attachmentChanges =
      const Stream<MediaAttachmentAuthorizationChange>.empty(),
  MediaViewerItem? Function()? currentItem,
}) => _mergeDirectPictureInPictureAuthorizationStreams([
  messageChanges
      .where((message) {
        if (message.contactPeerId != contactPeerId) return false;
        final current = currentItem?.call();
        return current == null ||
            (current.owner == MediaOwnerLane.direct &&
                current.messageId == message.id);
      })
      .map<void>((_) {}),
  messageRemovals
      .where((removal) {
        if (removal.contactPeerId != contactPeerId) return false;
        final current = currentItem?.call();
        return current == null ||
            (current.owner == MediaOwnerLane.direct &&
                (removal.messageId == null ||
                    removal.messageId == current.messageId));
      })
      .map<void>((_) {}),
  attachmentChanges
      .where(
        (change) => _directAttachmentChangeMatchesCurrent(
          change: change,
          contactPeerId: contactPeerId,
          currentItem: currentItem,
        ),
      )
      .map<void>((_) {}),
]);

/// Wired widget that connects ConversationScreen to business logic.
///
/// Loads identity and messages on init, subscribes to incoming message stream,
/// and handles sending messages via use cases.
@visibleForTesting
PrivateMediaPolicy? debugConversationWiredInitialPrivateMediaPolicy;

class ConversationWired extends StatefulWidget {
  static const deleteSheetKey = ValueKey('conversation-delete-message-sheet');
  static const deletePromptKey = ValueKey('conversation-delete-message-prompt');
  static const deleteForMeKey = ValueKey('conversation-delete-for-me-action');
  static const deleteForEveryoneKey = ValueKey(
    'conversation-delete-for-everyone-action',
  );
  static const deleteCancelKey = ValueKey('conversation-delete-cancel-action');

  /// 204 (BUG-1): the explicit Cancel row on the attach-source bottom sheet.
  static const attachSheetCancelKey = ValueKey(
    'conversation-attach-cancel-action',
  );

  /// 159 (TC-159-06): a test-only counter incremented once per
  /// [_ConversationWiredState._sortMessagesForDisplay] call. A relay-drain burst
  /// of M messageChanges events runs M synchronous sorts on HEAD; the per-frame
  /// coalescer collapses the burst into ONE batched sort. Tests reset it to 0.
  @visibleForTesting
  static int debugSortInvocationCount = 0;

  final ContactModel contact;
  final IdentityRepository identityRepo;
  final MessageRepository messageRepo;
  final ChatMessageListener chatMessageListener;
  final P2PService p2pService;
  final Bridge? bridge;
  final SendChatMessageFn sendChatMessageFn;
  final SendPrivateMediaFanoutChatMessageFn sendPrivateMediaFanoutChatMessageFn;
  final EditChatMessageFn editChatMessageFn;
  final DeleteMessageForMeFn deleteMessageForMeFn;
  final DeleteMessageForEveryoneFn deleteMessageForEveryoneFn;
  final List<ConversationMessage>? initialMessages;
  final ContactRepository? contactRepo;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final MediaFileManager? mediaFileManager;
  final List<File>? initialAttachments;
  final List<PendingComposerMedia>? initialPendingMedia;
  final String? initialText;
  final ImageProcessor? imageProcessor;
  final MediaPicker? mediaPicker;
  final ImageQualityPreference qualityPreference;
  final ImageQualityPreference videoQualityPreference;
  final int maxAttachmentBudgetBytes;
  final ActiveConversationTracker? conversationTracker;
  final AudioRecorderService? audioRecorderService;

  /// Permission authority for the voice-record mic (152). On denial the screen
  /// routes through this gateway so a `permanentlyDenied` user sees the shared
  /// rationale dialog + "Open Settings" deep-link instead of a dead-end toast.
  /// Production gets the real plugin via the default; tests inject a fake.
  final MicPermissionGateway micPermissionGateway;
  final ReactionRepository? reactionRepo;
  final ReactionListener? reactionListener;
  final IntroductionRepository? introductionRepository;
  final DeleteContactFn? deleteContactFn;
  final UploadMediaFn uploadMediaFn;
  final DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo;
  final SendVoiceMessageFn sendVoiceMessageFn;
  final SendReactionFn sendReactionFn;
  final RemoveReactionFn removeReactionFn;
  final DownloadMediaFn downloadMediaFn;

  /// Injectable seam for the encrypt-once LAN artifact (112 Phase 4): the
  /// real implementation does file I/O that cannot complete inside the
  /// testWidgets fake-async zone, so LAN-path widget tests stub this.
  final PrepareEncryptedMediaArtifactFn prepareEncryptedMediaArtifactFn;
  final PreparedDirectMediaBlobCustodyCoordinator?
  preparedDirectMediaBlobCustodyCoordinator;

  /// Testable view of the strict blob client selector. Production keeps the
  /// compile-time default; default-build host proofs can enable the exact
  /// authoring branch without skipping the causal scenario.
  final bool directMediaBlobCustodyClientEnabled;
  final bool directLinkedEventFanoutEnabled;

  /// 362: injectable authoring seam over the build-time linked-media
  /// selector; host proofs enable it per case, production reads the const.
  final DirectLinkedMediaFanoutSelector directLinkedMediaFanoutSelector;
  final DateTime? notificationTappedAt;
  final AppShellController? appShellController;
  final TransportMetrics? transportMetrics;

  /// Debug/E2E-only controller for the manifest-owned private-media outbox
  /// proof. Production routes leave this null; the controller itself also
  /// rejects registration unless the explicit E2E build flag enabled it.
  final PrivateMediaOutboxE2EController? privateMediaOutboxE2EController;

  /// 229: user auto-download policy consulted immediately before every
  /// automatic visible-media recovery transfer (initial mount, staged-drain
  /// reload and older-page load). Null preserves HEAD behavior (allowed).
  /// Explicit unavailable-media retry stays user-authoritative and is never
  /// gated by this decider.
  final MediaAutoDownloadDecider? autoDownloadDecider;

  /// 231: direct received-media Save/Share/Info authority. Null (production
  /// default) builds a controller over [messageRepo]/[mediaAttachmentRepo]
  /// and the real [ReceivedMediaEgressService]; tests inject a recording
  /// controller. Media actions stay unwired when [mediaAttachmentRepo] is
  /// absent and no controller is injected.
  final ReceivedMediaActionController? receivedMediaActionController;
  final GroupRepository? forwardGroupRepository;
  final GroupMessageRepository? forwardGroupMessageRepository;
  final GroupInviteDeliveryAttemptRepository?
  forwardGroupInviteDeliveryAttemptRepository;
  final GroupMessageListener? forwardGroupMessageListener;
  final ActiveConversationTracker? forwardGroupConversationTracker;

  /// Injected by owners that can supply contact+group picker dependencies.
  /// The pure conversation screen sees only a bounded forward callback.
  final Future<void> Function(BuildContext context, ShareIntent shareIntent)?
  receivedMediaForwardLauncher;

  /// 233 test seam: stands in for the shared-media library route. The popped
  /// [DirectSharedMediaLibraryResult] flows through the SAME Go to Message
  /// coordination as the production screen.
  final WidgetBuilder? sharedMediaLibraryRouteBuilder;

  /// Narrow test/owner seam for the already-qualified Plan-249 direct-only
  /// picker. It cannot authorize a denied Session-01 source build.
  final DirectMediaBatchForwardPickerLauncher?
  directMediaBatchForwardPickerLauncher;

  /// 233 test seam: the scroll-target delegate for Go to Message. Production
  /// defaults to the element-walk + ensureVisible reveal over the reversed
  /// list's stable `msg-<id>` keys.
  final Future<void> Function(String messageId)? revealConversationMessageFn;

  /// 360: the exact linked-device trust authority handed to the contact
  /// profile this screen opens from the header avatar.
  ///
  /// Optional here (the production composition root supplies the real
  /// database-backed capability) but REQUIRED and non-null on
  /// [ContactProfileScreen]. Left null — bare pumps and tests — the profile
  /// receives the inert [UnavailableDirectContactDeviceTrust], which reports an
  /// empty uninitialized roster and refuses every decision.
  final DirectContactDeviceTrustCapability? directDeviceTrust;

  /// 361: the smallest conversation modality policy. The default allows the
  /// incumbent full surface; the restricted linked role injects
  /// [DirectConversationModalityGate.linkedBlobFree].
  final DirectConversationModalityGate modalityGate;

  /// 361: the shared blob-free target-batch authoring owner. Null keeps the
  /// incumbent single-target senders byte-identically.
  final DirectEventFanoutAuthoring? directEventFanout;

  /// Foreground call access backed by the process-owned composition. A null
  /// capability keeps the header action hidden; a present but unavailable
  /// capability remains visible as a disabled, explanatory action.
  final OutgoingCallCapability? outgoingCallCapability;

  const ConversationWired({
    super.key,
    required this.contact,
    required this.identityRepo,
    required this.messageRepo,
    required this.chatMessageListener,
    required this.p2pService,
    this.bridge,
    this.sendChatMessageFn = sendChatMessage,
    this.sendPrivateMediaFanoutChatMessageFn = sendChatMessage,
    this.editChatMessageFn = editChatMessage,
    this.deleteMessageForMeFn = deleteMessageForMe,
    this.deleteMessageForEveryoneFn = deleteMessageForEveryone,
    this.initialMessages,
    this.contactRepo,
    this.mediaAttachmentRepo,
    this.mediaFileManager,
    this.initialAttachments,
    this.initialPendingMedia,
    this.initialText,
    this.imageProcessor,
    this.mediaPicker,
    this.qualityPreference = ImageQualityPreference.compressed,
    this.videoQualityPreference = ImageQualityPreference.compressed,
    this.maxAttachmentBudgetBytes = kGeneralMediaAttachmentBudgetBytes,
    this.conversationTracker,
    this.audioRecorderService,
    this.micPermissionGateway = const PermissionHandlerMicGateway(),
    this.reactionRepo,
    this.reactionListener,
    this.introductionRepository,
    this.deleteContactFn,
    this.uploadMediaFn = uploadMedia,
    this.uploadRetryProjectionRepo,
    this.sendVoiceMessageFn = sendVoiceMessage,
    this.sendReactionFn = sendReaction,
    this.removeReactionFn = removeReaction,
    this.downloadMediaFn = downloadMedia,
    this.prepareEncryptedMediaArtifactFn = prepareEncryptedMediaArtifact,
    this.preparedDirectMediaBlobCustodyCoordinator,
    this.directMediaBlobCustodyClientEnabled =
        kDirectMediaBlobCustodyClientEnabled,
    this.directLinkedEventFanoutEnabled = kDirectLinkedEventFanoutEnabled,
    this.directLinkedMediaFanoutSelector =
        const DirectLinkedMediaFanoutSelector(),
    this.notificationTappedAt,
    this.appShellController,
    this.transportMetrics,
    this.privateMediaOutboxE2EController,
    this.autoDownloadDecider,
    this.receivedMediaActionController,
    this.forwardGroupRepository,
    this.forwardGroupMessageRepository,
    this.forwardGroupInviteDeliveryAttemptRepository,
    this.forwardGroupMessageListener,
    this.forwardGroupConversationTracker,
    this.receivedMediaForwardLauncher,
    this.sharedMediaLibraryRouteBuilder,
    this.directMediaBatchForwardPickerLauncher,
    this.revealConversationMessageFn,
    this.directDeviceTrust,
    this.modalityGate = const DirectConversationModalityGate(),
    this.directEventFanout,
    this.outgoingCallCapability,
  });

  @override
  State<ConversationWired> createState() => _ConversationWiredState();
}

class _ConversationWiredState extends State<ConversationWired>
    with WidgetsBindingObserver {
  static const _uuid = Uuid();
  static const _pageSize = 50;
  static final MediaPicker _defaultMediaPicker = SystemMediaPicker();

  late AppLifecycleState _appLifecycleState;
  int _appLifecycleGeneration = 0;
  Object? _privateMediaOutboxE2EEndpointToken;
  String? _privateMediaOutboxE2ENextMessageId;
  String? _privateMediaOutboxE2ENextAttachmentId;
  int? _privateMediaOutboxE2ELifecycleBaseline;
  bool _privateMediaOutboxE2ERunInFlight = false;

  IdentityModel? _identity;
  late ContactModel _contact;
  List<ConversationMessage> _messages = [];

  // 172 (INV-2): kept-but-undisplayed staged-entry count behind the
  // "couldn't display N messages" affordance. 0 hides the banner.
  int _undeliveredAttentionCount = 0;

  // 159 (rebuild-storms-2): per-frame coalescer for the two per-event
  // message-apply sinks (messageChanges + incomingMessageStream). A relay-drain
  // burst of M events enqueues M upserts and applies them in ONE batched
  // setState + ONE sort on the next frame, instead of M setStates + M sorts. The
  // per-event live-stream side effects (scroll-to-edge / markAsRead /
  // intro-dismiss) run once-per-flush against the POST-batch state.
  bool _coalesceFlushScheduled = false;
  bool _coalesceNeedsFlush = false;
  bool _coalesceWantsMarkRead = false;
  bool _coalesceWantsIntroCheck = false;
  bool _outgoingCallStartInFlight = false;
  bool _outgoingCallContactAvailable = false;
  int _outgoingCallAvailabilityGeneration = 0;
  final Set<String> _coalesceLiveEdgeCandidateIds = {};

  StreamSubscription<ConversationMessage>? _incomingSubscription;
  StreamSubscription<ConversationMessage>? _repoChangeSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;
  StreamSubscription<bool>? _outgoingCallAvailabilitySubscription;
  final _scrollController = ScrollController();

  bool _hasMoreOlderMessages = true;
  bool _isLoadingMore = false;
  bool _initialLoadDone = false;
  bool _isSending = false;

  final _composerController = ConversationComposerController();
  late final ConversationUploadActivityController<_DirectComposerSnapshot>
  _uploadActivityController;
  final _reactionProjectionController =
      ConversationReactionProjectionController();
  final _reactionAttemptGuard = ReactionOptimisticAttemptGuard();
  late final ConversationVoiceCaptureController _voiceCaptureController;
  PrivateMediaPolicy _privateMediaPolicy = const PrivateMediaPolicy.ordinary();
  bool _privateMediaPolicyInvalidated = false;
  static const _maxAttachments = 10;

  // 117 Session 3: a recording captured by the 5-minute auto-stop is held
  // here (with its waveform) while the composer is in the `reviewing` state,
  // so the user can send or discard it instead of it being silently dropped.
  AudioRecording? _pendingReviewRecording;
  List<double> _pendingReviewWaveform = const [];

  StreamSubscription<ReactionChange>? _reactionSubscription;

  // Introduction banner state
  bool _showIntroBanner = false;
  bool _hasOtherFriends = false;
  String? _activeQuoteMessageId;
  String? _editingMessageId;
  String? _editingOriginalText;
  String _draftText = '';
  String? _restoredFailedMessageId;
  String? _restoredFailedDraftText;
  String? _restoredFailedQuotedMessageId;
  final Set<String> _unavailableMediaRetriesInFlight = <String>{};

  ConversationComposerViewState get _composerViewState =>
      _composerController.value;

  MediaPicker get _mediaPicker => widget.mediaPicker ?? _defaultMediaPicker;

  bool get _isRecording => _composerViewState.recordingState.isActive;

  Map<String, String> _activeVisualUploadOwnersByAttachmentId() {
    final result = <String, String>{};
    for (final message in _messages) {
      if (message.isIncoming ||
          message.isDeleted ||
          message.status != 'sending') {
        continue;
      }
      for (final attachment in message.media) {
        if (attachment.mediaType == 'image' ||
            attachment.mediaType == 'video' ||
            attachment.mime == 'image/gif') {
          result[attachment.id] = message.id;
        }
      }
    }
    return result;
  }

  bool get _supportsDurableMediaUploads =>
      widget.mediaAttachmentRepo != null && widget.mediaFileManager != null;

  bool _isOutgoingPrivateOneMoreLook(PrivateMediaPolicy policy) =>
      policy.version == 1 &&
      (policy.mode == PrivateMediaMode.protected ||
          policy.mode == PrivateMediaMode.viewOnce);

  Future<_ForegroundDirectPrivateTransferLease>
  _beginForegroundDirectPrivateTransfer({
    required String messageId,
    required List<MediaAttachment> attachments,
  }) async {
    final mediaRepository = widget.mediaAttachmentRepo;
    final messageRepository = widget.messageRepo;
    if (mediaRepository is! OutgoingDirectPrivateMutationRepository ||
        mediaRepository is! DirectPrivateMediaCleanupRepository ||
        mediaRepository is! DirectPrivateMediaCleanupRuntime ||
        messageRepository is! OutgoingDirectPrivateEnvelopeCustodyRepository ||
        messageRepository is! DirectPrivateMediaLifecycleRepository ||
        widget.bridge == null ||
        widget.mediaFileManager == null ||
        attachments.isEmpty) {
      throw StateError(
        'foreground private upload requires exact lifecycle, mutation, '
        'envelope, and file custody capabilities',
      );
    }

    final mutationRepository =
        mediaRepository as OutgoingDirectPrivateMutationRepository;
    final cleanupRuntime = mediaRepository as DirectPrivateMediaCleanupRuntime;
    final coordinator =
        mutationRepository.outgoingDirectPrivateMutationCoordinator;
    if (!identical(
      coordinator.lifecycleLock,
      cleanupRuntime.directPrivateMediaLifecycleLock,
    )) {
      throw StateError(
        'foreground private upload lifecycle authorities do not match',
      );
    }

    final tokens = <String, Object>{};
    final attachmentIds =
        attachments
            .map((attachment) => attachment.id)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (attachmentIds.length != attachments.length) {
      throw StateError('foreground private upload attachment ids conflict');
    }
    try {
      for (final attachmentId in attachmentIds) {
        Object? token;
        await coordinator.lifecycleLock.synchronized(attachmentId, () async {
          token = directPrivateMediaTransferRegistry.tryBegin(
            attachmentId,
            messageId: messageId,
          );
        });
        if (token == null) {
          throw StateError(
            'foreground private upload transfer custody is already owned',
          );
        }
        tokens[attachmentId] = token!;
      }
    } catch (_) {
      for (final entry in tokens.entries) {
        await coordinator.lifecycleLock.synchronized(entry.key, () async {
          directPrivateMediaTransferRegistry.end(entry.key, entry.value);
        });
      }
      rethrow;
    }

    return _ForegroundDirectPrivateTransferLease(
      messageId: messageId,
      coordinator: coordinator,
      envelopeRepository:
          messageRepository as OutgoingDirectPrivateEnvelopeCustodyRepository,
      lifecycleMessageRepository:
          messageRepository as DirectPrivateMediaLifecycleRepository,
      tokens: tokens,
    );
  }

  Future<void> _bindForegroundDirectPrivatePendingCustody({
    required _ForegroundDirectPrivateTransferLease lease,
    required List<_PreparedConversationMediaUpload> preparedUploads,
  }) async {
    if (preparedUploads.length != lease.tokens.length) {
      throw StateError(
        'foreground private upload durable attachment set changed',
      );
    }
    for (final plan in preparedUploads) {
      final attachment = plan.pendingAttachment;
      final token = lease.tokens[attachment.id];
      final expectedPendingPath = attachment.localPath;
      if (token == null ||
          expectedPendingPath == null ||
          expectedPendingPath.isEmpty) {
        throw StateError(
          'foreground private upload pending custody is incomplete',
        );
      }
      final invalidated = await lease.coordinator.lifecycleLock.synchronized(
        attachment.id,
        () async {
          if (!directPrivateMediaTransferRegistry.owns(attachment.id, token)) {
            return false;
          }
          return lease.envelopeRepository
              .invalidateWireEnvelopeBeforePrivateUpload(
                messageId: lease.messageId,
                attachmentId: attachment.id,
                expectedPendingLocalPath: expectedPendingPath,
              );
        },
      );
      if (!invalidated) {
        throw StateError(
          'foreground private upload envelope custody invalidation refused',
        );
      }
      lease.expectedPendingPaths[attachment.id] = expectedPendingPath;
    }
  }

  Future<MediaAttachment> _commitForegroundDirectPrivateCompletion({
    required _ForegroundDirectPrivateTransferLease lease,
    required _PreparedConversationMediaUpload plan,
    required MediaAttachment uploaded,
  }) async {
    final expectedPendingPath = lease.expectedPendingPaths[uploaded.id];
    if (plan.pendingAttachment.id != uploaded.id ||
        plan.pendingAttachment.localPath != expectedPendingPath ||
        expectedPendingPath == null) {
      throw StateError(
        'foreground private upload completion has no pending custody',
      );
    }
    final completion = await lease.coordinator.commitCompletion(
      attachment: uploaded,
      expectedPendingLocalPath: expectedPendingPath,
    );
    if (!completion.appliesToPrivateParent ||
        !completion.authorizesTransportHandoff) {
      throw StateError(
        'foreground private upload completion was not authorized',
      );
    }
    lease.completions[uploaded.id] = completion;
    return uploaded;
  }

  Future<void> _releaseForegroundDirectPrivateTransfer(
    _ForegroundDirectPrivateTransferLease lease,
  ) async {
    for (final entry in lease.tokens.entries) {
      try {
        await lease.coordinator.lifecycleLock.synchronized(entry.key, () async {
          directPrivateMediaTransferRegistry.end(entry.key, entry.value);
        });
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_PRIVATE_TRANSFER_RELEASE_ERROR',
          details: {'error': error.toString()},
        );
      }
    }

    final mediaRepository = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (mediaRepository == null || mediaFileManager == null) return;
    final lifecycle = DirectPrivateMediaLifecycle(
      messageRepository: lease.lifecycleMessageRepository,
      mediaAttachmentRepository: mediaRepository,
      mediaFileManager: mediaFileManager,
    );
    final engine = _privateMediaLifecycleEngine;
    if (engine != null &&
        identical(engine.lifecycleLock, lease.coordinator.lifecycleLock)) {
      try {
        // Exact cleanup only: unlike broad startup reconciliation, this cannot
        // terminalize a legitimate opening/viewing lease that is still active.
        await engine.cleanupTerminalMessage(lease.messageId);
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_PRIVATE_POST_TRANSFER_CLEANUP_ERROR',
          details: {'error': error.toString()},
        );
      }
    }
    for (final entry in lease.completions.entries) {
      if (!entry.value.authorizesTransportHandoff) {
        continue;
      }
      final expectedPendingPath = lease.expectedPendingPaths[entry.key];
      if (expectedPendingPath == null) continue;
      try {
        await lifecycle.cleanupCommittedPendingSource(
          messageId: lease.messageId,
          attachmentId: entry.key,
          expectedPendingLocalPath: expectedPendingPath,
        );
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_PRIVATE_PENDING_SOURCE_CLEANUP_ERROR',
          details: {'error': error.toString()},
        );
      }
    }
    final completedPendingPaths = <String, String>{};
    for (final attachmentId in lease.completions.keys) {
      final path = lease.expectedPendingPaths[attachmentId];
      if (path != null) completedPendingPaths[attachmentId] = path;
    }
    await reconcileReleasedOutgoingDirectPrivateUploadAttempt(
      messageId: lease.messageId,
      expectedPendingPaths: completedPendingPaths,
      coordinator: lease.coordinator,
      envelopeRepository: lease.envelopeRepository,
      lifecycleRepository: lease.lifecycleMessageRepository,
    );
  }

  DirectUploadRetryProjectionRepository? get _uploadRetryProjection =>
      widget.uploadRetryProjectionRepo ??
      (widget.messageRepo is DirectUploadRetryProjectionRepository
          ? widget.messageRepo as DirectUploadRetryProjectionRepository
          : null);

  Future<List<_PreparedConversationMediaUpload>> _prepareDurableMediaUploads({
    required String messageId,
    required List<PendingComposerMedia> mediaToUpload,
    required List<MediaAttachment> optimisticMedia,
    _ForegroundDirectPrivateTransferLease? privateTransferLease,
  }) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (mediaAttachmentRepo == null ||
        mediaFileManager == null ||
        mediaToUpload.isEmpty ||
        optimisticMedia.length != mediaToUpload.length) {
      return const [];
    }

    final preparedUploads = <_PreparedConversationMediaUpload>[];
    final privatePendingAttachments = privateTransferLease == null
        ? const <MediaAttachment>[]
        : optimisticMedia
              .map(
                (attachment) => attachment.copyWith(
                  messageId: messageId,
                  localPath:
                      MediaFilePathConvention.relativePathForPendingUpload(
                        messageId: messageId,
                        attachmentId: attachment.id,
                        mime: attachment.mime,
                      ),
                  downloadStatus: 'upload_pending',
                  ownerLane: MediaOwnerLane.direct,
                ),
              )
              .toList(growable: false);

    try {
      for (var index = 0; index < mediaToUpload.length; index++) {
        final pending = mediaToUpload[index];
        final optimisticAttachment = optimisticMedia[index];
        final durableRelativePath = await mediaFileManager.copyToDurableStorage(
          sourceFilePath: pending.file.path,
          messageId: messageId,
          attachmentId: optimisticAttachment.id,
          mime: optimisticAttachment.mime,
        );
        final durableAttachment = privateTransferLease == null
            ? optimisticAttachment.copyWith(
                messageId: messageId,
                localPath: durableRelativePath,
                downloadStatus: 'upload_pending',
                ownerLane: MediaOwnerLane.direct,
              )
            : privatePendingAttachments[index];
        if (privateTransferLease != null &&
            durableRelativePath != durableAttachment.localPath) {
          throw StateError(
            'foreground private upload durable path is not canonical',
          );
        }
        final absoluteDurablePath = await mediaFileManager.resolveStoredPath(
          durableRelativePath,
        );
        if (privateTransferLease == null) {
          await mediaAttachmentRepo.saveAttachment(
            durableAttachment,
            owner: MediaOwnerLane.direct,
          );
        }
        preparedUploads.add(
          _PreparedConversationMediaUpload(
            source: pending,
            pendingAttachment: durableAttachment,
            absoluteDurablePath: absoluteDurablePath,
          ),
        );
      }

      final transferLease = privateTransferLease;
      if (transferLease != null) {
        if (mediaAttachmentRepo is! OutgoingDirectPrivateMutationRepository) {
          throw StateError(
            'foreground private upload preparation capability disappeared',
          );
        }
        final mutationRepository =
            mediaAttachmentRepo as OutgoingDirectPrivateMutationRepository;
        final result = await mutationRepository
            .prepareOutgoingDirectPrivatePendingAttachments(
              privatePendingAttachments,
            );
        if (result != OutgoingDirectPrivatePendingPreparationOutcome.inserted) {
          throw OutgoingDirectPrivatePendingPreparationRefused(result);
        }
      }
    } catch (error) {
      final transferLease = privateTransferLease;
      if (transferLease != null) {
        try {
          // The typed batch insert is all-or-none. Re-read under its exact
          // lifecycle lock before unlinking so an exception after a committed
          // insert preserves every still-authoritative file, while a refusal
          // or pre-insert copy failure removes only untracked convention paths.
          await transferLease.coordinator.lifecycleLock.synchronizedAll(
            () async {
              final durableRows = await mediaAttachmentRepo
                  .getAttachmentsForMessage(
                    messageId,
                    owner: MediaOwnerLane.direct,
                  );
              final untrackedPaths = privatePendingAttachments
                  .where(
                    (pending) => !durableRows.any(
                      (row) =>
                          row.id == pending.id &&
                          row.messageId == pending.messageId &&
                          row.ownerLane == MediaOwnerLane.direct &&
                          row.localPath == pending.localPath,
                    ),
                  )
                  .map((pending) => pending.localPath)
                  .toList(growable: false);
              await mediaFileManager.deleteOwnedPendingUploadFilesForMessage(
                messageId: messageId,
                storedPaths: untrackedPaths,
              );
              for (final storedPath in untrackedPaths) {
                if (storedPath == null || storedPath.isEmpty) continue;
                final resolved = await mediaFileManager.resolveStoredPath(
                  storedPath,
                );
                if (await FileSystemEntity.type(resolved, followLinks: false) !=
                    FileSystemEntityType.notFound) {
                  throw StateError(
                    'foreground private upload copied-file compensation '
                    'was incomplete',
                  );
                }
              }
            },
          );
        } catch (compensationError) {
          throw StateError(
            'foreground private upload preparation failed and copied-file '
            'compensation failed: $error; compensation: $compensationError',
          );
        }
      }
      rethrow;
    }

    await Future<void>.delayed(Duration.zero);
    return preparedUploads;
  }

  Future<MediaAttachment> _buildLocalSuccessAttachmentFromPlan({
    required String messageId,
    required _PreparedConversationMediaUpload plan,
  }) async {
    final mediaFileManager = widget.mediaFileManager;
    if (mediaFileManager == null) {
      return plan.pendingAttachment.copyWith(
        messageId: messageId,
        size: plan.source.budgetBytes,
        localPath: plan.absoluteDurablePath,
        downloadStatus: 'done',
      );
    }

    final absoluteOwnedPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: _contact.peerId,
      blobId: plan.pendingAttachment.id,
      mime: plan.pendingAttachment.mime,
    );
    final sourceFile = File(plan.absoluteDurablePath);
    if (!await sourceFile.exists()) {
      return plan.pendingAttachment.copyWith(
        messageId: messageId,
        size: plan.source.budgetBytes,
        localPath: plan.absoluteDurablePath,
        downloadStatus: 'done',
      );
    }
    if (absoluteOwnedPath != plan.absoluteDurablePath) {
      final targetFile = File(absoluteOwnedPath);
      final parent = targetFile.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await sourceFile.copy(absoluteOwnedPath);
    }

    return plan.pendingAttachment.copyWith(
      messageId: messageId,
      size: plan.source.budgetBytes,
      localPath: mediaFileManager.relativePathForAttachment(
        contactPeerId: _contact.peerId,
        blobId: plan.pendingAttachment.id,
        mime: plan.pendingAttachment.mime,
      ),
      downloadStatus: 'done',
    );
  }

  /// 354: promotes the exact convention-pending plaintext to its canonical
  /// private path without network work or re-encryption, then preserves the
  /// strict generation's key, nonce, hashes and blob commitment byte-for-byte.
  ///
  /// Only the canonical local path may differ from the strict projection; any
  /// crypto drift between the published v111 generation and this completion is
  /// a hard refusal rather than a silent overwrite.
  Future<MediaAttachment> _canonicalizeStrictPrivateCompletion({
    required String messageId,
    required _PreparedConversationMediaUpload plan,
    required MediaAttachment strict,
  }) async {
    if (strict.id != plan.pendingAttachment.id ||
        strict.mime != plan.pendingAttachment.mime ||
        strict.size != plan.pendingAttachment.size ||
        strict.mediaType != plan.pendingAttachment.mediaType ||
        strict.blobCustody == null ||
        strict.contentHash == null ||
        strict.encryptionKeyBase64 == null ||
        strict.encryptionNonce == null ||
        strict.encryptionScheme == null) {
      throw StateError('private strict completion identity drifted');
    }
    final canonical = await _buildLocalSuccessAttachmentFromPlan(
      messageId: messageId,
      plan: plan,
    );
    final canonicalPath = canonical.localPath;
    if (canonicalPath == null || canonicalPath.isEmpty) {
      throw StateError('private strict completion has no canonical path');
    }
    return strict.copyWith(
      messageId: messageId,
      localPath: canonicalPath,
      downloadStatus: 'done',
      ownerLane: MediaOwnerLane.direct,
    );
  }

  Future<MediaAttachment> _finalizeUploadedAttachmentFromPlan({
    required String messageId,
    required _PreparedConversationMediaUpload plan,
    required MediaAttachment uploaded,
    required bool trustUploadedLocalPath,
    required bool enforceAuthoredIdentity,
  }) async {
    if (enforceAuthoredIdentity &&
        !_isExactAuthoredUploadResult(
          messageId: messageId,
          authored: plan.pendingAttachment,
          uploaded: uploaded,
        )) {
      throw StateError('ordinary media upload changed authored identity');
    }
    final stableAttachment = trustUploadedLocalPath
        ? plan.pendingAttachment
        : await _buildLocalSuccessAttachmentFromPlan(
            messageId: messageId,
            plan: plan,
          );
    return stableAttachment.copyWith(
      messageId: messageId,
      localPath: trustUploadedLocalPath
          ? uploaded.localPath
          : stableAttachment.localPath,
      downloadStatus: 'done',
      contentHash: uploaded.contentHash,
      thumbnailHash: uploaded.thumbnailHash,
      encryptionKeyBase64: uploaded.encryptionKeyBase64,
      encryptionNonce: uploaded.encryptionNonce,
      encryptionScheme: uploaded.encryptionScheme,
      ownerLane: MediaOwnerLane.direct,
    );
  }

  bool _isExactAuthoredUploadResult({
    required String messageId,
    required MediaAttachment authored,
    required MediaAttachment uploaded,
  }) {
    final authoredWaveform = authored.waveform;
    final uploadedWaveform = uploaded.waveform;
    final sameWaveform =
        identical(authoredWaveform, uploadedWaveform) ||
        (authoredWaveform != null &&
            uploadedWaveform != null &&
            authoredWaveform.length == uploadedWaveform.length &&
            authoredWaveform.indexed.every(
              (entry) => entry.$2 == uploadedWaveform[entry.$1],
            ));
    return uploaded.id == authored.id &&
        (uploaded.messageId.isEmpty || uploaded.messageId == messageId) &&
        uploaded.mime == authored.mime &&
        uploaded.size == authored.size &&
        uploaded.mediaType == authored.mediaType &&
        uploaded.width == authored.width &&
        uploaded.height == authored.height &&
        uploaded.durationMs == authored.durationMs &&
        sameWaveform &&
        uploaded.downloadStatus == 'done';
  }

  Future<UploadRetryProjectionResult>
  _projectManifestBoundComposerUploadFailure({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required String failedAttachmentId,
    required UploadMediaFailed failure,
  }) async {
    final attachmentRepository = widget.mediaAttachmentRepo;
    final failureRepository =
        attachmentRepository is OutgoingDirectMediaCustodyFailureRepository
        ? attachmentRepository as OutgoingDirectMediaCustodyFailureRepository
        : null;
    if (failureRepository == null ||
        !failureRepository.supportsDirectMediaCustodyFailureProjection) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_MEDIA_CUSTODY_FAILURE_PROJECTION_UNAVAILABLE',
        details: const {},
      );
      return const UploadRetryProjectionResult.notApplied();
    }

    try {
      final freshParent = await widget.messageRepo.getMessage(
        expectedParent.id,
      );
      final freshAttachments = await attachmentRepository!
          .getAttachmentsForMessage(
            expectedParent.id,
            owner: MediaOwnerLane.direct,
          );
      if (freshParent == null ||
          !_sameComposerDatabaseMap(
            expectedParent.toMap(),
            freshParent.toMap(),
          ) ||
          !_sameComposerAttachmentProjection(
            expectedAttachments,
            freshAttachments,
          )) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_MEDIA_CUSTODY_FAILURE_PROJECTION_CROSSED',
          details: const {},
        );
        return const UploadRetryProjectionResult.notApplied();
      }

      final projected = await failureRepository
          .projectDirectMediaCustodyUploadFailure(
            expectedParent: freshParent,
            expectedAttachments: freshAttachments,
            failedAttachmentId: failedAttachmentId,
            failure: failure,
          );
      if (!projected.applied) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_MEDIA_CUSTODY_FAILURE_PROJECTION_REFUSED',
          details: const {},
        );
      }
      return projected;
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_MEDIA_CUSTODY_FAILURE_PROJECTION_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      return const UploadRetryProjectionResult.notApplied();
    }
  }

  bool _sameComposerAttachmentProjection(
    List<MediaAttachment> expected,
    List<MediaAttachment> current,
  ) {
    if (expected.length != current.length) return false;
    final currentById = <String, MediaAttachment>{
      for (final attachment in current) attachment.id: attachment,
    };
    return currentById.length == current.length &&
        expected.every((attachment) {
          final fresh = currentById[attachment.id];
          return fresh != null &&
              _sameComposerDatabaseMap(attachment.toMap(), fresh.toMap());
        });
  }

  bool _sameComposerDatabaseMap(
    Map<String, Object?> expected,
    Map<String, Object?> current,
  ) =>
      expected.length == current.length &&
      expected.entries.every((entry) => current[entry.key] == entry.value);

  bool _sameComposerAuthoredPendingProjection(
    List<MediaAttachment> authored,
    List<MediaAttachment> persisted,
  ) {
    if (authored.length != persisted.length) return false;
    final persistedById = <String, MediaAttachment>{
      for (final attachment in persisted) attachment.id: attachment,
    };
    if (persistedById.length != persisted.length) return false;
    return authored.every((attachment) {
      final current = persistedById[attachment.id];
      if (current == null) return false;
      final authoredMap = attachment.toMap()
        ..['upload_retry_count'] = attachment.uploadRetryCount ?? 0
        ..['download_retry_count'] = attachment.downloadRetryCount ?? 0;
      final currentMap = current.toMap()
        ..['upload_retry_count'] = current.uploadRetryCount ?? 0
        ..['download_retry_count'] = current.downloadRetryCount ?? 0;
      return _sameComposerDatabaseMap(authoredMap, currentMap);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appLifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.detached;
    _contact = widget.contact;
    _bindOutgoingCallAvailability();
    _uploadActivityController =
        ConversationUploadActivityController<_DirectComposerSnapshot>(
          scopeId: widget.contact.peerId,
          resolveActiveOwners: _activeVisualUploadOwnersByAttachmentId,
          acquireWake: UploadWakeLockController.acquire,
          releaseWake: UploadWakeLockController.release,
        );
    _voiceCaptureController = ConversationVoiceCaptureController(
      onAutoStopOutcome: _onVoiceCaptureAutoStopOutcome,
    );
    _uploadActivityController.addListener(_onControllerInvalidated);
    _reactionProjectionController.addListener(_onControllerInvalidated);
    _voiceCaptureController.addListener(_onVoiceCaptureStateChanged);
    _uploadActivityController.bindProgressStream(mediaUploadProgressStream);
    final outboxController = widget.privateMediaOutboxE2EController;
    if (outboxController != null && outboxController.enabled) {
      _privateMediaOutboxE2EEndpointToken = outboxController.registerEndpoint(
        _runPrivateMediaOutboxE2E,
      );
    }
    _draftText = widget.initialText ?? '';
    widget.appShellController?.addListener(_onAppShellChanged);
    widget.conversationTracker?.setActive(widget.contact.peerId);
    // A cold notification launch can construct this route while Flutter still
    // reports `inactive`, then publish `resumed` before this State registers as
    // an observer. Re-check after the first rendered frame; the shared strict
    // predicate below still requires resumed + the exact tracked peer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_markAsRead());
    });
    _updateComposerState(
      pendingAttachments: _composerController.pendingAttachments,
    );
    final initialPendingMedia = widget.initialPendingMedia;
    final initialAttachments = widget.initialAttachments;
    if (initialPendingMedia != null && initialPendingMedia.isNotEmpty) {
      final seeded = _seedInitialPendingMediaIfWithinBudget(
        initialPendingMedia,
      );
      if (!seeded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_hydrateInitialPendingMedia(initialPendingMedia));
        });
      }
    } else if (initialAttachments != null && initialAttachments.isNotEmpty) {
      final prepared = _prepareLegacyInitialAttachmentsSync(initialAttachments);
      final seeded = prepared.isNotEmpty
          ? _seedInitialPendingMediaIfWithinBudget(prepared)
          : false;
      if (!seeded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_hydrateLegacyInitialAttachments(initialAttachments));
        });
      }
    }
    final debugInitialPrivateMediaPolicy =
        debugConversationWiredInitialPrivateMediaPolicy;
    debugConversationWiredInitialPrivateMediaPolicy = null;
    if (debugInitialPrivateMediaPolicy?.isPrivate ?? false) {
      _privateMediaPolicy = debugInitialPrivateMediaPolicy!;
      _updateComposerState(privateMediaPolicy: debugInitialPrivateMediaPolicy);
    }
    emitFlowEvent(layer: 'FL', event: 'CONV_FL_SCREEN_INIT', details: {});
    _scrollController.addListener(_onScroll);
    _loadIdentity();
    if (widget.initialMessages != null) {
      _messages = widget.initialMessages!;
      _hasMoreOlderMessages = _messages.length >= _pageSize;
      _scrollToBottom();
      _markAsRead();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _initialLoadDone = true);
          _emitNotificationTapTimingIfNeeded();
        }
      });
    } else {
      _loadInitialPage().then((_) => _markAsRead());
    }
    _startListeningForMessages();
    _startListeningForOutgoingMessageChanges();
    _startListeningForContactUpdates();
    _startListeningForReactions();
    _checkIntroBanner();
    _checkHasOtherFriends();
    // 131: a notification tap opens this screen before the relay offline inbox
    // has been drained, so the one-shot DB read above renders stale history
    // missing the just-received message. The live incoming stream has no replay
    // and nothing re-reads the DB on entry, so recover by draining and
    // re-fetching the latest page once (scrolling to the new message, since the
    // user tapped a notification expecting to see it).
    if (widget.notificationTappedAt != null) {
      unawaited(_drainAndReloadOnce('notif_tap', scrollToLiveEdge: true));
    }
    // FDC-04: eagerly warm the open peer so the first send hits the reuse fast
    // path instead of paying a cold discover->dial->send. UNCONDITIONAL — every
    // open warms (not just notif-tap opens). Speculative + fire-and-forget:
    // warmPeer is a no-op when the node isn't started (PS-3), never sends or
    // inboxes (PS-1), is debounced per peer, and is total/never-throws.
    unawaited(widget.p2pService.warmPeer(widget.contact.peerId));
    // 172 (INV-2): surface any kept-but-undisplayed staged entries on open.
    unawaited(_refreshUndeliveredAttentionCount());
  }

  bool _notificationTimingEmitted = false;

  // 145: separate one-shot latch for the post-drain ("live") render timing,
  // emitted once when a notif-tap drain actually surfaces a new incoming
  // message — distinct from the stale-render latch above.
  bool _notificationLiveTimingEmitted = false;

  void _emitNotificationTapTimingIfNeeded() {
    final tappedAt = widget.notificationTappedAt;
    if (tappedAt == null || _notificationTimingEmitted) return;
    _notificationTimingEmitted = true;
    emitNotificationTapTiming(tappedAt: tappedAt, routeKind: 'conversation');
  }

  void _onControllerInvalidated() {
    if (mounted) setState(() {});
  }

  void _onVoiceCaptureStateChanged() {
    if (!mounted) return;
    final voiceState = _voiceCaptureController.state;
    final recordingState = switch (voiceState.phase) {
      ConversationVoiceCapturePhase.idle => VoiceRecordingState.idle,
      ConversationVoiceCapturePhase.arming => VoiceRecordingState.arming,
      ConversationVoiceCapturePhase.recording => VoiceRecordingState.recording,
      ConversationVoiceCapturePhase.stopping => VoiceRecordingState.stopping,
    };
    _updateComposerState(
      recordingState: recordingState,
      recordingDuration: voiceState.duration,
      amplitudeValues: voiceState.amplitudeValues,
    );
  }

  Future<bool> _confirmLeaveWhileUploadActive() async {
    if (!_uploadActivityController.isTracking || !mounted) return true;
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.upload_leave_title),
          content: Text(l10n.upload_leave_body),
          actions: [
            TextButton(
              key: const ValueKey('upload-leave-stay'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.upload_leave_stay),
            ),
            FilledButton(
              key: const ValueKey('upload-leave-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.upload_leave_confirm),
            ),
          ],
        );
      },
    );
    return shouldLeave ?? false;
  }

  Future<void> _handleBackNavigation() async {
    final uploadWasActive = _uploadActivityController.isTracking;
    final shouldPop = await _confirmLeaveWhileUploadActive();
    if (!shouldPop || !mounted) return;
    if (uploadWasActive) {
      // Detach publication without terminally completing the retained
      // operation. Its async owner still releases the exact wake hold.
      _uploadActivityController.detachView();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    Navigator.of(context).pop();
  }

  void _requestCancelActiveAttachmentUpload() {
    _uploadActivityController.requestCancelActive();
  }

  Future<bool> _cancelActiveAttachmentUploadIfRequested({
    required ConversationUploadOperation<_DirectComposerSnapshot> operation,
  }) {
    if (!_uploadActivityController.cancellationRequestedFor(operation)) {
      return Future<bool>.value(false);
    }
    return _uploadActivityController.finalizeCancellation(operation);
  }

  Future<bool> _markUploadPendingAttachmentsCancelledForMessage(
    String messageId, {
    required PrivateMediaPolicy privateMediaPolicy,
  }) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    if (mediaAttachmentRepo == null) {
      return !_isOutgoingPrivateOneMoreLook(privateMediaPolicy);
    }

    Future<bool> applyCancellation() async {
      if (!await _terminalizeOutgoingDirectMediaBlobForCancellation(
        messageId,
      )) {
        return false;
      }

      final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      var pendingFound = false;
      for (final attachment in attachments) {
        if (attachment.downloadStatus != 'upload_pending') {
          continue;
        }
        pendingFound = true;
        final cancelled = attachment.copyWith(
          downloadStatus: 'upload_cancelled',
        );
        if (mediaAttachmentRepo is OutgoingDirectPrivateMutationRepository) {
          final privateMutationRepo =
              mediaAttachmentRepo as OutgoingDirectPrivateMutationRepository;
          final result = await privateMutationRepo
              .applyOutgoingDirectPrivateNonCompletionMutation(cancelled);
          if (result ==
              OutgoingDirectPrivateNonCompletionMutationOutcome.applied) {
            continue;
          }
          if (result !=
              OutgoingDirectPrivateNonCompletionMutationOutcome
                  .notPrivateParent) {
            return false;
          }
        } else if (_isOutgoingPrivateOneMoreLook(privateMediaPolicy)) {
          return false;
        }
        await mediaAttachmentRepo.saveAttachment(
          cancelled,
          owner: MediaOwnerLane.direct,
        );
      }
      return pendingFound || !_isOutgoingPrivateOneMoreLook(privateMediaPolicy);
    }

    if (mediaAttachmentRepo is DirectMediaBlobCustodyRepository) {
      final custodyRepository =
          mediaAttachmentRepo as DirectMediaBlobCustodyRepository;
      if (custodyRepository.supportsDirectMediaBlobCustody) {
        return custodyRepository.runDirectMediaBlobCustodyLifecycle(
          applyCancellation,
        );
      }
    }
    return applyCancellation();
  }

  Future<bool> _terminalizeOutgoingDirectMediaBlobForCancellation(
    String messageId,
  ) async {
    final repository = widget.mediaAttachmentRepo;
    if (repository is! DirectMediaBlobCustodyRepository) return true;
    final custodyRepository = repository as DirectMediaBlobCustodyRepository;
    if (!custodyRepository.supportsDirectMediaBlobCustody) return true;
    if (repository is! OutgoingDirectMediaBlobTerminalizationRepository) {
      return false;
    }
    final terminalizationRepository =
        repository as OutgoingDirectMediaBlobTerminalizationRepository;
    if (!custodyRepository.supportsDirectMediaBlobCustody ||
        !terminalizationRepository
            .supportsOutgoingDirectMediaBlobTerminalization) {
      return false;
    }
    return custodyRepository.runDirectMediaBlobCustodyLifecycle(() async {
      final allRows = await custodyRepository
          .loadDirectMediaBlobCustodyForMessage(messageId);
      if (allRows.isEmpty) return true;
      final outgoingRows = allRows
          .where(
            (row) => row.direction == DirectMediaBlobCustodyDirection.outgoing,
          )
          .toList(growable: false);
      if (outgoingRows.length != allRows.length) return false;
      final outcome = await terminalizationRepository
          .terminalizeOutgoingDirectMediaBlobGenerationIfExact(
            expectedRows: outgoingRows,
            reason: DirectMediaBlobTerminalizationReason.explicitCancellation,
            nowMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
      return outcome.publishedCleanupAuthority;
    });
  }

  Future<void> _hydrateInitialPendingMedia(
    List<PendingComposerMedia> initialPendingMedia,
  ) async {
    final accepted = await _resolvePendingMediaCandidates(
      candidateAttachments: initialPendingMedia,
    );
    if (!mounted || accepted == null || accepted.isEmpty) return;
    _updateComposerState(pendingAttachments: accepted);
  }

  bool _seedInitialPendingMediaIfWithinBudget(
    List<PendingComposerMedia> initialPendingMedia,
  ) {
    if (initialPendingMedia.isEmpty) return false;
    final totalBudgetBytes = totalPendingComposerBudgetBytes(
      initialPendingMedia,
    );
    if (totalBudgetBytes > widget.maxAttachmentBudgetBytes) {
      return false;
    }
    _updateComposerState(pendingAttachments: initialPendingMedia);
    return true;
  }

  List<PendingComposerMedia> _prepareLegacyInitialAttachmentsSync(
    List<File> attachments,
  ) {
    final prepared = <PendingComposerMedia>[];
    for (final attachment in attachments) {
      if (!attachment.existsSync()) continue;
      try {
        prepared.add(
          PendingComposerMedia(
            file: attachment,
            budgetBytes: attachment.lengthSync(),
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return prepared;
  }

  Future<void> _hydrateLegacyInitialAttachments(List<File> attachments) async {
    final prepared = _prepareLegacyInitialAttachmentsSync(attachments);
    if (prepared.isEmpty) {
      for (final attachment in attachments) {
        if (!await attachment.exists()) continue;
        prepared.add(
          PendingComposerMedia(
            file: attachment,
            budgetBytes: await attachment.length(),
          ),
        );
      }
    }
    if (prepared.isEmpty) return;
    await _hydrateInitialPendingMedia(prepared);
  }

  Future<void> _attemptAddPendingMedia(
    List<PendingComposerMedia> candidateAttachments,
  ) async {
    final accepted = await _resolvePendingMediaCandidates(
      candidateAttachments: candidateAttachments,
    );
    if (!mounted || accepted == null || accepted.isEmpty) return;
    _updateComposerState(
      pendingAttachments: [
        ..._composerController.pendingAttachments,
        ...accepted,
      ],
    );
  }

  Future<List<PendingComposerMedia>?> _resolvePendingMediaCandidates({
    required List<PendingComposerMedia> candidateAttachments,
  }) async {
    if (candidateAttachments.isEmpty) return const [];

    final combinedBudgetBytes = totalPendingComposerBudgetBytes([
      ..._composerController.pendingAttachments,
      ...candidateAttachments,
    ]);
    if (combinedBudgetBytes <= widget.maxAttachmentBudgetBytes) {
      return candidateAttachments;
    }

    final shouldCompress = await _showAttachmentOverflowDialog(
      totalBudgetBytes: combinedBudgetBytes,
    );
    if (shouldCompress != true) {
      return null;
    }

    final compressedCandidates = <PendingComposerMedia>[];
    for (final candidate in candidateAttachments) {
      compressedCandidates.add(
        await _preparePendingMedia(
          candidate.file.path,
          imageQualityPreference: ImageQualityPreference.compressed,
          videoQualityPreference: ImageQualityPreference.compressed,
        ),
      );
    }

    final compressedBudgetBytes = totalPendingComposerBudgetBytes([
      ..._composerController.pendingAttachments,
      ...compressedCandidates,
    ]);
    if (compressedBudgetBytes > widget.maxAttachmentBudgetBytes) {
      _showAttachmentTooLargeMessage();
      return null;
    }

    return compressedCandidates;
  }

  Future<bool?> _showAttachmentOverflowDialog({required int totalBudgetBytes}) {
    final formattedTotal = formatPendingComposerBudgetBytes(totalBudgetBytes);
    final formattedLimit = formatPendingComposerBudgetBytes(
      widget.maxAttachmentBudgetBytes,
    );
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.media_too_large_title),
          content: Text(
            l10n.media_too_large_prompt(formattedTotal, formattedLimit),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.btn_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.media_compress),
            ),
          ],
        );
      },
    );
  }

  void _showAttachmentTooLargeMessage() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.media_too_large_after_compress,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<PendingComposerMedia> _preparePendingMedia(
    String path, {
    ImageQualityPreference? imageQualityPreference,
    ImageQualityPreference? videoQualityPreference,
    bool ownsProcessingLifecycle = true,
  }) async {
    // GIF is no longer special-cased on raw pre-compression bytes here; it flows
    // through the same single send-time per-type size gate as every other type,
    // validated on final budget bytes (INV-SZ-2).
    final processor = widget.imageProcessor;
    final isVideo = processor?.isProcessableVideo(path) ?? false;
    if (isVideo && ownsProcessingLifecycle) {
      _updateComposerState(
        isProcessing: true,
        processingProgress: 0.0,
        processingCurrent: 0,
        processingTotal: 0,
      );
    }

    try {
      return await preparePendingComposerMedia(
        inputPath: path,
        imageProcessor: processor,
        imageQualityPreference:
            imageQualityPreference ?? widget.qualityPreference,
        videoQualityPreference:
            videoQualityPreference ?? widget.videoQualityPreference,
        onVideoProgress: (progress) {
          if (mounted) {
            _updateComposerState(processingProgress: progress / 100.0);
          }
        },
      );
    } finally {
      if (isVideo && ownsProcessingLifecycle && mounted) {
        _updateComposerState(
          isProcessing: false,
          processingProgress: 0.0,
          processingCurrent: 0,
          processingTotal: 0,
        );
      }
    }
  }

  /// Per-type SEND size gate for 1:1 media (OQ-2 — the per-type cap table now
  /// applies to 1:1 + share, not just groups). Validates EACH pending
  /// attachment's final (post-compression) budget bytes against its per-type cap
  /// and returns the FULL set of failures ({index, normalized reason}) — empty
  /// when every attachment is within its cap. Snackbar-free: the inline composer
  /// reject-chip (149) carries the reason. Used both at pick time (to mark the
  /// chip) and as a defensive re-check in [_onSend].
  List<MediaRejection> _validatePendingMediaSizes(
    List<PendingComposerMedia> media,
  ) {
    return collectPendingMediaSizeRejections(media, _mimeFromPath);
  }

  Future<void> _checkIntroBanner() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    final show = await shouldShowIntroBanner(
      contactRepo: contactRepo,
      contact: _contact,
      messageCount: _messages.length,
    );
    if (mounted && show != _showIntroBanner) {
      setState(() => _showIntroBanner = show);
    }
  }

  Future<void> _checkHasOtherFriends() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    final activeContacts = await contactRepo.getActiveContacts();
    final others = activeContacts
        .where((c) => c.peerId != _contact.peerId && !c.isBlocked)
        .toList();
    if (mounted) {
      setState(() => _hasOtherFriends = others.isNotEmpty);
    }
  }

  Future<void> _onMaybeLater() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    await contactRepo.dismissIntroBanner(_contact.peerId);
    if (mounted) {
      setState(() => _showIntroBanner = false);
      _contact = _contact.copyWith(introsBannerDismissed: true);
    }
  }

  void _onMakeIntroductions() {
    // The FriendPickerWired integration is handled at a higher level.
    // For now, this triggers the same flow as the overflow menu introduce action.
    _onIntroduce();
  }

  void _onIntroduce() {
    final introRepo = widget.introductionRepository;
    final contactRepo = widget.contactRepo;
    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_INTRODUCE_TAP',
      details: {
        'introRepoNull': introRepo == null,
        'contactRepoNull': contactRepo == null,
        'bridgeNull': widget.bridge == null,
      },
    );
    if (introRepo == null || contactRepo == null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_INTRODUCE_TRIGGERED',
      details: {'contactPeerId': _contact.peerId},
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FriendPickerWired(
        recipient: _contact,
        contactRepo: contactRepo,
        introRepo: introRepo,
        p2pService: widget.p2pService,
        bridge: widget.bridge!,
        identityRepo: widget.identityRepo,
        backgroundPreference:
            widget.appShellController?.backgroundPreference ??
            BackgroundPreference.defaultBackground,
        onIntroductionsSent: (intros) {
          // Insert system message into conversation history
          final identity = _identity;
          if (identity != null && intros.isNotEmpty) {
            insertIntroSystemMessage(
              messageRepo: widget.messageRepo,
              contactPeerId: _contact.peerId,
              text: formatIntroducerIntroductionSystemMessage(
                recipientUsername: _contact.username,
                introducedUsernames: intros
                    .map((intro) => intro.introducedUsername ?? '')
                    .toList(growable: false),
              ),
              ownPeerId: identity.peerId,
            ).then((_) {
              if (mounted) _loadInitialPage();
            });
          }
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SentConfirmationWired(
                introductionCount: intros.length,
                introducedUsernames: intros
                    .map((i) => i.introducedUsername ?? 'Unknown')
                    .toList(),
                onBackToConversation: () => Navigator.of(context).pop(),
                backgroundPreference:
                    widget.appShellController?.backgroundPreference ??
                    BackgroundPreference.defaultBackground,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadIdentity() async {
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity != null && mounted) {
        setState(() => _identity = identity);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_IDENTITY_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadInitialPage() async {
    try {
      final messages = await loadConversationPage(
        messageRepo: widget.messageRepo,
        contactPeerId: _contact.peerId,
        pageSize: _pageSize,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
        mediaFileManager: widget.mediaFileManager,
      );
      if (mounted) {
        setState(() {
          for (final message in messages) {
            _upsertMessageById(_mergeLoadedMessageWithCurrentState(message));
          }
          _hasMoreOlderMessages = messages.length >= _pageSize;
        });
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_MESSAGES_LOADED',
          details: {'count': messages.length},
        );
        _scrollToBottom();
        await _loadReactions(messages);
        unawaited(_recoverVisibleMedia(messages));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _initialLoadDone = true);
            _emitNotificationTapTimingIfNeeded();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _initialLoadDone = true);
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  bool _drainReloadInFlight = false;
  bool _drainReloadPending = false;
  static const _notificationTapLateRefetchAttempts = 8;
  static const _notificationTapLateRefetchInterval = Duration(
    milliseconds: 250,
  );
  // 145: view-facing mirror of an in-flight drain — drives the "catching up…"
  // affordance. Mutated via setState (unlike the coalescing flags above).
  bool _isSyncingNewMessages = false;

  /// 131: drains the relay offline inbox then re-reads the latest page so a
  /// message that landed after the one-shot initial load (notification-tap
  /// entry, or app-resume while this screen is open) is surfaced. The live
  /// `incomingMessageStream` is a no-replay broadcast and the screen never
  /// re-fetched on entry/resume, so a message persisted in the pre-subscribe
  /// window was otherwise only visible on the next fresh open (orbit re-entry).
  /// Non-blocking and idempotent: the cached page is already on screen; the new
  /// message is upsert-merged in when the drain completes. A trigger arriving
  /// while a drain is in flight (e.g. a resume during a notif_tap drain) is
  /// coalesced into one more pass rather than dropped; only the FIRST pass may
  /// scroll to the live edge — coalesced re-runs stand in for resumes.
  Future<void> _drainAndReloadOnce(
    String trigger, {
    required bool scrollToLiveEdge,
  }) async {
    if (_drainReloadInFlight) {
      _drainReloadPending = true;
      return;
    }
    _drainReloadInFlight = true;
    try {
      // 145: surface the "catching up…" affordance while the relay round-trip
      // is in flight. Yield to a microtask first so a notif_tap drain launched
      // from initState does not call setState during the initial build.
      await Future<void>.value();
      if (mounted) {
        setState(() => _isSyncingNewMessages = true);
      }
      var first = true;
      do {
        _drainReloadPending = false;
        final before = _messages.length;
        final drainSw = Stopwatch()..start();
        var addedIncoming = false;
        try {
          await widget.p2pService.drainOfflineInbox();
          if (mounted) {
            addedIncoming = await _reloadLatestPageForRecovery(
              scrollToLiveEdge: first && scrollToLiveEdge,
            );
            // A background isolate can finish persisting the staged push just
            // after drainOfflineInbox and the first DB refetch return. Its
            // in-memory repository change stream is not shared with this UI
            // isolate, so poll the local DB briefly instead of leaving the
            // tapped conversation stale until it is reopened.
            if (trigger == 'notif_tap' && first && !addedIncoming) {
              addedIncoming = await _pollForLateNotificationTapPersistence(
                scrollToLiveEdge: scrollToLiveEdge,
              );
            }
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONV_FL_DRAIN_REFETCH_ERROR',
            details: {'trigger': trigger, 'error': e.toString()},
          );
        }
        drainSw.stop();
        // 145: emit the post-drain ("live") render milestone exactly once per
        // notif-tap, when the drain actually surfaced a new incoming message.
        // The one-shot latch guards against coalesced re-runs double-emitting.
        if (trigger == 'notif_tap' &&
            addedIncoming &&
            !_notificationLiveTimingEmitted) {
          final tappedAt = widget.notificationTappedAt;
          if (tappedAt != null) {
            _notificationLiveTimingEmitted = true;
            emitNotificationTapLiveRenderTiming(
              tappedAt: tappedAt,
              routeKind: 'conversation',
              addedIncoming: true,
            );
          }
        }
        if (mounted) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONV_FL_NOTIF_DRAIN_REFETCH',
            details: {
              'trigger': trigger,
              'before': before,
              'after': _messages.length,
              'drainMs': drainSw.elapsedMilliseconds,
            },
          );
        }
        first = false;
      } while (_drainReloadPending && mounted);
    } finally {
      _drainReloadInFlight = false;
      _drainReloadPending = false;
      if (mounted) {
        setState(() => _isSyncingNewMessages = false);
      }
      // 172 (INV-2): a drain may have quarantined new entries (or committed
      // previously-stuck ones) — refresh the couldn't-display count either way.
      unawaited(_refreshUndeliveredAttentionCount());
    }
  }

  Future<bool> _pollForLateNotificationTapPersistence({
    required bool scrollToLiveEdge,
  }) async {
    for (
      var attempt = 1;
      attempt <= _notificationTapLateRefetchAttempts;
      attempt++
    ) {
      if (_drainReloadPending) return false;
      await Future<void>.delayed(_notificationTapLateRefetchInterval);
      if (!mounted || _drainReloadPending) return false;

      final addedIncoming = await _reloadLatestPageForRecovery(
        scrollToLiveEdge: scrollToLiveEdge,
      );
      if (addedIncoming) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_NOTIF_LATE_REFETCH',
          details: {'attempt': attempt, 'addedIncoming': true},
        );
        return true;
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_NOTIF_LATE_REFETCH',
      details: {
        'attempt': _notificationTapLateRefetchAttempts,
        'addedIncoming': false,
      },
    );
    return false;
  }

  /// 172 (INV-2): reads the kept-but-undisplayed staged-entry count off the
  /// optional [InboxAttentionSignal] capability (hidden when the service
  /// doesn't implement it — e.g. simple test fakes). Never throws.
  Future<void> _refreshUndeliveredAttentionCount() async {
    final p2pService = widget.p2pService;
    if (p2pService is! InboxAttentionSignal) return;
    try {
      final count = await (p2pService as InboxAttentionSignal)
          .countNeedsAttentionInboxEntries();
      if (!mounted || count == _undeliveredAttentionCount) return;
      setState(() => _undeliveredAttentionCount = count);
    } catch (_) {
      // Best-effort surface; a count failure must never break the screen.
    }
  }

  /// 172: the banner's retry — re-drives the staged drain (a since-healed
  /// cause gets its message displayed) and re-reads the count.
  Future<void> _onRetryUndelivered() async {
    await _drainAndReloadOnce('undelivered_retry', scrollToLiveEdge: false);
  }

  /// Re-reads the latest page and upsert-merges it into the current list without
  /// disturbing already-loaded older (paginated) messages. Only scrolls to the
  /// live edge when [scrollToLiveEdge] is set AND a genuinely new row appeared,
  /// so an app-resume recovery never yanks a user who scrolled up.
  /// Returns whether a genuinely new incoming row was surfaced (145: the caller
  /// uses this to emit the post-drain live-render timing milestone).
  Future<bool> _reloadLatestPageForRecovery({
    required bool scrollToLiveEdge,
  }) async {
    final messages = await loadConversationPage(
      messageRepo: widget.messageRepo,
      contactPeerId: _contact.peerId,
      pageSize: _pageSize,
      mediaAttachmentRepo: widget.mediaAttachmentRepo,
      mediaFileManager: widget.mediaFileManager,
    );
    if (!mounted) return false;
    var addedIncoming = false;
    setState(() {
      for (final message in messages) {
        final existed = _messages.any((m) => m.id == message.id);
        _upsertMessageById(_mergeLoadedMessageWithCurrentState(message));
        if (!existed && message.isIncoming) addedIncoming = true;
      }
    });
    await _loadReactions(messages);
    unawaited(_recoverVisibleMedia(messages));
    if (addedIncoming) {
      _markAsRead();
      if (scrollToLiveEdge) _scrollToBottom();
    }
    return addedIncoming;
  }

  void _onScroll() {
    if (!_hasMoreOlderMessages || _isLoadingMore) return;
    if (!_scrollController.hasClients) return;
    // In a reversed ListView, minScrollExtent is the "top" (oldest messages)
    final position = _scrollController.position;
    if (position.pixels <= position.minScrollExtent + 200) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_messages.isEmpty || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final cursor = _messages.first.timestamp;
      final olderMessages = await loadConversationPage(
        messageRepo: widget.messageRepo,
        contactPeerId: _contact.peerId,
        pageSize: _pageSize,
        beforeTimestamp: cursor,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
        mediaFileManager: widget.mediaFileManager,
      );
      if (mounted) {
        setState(() {
          _messages = [...olderMessages, ..._messages];
          _hasMoreOlderMessages = olderMessages.length >= _pageSize;
          _isLoadingMore = false;
        });
        unawaited(_recoverVisibleMedia(olderMessages));
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_LOAD_MORE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _recoverVisibleMedia(List<ConversationMessage> messages) async {
    final bridge = widget.bridge;
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (bridge == null ||
        mediaAttachmentRepo == null ||
        mediaFileManager == null ||
        messages.isEmpty) {
      return;
    }

    for (final message in messages) {
      final currentParent = await widget.messageRepo.getMessage(message.id);
      final recoveryParent = currentParent ?? message;
      if (recoveryParent.mustClearTransientMedia ||
          recoveryParent.privateMediaPolicy.requiresRedaction) {
        continue;
      }
      final storedAttachments = await mediaAttachmentRepo
          .getAttachmentsForMessage(message.id, owner: MediaOwnerLane.direct);
      if (storedAttachments.isEmpty) {
        continue;
      }

      final displayAttachments = <MediaAttachment>[];
      var didMutateDisplayState = false;
      for (final attachment in storedAttachments) {
        final resolved = await _resolveAttachmentForDisplay(attachment);
        if (_shouldRecoverVisibleAttachment(resolved) &&
            await _autoDownloadAllowed(resolved)) {
          MediaAttachment? downloaded;
          try {
            downloaded = await widget.downloadMediaFn(
              bridge: bridge,
              mediaAttachmentRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              attachment: resolved,
              contactPeerId: message.contactPeerId,
              owner: MediaOwnerLane.direct,
              messageRepo: widget.messageRepo,
              intent: MediaDownloadIntent.automatic,
            );
          } catch (_) {
            downloaded = null;
          }
          MediaAttachment fallback;
          if (downloaded != null) {
            fallback = downloaded;
          } else {
            // Re-read the authoritative persisted status so a terminal
            // download_failed (relay not-found / budget exhausted) is never
            // downgraded back to a retryable `failed` in the UI — which would
            // re-arm recovery forever (INV-DL-1). Mirrors the group path.
            MediaAttachment? persisted;
            try {
              final rows = await mediaAttachmentRepo.getAttachmentsForMessage(
                message.id,
                owner: MediaOwnerLane.direct,
              );
              final matches = rows.where((a) => a.id == resolved.id);
              persisted = matches.isEmpty ? null : matches.first;
            } catch (_) {}
            fallback =
                persisted ??
                resolved.copyWith(downloadStatus: kMediaDownloadStatusFailed);
          }
          displayAttachments.add(fallback);
          didMutateDisplayState = true;
          continue;
        }

        displayAttachments.add(resolved);
        if (resolved.localPath != attachment.localPath ||
            resolved.downloadStatus != attachment.downloadStatus) {
          didMutateDisplayState = true;
        }
      }

      if (!didMutateDisplayState || !mounted) {
        continue;
      }

      final latestMessage = await widget.messageRepo.getMessage(message.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _upsertMessageById(
          (latestMessage ?? message).copyWith(media: displayAttachments),
        );
      });
    }
  }

  bool _shouldRecoverVisibleAttachment(MediaAttachment attachment) {
    return attachment.downloadStatus == kMediaDownloadStatusPending ||
        attachment.downloadStatus == kMediaDownloadStatusDownloading ||
        // A transient `failed` row is recoverable only while under the bounded
        // retry budget; the terminal `download_failed` is never re-recovered
        // (INV-DL-1) — mirrors the group recovery path.
        GroupMediaIntegrityPolicy.isRetryableDownloadFailure(attachment);
  }

  /// 229: policy check run immediately before each automatic recovery
  /// transfer. The storage owner is the typed lane the row was addressed
  /// under ([MediaOwnerLane.direct]); an untrusted-row policy throw fails
  /// closed (no transfer).
  Future<bool> _autoDownloadAllowed(MediaAttachment attachment) async {
    final decider =
        widget.autoDownloadDecider ?? defaultMediaAutoDownloadDecider;
    if (decider == null) return true;
    try {
      return await decider.shouldAutoDownload(
        conversationKind: MediaConversationKind.oneToOne,
        storageOwner: MediaOwnerLane.direct,
        mediaType: attachment.mediaType,
        downloadStatus: attachment.downloadStatus,
      );
    } catch (_) {
      return false;
    }
  }

  Future<MediaAttachment> _resolveAttachmentForDisplay(
    MediaAttachment attachment,
  ) async {
    final mediaFileManager = widget.mediaFileManager;
    if (mediaFileManager == null || attachment.localPath == null) {
      return attachment;
    }

    final absolutePath = await mediaFileManager.resolveStoredPath(
      attachment.localPath!,
    );
    if (_isPendingUploadPath(attachment.localPath!) ||
        _isPendingUploadPath(absolutePath)) {
      return attachment.copyWith(localPath: absolutePath);
    }
    final exists = await File(absolutePath).exists();
    if (!exists && attachment.downloadStatus == 'done') {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_DURABILITY_DONE_PATH_MISSING',
        details: {
          'attachmentId': attachment.id,
          'messageId': attachment.messageId,
          'mime': attachment.mime,
          'mediaType': attachment.mediaType,
          'storedPath': attachment.localPath,
          'resolvedPath': absolutePath,
          'nextStatus': 'pending',
        },
      );
      try {
        await widget.mediaAttachmentRepo?.updateDownloadStatus(
          attachment.id,
          'pending',
        );
      } catch (_) {}
      return attachment.copyWith(
        localPath: absolutePath,
        downloadStatus: 'pending',
      );
    }

    return attachment.copyWith(localPath: absolutePath);
  }

  bool _isPendingUploadPath(String path) {
    return path.contains('pending_uploads/') ||
        path.contains('pending_uploads\\');
  }

  Future<void> _markAsRead() async {
    final tracker = widget.conversationTracker;
    if (_appLifecycleState != AppLifecycleState.resumed ||
        tracker == null ||
        !tracker.isViewing(_contact.peerId)) {
      return;
    }
    try {
      await markConversationRead(
        messageRepo: widget.messageRepo,
        contactPeerId: _contact.peerId,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_MARK_READ_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _startListeningForMessages() {
    _incomingSubscription = widget.chatMessageListener.incomingMessageStream
        .where((msg) => msg.contactPeerId == _contact.peerId)
        .listen(
          _onIncomingMessage,
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_CHAT_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
          onDone: () {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_CHAT_STREAM_DONE',
              details: {},
            );
          },
        );
  }

  void _startListeningForOutgoingMessageChanges() {
    final messageRepo = widget.messageRepo;
    if (messageRepo is! MessageRepositoryChangeSource) {
      return;
    }

    final changeSource = messageRepo as MessageRepositoryChangeSource;
    _repoChangeSubscription = changeSource.messageChanges
        .where(
          (message) =>
              message.contactPeerId == _contact.peerId &&
              // 131: also accept INCOMING inserts. saveMessage emits every save
              // (incoming included) on this durable stream, so a message
              // persisted by the relay drain while the screen is open surfaces
              // here even if the no-replay incomingMessageStream emit was missed
              // — previously only outgoing status changes / deletes refreshed.
              (message.isIncoming ||
                  (!message.isIncoming &&
                      _shouldRefreshFromRepositoryChange(message.status)) ||
                  message.isDeleted),
        )
        .listen(
          (message) async {
            if (!mounted) return;
            final alreadyShown = _messages.any((m) => m.id == message.id);

            // 156 QW-9 (reactive-streams-2): only read attachments when there is
            // media to hydrate that is not already shown. The common case — a
            // pure text/status update to an already-rendered message
            // (sent→delivered→read) — declares no new attachment id, so the
            // per-event getAttachments DB read is skipped (the merge below
            // preserves any already-hydrated media). A NEW message (incl. a
            // relay-drained media message whose inline media is empty but whose
            // attachments live in-table) is NOT already shown → it still
            // resolves. Media enrichment of an existing visible message flows
            // through _recoverVisibleMedia, not this stream.
            final shownMediaIds = <String>{
              for (final shown in _messages)
                if (shown.id == message.id)
                  for (final attachment in shown.media) attachment.id,
            };
            final hasUnresolvedMedia = message.media.any(
              (attachment) => !shownMediaIds.contains(attachment.id),
            );
            final shouldResolveMedia = !alreadyShown || hasUnresolvedMedia;

            final hydratedMedia = (message.isDeleted || !shouldResolveMedia)
                ? message.media
                : await _resolveHydratedMediaForMessage(
                    message.id,
                    fallbackMedia: message.media,
                  );
            if (!mounted) return;
            // 159: queue the upsert for the per-frame flush instead of a direct
            // per-event setState. Media merging against the latest state happens
            // at flush time (mergeMedia: true). markAsRead is requested only for
            // a genuinely new incoming row (preserves the pre-coalesce gate).
            _enqueueCoalescedUpsert(
              message.copyWith(media: hydratedMedia),
              mergeMedia: true,
              markRead: message.isIncoming && !alreadyShown,
            );
          },
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_REPO_CHANGE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );
  }

  bool _shouldRefreshFromRepositoryChange(String status) =>
      status == 'sent' ||
      status == 'delivered' ||
      status == 'failed' ||
      status == 'inboxed';

  void _onIncomingMessage(ConversationMessage message) {
    if (!mounted) return;
    // 159: queue for the per-frame flush. The live-stream side effects
    // (scroll-to-live-edge iff this becomes the new edge, markAsRead, and the
    // intro-banner auto-dismiss) run once-per-flush against the POST-batch state
    // in [_flushCoalescedUpserts] — never per queued event.
    _enqueueCoalescedUpsert(
      message,
      mergeMedia: false,
      markRead: true,
      introCheck: true,
      liveEdgeCandidate: true,
    );
  }

  /// 159: apply a message upsert to [_messages] SYNCHRONOUSLY (preserving its
  /// ordering with any other synchronous `_messages` mutation, e.g. an
  /// upload-cancel/restore), but defer the expensive SORT + setState + the
  /// per-event live-stream side effects to ONE per-frame flush. That is the
  /// storm collapse: a relay-drain burst of M events does M cheap synchronous
  /// merges but only ONE sort + ONE rebuild + ONE markAsRead/scroll/intro pass.
  void _enqueueCoalescedUpsert(
    ConversationMessage message, {
    required bool mergeMedia,
    bool markRead = false,
    bool introCheck = false,
    bool liveEdgeCandidate = false,
  }) {
    _upsertIntoMessagesUnsorted(message, mergeMedia: mergeMedia);
    _uploadActivityController.refreshOwnerProjection(publish: false);
    _coalesceNeedsFlush = true;
    if (markRead) _coalesceWantsMarkRead = true;
    if (introCheck) _coalesceWantsIntroCheck = true;
    // A hidden row is removed from _messages, so it can never be the post-batch
    // live edge — do not register it as a scroll-to-edge candidate.
    if (liveEdgeCandidate && !message.isHidden) {
      _coalesceLiveEdgeCandidateIds.add(message.id);
    }
    if (!_coalesceFlushScheduled) {
      _coalesceFlushScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _flushCoalescedUpserts(),
      );
      // 158: the chat surface suppresses its ambient idle-glow, so an otherwise
      // idle conversation schedules no frames, and addPostFrameCallback does NOT
      // request one. Explicitly schedule a frame so the deferred flush runs
      // promptly (otherwise a drained burst would not surface until some other
      // frame happened to be scheduled).
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  /// 159: id-keyed merge + upsert into [_messages] WITHOUT sorting — the sort is
  /// coalesced to [_flushCoalescedUpserts]. Mirrors the merge semantics of
  /// [_upsertMessageById] (media preservation) so the data state matches the
  /// pre-coalesce per-event path exactly; only the sort is deferred.
  void _upsertIntoMessagesUnsorted(
    ConversationMessage message, {
    required bool mergeMedia,
  }) {
    if (message.isHidden) {
      _messages = _messages
          .where((existing) => existing.id != message.id)
          .toList();
      return;
    }
    var resolved = message;
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (message.mustClearTransientMedia) {
      resolved = message.copyWith(media: const <MediaAttachment>[]);
    } else if (mergeMedia && index != -1) {
      resolved = message.copyWith(
        media: _mergeLoadedMediaWithCurrentState(
          loaded: message.media,
          current: _messages[index].media,
        ),
      );
    }
    if (index == -1) {
      _messages = [..._messages, resolved];
    } else {
      final updated = [..._messages];
      updated[index] = resolved;
      _messages = updated;
    }
  }

  /// 159: the per-frame flush — sort the coalesced upserts ONCE + cap, in ONE
  /// setState, then run the per-event live-stream side effects exactly once
  /// against the post-batch state.
  void _flushCoalescedUpserts() {
    _coalesceFlushScheduled = false;
    final needsFlush = _coalesceNeedsFlush;
    final wantMarkRead = _coalesceWantsMarkRead;
    final wantIntroCheck = _coalesceWantsIntroCheck;
    final liveEdgeIds = Set<String>.of(_coalesceLiveEdgeCandidateIds);
    _coalesceNeedsFlush = false;
    _coalesceWantsMarkRead = false;
    _coalesceWantsIntroCheck = false;
    _coalesceLiveEdgeCandidateIds.clear();
    if (!mounted || !needsFlush) return;

    setState(() {
      _messages = _sortMessagesForDisplay(_messages);
      _applyInMemoryCap();
    });

    final shouldScroll =
        _messages.isNotEmpty && liveEdgeIds.contains(_messages.last.id);
    if (shouldScroll) _scrollToBottom();
    if (wantMarkRead) _markAsRead();
    if (wantIntroCheck && _showIntroBanner && _messages.length >= 3) {
      _onMaybeLater();
    }
  }

  Future<void> _onRetryUnavailableMedia(
    String messageId,
    String attachmentId,
  ) async {
    final bridge = widget.bridge;
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (bridge == null ||
        mediaAttachmentRepo == null ||
        mediaFileManager == null ||
        !_unavailableMediaRetriesInFlight.add(attachmentId)) {
      return;
    }

    try {
      final currentParent = await widget.messageRepo.getMessage(messageId);
      if (currentParent == null) return;
      final isPrivate = currentParent.privateMediaPolicy.requiresRedaction;
      if (isPrivate &&
          !currentParent.privateMediaPolicy.allowsExplicitDownload(
            currentParent.privateMediaState,
          )) {
        return;
      }
      final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      final attachment = attachments
          .where((candidate) => candidate.id == attachmentId)
          .firstOrNull;
      if (attachment == null) {
        return;
      }

      final resolved = await _resolveAttachmentForDisplay(attachment);
      final downloaded = await widget.downloadMediaFn(
        bridge: bridge,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        attachment: resolved,
        contactPeerId: _contact.peerId,
        owner: MediaOwnerLane.direct,
        messageRepo: widget.messageRepo,
        intent: MediaDownloadIntent.explicitUser,
      );
      MediaAttachment refreshedAttachment;
      if (downloaded != null) {
        refreshedAttachment = downloaded;
      } else {
        // Re-read the persisted status so a terminal download_failed isn't
        // shown as a retryable `failed` (INV-DL-1) — mirrors the group path.
        final rows = await mediaAttachmentRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        );
        final matches = rows.where((a) => a.id == resolved.id);
        refreshedAttachment = matches.isEmpty
            ? resolved.copyWith(downloadStatus: kMediaDownloadStatusFailed)
            : matches.first;
      }
      await _refreshMessageWithMediaSnapshot(
        messageId,
        _replaceAttachmentById(attachments, refreshedAttachment),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_UNAVAILABLE_MEDIA_RETRY_ERROR',
        details: {
          'messageId': messageId,
          'attachmentId': attachmentId,
          'error': e.toString(),
        },
      );
      await _refreshMessageWithHydratedMedia(messageId);
    } finally {
      _unavailableMediaRetriesInFlight.remove(attachmentId);
    }
  }

  void _onQuoteReply(String messageId) {
    if (!mounted) return;
    setState(() {
      _editingMessageId = null;
      _editingOriginalText = null;
      _clearRestoredFailedDraftTracking();
      _activeQuoteMessageId = messageId;
    });
  }

  void _onClearQuote() {
    if (!mounted) return;
    setState(() => _activeQuoteMessageId = null);
  }

  void _onEditMessage(String messageId) {
    if (!mounted || !_canEnterEditMode) return;
    final message = _messages.where((m) => m.id == messageId).firstOrNull;
    if (message == null ||
        message.isIncoming ||
        message.status == 'failed' ||
        message.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _activeQuoteMessageId = null;
      _editingMessageId = message.id;
      _editingOriginalText = message.text;
      _clearRestoredFailedDraftTracking();
      _draftText = message.text;
      _privateMediaPolicy = const PrivateMediaPolicy.ordinary();
    });
    _updateComposerState();
  }

  void _onCancelEdit() {
    if (!mounted) return;
    setState(() {
      _editingMessageId = null;
      _editingOriginalText = null;
      _clearRestoredFailedDraftTracking();
      _draftText = '';
    });
  }

  Future<void> _onDeleteMessage(String messageId) =>
      _promptAndDeleteMessage(messageId, mediaMessage: false);

  /// 231: whole-message Delete for Me initiated from a media surface. Same
  /// confirmation sheet and use case as [_onDeleteMessage] — only the prompt
  /// copy changes, stating the message AND all its attachments are removed
  /// from this device (never a single-attachment deletion).
  Future<void> _onDeleteMediaMessage(String messageId) =>
      _promptAndDeleteMessage(messageId, mediaMessage: true);

  Future<void> _promptAndDeleteMessage(
    String messageId, {
    required bool mediaMessage,
  }) async {
    if (!mounted) return;
    final message = _messages.where((m) => m.id == messageId).firstOrNull;
    if (message == null || message.isDeleted) return;

    final action = await _showDeleteMessageSheet(
      canDeleteForEveryone: _canDeleteForEveryone(message),
      mediaMessage: mediaMessage,
    );
    if (!mounted || action == null || action == _DeleteMessageAction.cancel) {
      return;
    }

    if (action == _DeleteMessageAction.forMe) {
      if (_editingMessageId == messageId) {
        setState(() {
          _editingMessageId = null;
          _editingOriginalText = null;
          _draftText = '';
        });
      }
      if (_activeQuoteMessageId == messageId && mounted) {
        setState(() => _activeQuoteMessageId = null);
      }
      final deleted = await _deleteMessageForMeLocally(message);
      if (deleted > 0 && mounted) {
        _removeLocalMessage(messageId);
      }
      return;
    }

    final (result, updatedMessage) = await widget.deleteMessageForEveryoneFn(
      p2pService: widget.p2pService,
      messageRepo: widget.messageRepo,
      originalMessage: message,
      reactionRepo: widget.reactionRepo,
      mediaAttachmentRepo: widget.mediaAttachmentRepo,
      mediaFileManager: widget.mediaFileManager,
      bridge: widget.bridge,
      recipientMlKemPublicKey: _contact.mlKemPublicKey,
      directEventFanout: widget.directEventFanout,
    );

    if (!mounted) return;
    if (updatedMessage != null || result == SendChatMessageResult.success) {
      setState(() {
        if (_editingMessageId == messageId) {
          _editingMessageId = null;
          _editingOriginalText = null;
          _draftText = '';
        }
        if (_activeQuoteMessageId == messageId) {
          _activeQuoteMessageId = null;
        }
        if (updatedMessage != null) _upsertMessageById(updatedMessage);
      });
      return;
    }
    if (result != SendChatMessageResult.success) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.conversation_delete_failed,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// The ONE local whole-message Delete-for-Me call site (the 231 frozen
  /// transport inventory pins the delete-for-me seam to exactly one
  /// occurrence): the message-sheet path and the 233 shared-media batch path
  /// both delete through here.
  Future<int> _deleteMessageForMeLocally(ConversationMessage message) {
    return widget.deleteMessageForMeFn(
      message: message,
      messageRepo: widget.messageRepo,
      reactionRepo: widget.reactionRepo,
      mediaAttachmentRepo: widget.mediaAttachmentRepo,
      mediaFileManager: widget.mediaFileManager,
    );
  }

  bool get _canEnterEditMode =>
      _composerController.pendingAttachments.isEmpty &&
      !_composerViewState.isProcessing &&
      !_composerViewState.isUploading &&
      !_isRecording &&
      !_isSending;

  bool _canDeleteForEveryone(ConversationMessage message) {
    final ownPeerId = _identity?.peerId;
    if (ownPeerId == null) return false;
    if (message.isIncoming || message.isDeleted) return false;
    if (message.senderPeerId != ownPeerId) return false;
    // 'inboxed' rows already have a durable relay copy the receiver will
    // drain — delete-for-everyone must stay available for them (doc 115).
    return message.status == 'delivered' || message.status == 'inboxed';
  }

  Future<_DeleteMessageAction?> _showDeleteMessageSheet({
    required bool canDeleteForEveryone,
    bool mediaMessage = false,
  }) {
    return showModalBottomSheet<_DeleteMessageAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _DeleteMessageSheet(
        canDeleteForEveryone: canDeleteForEveryone,
        mediaMessage: mediaMessage,
      ),
    );
  }

  // ── 231: direct received-media actions → local controller only ──────────

  ReceivedMediaActionController? _lazyMediaActionController;
  MediaViewerRepositoryResumeStore? _lazyMediaViewerResumeStore;

  MediaViewerRepositoryResumeStore? get _mediaViewerResumeStore {
    final existing = _lazyMediaViewerResumeStore;
    if (existing != null) return existing;
    final attachments = widget.mediaAttachmentRepo;
    if (attachments == null || attachments is! MediaLibraryStateRepository) {
      return null;
    }
    return _lazyMediaViewerResumeStore = MediaViewerRepositoryResumeStore(
      attachmentRepository: attachments,
      stateRepository: attachments as MediaLibraryStateRepository,
    );
  }

  MediaPictureInPictureController _createMediaPictureInPictureController({
    required MediaPictureInPictureCurrentAuthorizer reloadCurrent,
    required MediaPictureInPictureRestorePlayback restorePlayback,
  }) {
    final resumeStore = _mediaViewerResumeStore;
    if (resumeStore == null) {
      throw StateError('PiP composition requires media library state');
    }
    final messageRepository = widget.messageRepo;
    final attachmentRepository = widget.mediaAttachmentRepo;
    MediaViewerItem? activeItem;
    Future<MediaPictureInPictureAuthorization?> trackedReloadCurrent() async {
      final authorization = await reloadCurrent();
      if (authorization != null) activeItem = authorization.item;
      return authorization;
    }

    final messageChanges = messageRepository is MessageRepositoryChangeSource
        ? (messageRepository as MessageRepositoryChangeSource).messageChanges
        : const Stream<ConversationMessage>.empty();
    final messageRemovals = messageRepository is MessageRepositoryRemovalSource
        ? (messageRepository as MessageRepositoryRemovalSource).messageRemovals
        : const Stream<DirectMessageRemoval>.empty();
    final attachmentChanges =
        attachmentRepository is MediaAttachmentAuthorizationChangeSource
        ? (attachmentRepository as MediaAttachmentAuthorizationChangeSource)
              .authorizationChanges
        : const Stream<MediaAttachmentAuthorizationChange>.empty();
    final authorizationChanges = directPictureInPictureAuthorizationChanges(
      messageChanges,
      contactPeerId: widget.contact.peerId,
      messageRemovals: messageRemovals,
      attachmentChanges: attachmentChanges,
      currentItem: () => activeItem,
    );
    return MediaPictureInPictureController(
      gateway: PictureInPictureChannelGateway.platform(),
      pathAuthority: IoAppOwnedMediaPathAuthority(),
      reloadCurrent: trackedReloadCurrent,
      resumeStore: resumeStore,
      restorePlayback: restorePlayback,
      authorizationChanges: authorizationChanges,
    );
  }

  /// The single egress/info authority for this screen's media actions. An
  /// injected controller wins (tests); otherwise one is built lazily over the
  /// local repositories and the real plan-227 service. Null (no repo) leaves
  /// media actions unwired.
  ReceivedMediaActionController? get _mediaActionController {
    final injected = widget.receivedMediaActionController;
    if (injected != null) return injected;
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    if (mediaAttachmentRepo == null) return null;
    return _lazyMediaActionController ??= ReceivedMediaActionController(
      loadParentMessage: widget.messageRepo.getMessage,
      mediaAttachmentRepo: mediaAttachmentRepo,
      egressService: ReceivedMediaEgressService(),
    );
  }

  Future<DirectReceivedMediaEgressOutcome> _performDirectMediaEgress(
    DirectReceivedMediaActionIdentity identity,
    MediaEgressDestination destination,
  ) async {
    final controller = _mediaActionController;
    if (controller == null) {
      return const DirectReceivedMediaEgressOutcome.denied(
        DirectMediaEgressDenial.policyUnavailable,
      );
    }
    return controller.performEgress(
      identity: identity,
      destination: destination,
    );
  }

  Future<DirectReceivedMediaInfo?> _loadDirectMediaInfo(
    DirectReceivedMediaActionIdentity identity,
  ) async {
    final controller = _mediaActionController;
    if (controller == null) return null;
    return controller.loadInfo(identity);
  }

  Future<DirectPrivateMediaActionDecision> _loadDirectMediaActionDecision(
    DirectReceivedMediaActionIdentity identity,
  ) async {
    final controller = _mediaActionController;
    if (controller != null) return controller.loadActionDecision(identity);
    return DirectPrivateMediaActionEligibility.evaluate(
      parent: null,
      attachment: null,
      expectedMessageId: identity.messageId,
      expectedAttachmentId: identity.attachmentId,
    );
  }

  Future<MediaPictureInPictureAuthorization?>
  _loadDirectPictureInPictureAuthorization(MediaViewerItem displayed) async {
    final mediaRepository = widget.mediaAttachmentRepo;
    if (!mounted ||
        mediaRepository == null ||
        displayed.owner != MediaOwnerLane.direct ||
        !displayed.isVideo) {
      return null;
    }
    final rows = await mediaRepository.getAttachmentsForMessage(
      displayed.messageId,
      owner: MediaOwnerLane.direct,
    );
    MediaAttachment? currentAttachment;
    for (final row in rows) {
      if (row.id == displayed.attachmentId &&
          row.messageId == displayed.messageId &&
          row.ownerLane == MediaOwnerLane.direct &&
          row.mediaType == 'video') {
        currentAttachment = row;
        break;
      }
    }
    if (currentAttachment == null) return null;

    // Reload the parent after the attachment await. This is the authority used
    // immediately before capability presentation, handoff, and every poll.
    final currentParent = await widget.messageRepo.getMessage(
      displayed.messageId,
    );
    final decision = DirectPrivateMediaActionEligibility.evaluate(
      parent: currentParent,
      attachment: currentAttachment,
      expectedMessageId: displayed.messageId,
      expectedAttachmentId: displayed.attachmentId,
    );
    if (!mounted || currentParent == null || !decision.isOrdinary) return null;

    final storedPath = currentAttachment.localPath;
    final resolvedPath = storedPath == null || storedPath.isEmpty
        ? null
        : MediaFileManager.resolveStoredPathSync(storedPath);
    final hasBytes = resolvedPath != null && File(resolvedPath).existsSync();
    final transferComplete =
        currentAttachment.downloadStatus == kMediaDownloadStatusDone;
    final currentItem = MediaViewerItem(
      attachmentId: currentAttachment.id,
      messageId: currentAttachment.messageId,
      kind: MediaViewerKind.video,
      mime: currentAttachment.mime,
      owner: MediaOwnerLane.direct,
      localPath: resolvedPath,
      sizeBytes: currentAttachment.size,
      width: currentAttachment.width,
      height: currentAttachment.height,
      durationMs: currentAttachment.durationMs,
      canEnterPictureInPicture: decision.canEnterPictureInPicture,
      protection: MediaViewerProtection(
        isDownloaded: transferComplete && hasBytes,
        isIntegrityVerified:
            currentAttachment.downloadStatus !=
            kMediaDownloadStatusIntegrityFailed,
      ),
    );
    return MediaPictureInPictureAuthorization(
      item: currentItem,
      generation:
          Object.hash(
            MediaOwnerLane.direct,
            currentItem.messageId,
            currentItem.attachmentId,
          ) &
          0x7fffffff,
      policyState: MediaPictureInPicturePolicyState.ordinary,
      isIncoming: currentParent.isIncoming,
      isTransferComplete: transferComplete,
      routeActive: mounted,
    );
  }

  PrivateMediaLifecycleEngine? _lazyPrivateMediaLifecycleEngine;
  DirectPrivateMediaViewerController? _lazyPrivateMediaViewerController;

  PrivateMediaLifecycleEngine? get _privateMediaLifecycleEngine {
    final existing = _lazyPrivateMediaLifecycleEngine;
    if (existing != null) return existing;
    final messageRepository = widget.messageRepo;
    final attachmentRepository = widget.mediaAttachmentRepo;
    final fileManager = widget.mediaFileManager;
    if (messageRepository is! DirectPrivateMediaLifecycleRepository ||
        attachmentRepository == null ||
        attachmentRepository is! DirectPrivateMediaCleanupRepository ||
        attachmentRepository is! DirectPrivateMediaCleanupRuntime ||
        fileManager == null) {
      return null;
    }
    final lifecycleMessageRepository =
        messageRepository as DirectPrivateMediaLifecycleRepository;
    final cleanupRuntime =
        attachmentRepository as DirectPrivateMediaCleanupRuntime;
    final lane = DirectPrivateMediaLifecycle(
      messageRepository: lifecycleMessageRepository,
      mediaAttachmentRepository: attachmentRepository,
      mediaFileManager: fileManager,
    );
    return _lazyPrivateMediaLifecycleEngine = PrivateMediaLifecycleEngine(
      adapter: lane,
      lifecycleLock: cleanupRuntime.directPrivateMediaLifecycleLock,
      nowMs: () => DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Session-05 runtime qualification is deliberately local to the direct
  /// conversation. Missing lifecycle, raw-cleanup, runtime-lock, or file
  /// capabilities deny the route without throwing or creating a substitute
  /// lock/engine.
  DirectPrivateMediaViewerController? get _privateMediaViewerController {
    final existing = _lazyPrivateMediaViewerController;
    if (existing != null) return existing;
    final engine = _privateMediaLifecycleEngine;
    if (engine == null) return null;
    final messageRepository =
        widget.messageRepo as DirectPrivateMediaLifecycleRepository;
    final attachmentRepository = widget.mediaAttachmentRepo!;
    final lifecycleMessageRepository = messageRepository;
    return _lazyPrivateMediaViewerController =
        DirectPrivateMediaViewerController(
          loadCurrentRows: (identity) async {
            final parent = await lifecycleMessageRepository
                .loadPrivateMediaLifecycleMessage(identity.messageId);
            final attachments = await attachmentRepository
                .getAttachmentsForMessage(
                  identity.messageId,
                  owner: MediaOwnerLane.direct,
                );
            MediaAttachment? exact;
            for (final attachment in attachments) {
              if (attachment.id == identity.attachmentId) {
                if (exact != null) {
                  exact = null;
                  break;
                }
                exact = attachment;
              }
            }
            return DirectPrivateMediaCurrentRows(
              parent: parent,
              attachment: exact,
            );
          },
          lifecycleEngine: engine,
          protectionCoordinator:
              PrivateMediaProtectionCoordinator.sharedPlatform(),
          disposeProtectionCoordinator: false,
        );
  }

  Future<DirectPrivateMediaActionDecision> _loadPrivateParentDecision(
    String messageId,
  ) async {
    final repository = widget.messageRepo;
    final parent = repository is DirectPrivateMediaLifecycleRepository
        ? await (repository as DirectPrivateMediaLifecycleRepository)
              .loadPrivateMediaLifecycleMessage(messageId)
        : await repository.getMessage(messageId);
    return DirectPrivateMediaActionEligibility.evaluate(
      parent: parent,
      attachment: null,
      expectedMessageId: messageId,
      attachmentRequired: false,
    );
  }

  Future<DirectPrivateMediaOpenResult> _openDirectPrivateMedia(
    DirectPrivateMediaViewerIdentity identity,
    DirectPrivateMediaContinuityGuard continuityGuard,
  ) async {
    final controller = _privateMediaViewerController;
    if (controller == null) {
      return const DirectPrivateMediaOpenResult.failed(
        DirectPrivateMediaOpenFailureReason.authorityLost,
        canRetry: false,
      );
    }
    final prepared = await controller.prepareResult(identity, continuityGuard);
    final grant = prepared.grant;
    if (grant == null) {
      final reason = prepared.failureReason!;
      final canRetry = await controller.canRetryAfterPrepareFailure(
        identity,
        reason,
        settleResult: prepared.settleResult,
      );
      return DirectPrivateMediaOpenResult.failed(
        switch (reason) {
          DirectPrivateMediaPrepareFailureReason.appLifecycleContinuityLost =>
            DirectPrivateMediaOpenFailureReason.lifecycleInterrupted,
          DirectPrivateMediaPrepareFailureReason.senderLocalBytesMissing =>
            DirectPrivateMediaOpenFailureReason.senderLocalBytesMissing,
          _ => DirectPrivateMediaOpenFailureReason.prepareFailed,
        },
        settleResult: prepared.settleResult,
        canRetry: canRetry,
      );
    }
    final continuityState = continuityGuard.state;
    if (!mounted ||
        continuityState != DirectPrivateMediaContinuityState.valid) {
      final appLifecycleInvalidated =
          continuityState ==
          DirectPrivateMediaContinuityState.appLifecycleInvalidated;
      final settled = await controller.settle(
        grant,
        appLifecycleInvalidated
            ? DirectPrivateMediaExitReason.appLifecycleLoss
            : DirectPrivateMediaExitReason.routeContinuityLoss,
      );
      final failureReason = appLifecycleInvalidated
          ? DirectPrivateMediaOpenFailureReason.lifecycleInterrupted
          : DirectPrivateMediaOpenFailureReason.preFrameFailure;
      final canRetry = await controller.canRetryAfterOpenFailure(
        identity,
        failureReason,
        settleResult: settled,
      );
      return DirectPrivateMediaOpenResult.failed(
        failureReason,
        settleResult: settled,
        canRetry: canRetry,
      );
    }
    MaterialPageRoute<void>? privateRoute;
    DirectPrivateMediaSettleResult? settled;
    var routePushFailed = false;
    try {
      final visibilityIdentity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: _contact.peerId,
      );
      Widget viewerBuilder(BuildContext _) => DirectPrivateMediaViewer(
        grant: grant,
        controller: controller,
        onSafeAction: (action) async {
          switch (action) {
            case DirectPrivateMediaAction.reply:
              _onQuoteReply(identity.messageId);
              return;
            case DirectPrivateMediaAction.info:
              if (!mounted) return;
              final l10n = AppLocalizations.of(context)!;
              await showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(l10n.private_media_notification_body),
                  content: Text(l10n.private_media_notification_body),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        MaterialLocalizations.of(context).closeButtonLabel,
                      ),
                    ),
                  ],
                ),
              );
              return;
            case DirectPrivateMediaAction.deleteForMe:
              await _onDeleteMediaMessage(identity.messageId);
              return;
            case DirectPrivateMediaAction.openInApp:
            case DirectPrivateMediaAction.explicitDownload:
            case DirectPrivateMediaAction.saveToPhotos:
            case DirectPrivateMediaAction.saveToFiles:
            case DirectPrivateMediaAction.externalShare:
            case DirectPrivateMediaAction.internalForward:
            case DirectPrivateMediaAction.bookmark:
            case DirectPrivateMediaAction.sharedMedia:
            case DirectPrivateMediaAction.pictureInPicture:
              return;
          }
        },
      );
      privateRoute = visibilityIdentity == null
          ? MaterialPageRoute<void>(builder: viewerBuilder)
          : AppVisibilityInheritedConversationRoute<void>(
              identity: visibilityIdentity,
              builder: viewerBuilder,
            );
      await Navigator.of(context).push<void>(privateRoute);
      await privateRoute.completed;
    } catch (_) {
      routePushFailed = true;
      settled = await controller.settle(
        grant,
        DirectPrivateMediaExitReason.routePushFailure,
        releaseProtection: false,
      );
    } finally {
      if (!grant.settled) {
        settled = await controller.settle(
          grant,
          DirectPrivateMediaExitReason.close,
          releaseProtection: false,
        );
      } else {
        settled ??= grant.settleResult;
      }
      await controller.releaseProtectionOwner(grant);
    }
    final result = settled ?? grant.settleResult;
    if (result != null && result.firstFrameRecorded) {
      return DirectPrivateMediaOpenResult.displayed(result);
    }
    final failureReason = routePushFailed
        ? DirectPrivateMediaOpenFailureReason.routePushFailure
        : _privateMediaOpenFailureReason(result);
    final canRetry = await controller.canRetryAfterOpenFailure(
      identity,
      failureReason,
      settleResult: result,
    );
    return DirectPrivateMediaOpenResult.failed(
      failureReason,
      settleResult: result,
      canRetry: canRetry,
    );
  }

  DirectPrivateMediaOpenFailureReason _privateMediaOpenFailureReason(
    DirectPrivateMediaSettleResult? result,
  ) => switch (result?.exitReason) {
    DirectPrivateMediaExitReason.routePushFailure =>
      DirectPrivateMediaOpenFailureReason.routePushFailure,
    DirectPrivateMediaExitReason.preFrameDecodeFailure ||
    DirectPrivateMediaExitReason.routeContinuityLoss ||
    DirectPrivateMediaExitReason.protectionEnterFailure ||
    DirectPrivateMediaExitReason.revalidationFailure =>
      DirectPrivateMediaOpenFailureReason.preFrameFailure,
    DirectPrivateMediaExitReason.appLifecycleLoss ||
    DirectPrivateMediaExitReason.background ||
    DirectPrivateMediaExitReason.capture ||
    DirectPrivateMediaExitReason.dispose =>
      DirectPrivateMediaOpenFailureReason.lifecycleInterrupted,
    _ => DirectPrivateMediaOpenFailureReason.authorityLost,
  };

  Future<bool> _forwardDirectReceivedMedia(
    String messageId, {
    String? currentAttachmentId,
  }) async {
    final mediaRepo = widget.mediaAttachmentRepo;
    final parent = await widget.messageRepo.getMessage(messageId);
    if (mediaRepo == null || parent == null || !mounted) return false;
    final result = await BuildReceivedMediaForward(
      loadParentMessage: widget.messageRepo.getMessage,
      mediaAttachmentRepository: mediaRepo,
      mediaFileManager: widget.mediaFileManager,
    ).build(parent: parent, currentAttachmentId: currentAttachmentId);
    final intent = result.draft?.shareIntent;
    if (intent == null || !mounted) return false;

    final injected = widget.receivedMediaForwardLauncher;
    if (injected != null) {
      await injected(context, intent);
      return true;
    }
    final contacts = widget.contactRepo;
    final bridge = widget.bridge;
    final mediaManager = widget.mediaFileManager;
    final imageProcessor = widget.imageProcessor;
    if (contacts == null ||
        bridge == null ||
        mediaManager == null ||
        imageProcessor == null) {
      return false;
    }
    await Navigator.of(context).push(
      buildShareTargetPickerRoute(
        shareIntent: intent,
        identityRepo: widget.identityRepo,
        contactRepository: contacts,
        messageRepository: widget.messageRepo,
        mediaAttachmentRepository: mediaRepo,
        chatMessageListener: widget.chatMessageListener,
        bridge: bridge,
        p2pService: widget.p2pService,
        mediaFileManager: mediaManager,
        imageProcessor: imageProcessor,
        conversationTracker: widget.conversationTracker,
        audioRecorderService: widget.audioRecorderService,
        reactionRepository: widget.reactionRepo,
        reactionListener: widget.reactionListener,
        groupRepository: widget.forwardGroupRepository,
        groupMessageRepository: widget.forwardGroupMessageRepository,
        groupInviteDeliveryAttemptRepository:
            widget.forwardGroupInviteDeliveryAttemptRepository,
        groupMessageListener: widget.forwardGroupMessageListener,
        groupConversationTracker: widget.forwardGroupConversationTracker,
        introductionRepository: widget.introductionRepository,
        appShellController: widget.appShellController,
        directEventFanoutResolver: () => widget.directEventFanout,
      ),
    );
    return true;
  }

  (String?, bool) _resolveActiveQuotePreview() {
    final quoteId = _activeQuoteMessageId;
    if (quoteId == null) return (null, false);

    final quoted = _messages.where((m) => m.id == quoteId).firstOrNull;
    if (quoted == null) return (null, true);
    final decision = DirectPrivateMediaActionEligibility.evaluate(
      parent: quoted,
      attachment: null,
      expectedMessageId: quoted.id,
      attachmentRequired: false,
    );
    if (decision.requiresPrivacyMinimizedPresentation &&
        decision.allows(DirectPrivateMediaAction.reply)) {
      return (
        AppLocalizations.of(context)!.private_media_notification_body,
        false,
      );
    }
    if (quoted.text.isNotEmpty) return (quoted.text, false);
    if (quoted.media.isNotEmpty) return (mediaPreviewText(quoted.media), false);
    return (null, true);
  }

  void _startListeningForContactUpdates() {
    _contactUpdateSubscription = widget.chatMessageListener.contactUpdatedStream
        .where((c) => c.peerId == _contact.peerId)
        .listen(
          (updatedContact) {
            if (!mounted) return;
            setState(() => _contact = updatedContact);
          },
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_CONTACT_UPDATE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
          onDone: () {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_CONTACT_UPDATE_STREAM_DONE',
              details: {},
            );
          },
        );
  }

  Future<void> _onSend(String text) async {
    final identity = _identity;
    if (identity == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Captured pre-gap: the failure snackbar below runs after awaits, when
    // this State may already be unmounted.
    final l10n = AppLocalizations.of(context)!;

    final hasAttachments = _composerController.pendingAttachments.isNotEmpty;
    final sanitizedText = sanitizeMessageText(text);
    final editingMessage = _editingMessageId == null
        ? null
        : _messages.where((m) => m.id == _editingMessageId).firstOrNull;
    if (sanitizedText.isEmpty && !hasAttachments) return;
    if (_isSending) return;

    final privateMediaPolicy = _privateMediaPolicy;
    final privateEligibility = _currentPrivateMediaEligibility(
      draftText: sanitizedText,
    );
    if (_privateMediaPolicyInvalidated ||
        (privateMediaPolicy.isPrivate &&
            !isPrivateMediaComposerPolicyEligible(
              selectedPolicy: privateMediaPolicy,
              eligibility: privateEligibility,
            ))) {
      // 362: this gate is the ONLY thing standing between a multi-attachment
      // Protected/View-Once send and persistence — `allowsNewPrivateMedia`
      // requires exactly one attachment, and `_currentPrivateMediaEligibility`
      // leaves the kind unknown above one, so such a send refuses HERE, before
      // any lease, row or durable copy. The invariant is emergent across two
      // files and five add sites, so it is named here and pinned by test.
      //
      // The reset to ordinary is DELIBERATE and pinned by test ("replacing a
      // private image draft with GIF resets to keep in chat", "video
      // replacement blocks stale view-once send", "failed private upload
      // restores the exact selected policy"). It is not the kind of draft
      // mutation the 362 admission contract forbids: the contract governs a
      // FANOUT refusal, which must not silently rewrite the user's intent,
      // whereas this is an eligibility reset the product wants — the composer
      // drops back to "keep in chat" so the send can proceed on a retry.
      _setPrivateMediaPolicy(const PrivateMediaPolicy.ordinary());
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.private_media_invalid_shape,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (editingMessage == null &&
        _shouldRetryRestoredFailedDraft(
          sanitizedText: sanitizedText,
          hasAttachments: hasAttachments,
        )) {
      await _retryRestoredFailedDraft();
      return;
    }

    if (editingMessage != null) {
      final originalText = _editingOriginalText ?? editingMessage.text;
      if (sanitizedText == originalText) {
        if (!mounted) return;
        setState(() {
          _editingMessageId = null;
          _editingOriginalText = null;
          _draftText = '';
        });
        return;
      }

      setState(() => _isSending = true);

      try {
        final (result, message) = await widget.editChatMessageFn(
          p2pService: widget.p2pService,
          messageRepo: widget.messageRepo,
          originalMessage: editingMessage,
          updatedText: sanitizedText,
          senderUsername: identity.username,
          bridge: widget.bridge,
          recipientMlKemPublicKey: _contact.mlKemPublicKey,
          mediaAttachmentRepo: widget.mediaAttachmentRepo,
          directEventFanout: widget.directEventFanout,
        );

        if (!mounted) return;

        if (result == SendChatMessageResult.success || message != null) {
          setState(() {
            _editingMessageId = null;
            _editingOriginalText = null;
            _draftText = '';
            if (message != null) _upsertMessageById(message);
          });
          if (message != null) _scrollToBottom();
        } else {
          // A custody/fanout refusal is retryable user intent. Keep edit mode
          // and the exact sanitized draft instead of clearing it optimistically.
          setState(() => _draftText = sanitizedText);
          messenger
            ?..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.edit_save_failed),
                behavior: SnackBarBehavior.floating,
                margin: _composerClearingSnackBarMargin(),
              ),
            );
        }
      } finally {
        if (mounted) {
          setState(() => _isSending = false);
        }
      }
      return;
    }

    // Per-type SEND size gate (OQ-2). Runs before any state mutation/upload so a
    // rejected attachment simply surfaces a message and leaves the composer
    // intact (no optimistic message, no upload).
    if (hasAttachments) {
      final rejections = _validatePendingMediaSizes(
        _composerController.pendingAttachments,
      );
      if (rejections.isNotEmpty) {
        for (final rejection in rejections) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONV_FL_MEDIA_REJECTED_INVALID_SIZE',
            details: {'index': rejection.index, 'reason': rejection.reason},
          );
        }
        return;
      }
    }

    setState(() {
      _clearRestoredFailedDraftTracking();
      _isSending = true;
    });

    MediaUploadLease? uploadLease;
    _ForegroundDirectPrivateTransferLease? privateTransferLease;

    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_SEND_PRESSED',
        details: {
          'textLength': sanitizedText.length,
          'attachments': _composerController.pendingAttachments.length,
        },
      );

      // 362 ADMISSION BOUNDARY. Resolve legacy | fanout | refused for this
      // send BEFORE any send-owned durable write: no upload lease, no composer
      // clearing, no message/attachment row, no durable copy, no crypto, no
      // custody staging, no network has happened yet at this line. A refusal
      // therefore returns with the draft and the picker sources intact and
      // leaves ZERO rows any retry lane could later pick up and upload to a
      // single target.
      //
      // The pending list is captured here rather than at its old site further
      // down because this boundary awaits: `_attemptAddPendingMedia` publishes
      // without an `_isSending` guard, so a second attachment could otherwise
      // land during the await and invalidate the shape we just validated.
      final mediaToUpload = List<PendingComposerMedia>.from(
        _composerController.pendingAttachments,
      );
      DirectMediaFanoutAdmission? mediaAdmission;
      if (mediaToUpload.isNotEmpty) {
        // Text-only sends are NOT admitted here: their route is already
        // resolved inside sendChatMessage, which receives the authoring owner
        // directly.
        final fanoutCapableRepository =
            widget.mediaAttachmentRepo
                is OutgoingDirectLinkedMediaBlobFanoutRepository &&
            (widget.mediaAttachmentRepo
                    as OutgoingDirectLinkedMediaBlobFanoutRepository)
                .supportsDirectLinkedMediaBlobFanout;
        final privateFanoutCapable =
            widget.mediaAttachmentRepo
                is OutgoingDirectPrivateMediaBlobFanoutGenerationRepository &&
            (widget.mediaAttachmentRepo
                    as OutgoingDirectPrivateMediaBlobFanoutGenerationRepository)
                .supportsOutgoingDirectPrivateMediaBlobFanoutGeneration &&
            widget.messageRepo
                is OutgoingDirectPrivateMediaFanoutInboxCustodyRepository &&
            (widget.messageRepo
                    as OutgoingDirectPrivateMediaFanoutInboxCustodyRepository)
                .supportsOutgoingDirectPrivateMediaFanoutInboxCustody;
        final linkedOwnersAvailable =
            _isOutgoingPrivateOneMoreLook(privateMediaPolicy)
            ? privateFanoutCapable
            : fanoutCapableRepository;
        final canServeLinkedFanout =
            widget.directMediaBlobCustodyClientEnabled &&
            widget.directLinkedEventFanoutEnabled &&
            widget
                .directLinkedMediaFanoutSelector
                .allowsDirectLinkedMediaFanoutAuthoring &&
            linkedOwnersAvailable;
        mediaAdmission = await resolveDirectMediaFanoutAdmission(
          mediaAttachmentRepository: widget.mediaAttachmentRepo,
          contactAccountPeerId: _contact.peerId,
          canServeLinkedFanout: canServeLinkedFanout,
        );
        if (mediaAdmission.refuses) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONV_FL_SEND_MEDIA_FANOUT_ADMISSION_REFUSED',
            details: {
              'reason': mediaAdmission.reason,
              'attachments': mediaToUpload.length,
            },
          );
          if (mounted) {
            setState(() {
              _isSending = false;
              _draftText = sanitizedText;
            });
          }
          return;
        }
      }

      final draftText = sanitizedText;
      final quotedMessageId = _activeQuoteMessageId;
      final composerSnapshot = _DirectComposerSnapshot(
        common: _composerController.snapshot(
          draftText: draftText,
          quotedMessageId: quotedMessageId,
        ),
        privateMediaPolicy: privateMediaPolicy,
      );
      if (_activeQuoteMessageId != null && mounted) {
        setState(() => _activeQuoteMessageId = null);
      }

      // `mediaToUpload` was captured above the 362 admission boundary.
      List<MediaAttachment>? optimisticMedia;
      List<_PreparedConversationMediaUpload> preparedUploads = const [];

      if (mediaToUpload.isNotEmpty) {
        final now = DateTime.now().toUtc().toIso8601String();
        optimisticMedia = mediaToUpload.indexed.map((entry) {
          final (index, m) = entry;
          final mime = _mimeFromPath(m.file.path);
          return MediaAttachment(
            id: index == 0 && _privateMediaOutboxE2ENextAttachmentId != null
                ? _privateMediaOutboxE2ENextAttachmentId!
                : _uuid.v4(),
            messageId: '',
            mime: mime,
            size: m.budgetBytes,
            mediaType: MediaAttachment.mediaTypeFromMime(mime),
            width: m.width,
            height: m.height,
            durationMs: m.durationMs,
            localPath: m.file.path,
            downloadStatus: 'done',
            createdAt: now,
          );
        }).toList();
        // 127-Bug-B: own these blobs from the EARLIEST point — BEFORE durable
        // prep and the LAN-direct send — not only at the later relay-upload
        // step. The optimistic ids ARE the upload blobIds (the upload loop falls
        // back to optimisticMedia[index].id, and durable prep preserves the id),
        // so the background retrier (which fires on connectivity edges and can
        // land during the LAN-send window) now always sees the blob in-flight
        // and defers, instead of racing in to re-encrypt + re-upload. Released
        // in the outer finally.
        uploadLease = mediaUploadInFlightTracker.tryClaimAll(
          optimisticMedia.map((attachment) => attachment.id),
          source: MediaUploadTriggerSource.foreground,
        );
        if (uploadLease == null) {
          if (quotedMessageId != null && mounted) {
            setState(() => _activeQuoteMessageId = quotedMessageId);
          }
          return;
        }
      }

      _draftText = '';
      _privateMediaPolicy = const PrivateMediaPolicy.ordinary();
      _updateComposerState(
        pendingAttachments: const [],
        isUploading: mediaToUpload.isNotEmpty,
      );

      final now = DateTime.now().toUtc().toIso8601String();
      final optimisticMessageId =
          _privateMediaOutboxE2ENextMessageId ?? _uuid.v4();
      final optimisticMessage = ConversationMessage(
        id: optimisticMessageId,
        contactPeerId: _contact.peerId,
        senderPeerId: identity.peerId,
        text: sanitizedText,
        timestamp: now,
        status: 'sending',
        isIncoming: false,
        createdAt: now,
        quotedMessageId: quotedMessageId,
        media: optimisticMedia ?? const [],
        privateMediaPolicy: privateMediaPolicy,
        privateMediaState: privateMediaPolicy.initialState,
        // 358: a newly authored disappearing image/video initial mints the same
        // deterministic v110 token as ordinary strict media, so it can adopt
        // the token-bearing v110 -> v111 -> v108 owners. The exact producer
        // matrix is proved here, before the parent is persisted, and again by
        // the DB predicates. Protected/View-Once keep their no-v110 lane.
        directMediaCustodyIntentId:
            hasAttachments &&
                (privateMediaPolicy.mode == PrivateMediaMode.ordinary ||
                    (widget.directMediaBlobCustodyClientEnabled &&
                        optimisticMedia!.length == 1 &&
                        sanitizedText.isEmpty &&
                        quotedMessageId == null &&
                        disappearingMediaInitialProducerMatrixAllows(
                          policyVersion: privateMediaPolicy.version,
                          mode: privateMediaPolicy.mode,
                          durationSeconds: privateMediaPolicy.durationSeconds,
                          mime: optimisticMedia.single.mime,
                          mediaType: optimisticMedia.single.mediaType,
                        )))
            ? computeDirectMediaCustodyIntentId(
                messageId: optimisticMessageId,
                attachmentIds: optimisticMedia!.map(
                  (attachment) => attachment.id,
                ),
              )
            : null,
      );
      final stagesFreshDirectTextCustody =
          !hasAttachments &&
          privateMediaPolicy.mode == PrivateMediaMode.ordinary;

      if (mounted) {
        setState(() {
          _upsertMessageById(optimisticMessage);
        });
        _scrollToBottom();
      }

      try {
        // Fresh ordinary text must reach sendChatMessage with no durable
        // predecessor: its production repository owns the first message row
        // and immutable custody row in one transaction. The bubble above stays
        // optimistic in memory. Media/private flows retain their established
        // pre-save and attachment-lifecycle authority.
        if (!stagesFreshDirectTextCustody) {
          if (_isOutgoingPrivateOneMoreLook(privateMediaPolicy)) {
            final mediaRuntime = widget.mediaAttachmentRepo;
            final contactRepository = widget.contactRepo;
            if (mediaRuntime is! DirectPrivateMediaCleanupRuntime ||
                contactRepository == null) {
              throw StateError(
                'private parent publication requires contact and lifecycle authority',
              );
            }
            final privateMediaRuntime =
                mediaRuntime as DirectPrivateMediaCleanupRuntime;

            // Contact deletion inventories messages, removes them, and finally
            // removes the contact while holding this same global lock. Publish
            // the first private parent under that authority and re-read contact
            // existence only after acquiring it. Therefore either publication
            // wins and the later deletion inventories/removes the parent, or
            // deletion wins and this publication refuses instead of resurrecting
            // a row from the screen's stale ContactModel snapshot.
            await privateMediaRuntime.directPrivateMediaLifecycleLock
                .synchronizedAll(() async {
                  final contactStillExists = await contactRepository
                      .contactExists(optimisticMessage.contactPeerId);
                  if (!contactStillExists) {
                    throw StateError(
                      'private parent publication refused after contact removal',
                    );
                  }
                  await widget.messageRepo.saveMessage(optimisticMessage);
                });
          } else {
            await widget.messageRepo.saveMessage(optimisticMessage);
          }
          if (!_isOutgoingPrivateOneMoreLook(privateMediaPolicy)) {
            await _persistOptimisticAttachments(
              optimisticMessage.id,
              optimisticMedia,
              errorEvent: 'CONV_FL_OPTIMISTIC_ATTACHMENT_SAVE_ERROR',
            );
          }
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_OPTIMISTIC_SAVE_ERROR',
          details: {'error': e.toString()},
        );
        if (_isOutgoingPrivateOneMoreLook(privateMediaPolicy)) {
          // A private pending file must never exist without its durable parent
          // policy row. Abort before registry claim or plaintext copy; the
          // ordinary-media optimistic-save behavior remains unchanged.
          await _restoreComposerSnapshot(
            composerSnapshot,
            optimisticMessageId: optimisticMessage.id,
            messenger: messenger,
            snackText: 'Failed to prepare private media. Try again.',
          );
          return;
        }
      }

      if (_isOutgoingPrivateOneMoreLook(privateMediaPolicy)) {
        try {
          privateTransferLease = await _beginForegroundDirectPrivateTransfer(
            messageId: optimisticMessage.id,
            attachments: optimisticMedia ?? const <MediaAttachment>[],
          );
        } catch (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONV_FL_PRIVATE_TRANSFER_CLAIM_REFUSED',
            details: {'error': error.toString()},
          );
          await _restoreComposerSnapshot(
            composerSnapshot,
            optimisticMessageId: optimisticMessage.id,
            messenger: messenger,
            snackText: 'Failed to prepare private media. Try again.',
          );
          return;
        }
      }

      // 170-S2: media/private messages are now durably optimistic, while fresh
      // ordinary text is ready for the atomic message-plus-custody stage in
      // `sendChatMessageFn` below. Release the composer here rather than after
      // the network round-trip. Keeping `_isSending` true through the
      // multi-second direct->relay->inbox cascade is what froze the Send button
      // and blocked a second message. The remaining staging/upload/send work
      // continues on this fire-and-forget `_onSend` future; the bubble still
      // drives sending->sent/failed below and the outer finally resets the flag
      // defensively. The same-frame re-entrancy guard remains effective because
      // this release lands only after the preparation boundary completes, and
      // the composer controller clear swallows the duplicate tap. See
      // conversation_wired_offline_send_ux_test.dart (TC-01 / TC-02).
      if (mounted) {
        setState(() => _isSending = false);
      } else {
        _isSending = false;
      }

      if (mediaToUpload.isNotEmpty &&
          widget.bridge != null &&
          _supportsDurableMediaUploads &&
          optimisticMedia != null) {
        try {
          preparedUploads = await _prepareDurableMediaUploads(
            messageId: optimisticMessage.id,
            mediaToUpload: mediaToUpload,
            optimisticMedia: optimisticMedia,
            privateTransferLease: privateTransferLease,
          );
          final transferLease = privateTransferLease;
          if (transferLease != null) {
            await _bindForegroundDirectPrivatePendingCustody(
              lease: transferLease,
              preparedUploads: preparedUploads,
            );
          }
          if (mounted && preparedUploads.isNotEmpty) {
            final displayMedia = transferLease != null
                ? preparedUploads
                      .map((plan) => plan.pendingAttachment)
                      .toList(growable: false)
                : preparedUploads
                      .map(
                        (plan) => plan.pendingAttachment.copyWith(
                          localPath: plan.absoluteDurablePath,
                          downloadStatus: 'done',
                        ),
                      )
                      .toList(growable: false);
            setState(
              () => _upsertMessageById(
                optimisticMessage.copyWith(media: displayMedia),
              ),
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONV_FL_MEDIA_DURABLE_PREP_ERROR',
            details: {'error': e.toString()},
          );
          await _restoreComposerSnapshot(
            composerSnapshot,
            optimisticMessageId: optimisticMessage.id,
            messenger: messenger,
            snackText: 'Failed to prepare media. Try again.',
          );
          return;
        }
      }

      // A v110 token binds upload-failure handling to the exact authored
      // parent and complete pending attachment manifest. Capture the durable
      // database projection before upload; the failure path re-reads it and
      // the repository repeats the same CAS plus global-v108 exclusion in its
      // transaction. A partial/malformed preparation deliberately leaves this
      // snapshot absent so a later upload failure can only refuse.
      ConversationMessage? manifestFailureParent;
      List<MediaAttachment> manifestFailureAttachments = const [];
      if (optimisticMessage.directMediaCustodyIntentId != null &&
          optimisticMedia != null) {
        final authoredPending = preparedUploads.length == optimisticMedia.length
            ? preparedUploads
                  .map((plan) => plan.pendingAttachment)
                  .toList(growable: false)
            : optimisticMedia
                  .map(
                    (attachment) => attachment.copyWith(
                      messageId: optimisticMessage.id,
                      downloadStatus: 'upload_pending',
                      ownerLane: MediaOwnerLane.direct,
                    ),
                  )
                  .toList(growable: false);
        try {
          final mediaRepository = widget.mediaAttachmentRepo;
          final durableParent = await widget.messageRepo.getMessage(
            optimisticMessage.id,
          );
          final durableAttachments = mediaRepository == null
              ? const <MediaAttachment>[]
              : await mediaRepository.getAttachmentsForMessage(
                  optimisticMessage.id,
                  owner: MediaOwnerLane.direct,
                );
          final exactManifest =
              optimisticMessage.directMediaCustodyIntentId ==
              computeDirectMediaCustodyIntentId(
                messageId: optimisticMessage.id,
                attachmentIds: authoredPending.map(
                  (attachment) => attachment.id,
                ),
              );
          if (durableParent != null &&
              exactManifest &&
              _sameComposerDatabaseMap(
                optimisticMessage.toMap(),
                durableParent.toMap(),
              ) &&
              _sameComposerAuthoredPendingProjection(
                authoredPending,
                durableAttachments,
              )) {
            manifestFailureParent = durableParent;
            manifestFailureAttachments = durableAttachments;
          }
        } catch (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONV_FL_MEDIA_CUSTODY_FAILURE_SNAPSHOT_ERROR',
            details: {'errorType': error.runtimeType.toString()},
          );
        }
      }

      // 354: protected/View-Once preparation authority is the durable private
      // parent plus its single convention-owned pending attachment. There is
      // no v110 token here and none is minted; a crossed/partial projection
      // deliberately leaves this snapshot absent so the unchanged legacy
      // private upload path is used instead.
      ConversationMessage? privateStrictParent;
      MediaAttachment? privateStrictAttachment;
      if (privateTransferLease != null &&
          preparedUploads.length == 1 &&
          mediaToUpload.length == 1) {
        try {
          final mediaRepository = widget.mediaAttachmentRepo;
          final durableParent = await widget.messageRepo.getMessage(
            optimisticMessage.id,
          );
          final durableAttachments = mediaRepository == null
              ? const <MediaAttachment>[]
              : await mediaRepository.getAttachmentsForMessage(
                  optimisticMessage.id,
                  owner: MediaOwnerLane.direct,
                );
          final authored = preparedUploads.single.pendingAttachment;
          if (durableParent != null &&
              durableAttachments.length == 1 &&
              durableParent.directMediaCustodyIntentId == null &&
              _sameComposerAuthoredPendingProjection(<MediaAttachment>[
                authored,
              ], durableAttachments)) {
            privateStrictParent = durableParent;
            privateStrictAttachment = durableAttachments.single;
          }
        } catch (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONV_FL_PRIVATE_MEDIA_CUSTODY_SNAPSHOT_ERROR',
            details: {'errorType': error.runtimeType.toString()},
          );
        }
      }

      // Acquire background task BEFORE upload so iOS cannot suspend during upload.
      final bgTaskId = widget.bridge != null
          ? await callBgBegin(widget.bridge!)
          : null;

      try {
        // Upload attachments if any
        List<MediaAttachment>? uploadedAttachments;
        DirectPrivateMediaFanoutContext? privateMediaFanoutContext;
        if (mediaToUpload.isNotEmpty && widget.bridge != null) {
          if (!mounted) return;
          final uploadOperation = _uploadActivityController.beginOperation(
            messageId: optimisticMessage.id,
            composerSnapshot: composerSnapshot,
            cancelFinalizer: (operation) async {
              final messageId = operation.messageId;
              final snapshot = operation.composerSnapshot;
              if (messageId == null || snapshot == null) return false;
              final cancellationApplied =
                  await _markUploadPendingAttachmentsCancelledForMessage(
                    messageId,
                    privateMediaPolicy: snapshot.privateMediaPolicy,
                  );
              if (!cancellationApplied) return false;
              if (_uploadActivityController.isCurrentOperation(operation) &&
                  mounted) {
                await _restoreComposerSnapshot(
                  snapshot,
                  optimisticMessageId: messageId,
                  messenger: messenger,
                  snackText: l10n.upload_cancelled,
                );
              } else {
                await _transitionSendingMessageToFailed(messageId);
              }
              return true;
            },
          );
          try {
            uploadedAttachments = [];
            var relayTrackingStarted = false;
            final DirectMediaBlobCustodyRepository? blobCustodyRepository =
                switch (widget.mediaAttachmentRepo) {
                  DirectMediaBlobCustodyRepository repository
                      when repository.supportsDirectMediaBlobCustody =>
                    repository,
                  _ => null,
                };
            // 358: a disappearing initial rides this exact ordinary strict
            // coordinator. Its producer matrix is re-checked here so a widened
            // composer selection can never reach encryption or network, and it
            // never acquires the private one-more-look transfer lease.
            final strictBlobSelected =
                widget.directMediaBlobCustodyClientEnabled &&
                privateTransferLease == null &&
                manifestFailureParent != null &&
                manifestFailureAttachments.length == mediaToUpload.length &&
                preparedUploads.length == mediaToUpload.length &&
                blobCustodyRepository != null &&
                (privateMediaPolicy.mode == PrivateMediaMode.ordinary ||
                    (manifestFailureAttachments.length == 1 &&
                        disappearingMediaInitialProducerMatrixAllows(
                          policyVersion: privateMediaPolicy.version,
                          mode: privateMediaPolicy.mode,
                          durationSeconds: privateMediaPolicy.durationSeconds,
                          mime: manifestFailureAttachments.single.mime,
                          mediaType:
                              manifestFailureAttachments.single.mediaType,
                        )));
            // 354: exactly one v1 Protected image/video or View-Once image
            // initial may adopt the same strict owner. The producer matrix is
            // re-checked here so a widened composer selection can never reach
            // encryption or network.
            final privateScalarGenerationAvailable =
                switch (blobCustodyRepository) {
                  OutgoingDirectPrivateMediaBlobGenerationRepository
                  repository =>
                    repository.supportsOutgoingDirectPrivateMediaBlobGeneration,
                  _ => false,
                };
            final privateFanoutGenerationAvailable =
                switch (blobCustodyRepository) {
                  OutgoingDirectPrivateMediaBlobFanoutGenerationRepository
                  repository =>
                    repository
                        .supportsOutgoingDirectPrivateMediaBlobFanoutGeneration,
                  _ => false,
                };
            final strictPrivateBlobSelected =
                widget.directMediaBlobCustodyClientEnabled &&
                privateTransferLease != null &&
                privateStrictParent != null &&
                privateStrictAttachment != null &&
                preparedUploads.length == 1 &&
                mediaToUpload.length == 1 &&
                blobCustodyRepository != null &&
                (mediaAdmission?.requiresLinkedFanout == true
                    ? privateFanoutGenerationAvailable
                    : privateScalarGenerationAvailable) &&
                privateMediaInitialProducerMatrixAllows(
                  policyVersion: privateMediaPolicy.version,
                  mode: privateMediaPolicy.mode,
                  mime: privateStrictAttachment.mime,
                  mediaType: privateStrictAttachment.mediaType,
                );
            if (strictPrivateBlobSelected) {
              final transferLease = privateTransferLease;
              final plan = preparedUploads.single;
              await _uploadActivityController.startTracking(
                uploadOperation,
                totalBytes: mediaToUpload.single.budgetBytes,
              );
              relayTrackingStarted = true;
              _uploadActivityController.markUploadStarted(
                uploadOperation,
                privateStrictAttachment.id,
              );
              final coordinator =
                  widget.preparedDirectMediaBlobCustodyCoordinator ??
                  PreparedDirectMediaBlobCustodyCoordinator(
                    repository: blobCustodyRepository,
                    artifactStore: DirectMediaBlobArtifactStore(),
                    prepareArtifact: widget.prepareEncryptedMediaArtifactFn,
                  );
              final source = PreparedDirectMediaBlobSource(
                attachment: privateStrictAttachment,
                plaintextPath: plan.absoluteDurablePath,
              );
              late final MediaAttachment strictCompletion;
              if (mediaAdmission?.requiresLinkedFanout == true) {
                final snapshot = mediaAdmission!.snapshot;
                if (snapshot == null) {
                  throw StateError(
                    'private fanout admission omitted its roster snapshot',
                  );
                }
                final fanoutResult = await coordinator
                    .prepareAndUploadPrivateFanout(
                      bridge: widget.bridge!,
                      identityPeerId: identity.peerId,
                      contactAccountPeerId: _contact.peerId,
                      snapshot: snapshot,
                      expectedParent: privateStrictParent,
                      source: source,
                    );
                if (!fanoutResult.isComplete ||
                    fanoutResult.attachments.length != 1) {
                  await _uploadActivityController.complete(uploadOperation);
                  _updateLocalMessageStatus(optimisticMessage.id, 'sending');
                  await _refreshMessageWithHydratedMedia(optimisticMessage.id);
                  if (mounted) _updateComposerState(isUploading: false);
                  return;
                }
                strictCompletion = fanoutResult.attachments.single;
                privateMediaFanoutContext = DirectPrivateMediaFanoutContext(
                  contactAccountPeerId: _contact.peerId,
                  snapshot: snapshot,
                  targetRows: fanoutResult.targetRows,
                );
              } else {
                if (mediaAdmission != null &&
                    !mediaAdmission.allowsIncumbentSingleTarget) {
                  throw StateError(
                    'private strict upload reached after an invalid '
                    'admission (${mediaAdmission.reason})',
                  );
                }
                final strictResult = await coordinator.prepareAndUploadPrivate(
                  bridge: widget.bridge!,
                  identityPeerId: identity.peerId,
                  recipientPeerId: _contact.peerId,
                  expectedParent: privateStrictParent,
                  source: source,
                  onGenerationReady:
                      widget.p2pService.isLocalPeer(_contact.peerId)
                      ? (artifacts) async {
                          for (final artifact in artifacts) {
                            await widget.p2pService.sendLocalMedia(
                              peerId: _contact.peerId,
                              filePath: artifact.absoluteCiphertextPath,
                              mime: kOpaqueMediaTransportMime,
                              mediaId: artifact.attachment.id,
                              fromPeerId: identity.peerId,
                              durationMs: artifact.attachment.durationMs,
                              enc: true,
                              encScheme: artifact.attachment.encryptionScheme,
                            );
                          }
                        }
                      : null,
                );
                if (!strictResult.isComplete ||
                    strictResult.attachments.length != 1) {
                  await _uploadActivityController.complete(uploadOperation);
                  _updateLocalMessageStatus(optimisticMessage.id, 'sending');
                  await _refreshMessageWithHydratedMedia(optimisticMessage.id);
                  if (mounted) _updateComposerState(isUploading: false);
                  return;
                }
                strictCompletion = strictResult.attachments.single;
              }
              if (strictCompletion.messageId != optimisticMessage.id) {
                await _uploadActivityController.complete(uploadOperation);
                _updateLocalMessageStatus(optimisticMessage.id, 'sending');
                await _refreshMessageWithHydratedMedia(optimisticMessage.id);
                if (mounted) _updateComposerState(isUploading: false);
                return;
              }
              final MediaAttachment completedPrivateAttachment;
              try {
                completedPrivateAttachment =
                    await _canonicalizeStrictPrivateCompletion(
                      messageId: optimisticMessage.id,
                      plan: plan,
                      strict: strictCompletion,
                    );
              } catch (error) {
                emitFlowEvent(
                  layer: 'FL',
                  event: 'CONV_FL_PRIVATE_STRICT_CANONICALIZE_ERROR',
                  details: {'errorType': error.runtimeType.toString()},
                );
                await _uploadActivityController.complete(uploadOperation);
                _updateLocalMessageStatus(optimisticMessage.id, 'sending');
                await _refreshMessageWithHydratedMedia(optimisticMessage.id);
                if (mounted) _updateComposerState(isUploading: false);
                return;
              }
              uploadedAttachments.add(
                await _commitForegroundDirectPrivateCompletion(
                  lease: transferLease,
                  plan: plan,
                  uploaded: completedPrivateAttachment,
                ),
              );
              _uploadActivityController.markUploadCompleted(
                uploadOperation,
                mediaToUpload.single.budgetBytes,
              );
            } else if (strictBlobSelected) {
              final totalBytes = mediaToUpload.fold<int>(
                0,
                (sum, item) => sum + item.budgetBytes,
              );
              await _uploadActivityController.startTracking(
                uploadOperation,
                totalBytes: totalBytes,
              );
              relayTrackingStarted = true;
              for (final attachment in manifestFailureAttachments) {
                _uploadActivityController.markUploadStarted(
                  uploadOperation,
                  attachment.id,
                );
              }
              final coordinator =
                  widget.preparedDirectMediaBlobCustodyCoordinator ??
                  PreparedDirectMediaBlobCustodyCoordinator(
                    repository: blobCustodyRepository,
                    artifactStore: DirectMediaBlobArtifactStore(),
                    prepareArtifact: widget.prepareEncryptedMediaArtifactFn,
                  );
              final expectedById = <String, MediaAttachment>{
                for (final attachment in manifestFailureAttachments)
                  attachment.id: attachment,
              };
              // 362: the target route was resolved ONCE, above every durable
              // write, and is carried here. The roster is deliberately not
              // re-read: a pairing that lands mid-send must not turn an
              // already-persisted generation into a late refusal.
              final routedSnapshot = mediaAdmission?.snapshot;
              if (mediaAdmission != null &&
                  mediaAdmission.requiresLinkedFanout &&
                  routedSnapshot != null) {
                final fanoutResult = await coordinator
                    .prepareAndUploadFreshFanout(
                      bridge: widget.bridge!,
                      identityPeerId: identity.peerId,
                      contactAccountPeerId: _contact.peerId,
                      snapshot: routedSnapshot,
                      expectedParent: manifestFailureParent,
                      sources: preparedUploads
                          .map(
                            (plan) => PreparedDirectMediaBlobSource(
                              attachment:
                                  expectedById[plan.pendingAttachment.id] ??
                                  plan.pendingAttachment,
                              plaintextPath: plan.absoluteDurablePath,
                            ),
                          )
                          .toList(growable: false),
                    );
                if (!fanoutResult.isComplete) {
                  await _uploadActivityController.complete(uploadOperation);
                  _updateLocalMessageStatus(optimisticMessage.id, 'sending');
                  await _refreshMessageWithHydratedMedia(optimisticMessage.id);
                  if (mounted) _updateComposerState(isUploading: false);
                  return;
                }
                uploadedAttachments.addAll(fanoutResult.attachments);
                for (var index = 0; index < mediaToUpload.length; index++) {
                  _uploadActivityController.markUploadCompleted(
                    uploadOperation,
                    mediaToUpload[index].budgetBytes,
                  );
                }
              } else {
                final strictResult = await coordinator.prepareAndUploadFresh(
                  bridge: widget.bridge!,
                  identityPeerId: identity.peerId,
                  recipientPeerId: _contact.peerId,
                  expectedParent: manifestFailureParent,
                  sources: preparedUploads
                      .map(
                        (plan) => PreparedDirectMediaBlobSource(
                          attachment:
                              expectedById[plan.pendingAttachment.id] ??
                              plan.pendingAttachment,
                          plaintextPath: plan.absoluteDurablePath,
                        ),
                      )
                      .toList(growable: false),
                  onGenerationReady:
                      widget.p2pService.isLocalPeer(_contact.peerId)
                      ? (artifacts) async {
                          for (final artifact in artifacts) {
                            await widget.p2pService.sendLocalMedia(
                              peerId: _contact.peerId,
                              filePath: artifact.absoluteCiphertextPath,
                              mime: kOpaqueMediaTransportMime,
                              mediaId: artifact.attachment.id,
                              fromPeerId: identity.peerId,
                              durationMs: artifact.attachment.durationMs,
                              enc: true,
                              encScheme: artifact.attachment.encryptionScheme,
                            );
                          }
                        }
                      : null,
                );
                if (!strictResult.isComplete) {
                  await _uploadActivityController.complete(uploadOperation);
                  _updateLocalMessageStatus(optimisticMessage.id, 'sending');
                  await _refreshMessageWithHydratedMedia(optimisticMessage.id);
                  if (mounted) _updateComposerState(isUploading: false);
                  return;
                }
                uploadedAttachments.addAll(strictResult.attachments);
                for (var index = 0; index < mediaToUpload.length; index++) {
                  _uploadActivityController.markUploadCompleted(
                    uploadOperation,
                    mediaToUpload[index].budgetBytes,
                  );
                }
              }
            } else {
              // 362: this is the incumbent single-target lane. A generation
              // the admission boundary routed to fanout may NEVER arrive here
              // — a false strict predicate (durable re-read mismatch, swallowed
              // snapshot error, absent capability) must be a hard failure, not
              // a silent demotion to one recipient on an initialized roster.
              if (mediaAdmission != null &&
                  mediaAdmission.requiresLinkedFanout) {
                throw StateError(
                  'linked-fanout generation reached the incumbent '
                  'single-target upload lane',
                );
              }
              for (var index = 0; index < mediaToUpload.length; index++) {
                if (await _cancelActiveAttachmentUploadIfRequested(
                  operation: uploadOperation,
                )) {
                  return;
                }
                final media = mediaToUpload[index];
                final preparedUpload = preparedUploads.length > index
                    ? preparedUploads[index]
                    : null;
                final mime =
                    preparedUpload?.pendingAttachment.mime ??
                    _mimeFromPath(media.file.path);
                final mediaId =
                    preparedUpload?.pendingAttachment.id ??
                    optimisticMedia?[index].id ??
                    _uuid.v4();
                final sourcePath =
                    preparedUpload?.absoluteDurablePath ?? media.file.path;
                final fileSize =
                    preparedUpload?.source.budgetBytes ??
                    File(sourcePath).lengthSync();

                // Try local WiFi first, then keep relay upload as the durable
                // recovery copy because local ACK does not prove DB persistence.
                // 112 Phase 4: encrypt once — the LAN leg streams the SAME
                // ciphertext artifact the relay upload below consumes, with an
                // opaque transport mime (the real mime rides the envelope).
                EncryptedMediaArtifact? preparedArtifact;
                if (widget.p2pService.isLocalPeer(_contact.peerId) &&
                    widget.bridge != null) {
                  try {
                    preparedArtifact = await widget
                        .prepareEncryptedMediaArtifactFn(
                          bridge: widget.bridge!,
                          localFilePath: sourcePath,
                        );
                    await widget.p2pService.sendLocalMedia(
                      peerId: _contact.peerId,
                      filePath: preparedArtifact.encryptedPath,
                      mime: kOpaqueMediaTransportMime,
                      mediaId: mediaId,
                      fromPeerId: identity.peerId,
                      durationMs: media.durationMs,
                      enc: true,
                      encScheme: preparedArtifact.scheme,
                    );
                  } catch (_) {
                    // Fail closed on the LAN leg — never fall back to raw
                    // bytes; the relay upload below mints its own artifact.
                    preparedArtifact = null;
                  }
                }

                if (!relayTrackingStarted) {
                  final remainingBytes = mediaToUpload
                      .skip(index)
                      .fold<int>(0, (sum, item) => sum + item.budgetBytes);
                  await _uploadActivityController.startTracking(
                    uploadOperation,
                    totalBytes: remainingBytes,
                  );
                  relayTrackingStarted = true;
                }
                _uploadActivityController.markUploadStarted(
                  uploadOperation,
                  mediaId,
                );
                final uploadOutcome = await runUploadMedia(
                  uploadMediaFn: widget.uploadMediaFn,
                  bridge: widget.bridge!,
                  localFilePath: sourcePath,
                  mime: mime,
                  recipientPeerId: _contact.peerId,
                  mediaFileManager: widget.mediaFileManager,
                  blobId: mediaId,
                  width: preparedUpload?.source.width ?? media.width,
                  height: preparedUpload?.source.height ?? media.height,
                  durationMs:
                      preparedUpload?.source.durationMs ?? media.durationMs,
                  // After uploadMedia commits its canonical owned copy it may
                  // unlink this pending source. Finalization therefore trusts
                  // the canonical relative path returned by the upload result.
                  deleteSourceWhenDone:
                      privateTransferLease == null &&
                      optimisticMessage.directMediaCustodyIntentId == null,
                  preparedArtifact: preparedArtifact,
                );
                final result = uploadOutcome.attachmentOrNull;

                if (await _cancelActiveAttachmentUploadIfRequested(
                  operation: uploadOperation,
                )) {
                  return;
                }

                if (result == null) {
                  if (relayTrackingStarted) {
                    await _uploadActivityController.complete(uploadOperation);
                  }
                  final failure = uploadOutcome as UploadMediaFailed;
                  UploadRetryProjectionResult projected;
                  if (optimisticMessage.directMediaCustodyIntentId != null) {
                    final expectedParent = manifestFailureParent;
                    if (expectedParent == null ||
                        manifestFailureAttachments.isEmpty) {
                      projected =
                          const UploadRetryProjectionResult.notApplied();
                    } else {
                      projected =
                          await _projectManifestBoundComposerUploadFailure(
                            expectedParent: expectedParent,
                            expectedAttachments: manifestFailureAttachments,
                            failedAttachmentId: mediaId,
                            failure: failure,
                          );
                    }
                    if (!projected.applied) {
                      emitFlowEvent(
                        layer: 'FL',
                        event: 'CONV_FL_MEDIA_CUSTODY_FAILURE_REFUSED',
                        details: const {},
                      );
                      await _restoreComposerSnapshot(
                        composerSnapshot,
                        optimisticMessageId: optimisticMessage.id,
                        messenger: messenger,
                        snackText: 'Failed to upload media. Try again.',
                        transitionMessageToFailed: false,
                      );
                      return;
                    }
                  } else {
                    final projection = _uploadRetryProjection;
                    if (projection == null) {
                      await _restoreComposerSnapshot(
                        composerSnapshot,
                        optimisticMessageId: optimisticMessage.id,
                        messenger: messenger,
                        snackText: 'Failed to upload media. Try again.',
                      );
                      return;
                    }
                    projected = await projection.projectUploadFailure(
                      messageId: optimisticMessage.id,
                      attachmentId: mediaId,
                      failure: failure,
                    );
                  }
                  if (!projected.isTerminal) {
                    _updateLocalMessageStatus(optimisticMessage.id, 'sending');
                    await _refreshMessageWithHydratedMedia(
                      optimisticMessage.id,
                    );
                    if (mounted) {
                      _updateComposerState(isUploading: false);
                    }
                    return;
                  }
                  await _restoreComposerAfterProjectedTerminal(
                    composerSnapshot,
                    optimisticMessageId: optimisticMessage.id,
                    messenger: messenger,
                    snackText: 'Failed to upload media. Try again.',
                  );
                  return;
                }
                _uploadActivityController.markUploadCompleted(
                  uploadOperation,
                  fileSize,
                );
                if (preparedUpload != null &&
                    widget.mediaAttachmentRepo != null) {
                  final stableResult =
                      await _finalizeUploadedAttachmentFromPlan(
                        messageId: optimisticMessage.id,
                        plan: preparedUpload,
                        uploaded: result,
                        trustUploadedLocalPath: privateTransferLease != null,
                        enforceAuthoredIdentity:
                            optimisticMessage.directMediaCustodyIntentId !=
                            null,
                      );
                  final transferLease = privateTransferLease;
                  if (transferLease != null) {
                    uploadedAttachments.add(
                      await _commitForegroundDirectPrivateCompletion(
                        lease: transferLease,
                        plan: preparedUpload,
                        uploaded: stableResult,
                      ),
                    );
                  } else if (optimisticMessage.directMediaCustodyIntentId !=
                      null) {
                    // The v110 intent is exclusive preparation authority. Keep
                    // its exact pending row untouched and carry upload-owned
                    // completion fields directly to the combined parent +
                    // attachments + v108 transaction below. This prevents a
                    // generic save from laundering a crossed/deleted authored
                    // row before final revalidation.
                    uploadedAttachments.add(stableResult);
                  } else {
                    await widget.mediaAttachmentRepo!.saveAttachment(
                      stableResult,
                      owner: MediaOwnerLane.direct,
                    );
                    uploadedAttachments.add(stableResult);
                  }
                } else {
                  uploadedAttachments.add(result);
                }

                if (await _cancelActiveAttachmentUploadIfRequested(
                  operation: uploadOperation,
                )) {
                  return;
                }
              }
            }
            if (await _cancelActiveAttachmentUploadIfRequested(
              operation: uploadOperation,
            )) {
              return;
            }
            if (relayTrackingStarted) {
              await _uploadActivityController.complete(uploadOperation);
            }
            if (mounted) {
              _updateComposerState(isUploading: false);
            }
          } finally {
            await _uploadActivityController.complete(uploadOperation);
          }
        }

        // Re-read contact from DB to pick up ML-KEM key updates that may
        // have arrived via reciprocal contact request since this screen opened.
        if (widget.contactRepo != null) {
          final fresh = await widget.contactRepo!.getContact(_contact.peerId);
          if (fresh != null && mounted) {
            setState(() => _contact = fresh);
          }
        }

        final sendOutcome = privateMediaFanoutContext == null
            ? await widget.sendChatMessageFn(
                p2pService: widget.p2pService,
                messageRepo: widget.messageRepo,
                targetPeerId: _contact.peerId,
                text: sanitizedText,
                senderPeerId: identity.peerId,
                senderUsername: identity.username,
                messageId: optimisticMessage.id,
                preassignedMessageIdIsFresh: stagesFreshDirectTextCustody,
                timestamp: optimisticMessage.timestamp,
                bridge: widget.bridge,
                recipientMlKemPublicKey: _contact.mlKemPublicKey,
                quotedMessageId: quotedMessageId,
                mediaAttachments: uploadedAttachments,
                privateMediaPolicy: privateMediaPolicy,
                mediaAttachmentRepo: widget.mediaAttachmentRepo,
                transportMetrics: widget.transportMetrics,
                directEventFanout: widget.directEventFanout,
              )
            : await widget.sendPrivateMediaFanoutChatMessageFn(
                p2pService: widget.p2pService,
                messageRepo: widget.messageRepo,
                targetPeerId: _contact.peerId,
                text: sanitizedText,
                senderPeerId: identity.peerId,
                senderUsername: identity.username,
                messageId: optimisticMessage.id,
                preassignedMessageIdIsFresh: stagesFreshDirectTextCustody,
                timestamp: optimisticMessage.timestamp,
                bridge: widget.bridge,
                recipientMlKemPublicKey: _contact.mlKemPublicKey,
                quotedMessageId: quotedMessageId,
                mediaAttachments: uploadedAttachments,
                privateMediaPolicy: privateMediaPolicy,
                mediaAttachmentRepo: widget.mediaAttachmentRepo,
                transportMetrics: widget.transportMetrics,
                directEventFanout: widget.directEventFanout,
                directPrivateMediaFanout: privateMediaFanoutContext,
              );
        final (result, message) = sendOutcome;

        if (preparedUploads.isNotEmpty &&
            uploadedAttachments != null &&
            uploadedAttachments.length == mediaToUpload.length &&
            !uploadedAttachments.any(
              (attachment) => attachment.blobCustody != null,
            ) &&
            privateTransferLease == null) {
          try {
            if (optimisticMessage.directMediaCustodyIntentId == null) {
              await widget.mediaFileManager?.deletePendingUploadDir(
                optimisticMessage.id,
              );
            } else {
              final durableParent = await widget.messageRepo.getMessage(
                optimisticMessage.id,
              );
              // Generic message saves cannot clear this token. A null durable
              // value therefore proves the combined custody transaction
              // committed before pending-source cleanup.
              if (durableParent != null &&
                  durableParent.directMediaCustodyIntentId == null) {
                await widget.mediaFileManager?.deletePendingUploadDir(
                  optimisticMessage.id,
                );
              }
            }
          } catch (_) {}
        }

        if (!mounted) return;

        // 127-Bug-A: own-sent media is persisted with a RELATIVE local_path
        // (media/<peer>/<blob>.jpg). MediaGridCell checks File(localPath)
        // .existsSync() verbatim, so a relative path renders "Media unavailable"
        // even though the durable file exists. Resolve to absolute ONCE and
        // apply in BOTH result branches — previously only the message != null
        // branch resolved, leaving a null-message result showing the optimistic
        // message's now-deleted picker-temp paths as unavailable.
        // The direct send boundary returns the canonical local projection
        // (message id + direct owner lane). Resolve paths on that projection
        // instead of replacing it with the pre-boundary upload objects, whose
        // local-only owner is intentionally unresolved.
        final canonicalMedia = message != null && message.media.isNotEmpty
            ? message.media
            : uploadedAttachments;
        final displayMedia = await _resolveDisplayMedia(canonicalMedia);
        if (!mounted) return;

        // 185: when a 1:1 send fails ONLY because the SENDER is offline
        // (relay unreachable) with a connectivity-class result, keep the row in
        // the retriable self-healing lane — status 'sent', wire envelope
        // preserved — so `retryUnacked` + the delivery receipt converge it to
        // 'delivered', instead of dropping it to terminal 'failed' (a red Retry
        // that never clears even after the peer receives it). peerNotFound /
        // dialFailed persist their wire envelope before the transport race and
        // return that authoritative row, so the kept-'sent' row is
        // getUnackedOutgoingMessages-eligible.
        // 185×187 (field-hit 2026-07-02): sendFailed is ALSO lane-eligible, but
        // ONLY in its terminal-rung shape (message != null — the use case
        // persisted the wire envelope). With the 183 keepalive latched, 187
        // skips the direct dial and the race fails with reason
        // 'direct_skipped_keepalive_drop' → _resultForFailureReason →
        // sendFailed; without this arm an offline sender regressed to the
        // pre-185 terminal 'failed' + Retry. The message != null guard keeps
        // every NULL-shaped return (including defensive connectivity results
        // and encrypt_failed/encrypt_error) out of the lane because it carries
        // no envelope authority and is NOT self-healing.
        // nodeNotRunning is EXCLUDED: it returns before the envelope is
        // persisted, so its row is not lane-eligible and belongs in the failed /
        // retryFailedMessages lane.
        // 192 (field-hit 2026-07-02): the lane is ALSO open when relayReady
        // reads TRUE, provided the wire envelope was persisted (message !=
        // null). Secured inbox custody returns success, so a connectivity-class
        // failure carrying an envelope can only mean the relay state was STALE
        // (the network-transition window) — the wire disagreed with the state.
        // Terminal 'failed' there is a Retry that flashes for ~15 s until the
        // delivery receipt heals it; the honest state is 'sent' + retryUnacked.
        // Envelope-less shapes (encrypt_failed, and the null-shaped defensive
        // arms) are NOT self-healing and stay terminal when online.
        final senderOffline = !widget.p2pService.currentState.relayReady;
        final keepRetriable =
            (result == SendChatMessageResult.peerNotFound ||
                result == SendChatMessageResult.dialFailed ||
                result == SendChatMessageResult.sendFailed) &&
            message != null;

        if (message != null) {
          final persistedMedia =
              displayMedia ?? uploadedAttachments ?? optimisticMedia;
          ConversationMessage? authoritativeMessage = message;
          if (keepRetriable &&
              !_isOutgoingPrivateOneMoreLook(privateMediaPolicy)) {
            authoritativeMessage = await _settleRetriableOrdinaryMessage(
              message,
            );
          }
          if (authoritativeMessage != null) {
            final effectiveStatus =
                keepRetriable &&
                    _isOutgoingPrivateOneMoreLook(privateMediaPolicy)
                ? 'sent'
                : authoritativeMessage.status;
            final messageWithMedia = authoritativeMessage.copyWith(
              quotedMessageId: quotedMessageId,
              media: persistedMedia ?? authoritativeMessage.media,
              status: effectiveStatus,
            );
            setState(() {
              _upsertMessageById(messageWithMedia);
            });
          } else {
            _removeLocalMessage(message.id);
          }
          _scrollToBottom();
        } else {
          // A null result carries no durable envelope/transport authority. Keep
          // the exact optimistic sending -> failed edge and then paint only the
          // authoritative row that won that CAS.
          final authoritativeMessage = await _transitionSendingMessageToFailed(
            optimisticMessage.id,
          );
          final resolvedMedia = displayMedia ?? uploadedAttachments;
          if (authoritativeMessage != null &&
              resolvedMedia != null &&
              resolvedMedia.isNotEmpty) {
            // Re-point the on-screen optimistic message at the resolved absolute
            // durable copies (its picker temps were deleted post-upload).
            setState(() {
              _upsertMessageById(
                authoritativeMessage.copyWith(media: resolvedMedia),
              );
            });
          } else if (authoritativeMessage != null) {
            await _refreshMessageWithHydratedMedia(optimisticMessage.id);
          } else {
            _removeLocalMessage(optimisticMessage.id);
          }
        }

        if (result != SendChatMessageResult.success) {
          // 185: name the REAL cause. When WE are offline, a connectivity-class
          // failure must not blame the contact — say so honestly (and truthfully
          // promise the queued send). nodeNotRunning is inherently sender-side,
          // so it always uses this copy. For every other shape the honest copy
          // is tied DIRECTLY to the lane decision (keepRetriable): the
          // "will send when you're back online" promise is shown exactly when
          // the row really is queued in the self-healing lane — the old per-arm
          // `senderOffline ?` ternaries are deleted so a new failure shape can
          // never again show contact-blaming copy (or a false promise) while
          // offline (the 185×187 'direct_skipped_keepalive_drop' regression,
          // field-hit 2026-07-02).
          // Short one-liner: the wifi-off glyph carries "no internet", the
          // text carries the self-healing promise.
          // 192: when the lane is open but the phone BELIEVES it is online
          // (stale relay state), "back online" would be dishonest — the queued-
          // retry copy names what is actually happening.
          final senderOfflineCopy = l10n.offline_send_promise;
          final queuedRetryCopy = l10n.offline_retry_delayed;
          final snackText =
              result == SendChatMessageResult.nodeNotRunning ||
                  (keepRetriable && senderOffline)
              ? senderOfflineCopy
              : keepRetriable
              ? queuedRetryCopy
              : switch (result) {
                  SendChatMessageResult.peerNotFound =>
                    'Contact appears offline. Message saved.',
                  SendChatMessageResult.dialFailed =>
                    'Could not connect to contact. Message saved.',
                  SendChatMessageResult.invalidMessage =>
                    'Message cannot be empty.',
                  SendChatMessageResult.encryptionRequired =>
                    'Cannot send: contact does not support encryption.',
                  _ => 'Failed to send message. Message saved.',
                };
          // 185: the self-healing copies describe a benign, queued state (the
          // message will send without user action), NOT a failure — give them
          // an informational slate tone instead of the error-red reserved for
          // genuine send failures.
          final selfHealingCopy =
              snackText == senderOfflineCopy || snackText == queuedRetryCopy;
          final snackColor = selfHealingCopy
              ? Colors.blueGrey[700]
              : Colors.red[700];
          // 185: for a kept-retriable send the row is safely queued for the
          // self-healing lane, so DO NOT restore the composer draft or let
          // _restoreComposerSnapshot re-stamp it 'failed' — that would resurrect
          // the Retry this fix removes and invite a duplicate send. Just surface
          // the honest snackbar. Genuine failures still restore + go 'failed'.
          if (!keepRetriable) {
            await _restoreComposerSnapshot(
              composerSnapshot,
              optimisticMessageId: optimisticMessage.id,
              messenger: messenger,
              snackText: snackText,
              showSnackBar: false,
            );
          }
          // Self-healing: an icon + single-line text (wifi-off reads "no
          // internet, it's handled"; schedule-send reads "queued, retrying");
          // other failures keep the plain text.
          final snackContent = selfHealingCopy
              ? Row(
                  children: [
                    Icon(
                      snackText == senderOfflineCopy
                          ? Icons.wifi_off_rounded
                          : Icons.schedule_send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        snackText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Text(snackText);
          messenger?.showSnackBar(
            SnackBar(
              content: snackContent,
              backgroundColor: snackColor,
              behavior: SnackBarBehavior.floating,
              margin: _composerClearingSnackBarMargin(),
            ),
          );
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_SEND_ERROR',
          details: {'error': e.toString()},
        );
        if (!mounted) return;
        await _restoreComposerSnapshot(
          composerSnapshot,
          optimisticMessageId: optimisticMessage.id,
          messenger: messenger,
          snackText: 'Failed to send message. Message saved.',
        );
      } finally {
        if (bgTaskId != null && widget.bridge != null) {
          await callBgEnd(widget.bridge!, bgTaskId);
        }
      }
    } finally {
      final transferLease = privateTransferLease;
      if (transferLease != null) {
        await _releaseForegroundDirectPrivateTransfer(transferLease);
      }
      final lease = uploadLease;
      if (lease != null) {
        mediaUploadInFlightTracker.release(lease);
      }
      if (mounted) {
        setState(() => _isSending = false);
      } else {
        _isSending = false;
      }
    }
  }

  /// 127-Bug-A: resolves each attachment's stored (relative) `localPath` to an
  /// absolute filesystem path for in-memory display. `MediaGridCell` checks
  /// `File(localPath).existsSync()` verbatim, so a relative path would render
  /// "Media unavailable" even though the durable file exists. Returns the input
  /// unchanged when there is nothing to resolve (no manager / null list).
  Future<List<MediaAttachment>?> _resolveDisplayMedia(
    List<MediaAttachment>? attachments,
  ) async {
    final manager = widget.mediaFileManager;
    if (attachments == null || manager == null) {
      return attachments;
    }
    final resolved = <MediaAttachment>[];
    for (final attachment in attachments) {
      final localPath = attachment.localPath;
      if (localPath != null) {
        final absPath = await manager.resolveStoredPath(localPath);
        resolved.add(attachment.copyWith(localPath: absPath));
      } else {
        resolved.add(attachment);
      }
    }
    return resolved;
  }

  void _onDraftChanged(String text) {
    if (_draftText == text) return;
    setState(() {
      _draftText = text;
      final restoredDraft = _restoredFailedDraftText;
      if (restoredDraft != null && sanitizeMessageText(text) != restoredDraft) {
        _clearRestoredFailedDraftTracking();
      }
    });
    if (sanitizeMessageText(text).trim().isNotEmpty &&
        _privateMediaPolicy.isPrivate) {
      _privateMediaPolicy = const PrivateMediaPolicy.ordinary();
      _privateMediaPolicyInvalidated = false;
    }
    _updateComposerState();
  }

  bool _shouldRetryRestoredFailedDraft({
    required String sanitizedText,
    required bool hasAttachments,
  }) {
    final restoredMessageId = _restoredFailedMessageId;
    final restoredDraftText = _restoredFailedDraftText;
    if (restoredMessageId == null || restoredDraftText == null) return false;
    if (hasAttachments || _composerController.pendingAttachments.isNotEmpty) {
      return false;
    }
    if (sanitizedText != restoredDraftText) return false;
    return _activeQuoteMessageId == _restoredFailedQuotedMessageId;
  }

  Future<void> _retryRestoredFailedDraft() async {
    final restoredMessageId = _restoredFailedMessageId;
    if (restoredMessageId == null) return;

    final restoredMessage = await widget.messageRepo.getMessage(
      restoredMessageId,
    );
    if (!mounted) return;

    if (restoredMessage == null || restoredMessage.status != 'failed') {
      setState(() {
        if (restoredMessage != null) {
          _upsertMessageById(restoredMessage);
        }
        _draftText = '';
        _activeQuoteMessageId = null;
        _clearRestoredFailedDraftTracking();
      });
      return;
    }

    setState(() => _isSending = true);
    try {
      final retried = await _retryFailedMessageById(
        restoredMessageId,
        failureSnackText: 'Could not retry message.',
      );
      if (!mounted) return;
      if (retried > 0) {
        setState(() {
          _draftText = '';
          _activeQuoteMessageId = null;
          _clearRestoredFailedDraftTracking();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      } else {
        _isSending = false;
      }
    }
  }

  Future<void> _onRetryFailedMessage(String messageId) async {
    await _retryFailedMessageById(
      messageId,
      failureSnackText: 'Could not retry message.',
    );
  }

  Future<void> _onRetryFailedMedia(String messageId) async {
    await _retryFailedMessageById(
      messageId,
      failureSnackText: 'Could not retry media message.',
    );
  }

  Future<int> _retryFailedMessageById(
    String messageId, {
    required String failureSnackText,
  }) async {
    final bridge = widget.bridge;
    final contactRepo = widget.contactRepo;
    if (bridge == null || contactRepo == null) {
      _showFloatingSnackBar(
        'Retry unavailable right now.',
        backgroundColor: Colors.red[700],
      );
      return 0;
    }

    final fallbackMedia = _messages
        .where((message) => message.id == messageId)
        .firstOrNull
        ?.media;
    final retried = await retryFailedMessage(
      messageId: messageId,
      messageRepo: widget.messageRepo,
      identityRepo: widget.identityRepo,
      contactRepo: contactRepo,
      p2pService: widget.p2pService,
      bridge: bridge,
      mediaAttachmentRepo: widget.mediaAttachmentRepo,
      uploadMediaFn: widget.uploadMediaFn,
      mediaFileManager: widget.mediaFileManager,
      tryClaimUploadLease: (attachmentIds) => mediaUploadInFlightTracker
          .tryClaimAll(attachmentIds, source: MediaUploadTriggerSource.manual),
      releaseUploadLease: mediaUploadInFlightTracker.release,
    );

    await _refreshMessageWithHydratedMedia(
      messageId,
      fallbackMedia: fallbackMedia,
    );

    if (retried == 0) {
      _showFloatingSnackBar(failureSnackText, backgroundColor: Colors.red[700]);
    }
    return retried;
  }

  Future<void> _onDeleteFailedMedia(String messageId) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;

    final useGenericDeletion = mediaAttachmentRepo != null;
    if (mediaAttachmentRepo is OutgoingDirectPrivateMutationRepository) {
      if (mediaFileManager == null ||
          mediaAttachmentRepo is! DirectPrivateMediaCleanupRuntime) {
        return;
      }
      final privateMutationRepo =
          mediaAttachmentRepo as OutgoingDirectPrivateMutationRepository;
      final cleanupRuntime =
          mediaAttachmentRepo as DirectPrivateMediaCleanupRuntime;
      final lifecycleLock = privateMutationRepo
          .outgoingDirectPrivateMutationCoordinator
          .lifecycleLock;
      if (!identical(
        lifecycleLock,
        cleanupRuntime.directPrivateMediaLifecycleLock,
      )) {
        return;
      }
      late final OutgoingDirectPrivateNonCompletionMutationOutcome result;
      var privateParentDeleted = false;
      await lifecycleLock.synchronizedAll(() async {
        result = await privateMutationRepo
            .deleteOutgoingDirectPrivatePendingAttachmentsForMessage(
              messageId,
              mediaFileManager: mediaFileManager,
            );
        if (result ==
            OutgoingDirectPrivateNonCompletionMutationOutcome.applied) {
          privateParentDeleted =
              await widget.messageRepo.deleteMessage(messageId) > 0 ||
              await widget.messageRepo.getMessage(messageId) == null;
        }
      });
      if (result == OutgoingDirectPrivateNonCompletionMutationOutcome.applied) {
        if (privateParentDeleted) {
          _removeLocalMessage(messageId);
        } else {
          await _refreshMessageWithHydratedMedia(messageId);
        }
        return;
      } else if (result !=
          OutgoingDirectPrivateNonCompletionMutationOutcome.notPrivateParent) {
        return;
      }
    } else if (mediaAttachmentRepo != null) {
      final parent = await widget.messageRepo.getMessage(messageId);
      if (parent != null &&
          _isOutgoingPrivateOneMoreLook(parent.privateMediaPolicy)) {
        return;
      }
    }

    var parentDeletedUnderBlobAuthority = false;
    if (useGenericDeletion) {
      final ordinaryRepository = mediaAttachmentRepo;
      Future<bool> deleteOrdinaryMedia() async {
        if (!await _terminalizeOutgoingDirectMediaBlobForCancellation(
          messageId,
        )) {
          return false;
        }
        final storedAttachments = await ordinaryRepository
            .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct);
        await ordinaryRepository.markUploadPendingAttachmentsFailedForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        );
        // Ordinary-media cleanup keeps the attachment rows until plaintext
        // deletion succeeds. Those rows are the durable authority for the
        // exact pending paths; deleting them first would orphan plaintext when
        // the filesystem operation throws. Outgoing protected/View-Once media
        // has already returned through the typed branch above.
        try {
          await mediaFileManager?.deleteOwnedPendingUploadFilesForMessage(
            messageId: messageId,
            storedPaths: storedAttachments.map(
              (attachment) => attachment.localPath,
            ),
          );
        } catch (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONV_FL_ORDINARY_PENDING_FILE_DELETE_ERROR',
            details: {'error': error.runtimeType.toString()},
          );
          return false;
        }
        final deleted = await ordinaryRepository.deleteAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        );
        if (deleted != storedAttachments.length) return false;
        await widget.messageRepo.deleteMessage(messageId);
        return true;
      }

      late final bool deleted;
      if (ordinaryRepository is DirectMediaBlobCustodyRepository) {
        final custodyRepository =
            ordinaryRepository as DirectMediaBlobCustodyRepository;
        deleted = custodyRepository.supportsDirectMediaBlobCustody
            ? await custodyRepository.runDirectMediaBlobCustodyLifecycle(
                deleteOrdinaryMedia,
              )
            : await deleteOrdinaryMedia();
      } else {
        deleted = await deleteOrdinaryMedia();
      }
      if (!deleted) return;
      parentDeletedUnderBlobAuthority = true;
    }
    if (!parentDeletedUnderBlobAuthority) {
      await widget.messageRepo.deleteMessage(messageId);
    }

    _removeLocalMessage(messageId);
  }

  Future<void> _restoreComposerSnapshot(
    _DirectComposerSnapshot snapshot, {
    required String optimisticMessageId,
    required ScaffoldMessengerState? messenger,
    required String snackText,
    bool showSnackBar = true,
    bool transitionMessageToFailed = true,
  }) async {
    final commonSnapshot = snapshot.common;
    _draftText = commonSnapshot.draftText;
    _privateMediaPolicy = snapshot.privateMediaPolicy;
    _updateComposerState(restoreSnapshot: commonSnapshot, isUploading: false);
    final authoritativeMessage = transitionMessageToFailed
        ? await _transitionSendingMessageToFailed(optimisticMessageId)
        : await widget.messageRepo.getMessage(optimisticMessageId);
    if (authoritativeMessage == null) {
      if (_isOutgoingPrivateOneMoreLook(snapshot.privateMediaPolicy)) {
        // Preserve the established private-media composer retry projection
        // when its insert failed before any durable parent existed. This is a
        // local-only failed bubble; ordinary removed rows still disappear and
        // no insert-capable fallback is reintroduced.
        _updateLocalMessageStatus(optimisticMessageId, 'failed');
      } else {
        _removeLocalMessage(optimisticMessageId);
      }
    } else {
      await _refreshMessageWithHydratedMedia(optimisticMessageId);
    }
    if (commonSnapshot.pendingAttachments.isEmpty &&
        commonSnapshot.draftText.isNotEmpty) {
      _restoredFailedMessageId = optimisticMessageId;
      _restoredFailedDraftText = commonSnapshot.draftText;
      _restoredFailedQuotedMessageId = commonSnapshot.quotedMessageId;
    } else {
      _clearRestoredFailedDraftTracking();
    }
    if (mounted) {
      setState(() => _activeQuoteMessageId = commonSnapshot.quotedMessageId);
    }
    if (showSnackBar) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(snackText),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          margin: _composerClearingSnackBarMargin(),
        ),
      );
    }
  }

  Future<void> _restoreComposerAfterProjectedTerminal(
    _DirectComposerSnapshot snapshot, {
    required String optimisticMessageId,
    required ScaffoldMessengerState? messenger,
    required String snackText,
  }) async {
    final commonSnapshot = snapshot.common;
    _draftText = commonSnapshot.draftText;
    _privateMediaPolicy = snapshot.privateMediaPolicy;
    _updateComposerState(restoreSnapshot: commonSnapshot, isUploading: false);
    _updateLocalMessageStatus(optimisticMessageId, 'failed');
    await _refreshMessageWithHydratedMedia(optimisticMessageId);
    if (commonSnapshot.pendingAttachments.isEmpty &&
        commonSnapshot.draftText.isNotEmpty) {
      _restoredFailedMessageId = optimisticMessageId;
      _restoredFailedDraftText = commonSnapshot.draftText;
      _restoredFailedQuotedMessageId = commonSnapshot.quotedMessageId;
    } else {
      _clearRestoredFailedDraftTracking();
    }
    if (mounted) {
      setState(() => _activeQuoteMessageId = commonSnapshot.quotedMessageId);
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text(snackText),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        margin: _composerClearingSnackBarMargin(),
      ),
    );
  }

  void _clearRestoredFailedDraftTracking() {
    _restoredFailedMessageId = null;
    _restoredFailedDraftText = null;
    _restoredFailedQuotedMessageId = null;
  }

  static String _mimeFromPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska',
      'm4v': 'video/x-m4v',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  void _onAttach() {
    // 361: the restricted linked role authors blob-free events only.
    if (!widget.modalityGate.allowsMediaAuthoring) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_MODALITY_GATE_MEDIA_REFUSED',
        details: const {},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.linked_device_media_unavailable,
          ),
        ),
      );
      return;
    }
    final readableColors = context.backgroundReadableColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: readableColors.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: readableColors.divider),
      ),
      builder: (ctx) {
        final sheetColors = ctx.backgroundReadableColors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(
                  Icons.photo_library,
                  color: sheetColors.iconPrimary,
                ),
                title: Text(
                  AppLocalizations.of(context)!.picker_media_library,
                  style: TextStyle(color: sheetColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromGallery();
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: sheetColors.iconPrimary),
                title: Text(
                  AppLocalizations.of(context)!.picker_take_photo,
                  style: TextStyle(color: sheetColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromCamera();
                },
              ),
              ListTile(
                leading: Icon(Icons.videocam, color: sheetColors.iconPrimary),
                title: Text(
                  AppLocalizations.of(context)!.picker_record_video,
                  style: TextStyle(color: sheetColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickVideoFromCamera();
                },
              ),
              // 204 (BUG-1): explicit Cancel to go back to the chat. Dismisses
              // the sheet ONLY — never picks, never touches staged media.
              ListTile(
                key: ConversationWired.attachSheetCancelKey,
                leading: Icon(
                  Icons.close_rounded,
                  color: sheetColors.iconPrimary,
                ),
                title: Text(
                  AppLocalizations.of(context)!.btn_cancel,
                  style: TextStyle(color: sheetColors.textPrimary),
                ),
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFromGallery() async {
    try {
      final remaining =
          _maxAttachments - _composerController.pendingAttachments.length;
      if (remaining <= 0) return;

      final picked = await _mediaPicker.pickMultipleMedia();
      if (picked.isEmpty || !mounted) return;

      final selectedFiles = picked.take(remaining).toList();
      final processor = widget.imageProcessor;
      final processingTotal = selectedFiles
          .where((xf) => processor?.isProcessableVideo(xf.path) ?? false)
          .length;
      final useBatchProcessing = processingTotal > 1;
      var processingCurrent = 0;
      var didStartBatchProcessing = false;
      final media = <PendingComposerMedia>[];
      try {
        for (final xf in selectedFiles) {
          final isProcessableVideo =
              processor?.isProcessableVideo(xf.path) ?? false;
          if (useBatchProcessing && isProcessableVideo) {
            didStartBatchProcessing = true;
            processingCurrent++;
            _updateComposerState(
              isProcessing: true,
              processingProgress: 0.0,
              processingCurrent: processingCurrent,
              processingTotal: processingTotal,
            );
          }

          try {
            final result = await _preparePendingMedia(
              xf.path,
              ownsProcessingLifecycle: !useBatchProcessing,
            );
            media.add(result);
          } on _RejectedPendingMediaException {
            continue;
          }
        }
      } finally {
        if (useBatchProcessing && didStartBatchProcessing && mounted) {
          _updateComposerState(
            isProcessing: false,
            processingProgress: 0.0,
            processingCurrent: 0,
            processingTotal: 0,
          );
        }
      }

      if (!mounted) return;
      await _attemptAddPendingMedia(media);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_PICK_GALLERY_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final picked = await _mediaPicker.pickImage(source: ImageSource.camera);
      if (picked == null || !mounted) return;
      if (_composerController.pendingAttachments.length >= _maxAttachments) {
        return;
      }

      final result = await _preparePendingMedia(picked.path);
      if (!mounted) return;

      await _attemptAddPendingMedia([result]);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_PICK_CAMERA_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _pickVideoFromCamera() async {
    try {
      final picked = await _mediaPicker.pickVideo(source: ImageSource.camera);
      if (picked == null || !mounted) return;
      if (_composerController.pendingAttachments.length >= _maxAttachments) {
        return;
      }

      final result = await _preparePendingMedia(picked.path);
      if (!mounted) return;

      await _attemptAddPendingMedia([result]);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_PICK_VIDEO_CAMERA_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  // -- Voice recording --

  Future<void> _onRecordStart() async {
    // 361: the restricted linked role authors blob-free events only.
    if (!widget.modalityGate.allowsVoiceAuthoring) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_MODALITY_GATE_VOICE_REFUSED',
        details: const {},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.linked_device_voice_unavailable,
          ),
        ),
      );
      return;
    }
    final recorder = widget.audioRecorderService;
    if (recorder == null ||
        _composerViewState.recordingState.isActive ||
        _voiceCaptureController.state.isActive) {
      return;
    }

    _privateMediaPolicy = const PrivateMediaPolicy.ordinary();
    final result = await _voiceCaptureController.start(
      recorder: recorder,
      requestPermission: widget.micPermissionGateway.request,
    );
    if (!mounted ||
        result.scopeGeneration != _voiceCaptureController.scopeGeneration) {
      return;
    }

    if (result.status == ConversationVoiceCaptureStartStatus.permissionDenied) {
      // permanentlyDenied/restricted = the OS will no longer re-prompt
      // in-app, so the only recovery remains the system Settings deep-link.
      if (result.permissionStatus == MicPermissionStatus.permanentlyDenied) {
        await showMicPermissionDeniedPrompt(
          context,
          gateway: widget.micPermissionGateway,
        );
      }
      return;
    }
    if (result.status == ConversationVoiceCaptureStartStatus.failed) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_RECORD_START_ERROR',
        details: {'error': result.error.toString()},
      );
      return;
    }
    if (result.status == ConversationVoiceCaptureStartStatus.started) {
      emitFlowEvent(layer: 'FL', event: 'CONV_FL_RECORD_STARTED', details: {});
    }
  }

  Future<void> _onRecordStop() async {
    if (!_voiceCaptureController.state.isActive) {
      return;
    }

    if (_voiceCaptureController.state.phase ==
        ConversationVoiceCapturePhase.arming) {
      await _voiceCaptureController.stop();
      return;
    }

    final outcome = await _voiceCaptureController.stop();
    if (outcome == null || !_voiceCaptureController.isCurrentOutcome(outcome)) {
      return;
    }
    if (outcome.error != null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_RECORD_STOP_ERROR',
        details: {'error': outcome.error.toString()},
      );
      return;
    }

    final recording = outcome.recording;
    if (recording == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_RECORD_TOO_SHORT',
        details: {},
      );
      return;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_RECORD_STOPPED',
      details: {'durationMs': recording.durationMs},
    );

    await _sendVoiceRecording(recording, outcome.waveform);
  }

  /// Sends a captured voice [recording] (with its [waveform]) through the
  /// optimistic → LAN → relay pipeline. Shared by the manual stop
  /// ([_onRecordStop]) and the 5-minute auto-stop review-send
  /// ([_onReviewSend]) so a reviewed recording follows the exact same path.
  /// 362: puts a refused voice send back into the review-hold state instead of
  /// dropping it.
  ///
  /// `_onReviewSend` nulls `_pendingReviewRecording`/`_pendingReviewWaveform`
  /// and resets the composer to idle BEFORE calling `_sendVoiceRecording`, so
  /// a refusal that simply returned would orphan the recorder temp with no
  /// draft to restore. "Refuse with the source intact" means the user gets the
  /// recording back, not that the bytes silently leak.
  void _restoreVoiceReviewHoldAfterRefusal(
    AudioRecording recording,
    List<double> waveform,
  ) {
    if (!mounted) return;
    _pendingReviewRecording = recording;
    _pendingReviewWaveform = waveform;
    _updateComposerState(
      isUploading: false,
      recordingState: VoiceRecordingState.reviewing,
      recordingDuration: Duration(milliseconds: recording.durationMs),
      amplitudeValues: const [],
    );
  }

  Future<void> _sendVoiceRecording(
    AudioRecording recording,
    List<double> waveform,
  ) async {
    // Send the voice message
    final identity = _identity;
    if (identity == null) return;
    final quotedMessageId = _activeQuoteMessageId;

    // 362 ADMISSION BOUNDARY (voice). Both callers of this method — the
    // record-stop send and the review-hold send — carry a FRESH recording;
    // survivor replay never reaches here, it drains through the retry lanes
    // from stored authority. So the resolution below is fresh-only and never
    // re-reads the roster for a committed generation.
    //
    // The read-only recording validation is pulled up from the use case,
    // where it used to run only AFTER the durable copy, the recorder-temp
    // delete and both durable rows. The order the contract requires is:
    // validate, resolve, and only then take a lease or write anything.
    // Size only — deliberately no filesystem probe here. Existence stays in
    // the use case, which owns the recording bytes; hoisting an I/O check into
    // the widget would make the composer refuse recordings whose file is
    // supplied by the caller rather than the recorder.
    if (recording.sizeBytes <= 0 ||
        recording.sizeBytes > kMaxVoiceRecordingBytes) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_VOICE_SEND_INVALID_RECORDING',
        details: {'sizeBytes': recording.sizeBytes},
      );
      _restoreVoiceReviewHoldAfterRefusal(recording, waveform);
      return;
    }
    final fanoutCapableRepository =
        widget.mediaAttachmentRepo
            is OutgoingDirectLinkedMediaBlobFanoutRepository &&
        (widget.mediaAttachmentRepo
                as OutgoingDirectLinkedMediaBlobFanoutRepository)
            .supportsDirectLinkedMediaBlobFanout;
    final canServeLinkedFanout =
        widget.directMediaBlobCustodyClientEnabled &&
        widget.directLinkedEventFanoutEnabled &&
        widget
            .directLinkedMediaFanoutSelector
            .allowsDirectLinkedMediaFanoutAuthoring &&
        fanoutCapableRepository;
    final voiceAdmission = await resolveDirectMediaFanoutAdmission(
      mediaAttachmentRepository: widget.mediaAttachmentRepo,
      contactAccountPeerId: _contact.peerId,
      canServeLinkedFanout: canServeLinkedFanout,
    );
    if (voiceAdmission.refuses) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_VOICE_SEND_MEDIA_FANOUT_ADMISSION_REFUSED',
        details: {'reason': voiceAdmission.reason},
      );
      _restoreVoiceReviewHoldAfterRefusal(recording, waveform);
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final voiceMessageId = _uuid.v4();
    final voiceAttachmentId = _uuid.v4();
    final voiceUploadLease = mediaUploadInFlightTracker.tryClaimAll([
      voiceAttachmentId,
    ], source: MediaUploadTriggerSource.foreground);
    if (voiceUploadLease == null) return;

    if (quotedMessageId != null && mounted) {
      setState(() => _activeQuoteMessageId = null);
    }

    var storedVoicePath = recording.filePath;
    var uploadVoicePath = recording.filePath;
    final mediaFileManager = widget.mediaFileManager;
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    try {
      if (mediaFileManager != null && mediaAttachmentRepo != null) {
        storedVoicePath = await mediaFileManager.copyToDurableStorage(
          sourceFilePath: recording.filePath,
          messageId: voiceMessageId,
          attachmentId: voiceAttachmentId,
          mime: recording.mime,
        );
        uploadVoicePath = await mediaFileManager.resolveStoredPath(
          storedVoicePath,
        );
        if (uploadVoicePath != recording.filePath) {
          try {
            await File(recording.filePath).delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_VOICE_DURABLE_PREP_ERROR',
        details: {'error': e.toString()},
      );
      final failedMessage = ConversationMessage(
        id: voiceMessageId,
        contactPeerId: _contact.peerId,
        senderPeerId: identity.peerId,
        text: '',
        timestamp: now,
        status: 'failed',
        isIncoming: false,
        createdAt: now,
        quotedMessageId: quotedMessageId,
      );
      try {
        await widget.messageRepo.saveMessage(failedMessage);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _upsertMessageById(failedMessage);
          if (quotedMessageId != null) {
            _activeQuoteMessageId = quotedMessageId;
          }
        });
        _updateComposerState(isUploading: false);
        _showFloatingSnackBar(
          AppLocalizations.of(context)!.conversation_voice_fail,
          backgroundColor: Colors.red[700],
        );
      }
      mediaUploadInFlightTracker.release(voiceUploadLease);
      return;
    }

    final persistedVoiceAttachment = MediaAttachment(
      id: voiceAttachmentId,
      messageId: voiceMessageId,
      mime: recording.mime,
      size: recording.sizeBytes,
      mediaType: 'audio',
      durationMs: recording.durationMs,
      localPath: storedVoicePath,
      downloadStatus: 'upload_pending',
      createdAt: now,
      waveform: waveform,
    );
    final optimisticMessage = ConversationMessage(
      id: voiceMessageId,
      contactPeerId: _contact.peerId,
      senderPeerId: identity.peerId,
      text: '',
      timestamp: now,
      status: 'sending',
      isIncoming: false,
      createdAt: now,
      quotedMessageId: quotedMessageId,
      directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
        messageId: voiceMessageId,
        attachmentIds: <String>[voiceAttachmentId],
      ),
      media: [persistedVoiceAttachment.copyWith(localPath: uploadVoicePath)],
    );

    if (mounted) {
      setState(() {
        _upsertMessageById(optimisticMessage);
      });
      _updateComposerState(isUploading: true);
      _scrollToBottom();
    }

    try {
      await widget.messageRepo.saveMessage(optimisticMessage);
      await mediaAttachmentRepo?.saveAttachment(
        persistedVoiceAttachment,
        owner: MediaOwnerLane.direct,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_VOICE_OPTIMISTIC_SAVE_ERROR',
        details: {'error': e.toString()},
      );
      final failedMessage = optimisticMessage.copyWith(status: 'failed');
      final authoritativeMessage = await _transitionSendingMessageToFailed(
        optimisticMessage.id,
      );
      if (mounted) {
        setState(() {
          if (authoritativeMessage == null) {
            _messages = _messages
                .where((message) => message.id != failedMessage.id)
                .toList(growable: false);
          } else {
            _upsertMessageById(authoritativeMessage);
          }
          if (quotedMessageId != null) {
            _activeQuoteMessageId = quotedMessageId;
          }
        });
        _updateComposerState(isUploading: false);
      }
      mediaUploadInFlightTracker.release(voiceUploadLease);
      return;
    }

    final stagedRecording = AudioRecording(
      filePath: uploadVoicePath,
      durationMs: recording.durationMs,
      mime: recording.mime,
      sizeBytes: recording.sizeBytes,
    );

    // Re-read contact from DB to pick up ML-KEM key updates.
    if (widget.contactRepo != null) {
      try {
        final fresh = await widget.contactRepo!.getContact(_contact.peerId);
        if (fresh != null && mounted) {
          setState(() => _contact = fresh);
        }
      } catch (_) {}
    }

    // Acquire background task BEFORE local transfer / relay upload.
    String? bgTaskId;
    try {
      bgTaskId = widget.bridge != null
          ? await callBgBegin(widget.bridge!)
          : null;
    } catch (_) {
      bgTaskId = null;
    }

    try {
      // Try local WiFi first for voice messages, then keep the relay upload
      // fallback as the durable recovery copy.
      // 112 Phase 4: encrypt once — the LAN leg streams the ciphertext
      // artifact (opaque mime, no waveform in the cleartext offer; both
      // ride the encrypted envelope) and the relay upload reuses it.
      EncryptedMediaArtifact? voiceArtifact;
      final strictVoiceBlobSelected =
          widget.directMediaBlobCustodyClientEnabled &&
          switch (mediaAttachmentRepo) {
            DirectMediaBlobCustodyRepository repository
                when repository.supportsDirectMediaBlobCustody =>
              true,
            _ => false,
          };
      if (!strictVoiceBlobSelected &&
          widget.p2pService.isLocalPeer(_contact.peerId) &&
          widget.bridge != null) {
        try {
          voiceArtifact = await widget.prepareEncryptedMediaArtifactFn(
            bridge: widget.bridge!,
            localFilePath: uploadVoicePath,
          );
          await widget.p2pService.sendLocalMedia(
            peerId: _contact.peerId,
            filePath: voiceArtifact.encryptedPath,
            mime: kOpaqueMediaTransportMime,
            mediaId: voiceAttachmentId,
            fromPeerId: identity.peerId,
            durationMs: recording.durationMs,
            enc: true,
            encScheme: voiceArtifact.scheme,
          );
        } catch (_) {
          // Fail closed on the LAN leg — never stream the raw recording.
          voiceArtifact = null;
        }
      }

      final bridge = widget.bridge;
      if (bridge == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_VOICE_SEND_QUEUED_NO_BRIDGE',
          details: {},
        );
        if (mounted) {
          _updateComposerState(isUploading: false);
          _updateLocalMessageStatus(optimisticMessage.id, 'sending');
        }
        return;
      }

      // Upload + send (relay fallback)
      if (!mounted) return;
      final uploadOperation = _uploadActivityController.beginOperation();
      try {
        await _uploadActivityController.startTracking(
          uploadOperation,
          totalBytes: recording.sizeBytes,
        );
        _uploadActivityController.markUploadStarted(
          uploadOperation,
          voiceAttachmentId,
        );
        final (result, voiceMessage) = await widget.sendVoiceMessageFn(
          p2pService: widget.p2pService,
          messageRepo: widget.messageRepo,
          targetPeerId: _contact.peerId,
          senderPeerId: identity.peerId,
          senderUsername: identity.username,
          recording: stagedRecording,
          bridge: bridge,
          recipientMlKemPublicKey: _contact.mlKemPublicKey,
          mediaAttachmentRepo: widget.mediaAttachmentRepo,
          mediaFileManager: widget.mediaFileManager,
          waveform: waveform,
          messageId: optimisticMessage.id,
          timestamp: optimisticMessage.timestamp,
          quotedMessageId: quotedMessageId,
          blobId: voiceAttachmentId,
          preparedArtifact: voiceArtifact,
          mediaAdmission: voiceAdmission,
        );
        if (result == SendVoiceMessageResult.success) {
          _uploadActivityController.markUploadCompleted(
            uploadOperation,
            recording.sizeBytes,
          );
        }
        await _uploadActivityController.complete(uploadOperation);

        if (mounted) {
          _updateComposerState(isUploading: false);
        }

        if (result == SendVoiceMessageResult.success && voiceMessage != null) {
          // Replace optimistic with real message, preserving relay-backed media
          // when the send use case returns it and falling back to local playback
          // metadata for older/fake send paths.
          // DB already has correct data from sendChatMessage's saveMessage call.
          final messageWithMedia = voiceMessage.copyWith(
            media: voiceMessage.media.isNotEmpty
                ? voiceMessage.media
                : optimisticMessage.media,
          );
          if (mounted) {
            setState(() {
              _upsertMessageById(messageWithMedia);
            });
          }
        } else if (result == SendVoiceMessageResult.success) {
          final authoritativeMessage = await _transitionSendingMessageToFailed(
            optimisticMessage.id,
          );
          if (authoritativeMessage == null) {
            _removeLocalMessage(optimisticMessage.id);
          } else {
            await _refreshMessageWithHydratedMedia(optimisticMessage.id);
          }
        } else if (result == SendVoiceMessageResult.uploadQueued) {
          _updateLocalMessageStatus(optimisticMessage.id, 'sending');
          await _refreshMessageWithHydratedMedia(optimisticMessage.id);
        } else {
          ConversationMessage? authoritativeMessage;
          if (result != SendVoiceMessageResult.uploadFailed ||
              _uploadRetryProjection == null) {
            authoritativeMessage = await _transitionSendingMessageToFailed(
              optimisticMessage.id,
            );
          } else {
            authoritativeMessage = await widget.messageRepo.getMessage(
              optimisticMessage.id,
            );
          }
          if (authoritativeMessage == null) {
            _removeLocalMessage(optimisticMessage.id);
          } else {
            await _refreshMessageWithHydratedMedia(optimisticMessage.id);
          }
          if (quotedMessageId != null && mounted) {
            setState(() => _activeQuoteMessageId = quotedMessageId);
          }

          if (mounted) {
            final snackText = switch (result) {
              SendVoiceMessageResult.uploadFailed =>
                'Failed to upload voice message. Try again.',
              _ => AppLocalizations.of(context)!.conversation_voice_fail,
            };
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(snackText),
                backgroundColor: Colors.red[700],
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } finally {
        await _uploadActivityController.complete(uploadOperation);
      }
    } finally {
      mediaUploadInFlightTracker.release(voiceUploadLease);
      if (bgTaskId != null && widget.bridge != null) {
        await callBgEnd(widget.bridge!, bgTaskId);
      }
    }
  }

  Future<void> _onRecordCancel() async {
    if (!_voiceCaptureController.state.isActive) {
      return;
    }

    final wasArming =
        _voiceCaptureController.state.phase ==
        ConversationVoiceCapturePhase.arming;
    await _voiceCaptureController.cancel();
    if (wasArming) return;

    emitFlowEvent(layer: 'FL', event: 'CONV_FL_RECORD_CANCELLED', details: {});
  }

  void _onVoiceCaptureAutoStopOutcome(ConversationVoiceCaptureOutcome outcome) {
    // 117 Session 3: the recorder stopped itself at the max recording
    // duration without any user gesture. A VALID captured recording must NOT
    // be silently discarded — hold it in a `reviewing` composer state so the
    // user can send or discard it, and surface a SnackBar. Auto-send is
    // deliberately avoided (no surprise send). A sub-500ms clip (null) was
    // already cleaned up by the recorder and is dropped like a too-short stop.
    if (!mounted || !_voiceCaptureController.isCurrentOutcome(outcome)) {
      return;
    }

    final recording = outcome.recording;
    if (recording == null) {
      _updateComposerState(
        recordingState: VoiceRecordingState.idle,
        recordingDuration: Duration.zero,
        amplitudeValues: const [],
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_RECORD_AUTO_STOPPED',
        details: {'tooShort': true, 'kept': false},
      );
      return;
    }

    _pendingReviewRecording = recording;
    _pendingReviewWaveform = outcome.waveform;
    _updateComposerState(
      recordingState: VoiceRecordingState.reviewing,
      recordingDuration: Duration(milliseconds: recording.durationMs),
      amplitudeValues: const [],
    );
    _showFloatingSnackBar(
      AppLocalizations.of(context)!.conversation_voice_limit_reached,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_RECORD_AUTO_STOPPED',
      details: {
        'tooShort': false,
        'kept': true,
        'durationMs': recording.durationMs,
      },
    );
  }

  /// User chose to send the auto-stopped recording held for review.
  Future<void> _onReviewSend() async {
    final recording = _pendingReviewRecording;
    if (recording == null) return;
    final waveform = _pendingReviewWaveform;
    _pendingReviewRecording = null;
    _pendingReviewWaveform = const [];
    if (mounted) {
      _updateComposerState(
        recordingState: VoiceRecordingState.idle,
        recordingDuration: Duration.zero,
        amplitudeValues: const [],
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_RECORD_REVIEW_SENT',
      details: {'durationMs': recording.durationMs},
    );
    await _sendVoiceRecording(recording, waveform);
  }

  /// User chose to discard the auto-stopped recording held for review.
  Future<void> _onReviewDiscard() async {
    final recording = _pendingReviewRecording;
    _pendingReviewRecording = null;
    _pendingReviewWaveform = const [];
    if (recording != null) {
      try {
        final file = File(recording.filePath);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    if (mounted) {
      _updateComposerState(
        recordingState: VoiceRecordingState.idle,
        recordingDuration: Duration.zero,
        amplitudeValues: const [],
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_RECORD_REVIEW_DISCARDED',
      details: {'durationMs': recording?.durationMs},
    );
  }

  void _startListeningForReactions() {
    final listener = widget.reactionListener;
    if (listener == null) return;

    _reactionSubscription = listener.incomingReactionChangeStream
        .where((change) {
          // Only process reactions for messages in this conversation
          return _messages.any((m) => m.id == change.messageId);
        })
        .listen(
          _onIncomingReactionChange,
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_REACTION_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );
  }

  void _onIncomingReactionChange(ReactionChange change) {
    if (!mounted) return;
    _reactionProjectionController.applyChange(
      change,
      upsertPlacement:
          ConversationReactionUpsertPlacement.preserveExistingIndex,
    );
  }

  Future<void> _loadReactions(List<ConversationMessage> messages) async {
    final reactionRepo = widget.reactionRepo;
    if (reactionRepo == null || messages.isEmpty) return;

    try {
      final messageIds = messages.map((m) => m.id).toList();
      final reactions = await loadReactionsForConversation(
        reactionRepo: reactionRepo,
        messageIds: messageIds,
      );
      if (mounted) {
        _reactionProjectionController.replaceAll(reactions);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_LOAD_REACTIONS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onReactionSelected(String messageId, String emoji) async {
    final identity = _identity;
    if (identity == null) return;

    final reactionRepo = widget.reactionRepo;
    final bridge = widget.bridge;
    if (reactionRepo == null || bridge == null) return;

    // Check if toggling (same emoji from same user)
    final existingReactions = _reactionProjectionController.reactionsFor(
      messageId,
    );
    final ownReaction = existingReactions
        .where((r) => r.senderPeerId == identity.peerId)
        .firstOrNull;
    final optimisticAttempt = _reactionAttemptGuard.begin(messageId);

    if (ownReaction != null && ownReaction.emoji == emoji) {
      // Toggle off: remove reaction
      final updated = existingReactions
          .where((r) => r.senderPeerId != identity.peerId)
          .toList();
      _reactionProjectionController.replaceForMessage(messageId, updated);

      await widget.removeReactionFn(
        p2pService: widget.p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: _contact.peerId,
        messageId: messageId,
        emoji: emoji,
        senderPeerId: identity.peerId,
        recipientMlKemPublicKey: _contact.mlKemPublicKey ?? '',
        directEventFanout: widget.directEventFanout,
      );
      return;
    }

    // Add/replace reaction optimistically
    final now = DateTime.now().toUtc().toIso8601String();
    final optimisticReaction = MessageReaction(
      id: optimisticAttempt.optimisticReactionId,
      messageId: messageId,
      emoji: emoji,
      senderPeerId: identity.peerId,
      timestamp: now,
      createdAt: now,
    );

    final updated = List<MessageReaction>.from(existingReactions);
    final idx = updated.indexWhere(
      (reaction) => reaction.senderPeerId == identity.peerId,
    );
    if (idx >= 0) {
      updated[idx] = optimisticReaction;
    } else {
      updated.add(optimisticReaction);
    }
    _reactionProjectionController.replaceForMessage(messageId, updated);

    final (_, reaction) = await widget.sendReactionFn(
      p2pService: widget.p2pService,
      bridge: bridge,
      reactionRepo: reactionRepo,
      targetPeerId: _contact.peerId,
      messageId: messageId,
      emoji: emoji,
      senderPeerId: identity.peerId,
      recipientMlKemPublicKey: _contact.mlKemPublicKey ?? '',
      directEventFanout: widget.directEventFanout,
    );

    // The atomic custody stage, rather than the immediate transport diagnostic,
    // makes a returned reaction authoritative. Adopt it only while this exact
    // optimistic attempt is still the newest visible user intent. A delayed
    // ADD must never replace a later ADD or resurrect after a later REMOVE.
    if (reaction != null && mounted) {
      final updated = List<MessageReaction>.from(
        _reactionProjectionController.reactionsFor(messageId),
      );
      if (!_reactionAttemptGuard.canAdopt(
        attempt: optimisticAttempt,
        senderPeerId: identity.peerId,
        visibleReactions: updated,
      )) {
        return;
      }
      final idx = updated.indexWhere(
        (candidate) =>
            candidate.senderPeerId == identity.peerId &&
            candidate.id == optimisticReaction.id,
      );
      if (idx >= 0) {
        updated[idx] = reaction;
        _reactionProjectionController.replaceForMessage(messageId, updated);
      }
    }
  }

  void _removeAttachment(int index) {
    final pendingAttachments = _composerController.pendingAttachments;
    if (index < 0 || index >= pendingAttachments.length) return;
    final updated = List<PendingComposerMedia>.from(pendingAttachments);
    updated.removeAt(index);
    _updateComposerState(pendingAttachments: updated);
  }

  PrivateMediaEligibility _currentPrivateMediaEligibility({
    String? draftText,
    VoiceRecordingState? recordingState,
    List<PendingComposerMedia>? pendingAttachments,
  }) {
    final effectivePendingAttachments =
        pendingAttachments ?? _composerController.pendingAttachments;
    var kind = PrivateMediaAttachmentKind.unknown;
    if (effectivePendingAttachments.length == 1) {
      final mime = _mimeFromPath(
        effectivePendingAttachments.single.file.path,
      ).toLowerCase();
      if (mime == 'image/gif') {
        kind = PrivateMediaAttachmentKind.gif;
      } else if (mime.startsWith('image/')) {
        kind = PrivateMediaAttachmentKind.image;
      } else if (mime.startsWith('video/')) {
        kind = PrivateMediaAttachmentKind.video;
      } else if (mime.startsWith('audio/')) {
        kind = PrivateMediaAttachmentKind.audio;
      } else {
        kind = PrivateMediaAttachmentKind.file;
      }
    }
    final effectiveRecordingState =
        recordingState ?? _composerViewState.recordingState;
    return PrivateMediaEligibility(
      attachmentCount: effectivePendingAttachments.length,
      attachmentKind: kind,
      hasTextOrCaption: sanitizeMessageText(
        draftText ?? _draftText,
      ).trim().isNotEmpty,
      isEdit: _editingMessageId != null,
      isForward: effectiveRecordingState.isActive,
    );
  }

  void _setPrivateMediaPolicy(PrivateMediaPolicy policy) {
    final eligibility = _currentPrivateMediaEligibility();
    _privateMediaPolicyInvalidated =
        policy.mode == PrivateMediaMode.viewOnce &&
        eligibility.attachmentKind == PrivateMediaAttachmentKind.video;
    _privateMediaPolicy = normalizePrivateMediaComposerPolicy(
      selectedPolicy: policy,
      eligibility: eligibility,
      eligibleAttachmentIdentityChanged: false,
    );
    _updateComposerState();
  }

  void _updateComposerState({
    List<PendingComposerMedia>? pendingAttachments,
    ConversationComposerSnapshot? restoreSnapshot,
    Set<int>? invalidAttachmentIndices,
    Map<int, String>? invalidAttachmentReasons,
    bool? isUploading,
    bool? isProcessing,
    double? processingProgress,
    int? processingCurrent,
    int? processingTotal,
    VoiceRecordingState? recordingState,
    Duration? recordingDuration,
    List<double>? amplitudeValues,
    PrivateMediaPolicy? privateMediaPolicy,
  }) {
    assert(pendingAttachments == null || restoreSnapshot == null);
    final current = _composerController.value;
    final replacesPendingAttachments =
        pendingAttachments != null || restoreSnapshot != null;
    final effectivePendingAttachments =
        restoreSnapshot?.pendingAttachments ??
        pendingAttachments ??
        _composerController.pendingAttachments;
    final pendingAttachmentFiles = effectivePendingAttachments
        .map((media) => media.file)
        .toList(growable: false);
    // 149: whenever the pending-attachment list changes, re-derive the size/GIF
    // reject set from the LIVE list (never a stale snapshot) so the inline chip
    // + Send-disable always track the current attachments after pick/remove —
    // unless the caller supplied an explicit set.
    var nextInvalidIndices = invalidAttachmentIndices;
    var nextInvalidReasons = invalidAttachmentReasons;
    bool? nextHasTotalSizeOverflow;
    if (replacesPendingAttachments && invalidAttachmentIndices == null) {
      if (effectivePendingAttachments.isEmpty) {
        nextInvalidIndices = const <int>{};
        nextInvalidReasons = const <int, String>{};
        nextHasTotalSizeOverflow = false;
      } else {
        final rejections = _validatePendingMediaSizes(
          effectivePendingAttachments,
        );
        nextInvalidIndices = rejections.map((r) => r.index).toSet();
        nextInvalidReasons = {
          for (final rejection in rejections) rejection.index: rejection.reason,
        };
        // 149: individually-valid attachments whose summed bytes exceed the
        // total message budget get a strip-level note (no per-chip index).
        // Suppressed when any attachment is over its own cap (that per-chip
        // reject already disables Send) so the two signals never double up.
        nextHasTotalSizeOverflow =
            nextInvalidIndices.isEmpty &&
            pendingMediaTotalSizeOverflow(effectivePendingAttachments);
      }
    }
    final eligibility = _currentPrivateMediaEligibility(
      recordingState: recordingState,
      pendingAttachments: effectivePendingAttachments,
    );
    final attachmentIdentityChanged =
        replacesPendingAttachments &&
        current.pendingAttachments.isNotEmpty &&
        (current.pendingAttachments.length != pendingAttachmentFiles.length ||
            current.pendingAttachments.indexed.any(
              (entry) => entry.$2.path != pendingAttachmentFiles[entry.$1].path,
            ));
    var effectivePrivateMediaPolicy = privateMediaPolicy ?? _privateMediaPolicy;
    if (effectivePrivateMediaPolicy.mode == PrivateMediaMode.viewOnce &&
        eligibility.attachmentKind == PrivateMediaAttachmentKind.video) {
      _privateMediaPolicyInvalidated = true;
    }
    effectivePrivateMediaPolicy = normalizePrivateMediaComposerPolicy(
      selectedPolicy: effectivePrivateMediaPolicy,
      eligibility: eligibility,
      eligibleAttachmentIdentityChanged: attachmentIdentityChanged,
    );
    _privateMediaPolicy = effectivePrivateMediaPolicy;
    final next = current.copyWith(
      pendingAttachments: replacesPendingAttachments
          ? pendingAttachmentFiles
          : null,
      invalidAttachmentIndices: nextInvalidIndices,
      invalidAttachmentReasons: nextInvalidReasons,
      hasTotalSizeOverflow: nextHasTotalSizeOverflow,
      isUploading: isUploading,
      isProcessing: isProcessing,
      processingProgress: processingProgress,
      processingCurrent: processingCurrent,
      processingTotal: processingTotal,
      recordingState: recordingState,
      recordingDuration: recordingDuration,
      amplitudeValues: amplitudeValues,
      privateMediaEligibility: eligibility,
      privateMediaPolicy: effectivePrivateMediaPolicy,
    );
    if (restoreSnapshot != null) {
      _composerController.restoreSnapshot(restoreSnapshot, state: next);
    } else {
      _composerController.publish(
        state: next,
        pendingAttachments: pendingAttachments,
      );
    }
  }

  void _upsertMessageById(ConversationMessage message) {
    if (message.isHidden) {
      _messages = _messages
          .where((existing) => existing.id != message.id)
          .toList();
      _uploadActivityController.refreshOwnerProjection(publish: false);
      return;
    }
    final resolved = message.mustClearTransientMedia
        ? message.copyWith(media: const <MediaAttachment>[])
        : message;
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index == -1) {
      _messages = _sortMessagesForDisplay([..._messages, resolved]);
    } else {
      final updated = [..._messages];
      updated[index] = resolved;
      _messages = _sortMessagesForDisplay(updated);
    }
    _applyInMemoryCap();
    _uploadActivityController.refreshOwnerProjection(publish: false);
  }

  /// 159 (rebuild-storms-3): cap the in-memory window on the LIVE-APPEND path
  /// only. Trims newest-first (oldest evicted, live edge retained); on an
  /// eviction, flags more older history as re-fetchable so [_loadOlderMessages]
  /// can re-surface the dropped tail. The back-scroll prepend path
  /// ([_loadOlderMessages]) does NOT route through here and is intentionally
  /// exempt (a newest-first trim there would evict the just-loaded page).
  void _applyInMemoryCap() {
    final capped = trimToNewestInMemoryCap(_messages);
    if (capped.length < _messages.length) {
      _hasMoreOlderMessages = true;
    }
    _messages = capped;
  }

  ConversationMessage _mergeLoadedMessageWithCurrentState(
    ConversationMessage loaded,
  ) {
    if (loaded.mustClearTransientMedia) {
      return loaded.copyWith(media: const <MediaAttachment>[]);
    }
    final current = _messages
        .where((message) => message.id == loaded.id)
        .firstOrNull;
    if (current == null) {
      return loaded;
    }
    return loaded.copyWith(
      media: _mergeLoadedMediaWithCurrentState(
        loaded: loaded.media,
        current: current.media,
      ),
    );
  }

  List<MediaAttachment> _mergeLoadedMediaWithCurrentState({
    required List<MediaAttachment> loaded,
    required List<MediaAttachment> current,
  }) {
    if (loaded.isEmpty && current.isNotEmpty) {
      return current;
    }
    if (loaded.isEmpty || current.isEmpty) {
      return loaded;
    }

    final currentById = {
      for (final attachment in current) attachment.id: attachment,
    };
    return loaded
        .map((loadedAttachment) {
          final currentAttachment = currentById[loadedAttachment.id];
          if (currentAttachment == null) {
            return loadedAttachment;
          }
          if (_hasCompletedLocalPath(currentAttachment) &&
              !_hasCompletedLocalPath(loadedAttachment)) {
            return currentAttachment;
          }
          if (_isDisplayableResolvedAttachment(currentAttachment) &&
              !_isDisplayableResolvedAttachment(loadedAttachment)) {
            return currentAttachment;
          }
          return loadedAttachment;
        })
        .toList(growable: false);
  }

  bool _hasCompletedLocalPath(MediaAttachment attachment) {
    final localPath = attachment.localPath;
    return attachment.downloadStatus == 'done' &&
        localPath != null &&
        localPath.isNotEmpty;
  }

  bool _isDisplayableResolvedAttachment(MediaAttachment attachment) {
    final localPath = attachment.localPath;
    return _hasCompletedLocalPath(attachment) && File(localPath!).existsSync();
  }

  List<MediaAttachment> _replaceAttachmentById(
    List<MediaAttachment> attachments,
    MediaAttachment replacement,
  ) {
    var replaced = false;
    final next = attachments
        .map((attachment) {
          if (attachment.id != replacement.id) {
            return attachment;
          }
          replaced = true;
          return replacement;
        })
        .toList(growable: true);
    if (!replaced) {
      next.add(replacement);
    }
    return next;
  }

  List<ConversationMessage> _sortMessagesForDisplay(
    List<ConversationMessage> messages,
  ) {
    ConversationWired.debugSortInvocationCount++;
    final sorted = [...messages];
    sorted.sort((a, b) {
      // 159: compare by the model-cached parsed DateTime, falling back to the
      // ISO-string compare identically when either side fails to parse.
      final aTs = a.parsedTimestamp;
      final bTs = b.parsedTimestamp;
      final timestampCompare = (aTs != null && bTs != null)
          ? aTs.compareTo(bTs)
          : a.timestamp.compareTo(b.timestamp);
      if (timestampCompare != 0) return timestampCompare;
      final createdAtCompare = a.createdAt.compareTo(b.createdAt);
      if (createdAtCompare != 0) return createdAtCompare;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  void _updateLocalMessageStatus(String id, String status) {
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((m) => m.id == id);
      if (index == -1) return;
      final updated = [..._messages];
      updated[index] = updated[index].copyWith(status: status);
      _messages = updated;
      _uploadActivityController.refreshOwnerProjection(publish: false);
    });
  }

  void _removeLocalMessage(String id) {
    if (!mounted) return;
    setState(() {
      _messages = _messages.where((message) => message.id != id).toList();
      _uploadActivityController.refreshOwnerProjection(publish: false);
    });
  }

  Future<ConversationMessage?> _transitionSendingMessageToFailed(
    String id,
  ) async {
    try {
      await widget.messageRepo.conditionalTransitionStatus(
        id,
        fromStatus: 'sending',
        toStatus: 'failed',
      );
      return widget.messageRepo.getMessage(id);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_STATUS_UPDATE_ERROR',
        details: {'error': e.toString(), 'status': 'failed'},
      );
      try {
        return await widget.messageRepo.getMessage(id);
      } catch (_) {
        return null;
      }
    }
  }

  Future<ConversationMessage?> _settleRetriableOrdinaryMessage(
    ConversationMessage message,
  ) async {
    final repository = widget.messageRepo;
    final transportRepository =
        repository is OutgoingTransportMutationRepository
        ? repository as OutgoingTransportMutationRepository
        : null;
    final envelope = message.wireEnvelope;
    if (transportRepository == null || envelope == null || envelope.isEmpty) {
      return repository.getMessage(message.id);
    }
    try {
      final result = await transportRepository.settleOutgoingOrdinaryTransport(
        messageId: message.id,
        expectedContactPeerId: message.contactPeerId,
        expectedEnvelope: envelope,
        status: 'sent',
        transport: 'inbox',
        relayExpiresAt: null,
        mode: OutgoingOrdinarySettlementMode.live,
      );
      return result.message;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_STATUS_UPDATE_ERROR',
        details: {'error': e.toString(), 'status': 'sent'},
      );
      return repository.getMessage(message.id);
    }
  }

  /// 170-S1 / UX tweak: a floating failure/offline SnackBar sits RIGHT ON TOP of
  /// the bottom composer (the "Write something…" field), not floating high above
  /// it. The composer is plain body content and the host Scaffold has no
  /// bottomNavigationBar/FAB, so nothing else lifts a floating bar off it —
  /// without a margin it lands on the Send button. Its height is ~12 top pad +
  /// 48 button row + 12 base bottom pad (≈72-76 logical px), plus the device
  /// bottom inset the composer applies itself; so a margin of (that height + a
  /// small gap) drops the bar's lower edge to just above the composer.
  static const double _kComposerApproxHeight = 76.0;
  static const double _kComposerSnackBarGap = 6.0;

  /// Bottom margin that seats a floating failure SnackBar just above the
  /// composer. Uses `padding.bottom` (0 while the keyboard is open — the common
  /// send case — and the safe-area inset when closed) to match the composer's
  /// own bottom inset. Guarded for the background send-completion path where the
  /// screen may already be gone (no MediaQuery lookup off a defunct context).
  EdgeInsetsGeometry _composerClearingSnackBarMargin() {
    final bottomInset = mounted
        ? (MediaQuery.maybeOf(context)?.padding.bottom ?? 0.0)
        : 0.0;
    return EdgeInsets.only(
      left: 8,
      right: 8,
      bottom: _kComposerApproxHeight + _kComposerSnackBarGap + bottomInset,
    );
  }

  void _showFloatingSnackBar(String text, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        margin: _composerClearingSnackBarMargin(),
      ),
    );
  }

  Future<void> _persistOptimisticAttachments(
    String messageId,
    List<MediaAttachment>? attachments, {
    required String errorEvent,
  }) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    if (mediaAttachmentRepo == null ||
        attachments == null ||
        attachments.isEmpty) {
      return;
    }

    try {
      for (final attachment in attachments) {
        await mediaAttachmentRepo.saveAttachment(
          attachment.copyWith(
            messageId: messageId,
            downloadStatus: 'upload_pending',
          ),
          owner: MediaOwnerLane.direct,
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: errorEvent,
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _refreshMessageWithHydratedMedia(
    String messageId, {
    List<MediaAttachment>? fallbackMedia,
  }) async {
    final refreshedMessage = await widget.messageRepo.getMessage(messageId);
    if (refreshedMessage == null || !mounted) return;
    final hydratedMedia = await _resolveHydratedMediaForMessage(
      messageId,
      fallbackMedia: fallbackMedia,
    );
    if (!mounted) return;
    setState(() {
      _upsertMessageById(refreshedMessage.copyWith(media: hydratedMedia));
    });
  }

  Future<void> _refreshMessageWithMediaSnapshot(
    String messageId,
    List<MediaAttachment> media,
  ) async {
    final refreshedMessage = await widget.messageRepo.getMessage(messageId);
    if (!mounted) return;
    final currentMessage = _messages
        .where((message) => message.id == messageId)
        .firstOrNull;
    final baseMessage = refreshedMessage ?? currentMessage;
    if (baseMessage == null) return;
    setState(() {
      _upsertMessageById(baseMessage.copyWith(media: media));
    });
  }

  Future<List<MediaAttachment>> _resolveHydratedMediaForMessage(
    String messageId, {
    List<MediaAttachment>? fallbackMedia,
  }) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    if (mediaAttachmentRepo == null) {
      return fallbackMedia ?? const <MediaAttachment>[];
    }

    final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.direct,
    );
    if (attachments.isEmpty) {
      return fallbackMedia ?? const <MediaAttachment>[];
    }

    final mediaFileManager = widget.mediaFileManager;
    if (mediaFileManager == null) {
      return attachments;
    }

    final resolved = <MediaAttachment>[];
    for (final attachment in attachments) {
      resolved.add(await _resolveAttachmentForDisplay(attachment));
    }
    return resolved;
  }

  // ── 233: direct shared media library ─────────────────────────────────────

  /// The Shared Media entry exists only when the injected attachment
  /// repository actually implements the plan-228 library read/state
  /// capabilities — never a defaulted or inferred owner. (Tests may stand a
  /// route in via [ConversationWired.sharedMediaLibraryRouteBuilder].)
  bool get _sharedMediaLibraryAvailable =>
      widget.sharedMediaLibraryRouteBuilder != null ||
      (widget.mediaAttachmentRepo is MediaLibraryRepository &&
          widget.mediaAttachmentRepo is MediaLibraryStateRepository);

  bool get _directMediaBatchForwardAvailable =>
      widget.mediaAttachmentRepo != null &&
      widget.contactRepo != null &&
      widget.bridge != null &&
      widget.mediaFileManager != null &&
      widget.imageProcessor != null;

  Future<DirectMediaBatchForwardLibraryLaunchResult>
  _launchDirectMediaBatchForward(
    List<DirectReceivedMediaActionIdentity> identities,
  ) async {
    final mediaRepository = widget.mediaAttachmentRepo;
    final contacts = widget.contactRepo;
    final bridge = widget.bridge;
    final mediaFileManager = widget.mediaFileManager;
    final imageProcessor = widget.imageProcessor;
    if (mediaRepository == null ||
        contacts == null ||
        bridge == null ||
        mediaFileManager == null ||
        imageProcessor == null) {
      return const DirectMediaBatchForwardLibraryLaunchResult.sourceUnavailable();
    }

    final builder = BuildDirectMediaLibraryBatchForward(
      loadParentMessage: widget.messageRepo.getMessage,
      mediaAttachmentRepository: mediaRepository,
    );
    final buildResult = await builder.build(
      contactPeerId: _contact.peerId,
      identities: identities,
    );
    final draft = buildResult.draft;
    if (!buildResult.isReady || draft == null || !mounted) {
      return const DirectMediaBatchForwardLibraryLaunchResult.sourceUnavailable();
    }

    final ordinary = DefaultShareBatchDeliveryCoordinator(
      identityRepository: widget.identityRepo,
      contactRepository: contacts,
      messageRepository: widget.messageRepo,
      mediaAttachmentRepository: mediaRepository,
      groupRepository: widget.forwardGroupRepository,
      groupMessageRepository: widget.forwardGroupMessageRepository,
      groupInviteDeliveryAttemptRepository:
          widget.forwardGroupInviteDeliveryAttemptRepository,
      bridge: bridge,
      p2pService: widget.p2pService,
      mediaFileManager: mediaFileManager,
      imageProcessor: imageProcessor,
      qualityPreference: widget.qualityPreference,
      videoQualityPreference: widget.videoQualityPreference,
      directEventFanoutResolver: () => widget.directEventFanout,
      shareStoredOfflinePromise: AppLocalizations.of(
        context,
      )!.share_stored_offline_promise,
    );
    final delivery = DirectMediaBatchForwardDeliveryCoordinator(
      revalidateForDispatch: ({required contactPeerId, required draft}) =>
          builder.revalidateForDispatch(
            contactPeerId: contactPeerId,
            draft: draft,
          ),
      contactRepository: contacts,
      deliverStrict: ({required shareIntent, required contacts, onProgress}) =>
          ordinary.deliverDirectMediaBatchForwardStrict(
            shareIntent: shareIntent,
            contacts: contacts,
            onProgress: onProgress,
          ),
    );

    final injected = widget.directMediaBatchForwardPickerLauncher;
    final DirectMediaBatchForwardCompletion? completion;
    if (injected != null) {
      completion = await injected(context, draft, delivery);
    } else {
      completion = await Navigator.of(context)
          .push<DirectMediaBatchForwardCompletion>(
            buildDirectMediaBatchForwardPickerRoute(
              draft: draft,
              sourceContactPeerId: _contact.peerId,
              contactRepository: contacts,
              deliveryCoordinator: delivery,
            ),
          );
    }
    if (completion == null) {
      return const DirectMediaBatchForwardLibraryLaunchResult.cancelled();
    }
    return DirectMediaBatchForwardLibraryLaunchResult.completed(completion);
  }

  Future<void> _openSharedMediaLibrary() async {
    final routeBuilder = widget.sharedMediaLibraryRouteBuilder;
    if (routeBuilder != null) {
      final result = await Navigator.of(context)
          .push<DirectSharedMediaLibraryResult>(
            MaterialPageRoute(builder: routeBuilder),
          );
      if (!mounted) return;
      if (result is DirectSharedMediaGoToMessage) {
        await _goToLibraryMessage(result.messageId);
      }
      return;
    }
    final repo = widget.mediaAttachmentRepo;
    if (repo == null ||
        repo is! MediaLibraryRepository ||
        repo is! MediaLibraryStateRepository) {
      return;
    }
    // Batch Save/Share: the shared plan-231 current-row qualification with
    // ONE plan-227 list-capable native call per dispatch.
    final batchActions = DirectMediaLibraryBatchActionsCoordinator(
      loadParentMessage: widget.messageRepo.getMessage,
      mediaAttachmentRepo: repo,
      egressService: ReceivedMediaEgressService(),
    );
    final result = await Navigator.of(context)
        .push<DirectSharedMediaLibraryResult>(
          AppVisibilityInheritedConversationRoute<
            DirectSharedMediaLibraryResult
          >(
            identity: AppVisibilityConversationIdentity.tryParse(
              lane: AppVisibilityConversationLane.direct,
              value: _contact.peerId,
            )!,
            builder: (_) => DirectSharedMediaLibraryScreen(
              contactPeerId: _contact.peerId,
              contactUsername: _contact.username,
              libraryRepository: repo as MediaLibraryRepository,
              stateRepository: repo as MediaLibraryStateRepository,
              loadActionDecision: _loadDirectMediaActionDecision,
              pictureInPictureControllerFactory:
                  _createMediaPictureInPictureController,
              loadPictureInPictureAuthorization:
                  _loadDirectPictureInPictureAuthorization,
              mediaViewerResumeStore: _mediaViewerResumeStore,
              launchBatchForward: _directMediaBatchForwardAvailable
                  ? _launchDirectMediaBatchForward
                  : null,
              dispatchEgress: (identities, destination) =>
                  batchActions.performBatchEgress(
                    identities: identities,
                    destination: destination,
                  ),
              // Confirmed whole-message Delete for Me: dedup by unique
              // parent, materialize through getMessage, reuse the existing
              // local delete seam once per resolved parent.
              dispatchDelete: (identities) => deleteDirectMediaSelectionForMe(
                identities: identities,
                messageRepo: widget.messageRepo,
                deleteMessageForMe: _deleteMessageForMeLocally,
              ),
              onMessagesDeleted: (deletedMessageIds) {
                if (!mounted) return;
                for (final messageId in deletedMessageIds) {
                  _removeLocalMessage(messageId);
                }
              },
            ),
          ),
        );
    if (!mounted) return;
    if (result is DirectSharedMediaGoToMessage) {
      await _goToLibraryMessage(result.messageId);
    }
  }

  // ── 233: bounded Go to Message coordination ──────────────────────────────

  String? _highlightedMessageId;
  Timer? _highlightClearTimer;

  /// Loads older pages SERIALLY until the target message is present or
  /// history is exhausted, then reveals and transiently highlights exactly
  /// its stable `msg-<id>` key. Never replaces or resets the loaded window:
  /// pages append through the existing [_loadOlderMessages] path only.
  Future<void> _goToLibraryMessage(String messageId) async {
    bool loaded() => _messages.any((m) => m.id == messageId);

    while (mounted && !loaded()) {
      if (_isLoadingMore) {
        // A scroll-triggered load is in flight — wait for it instead of
        // issuing a concurrent page request.
        await Future<void>.delayed(const Duration(milliseconds: 40));
        continue;
      }
      if (!_hasMoreOlderMessages) break;
      final beforeCount = _messages.length;
      await _loadOlderMessages();
      if (!mounted) return;
      // Stop on a page that made no progress — a repository stuck below the
      // cursor must not spin forever.
      if (_messages.length == beforeCount) break;
    }
    if (!mounted) return;

    if (!loaded()) {
      // Truthful terminal state: the message is gone (deleted/older than
      // history) — no spinner, no nearest-row substitution, no navigation.
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.shared_media_go_to_message_missing,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    setState(() => _highlightedMessageId = messageId);
    final reveal = widget.revealConversationMessageFn ?? _revealMessageInList;
    await reveal(messageId);
    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  /// Default reveal: walk the element tree for the row's stable key and
  /// ensure it is visible; while the (already loaded) row is still outside
  /// the virtualized build window, step the scroll position toward the older
  /// end until it materializes. Bounded — never loads pages.
  Future<void> _revealMessageInList(String messageId) async {
    final targetKey = ValueKey('msg-$messageId');
    for (var attempt = 0; attempt < 80; attempt++) {
      if (!mounted) return;
      final targetContext = _findDescendantContextByKey(targetKey);
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 200),
        );
        return;
      }
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent) return;
      _scrollController.jumpTo(
        (position.pixels + position.viewportDimension * 0.9).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  BuildContext? _findDescendantContextByKey(Key key) {
    BuildContext? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element;
        return;
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    return found;
  }

  void _onOverflow() {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    // Position the popup menu near the top-right overflow button area
    final topPadding = MediaQuery.of(context).padding.top;
    final position = RelativeRect.fromLTRB(
      box.size.width - 200,
      topPadding + 50,
      16,
      0,
    );
    final l10n = AppLocalizations.of(context)!;

    // 248 (TC-17) — under Signal the popup uses light warm chrome + semantic
    // success/destructive colors; the dark branch keeps the transcribed
    // hardcoded literals.
    final readable = context.backgroundReadableColors;
    final isLight = readable.isLightSurface;
    final menuSurface = isLight
        ? readable.surfaceRaised
        : const Color.fromRGBO(18, 20, 28, 0.98);
    final menuBorder = isLight
        ? readable.surfaceBorder
        : const Color.fromRGBO(255, 255, 255, 0.14);
    final successColor = isLight
        ? const Color(0xFF2F7755)
        : const Color(0xFF10B981);
    final destructiveColor = isLight
        ? const Color(0xFFB4232F)
        : const Color(0xFFEF4444);

    showMenu<String>(
      context: context,
      position: position,
      color: menuSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: menuBorder),
      ),
      items: [
        if (!_contact.isBlocked && _hasOtherFriends)
          PopupMenuItem<String>(
            value: 'introduce',
            child: Row(
              children: [
                Icon(Icons.people_outline, size: 18, color: successColor),
                const SizedBox(width: 10),
                Text(
                  l10n.conversation_introduce_to_circle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: successColor,
                  ),
                ),
              ],
            ),
          ),
        if (_sharedMediaLibraryAvailable)
          PopupMenuItem<String>(
            key: const ValueKey('conversation-shared-media-action'),
            value: 'shared_media',
            child: Row(
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 18,
                  color: isLight ? readable.textPrimary : Colors.white,
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.conversation_shared_media,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isLight ? readable.textPrimary : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'block',
          child: Row(
            children: [
              Icon(
                _contact.isBlocked ? Icons.replay : Icons.block,
                size: 18,
                color: _contact.isBlocked ? successColor : destructiveColor,
              ),
              const SizedBox(width: 10),
              Text(
                _contact.isBlocked
                    ? l10n.conversation_unblock_contact(_contact.username)
                    : l10n.conversation_block_contact(_contact.username),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _contact.isBlocked ? successColor : destructiveColor,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: destructiveColor),
              const SizedBox(width: 10),
              Text(
                l10n.conversation_delete_chat_action,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: destructiveColor,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'introduce') {
        _onIntroduce();
      } else if (value == 'shared_media') {
        _openSharedMediaLibrary();
      } else if (value == 'block') {
        if (_contact.isBlocked) {
          _onUnblock();
        } else {
          _onBlock();
        }
      } else if (value == 'delete') {
        _onDelete();
      }
    });
  }

  Future<void> _onBlock() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    final confirmed = await showConfirmationDialog(
      context: context,
      title: AppLocalizations.of(
        context,
      )!.conversation_block(_contact.username),
      description:
          'They won\'t be able to send you messages. You can unblock them later.',
      confirmLabel: 'Block',
    );
    if (!confirmed || !mounted) return;

    try {
      await blockContact(contactRepo: contactRepo, peerId: _contact.peerId);
      if (!mounted) return;
      final updated = await contactRepo.getContact(_contact.peerId);
      if (updated != null && mounted) {
        setState(() => _contact = updated);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_BLOCK_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onUnblock() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    try {
      await unblockContact(contactRepo: contactRepo, peerId: _contact.peerId);
      if (!mounted) return;
      final updated = await contactRepo.getContact(_contact.peerId);
      if (updated != null && mounted) {
        setState(() => _contact = updated);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_UNBLOCK_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onDelete() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    final confirmed = await showConfirmationDialog(
      context: context,
      title: AppLocalizations.of(context)!.conversation_delete_chat,
      description:
          'This will permanently remove ${_contact.username} and all messages. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    try {
      final deleteContactFn = widget.deleteContactFn;
      if (deleteContactFn != null) {
        await deleteContactFn(_contact.peerId);
      } else {
        await deleteContactAndMessages(
          contactRepo: contactRepo,
          messageRepo: widget.messageRepo,
          peerId: _contact.peerId,
          mediaAttachmentRepo: widget.mediaAttachmentRepo,
          reactionRepo: widget.reactionRepo,
          mediaFileManager: widget.mediaFileManager,
          introductionRepo: widget.introductionRepository,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_DELETE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatConnectionDate() {
    try {
      final date = DateTime.parse(_contact.scannedAt);
      final locale = Localizations.localeOf(context).toString();
      return intl.DateFormat.yMMMd(locale).format(date);
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, Object?>> _runPrivateMediaOutboxE2E(
    PrivateMediaOutboxE2ERequest request,
    PrivateMediaOutboxE2EProgressWriter writeProgress,
    PrivateMediaOutboxE2EHostReleaseWaiter waitForHostRelease,
  ) async {
    if (_privateMediaOutboxE2ERunInFlight) {
      throw StateError('private-media outbox conversation is already running');
    }
    _privateMediaOutboxE2ERunInFlight = true;
    try {
      final endpoint = PrivateMediaOutboxE2EConversationEndpoint(
        contactPeerId: _contact.peerId,
        sendPrivateMedia: _sendPrivateMediaOutboxE2EFixture,
        isSenderQueued: _isPrivateMediaOutboxE2ESenderQueued,
        isSenderDelivered: _isPrivateMediaOutboxE2ESenderDelivered,
        isReceiverDelivered: _isPrivateMediaOutboxE2EReceiverDelivered,
        waitForSenderHostRelease: () => waitForHostRelease(request),
        waitForSenderOfflineObservation: () =>
            _waitForPrivateMediaOutboxE2EOfflineConnectivity(request),
        waitForOfflinePauseResume: () =>
            _waitForPrivateMediaOutboxE2EOfflinePauseResume(request),
      );
      return await endpoint.run(request, writeProgress);
    } finally {
      _privateMediaOutboxE2ELifecycleBaseline = null;
      _privateMediaOutboxE2ERunInFlight = false;
    }
  }

  Future<void> _sendPrivateMediaOutboxE2EFixture(
    PrivateMediaOutboxE2ERequest request,
  ) async {
    await waitForPrivateMediaOutboxE2ECondition(
      label: privateMediaOutboxConversationReadyCondition,
      timeout: request.timeout,
      check: () async =>
          mounted &&
          _identity != null &&
          widget.bridge != null &&
          widget.mediaAttachmentRepo != null &&
          widget.mediaFileManager != null,
    );
    if (!mounted ||
        _isSending ||
        _composerController.pendingAttachments.isNotEmpty ||
        _draftText.isNotEmpty) {
      throw StateError('private-media outbox composer is not clean');
    }
    final mediaFileManager = widget.mediaFileManager!;
    final source = await createPrivateMediaOutboxE2ESource(
      mediaFileManager: mediaFileManager,
      request: request,
    );
    _privateMediaOutboxE2ENextMessageId = request.messageId;
    _privateMediaOutboxE2ENextAttachmentId = request.attachmentId;
    _privateMediaOutboxE2ELifecycleBaseline = _appLifecycleGeneration;
    try {
      final pending = PendingComposerMedia(
        file: source,
        budgetBytes: await source.length(),
        width: 1,
        height: 1,
      );
      if (!mounted) {
        throw StateError('private-media outbox route was disposed');
      }
      setState(() {
        _privateMediaPolicy = _privateMediaOutboxPolicy(request);
        _draftText = '';
        _activeQuoteMessageId = null;
        _restoredFailedMessageId = null;
        _restoredFailedDraftText = null;
        _restoredFailedQuotedMessageId = null;
      });
      _updateComposerState(pendingAttachments: <PendingComposerMedia>[pending]);
      await _onSend('');
    } finally {
      _privateMediaOutboxE2ENextMessageId = null;
      _privateMediaOutboxE2ENextAttachmentId = null;
      try {
        if (await source.exists()) await source.delete();
      } catch (_) {}
    }
  }

  Future<bool> _isPrivateMediaOutboxE2ESenderQueued(
    PrivateMediaOutboxE2ERequest request,
  ) async {
    final mediaFileManager = widget.mediaFileManager;
    final attachment = await _loadPrivateMediaOutboxE2EAttachment(request);
    final parent = await widget.messageRepo.getMessage(request.messageId);
    if (mediaFileManager == null ||
        parent == null ||
        attachment == null ||
        parent.isIncoming ||
        parent.contactPeerId != request.contactPeerId ||
        parent.status != 'sending' ||
        parent.privateMediaPolicy != _privateMediaOutboxPolicy(request) ||
        attachment.downloadStatus != 'upload_pending' ||
        (attachment.uploadRetryCount ?? 0) != 0 ||
        attachment.mime != 'image/jpeg' ||
        attachment.localPath == null ||
        !attachment.localPath!.startsWith('pending_uploads/')) {
      return false;
    }
    final resolved = await mediaFileManager.resolveStoredPath(
      attachment.localPath!,
    );
    return File(resolved).existsSync() &&
        _composerController.pendingAttachments.isEmpty &&
        _draftText.isEmpty &&
        _privateMediaPolicy == const PrivateMediaPolicy.ordinary() &&
        _restoredFailedMessageId == null;
  }

  Future<bool> _isPrivateMediaOutboxE2ESenderDelivered(
    PrivateMediaOutboxE2ERequest request,
  ) async {
    final mediaFileManager = widget.mediaFileManager;
    final attachment = await _loadPrivateMediaOutboxE2EAttachment(request);
    final parent = await widget.messageRepo.getMessage(request.messageId);
    if (mediaFileManager == null ||
        parent == null ||
        attachment == null ||
        parent.isIncoming ||
        parent.contactPeerId != request.contactPeerId ||
        parent.status == 'sending' ||
        parent.status == 'failed' ||
        parent.privateMediaPolicy != _privateMediaOutboxPolicy(request) ||
        attachment.downloadStatus != 'done' ||
        attachment.localPath == null ||
        !attachment.localPath!.startsWith('media/')) {
      return false;
    }
    final resolved = await mediaFileManager.resolveStoredPath(
      attachment.localPath!,
    );
    return File(resolved).existsSync();
  }

  Future<bool> _isPrivateMediaOutboxE2EReceiverDelivered(
    PrivateMediaOutboxE2ERequest request,
  ) async {
    final attachment = await _loadPrivateMediaOutboxE2EAttachment(request);
    final parent = await widget.messageRepo.getMessage(request.messageId);
    return parent != null &&
        attachment != null &&
        parent.isIncoming &&
        !parent.isDeleted &&
        parent.status != 'failed' &&
        parent.contactPeerId == request.contactPeerId &&
        parent.privateMediaPolicy == _privateMediaOutboxPolicy(request) &&
        parent.privateMediaState == PrivateMediaLifecycleState.available &&
        attachment.messageId == request.messageId &&
        attachment.mime == 'image/jpeg' &&
        attachment.contentHash?.isNotEmpty == true &&
        attachment.encryptionKeyBase64?.isNotEmpty == true &&
        attachment.encryptionNonce?.isNotEmpty == true;
  }

  Future<MediaAttachment?> _loadPrivateMediaOutboxE2EAttachment(
    PrivateMediaOutboxE2ERequest request,
  ) async {
    final mediaRepository = widget.mediaAttachmentRepo;
    if (mediaRepository == null) return null;
    final attachments = await mediaRepository.getAttachmentsForMessage(
      request.messageId,
      owner: MediaOwnerLane.direct,
    );
    final exact = attachments
        .where((attachment) => attachment.id == request.attachmentId)
        .toList(growable: false);
    return exact.length == 1 ? exact.single : null;
  }

  Future<void> _waitForPrivateMediaOutboxE2EOfflinePauseResume(
    PrivateMediaOutboxE2ERequest request,
  ) async {
    final baseline = _privateMediaOutboxE2ELifecycleBaseline;
    if (baseline == null) {
      throw StateError('private-media outbox lifecycle baseline is missing');
    }
    await waitForPrivateMediaOutboxE2ECondition(
      label: privateMediaOutboxOfflineLifecycleCondition,
      timeout: request.timeout,
      check: () async =>
          mounted &&
          _appLifecycleState == AppLifecycleState.resumed &&
          _appLifecycleGeneration >= baseline + 2,
    );
  }

  Future<void> _waitForPrivateMediaOutboxE2EOfflineConnectivity(
    PrivateMediaOutboxE2ERequest request,
  ) async {
    await waitForPrivateMediaOutboxE2ECondition(
      label: privateMediaOutboxOfflineConnectivityCondition,
      timeout: request.timeout,
      check: () async {
        if (!mounted) return false;
        final results = await Connectivity().checkConnectivity();
        return results.isNotEmpty &&
            results.every((result) => result == ConnectivityResult.none);
      },
    );
  }

  PrivateMediaPolicy _privateMediaOutboxPolicy(
    PrivateMediaOutboxE2ERequest request,
  ) => request.phase == 1
      ? const PrivateMediaPolicy.protected()
      : const PrivateMediaPolicy.viewOnce();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final outboxEndpointToken = _privateMediaOutboxE2EEndpointToken;
    _privateMediaOutboxE2EEndpointToken = null;
    if (outboxEndpointToken != null) {
      widget.privateMediaOutboxE2EController?.unregisterEndpoint(
        outboxEndpointToken,
      );
    }
    widget.conversationTracker?.clearIfActive(widget.contact.peerId);
    widget.appShellController?.removeListener(_onAppShellChanged);
    _scrollController.removeListener(_onScroll);
    _incomingSubscription?.cancel();
    _repoChangeSubscription?.cancel();
    _contactUpdateSubscription?.cancel();
    _outgoingCallAvailabilityGeneration++;
    _outgoingCallAvailabilitySubscription?.cancel();
    _reactionSubscription?.cancel();
    _uploadActivityController.removeListener(_onControllerInvalidated);
    _reactionProjectionController.removeListener(_onControllerInvalidated);
    _voiceCaptureController.removeListener(_onVoiceCaptureStateChanged);
    _uploadActivityController.dispose();
    _reactionProjectionController.dispose();
    _voiceCaptureController.dispose();
    final privateViewerController = _lazyPrivateMediaViewerController;
    _lazyPrivateMediaViewerController = null;
    if (privateViewerController != null) {
      unawaited(privateViewerController.dispose());
    }
    // 117 Session 3: a never-acted-on auto-stop review recording is the user's
    // to keep only while the screen is open; clean up its temp on teardown.
    final reviewRecording = _pendingReviewRecording;
    _pendingReviewRecording = null;
    if (reviewRecording != null) {
      try {
        final file = File(reviewRecording.filePath);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _composerController.dispose();
    _scrollController.dispose();
    _highlightClearTimer?.cancel();
    super.dispose();
  }

  void _onAppShellChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_appLifecycleState != state) {
      _appLifecycleState = state;
      _appLifecycleGeneration++;
      if (mounted) setState(() {});
    }
    // 131: on resume, a message that arrived while backgrounded lands via the
    // async app-resume drain AFTER this screen's one-shot DB read and may miss
    // the no-replay live stream. Re-fetch (without yanking the scroll position).
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverAndMarkReadAfterResume());
      unawaited(_refreshOutgoingCallAvailability());
    }
  }

  @override
  void didUpdateWidget(covariant ConversationWired oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.outgoingCallCapability,
      widget.outgoingCallCapability,
    )) {
      _bindOutgoingCallAvailability();
    } else if (oldWidget.contact.peerId != widget.contact.peerId) {
      unawaited(_refreshOutgoingCallAvailability());
    }
  }

  Future<void> _recoverAndMarkReadAfterResume() async {
    try {
      await _drainAndReloadOnce('resume', scrollToLiveEdge: false);
    } finally {
      // Even when the row was already present in the initial page (so recovery
      // reports no newly-added message), resumed exact visibility is sufficient
      // read authority. The strict predicate is re-evaluated at this final seam.
      await _markAsRead();
    }
  }

  Future<void> _startOutgoingCall(OutgoingCallCapability capability) async {
    if (_outgoingCallStartInFlight || !capability.isOutgoingCallAvailable) {
      return;
    }
    setState(() => _outgoingCallStartInFlight = true);
    var shouldShowFailure = false;
    var result = OutgoingCallStartResult.failed;
    try {
      final contactAvailable = await capability.isOutgoingCallAvailableFor(
        _contact.peerId,
      );
      if (!mounted) return;
      if (!contactAvailable || !capability.isOutgoingCallAvailable) {
        if (_outgoingCallContactAvailable) {
          setState(() => _outgoingCallContactAvailable = false);
        }
        return;
      }
      shouldShowFailure = true;
      result = await capability.startOutgoingCall(_contact.peerId);
    } catch (_) {
      // Presentation receives no adapter, endpoint, or route failure detail.
      if (!shouldShowFailure && mounted && _outgoingCallContactAvailable) {
        setState(() => _outgoingCallContactAvailable = false);
      }
    } finally {
      if (mounted) {
        setState(() => _outgoingCallStartInFlight = false);
      }
    }
    if (!mounted ||
        !shouldShowFailure ||
        result == OutgoingCallStartResult.started) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text("Couldn't start voice call. Please try again."),
        ),
      );
  }

  void _bindOutgoingCallAvailability() {
    _outgoingCallAvailabilityGeneration++;
    _outgoingCallContactAvailable = false;
    final previous = _outgoingCallAvailabilitySubscription;
    _outgoingCallAvailabilitySubscription = null;
    if (previous != null) unawaited(previous.cancel());

    final capability = widget.outgoingCallCapability;
    if (capability != null) {
      _outgoingCallAvailabilitySubscription = capability
          .outgoingCallAvailabilityChanges
          .listen(
            (_) => unawaited(_refreshOutgoingCallAvailability()),
            onError: (_, _) => _hideOutgoingCallAvailability(),
            onDone: _hideOutgoingCallAvailability,
          );
    }
    unawaited(_refreshOutgoingCallAvailability());
  }

  void _hideOutgoingCallAvailability() {
    _outgoingCallAvailabilityGeneration++;
    if (mounted && _outgoingCallContactAvailable) {
      setState(() => _outgoingCallContactAvailable = false);
    }
  }

  Future<void> _refreshOutgoingCallAvailability() async {
    final generation = ++_outgoingCallAvailabilityGeneration;
    final capability = widget.outgoingCallCapability;
    final contactPeerId = _contact.peerId;
    var available = false;
    if (capability?.isOutgoingCallAvailable ?? false) {
      try {
        available = await capability!.isOutgoingCallAvailableFor(contactPeerId);
      } catch (_) {}
    }
    if (!mounted ||
        generation != _outgoingCallAvailabilityGeneration ||
        contactPeerId != _contact.peerId ||
        !identical(capability, widget.outgoingCallCapability)) {
      return;
    }
    if (_outgoingCallContactAvailable != available) {
      setState(() => _outgoingCallContactAvailable = available);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (activeQuoteText, isActiveQuoteUnavailable) =
        _resolveActiveQuotePreview();
    final outgoingCallCapability = widget.outgoingCallCapability;
    final outgoingCallAvailable =
        (outgoingCallCapability?.isOutgoingCallAvailable ?? false) &&
        _outgoingCallContactAvailable;

    final child = PopScope(
      canPop: !_uploadActivityController.isTracking,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !_uploadActivityController.isTracking) return;
        unawaited(_handleBackNavigation());
      },
      child: Scaffold(
        body: ConversationScreen(
          contactPeerId: _contact.peerId,
          contactUsername: _contact.username,
          connectionDate: _formatConnectionDate(),
          ownPeerId: _identity?.peerId,
          messages: _messages,
          onSend: _onSend,
          onBack: _handleBackNavigation,
          scrollController: _scrollController,
          isBlocked: _contact.isBlocked,
          onUnblock: _onUnblock,
          onOverflow: widget.contactRepo != null ? _onOverflow : null,
          onAvatarTap: () => ContactProfileScreen.open(
            context,
            contact: _contact,
            directDeviceTrust:
                widget.directDeviceTrust ??
                const UnavailableDirectContactDeviceTrust(),
          ),
          onCall: outgoingCallAvailable && outgoingCallCapability != null
              ? () => unawaited(_startOutgoingCall(outgoingCallCapability))
              : null,
          showCallAction: outgoingCallCapability != null,
          callActionEnabled:
              outgoingCallAvailable && !_outgoingCallStartInFlight,
          isLoadingMore: _isLoadingMore,
          hasMoreOlderMessages: _hasMoreOlderMessages,
          initialLoadDone: _initialLoadDone,
          isSyncingNewMessages: _isSyncingNewMessages,
          isSending: _isSending,
          recordingState: _composerController.value.recordingState,
          onAttach: _onAttach,
          onRemoveAttachment: _removeAttachment,
          onRecordStart: widget.audioRecorderService != null
              ? _onRecordStart
              : null,
          onRecordStop: widget.audioRecorderService != null
              ? _onRecordStop
              : null,
          onRecordCancel: widget.audioRecorderService != null
              ? _onRecordCancel
              : null,
          onReviewSend: widget.audioRecorderService != null
              ? _onReviewSend
              : null,
          onReviewDiscard: widget.audioRecorderService != null
              ? _onReviewDiscard
              : null,
          composerStateListenable: _composerController,
          initialText: _draftText,
          onDraftChanged: _onDraftChanged,
          onPrivateMediaPolicyChanged: _setPrivateMediaPolicy,
          reactions: _reactionProjectionController.reactions,
          onReactionSelected: widget.reactionRepo != null
              ? _onReactionSelected
              : null,
          onRetryFailedMessage: _onRetryFailedMessage,
          onRetryFailedMedia: _onRetryFailedMedia,
          onDeleteFailedMedia: _onDeleteFailedMedia,
          onRetryUnavailableMedia: _onRetryUnavailableMedia,
          showIntroBanner: _showIntroBanner,
          bannerContactUsername: _contact.username,
          undeliveredCount: _undeliveredAttentionCount,
          onRetryUndelivered: () => unawaited(_onRetryUndelivered()),
          uploadProgress: _uploadActivityController.aggregateProgress,
          messageUploadProgress: _uploadActivityController.messageProgress,
          p2pService: widget.p2pService,
          onCancelUpload:
              _uploadActivityController.activeOperation == null ||
                  _uploadActivityController.cancelRequested
              ? null
              : _requestCancelActiveAttachmentUpload,
          onMakeIntroductions: _onMakeIntroductions,
          onMaybeLater: _onMaybeLater,
          onQuoteReply: _onQuoteReply,
          onDeleteMessage: _onDeleteMessage,
          // 231: direct received-media actions — every Save/Share/Info runs
          // through the local controller; Delete stays on the existing
          // whole-message seam with media-labeled confirmation copy.
          onMediaEgress: _mediaActionController != null
              ? _performDirectMediaEgress
              : null,
          onLoadMediaInfo: _mediaActionController != null
              ? _loadDirectMediaInfo
              : null,
          onLoadMediaActionDecision: _mediaActionController != null
              ? _loadDirectMediaActionDecision
              : null,
          pictureInPictureControllerFactory: _mediaViewerResumeStore == null
              ? null
              : _createMediaPictureInPictureController,
          loadPictureInPictureAuthorization: _mediaViewerResumeStore == null
              ? null
              : _loadDirectPictureInPictureAuthorization,
          mediaViewerResumeStore: _mediaViewerResumeStore,
          onOpenPrivateMediaResult: _privateMediaViewerController != null
              ? _openDirectPrivateMedia
              : null,
          onLoadPrivateParentDecision: _loadPrivateParentDecision,
          // 301: Android-only route-scoped FLAG_SECURE while a protected
          // thumbnail is rendered; the EXACT process-shared coordinator the
          // viewer controller holds (owner-refcounted, so both grants
          // coexist). Rides the same Session-05 capability qualification —
          // a route without private-media deps stays coordinator-less and
          // the screen keeps its fail-closed no-pixel presentations.
          protectionCoordinator:
              _privateMediaViewerController?.protectionCoordinator,
          appLifecycleState: _appLifecycleState,
          appLifecycleGeneration: _appLifecycleGeneration,
          appLifecycleSnapshotProvider: () =>
              (state: _appLifecycleState, generation: _appLifecycleGeneration),
          onForwardMedia:
              widget.mediaAttachmentRepo != null &&
                  (widget.receivedMediaForwardLauncher != null ||
                      (widget.contactRepo != null &&
                          widget.bridge != null &&
                          widget.mediaFileManager != null &&
                          widget.imageProcessor != null))
              ? _forwardDirectReceivedMedia
              : null,
          onDeleteMediaMessage: _mediaActionController != null
              ? (messageId) => unawaited(_onDeleteMediaMessage(messageId))
              : null,
          activeQuoteText: activeQuoteText,
          isActiveQuoteUnavailable: isActiveQuoteUnavailable,
          onClearQuote: _onClearQuote,
          onEditMessage: _onEditMessage,
          isEditingMessage: _editingMessageId != null,
          onCancelEdit: _editingMessageId != null ? _onCancelEdit : null,
          allowEditAction: _canEnterEditMode,
          backgroundPreference:
              widget.appShellController?.backgroundPreference ??
              BackgroundPreference.defaultBackground,
          highlightedMessageId: _highlightedMessageId,
        ),
      ),
    );
    final registry = DirectPrivateMediaRouteObserverScope.maybeRegistryOf(
      context,
    );
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.direct,
      value: _contact.peerId,
    );
    if (registry == null || identity == null) return child;
    return AppVisibilityRouteBinding(
      registry: registry,
      identity: identity,
      observer: DirectPrivateMediaRouteObserverScope.maybeOf(context),
      child: child,
    );
  }
}

enum _DeleteMessageAction { forMe, forEveryone, cancel }

class _DeleteMessageSheet extends StatelessWidget {
  final bool canDeleteForEveryone;

  /// 231: when the deletion was initiated from a media surface the prompt
  /// states that the message AND all of its attachments leave this device.
  final bool mediaMessage;

  const _DeleteMessageSheet({
    required this.canDeleteForEveryone,
    this.mediaMessage = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final maxHeight = MediaQuery.of(context).size.height * 0.72;
    // 248 (TC-18) — under Signal the sheet uses warm light chrome + readable
    // semantic destructive actions; the dark branch keeps transcribed literals.
    final readable = context.backgroundReadableColors;
    final isLight = readable.isLightSurface;
    final sheetSurface = isLight
        ? readable.surfaceRaised
        : const Color.fromRGBO(18, 20, 28, 0.96);
    final sheetBorder = isLight
        ? readable.surfaceBorder
        : const Color.fromRGBO(255, 255, 255, 0.10);
    final handleColor = isLight
        ? readable.divider
        : const Color.fromRGBO(255, 255, 255, 0.18);
    final promptColor = isLight
        ? readable.textPrimary
        : const Color.fromRGBO(255, 255, 255, 0.94);
    final forMeColor = isLight
        ? const Color(0xFFB4232F)
        : const Color(0xFFFF8A80);
    final forEveryoneColor = isLight
        ? const Color(0xFF9A3412)
        : const Color(0xFFFFB38A);
    final cancelColor = isLight
        ? readable.textSecondary
        : const Color.fromRGBO(255, 255, 255, 0.72);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              key: ConversationWired.deleteSheetKey,
              decoration: BoxDecoration(
                color: sheetSurface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: sheetBorder),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: handleColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        mediaMessage
                            ? l10n.conversation_delete_media_message_prompt
                            : l10n.conversation_delete_message_prompt,
                        key: ConversationWired.deletePromptKey,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: promptColor,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DeleteSheetAction(
                        key: ConversationWired.deleteForMeKey,
                        label: l10n.conversation_delete_for_me,
                        icon: Icons.delete_outline_rounded,
                        color: forMeColor,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(_DeleteMessageAction.forMe),
                      ),
                      if (canDeleteForEveryone) ...[
                        const SizedBox(height: 10),
                        _DeleteSheetAction(
                          key: ConversationWired.deleteForEveryoneKey,
                          label: l10n.conversation_delete_for_everyone,
                          icon: Icons.person_remove_alt_1_rounded,
                          color: forEveryoneColor,
                          onTap: () => Navigator.of(
                            context,
                          ).pop(_DeleteMessageAction.forEveryone),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _DeleteSheetAction(
                        key: ConversationWired.deleteCancelKey,
                        label: l10n.conversation_delete_cancel,
                        icon: Icons.close_rounded,
                        color: cancelColor,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(_DeleteMessageAction.cancel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteSheetAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DeleteSheetAction({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 248 (TC-18) — nested chip surface follows the resolved theme: a warm
    // subtle fill + decorative surfaceBorder on light, transcribed literals dark.
    final readable = context.backgroundReadableColors;
    final isLight = readable.isLightSurface;
    final chipFill = isLight
        ? readable.surfaceSubtle
        : const Color.fromRGBO(255, 255, 255, 0.05);
    final chipBorder = isLight
        ? readable.surfaceBorder
        : const Color.fromRGBO(255, 255, 255, 0.08);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: chipFill,
            border: Border.all(color: chipBorder),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectComposerSnapshot {
  final ConversationComposerSnapshot common;
  final PrivateMediaPolicy privateMediaPolicy;

  const _DirectComposerSnapshot({
    required this.common,
    required this.privateMediaPolicy,
  });
}
