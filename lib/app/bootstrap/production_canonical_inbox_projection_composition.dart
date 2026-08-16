import 'dart:async';

import 'package:flutter_app/app/bootstrap/production_canonical_direct_replay_composition.dart';
import 'package:flutter_app/app/bootstrap/production_canonical_direct_projection_composition.dart';
import 'package:flutter_app/app/bootstrap/production_canonical_group_replay_composition.dart';
import 'package:flutter_app/app/bootstrap/production_headless_canonical_recovery.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reaction_terminal_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_read_acknowledgement_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_forward_authorization_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_history_gap_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_canonical_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_key_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_membership_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_sync_receipts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/linked_group_bootstrap_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_sibling_devices_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introduction_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_introduction_responses_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository_impl.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/canonical_recovery_runtime.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/direct_notification_projection_owner.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_display_outbox_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_reaction_terminal_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_read_acknowledgement_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_reconciliation_outbox_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/manage_pending_sibling_device.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/data/repositories/group_history_gap_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_notification_display_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_notification_reconciliation_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_key_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_membership_message_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_reaction_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// The exact partial-owner cleanup producer used by construction failures.
/// Tests inject closures into this same type; the production catch below does
/// not recreate or merely describe its proof logic.
final class ProductionCanonicalRecoveryPartialConstructionCleanup {
  const ProductionCanonicalRecoveryPartialConstructionCleanup({
    this.sealAndAwaitAdmission,
    this.stopDartOwners = const <Future<void> Function()>[],
    this.disposeDartOwners = const <void Function()>[],
    this.stopRuntime,
    this.disposeRuntimeOwners = const <void Function()>[],
  });

  final Future<void> Function()? sealAndAwaitAdmission;
  final List<Future<void> Function()> stopDartOwners;
  final List<void Function()> disposeDartOwners;
  final Future<bool> Function()? stopRuntime;
  final List<void Function()> disposeRuntimeOwners;

  Future<ProductionCanonicalRecoveryConstructionCleanupProof> run() async {
    var admissionSealedAndDrained = sealAndAwaitAdmission == null;
    try {
      await sealAndAwaitAdmission?.call();
      admissionSealedAndDrained = true;
    } catch (_) {}

    var dartOwnersQuiesced = true;
    for (final stop in stopDartOwners) {
      try {
        await stop();
      } catch (_) {
        dartOwnersQuiesced = false;
      }
    }
    for (final dispose in disposeDartOwners) {
      try {
        dispose();
      } catch (_) {
        dartOwnersQuiesced = false;
      }
    }

    var runtimeStopped = stopRuntime == null;
    try {
      runtimeStopped = await stopRuntime?.call() ?? true;
    } catch (_) {
      runtimeStopped = false;
    }
    var runtimeQuiesced = false;
    if (runtimeStopped) {
      runtimeQuiesced = true;
      for (final dispose in disposeRuntimeOwners) {
        try {
          dispose();
        } catch (_) {
          runtimeQuiesced = false;
        }
      }
    }
    return ProductionCanonicalRecoveryConstructionCleanupProof(
      admissionSealedAndDrained: admissionSealedAndDrained,
      dartOwnersQuiesced: dartOwnersQuiesced,
      runtimeQuiesced: runtimeQuiesced,
    );
  }
}

Future<Never> throwProductionCanonicalRecoveryConstructionFailure({
  required Object cause,
  required StackTrace causeStackTrace,
  required ProductionCanonicalRecoveryPartialConstructionCleanup cleanup,
}) async {
  final proof = await cleanup.run();
  Error.throwWithStackTrace(
    ProductionCanonicalRecoveryCompositionConstructionFailure(
      cause: cause,
      causeStackTrace: causeStackTrace,
      cleanupProof: proof,
    ),
    causeStackTrace,
  );
}

/// The one production, UI-neutral canonical inbox/projection graph.
///
/// This deliberately constructs no router, Firebase listener, presence owner,
/// discovery service, timer, or application root. It reuses the production SQL
/// repositories and typed replay adapters, and opts the incumbent P2P service
/// into its bounded recovery-only lifecycle.
Future<ProductionHeadlessRecoverySessionDelegates>
buildProductionCanonicalInboxProjectionComposition({
  required Database database,
  required SecureKeyStore secureKeyStore,
  required IdentityModel identity,
  required LinkedInstallationAuthoritySnapshot linkedAuthority,
  required ProductionHeadlessQualifiedIdentity qualifiedIdentity,
  required CanonicalRecoveryReason reason,
}) async {
  final bridge = GoBridgeClient();
  FlutterNotificationService? notificationServiceForCleanup;
  DirectNotificationProjectionOwner? directProjectionOwnerForCleanup;
  GroupMessageListener? groupMessageListenerForCleanup;
  GroupKeyUpdateListener? groupKeyUpdateListenerForCleanup;
  ChatMessageListener? chatMessageListenerForCleanup;
  IntroductionListener? introductionListenerForCleanup;
  ContactRequestListener? contactRequestListenerForCleanup;
  P2PServiceImpl? p2pServiceForCleanup;
  AppVisibilityAuthority? appVisibilityForCleanup;
  try {
    final mediaFileManager = MediaFileManager();
    final notificationRegistry =
        await DurableConversationNotificationIdRegistry.openDefault();
    final notificationLedger = LocalNotificationLedgerStore(
      directory: notificationRegistry.directory,
    );
    final notificationService = FlutterNotificationService(
      requestApplePermissions: false,
      notificationIdRegistryResolver: () async => notificationRegistry,
      notificationContentRegistryResolver: () async => notificationRegistry,
    );
    notificationServiceForCleanup = notificationService;
    final appVisibility = AppVisibilityAuthority(
      platformBridge: MethodChannelAppVisibilityPlatformBridge(),
    );
    appVisibilityForCleanup = appVisibility;
    final notificationToneTracker = NotificationToneTracker();
    final durableNotificationToneLease =
        await DurableNotificationToneLease.openDefault();
    final accountMigrationNetworkGate = AccountMigrationRuntimeNetworkGate(
      authorityRepository: SecureKeyStoreAccountMigrationAuthorityRepository(
        secureKeyStore: secureKeyStore,
      ),
    ).allowsAccountNetworkSideEffects;

    final contactRepository = _buildContactRepository(database);
    final contactRequestRepository = _buildContactRequestRepository(database);
    late final Future<int> Function(String peerId)
    projectDirectConversationRead;
    final messageRepository = _buildMessageRepository(
      database,
      projectConversationRead: (peerId) =>
          projectDirectConversationRead(peerId),
    );
    final mediaAttachmentRepository = _buildMediaAttachmentRepository(
      database,
      secureKeyStore,
    );
    final reactionRepository = _buildReactionRepository(database);
    final introductionRepository = _buildIntroductionRepository(database);
    final stagingRepository = _buildInboxStagingRepository(database);
    final groupRepository = _buildGroupRepository(database, secureKeyStore);
    final groupMessageRepository = _buildGroupMessageRepository(database);
    final groupPendingKeyRepairRepository =
        _buildGroupPendingKeyRepairRepository(database);
    final groupPendingMembershipRepository =
        _buildGroupPendingMembershipRepository(database);
    final groupPendingReactionRepository = _buildGroupPendingReactionRepository(
      database,
    );
    final groupHistoryGapRepairRepository =
        _buildGroupHistoryGapRepairRepository(database);

    final directDisplayOutbox = _buildDirectDisplayOutbox(database);
    final directReconciliationOutbox = _buildDirectReconciliationOutbox(
      database,
    );
    final directReactionTerminal = _buildDirectReactionTerminal(database);
    final directReadAcknowledgement = _buildDirectReadAcknowledgement(database);
    final groupDisplayOutbox = _buildGroupDisplayOutbox(database);
    final groupReconciliationOutbox = _buildGroupReconciliationOutbox(database);

    final directProjection =
        buildProductionCanonicalDirectProjectionComposition(
          ProductionCanonicalDirectProjectionDependencies(
            database: database,
            notificationService: notificationService,
            appVisibility: appVisibility,
            contactRepository: contactRepository,
            messageRepository: messageRepository,
            reactionRepository: reactionRepository,
            mediaAttachmentRepository: mediaAttachmentRepository,
            displayOutbox: directDisplayOutbox,
            reconciliationOutbox: directReconciliationOutbox,
            reactionTerminal: directReactionTerminal,
            readAcknowledgement: directReadAcknowledgement,
            durableRegistry: notificationRegistry,
            readCurrentOpaqueBinding: () async => qualifiedIdentity.binding,
            resolvePhysicalPeerId: () async => qualifiedIdentity.physicalPeerId,
            presentationOwner:
                LocalNotificationPresentationOwner.inboxReconciler,
            completedOutcomeProducerEnabled: false,
            notificationToneTracker: notificationToneTracker,
            durableNotificationCoordinatorResolver: () async =>
                durableNotificationToneLease,
          ),
        );
    final directProjectionOwner = directProjection.owner;
    projectDirectConversationRead =
        directProjection.readProjector.markConversationRead;
    directProjectionOwnerForCleanup = directProjectionOwner;

    late final P2PServiceImpl p2pService;
    late final ChatMessageListener chatMessageListener;
    late final IntroductionListener introductionListener;
    late final ContactRequestListener contactRequestListener;
    late final GroupKeyRepairRequestSender groupKeyRepairRequestSender;

    Future<void> sendReceipt({
      required String contactPeerId,
      required List<String> messageIds,
      Map<String, String>? mutationEventIds,
    }) async {
      await sendDeliveryReceipt(
        p2pService: p2pService,
        targetPeerId: contactPeerId,
        messageIds: messageIds,
        mutationEventIds: mutationEventIds,
      );
    }

    final directReplay = ProductionCanonicalDirectReplayComposition(
      loadIdentity: () async => identity,
      chatMessageListener: () => chatMessageListener,
      introductionListener: () => introductionListener,
      contactRequestListener: () => contactRequestListener,
      introductionRepository: introductionRepository,
      contactRepository: contactRepository,
      messageRepository: messageRepository,
      reactionRepository: reactionRepository,
      mediaAttachmentRepository: mediaAttachmentRepository,
      transportAuthority: DatabaseDirectTransportAuthority(database: database),
      bridge: bridge,
      secureKeyStore: secureKeyStore,
      mediaFileManager: mediaFileManager,
      sendDeliveryReceipt: sendReceipt,
      notificationOwner: () => directProjectionOwner,
      reactionNotificationDependencies: () =>
          ProductionDirectReactionNotificationDependencies(
            service: notificationService,
            appVisibility: appVisibility,
            toneTracker: notificationToneTracker,
            durableCoordinator: durableNotificationToneLease,
          ),
      forceSilentNotification: false,
      publishPersistedReactionChange: () => null,
    );

    final groupMessageListener = GroupMessageListener(
      groupRepo: groupRepository,
      msgRepo: groupMessageRepository,
      bridge: bridge,
      holdPendingSiblingDevice:
          ({
            required groupId,
            required memberPeerId,
            required announcedDeviceId,
            required announcedTransportPeerId,
            required announcedDeviceSigningPublicKey,
            required verifiedAccountSigningPublicKey,
            announcedMlKemPublicKey,
            announcedKeyPackageId,
          }) => holdPendingSiblingDevice(
            pendingRepo: groupRepository,
            groupRepo: groupRepository,
            groupId: groupId,
            memberPeerId: memberPeerId,
            announcedDeviceId: announcedDeviceId,
            announcedTransportPeerId: announcedTransportPeerId,
            announcedDeviceSigningPublicKey: announcedDeviceSigningPublicKey,
            verifiedAccountSigningPublicKey: verifiedAccountSigningPublicKey,
            announcedMlKemPublicKey: announcedMlKemPublicKey,
            announcedKeyPackageId: announcedKeyPackageId,
          ),
      getSelfPeerId: () async => identity.peerId,
      accountMigrationNetworkGate: accountMigrationNetworkGate,
      mediaAttachmentRepo: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
      notificationService: notificationService,
      appVisibility: appVisibility,
      notificationToneTracker: notificationToneTracker,
      durableNotificationCoordinatorResolver: () async =>
          durableNotificationToneLease,
      reactionRepo: reactionRepository,
      pendingKeyRepairRepo: groupPendingKeyRepairRepository,
      pendingMembershipMessageRepo: groupPendingMembershipRepository,
      pendingReactionRepo: groupPendingReactionRepository,
      requestGroupKeyRepair: (request) =>
          groupKeyRepairRequestSender.call(request),
      appendGroupEventLogEntry:
          ({
            required groupId,
            required eventType,
            required sourcePeerId,
            required sourceEventId,
            required sourceTimestamp,
            required payload,
            createdAt,
          }) => dbAppendGroupEventLogEntry(
            database,
            groupId: groupId,
            eventType: eventType,
            sourcePeerId: sourcePeerId,
            sourceEventId: sourceEventId,
            sourceTimestamp: sourceTimestamp,
            payload: payload,
            createdAt: createdAt,
          ),
      notificationDisplayOutbox: groupDisplayOutbox,
      notificationReconciliationOutbox: groupReconciliationOutbox,
      loadLatestUnreadNotificationMessage: (groupId) async {
        final row = await dbLoadLatestUnreadGroupNotificationMessage(
          database,
          groupId,
        );
        return row == null ? null : GroupMessage.fromMap(row);
      },
      isActiveGroupNotificationReaction:
          ({required groupId, required selfPeerId, required eventIdentity}) =>
              dbIsActiveGroupNotificationReaction(
                database,
                groupId: groupId,
                selfPeerId: selfPeerId,
                eventIdentity: eventIdentity,
              ),
      loadLatestActiveNotificationReaction:
          ({required groupId, required selfPeerId}) async {
            final row = await dbLoadLatestActiveGroupNotificationReaction(
              database,
              groupId: groupId,
              selfPeerId: selfPeerId,
            );
            if (row == null) return null;
            final messageId = (row['message_id'] as String?)?.trim();
            final actorPeerId = (row['sender_peer_id'] as String?)?.trim();
            final eventIdentity =
                (row['notification_display_terminal_event_id'] as String?)
                    ?.trim();
            final timestamp = DateTime.tryParse(
              (row['timestamp'] as String?)?.trim() ?? '',
            );
            if (messageId == null ||
                messageId.isEmpty ||
                actorPeerId == null ||
                actorPeerId.isEmpty ||
                eventIdentity == null ||
                eventIdentity.isEmpty ||
                timestamp == null) {
              throw StateError(
                'canonical group reaction descriptor is malformed',
              );
            }
            return GroupNotificationCanonicalReaction(
              messageId: messageId,
              actorPeerId: actorPeerId,
              eventIdentity: eventIdentity,
              timestamp: timestamp.toUtc(),
            );
          },
      isGroupNotificationEventAcknowledged:
          ({required groupId, required contentKind, required eventIdentity}) =>
              dbIsGroupNotificationEventAcknowledged(
                database,
                groupId: groupId,
                contentKind: contentKind,
                eventIdentity: eventIdentity,
              ),
      resolveCompletedOutcomePhysicalPeerId: () async =>
          qualifiedIdentity.physicalPeerId,
      resolveCurrentOpaqueBinding: () async => qualifiedIdentity.binding,
      durableLocalNotificationEffectRegistry: notificationRegistry,
      notificationPresentationOwner:
          LocalNotificationPresentationOwner.inboxReconciler,
      completedOutcomeProducerEnabled: false,
    );
    groupMessageListenerForCleanup = groupMessageListener;

    final groupPendingKeyRepairRunner = GroupPendingKeyRepairRunner(
      bridge: bridge,
      groupRepo: groupRepository,
      msgRepo: groupMessageRepository,
      pendingKeyRepairRepo: groupPendingKeyRepairRepository,
      mediaAttachmentRepo: mediaAttachmentRepository,
      reactionRepo: reactionRepository,
      replayGroupEnvelope: (data) => groupMessageListener.handleReplayEnvelope(
        data,
        allowMembershipBuffer: true,
      ),
    );
    final groupKeyUpdateListener = GroupKeyUpdateListener(
      groupKeyUpdateStream: const Stream<ChatMessage>.empty(),
      groupRepo: groupRepository,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => identity.mlKemSecretKey,
      getOwnPeerId: () async => identity.peerId,
      getOwnDeviceId: () async => linkedAuthority.credential?.deviceId,
      retryPendingGroupKeyRepairs:
          groupPendingKeyRepairRunner.retryPendingRepairsForRequest,
      requestGroupKeyRepair: (request) =>
          groupKeyRepairRequestSender.call(request),
      appendGroupEventLogEntry:
          ({
            required groupId,
            required eventType,
            required sourcePeerId,
            required sourceEventId,
            required sourceTimestamp,
            required payload,
            createdAt,
          }) => dbAppendGroupEventLogEntry(
            database,
            groupId: groupId,
            eventType: eventType,
            sourcePeerId: sourcePeerId,
            sourceEventId: sourceEventId,
            sourceTimestamp: sourceTimestamp,
            payload: payload,
            createdAt: createdAt,
          ),
    );
    groupKeyUpdateListenerForCleanup = groupKeyUpdateListener;
    final protectedGroupAuthoritySupport =
        ProductionCanonicalProtectedGroupAuthoritySupport(
          database: database,
          bridge: bridge,
          groupRepository: groupRepository,
        );
    final protectedGroupReplay =
        ProductionCanonicalProtectedGroupReplayComposition(
          database: database,
          bridge: bridge,
          groupRepository: groupRepository,
          groupMessageListener: groupMessageListener,
          groupKeyUpdateListener: groupKeyUpdateListener,
          authoritySupport: protectedGroupAuthoritySupport,
          loadIdentity: () async => identity,
          loadLinkedAuthority: (_) async => linkedAuthority,
          applySystemAuthorityReplay: (control, replayData, authority) =>
              applyProductionCanonicalProtectedSystemAuthorityReplay(
                control: control,
                replayData: replayData,
                authority: authority,
                groupRepository: groupRepository,
                groupMessageListener: groupMessageListener,
              ),
          retryPendingKeyRepairs:
              groupPendingKeyRepairRunner.retryPendingRepairsForRequest,
        );

    p2pService = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: stagingRepository,
      requiredTransportPeerId: () => qualifiedIdentity.physicalPeerId,
      logicalAccountPeerId: () => qualifiedIdentity.accountPeerId,
      accountMigrationNetworkGate: accountMigrationNetworkGate,
      recoveryOnly: true,
      replayRecoveredInboxChatMessage: (message, {String? stagedEntryId}) =>
          directReplay.replayChatMessage(message, stagedEntryId: stagedEntryId),
      replayLiveDirectChatMessage: (message, {String? stagedEntryId}) =>
          directReplay.replayChatMessage(message, stagedEntryId: stagedEntryId),
      replayLiveLanChatMessage: (message, {String? stagedEntryId}) =>
          directReplay.replayChatMessage(message, stagedEntryId: stagedEntryId),
      replayRecoveredInboxIntroductionMessage: directReplay.replayIntroduction,
      replayRecoveredInboxContactRequest: directReplay.replayContactRequest,
      replayRecoveredInboxReaction: (message, {String? stagedEntryId}) =>
          directReplay.replayReaction(message, stagedEntryId: stagedEntryId),
      replayRecoveredInboxMessageDeletion: (message, {String? stagedEntryId}) =>
          directReplay.replayMessageDeletion(
            message,
            stagedEntryId: stagedEntryId,
          ),
      replayRecoveredProtectedGroupEnvelope: protectedGroupReplay.replay,
      predecryptInboxChatEntry: directReplay.predecryptChatMessage,
    );
    p2pServiceForCleanup = p2pService;
    groupKeyRepairRequestSender = GroupKeyRepairRequestSender(
      bridge: bridge,
      groupRepo: groupRepository,
      getOwnPeerId: () async => identity.peerId,
      getOwnDeviceId: () async => linkedAuthority.credential?.deviceId,
      getOwnPrivateKey: () async => qualifiedIdentity.physicalPrivateKey,
      sendP2PMessage: p2pService.sendMessage,
      storeP2PMessageInInbox: p2pService.storeInInbox,
    );

    chatMessageListener = ChatMessageListener(
      transportAuthority: DatabaseDirectTransportAuthority(database: database),
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => identity.mlKemSecretKey,
      mediaAttachmentRepo: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
      notificationService: notificationService,
      appVisibility: appVisibility,
      notificationToneTracker: notificationToneTracker,
      sendDeliveryReceipt: sendReceipt,
      stageNotificationDisplayCustody: directProjectionOwner.stageMessage,
      promoteNotificationDisplayCustody:
          directProjectionOwner.promoteMessageReadyIfExact,
      retryNotificationDisplays: directProjectionOwner.retryNow,
      accountMigrationNetworkGate: accountMigrationNetworkGate,
    );
    chatMessageListenerForCleanup = chatMessageListener;
    introductionListener = IntroductionListener(
      introductionStream: const Stream<ChatMessage>.empty(),
      introRepo: introductionRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      messageRepo: messageRepository,
      getOwnMlKemSecretKey: () async => identity.mlKemSecretKey,
      getOwnPeerId: () async => identity.peerId,
      notificationService: notificationService,
    );
    introductionListenerForCleanup = introductionListener;
    contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnPeerId: () => qualifiedIdentity.physicalPeerId,
      getOwnPrivateKey: () async => qualifiedIdentity.physicalPrivateKey,
      attemptSilentIntroRecovery: (request) => recoverIntroContactRequest(
        introRepo: introductionRepository,
        requestRepo: contactRequestRepository,
        contactRepo: contactRepository,
        ownPeerId: qualifiedIdentity.physicalPeerId,
        request: request,
        messageRepo: messageRepository,
        bridge: bridge,
      ),
      emitRecoveredIntroductionStatus:
          introductionListener.emitIntroStatusChanged,
      autoAcceptAndReciprocate: null,
    );
    contactRequestListenerForCleanup = contactRequestListener;

    Future<ProductionHeadlessCustodyTotals> readTotals() async {
      final envelope = await notificationLedger.read(
        currentOpaqueBinding: qualifiedIdentity.binding,
      );
      final unresolvedLedgerRecords = envelope == null
          ? 1
          : (envelope.claimsSuspended ? 1 : 0) +
                envelope.records.values
                    .where(
                      (record) =>
                          record.effectPhase !=
                          LocalNotificationEffectPhase.settled,
                    )
                    .length;
      return ProductionHeadlessCustodyTotals(
        directDisplay: await dbCountAllDirectNotificationDisplayOutboxEntries(
          database,
        ),
        directReconciliation:
            await dbCountAllDirectNotificationReconciliationOutboxEntries(
              database,
            ),
        groupDisplay: await dbCountAllGroupNotificationDisplayOutboxEntries(
          database,
        ),
        groupReconciliation:
            await dbCountAllGroupNotificationReconciliationOutboxEntries(
              database,
            ),
        unresolvedLedgerRecords: unresolvedLedgerRecords,
      );
    }

    Future<void>? externalSeal;
    Future<void>? runtimeReady;
    Future<bool>? runtimeOwnerDisposalInFlight;
    var runtimeDisposed = false;
    var p2pServiceDisposed = false;
    var bridgeDisposed = false;
    var projectionOwnersDisposed = false;
    var directProjectionOwnerDisposed = false;
    var groupMessageListenerDisposed = false;
    var groupKeyUpdateListenerDisposed = false;
    var chatMessageListenerDisposed = false;
    var introductionListenerDisposed = false;
    var contactRequestListenerDisposed = false;
    var appVisibilityDisposed = false;
    var notificationServiceDisposed = false;

    Future<void> disposeProjectionOwnersAndServices() async {
      if (projectionOwnersDisposed) return;
      Object? firstError;
      StackTrace? firstStackTrace;

      void disposeOne({
        required bool alreadyDisposed,
        required void Function() dispose,
        required void Function() markDisposed,
      }) {
        if (alreadyDisposed) return;
        try {
          dispose();
          markDisposed();
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }

      disposeOne(
        alreadyDisposed: directProjectionOwnerDisposed,
        dispose: directProjectionOwner.dispose,
        markDisposed: () => directProjectionOwnerDisposed = true,
      );
      disposeOne(
        alreadyDisposed: groupMessageListenerDisposed,
        dispose: groupMessageListener.dispose,
        markDisposed: () => groupMessageListenerDisposed = true,
      );
      disposeOne(
        alreadyDisposed: groupKeyUpdateListenerDisposed,
        dispose: groupKeyUpdateListener.dispose,
        markDisposed: () => groupKeyUpdateListenerDisposed = true,
      );
      disposeOne(
        alreadyDisposed: chatMessageListenerDisposed,
        dispose: chatMessageListener.dispose,
        markDisposed: () => chatMessageListenerDisposed = true,
      );
      disposeOne(
        alreadyDisposed: introductionListenerDisposed,
        dispose: introductionListener.dispose,
        markDisposed: () => introductionListenerDisposed = true,
      );
      disposeOne(
        alreadyDisposed: contactRequestListenerDisposed,
        dispose: contactRequestListener.dispose,
        markDisposed: () => contactRequestListenerDisposed = true,
      );
      disposeOne(
        alreadyDisposed: appVisibilityDisposed,
        dispose: appVisibility.dispose,
        markDisposed: () => appVisibilityDisposed = true,
      );
      disposeOne(
        alreadyDisposed: notificationServiceDisposed,
        dispose: notificationService.dispose,
        markDisposed: () => notificationServiceDisposed = true,
      );

      projectionOwnersDisposed =
          directProjectionOwnerDisposed &&
          groupMessageListenerDisposed &&
          groupKeyUpdateListenerDisposed &&
          chatMessageListenerDisposed &&
          introductionListenerDisposed &&
          contactRequestListenerDisposed &&
          appVisibilityDisposed &&
          notificationServiceDisposed;
      if (firstError != null) {
        Error.throwWithStackTrace(firstError!, firstStackTrace!);
      }
    }

    Future<bool> performRuntimeOwnerDisposalAfterNativeQuiescence() async {
      Object? firstError;
      StackTrace? firstStackTrace;
      if (!p2pServiceDisposed) {
        try {
          p2pService.dispose();
          p2pServiceDisposed = true;
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }
      if (p2pServiceDisposed && !bridgeDisposed) {
        try {
          bridge.dispose();
          bridgeDisposed = true;
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }
      runtimeDisposed = p2pServiceDisposed && bridgeDisposed;
      if (firstError != null) {
        Error.throwWithStackTrace(firstError, firstStackTrace!);
      }
      return runtimeDisposed;
    }

    Future<bool> disposeRuntimeOwnersAfterNativeQuiescence() async {
      if (runtimeDisposed) return true;
      final existing = runtimeOwnerDisposalInFlight;
      if (existing != null) return existing;
      final attempt = performRuntimeOwnerDisposalAfterNativeQuiescence();
      runtimeOwnerDisposalInFlight = attempt;
      try {
        return await attempt;
      } finally {
        if (!runtimeDisposed &&
            identical(runtimeOwnerDisposalInFlight, attempt)) {
          runtimeOwnerDisposalInFlight = null;
        }
      }
    }

    final admissionBarrier = ProductionHeadlessRecoveryAdmissionBarrier();
    return ProductionHeadlessRecoverySessionDelegates(
      ensureRuntimeReady: () => runtimeReady ??= () async {
        await bridge.initialize();
        await notificationService.initialize();
        final started = await p2pService.startRecoveryOnlyNode(
          qualifiedIdentity.physicalPrivateKey,
          qualifiedIdentity.physicalPeerId,
        );
        if (!started) throw StateError('recovery-only node start failed');
      }(),
      ensureTransportHealthy: () async {
        if (!await p2pService.checkRecoveryNodeHealth(
          expectedPeerId: qualifiedIdentity.physicalPeerId,
        )) {
          throw StateError('recovery-only node health failed');
        }
      },
      drainDirectInbox: () async {
        final result = await p2pService.drainOfflineInboxFully();
        return CanonicalRecoveryDrainOutcome(
          isSuccessful: result.isSuccessful,
          hasMore: result.hasMore,
          failureReason: result.failureReason,
        );
      },
      drainGroupInbox: () async {
        final legacy = await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepository,
          msgRepo: groupMessageRepository,
          groupMessageListener: groupMessageListener,
          mediaAttachmentRepo: mediaAttachmentRepository,
          reactionRepo: reactionRepository,
          pendingReactionRepo: groupPendingReactionRepository,
          pendingKeyRepairRepo: groupPendingKeyRepairRepository,
          historyGapRepairRepo: groupHistoryGapRepairRepository,
          requestGroupKeyRepair: groupKeyRepairRequestSender.call,
          selfPeerId: identity.peerId,
        );
        final protected = await p2pService
            .drainProtectedGroupContentRecoveryFixedPoint();
        final legacyConverged = legacy.isSuccessful && !legacy.hasMorePages;
        return CanonicalRecoveryDrainOutcome(
          isSuccessful: legacyConverged && protected.isSuccessful,
          hasMore: legacy.hasMorePages || protected.hasMore,
          failureReason: !legacyConverged
              ? 'legacy_group_drain_failed'
              : protected.isSuccessful
              ? null
              : protected.failureReason ??
                    'protected_group_${protected.disposition.name}',
        );
      },
      settleNotificationProjection: ({required authoritative}) async {
        await directProjectionOwner.retryNow();
        await groupMessageListener.retryPendingNotificationDisplays();
        final totals = await readTotals();
        return CanonicalRecoveryProjectionOutcome(
          isSuccessful: totals.isConverged,
          hasPendingWork: !totals.isConverged,
          failureReason: totals.isConverged
              ? null
              : 'canonical_notification_projection_pending',
        );
      },
      sealExternalAdmission: () {
        externalSeal ??= p2pService.sealRecoveryAdmissionAndAwaitInFlight();
      },
      awaitExternalInFlight: () =>
          externalSeal ??= p2pService.sealRecoveryAdmissionAndAwaitInFlight(),
      stopGroupMessageListener: groupMessageListener.stop,
      disposeProjectionOwners: disposeProjectionOwnersAndServices,
      disposeRuntimeOwnersAfterNativeQuiescence:
          disposeRuntimeOwnersAfterNativeQuiescence,
      admissionBarrier: admissionBarrier,
      hasExternalPostSealRetryableWork: () =>
          p2pService.recoveryAdmissionRefusedAfterSeal,
    );
  } catch (error, stackTrace) {
    final p2pService = p2pServiceForCleanup;
    final groupMessageListener = groupMessageListenerForCleanup;
    final directProjectionOwner = directProjectionOwnerForCleanup;
    final groupKeyUpdateListener = groupKeyUpdateListenerForCleanup;
    final chatMessageListener = chatMessageListenerForCleanup;
    final introductionListener = introductionListenerForCleanup;
    final contactRequestListener = contactRequestListenerForCleanup;
    final appVisibility = appVisibilityForCleanup;
    final notificationService = notificationServiceForCleanup;
    await throwProductionCanonicalRecoveryConstructionFailure(
      cause: error,
      causeStackTrace: stackTrace,
      cleanup: ProductionCanonicalRecoveryPartialConstructionCleanup(
        sealAndAwaitAdmission:
            p2pService?.sealRecoveryAdmissionAndAwaitInFlight,
        stopDartOwners: <Future<void> Function()>[
          if (groupMessageListener != null) groupMessageListener.stop,
        ],
        disposeDartOwners: <void Function()>[
          if (directProjectionOwner != null) directProjectionOwner.dispose,
          if (groupMessageListener != null) groupMessageListener.dispose,
          if (groupKeyUpdateListener != null) groupKeyUpdateListener.dispose,
          if (chatMessageListener != null) chatMessageListener.dispose,
          if (introductionListener != null) introductionListener.dispose,
          if (contactRequestListener != null) contactRequestListener.dispose,
          if (appVisibility != null) appVisibility.dispose,
          if (notificationService != null) notificationService.dispose,
        ],
        stopRuntime: p2pService?.stopNode,
        disposeRuntimeOwners: <void Function()>[
          if (p2pService != null) p2pService.dispose,
          bridge.dispose,
        ],
      ),
    );
  }
}

ContactRepositoryImpl _buildContactRepository(Database database) =>
    ContactRepositoryImpl(
      dbLoadAllContacts: () => dbLoadAllContacts(database),
      dbLoadContact: (peerId) => dbLoadContact(database, peerId),
      dbUpsertContact: (row) => dbUpsertContact(database, row),
      dbDeleteContact: (peerId) => dbDeleteContact(database, peerId),
      dbGetContactCount: () => dbGetContactCount(database),
      dbContactExists: (peerId) => dbContactExists(database, peerId),
      dbArchiveContact: (peerId) => dbArchiveContact(database, peerId),
      dbUnarchiveContact: (peerId) => dbUnarchiveContact(database, peerId),
      dbLoadActiveContacts: () => dbLoadActiveContacts(database),
      dbLoadArchivedContacts: () => dbLoadArchivedContacts(database),
      dbBlockContact: (peerId) => dbBlockContact(database, peerId),
      dbUnblockContact: (peerId) => dbUnblockContact(database, peerId),
      dbDismissIntroBanner: (peerId) => dbDismissIntroBanner(database, peerId),
      dbSetIntrosSentAt: (peerId, timestamp) =>
          dbSetIntrosSentAt(database, peerId, timestamp),
    );

ContactRequestRepositoryImpl _buildContactRequestRepository(
  Database database,
) => ContactRequestRepositoryImpl(
  dbLoadPendingRequests: () => dbLoadPendingRequests(database),
  dbLoadRequest: (peerId) => dbLoadRequest(database, peerId),
  dbUpsertRequest: (row) => dbUpsertRequest(database, row),
  dbUpdateRequestStatus: (peerId, status) =>
      dbUpdateRequestStatus(database, peerId, status),
  dbDeleteRequest: (peerId) => dbDeleteRequest(database, peerId),
  dbRequestExists: (peerId) => dbRequestExists(database, peerId),
);

MessageRepositoryImpl _buildMessageRepository(
  Database database, {
  Future<int> Function(String peerId)? projectConversationRead,
}) => MessageRepositoryImpl(
  dbInsertMessage: (row) => dbInsertMessage(database, row),
  dbLoadMessagesForContact: (peerId) =>
      dbLoadMessagesForContact(database, peerId),
  dbLoadLatestMessageForContact: (peerId) =>
      dbLoadLatestMessageForContact(database, peerId),
  dbUpdateMessageStatus: (id, status) =>
      dbUpdateMessageStatus(database, id, status),
  dbLoadMessage: (id) => dbLoadMessage(database, id),
  dbCountMessagesForContact: (peerId) =>
      dbCountMessagesForContact(database, peerId),
  dbMarkConversationAsRead: (peerId) =>
      dbMarkConversationAsRead(database, peerId),
  projectConversationRead: projectConversationRead,
  dbCountUnreadForContact: (peerId) =>
      dbCountUnreadForContact(database, peerId),
  dbCountTotalUnread: () => dbCountTotalUnread(database),
  dbCountTotalUnreadExcludingArchived: () =>
      dbCountTotalUnreadExcludingArchived(database),
  dbDeleteMessagesForContact: (peerId) =>
      dbDeleteMessagesForContact(database, peerId),
  dbDeleteMessage: (id) => dbDeleteMessage(database, id),
  dbExistsMessageByContent: (peerId, senderPeerId, text, timestamp) =>
      dbExistsMessageByContent(database, peerId, senderPeerId, text, timestamp),
  dbExistsMessageByDedupKey: (peerId, senderPeerId, dedupKey) =>
      dbExistsMessageByDedupKey(database, peerId, senderPeerId, dedupKey),
  dbLoadMessagesPage: (peerId, {limit = 50, beforeTimestamp}) =>
      dbLoadMessagesPage(
        database,
        peerId,
        limit: limit,
        beforeTimestamp: beforeTimestamp,
      ),
  dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(database),
  dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
      dbLoadUnackedOutgoingMessages(
        database,
        olderThan: olderThan,
        limit: limit,
      ),
  dbLoadConversationThreadSummaries: (peerIds) =>
      dbLoadConversationThreadSummaries(database, peerIds),
  dbRecoverStuckSendingMessages:
      ({required DateTime olderThan, int limit = 50}) =>
          dbRecoverStuckSendingMessages(
            database,
            olderThan: olderThan,
            limit: limit,
          ),
  dbLoadStuckSendingOutgoingMessages:
      ({required DateTime olderThan, int limit = 50}) =>
          dbLoadStuckSendingOutgoingMessages(
            database,
            olderThan: olderThan,
            limit: limit,
          ),
  dbLoadSendingOutgoingMessages: () => dbLoadSendingOutgoingMessages(database),
  dbConditionalTransitionStatus:
      (id, {required fromStatus, required toStatus}) =>
          dbConditionalTransitionStatus(
            database,
            id,
            fromStatus: fromStatus,
            toStatus: toStatus,
          ),
  dbApplyIncomingOrdinaryTextMutationWithAuthority:
      ({
        required incomingRow,
        required kind,
        required authenticatedTransportPeerId,
      }) => dbApplyIncomingOrdinaryTextMutation(
        database,
        incomingRow: incomingRow,
        kind: kind,
        authenticatedTransportPeerId: authenticatedTransportPeerId,
      ),
  dbApplyIncomingDirectMessageDeletionWithAuthority:
      ({
        required messageId,
        required senderPeerId,
        required deletedAt,
        required transport,
        required createdAt,
        required authenticatedTransportPeerId,
      }) => dbApplyIncomingDirectMessageDeletion(
        database,
        messageId: messageId,
        senderPeerId: senderPeerId,
        deletedAt: deletedAt,
        transport: transport,
        createdAt: createdAt,
        authenticatedTransportPeerId: authenticatedTransportPeerId,
      ),
);

MediaAttachmentRepositoryImpl _buildMediaAttachmentRepository(
  Database database,
  SecureKeyStore secureKeyStore,
) => MediaAttachmentRepositoryImpl(
  dbSaveMediaAttachmentPreservingLocalState: (row) =>
      dbSaveMediaAttachmentPreservingLocalState(database, row),
  dbCanApplyGenericMediaAttachmentSave: (row) =>
      dbCanApplyGenericMediaAttachmentSave(database, row),
  dbLoadMediaForMessage: (messageId, ownerLane) =>
      dbLoadMediaForMessage(database, messageId, ownerLane: ownerLane),
  dbLoadMediaById: (id) => dbLoadMediaById(database, id),
  dbLoadMediaForMessages: (messageIds, ownerLane) =>
      dbLoadMediaForMessages(database, messageIds, ownerLane: ownerLane),
  dbUpdateMediaLocalPath: (id, path, status) =>
      dbUpdateMediaLocalPath(database, id, path, status),
  dbUpdateMediaDownloadStatus: (id, status) =>
      dbUpdateMediaDownloadStatus(database, id, status),
  dbDeleteMediaForMessage: (messageId, ownerLane) =>
      dbDeleteMediaForMessage(database, messageId, ownerLane: ownerLane),
  dbDeleteMediaForContact: (peerId) =>
      dbDeleteMediaForContact(database, peerId),
  dbMarkUploadPendingAttachmentsFailedForMessage: (messageId, ownerLane) =>
      dbMarkUploadPendingAttachmentsFailedForMessage(
        database,
        messageId,
        ownerLane: ownerLane,
      ),
  dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(database),
  dbLoadUploadPendingAttachments: ({limit = 50, required ownerLane}) =>
      dbLoadUploadPendingAttachments(
        database,
        limit: limit,
        ownerLane: ownerLane,
      ),
  dbSetMediaBookmarked: (id, bookmarked) =>
      dbSetMediaBookmarked(database, id, bookmarked: bookmarked),
  dbUpdateMediaPlaybackPosition: (id, positionMs) =>
      dbUpdateMediaPlaybackPosition(database, id, positionMs),
  dbLoadMediaLibraryPage:
      ({
        required scopeKind,
        required scopeId,
        required mediaTypes,
        required bookmarkedOnly,
        incomingOnly = false,
        required limit,
        afterTimestamp,
        afterMessageId,
        afterAttachmentId,
      }) => dbLoadMediaLibraryPage(
        database,
        scopeKind: scopeKind,
        scopeId: scopeId,
        mediaTypes: mediaTypes,
        bookmarkedOnly: bookmarkedOnly,
        incomingOnly: incomingOnly,
        limit: limit,
        afterTimestamp: afterTimestamp,
        afterMessageId: afterMessageId,
        afterAttachmentId: afterAttachmentId,
      ),
  dbSaveDirectPrivateMediaAttachmentGuarded:
      (row, {required messageId, required nowMs}) =>
          dbSaveDirectPrivateMediaAttachmentGuarded(
            database,
            row,
            messageId: messageId,
            nowMs: nowMs,
          ),
  secureKeyStore: secureKeyStore,
);

ReactionRepositoryImpl _buildReactionRepository(
  Database database,
) => ReactionRepositoryImpl(
  dbInsertReaction: (row) => dbInsertReaction(database, row),
  dbApplyIncomingAddWithAuthority:
      (row, {required authenticatedTransportPeerId}) async {
        final result = await dbApplyIncomingReactionMutation(
          database,
          row,
          mutation: DbIncomingReactionMutation.add,
          authenticatedTransportPeerId: authenticatedTransportPeerId,
        );
        return switch (result) {
          DbIncomingReactionApplyResult.inserted =>
            ReactionAddApplyResult.inserted,
          DbIncomingReactionApplyResult.updated =>
            ReactionAddApplyResult.updated,
          DbIncomingReactionApplyResult.exactReplay =>
            ReactionAddApplyResult.exactReplay,
          DbIncomingReactionApplyResult.stale => ReactionAddApplyResult.stale,
          DbIncomingReactionApplyResult.removed => throw StateError(
            'ADD returned REMOVE',
          ),
        };
      },
  dbApplyIncomingRemoveWithAuthority:
      (row, {required authenticatedTransportPeerId}) async {
        final result = await dbApplyIncomingReactionMutation(
          database,
          row,
          mutation: DbIncomingReactionMutation.remove,
          authenticatedTransportPeerId: authenticatedTransportPeerId,
        );
        return switch (result) {
          DbIncomingReactionApplyResult.removed =>
            ReactionRemoveApplyResult.applied,
          DbIncomingReactionApplyResult.exactReplay =>
            ReactionRemoveApplyResult.exactReplay,
          DbIncomingReactionApplyResult.stale =>
            ReactionRemoveApplyResult.stale,
          DbIncomingReactionApplyResult.inserted ||
          DbIncomingReactionApplyResult.updated => throw StateError(
            'REMOVE returned ADD',
          ),
        };
      },
  dbApplyIncomingAdd: (row) async {
    final result = await dbApplyIncomingReactionMutation(
      database,
      row,
      mutation: DbIncomingReactionMutation.add,
    );
    return switch (result) {
      DbIncomingReactionApplyResult.inserted => ReactionAddApplyResult.inserted,
      DbIncomingReactionApplyResult.updated => ReactionAddApplyResult.updated,
      DbIncomingReactionApplyResult.exactReplay =>
        ReactionAddApplyResult.exactReplay,
      DbIncomingReactionApplyResult.stale => ReactionAddApplyResult.stale,
      DbIncomingReactionApplyResult.removed => throw StateError(
        'ADD returned REMOVE',
      ),
    };
  },
  dbApplyIncomingRemove: (row) async {
    final result = await dbApplyIncomingReactionMutation(
      database,
      row,
      mutation: DbIncomingReactionMutation.remove,
    );
    return switch (result) {
      DbIncomingReactionApplyResult.removed =>
        ReactionRemoveApplyResult.applied,
      DbIncomingReactionApplyResult.exactReplay =>
        ReactionRemoveApplyResult.exactReplay,
      DbIncomingReactionApplyResult.stale => ReactionRemoveApplyResult.stale,
      DbIncomingReactionApplyResult.inserted ||
      DbIncomingReactionApplyResult.updated => throw StateError(
        'REMOVE returned ADD',
      ),
    };
  },
  dbApplyGroupAdd:
      ({required groupId, required notificationEventId, required row}) async {
        final result = await dbApplyIncomingReactionMutation(
          database,
          row,
          mutation: DbIncomingReactionMutation.add,
          groupIdForNotificationCleanup: groupId,
          notificationEventIdForStaleAddCleanup: notificationEventId,
        );
        return result == DbIncomingReactionApplyResult.inserted
            ? ReactionAddApplyResult.inserted
            : result == DbIncomingReactionApplyResult.updated
            ? ReactionAddApplyResult.updated
            : result == DbIncomingReactionApplyResult.exactReplay
            ? ReactionAddApplyResult.exactReplay
            : ReactionAddApplyResult.stale;
      },
  dbApplyGroupRemove: ({required groupId, required row}) async {
    final result = await dbApplyIncomingReactionMutation(
      database,
      row,
      mutation: DbIncomingReactionMutation.remove,
      groupIdForNotificationCleanup: groupId,
    );
    return result == DbIncomingReactionApplyResult.removed
        ? ReactionRemoveApplyResult.applied
        : result == DbIncomingReactionApplyResult.exactReplay
        ? ReactionRemoveApplyResult.exactReplay
        : ReactionRemoveApplyResult.stale;
  },
  dbLoadReactionsForMessage: (messageId) =>
      dbLoadReactionsForMessage(database, messageId),
  dbLoadReactionsForMessages: (messageIds) =>
      dbLoadReactionsForMessages(database, messageIds),
  dbLoadActiveOrTombstonedReactionForSender: (messageId, senderPeerId) =>
      dbLoadActiveOrTombstonedReactionForSender(
        database,
        messageId,
        senderPeerId,
      ),
  dbDeleteReaction: (messageId, senderPeerId, {removedAtTimestamp}) =>
      dbDeleteReaction(
        database,
        messageId,
        senderPeerId,
        removedAtTimestamp: removedAtTimestamp,
      ),
  dbDeleteReactionsForMessage: (messageId) =>
      dbDeleteReactionsForMessage(database, messageId),
  dbDeleteReactionsForContact: (peerId) =>
      dbDeleteReactionsForContact(database, peerId),
);

IntroductionRepositoryImpl _buildIntroductionRepository(Database database) =>
    IntroductionRepositoryImpl(
      dbInsertIntroduction: (row) => dbInsertIntroduction(database, row),
      dbLoadIntroduction: (id) => dbLoadIntroduction(database, id),
      dbDeleteIntroduction: (id) => dbDeleteIntroduction(database, id),
      dbLoadIntroductionsByRecipient: (id) =>
          dbLoadIntroductionsByRecipient(database, id),
      dbLoadIntroductionsByIntroduced: (id) =>
          dbLoadIntroductionsByIntroduced(database, id),
      dbLoadIntroductionsByIntroducer: (id) =>
          dbLoadIntroductionsByIntroducer(database, id),
      dbLoadIntroductionsForRecipientAndIntroducer: (recipient, introducer) =>
          dbLoadIntroductionsForRecipientAndIntroducer(
            database,
            recipient,
            introducer,
          ),
      dbUpdateRecipientStatus: (id, status, respondedAt) =>
          dbUpdateRecipientStatus(database, id, status, respondedAt),
      dbUpdateIntroducedStatus: (id, status, respondedAt) =>
          dbUpdateIntroducedStatus(database, id, status, respondedAt),
      dbUpdateOverallStatus: (id, status) =>
          dbUpdateOverallStatus(database, id, status),
      dbLoadPendingIntroductionsForUser: (peerId) =>
          dbLoadPendingIntroductionsForUser(database, peerId),
      dbCountPendingIntroductions: (peerId) =>
          dbCountPendingIntroductions(database, peerId),
      dbUpsertPendingIntroductionResponse: (row) =>
          dbUpsertPendingIntroductionResponse(database, row),
      dbLoadPendingIntroductionResponses: (id) =>
          dbLoadPendingIntroductionResponses(database, id),
      dbDeletePendingIntroductionResponse: (key) =>
          dbDeletePendingIntroductionResponse(database, key),
      dbUpsertIntroductionOutboxDelivery: (row) =>
          dbUpsertIntroductionOutboxDelivery(database, row),
      dbSaveIntroductionWithOutboxDeliveries: (intro, deliveries) =>
          dbSaveIntroductionWithOutboxDeliveries(database, intro, deliveries),
      dbReplaceIntroductionWithPendingResponseMigration:
          ({
            required introductionRow,
            required deliveryRows,
            required replacedIntroductionIds,
          }) => dbReplaceIntroductionWithPendingResponseMigration(
            database,
            introductionRow: introductionRow,
            deliveryRows: deliveryRows,
            replacedIntroductionIds: replacedIntroductionIds,
          ),
      dbSaveIntroductionResponseWithOutboxDeliveries:
          ({
            required introductionId,
            required isRecipient,
            required responseStatus,
            required respondedAt,
            required overallStatus,
            required deliveryRows,
          }) => dbSaveIntroductionResponseWithOutboxDeliveries(
            database,
            introductionId: introductionId,
            isRecipient: isRecipient,
            responseStatus: responseStatus,
            respondedAt: respondedAt,
            overallStatus: overallStatus,
            deliveryRows: deliveryRows,
          ),
      dbLoadIntroductionOutboxDeliveriesForIntroduction: (id) =>
          dbLoadIntroductionOutboxDeliveriesForIntroduction(database, id),
      dbLoadRetryableIntroductionOutboxDeliveries:
          ({required olderThan, limit = 100}) =>
              dbLoadRetryableIntroductionOutboxDeliveries(
                database,
                olderThan: olderThan,
                limit: limit,
              ),
      dbDeleteIntroductionOutboxDelivery: (id) =>
          dbDeleteIntroductionOutboxDelivery(database, id),
      dbDeleteIntroductionOutboxDeliveriesForIntroduction: (id) =>
          dbDeleteIntroductionOutboxDeliveriesForIntroduction(database, id),
    );

InboxStagingRepositoryImpl _buildInboxStagingRepository(
  Database database,
) => InboxStagingRepositoryImpl(
  dbInsertInboxStagingEntry: (row) => dbInsertInboxStagingEntry(database, row),
  dbLoadRecoverableInboxStagingEntries: ({limit = 50, entryIds}) =>
      dbLoadRecoverableInboxStagingEntries(
        database,
        limit: limit,
        entryIds: entryIds,
      ),
  dbLoadInboxStagingEntry: (id) => dbLoadInboxStagingEntry(database, id),
  dbDeleteInboxStagingEntry: (id) => dbDeleteInboxStagingEntry(database, id),
  dbMarkInboxStagingEntryRetryable: (id, {required reasonCode, reasonDetail}) =>
      dbMarkInboxStagingEntryRetryable(
        database,
        id,
        reasonCode: reasonCode,
        reasonDetail: reasonDetail,
      ),
  dbMarkInboxStagingEntryPrerequisiteWaiting:
      (id, {required reasonCode, reasonDetail}) =>
          dbMarkInboxStagingEntryPrerequisiteWaiting(
            database,
            id,
            reasonCode: reasonCode,
            reasonDetail: reasonDetail,
          ),
  dbMarkInboxStagingEntryProtectedAckPending: (id) =>
      dbMarkInboxStagingEntryProtectedAckPending(database, id),
  dbMarkInboxStagingEntryRejected: (id, {required reasonCode, reasonDetail}) =>
      dbMarkInboxStagingEntryRejected(
        database,
        id,
        reasonCode: reasonCode,
        reasonDetail: reasonDetail,
      ),
  dbMarkInboxStagingEntryQuarantined:
      (id, {required reasonCode, reasonDetail}) =>
          dbMarkInboxStagingEntryQuarantined(
            database,
            id,
            reasonCode: reasonCode,
            reasonDetail: reasonDetail,
          ),
  dbCountQuarantinedInboxStagingEntries: () =>
      dbCountQuarantinedInboxStagingEntries(database),
  dbCountNeedsAttentionInboxStagingEntries: () =>
      dbCountNeedsAttentionInboxStagingEntries(database),
);

GroupRepositoryImpl _buildGroupRepository(
  Database database,
  SecureKeyStore secureKeyStore,
) => GroupRepositoryImpl(
  dbInsertGroup: (row) => dbInsertGroup(database, row),
  dbLoadAllGroups: () => dbLoadAllGroups(database),
  dbLoadGroup: (id) => dbLoadGroup(database, id),
  dbUpdateGroup: (row) => dbUpdateGroup(database, row),
  dbCommitProtectedGroupMetadataAuthorityFn:
      ({
        required expectedGroupRow,
        required expectedMemberRows,
        required expectedLatestKeyGeneration,
        required groupRow,
        required pendingBroadcastRows,
        required authorityPreparedSourcePeerId,
        required authorityPreparedSourceEventId,
        required authorityPreparedSourceTimestamp,
        required authorityPreparedPayload,
      }) => dbCommitProtectedGroupMetadataAuthority(
        database,
        expectedGroupRow: expectedGroupRow,
        expectedMemberRows: expectedMemberRows,
        expectedLatestKeyGeneration: expectedLatestKeyGeneration,
        groupRow: groupRow,
        pendingBroadcastRows: pendingBroadcastRows,
        authorityPreparedSourcePeerId: authorityPreparedSourcePeerId,
        authorityPreparedSourceEventId: authorityPreparedSourceEventId,
        authorityPreparedSourceTimestamp: authorityPreparedSourceTimestamp,
        authorityPreparedPayload: authorityPreparedPayload,
      ),
  dbCommitDissolvedGroup: (row) =>
      dbCommitDissolvedGroupAndDeleteNotificationDisplayOutbox(database, row),
  dbCommitProtectedDissolvedGroup:
      ({
        required groupRow,
        required expectedBroadcastRows,
        required authorityCompleteSourcePeerId,
        required authorityCompleteSourceEventId,
        required authorityCompleteSourceTimestamp,
        required authorityCompletePayload,
      }) => dbCommitProtectedDissolvedGroup(
        database,
        groupRow: groupRow,
        expectedBroadcastRows: expectedBroadcastRows,
        authorityCompleteSourcePeerId: authorityCompleteSourcePeerId,
        authorityCompleteSourceEventId: authorityCompleteSourceEventId,
        authorityCompleteSourceTimestamp: authorityCompleteSourceTimestamp,
        authorityCompletePayload: authorityCompletePayload,
      ),
  dbDeleteGroup: (id) => dbDeleteGroup(database, id),
  dbLoadActiveGroups: () => dbLoadActiveGroups(database),
  dbArchiveGroup: (id) => dbArchiveGroup(database, id),
  dbUnarchiveGroup: (id) => dbUnarchiveGroup(database, id),
  dbAdvanceGroupMembershipWatermark:
      ({required groupId, required eventAt, required eventId}) =>
          dbAdvanceGroupMembershipWatermark(
            database,
            groupId: groupId,
            eventAt: eventAt,
            eventId: eventId,
          ),
  dbLoadGroupForwardAuthorizationSnapshot: (groupId) =>
      dbLoadGroupForwardAuthorizationSnapshot(database, groupId),
  dbInsertGroupMember: (row) => dbInsertGroupMember(database, row),
  dbLoadAllGroupMembers: (groupId) => dbLoadAllGroupMembers(database, groupId),
  dbLoadGroupMember: (groupId, peerId) =>
      dbLoadGroupMember(database, groupId, peerId),
  dbUpdateGroupMemberRole: (groupId, peerId, role) =>
      dbUpdateGroupMemberRole(database, groupId, peerId, role),
  dbDeleteGroupMember: (groupId, peerId) =>
      dbDeleteGroupMember(database, groupId, peerId),
  dbDeleteAllGroupMembers: (groupId) =>
      dbDeleteAllGroupMembers(database, groupId),
  dbInsertRemovedGroupMemberSnapshot: (row, removedAt) =>
      dbInsertRemovedGroupMemberSnapshot(database, row, removedAt),
  dbLoadRemovedGroupMemberSnapshot: (groupId, peerId) =>
      dbLoadRemovedGroupMemberSnapshot(database, groupId, peerId),
  dbUpsertGroupMemberDeviceSnapshot: (row, savedAt) =>
      dbUpsertGroupMemberDeviceSnapshot(database, row, savedAt),
  dbLoadGroupMemberDeviceSnapshot: (groupId, peerId) =>
      dbLoadGroupMemberDeviceSnapshot(database, groupId, peerId),
  dbUpsertPendingSiblingDevice: (row) =>
      dbUpsertPendingSiblingDevice(database, row),
  dbLoadPendingSiblingDevicesForGroup: (groupId) =>
      dbLoadPendingSiblingDevicesForGroup(database, groupId),
  dbLoadPendingSiblingDevice: (groupId, memberPeerId, deviceId) =>
      dbLoadPendingSiblingDevice(database, groupId, memberPeerId, deviceId),
  dbDeletePendingSiblingDevice: (groupId, memberPeerId, deviceId) =>
      dbDeletePendingSiblingDevice(database, groupId, memberPeerId, deviceId),
  dbCommitLinkedGroupBootstrapAuthoringFn:
      ({
        required expectedGroup,
        required expectedMembers,
        required expectedSelfMember,
        required expectedLatestKeyGeneration,
        required expectedLatestKeyCreatedAt,
        required updatedSelfMember,
        required pendingDevice,
        required pendingBroadcast,
        required authorityGenesisSourcePeerId,
        required authorityGenesisSourceEventId,
        required authorityGenesisSourceTimestamp,
        required authorityGenesisPayload,
      }) => dbCommitLinkedGroupBootstrapAuthoring(
        database,
        expectedGroup: expectedGroup,
        expectedMembers: expectedMembers,
        expectedSelfMember: expectedSelfMember,
        expectedLatestKeyGeneration: expectedLatestKeyGeneration,
        expectedLatestKeyCreatedAt: expectedLatestKeyCreatedAt,
        updatedSelfMember: updatedSelfMember,
        pendingDevice: pendingDevice,
        pendingBroadcast: pendingBroadcast,
        authorityGenesisSourcePeerId: authorityGenesisSourcePeerId,
        authorityGenesisSourceEventId: authorityGenesisSourceEventId,
        authorityGenesisSourceTimestamp: authorityGenesisSourceTimestamp,
        authorityGenesisPayload: authorityGenesisPayload,
      ),
  dbCompleteLinkedGroupBootstrapCustodyFn:
      ({required expectedDevice, required expectedBroadcast}) =>
          dbCompleteLinkedGroupBootstrapCustody(
            database,
            expectedDevice: expectedDevice,
            expectedBroadcast: expectedBroadcast,
          ),
  dbCommitLinkedGroupBootstrapMaterializationFn:
      ({
        required groupRow,
        required memberRows,
        required keyRow,
        required authorityGenesisSourcePeerId,
        required authorityGenesisSourceEventId,
        required authorityGenesisSourceTimestamp,
        required authorityGenesisPayload,
      }) => dbCommitLinkedGroupBootstrapMaterialization(
        database,
        groupRow: groupRow,
        memberRows: memberRows,
        keyRow: keyRow,
        authorityGenesisSourcePeerId: authorityGenesisSourcePeerId,
        authorityGenesisSourceEventId: authorityGenesisSourceEventId,
        authorityGenesisSourceTimestamp: authorityGenesisSourceTimestamp,
        authorityGenesisPayload: authorityGenesisPayload,
      ),
  dbHasLinkedGroupBootstrapIntentFn:
      ({required groupId, required transportPeerId}) =>
          dbHasLinkedGroupBootstrapIntent(
            database,
            groupId: groupId,
            transportPeerId: transportPeerId,
          ),
  dbInsertGroupKey: (row) => dbInsertGroupKey(database, row),
  dbCommitProtectedGroupKeyAuthority:
      ({
        required keyRow,
        required authorityCompleteSourcePeerId,
        required authorityCompleteSourceEventId,
        required authorityCompleteSourceTimestamp,
        required authorityCompletePayload,
      }) => dbCommitGroupKeyWithAuthorityComplete(
        database,
        keyRow: keyRow,
        authorityCompleteSourcePeerId: authorityCompleteSourcePeerId,
        authorityCompleteSourceEventId: authorityCompleteSourceEventId,
        authorityCompleteSourceTimestamp: authorityCompleteSourceTimestamp,
        authorityCompletePayload: authorityCompletePayload,
      ),
  dbLoadLatestGroupKey: (groupId) => dbLoadLatestGroupKey(database, groupId),
  dbLoadGroupKeyByGeneration: (groupId, generation) =>
      dbLoadGroupKeyByGeneration(database, groupId, generation),
  dbDeleteAllGroupKeys: (groupId) => dbDeleteAllGroupKeys(database, groupId),
  dbLoadAllGroupKeys: (groupId) => dbLoadAllGroupKeys(database, groupId),
  dbDeleteGroupKeysBeforeGeneration: (groupId, minKeyGenerationToKeep) =>
      dbDeleteGroupKeysBeforeGeneration(
        database,
        groupId,
        minKeyGenerationToKeep,
      ),
  dbUpsertPendingGroupKeyRotation: (row) =>
      dbUpsertPendingGroupKeyRotation(database, row),
  dbLoadPendingGroupKeyRotation: (groupId) =>
      dbLoadPendingGroupKeyRotation(database, groupId),
  dbDeletePendingGroupKeyRotation: (groupId, keyGeneration) =>
      dbDeletePendingGroupKeyRotation(database, groupId, keyGeneration),
  dbDeletePendingGroupKeyRotations: (groupId) =>
      dbDeletePendingGroupKeyRotations(database, groupId),
  groupKeyStore: secureKeyStore,
);

GroupPendingKeyRepairRepositoryImpl _buildGroupPendingKeyRepairRepository(
  Database database,
) => GroupPendingKeyRepairRepositoryImpl(
  dbUpsertGroupPendingKeyRepair: (row) =>
      dbUpsertGroupPendingKeyRepair(database, row),
  dbLoadGroupPendingKeyRepair: (id) =>
      dbLoadGroupPendingKeyRepair(database, id),
  dbLoadPendingGroupKeyRepairsForEpoch:
      ({required groupId, required keyEpoch, int limit = 50}) =>
          dbLoadPendingGroupKeyRepairsForEpoch(
            database,
            groupId: groupId,
            keyEpoch: keyEpoch,
            limit: limit,
          ),
  dbLoadAllPendingGroupKeyRepairs: ({int limit = 200}) =>
      dbLoadAllPendingGroupKeyRepairs(database, limit: limit),
  dbLoadPendingGroupKeyRepairsForGroup: ({required groupId, int limit = 100}) =>
      dbLoadPendingGroupKeyRepairsForGroup(
        database,
        groupId: groupId,
        limit: limit,
      ),
  dbDeleteGroupPendingKeyRepair: (id) =>
      dbDeleteGroupPendingKeyRepair(database, id),
  dbDeleteGroupPendingKeyRepairIfExact: (expected) =>
      dbDeleteGroupPendingKeyRepairIfExact(database, expected),
  dbRecordGroupPendingKeyRepairAttempt:
      (id, {required lastError, required updatedAt}) =>
          dbRecordGroupPendingKeyRepairAttempt(
            database,
            id,
            lastError: lastError,
            updatedAt: updatedAt,
          ),
  dbRecordGroupPendingKeyRepairAttemptIfExact:
      (expected, {required lastError, required updatedAt}) =>
          dbRecordGroupPendingKeyRepairAttemptIfExact(
            database,
            expected,
            lastError: lastError,
            updatedAt: updatedAt,
          ),
  dbFinalizeGroupPendingKeyRepair:
      (id, {required status, required lastError, required finalizedAt}) =>
          dbFinalizeGroupPendingKeyRepair(
            database,
            id,
            status: status,
            lastError: lastError,
            finalizedAt: finalizedAt,
          ),
  dbFinalizeGroupPendingKeyRepairIfExact:
      (expected, {required status, required lastError, required finalizedAt}) =>
          dbFinalizeGroupPendingKeyRepairIfExact(
            database,
            expected,
            status: status,
            lastError: lastError,
            finalizedAt: finalizedAt,
          ),
);

GroupPendingMembershipMessageRepositoryImpl
_buildGroupPendingMembershipRepository(Database database) =>
    GroupPendingMembershipMessageRepositoryImpl(
      dbUpsertGroupPendingMembershipMessage: (row) =>
          dbUpsertGroupPendingMembershipMessage(database, row),
      dbLoadGroupPendingMembershipMessages: ({int limit = 200}) =>
          dbLoadGroupPendingMembershipMessages(database, limit: limit),
      dbLoadGroupPendingMembershipMessagesForSenders:
          ({required groupId, required senderPeerIds, int limit = 50}) =>
              dbLoadGroupPendingMembershipMessagesForSenders(
                database,
                groupId: groupId,
                senderPeerIds: senderPeerIds,
                limit: limit,
              ),
      dbDeleteGroupPendingMembershipMessage: (id) =>
          dbDeleteGroupPendingMembershipMessage(database, id),
      dbDeleteGroupPendingMembershipMessageByGroupAndMessageId:
          ({required groupId, required messageId}) =>
              dbDeleteGroupPendingMembershipMessageByGroupAndMessageId(
                database,
                groupId: groupId,
                messageId: messageId,
              ),
      dbPruneGroupPendingMembershipMessages: (groupId, {required maxRows}) =>
          dbPruneGroupPendingMembershipMessages(
            database,
            groupId,
            maxRows: maxRows,
          ),
    );

GroupPendingReactionRepositoryImpl _buildGroupPendingReactionRepository(
  Database database,
) => GroupPendingReactionRepositoryImpl(
  dbUpsertGroupPendingReaction: (row) =>
      dbUpsertGroupPendingReaction(database, row),
  dbLoadGroupPendingReactionsForMessage:
      ({required groupId, required messageId}) =>
          dbLoadGroupPendingReactionsForMessage(
            database,
            groupId: groupId,
            messageId: messageId,
          ),
  dbLoadGroupPendingReactions: ({int limit = 200}) =>
      dbLoadGroupPendingReactions(database, limit: limit),
  dbDeleteGroupPendingReaction: (id) =>
      dbDeleteGroupPendingReaction(database, id),
  dbPruneGroupPendingReactions: (groupId, {required maxRows}) =>
      dbPruneGroupPendingReactions(database, groupId, maxRows: maxRows),
  dbDeleteExpiredGroupPendingReactions: ({required olderThanIso}) =>
      dbDeleteExpiredGroupPendingReactions(
        database,
        olderThanIso: olderThanIso,
      ),
);

GroupHistoryGapRepairRepositoryImpl _buildGroupHistoryGapRepairRepository(
  Database database,
) => GroupHistoryGapRepairRepositoryImpl(
  dbUpsertGroupHistoryGapRepair: (row) =>
      dbUpsertGroupHistoryGapRepair(database, row),
  dbSaveGroupHistoryGapRepair: (row) =>
      dbSaveGroupHistoryGapRepair(database, row),
  dbReplaceGroupHistoryGapRepairIfExact:
      ({required expected, required replacement}) =>
          dbReplaceGroupHistoryGapRepairIfExact(
            database,
            expected: expected,
            replacement: replacement,
          ),
  dbLoadGroupHistoryGapRepair: ({required groupId, required gapId}) =>
      dbLoadGroupHistoryGapRepair(database, groupId: groupId, gapId: gapId),
  dbLoadLatestGroupHistoryGapRepair: ({required groupId}) =>
      dbLoadLatestGroupHistoryGapRepair(database, groupId: groupId),
  dbLoadVisibleGroupHistoryGapRepairs: ({required groupId, int limit = 20}) =>
      dbLoadVisibleGroupHistoryGapRepairs(
        database,
        groupId: groupId,
        limit: limit,
      ),
);

GroupMessageRepositoryImpl _buildGroupMessageRepository(Database database) {
  GroupMessageRepositoryImpl build(
    dynamic executor, {
    bool transactional = false,
  }) {
    return GroupMessageRepositoryImpl(
      dbInsertGroupMessage: (row) => dbInsertGroupMessage(executor, row),
      dbLoadGroupMessagesPage: (groupId, {limit = 50, offset = 0}) =>
          dbLoadGroupMessagesPage(
            executor,
            groupId,
            limit: limit,
            offset: offset,
          ),
      dbLoadGroupMessage: (id) => dbLoadGroupMessage(executor, id),
      dbLoadGroupMessageByLogicalDeliveryIdFn:
          (groupId, senderPeerId, logicalDeliveryId) =>
              dbLoadGroupMessageByLogicalDeliveryId(
                executor,
                groupId,
                senderPeerId,
                logicalDeliveryId,
              ),
      dbLoadLatestGroupMessage: (groupId) =>
          dbLoadLatestGroupMessage(executor, groupId),
      dbLoadLatestRemovalTimestampForSenderFn: (groupId, senderPeerId) =>
          dbLoadLatestGroupRemovalTimestampForSender(
            executor,
            groupId,
            senderPeerId,
          ),
      dbUpdateGroupMessageStatus: (id, status) =>
          dbUpdateGroupMessageStatus(executor, id, status),
      dbCountGroupMessages: (groupId) =>
          dbCountGroupMessages(executor, groupId),
      dbCountUnreadGroupMessages: (groupId) =>
          dbCountUnreadGroupMessages(executor, groupId),
      dbCountTotalUnreadGroupMessages: () =>
          dbCountTotalUnreadGroupMessages(executor),
      dbMarkGroupMessagesAsRead: (groupId) =>
          dbMarkGroupMessagesAsRead(executor, groupId),
      dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(executor, id),
      dbExistsGroupMessageByContent: (groupId, senderPeerId, text, timestamp) =>
          dbExistsGroupMessageByContent(
            executor,
            groupId,
            senderPeerId,
            text,
            timestamp,
          ),
      dbDeleteGroupMessagesForGroup: (groupId) =>
          dbDeleteGroupMessagesForGroup(executor, groupId),
      dbLoadGroupThreadSummaries: (groupIds) =>
          dbLoadGroupThreadSummaries(executor, groupIds),
      dbLoadGroupMessagesWithFailedInboxStore:
          ({int limit = 50, bool strictContentOnly = false, int offset = 0}) =>
              dbLoadGroupMessagesWithFailedInboxStore(
                executor,
                limit: limit,
                strictContentOnly: strictContentOnly,
                offset: offset,
              ),
      dbUpdateGroupMessageInboxStoredFn: (id, {required stored}) =>
          dbUpdateGroupMessageInboxStored(executor, id, stored: stored),
      dbUpdateGroupMessageInboxRetryPayloadFn: (id, payload) =>
          dbUpdateGroupMessageInboxRetryPayload(executor, id, payload),
      dbUpdateGroupMessageWireEnvelopeFn: (id, envelope) =>
          dbUpdateGroupMessageWireEnvelope(executor, id, envelope),
      dbCompleteGroupInboxStoreRetryFn: executor is Database
          ? (expected) => dbCompleteGroupInboxStoreRetry(executor, expected)
          : null,
      dbCompleteGroupContentInboxStoreRetryIfExactFn: executor is Database
          ? ({
              required expected,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required eventPayload,
            }) => dbCompleteGroupContentInboxStoreRetryIfExact(
              executor,
              expected: expected,
              sourcePeerId: sourcePeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: sourceTimestamp,
              eventPayload: eventPayload,
            )
          : null,
      dbStageAndCompleteLocalGroupContentMessageFn: executor is Database
          ? ({
              required expected,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required eventPayload,
            }) => dbStageAndCompleteLocalGroupContentMessage(
              executor,
              expected: expected,
              sourcePeerId: sourcePeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: sourceTimestamp,
              eventPayload: eventPayload,
            )
          : null,
      dbStagePreparedLocalGroupContentMessageFn: executor is Database
          ? ({
              required expected,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required preparedEventPayload,
            }) => dbStagePreparedLocalGroupContentMessage(
              executor,
              expected: expected,
              sourcePeerId: sourcePeerId,
              sourceEventId: sourceEventId,
              sourceTimestamp: sourceTimestamp,
              preparedEventPayload: preparedEventPayload,
            )
          : null,
      dbTerminalizePreparedLocalGroupContentMessageIfExactFn:
          executor is Database
          ? ({
              required expected,
              required preparedEventPayload,
              required terminalSourcePeerId,
              required terminalSourceEventId,
              required terminalSourceTimestamp,
              required terminalEventPayload,
            }) => dbTerminalizePreparedLocalGroupContentMessageIfExact(
              executor,
              expected: expected,
              preparedEventPayload: preparedEventPayload,
              terminalSourcePeerId: terminalSourcePeerId,
              terminalSourceEventId: terminalSourceEventId,
              terminalSourceTimestamp: terminalSourceTimestamp,
              terminalEventPayload: terminalEventPayload,
            )
          : null,
      dbHasExactPreparedLocalGroupContentMessageFn:
          ({required expected, required eventPayload}) =>
              dbHasExactPreparedLocalGroupContentMessage(
                executor,
                expected: expected,
                eventPayload: eventPayload,
              ),
      dbIsStrictGroupReactionTargetEligibleFn: (expected) =>
          dbIsStrictGroupReactionTargetEligible(executor, expected),
      dbReplaceGroupInboxRetryPayloadIfExactFn: executor is Database
          ? (expected, replacement) => dbReplaceGroupInboxRetryPayloadIfExact(
              executor,
              expected,
              replacement,
            )
          : null,
      dbRecordGroupMessageRetryFailureFn:
          (id, {required nextEligibleAtMs, required markTerminal}) =>
              dbRecordGroupMessageRetryFailure(
                executor,
                id,
                nextEligibleAtMs: nextEligibleAtMs,
                markTerminal: markTerminal,
              ),
      dbClearGroupMessageRetryBackoffFn: () =>
          dbClearGroupMessageRetryBackoff(executor),
      dbResetGroupMessageRetryStateFn: (id) =>
          dbResetGroupMessageRetryState(executor, id),
      dbLoadGroupInboxCursorFn: (groupId) async =>
          (await dbLoadGroupInboxCursor(executor, groupId))?['cursor']
              as String?,
      dbLoadGroupMessageReceiptsFn:
          (groupId, messageId, {String? receiptType}) =>
              dbLoadGroupMessageReceipts(
                executor,
                groupId: groupId,
                messageId: messageId,
                receiptType: receiptType,
              ),
      dbRunGroupInboxPageTransactionFn: transactional
          ? ({
              required groupId,
              required nextCursor,
              required apply,
              required receipts,
              required markReadMessageIds,
            }) => dbApplyGroupInboxPageTransaction(
              database,
              groupId: groupId,
              nextCursor: nextCursor,
              receiptRows: () =>
                  receipts.map((receipt) => receipt.toMap()).toList(),
              markReadMessageIds: () => markReadMessageIds,
              apply: (transactionExecutor) => apply(build(transactionExecutor)),
            )
          : null,
    );
  }

  return build(database, transactional: true);
}

DirectNotificationDisplayOutboxRepositoryImpl _buildDirectDisplayOutbox(
  Database database,
) => DirectNotificationDisplayOutboxRepositoryImpl(
  dbStage: (row) => dbStageDirectNotificationDisplayOutboxEntry(database, row),
  dbLoadExact: ({required peerId, required eventKind, required eventId}) =>
      dbLoadDirectNotificationDisplayOutboxEntry(
        database,
        peerId: peerId,
        eventKind: eventKind,
        eventId: eventId,
      ),
  dbPromoteReadyIfExact:
      ({
        required peerId,
        required eventKind,
        required eventId,
        required expectedRevision,
        required updatedAt,
      }) => dbPromoteDirectNotificationDisplayOutboxReadyIfExact(
        database,
        peerId: peerId,
        eventKind: eventKind,
        eventId: eventId,
        expectedRevision: expectedRevision,
        updatedAt: updatedAt,
      ),
  dbLoadReady: ({limit = 20, required eligibleAt}) =>
      dbLoadReadyDirectNotificationDisplayOutboxEntries(
        database,
        limit: limit,
        eligibleAt: eligibleAt,
      ),
  dbLoadEarliestNextAttemptAt: () =>
      dbLoadEarliestDirectNotificationDisplayOutboxNextAttemptAt(database),
  dbRecordRetryIfExact:
      ({
        required peerId,
        required eventKind,
        required eventId,
        required expectedRevision,
        required lastErrorCode,
        required lastAttemptAt,
        required nextAttemptAt,
        required updatedAt,
      }) => dbRecordDirectNotificationDisplayOutboxRetryIfExact(
        database,
        peerId: peerId,
        eventKind: eventKind,
        eventId: eventId,
        expectedRevision: expectedRevision,
        lastErrorCode: lastErrorCode,
        lastAttemptAt: lastAttemptAt,
        nextAttemptAt: nextAttemptAt,
        updatedAt: updatedAt,
      ),
  dbCompleteIfExact:
      ({
        required eventId,
        required expectedRevision,
        required expectedEventKind,
        required expectedPeerId,
        required expectedMessageId,
        required expectedActorPeerId,
        required expectedEventTimestamp,
        required expectedReactionId,
        required expectedReactionAction,
        required expectedReactionTombstone,
        required completedAt,
        outcome,
      }) => dbCompleteDirectNotificationDisplayOutboxEntryIfExact(
        database,
        eventId: eventId,
        expectedRevision: expectedRevision,
        expectedEventKind: expectedEventKind,
        expectedPeerId: expectedPeerId,
        expectedMessageId: expectedMessageId,
        expectedActorPeerId: expectedActorPeerId,
        expectedEventTimestamp: expectedEventTimestamp,
        expectedReactionId: expectedReactionId,
        expectedReactionAction: expectedReactionAction,
        expectedReactionTombstone: expectedReactionTombstone,
        completedAt: completedAt,
        outcome: outcome,
      ),
  dbRetireAfterDurableSettlementIfExact:
      ({
        required eventId,
        required expectedRevision,
        required expectedEventKind,
        required expectedPeerId,
        required expectedMessageId,
        required expectedActorPeerId,
        required expectedEventTimestamp,
        required expectedReactionId,
        required expectedReactionAction,
        required expectedReactionTombstone,
      }) =>
          dbRetireDirectNotificationDisplayOutboxAfterDurableSettlementIfExact(
            database,
            eventId: eventId,
            expectedRevision: expectedRevision,
            expectedEventKind: expectedEventKind,
            expectedPeerId: expectedPeerId,
            expectedMessageId: expectedMessageId,
            expectedActorPeerId: expectedActorPeerId,
            expectedEventTimestamp: expectedEventTimestamp,
            expectedReactionId: expectedReactionId,
            expectedReactionAction: expectedReactionAction,
            expectedReactionTombstone: expectedReactionTombstone,
          ),
  dbRetireIfExact:
      ({
        required eventId,
        required expectedRevision,
        required expectedEventKind,
        required expectedPeerId,
        required expectedMessageId,
        required expectedActorPeerId,
        required expectedEventTimestamp,
        required expectedReactionId,
        required expectedReactionAction,
        required expectedReactionTombstone,
      }) => dbRetireDirectNotificationDisplayOutboxEntryIfExact(
        database,
        eventId: eventId,
        expectedRevision: expectedRevision,
        expectedEventKind: expectedEventKind,
        expectedPeerId: expectedPeerId,
        expectedMessageId: expectedMessageId,
        expectedActorPeerId: expectedActorPeerId,
        expectedEventTimestamp: expectedEventTimestamp,
        expectedReactionId: expectedReactionId,
        expectedReactionAction: expectedReactionAction,
        expectedReactionTombstone: expectedReactionTombstone,
      ),
  dbDeleteForPeer: (peerId) =>
      dbDeleteDirectNotificationDisplayOutboxForPeer(database, peerId),
  dbDeleteForMessage: ({required peerId, required messageId}) =>
      dbDeleteDirectNotificationDisplayOutboxForMessage(
        database,
        peerId: peerId,
        messageId: messageId,
      ),
  dbDeleteForReactionActor:
      ({required peerId, required messageId, required actorPeerId}) =>
          dbDeleteDirectNotificationDisplayOutboxForReactionActor(
            database,
            peerId: peerId,
            messageId: messageId,
            actorPeerId: actorPeerId,
          ),
);

DirectNotificationReadAcknowledgementRepositoryImpl
_buildDirectReadAcknowledgement(Database database) =>
    DirectNotificationReadAcknowledgementRepositoryImpl(
      dbRecord:
          ({
            required peerId,
            required contentKind,
            required eventIdentity,
            required messageId,
            required actorPeerId,
            required generation,
            required acknowledgedAt,
          }) => dbRecordDirectNotificationReadAcknowledgement(
            database,
            peerId: peerId,
            contentKind: contentKind,
            eventIdentity: eventIdentity,
            messageId: messageId,
            actorPeerId: actorPeerId,
            generation: generation,
            acknowledgedAt: acknowledgedAt,
          ),
      dbLoadExact:
          ({
            required peerId,
            required contentKind,
            required eventIdentity,
            generation,
          }) => dbLoadExactDirectNotificationReadAcknowledgement(
            database,
            peerId: peerId,
            contentKind: contentKind,
            eventIdentity: eventIdentity,
            generation: generation,
          ),
      dbConsumeExact:
          ({required peerId, required contentKind, required eventIdentity}) =>
              dbConsumeExactDirectNotificationReadAcknowledgement(
                database,
                peerId: peerId,
                contentKind: contentKind,
                eventIdentity: eventIdentity,
              ),
      dbDeleteForPeer: (peerId) =>
          dbDeleteDirectNotificationReadAcknowledgementsForPeer(
            database,
            peerId,
          ),
    );

DirectNotificationReactionTerminalRepositoryImpl _buildDirectReactionTerminal(
  Database database,
) => DirectNotificationReactionTerminalRepositoryImpl(
  dbUpsert:
      ({
        required peerId,
        required messageId,
        required actorPeerId,
        required reactionId,
        required terminalEventId,
        required updatedAt,
      }) => dbUpsertDirectNotificationReactionTerminalEvent(
        database,
        peerId: peerId,
        messageId: messageId,
        actorPeerId: actorPeerId,
        reactionId: reactionId,
        terminalEventId: terminalEventId,
        updatedAt: updatedAt,
      ),
  dbLoadExact: ({required peerId, required messageId, required actorPeerId}) =>
      dbLoadDirectNotificationReactionTerminalEvent(
        database,
        peerId: peerId,
        messageId: messageId,
        actorPeerId: actorPeerId,
      ),
  dbLoadByTerminalEvent: ({required peerId, required terminalEventId}) =>
      dbLoadDirectNotificationReactionTerminalEventByIdentity(
        database,
        peerId: peerId,
        terminalEventId: terminalEventId,
      ),
  dbMarkAcknowledgedIfExact:
      ({
        required peerId,
        required messageId,
        required actorPeerId,
        required terminalEventId,
        required acknowledgedAt,
      }) => dbMarkDirectNotificationReactionTerminalAcknowledgedIfExact(
        database,
        peerId: peerId,
        messageId: messageId,
        actorPeerId: actorPeerId,
        terminalEventId: terminalEventId,
        acknowledgedAt: acknowledgedAt,
      ),
  dbConsumeAcknowledgementIfExact:
      ({
        required peerId,
        required messageId,
        required actorPeerId,
        required terminalEventId,
        required generation,
      }) =>
          dbConsumeDirectNotificationReactionAcknowledgementIntoTerminalIfExact(
            database,
            peerId: peerId,
            messageId: messageId,
            actorPeerId: actorPeerId,
            terminalEventId: terminalEventId,
            generation: generation,
          ),
  dbDeleteForActor:
      ({required peerId, required messageId, required actorPeerId}) =>
          dbDeleteDirectNotificationReactionTerminalForActor(
            database,
            peerId: peerId,
            messageId: messageId,
            actorPeerId: actorPeerId,
          ),
  dbDeleteForMessage: ({required peerId, required messageId}) =>
      dbDeleteDirectNotificationReactionTerminalsForMessage(
        database,
        peerId: peerId,
        messageId: messageId,
      ),
  dbDeleteForPeer: (peerId) =>
      dbDeleteDirectNotificationReactionTerminalsForPeer(database, peerId),
);

DirectNotificationReconciliationOutboxRepositoryImpl
_buildDirectReconciliationOutbox(Database database) =>
    DirectNotificationReconciliationOutboxRepositoryImpl(
      dbLoadEligible: ({limit = 20, required eligibleAt}) =>
          dbLoadEligibleDirectNotificationReconciliationOutboxEntries(
            database,
            limit: limit,
            eligibleAt: eligibleAt,
          ),
      dbLoadEarliestNextAttemptAt: () =>
          dbLoadEarliestDirectNotificationReconciliationOutboxNextAttemptAt(
            database,
          ),
      dbRecordFailureIfExact:
          ({
            required peerId,
            required expectedIncarnationId,
            required expectedRevision,
            required lastAttemptAt,
            required nextAttemptAt,
            required updatedAt,
          }) => dbRecordDirectNotificationReconciliationOutboxFailureIfExact(
            database,
            peerId: peerId,
            expectedIncarnationId: expectedIncarnationId,
            expectedRevision: expectedRevision,
            lastAttemptAt: lastAttemptAt,
            nextAttemptAt: nextAttemptAt,
            updatedAt: updatedAt,
          ),
      dbCompleteIfExact:
          ({
            required peerId,
            required expectedIncarnationId,
            required expectedRevision,
          }) => dbCompleteDirectNotificationReconciliationOutboxIfExact(
            database,
            peerId: peerId,
            expectedIncarnationId: expectedIncarnationId,
            expectedRevision: expectedRevision,
          ),
    );

GroupNotificationDisplayOutboxRepositoryImpl _buildGroupDisplayOutbox(
  Database database,
) => GroupNotificationDisplayOutboxRepositoryImpl(
  dbStage: (row) => dbStageGroupNotificationDisplayOutboxEntry(database, row),
  dbLoadByEventId: (eventId) =>
      dbLoadGroupNotificationDisplayOutboxEntry(database, eventId),
  dbBindDurableCorrelationIfExact:
      ({
        required eventId,
        required expectedRevision,
        required expectedEventKind,
        required expectedGroupId,
        required expectedMessageId,
        required expectedActorPeerId,
        required expectedEventTimestamp,
        required expectedReactionId,
        required expectedReactionAction,
        required expectedReactionTombstone,
        required durableEventCorrelation,
        required updatedAt,
      }) => dbBindGroupNotificationDisplayOutboxDurableCorrelationIfExact(
        database,
        eventId: eventId,
        expectedRevision: expectedRevision,
        expectedEventKind: expectedEventKind,
        expectedGroupId: expectedGroupId,
        expectedMessageId: expectedMessageId,
        expectedActorPeerId: expectedActorPeerId,
        expectedEventTimestamp: expectedEventTimestamp,
        expectedReactionId: expectedReactionId,
        expectedReactionAction: expectedReactionAction,
        expectedReactionTombstone: expectedReactionTombstone,
        durableEventCorrelation: durableEventCorrelation,
        updatedAt: updatedAt,
      ),
  dbPromoteReadyIfExact:
      ({required eventId, required expectedRevision, required updatedAt}) =>
          dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
            database,
            eventId: eventId,
            expectedRevision: expectedRevision,
            updatedAt: updatedAt,
          ),
  dbLoadReady: ({limit = 20, required eligibleAt}) =>
      dbLoadReadyGroupNotificationDisplayOutboxEntries(
        database,
        limit: limit,
        eligibleAt: eligibleAt,
      ),
  dbLoadEarliestNextAttemptAt: () =>
      dbLoadEarliestGroupNotificationDisplayOutboxNextAttemptAt(database),
  dbRecordRetryIfExact:
      ({
        required eventId,
        required expectedRevision,
        required lastErrorCode,
        required lastAttemptAt,
        required nextAttemptAt,
        required updatedAt,
      }) => dbRecordGroupNotificationDisplayOutboxRetryIfExact(
        database,
        eventId: eventId,
        expectedRevision: expectedRevision,
        lastErrorCode: lastErrorCode,
        lastAttemptAt: lastAttemptAt,
        nextAttemptAt: nextAttemptAt,
        updatedAt: updatedAt,
      ),
  dbCompleteIfExact:
      ({
        required eventId,
        required expectedRevision,
        required expectedEventKind,
        required expectedGroupId,
        required expectedMessageId,
        required expectedActorPeerId,
        required expectedEventTimestamp,
        required expectedReactionId,
        required expectedReactionAction,
        required expectedReactionTombstone,
        required completedAt,
        outcome,
      }) => dbCompleteGroupNotificationDisplayOutboxEntryIfExact(
        database,
        eventId: eventId,
        expectedRevision: expectedRevision,
        expectedEventKind: expectedEventKind,
        expectedGroupId: expectedGroupId,
        expectedMessageId: expectedMessageId,
        expectedActorPeerId: expectedActorPeerId,
        expectedEventTimestamp: expectedEventTimestamp,
        expectedReactionId: expectedReactionId,
        expectedReactionAction: expectedReactionAction,
        expectedReactionTombstone: expectedReactionTombstone,
        completedAt: completedAt,
        outcome: outcome,
      ),
  dbCompleteOrVerifyIfExact:
      ({
        required eventId,
        required expectedRevision,
        required expectedEventKind,
        required expectedGroupId,
        required expectedMessageId,
        required expectedActorPeerId,
        required expectedEventTimestamp,
        required expectedReactionId,
        required expectedReactionAction,
        required expectedReactionTombstone,
        required completedAt,
        outcome,
        durableEventCorrelation,
      }) => dbCompleteOrVerifyGroupNotificationDisplayOutboxEntryIfExact(
        database,
        eventId: eventId,
        expectedRevision: expectedRevision,
        expectedEventKind: expectedEventKind,
        expectedGroupId: expectedGroupId,
        expectedMessageId: expectedMessageId,
        expectedActorPeerId: expectedActorPeerId,
        expectedEventTimestamp: expectedEventTimestamp,
        expectedReactionId: expectedReactionId,
        expectedReactionAction: expectedReactionAction,
        expectedReactionTombstone: expectedReactionTombstone,
        completedAt: completedAt,
        outcome: outcome,
        durableEventCorrelation: durableEventCorrelation,
      ),
  dbRetireAfterDurableSettlementIfExact:
      ({
        required eventId,
        required expectedRevision,
        required expectedEventKind,
        required expectedGroupId,
        required expectedMessageId,
        required expectedActorPeerId,
        required expectedEventTimestamp,
        required expectedReactionId,
        required expectedReactionAction,
        required expectedReactionTombstone,
        durableEventCorrelation,
      }) => dbRetireGroupNotificationDisplayOutboxAfterDurableSettlementIfExact(
        database,
        eventId: eventId,
        expectedRevision: expectedRevision,
        expectedEventKind: expectedEventKind,
        expectedGroupId: expectedGroupId,
        expectedMessageId: expectedMessageId,
        expectedActorPeerId: expectedActorPeerId,
        expectedEventTimestamp: expectedEventTimestamp,
        expectedReactionId: expectedReactionId,
        expectedReactionAction: expectedReactionAction,
        expectedReactionTombstone: expectedReactionTombstone,
        durableEventCorrelation: durableEventCorrelation,
      ),
  dbRetireIfExact:
      ({
        required eventId,
        required expectedRevision,
        required expectedEventKind,
        required expectedGroupId,
        required expectedMessageId,
        required expectedActorPeerId,
        required expectedEventTimestamp,
        required expectedReactionId,
        required expectedReactionAction,
        required expectedReactionTombstone,
      }) => dbRetireGroupNotificationDisplayOutboxEntryIfExact(
        database,
        eventId: eventId,
        expectedRevision: expectedRevision,
        expectedEventKind: expectedEventKind,
        expectedGroupId: expectedGroupId,
        expectedMessageId: expectedMessageId,
        expectedActorPeerId: expectedActorPeerId,
        expectedEventTimestamp: expectedEventTimestamp,
        expectedReactionId: expectedReactionId,
        expectedReactionAction: expectedReactionAction,
        expectedReactionTombstone: expectedReactionTombstone,
      ),
  dbReconcileMessageAliasReady:
      ({
        required aliasEventId,
        required canonicalEventId,
        required groupId,
        required actorPeerId,
        required eventTimestamp,
        required updatedAt,
      }) => dbReconcileGroupNotificationDisplayOutboxMessageAliasReady(
        database,
        aliasEventId: aliasEventId,
        canonicalEventId: canonicalEventId,
        groupId: groupId,
        actorPeerId: actorPeerId,
        eventTimestamp: eventTimestamp,
        updatedAt: updatedAt,
      ),
  dbDeleteForGroup: (groupId) =>
      dbDeleteGroupNotificationDisplayOutboxForGroup(database, groupId),
  dbDeleteForMessage: ({required groupId, required messageId}) =>
      dbDeleteGroupNotificationDisplayOutboxForMessage(
        database,
        groupId: groupId,
        messageId: messageId,
      ),
  dbDeleteForReaction:
      ({required groupId, required messageId, required reactionId}) =>
          dbDeleteGroupNotificationDisplayOutboxForReaction(
            database,
            groupId: groupId,
            messageId: messageId,
            reactionId: reactionId,
          ),
  dbDeleteForReactionActor:
      ({required groupId, required messageId, required actorPeerId}) =>
          dbDeleteGroupNotificationDisplayOutboxForReactionActor(
            database,
            groupId: groupId,
            messageId: messageId,
            actorPeerId: actorPeerId,
          ),
);

GroupNotificationReconciliationOutboxRepositoryImpl
_buildGroupReconciliationOutbox(Database database) =>
    GroupNotificationReconciliationOutboxRepositoryImpl(
      dbLoadEligible: ({limit = 20, required eligibleAt}) =>
          dbLoadEligibleGroupNotificationReconciliationOutboxEntries(
            database,
            limit: limit,
            eligibleAt: eligibleAt,
          ),
      dbLoadEarliestNextAttemptAt: () =>
          dbLoadEarliestGroupNotificationReconciliationOutboxNextAttemptAt(
            database,
          ),
      dbRecordFailureIfExact:
          ({
            required groupId,
            required expectedIncarnationId,
            required expectedRevision,
            required lastAttemptAt,
            required nextAttemptAt,
            required updatedAt,
          }) => dbRecordGroupNotificationReconciliationOutboxFailureIfExact(
            database,
            groupId: groupId,
            expectedIncarnationId: expectedIncarnationId,
            expectedRevision: expectedRevision,
            lastAttemptAt: lastAttemptAt,
            nextAttemptAt: nextAttemptAt,
            updatedAt: updatedAt,
          ),
      dbCompleteIfExact:
          ({
            required groupId,
            required expectedIncarnationId,
            required expectedRevision,
          }) => dbCompleteGroupNotificationReconciliationOutboxIfExact(
            database,
            groupId: groupId,
            expectedIncarnationId: expectedIncarnationId,
            expectedRevision: expectedRevision,
          ),
    );
