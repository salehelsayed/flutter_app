import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart' show XFile;
import 'package:flutter_app/features/update_check/application/update_check_controller.dart';
import '../features/update_check/support/fake_update_check_service.dart';
import 'package:flutter_app/app/application_root.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_presentation_gate.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/message_deletion_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_repair_responder_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_backoff_timer.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/data/repositories/group_history_gap_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_invite_delivery_attempt_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_key_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_reaction_replay_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_reaction_repository.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/data/repositories/intro_review_seen_repository_impl.dart';
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_media_upload_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/application/post_comment_listener.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/application/post_pin_listener.dart';
import 'package:flutter_app/features/posts/application/post_presence_listener.dart';
import 'package:flutter_app/features/posts/application/post_reaction_listener.dart';
import 'package:flutter_app/features/posts/data/repositories/contact_presence_snapshot_repository_impl.dart';
import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/data/repositories/posts_privacy_settings_repository_impl.dart';
import 'package:flutter_app/features/settings/application/profile_update_listener.dart';

import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_history_gap_repair.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import '../core/bridge/fake_bridge.dart';
import '../core/secure_storage/fake_secure_key_store.dart';
import '../core/services/fake_p2p_service.dart';
import '../features/identity/domain/repositories/fake_identity_repository.dart';
import '../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../shared/fakes/in_memory_group_repository.dart';
import '../shared/fakes/in_memory_group_message_repository.dart';
import '../shared/fakes/in_memory_message_repository.dart';
import '../shared/fakes/in_memory_media_attachment_repository.dart';
import '../shared/fakes/in_memory_pending_group_invite_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';
import '../shared/fakes/fake_media_file_manager.dart';

void main() {
  test('production processor reads the one persisted quality source', () {
    final source = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final start = source.indexOf('final imageProcessor = ImageProcessor(');
    final end = source.indexOf('// Create audio recorder service', start);
    expect(start, greaterThanOrEqualTo(0));
    final wiring = source.substring(start, end);
    expect(
      wiring,
      contains('loadImageQualityPreference(secureKeyStore: secureKeyStore)'),
    );
    expect(
      wiring,
      contains('loadVideoQualityPreference(secureKeyStore: secureKeyStore)'),
    );
  });

  for (final isGroup in [false, true]) {
    testWidgets(
      'notification-root ${isGroup ? 'group' : 'direct'} photo preparation honours stored quality',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 1700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final notifications = _Notifications();
        final identity = _QualityIdentity()
          ..seed(FakeIdentityRepository.makeIdentity(peerId: 'self'));
        final contacts = _QualityContacts()
          ..seed([
            const ContactModel(
              peerId: 'peer-photo',
              publicKey: 'pk',
              rendezvous: '',
              username: 'Photo contact',
              signature: '',
              scannedAt: '2026-10-22',
            ),
          ]);
        final groups = _QualityGroups();
        await groups.saveGroup(
          GroupModel(
            id: 'group-photo',
            name: 'Photo group',
            type: GroupType.chat,
            topicName: 'photo-topic',
            createdAt: DateTime.utc(2026),
            createdBy: 'self',
            myRole: GroupRole.admin,
          ),
        );
        await groups.saveMember(
          GroupMember(
            groupId: 'group-photo',
            peerId: 'self',
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026),
          ),
        );
        final messages = _QualityMessages();
        final bridge = FakeBridge();
        final p2p = _QualityP2P();
        final chat = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messages,
          contactRepo: contacts,
          bridge: bridge,
        );
        final store = FakeSecureKeyStore();
        await saveImageQualityPreference(
          secureKeyStore: store,
          preference: ImageQualityPreference.original,
        );
        final requested = <int>[];
        final processor = ImageProcessor(
          loadImageQualityPreference: () =>
              loadImageQualityPreference(secureKeyStore: store),
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                requested.add(quality);
                return XFile(path);
              },
        );
        final updates = UpdateCheckController(
          service: FakeUpdateCheckService(),
        );
        addTearDown(updates.dispose);
        await tester.pumpWidget(
          MyApp(
            repository: identity,
            contactRepository: contacts,
            contactRequestRepository: _ContactRequestRepositoryImpl(),
            contactRequestListener: _ContactRequestListener(),
            contactRequestPresentationGate: ContactRequestPresentationGate(),
            messageRepository: messages,
            postRepository: _PostRepositoryImpl(),
            postsPrivacySettingsRepository:
                _PostsPrivacySettingsRepositoryImpl(),
            feedClearedRepository: _FeedClearedRepository(),
            contactPresenceSnapshotRepository:
                _ContactPresenceSnapshotRepositoryImpl(),
            nearbyLocationService: _NearbyLocationService(),
            mediaAttachmentRepository: _QualityMedia(),
            groupMediaDeleteForMeCoordinator:
                _GroupMediaDeleteForMeCoordinator(),
            groupMediaDeletionCleanup: () async {},
            chatMessageListener: chat,
            postListener: _PostListener(),
            postCommentListener: _PostCommentListener(),
            postReactionListener: _PostReactionListener(),
            postPresenceListener: _PostPresenceListener(),
            postPassListener: _PostPassListener(),
            postPinListener: _PostPinListener(),
            reactionListener: _ReactionListener(),
            messageDeletionListener: _MessageDeletionListener(),
            profileUpdateListener: _ProfileUpdateListener(),
            messageRouter: _IncomingMessageRouter(),
            pendingMessageRetrier: _PendingMessageRetrier(),
            pendingPostMediaUploadRetrier: _PendingPostMediaUploadRetrier(),
            pendingPostDeliveryRetrier: _PendingPostDeliveryRetrier(),
            pendingPostFollowOnRetrier: _PendingPostFollowOnRetrier(),
            keyExchangeRetrier: _KeyExchangeRetrier(),
            bridge: bridge,
            p2pService: p2p,
            mediaFileManager: FakeMediaFileManager(),
            secureKeyStore: store,
            imageProcessor: processor,
            audioRecorderService: _AudioRecorderService(),
            reactionRepository: _ReactionRepositoryImpl(),
            isDesktop: false,
            notificationService: notifications,
            appShellController: AppShellController(),
            pendingPostTargetStore: PendingPostTargetStore(),
            conversationTracker: ActiveConversationTracker(),
            groupRepository: groups,
            groupMessageRepository: _QualityGroupMessages(),
            groupInviteDeliveryAttemptRepository:
                _GroupInviteDeliveryAttemptRepositoryImpl(),
            groupPendingKeyRepairRepository:
                _GroupPendingKeyRepairRepositoryImpl(),
            groupPendingReactionRepository: _GroupPendingReactionRepository(),
            groupPendingKeyRepairRunner: _GroupPendingKeyRepairRunner(),
            groupPendingKeyRepairBackoffTimer:
                _GroupPendingKeyRepairBackoffTimer(),
            groupPendingKeyDistributionRunner:
                _GroupPendingKeyDistributionRunner(),
            groupHistoryGapRepairRepository:
                _GroupHistoryGapRepairRepositoryImpl(),
            groupReactionReplayOutboxRepository:
                _GroupReactionReplayOutboxRepositoryImpl(),
            groupMessageListener: _GroupMessageListener(),
            groupInviteListener: _GroupInviteListener(),
            groupKeyUpdateListener: _GroupKeyUpdateListener(),
            groupKeyRepairResponderListener: _GroupKeyRepairResponderListener(),
            requestGroupKeyRepair: (_) async {},
            groupMembershipUpdateListener: _GroupMembershipUpdateListener(),
            groupConversationTracker: ActiveConversationTracker(),
            introductionRepository: _IntroductionRepositoryImpl(),
            introReviewSeenRepository: _IntroReviewSeenRepositoryImpl(),
            introductionListener: _IntroductionListener(),
            shareIntentService: _Shares(),
            updateCheckController: updates,
          ),
        );

        try {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          final startup = tester.widget<StartupRouter>(
            find.byType(StartupRouter),
          );
          startup.onStartupHomeReady!();
          notifications.onNotificationTap!(
            isGroup ? 'group:group-photo' : 'peer-photo',
          );
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (isGroup) {
            final route = tester.widget<GroupConversationWired>(
              find.byType(GroupConversationWired),
            );
            expect(route.imageProcessor, same(processor));
            await tester.runAsync(
              () => route.imageProcessor!.processImage(
                inputPath: '/tmp/notification.png',
                quality: route.qualityPreference,
              ),
            );
          } else {
            final route = tester.widget<ConversationWired>(
              find.byType(ConversationWired),
            );
            expect(route.imageProcessor, same(processor));
            await tester.runAsync(
              () => route.imageProcessor!.processImage(
                inputPath: '/tmp/notification.png',
                quality: route.qualityPreference,
              ),
            );
          }
          expect(requested, [100]);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 10));
        }
      },
    );
  }
}

class _Unused {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter &&
        invocation.memberName.toString().contains('Stream')) {
      return const Stream<Never>.empty();
    }
    return null;
  }
}

class _Notifications extends _Unused implements NotificationService {
  @override
  void Function(String)? onNotificationTap;
  @override
  Future<String?> consumeInitialPayload() async => null;
}

class _Shares extends _Unused implements ShareIntentService {
  @override
  bool get hasPendingIntent => false;
  @override
  Stream<ShareIntent> get intentStream => const Stream.empty();
  @override
  Future<ShareIntent?> captureInitialIntent() =>
      Completer<ShareIntent?>().future;
}

class _AudioRecorderService extends _Unused implements AudioRecorderService {
  @override
  Future<void> dispose() async {}
}

class _ContactPresenceSnapshotRepositoryImpl extends _Unused
    implements ContactPresenceSnapshotRepositoryImpl {}

class _ContactRequestListener extends _Unused
    implements ContactRequestListener {}

class _ContactRequestRepositoryImpl extends _Unused
    implements ContactRequestRepositoryImpl {}

class _FeedClearedRepository extends _Unused implements FeedClearedRepository {}

class _GroupHistoryGapRepairRepositoryImpl extends _Unused
    implements GroupHistoryGapRepairRepositoryImpl {
  @override
  Future<GroupHistoryGapRepair?> getLatestRepairForGroup(
    String groupId,
  ) async => null;
}

class _GroupInviteDeliveryAttemptRepositoryImpl extends _Unused
    implements GroupInviteDeliveryAttemptRepositoryImpl {}

class _GroupInviteListener extends _Unused implements GroupInviteListener {
  @override
  final PendingGroupInviteRepository pendingInviteRepo =
      InMemoryPendingGroupInviteRepository();
}

class _GroupKeyRepairResponderListener extends _Unused
    implements GroupKeyRepairResponderListener {}

class _GroupKeyUpdateListener extends _Unused
    implements GroupKeyUpdateListener {}

class _GroupMediaDeleteForMeCoordinator extends _Unused
    implements GroupMediaDeleteForMeCoordinator {}

class _GroupMembershipUpdateListener extends _Unused
    implements GroupMembershipUpdateListener {}

class _GroupMessageListener extends _Unused implements GroupMessageListener {
  @override
  Future<void> endCanonicalNotificationRecovery({
    required bool canonicalStateComplete,
    bool releaseStartupHold = false,
  }) async {}

  @override
  Future<void> flushPendingMembershipDependentMessagesForGroup(
    String groupId, {
    dynamic msgRepoOverride,
  }) async {}
}

class _GroupPendingKeyDistributionRunner extends _Unused
    implements GroupPendingKeyDistributionRunner {}

class _GroupPendingKeyRepairBackoffTimer extends _Unused
    implements GroupPendingKeyRepairBackoffTimer {}

class _GroupPendingKeyRepairRepositoryImpl extends _Unused
    implements GroupPendingKeyRepairRepositoryImpl {}

class _GroupPendingKeyRepairRunner extends _Unused
    implements GroupPendingKeyRepairRunner {}

class _GroupPendingReactionRepository extends _Unused
    implements GroupPendingReactionRepository {}

class _GroupReactionReplayOutboxRepositoryImpl extends _Unused
    implements GroupReactionReplayOutboxRepositoryImpl {}

class _IncomingMessageRouter extends _Unused implements IncomingMessageRouter {}

class _IntroReviewSeenRepositoryImpl extends _Unused
    implements IntroReviewSeenRepositoryImpl {}

class _IntroductionListener extends _Unused implements IntroductionListener {}

class _IntroductionRepositoryImpl extends _Unused
    implements IntroductionRepositoryImpl {}

class _KeyExchangeRetrier extends _Unused implements KeyExchangeRetrier {}

class _MessageDeletionListener extends _Unused
    implements MessageDeletionListener {}

class _NearbyLocationService extends _Unused implements NearbyLocationService {}

class _PendingMessageRetrier extends _Unused implements PendingMessageRetrier {}

class _PendingPostDeliveryRetrier extends _Unused
    implements PendingPostDeliveryRetrier {}

class _PendingPostFollowOnRetrier extends _Unused
    implements PendingPostFollowOnRetrier {}

class _PendingPostMediaUploadRetrier extends _Unused
    implements PendingPostMediaUploadRetrier {}

class _PostCommentListener extends _Unused implements PostCommentListener {}

class _PostListener extends _Unused implements PostListener {}

class _PostPassListener extends _Unused implements PostPassListener {}

class _PostPinListener extends _Unused implements PostPinListener {}

class _PostPresenceListener extends _Unused implements PostPresenceListener {}

class _PostReactionListener extends _Unused implements PostReactionListener {}

class _PostRepositoryImpl extends _Unused implements PostRepositoryImpl {
  @override
  Stream<String> get postChanges => const Stream.empty();
}

class _PostsPrivacySettingsRepositoryImpl extends _Unused
    implements PostsPrivacySettingsRepositoryImpl {}

class _ProfileUpdateListener extends _Unused implements ProfileUpdateListener {}

class _ReactionListener extends _Unused implements ReactionListener {}

class _ReactionRepositoryImpl extends _Unused
    implements ReactionRepositoryImpl {}

class _QualityIdentity extends FakeIdentityRepository
    implements IdentityRepositoryImpl {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QualityContacts extends FakeContactRepository
    implements ContactRepositoryImpl {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QualityGroups extends InMemoryGroupRepository
    implements GroupRepositoryImpl {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QualityGroupMessages extends InMemoryGroupMessageRepository
    implements GroupMessageRepositoryImpl {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QualityMessages extends InMemoryMessageRepository
    implements MessageRepositoryImpl {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QualityMedia extends InMemoryMediaAttachmentRepository
    implements MediaAttachmentRepositoryImpl {
  @override
  final directPrivateMediaLifecycleLock = MediaAttachmentLifecycleLock();
  @override
  final groupPrivateMediaLifecycleLock = MediaAttachmentLifecycleLock();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QualityP2P extends FakeP2PService implements P2PServiceImpl {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
