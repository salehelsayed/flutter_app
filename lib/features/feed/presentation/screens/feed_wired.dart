import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/load_reactions_use_case.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/remove_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/feed/application/feed_reaction_store.dart';
import 'package:flutter_app/features/feed/application/feed_store.dart';
import 'package:flutter_app/features/feed/application/load_contact_feed_snapshot_use_case.dart';
import 'package:flutter_app/features/feed/application/load_feed_use_case.dart';
import 'package:flutter_app/features/feed/application/load_group_feed_snapshot_use_case.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/home/application/identity_avatar_resolver.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/orbit/presentation/navigation/orbit_route_transition.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/settings/presentation/navigation/settings_route_transition.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';
import 'feed_screen.dart';

enum _MediaSource { gallery, camera, videoCamera }

const _uuid = Uuid();

/// Wired widget that connects FeedScreen to business logic.
///
/// Follows the same "Wired" pattern as FirstTimeExperienceWired.
/// Loads identity, builds feed items from the initial contact,
/// and listens for new incoming contact requests.
class FeedWired extends StatefulWidget {
  final IdentityRepository repository;
  final ContactRepository contactRepository;
  final ContactRequestRepository contactRequestRepository;
  final ContactRequestListener contactRequestListener;
  final MessageRepository messageRepository;
  final PostRepository postRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final ChatMessageListener chatMessageListener;
  final Bridge bridge;
  final P2PService p2pService;
  final MediaFileManager mediaFileManager;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;
  final ActiveConversationTracker? conversationTracker;
  final AudioRecorderService? audioRecorderService;
  final ReactionRepository? reactionRepository;
  final ReactionListener? reactionListener;
  final GroupRepository? groupRepository;
  final GroupMessageRepository? groupMessageRepository;
  final GroupMessageListener? groupMessageListener;
  final GroupInviteListener? groupInviteListener;
  final ActiveConversationTracker? groupConversationTracker;
  final IntroductionRepository? introductionRepository;
  final IntroductionListener? introductionListener;
  final AppShellController appShellController;
  final PendingPostTargetStore pendingPostTargetStore;
  final PostsPrivacySettingsRepository postsPrivacySettingsRepository;
  final ContactPresenceSnapshotRepository? contactPresenceSnapshotRepository;
  final NearbyLocationService? nearbyLocationService;

  const FeedWired({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.messageRepository,
    required this.postRepository,
    required this.mediaAttachmentRepository,
    required this.chatMessageListener,
    required this.bridge,
    required this.p2pService,
    required this.mediaFileManager,
    required this.secureKeyStore,
    required this.imageProcessor,
    this.conversationTracker,
    this.audioRecorderService,
    this.reactionRepository,
    this.reactionListener,
    this.groupRepository,
    this.groupMessageRepository,
    this.groupMessageListener,
    this.groupInviteListener,
    this.groupConversationTracker,
    this.introductionRepository,
    this.introductionListener,
    required this.appShellController,
    required this.pendingPostTargetStore,
    required this.postsPrivacySettingsRepository,
    this.contactPresenceSnapshotRepository,
    this.nearbyLocationService,
  });

  @override
  State<FeedWired> createState() => _FeedWiredState();
}

class _FeedWiredState extends State<FeedWired> {
  String _username = 'Username';
  Uint8List? _avatarBytes;
  String? _peerId;
  IdentityModel? _identity;
  final FeedStore _feedStore = FeedStore();
  final ValueNotifier<int> _totalUnreadCountNotifier = ValueNotifier<int>(0);
  final FeedReactionStore _reactionStore = FeedReactionStore();
  bool _feedLoaded = false;
  String? _expandedCardId;
  final Map<String, String> _draftTexts = {};
  final Map<String, String> _activeQuoteMessageIds = {};
  final SessionReplyTracker _sessionReplies = SessionReplyTracker();
  String? _activeFocusPeerId;
  StreamSubscription<ContactRequestModel>? _requestSubscription;
  StreamSubscription<ConversationMessage>? _chatSubscription;
  StreamSubscription<ConversationMessage>? _repoChangeSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;
  StreamSubscription<ReactionChange>? _reactionSubscription;
  StreamSubscription<dynamic>? _groupMessageSubscription;
  StreamSubscription<ReactionChange>? _groupReactionSubscription;
  StreamSubscription<IntroductionModel>? _introReceivedSubscription;
  StreamSubscription<IntroductionModel>? _introStatusSubscription;
  ImageQualityPreference _qualityPreference = ImageQualityPreference.compressed;
  ImageQualityPreference _videoQualityPreference =
      ImageQualityPreference.compressed;
  bool _orbitRouteOpen = false;
  String _orbitReturnTab = AppShellTab.feed;

  List<FeedItem> get _feedItems => _feedStore.items;
  String _groupQuoteKey(String groupId) => 'group:$groupId';

  void _restoreFeedComposerState({
    required String draftKey,
    required String? quotedMessageId,
    required String draftText,
    required String sessionReplyKey,
  }) {
    _sessionReplies.clear(sessionReplyKey);
    if (draftText.isEmpty) {
      _draftTexts.remove(draftKey);
    } else {
      _draftTexts[draftKey] = draftText;
    }
    if (quotedMessageId == null || quotedMessageId.isEmpty) {
      _activeQuoteMessageIds.remove(draftKey);
    } else {
      _activeQuoteMessageIds[draftKey] = quotedMessageId;
    }
    if (mounted) setState(() {});
  }

  void _markFeedLoaded() {
    if (_feedLoaded || !mounted) return;
    setState(() => _feedLoaded = true);
  }

  @override
  void initState() {
    super.initState();
    widget.appShellController.addListener(_onShellChanged);
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_FL_SCREEN_INIT',
      details: {'introRepoNull': widget.introductionRepository == null},
    );
    _loadIdentity();
    _loadQualityPreference();
    _loadVideoQualityPreference();
    _loadFeedFromDatabase();
    _loadTotalUnreadCount();
    _startListeningForContactRequests();
    _startListeningForChatMessages();
    _startListeningForOutgoingMessageChanges();
    _startListeningForContactUpdates();
    _startListeningForReactions();
    _startListeningForGroupReactions();
    _startListeningForGroupMessages();
    _startListeningForIntroductions();
  }

  Future<void> _loadIdentity() async {
    try {
      final identity = await widget.repository.loadIdentity();
      if (identity == null || !mounted) return;

      final avatarBytes = await IdentityAvatarResolver.resolve(identity);

      if (!mounted) return;

      setState(() {
        _identity = identity;
        _username = identity.username;
        _avatarBytes = avatarBytes;
        _peerId = identity.peerId;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadQualityPreference() async {
    final pref = await loadImageQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      setState(() => _qualityPreference = pref);
    }
  }

  Future<void> _loadVideoQualityPreference() async {
    final pref = await loadVideoQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      setState(() => _videoQualityPreference = pref);
    }
  }

  Future<void> _loadFeedFromDatabase() async {
    try {
      final items = await loadFeed(
        contactRepo: widget.contactRepository,
        messageRepo: widget.messageRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
        groupRepo: widget.groupRepository,
        groupMsgRepo: widget.groupMessageRepository,
      );
      if (!mounted) return;

      _feedStore.replaceAll(items);
      _markFeedLoaded();
      _loadReactionsForFeed();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_DB_LOAD_ERROR',
        details: {'error': e.toString()},
      );
      _markFeedLoaded();
    }
  }

  Future<void> _loadTotalUnreadCount() async {
    try {
      final count = await widget.messageRepository
          .getTotalUnreadCountExcludingArchived();
      if (!mounted) return;
      _totalUnreadCountNotifier.value = count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_UNREAD_COUNT_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _refreshFeed() async {
    await _loadTotalUnreadCount();
    await _loadFeedFromDatabase();
  }

  Set<String> _messageIdsForContact(String contactPeerId) {
    return _feedStore.messageIdsForContact(contactPeerId);
  }

  Future<void> _refreshReactionsForMessageIds(List<String> messageIds) async {
    if (widget.reactionRepository == null || messageIds.isEmpty) {
      return;
    }

    try {
      final reactions = await loadReactionsForConversation(
        reactionRepo: widget.reactionRepository!,
        messageIds: messageIds,
      );
      _reactionStore.replaceForMessageIds(messageIds, reactions);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_LOAD_REACTIONS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _refreshContactFeedItem(
    String contactPeerId, {
    bool refreshUnreadCount = true,
  }) async {
    final previousMessageIds = _messageIdsForContact(contactPeerId);

    try {
      final snapshot = await loadContactFeedSnapshot(
        contactRepo: widget.contactRepository,
        messageRepo: widget.messageRepository,
        contactPeerId: contactPeerId,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      if (!mounted) return;

      final nextMessageIds = snapshot.threadItem == null
          ? <String>{}
          : snapshot.threadItem!.messages.map((message) => message.id).toSet();

      _feedStore.replaceContactSnapshot(
        contactPeerId: contactPeerId,
        connectionItem: snapshot.connectionItem,
        threadItem: snapshot.threadItem,
      );
      _markFeedLoaded();
      final removedMessageIds = previousMessageIds.difference(nextMessageIds);
      _reactionStore.clearMessageIds(removedMessageIds);

      await _refreshReactionsForMessageIds(nextMessageIds.toList());

      if (refreshUnreadCount) {
        await _loadTotalUnreadCount();
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_CONTACT_REFRESH_ERROR',
        details: {'contactPeerId': contactPeerId, 'error': e.toString()},
      );
      await _refreshFeed();
    }
  }

  Future<void> _refreshGroupFeedItem(String groupId) async {
    final groupRepo = widget.groupRepository;
    final groupMsgRepo = widget.groupMessageRepository;
    if (groupRepo == null || groupMsgRepo == null) return;

    try {
      final threadItem = await loadGroupFeedSnapshot(
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        groupId: groupId,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      if (!mounted) return;

      _feedStore.replaceGroupSnapshot(groupId: groupId, threadItem: threadItem);
      _markFeedLoaded();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_GROUP_REFRESH_ERROR',
        details: {'groupId': groupId, 'error': e.toString()},
      );
      await _refreshFeed();
    }
  }

  Future<void> _refreshAllContactsSection({
    bool refreshUnreadCount = true,
  }) async {
    final previousContactMessageIds = _feedItems
        .whereType<ThreadFeedItem>()
        .expand((item) => item.messages)
        .map((message) => message.id)
        .toSet();

    try {
      final contactItems = await loadContactFeedItems(
        contactRepo: widget.contactRepository,
        messageRepo: widget.messageRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      if (!mounted) return;

      final nextContactMessageIds = contactItems
          .whereType<ThreadFeedItem>()
          .expand((item) => item.messages)
          .map((message) => message.id)
          .toSet();

      _feedStore.replaceContacts(contactItems);
      _markFeedLoaded();
      _reactionStore.clearMessageIds(
        previousContactMessageIds.difference(nextContactMessageIds),
      );

      await _refreshReactionsForMessageIds(nextContactMessageIds.toList());

      if (refreshUnreadCount) {
        await _loadTotalUnreadCount();
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_CONTACT_SECTION_REFRESH_ERROR',
        details: {'error': e.toString()},
      );
      await _refreshFeed();
    }
  }

  Future<void> _refreshAllGroupsSection() async {
    try {
      final groupItems = await loadGroupFeedItems(
        groupRepo: widget.groupRepository,
        groupMsgRepo: widget.groupMessageRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      if (!mounted) return;

      _feedStore.replaceGroups(groupItems);
      _markFeedLoaded();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_GROUP_SECTION_REFRESH_ERROR',
        details: {'error': e.toString()},
      );
      await _refreshFeed();
    }
  }

  ThreadFeedItem? _threadForContact(String contactPeerId) {
    for (final item in _feedItems) {
      if (item is ThreadFeedItem && item.contactPeerId == contactPeerId) {
        return item;
      }
    }
    return null;
  }

  GroupThreadFeedItem? _threadForGroup(String groupId) {
    for (final item in _feedItems) {
      if (item is GroupThreadFeedItem && item.groupId == groupId) {
        return item;
      }
    }
    return null;
  }

  Future<List<MediaAttachment>> _loadResolvedAttachmentsForMessage(
    String messageId,
  ) async {
    final attachments = await widget.mediaAttachmentRepository
        .getAttachmentsForMessage(messageId);
    if (attachments.isEmpty) return const <MediaAttachment>[];

    final resolved = <MediaAttachment>[];
    for (final attachment in attachments) {
      if (attachment.localPath == null) {
        resolved.add(attachment);
        continue;
      }

      final absolutePath = await widget.mediaFileManager.resolveStoredPath(
        attachment.localPath!,
      );
      resolved.add(attachment.copyWith(localPath: absolutePath));
    }
    return resolved;
  }

  ThreadMessage _toThreadMessage(ConversationMessage message) {
    final timestamp = DateTime.tryParse(message.timestamp) ?? DateTime.now();
    return ThreadMessage(
      id: message.id,
      text: message.text,
      time: formatMessageTime(message.timestamp),
      timestamp: timestamp,
      isUnread: message.isIncoming && message.readAt == null,
      isIncoming: message.isIncoming,
      status: message.isIncoming ? null : message.status,
      quotedMessageId: message.quotedMessageId,
      media: message.media,
      senderPeerId: message.senderPeerId,
    );
  }

  ThreadMessage _toGroupThreadMessage(GroupMessage message) {
    return ThreadMessage(
      id: message.id,
      text: message.text,
      time: formatMessageTime(message.timestamp.toUtc().toIso8601String()),
      timestamp: message.timestamp,
      isUnread: message.isIncoming && message.readAt == null,
      isIncoming: message.isIncoming,
      status: message.isIncoming ? null : message.status,
      quotedMessageId: message.quotedMessageId,
      senderPeerId: message.senderPeerId,
      senderUsername: message.senderUsername,
      media: message.media,
    );
  }

  List<ThreadMessage> _mergeThreadMessages(
    List<ThreadMessage> current,
    ThreadMessage next,
  ) {
    final updated = List<ThreadMessage>.from(current);
    final index = updated.indexWhere((message) => message.id == next.id);
    if (index >= 0) {
      updated[index] = next;
    } else {
      updated.add(next);
    }
    updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return updated;
  }

  ConversationState _conversationStateForMessages(
    List<ThreadMessage> messages,
  ) {
    final hasUnreadIncoming = messages.any(
      (message) => message.isIncoming && message.isUnread,
    );
    final hasSentMessages = messages.any((message) => !message.isIncoming);
    if (hasUnreadIncoming && hasSentMessages) {
      return ConversationState.active;
    }
    if (hasUnreadIncoming) {
      return ConversationState.unread;
    }
    if (hasSentMessages) {
      return ConversationState.replied;
    }
    return ConversationState.read;
  }

  DateTime? _lastSentTimestamp(List<ThreadMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (!message.isIncoming) {
        return message.timestamp;
      }
    }
    return null;
  }

  ThreadFeedItem _buildThreadFeedItem({
    required ContactModel contact,
    required List<ThreadMessage> messages,
  }) {
    final state = _conversationStateForMessages(messages);
    return ThreadFeedItem(
      id: 'thread_${contact.peerId}',
      timestamp: messages.isEmpty ? DateTime.now() : messages.last.timestamp,
      contactPeerId: contact.peerId,
      contactUsername: contact.username,
      messages: messages,
      unreadCount: messages.where((message) => message.isUnread).length,
      isUnreadCard:
          state == ConversationState.unread ||
          state == ConversationState.active,
      conversationState: state,
      lastRepliedAt: _lastSentTimestamp(messages),
      isBlocked: contact.isBlocked,
    );
  }

  GroupThreadFeedItem _buildGroupThreadFeedItem({
    required GroupModel group,
    required List<ThreadMessage> messages,
  }) {
    final state = _conversationStateForMessages(messages);
    return GroupThreadFeedItem(
      id: 'group_thread_${group.id}',
      timestamp: messages.isEmpty ? group.createdAt : messages.last.timestamp,
      groupId: group.id,
      groupName: group.name,
      groupType: group.type,
      myRole: group.myRole,
      messages: messages,
      unreadCount: messages.where((message) => message.isUnread).length,
      conversationState: state,
    );
  }

  Future<void> _applyIncomingContactMessageToFeed(
    ConversationMessage message, {
    bool refreshUnreadCount = true,
  }) async {
    try {
      final contact = await widget.contactRepository.getContact(
        message.contactPeerId,
      );
      if (contact == null || contact.isArchived) {
        await _refreshContactFeedItem(
          message.contactPeerId,
          refreshUnreadCount: refreshUnreadCount,
        );
        return;
      }

      final displayMessage = message.copyWith(
        media: await _loadResolvedAttachmentsForMessage(message.id),
      );
      final currentThread = _threadForContact(contact.peerId);
      final nextMessages = _mergeThreadMessages(
        currentThread?.messages ?? const <ThreadMessage>[],
        _toThreadMessage(displayMessage),
      );

      _feedStore.replaceContactSnapshot(
        contactPeerId: contact.peerId,
        connectionItem: ConnectionFeedItem.fromContact(contact),
        threadItem: _buildThreadFeedItem(
          contact: contact,
          messages: nextMessages,
        ),
      );
      _markFeedLoaded();

      if (refreshUnreadCount) {
        await _loadTotalUnreadCount();
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_CONTACT_INCREMENTAL_UPDATE_ERROR',
        details: {
          'contactPeerId': message.contactPeerId,
          'error': e.toString(),
        },
      );
      await _refreshContactFeedItem(
        message.contactPeerId,
        refreshUnreadCount: refreshUnreadCount,
      );
    }
  }

  Future<void> _applyContactUpdateToFeed(ContactModel contact) async {
    if (contact.isArchived) {
      await _refreshContactFeedItem(contact.peerId);
      return;
    }

    final currentThread = _threadForContact(contact.peerId);
    _feedStore.replaceContactSnapshot(
      contactPeerId: contact.peerId,
      connectionItem: ConnectionFeedItem.fromContact(contact),
      threadItem: currentThread == null
          ? null
          : ThreadFeedItem(
              id: currentThread.id,
              timestamp: currentThread.timestamp,
              contactPeerId: contact.peerId,
              contactUsername: contact.username,
              messages: currentThread.messages,
              unreadCount: currentThread.unreadCount,
              isUnreadCard: currentThread.isUnreadCard,
              conversationState: currentThread.conversationState,
              lastRepliedAt: currentThread.lastRepliedAt,
              isBlocked: contact.isBlocked,
            ),
    );
    _markFeedLoaded();
  }

  Future<void> _applyIncomingGroupMessageToFeed(GroupMessage message) async {
    final groupRepo = widget.groupRepository;
    if (groupRepo == null) {
      return;
    }

    try {
      final group = await groupRepo.getGroup(message.groupId);
      if (group == null || group.isArchived) {
        await _refreshGroupFeedItem(message.groupId);
        return;
      }

      final displayMessage = message.copyWith(
        media: await _loadResolvedAttachmentsForMessage(message.id),
      );
      final currentThread = _threadForGroup(group.id);
      final nextMessages = _mergeThreadMessages(
        currentThread?.messages ?? const <ThreadMessage>[],
        _toGroupThreadMessage(displayMessage),
      );

      _feedStore.replaceGroupSnapshot(
        groupId: group.id,
        threadItem: _buildGroupThreadFeedItem(
          group: group,
          messages: nextMessages,
        ),
      );
      _markFeedLoaded();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_GROUP_INCREMENTAL_UPDATE_ERROR',
        details: {'groupId': message.groupId, 'error': e.toString()},
      );
      await _refreshGroupFeedItem(message.groupId);
    }
  }

  Future<void> _applyRouteChanges(FeedRouteChanges? changes) async {
    if (changes == null || !changes.hasChanges) return;

    var shouldReloadUnreadCount = false;

    if (changes.reloadAllContacts) {
      await _refreshAllContactsSection(refreshUnreadCount: false);
      shouldReloadUnreadCount = true;
    } else if (changes.changedContactPeerIds.isNotEmpty) {
      for (final peerId in changes.changedContactPeerIds) {
        _sessionReplies.clear(peerId);
        await _refreshContactFeedItem(peerId, refreshUnreadCount: false);
      }
      shouldReloadUnreadCount = true;
    }

    if (changes.reloadAllGroups) {
      await _refreshAllGroupsSection();
    } else if (changes.changedGroupIds.isNotEmpty) {
      for (final groupId in changes.changedGroupIds) {
        _sessionReplies.clear('group:$groupId');
        await _refreshGroupFeedItem(groupId);
      }
    }

    if (shouldReloadUnreadCount) {
      await _loadTotalUnreadCount();
    }
  }

  void _startListeningForContactRequests() {
    _requestSubscription = widget.contactRequestListener.requestStream.listen(
      _onContactRequest,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_REQUEST_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_REQUEST_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  void _onContactRequest(ContactRequestModel request) {
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_FL_CONTACT_REQUEST_RECEIVED',
      details: {
        'peerId': request.peerId.substring(0, 10),
        'username': request.username,
      },
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ContactRequestDialog(
        request: request,
        onAccept: () => _acceptRequest(ctx, request),
        onDecline: () => _declineRequest(ctx, request),
      ),
    );
  }

  Future<void> _acceptRequest(
    BuildContext ctx,
    ContactRequestModel request,
  ) async {
    Navigator.pop(ctx);

    final result = await acceptAndReciprocateContactRequest(
      requestRepo: widget.contactRequestRepository,
      contactRepo: widget.contactRepository,
      peerId: request.peerId,
      p2pService: widget.p2pService,
      identityRepo: widget.repository,
      bridge: widget.bridge,
      onProfileDownloaded: widget.chatMessageListener.emitContactUpdate,
    );

    if (!mounted) return;

    if (result == AcceptContactRequestResult.success ||
        result == AcceptContactRequestResult.notPending) {
      final contact = request.toContactModel();
      final alreadyExists = _feedItems.any(
        (item) =>
            item is ConnectionFeedItem && item.contactPeerId == contact.peerId,
      );
      if (!alreadyExists) {
        final item = ConnectionFeedItem.fromContact(contact);
        _feedStore.upsertConnection(item);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.error_add_contact),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _declineRequest(
    BuildContext ctx,
    ContactRequestModel request,
  ) async {
    Navigator.pop(ctx);

    await declineContactRequest(
      requestRepo: widget.contactRequestRepository,
      peerId: request.peerId,
    );
  }

  void _startListeningForChatMessages() {
    _chatSubscription = widget.chatMessageListener.incomingMessageStream.listen(
      _onIncomingChatMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_CHAT_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'FEED_CHAT_STREAM_DONE', details: {});
      },
    );
  }

  void _startListeningForOutgoingMessageChanges() {
    final messageRepo = widget.messageRepository;
    if (messageRepo is! MessageRepositoryChangeSource) {
      return;
    }

    final changeSource = messageRepo as MessageRepositoryChangeSource;
    _repoChangeSubscription = changeSource.messageChanges
        .where(
          (message) =>
              !message.isIncoming &&
              _shouldRefreshFromRepositoryChange(message.status),
        )
        .listen(
          (message) {
            if (!mounted) return;
            unawaited(
              _applyIncomingContactMessageToFeed(
                message,
                refreshUnreadCount: false,
              ),
            );
          },
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'FEED_REPO_CHANGE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );
  }

  bool _shouldRefreshFromRepositoryChange(String status) =>
      status == 'sent' || status == 'delivered';

  void _onIncomingChatMessage(ConversationMessage message) {
    if (!mounted) return;
    _sessionReplies.clear(message.contactPeerId);
    unawaited(_applyIncomingContactMessageToFeed(message));
  }

  void _startListeningForContactUpdates() {
    _contactUpdateSubscription = widget.chatMessageListener.contactUpdatedStream
        .listen(
          _onContactUpdated,
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'FEED_CONTACT_UPDATE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
          onDone: () {
            emitFlowEvent(
              layer: 'FL',
              event: 'FEED_CONTACT_UPDATE_STREAM_DONE',
              details: {},
            );
          },
        );
  }

  void _onContactUpdated(ContactModel contact) {
    if (!mounted) return;
    unawaited(_applyContactUpdateToFeed(contact));
  }

  void _onSendMessage(ConnectionFeedItem item) async {
    final contact = await widget.contactRepository.getContact(
      item.contactPeerId,
    );
    if (contact == null || !mounted) return;

    _clearFeedComposerFocus();
    Navigator.of(context)
        .push(
          buildConversationSlideUpRoute(
            builder: (_) => ConversationWired(
              contact: contact,
              identityRepo: widget.repository,
              messageRepo: widget.messageRepository,
              chatMessageListener: widget.chatMessageListener,
              p2pService: widget.p2pService,
              bridge: widget.bridge,
              contactRepo: widget.contactRepository,
              mediaAttachmentRepo: widget.mediaAttachmentRepository,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              qualityPreference: _qualityPreference,
              videoQualityPreference: _videoQualityPreference,
              conversationTracker: widget.conversationTracker,
              audioRecorderService: widget.audioRecorderService,
              reactionRepo: widget.reactionRepository,
              reactionListener: widget.reactionListener,
              introductionRepository: widget.introductionRepository,
            ),
          ),
        )
        .then((_) {
          _sessionReplies.clear(item.contactPeerId);
          unawaited(_refreshContactFeedItem(item.contactPeerId));
        });
  }

  void _onReplyToMessage(String contactPeerId) async {
    final contact = await widget.contactRepository.getContact(contactPeerId);
    if (contact == null || !mounted) return;

    _clearFeedComposerFocus();
    Navigator.of(context)
        .push(
          buildConversationSlideUpRoute(
            builder: (_) => ConversationWired(
              contact: contact,
              identityRepo: widget.repository,
              messageRepo: widget.messageRepository,
              chatMessageListener: widget.chatMessageListener,
              p2pService: widget.p2pService,
              bridge: widget.bridge,
              contactRepo: widget.contactRepository,
              mediaAttachmentRepo: widget.mediaAttachmentRepository,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              qualityPreference: _qualityPreference,
              videoQualityPreference: _videoQualityPreference,
              conversationTracker: widget.conversationTracker,
              audioRecorderService: widget.audioRecorderService,
              reactionRepo: widget.reactionRepository,
              reactionListener: widget.reactionListener,
              introductionRepository: widget.introductionRepository,
            ),
          ),
        )
        .then((_) {
          _sessionReplies.clear(contactPeerId);
          unawaited(_refreshContactFeedItem(contactPeerId));
        });
  }

  Future<void> _onInlineSend(String contactPeerId, String text) async {
    final identity = _identity;
    if (identity == null) return;
    final localizations = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Optimistic: show session reply immediately before network send.
    final quotedMsgId = _activeQuoteMessageIds[contactPeerId];
    final draftText = text;
    final sanitizedText = sanitizeMessageText(text);
    _draftTexts.remove(contactPeerId);
    _activeQuoteMessageIds.remove(contactPeerId);
    _sessionReplies.track(contactPeerId, SessionReply.justNow(text));
    if (mounted) setState(() {});
    String? bgTaskId;
    ConversationMessage? optimisticMessage;

    try {
      final contact = await widget.contactRepository.getContact(contactPeerId);
      if (contact == null || !mounted) {
        _restoreFeedComposerState(
          draftKey: contactPeerId,
          quotedMessageId: quotedMsgId,
          draftText: draftText,
          sessionReplyKey: contactPeerId,
        );
        return;
      }

      final timestamp = DateTime.now().toUtc().toIso8601String();
      optimisticMessage = ConversationMessage(
        id: _uuid.v4(),
        contactPeerId: contactPeerId,
        senderPeerId: identity.peerId,
        text: sanitizedText,
        timestamp: timestamp,
        status: 'sending',
        isIncoming: false,
        createdAt: timestamp,
        quotedMessageId: quotedMsgId,
      );

      try {
        await widget.messageRepository.saveMessage(optimisticMessage);
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_FL_OPTIMISTIC_SAVE_ERROR',
          details: {'error': e.toString(), 'contactPeerId': contactPeerId},
        );
      }

      // Acquire background task before network send.
      bgTaskId = await callBgBegin(widget.bridge);

      final (result, message) = await sendChatMessage(
        p2pService: widget.p2pService,
        messageRepo: widget.messageRepository,
        targetPeerId: contactPeerId,
        text: sanitizedText,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        messageId: optimisticMessage.id,
        timestamp: optimisticMessage.timestamp,
        bridge: widget.bridge,
        recipientMlKemPublicKey: contact.mlKemPublicKey,
        quotedMessageId: quotedMsgId,
      );

      if (!mounted) return;

      if (result == SendChatMessageResult.success) {
        // Mark as read on successful inline reply
        await markConversationRead(
          messageRepo: widget.messageRepository,
          contactPeerId: contactPeerId,
        );
        if (message != null) {
          await _applyIncomingContactMessageToFeed(
            message,
            refreshUnreadCount: false,
          );
        } else {
          await _refreshContactFeedItem(
            contactPeerId,
            refreshUnreadCount: false,
          );
        }
        await _loadTotalUnreadCount();
      } else {
        if (message == null) {
          await widget.messageRepository.updateMessageStatus(
            optimisticMessage.id,
            'failed',
          );
        }
        _restoreFeedComposerState(
          draftKey: contactPeerId,
          quotedMessageId: quotedMsgId,
          draftText: draftText,
          sessionReplyKey: contactPeerId,
        );
        final errorText = result == SendChatMessageResult.encryptionRequired
            ? 'Cannot send: contact does not support encryption.'
            : localizations.error_send_message;
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(errorText),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (optimisticMessage != null) {
        await widget.messageRepository.updateMessageStatus(
          optimisticMessage.id,
          'failed',
        );
      }
      _restoreFeedComposerState(
        draftKey: contactPeerId,
        quotedMessageId: quotedMsgId,
        draftText: draftText,
        sessionReplyKey: contactPeerId,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_INLINE_SEND_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(localizations.error_send_message),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      await callBgEnd(widget.bridge, bgTaskId);
    }
  }

  void _onViewFullConversation(String contactPeerId) {
    _onReplyToMessage(contactPeerId);
  }

  void _onAttach(String contactPeerId) {
    _clearFeedComposerFocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text(
                'Media Library',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndOpenConversation(
                  contactPeerId,
                  source: _MediaSource.gallery,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text(
                'Take Photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndOpenConversation(
                  contactPeerId,
                  source: _MediaSource.camera,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.white),
              title: const Text(
                'Record Video',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndOpenConversation(
                  contactPeerId,
                  source: _MediaSource.videoCamera,
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndOpenConversation(
    String contactPeerId, {
    required _MediaSource source,
  }) async {
    try {
      final picker = ImagePicker();
      List<PendingComposerMedia> pendingMedia;

      switch (source) {
        case _MediaSource.camera:
          final picked = await picker.pickImage(source: ImageSource.camera);
          if (picked == null || !mounted) return;
          final media = await _preparePendingMediaForLaunch(picked.path);
          pendingMedia = [media];
        case _MediaSource.videoCamera:
          final picked = await picker.pickVideo(source: ImageSource.camera);
          if (picked == null || !mounted) return;
          _showProcessingSnackBar();
          final media = await _preparePendingMediaForLaunch(picked.path);
          if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
          pendingMedia = [media];
        case _MediaSource.gallery:
          final picked = await picker.pickMultipleMedia();
          if (picked.isEmpty || !mounted) return;
          final hasVideo = picked.any(
            (xf) => widget.imageProcessor.isProcessableVideo(xf.path),
          );
          if (hasVideo) _showProcessingSnackBar();
          final processedFiles = <PendingComposerMedia>[];
          for (final xf in picked) {
            processedFiles.add(await _preparePendingMediaForLaunch(xf.path));
          }
          if (hasVideo && mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
          pendingMedia = processedFiles;
      }
      final files = pendingMedia
          .map((media) => media.file)
          .toList(growable: false);

      final contact = await widget.contactRepository.getContact(contactPeerId);
      if (contact == null || !mounted) return;

      Navigator.of(context)
          .push(
            buildConversationSlideUpRoute(
              builder: (_) => ConversationWired(
                contact: contact,
                identityRepo: widget.repository,
                messageRepo: widget.messageRepository,
                chatMessageListener: widget.chatMessageListener,
                p2pService: widget.p2pService,
                bridge: widget.bridge,
                contactRepo: widget.contactRepository,
                mediaAttachmentRepo: widget.mediaAttachmentRepository,
                mediaFileManager: widget.mediaFileManager,
                initialAttachments: files,
                initialPendingMedia: pendingMedia,
                imageProcessor: widget.imageProcessor,
                qualityPreference: _qualityPreference,
                videoQualityPreference: _videoQualityPreference,
                conversationTracker: widget.conversationTracker,
                audioRecorderService: widget.audioRecorderService,
                reactionRepo: widget.reactionRepository,
                reactionListener: widget.reactionListener,
                introductionRepository: widget.introductionRepository,
              ),
            ),
          )
          .then((_) {
            _sessionReplies.clear(contactPeerId);
            unawaited(_refreshContactFeedItem(contactPeerId));
          });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_PICK_ATTACH_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _showProcessingSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.status_processing_video),
        duration: const Duration(minutes: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<PendingComposerMedia> _preparePendingMediaForLaunch(String path) {
    return preparePendingComposerMedia(
      inputPath: path,
      imageProcessor: widget.imageProcessor,
      imageQualityPreference: _qualityPreference,
      videoQualityPreference: _videoQualityPreference,
    );
  }

  Future<void> _loadReactionsForFeed() async {
    if (widget.reactionRepository == null) return;
    final messageIds = _feedStore.contactMessageIds.toList();
    if (messageIds.isEmpty) {
      _reactionStore.replaceAll(const {});
      return;
    }
    try {
      final reactions = await loadReactionsForConversation(
        reactionRepo: widget.reactionRepository!,
        messageIds: messageIds,
      );
      _reactionStore.replaceAll(reactions);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_LOAD_REACTIONS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _startListeningForReactions() {
    if (widget.reactionListener == null) return;
    _reactionSubscription = widget
        .reactionListener!
        .incomingReactionChangeStream
        .listen(
          _onIncomingReactionChange,
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'FEED_REACTION_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );
  }

  void _onIncomingReactionChange(ReactionChange change) {
    if (!mounted) return;
    if (!_feedStore.containsMessageId(change.messageId)) return;
    _reactionStore.applyChange(change);
  }

  void _startListeningForGroupReactions() {
    final listener = widget.groupMessageListener;
    if (listener == null) return;
    _groupReactionSubscription = listener.groupReactionChangeStream.listen(
      (change) {
        if (!mounted) return;
        _reactionStore.applyChange(change);
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_GROUP_REACTION_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  void _startListeningForGroupMessages() {
    final listener = widget.groupMessageListener;
    if (listener == null) return;
    _groupMessageSubscription = listener.groupMessageStream.listen(
      (message) {
        if (!mounted) return;
        _sessionReplies.clear('group:${message.groupId}');
        unawaited(_applyIncomingGroupMessageToFeed(message));
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_GROUP_MSG_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  void _startListeningForIntroductions() {
    final listener = widget.introductionListener;
    if (listener == null) return;

    _introReceivedSubscription = listener.introReceivedStream.listen((_) {});

    _introStatusSubscription = listener.introStatusChangedStream.listen((
      intro,
    ) {
      final ownPeerId = _peerId;
      if (!mounted || ownPeerId == null) return;
      if (intro.status != IntroductionOverallStatus.mutualAccepted) return;

      final otherPeerId = intro.recipientId == ownPeerId
          ? intro.introducedId
          : intro.recipientId;
      if (otherPeerId.isEmpty) return;

      unawaited(_refreshContactFeedItem(otherPeerId));
    });
  }

  Future<GroupModel> _resolveGroupForThread(
    GroupThreadFeedItem groupThread,
  ) async {
    final groupRepo = widget.groupRepository;
    final persisted = await groupRepo?.getGroup(groupThread.groupId);
    if (persisted != null) {
      return persisted;
    }

    return GroupModel(
      id: groupThread.groupId,
      name: groupThread.groupName,
      type: groupThread.groupType,
      topicName: '/mknoon/group/${groupThread.groupId}',
      createdAt: DateTime.now(),
      createdBy: '',
      myRole: groupThread.myRole,
    );
  }

  Future<void> _openGroupConversation(
    GroupThreadFeedItem groupThread, {
    List<PendingComposerMedia>? initialPendingMedia,
    List<File>? initialAttachments,
  }) async {
    final groupRepo = widget.groupRepository;
    final msgRepo = widget.groupMessageRepository;
    final listener = widget.groupMessageListener;
    if (groupRepo == null || msgRepo == null || listener == null) return;

    final group = await _resolveGroupForThread(groupThread);
    if (!mounted) return;

    _clearFeedComposerFocus();
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GroupConversationWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              groupMessageListener: listener,
              bridge: widget.bridge,
              identityRepo: widget.repository,
              contactRepo: widget.contactRepository,
              p2pService: widget.p2pService,
              mediaAttachmentRepo: widget.mediaAttachmentRepository,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              qualityPreference: _qualityPreference,
              videoQualityPreference: _videoQualityPreference,
              audioRecorderService: widget.audioRecorderService,
              groupConversationTracker: widget.groupConversationTracker,
              reactionRepo: widget.reactionRepository,
              initialPendingMedia: initialPendingMedia,
              initialAttachments: initialAttachments,
            ),
          ),
        )
        .then((_) {
          _sessionReplies.clear('group:${groupThread.groupId}');
          unawaited(_refreshGroupFeedItem(groupThread.groupId));
        });
  }

  void _onGroupTap(GroupThreadFeedItem groupThread) {
    unawaited(_openGroupConversation(groupThread));
  }

  void _onGroupAttach(GroupThreadFeedItem groupThread) {
    if (!groupThread.canWrite) return;
    _clearFeedComposerFocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text(
                'Media Library',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndOpenGroupConversation(
                  groupThread,
                  source: _MediaSource.gallery,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text(
                'Take Photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndOpenGroupConversation(
                  groupThread,
                  source: _MediaSource.camera,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.white),
              title: const Text(
                'Record Video',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndOpenGroupConversation(
                  groupThread,
                  source: _MediaSource.videoCamera,
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndOpenGroupConversation(
    GroupThreadFeedItem groupThread, {
    required _MediaSource source,
  }) async {
    try {
      final picker = ImagePicker();
      List<PendingComposerMedia> pendingMedia;

      switch (source) {
        case _MediaSource.camera:
          final picked = await picker.pickImage(source: ImageSource.camera);
          if (picked == null || !mounted) return;
          final media = await _preparePendingMediaForLaunch(picked.path);
          pendingMedia = [media];
        case _MediaSource.videoCamera:
          final picked = await picker.pickVideo(source: ImageSource.camera);
          if (picked == null || !mounted) return;
          _showProcessingSnackBar();
          final media = await _preparePendingMediaForLaunch(picked.path);
          if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
          pendingMedia = [media];
        case _MediaSource.gallery:
          final picked = await picker.pickMultipleMedia();
          if (picked.isEmpty || !mounted) return;
          final hasVideo = picked.any(
            (xf) => widget.imageProcessor.isProcessableVideo(xf.path),
          );
          if (hasVideo) _showProcessingSnackBar();
          final processedFiles = <PendingComposerMedia>[];
          for (final xf in picked) {
            processedFiles.add(await _preparePendingMediaForLaunch(xf.path));
          }
          if (hasVideo && mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
          pendingMedia = processedFiles;
      }
      final files = pendingMedia
          .map((media) => media.file)
          .toList(growable: false);

      if (!mounted) return;

      await _openGroupConversation(
        groupThread,
        initialPendingMedia: pendingMedia,
        initialAttachments: files,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_GROUP_PICK_ATTACH_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onGroupInlineSend(String groupId, String text) async {
    final identity = _identity;
    final groupRepo = widget.groupRepository;
    final msgRepo = widget.groupMessageRepository;
    if (identity == null || groupRepo == null || msgRepo == null) return;

    // Optimistic: show session reply immediately before network send.
    final quoteKey = _groupQuoteKey(groupId);
    final quotedMsgId = _activeQuoteMessageIds[quoteKey];
    final draftText = text;
    _draftTexts.remove(quoteKey);
    _activeQuoteMessageIds.remove(quoteKey);
    _sessionReplies.track('group:$groupId', SessionReply.justNow(text));
    if (mounted) setState(() {});

    try {
      final (result, message) = await sendGroupMessage(
        bridge: widget.bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: text,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        quotedMessageId: quotedMsgId,
      );

      if (!mounted) return;

      if (result == SendGroupMessageResult.success ||
          result == SendGroupMessageResult.successNoPeers) {
        await widget.groupMessageRepository?.markAsRead(groupId);
        await _refreshGroupFeedItem(groupId);
        await _loadTotalUnreadCount();
      } else {
        _restoreFeedComposerState(
          draftKey: quoteKey,
          quotedMessageId: quotedMsgId,
          draftText: draftText,
          sessionReplyKey: 'group:$groupId',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.error_send_message),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _restoreFeedComposerState(
        draftKey: quoteKey,
        quotedMessageId: quotedMsgId,
        draftText: draftText,
        sessionReplyKey: 'group:$groupId',
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_GROUP_INLINE_SEND_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.error_send_message),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onReactionSelected(String messageId, String emoji) async {
    final identity = _identity;
    if (identity == null) return;

    final reactionRepo = widget.reactionRepository;
    if (reactionRepo == null) return;

    // Find which contact this message belongs to
    final thread = _feedItems
        .whereType<ThreadFeedItem>()
        .where((t) => t.messages.any((m) => m.id == messageId))
        .firstOrNull;
    if (thread == null) return;

    final contact = await widget.contactRepository.getContact(
      thread.contactPeerId,
    );
    if (contact == null || !mounted) return;

    // Check if toggling (same emoji from same user)
    final currentReactions = _reactionStore.reactionsForMessage(messageId);
    final ownReaction = currentReactions
        .where((r) => r.senderPeerId == identity.peerId)
        .firstOrNull;

    if (ownReaction != null && ownReaction.emoji == emoji) {
      // Toggle off: remove reaction optimistically
      final updated = currentReactions
          .where((r) => r.senderPeerId != identity.peerId)
          .toList();
      _reactionStore.setMessageReactions(messageId, updated);

      await removeReaction(
        p2pService: widget.p2pService,
        bridge: widget.bridge,
        reactionRepo: reactionRepo,
        targetPeerId: thread.contactPeerId,
        messageId: messageId,
        emoji: emoji,
        senderPeerId: identity.peerId,
        recipientMlKemPublicKey: contact.mlKemPublicKey ?? '',
      );
      return;
    }

    // Add/replace reaction optimistically
    final now = DateTime.now().toUtc().toIso8601String();
    final optimisticReaction = MessageReaction(
      id: '',
      messageId: messageId,
      emoji: emoji,
      senderPeerId: identity.peerId,
      timestamp: now,
      createdAt: now,
    );

    final updated = List<MessageReaction>.from(currentReactions);
    final idx = updated.indexWhere((r) => r.senderPeerId == identity.peerId);
    if (idx >= 0) {
      updated[idx] = optimisticReaction;
    } else {
      updated.add(optimisticReaction);
    }
    _reactionStore.setMessageReactions(messageId, updated);

    final (result, reaction) = await sendReaction(
      p2pService: widget.p2pService,
      bridge: widget.bridge,
      reactionRepo: reactionRepo,
      targetPeerId: thread.contactPeerId,
      messageId: messageId,
      emoji: emoji,
      senderPeerId: identity.peerId,
      recipientMlKemPublicKey: contact.mlKemPublicKey ?? '',
    );

    // Update with real reaction on success
    if (result == SendReactionResult.success && reaction != null && mounted) {
      final updated = List<MessageReaction>.from(
        _reactionStore.reactionsForMessage(messageId),
      );
      final idx = updated.indexWhere((r) => r.senderPeerId == identity.peerId);
      if (idx >= 0) {
        updated[idx] = reaction;
      }
      _reactionStore.setMessageReactions(messageId, updated);
    }
  }

  Future<void> _onGroupReactionSelected(
    String groupId,
    String messageId,
    String emoji,
  ) async {
    final identity = _identity;
    if (identity == null) return;

    final reactionRepo = widget.reactionRepository;
    final groupRepo = widget.groupRepository;
    final msgRepo = widget.groupMessageRepository;
    if (reactionRepo == null || groupRepo == null || msgRepo == null) return;

    // Check if toggling (same emoji from same user)
    final currentReactions = _reactionStore.reactionsForMessage(messageId);
    final ownReaction = currentReactions
        .where((r) => r.senderPeerId == identity.peerId)
        .firstOrNull;

    if (ownReaction != null && ownReaction.emoji == emoji) {
      // Toggle off: remove reaction optimistically
      final updated = currentReactions
          .where((r) => r.senderPeerId != identity.peerId)
          .toList();
      _reactionStore.setMessageReactions(messageId, updated);

      await removeGroupReaction(
        bridge: widget.bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        groupId: groupId,
        messageId: messageId,
        emoji: emoji,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
      );
      return;
    }

    // Add/replace reaction optimistically
    final now = DateTime.now().toUtc().toIso8601String();
    final optimisticReaction = MessageReaction(
      id: '',
      messageId: messageId,
      emoji: emoji,
      senderPeerId: identity.peerId,
      timestamp: now,
      createdAt: now,
    );

    final updated = List<MessageReaction>.from(currentReactions);
    final idx = updated.indexWhere((r) => r.senderPeerId == identity.peerId);
    if (idx >= 0) {
      updated[idx] = optimisticReaction;
    } else {
      updated.add(optimisticReaction);
    }
    _reactionStore.setMessageReactions(messageId, updated);

    final (result, reaction) = await sendGroupReaction(
      bridge: widget.bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      groupId: groupId,
      messageId: messageId,
      emoji: emoji,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
    );

    // Update with real reaction on success
    if (result == SendGroupReactionResult.success &&
        reaction != null &&
        mounted) {
      final updated = List<MessageReaction>.from(
        _reactionStore.reactionsForMessage(messageId),
      );
      final idx = updated.indexWhere((r) => r.senderPeerId == identity.peerId);
      if (idx >= 0) {
        updated[idx] = reaction;
      }
      _reactionStore.setMessageReactions(messageId, updated);
    }
  }

  void _onAvatarTap() {
    _clearFeedComposerFocus();
    Navigator.of(context)
        .push(
          buildSettingsSlideUpRoute(
            builder: (_) => SettingsWired(
              identityRepo: widget.repository,
              bridge: widget.bridge,
              contactRepo: widget.contactRepository,
              p2pService: widget.p2pService,
              secureKeyStore: widget.secureKeyStore,
              imageProcessor: widget.imageProcessor,
              appShellController: widget.appShellController,
              postsPrivacySettingsRepository:
                  widget.postsPrivacySettingsRepository,
              introductionRepository: widget.introductionRepository,
              nearbyLocationService: widget.nearbyLocationService,
            ),
          ),
        )
        .then((_) {
          _loadIdentity();
          _loadQualityPreference();
          _loadVideoQualityPreference();
        });
  }

  String get _activeTab => widget.appShellController.activeTab;

  String? get _visibleActiveFocusPeerId {
    final activeFocusPeerId = _activeFocusPeerId;
    if (activeFocusPeerId == null) {
      return null;
    }

    final hasVisibleThread = _feedItems.whereType<ThreadFeedItem>().any(
      (item) => item.contactPeerId == activeFocusPeerId,
    );
    return hasVisibleThread ? activeFocusPeerId : null;
  }

  void _clearFeedComposerFocus({bool notify = true}) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_activeFocusPeerId == null) {
      return;
    }

    if (!notify || !mounted) {
      _activeFocusPeerId = null;
      return;
    }

    setState(() {
      _activeFocusPeerId = null;
    });
  }

  void _onShellChanged() {
    if (!mounted) {
      return;
    }
    final activeTab = widget.appShellController.activeTab;
    if (activeTab != AppShellTab.feed) {
      _clearFeedComposerFocus(notify: false);
    }
    if (activeTab != AppShellTab.orbit) {
      _orbitReturnTab = activeTab;
    }
    if (activeTab == AppShellTab.orbit && !_orbitRouteOpen) {
      _openOrbitRoute();
      return;
    }
    setState(() {});
  }

  void _openOrbitRoute() {
    _orbitRouteOpen = true;

    Navigator.of(context)
        .push(
          buildOrbitSlideUpRoute(
            builder: (_) => OrbitWired(
              identityRepo: widget.repository,
              contactRepo: widget.contactRepository,
              contactRequestRepo: widget.contactRequestRepository,
              contactRequestListener: widget.contactRequestListener,
              messageRepo: widget.messageRepository,
              postRepository: widget.postRepository,
              mediaAttachmentRepo: widget.mediaAttachmentRepository,
              chatMessageListener: widget.chatMessageListener,
              bridge: widget.bridge,
              p2pService: widget.p2pService,
              mediaFileManager: widget.mediaFileManager,
              secureKeyStore: widget.secureKeyStore,
              imageProcessor: widget.imageProcessor,
              conversationTracker: widget.conversationTracker,
              audioRecorderService: widget.audioRecorderService,
              reactionRepository: widget.reactionRepository,
              reactionListener: widget.reactionListener,
              groupRepository: widget.groupRepository,
              groupMessageRepository: widget.groupMessageRepository,
              groupMessageListener: widget.groupMessageListener,
              groupInviteListener: widget.groupInviteListener,
              groupConversationTracker: widget.groupConversationTracker,
              introductionRepository: widget.introductionRepository,
              introductionListener: widget.introductionListener,
              appShellController: widget.appShellController,
              pendingPostTargetStore: widget.pendingPostTargetStore,
              postsPrivacySettingsRepository:
                  widget.postsPrivacySettingsRepository,
            ),
          ),
        )
        .then((result) {
          _orbitRouteOpen = false;
          if (widget.appShellController.activeTab == AppShellTab.orbit) {
            widget.appShellController.switchTo(_orbitReturnTab);
          }
          final changes = result is FeedRouteChanges ? result : null;
          unawaited(_applyRouteChanges(changes));
        });
  }

  void _onSwitchView(String tab) {
    widget.appShellController.switchTo(tab);
  }

  Future<void> _onUsernameChanged(String newUsername) async {
    final identity = _identity;
    if (identity == null) return;

    final updatedIdentity = IdentityModel(
      peerId: identity.peerId,
      publicKey: identity.publicKey,
      privateKey: identity.privateKey,
      mnemonic12: identity.mnemonic12,
      mlKemPublicKey: identity.mlKemPublicKey,
      mlKemSecretKey: identity.mlKemSecretKey,
      username: newUsername,
      avatarBlob: identity.avatarBlob,
      avatarVersion: identity.avatarVersion,
      createdAt: identity.createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    try {
      await widget.repository.saveIdentity(updatedIdentity);
      if (!mounted) return;

      setState(() {
        _identity = updatedIdentity;
        _username = newUsername;
      });

      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_USERNAME_UPDATED',
        details: {'username': newUsername},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_USERNAME_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.error_update_username),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onToggleExpand(String cardId) {
    // Find the card — could be 1:1 or group
    final cardItem = _feedItems
        .whereType<CardThreadFeedItem>()
        .where((t) => t.id == cardId)
        .firstOrNull;

    // Mark as read when collapsing an unread/active card
    if (cardItem != null &&
        _expandedCardId != cardId &&
        (cardItem.conversationState == ConversationState.unread ||
            cardItem.conversationState == ConversationState.active)) {
      if (cardItem is ThreadFeedItem) {
        markConversationRead(
          messageRepo: widget.messageRepository,
          contactPeerId: cardItem.contactPeerId,
        ).then((_) {
          if (mounted) {
            unawaited(_refreshContactFeedItem(cardItem.contactPeerId));
          }
        });
      } else if (cardItem is GroupThreadFeedItem) {
        widget.groupMessageRepository?.markAsRead(cardItem.groupId).then((_) {
          if (mounted) {
            unawaited(_refreshGroupFeedItem(cardItem.groupId));
          }
        });
      }
      // Ensure the resulting collapsed card is NOT expanded
      setState(() {
        _expandedCardId = null;
      });
      return;
    }

    // Clear active quote when collapsing the current card.
    if (_expandedCardId == cardId) {
      if (cardItem is ThreadFeedItem) {
        _activeQuoteMessageIds.remove(cardItem.contactPeerId);
      } else if (cardItem is GroupThreadFeedItem) {
        _activeQuoteMessageIds.remove(_groupQuoteKey(cardItem.groupId));
      }
    }

    // Clear session reply when expanding so expanded messages become visible
    if (_expandedCardId != cardId) {
      if (cardItem is ThreadFeedItem) {
        _sessionReplies.clear(cardItem.contactPeerId);
      } else if (cardItem is GroupThreadFeedItem) {
        _sessionReplies.clear('group:${cardItem.groupId}');
      }
    }

    setState(() {
      _expandedCardId = _expandedCardId == cardId ? null : cardId;
    });
  }

  void _onDraftChanged(String contactPeerId, String text) {
    if (text.isEmpty) {
      _draftTexts.remove(contactPeerId);
    } else {
      _draftTexts[contactPeerId] = text;
    }
  }

  void _onInputFocusChanged(String contactPeerId, bool hasFocus) {
    setState(() {
      _activeFocusPeerId = hasFocus ? contactPeerId : null;
    });
  }

  void _onQuoteReply(String contactPeerId, String messageId) {
    setState(() {
      _activeQuoteMessageIds[contactPeerId] = messageId;
    });
  }

  void _onClearQuote(String contactPeerId) {
    setState(() {
      _activeQuoteMessageIds.remove(contactPeerId);
    });
  }

  @override
  void dispose() {
    widget.appShellController.removeListener(_onShellChanged);
    _requestSubscription?.cancel();
    _chatSubscription?.cancel();
    _repoChangeSubscription?.cancel();
    _contactUpdateSubscription?.cancel();
    _reactionSubscription?.cancel();
    _groupReactionSubscription?.cancel();
    _groupMessageSubscription?.cancel();
    _introReceivedSubscription?.cancel();
    _introStatusSubscription?.cancel();
    _totalUnreadCountNotifier.dispose();
    _reactionStore.dispose();
    _feedStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = _activeTab;
    final activeFocusPeerId = _visibleActiveFocusPeerId;
    final body = FeedScreen(
      username: _username,
      userAvatarBytes: _avatarBytes,
      userPeerId: _peerId,
      feedItems: _feedItems,
      feedItemsListenable: _feedStore.itemsListenable,
      feedLoaded: _feedLoaded,
      onUsernameChanged: _onUsernameChanged,
      p2pService: widget.p2pService,
      onSwitchView: _onSwitchView,
      activeTab: activeTab,
      onSendMessage: _onSendMessage,
      onReplyToMessage: _onReplyToMessage,
      totalUnreadCountListenable: _totalUnreadCountNotifier,
      expandedCardId: _expandedCardId,
      onToggleExpand: _onToggleExpand,
      onInlineSend: _onInlineSend,
      onViewFullConversation: _onViewFullConversation,
      draftTexts: _draftTexts,
      activeFocusPeerId: activeFocusPeerId,
      onDraftChanged: _onDraftChanged,
      onInputFocusChanged: _onInputFocusChanged,
      activeQuoteMessageIds: _activeQuoteMessageIds,
      onQuoteReply: _onQuoteReply,
      onClearQuote: _onClearQuote,
      onAttach: _onAttach,
      onAvatarTap: _onAvatarTap,
      sessionReplies: _sessionReplies,
      reactionListenableForMessage: _reactionStore.listenableForMessage,
      onReactionSelected: _onReactionSelected,
      onGroupTap: _onGroupTap,
      onGroupInlineSend: _onGroupInlineSend,
      onGroupAttach: _onGroupAttach,
      onGroupReactionSelected: _onGroupReactionSelected,
    );

    return Scaffold(resizeToAvoidBottomInset: false, body: body);
  }
}
