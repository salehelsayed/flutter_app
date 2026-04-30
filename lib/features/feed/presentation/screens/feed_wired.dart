import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/gestures.dart';
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
import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
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
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
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
import 'package:flutter_app/features/feed/application/group_feed_media_verification.dart';
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
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/application/expire_old_introductions_use_case.dart';
import 'package:flutter_app/features/home/application/identity_avatar_resolver.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_reaction_details_sheet.dart';
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
    });

typedef DeleteMessageForMeFn =
    Future<int> Function({
      required ConversationMessage message,
      required MessageRepository messageRepo,
      ReactionRepository? reactionRepo,
      MediaAttachmentRepository? mediaAttachmentRepo,
      MediaFileManager? mediaFileManager,
    });

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
    });

/// Wired widget that connects FeedScreen to business logic.
///
/// Follows the same "Wired" pattern as FirstTimeExperienceWired.
/// Loads identity, builds feed items from the initial contact,
/// and listens for new incoming contact requests.
class FeedWired extends StatefulWidget {
  static const deleteSheetKey = ValueKey('feed-delete-message-sheet');
  static const deletePromptKey = ValueKey('feed-delete-message-prompt');
  static const deleteForMeKey = ValueKey('feed-delete-for-me-action');
  static const deleteForEveryoneKey = ValueKey(
    'feed-delete-for-everyone-action',
  );
  static const deleteCancelKey = ValueKey('feed-delete-cancel-action');

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
  final GroupReactionReplayOutboxRepository?
  groupReactionReplayOutboxRepository;
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
  final EditChatMessageFn editChatMessageFn;
  final DeleteMessageForMeFn deleteMessageForMeFn;
  final DeleteMessageForEveryoneFn deleteMessageForEveryoneFn;

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
    this.groupReactionReplayOutboxRepository,
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
    this.editChatMessageFn = editChatMessage,
    this.deleteMessageForMeFn = deleteMessageForMe,
    this.deleteMessageForEveryoneFn = deleteMessageForEveryone,
  });

  @override
  State<FeedWired> createState() => _FeedWiredState();
}

class _FeedWiredState extends State<FeedWired>
    with SingleTickerProviderStateMixin {
  static const _hostSwipeSettleDuration = Duration(milliseconds: 240);
  static const _hostSwipeDecisionThreshold = 12.0;
  static const _hostSwipeCompletionThreshold = 0.28;
  static const _hostSwipeVelocityThreshold = 900.0;

  String _username = 'Username';
  Uint8List? _avatarBytes;
  String? _peerId;
  IdentityModel? _identity;
  final FeedStore _feedStore = FeedStore();
  final ValueNotifier<int> _totalUnreadCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _orbitBadgeCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<FeedRouteChanges?> _mountedOrbitRouteChangesNotifier =
      ValueNotifier<FeedRouteChanges?>(null);
  final FeedReactionStore _reactionStore = FeedReactionStore();
  bool _feedLoaded = false;
  String? _expandedCardId;
  final Map<String, String> _draftTexts = {};
  final Map<String, String> _activeQuoteMessageIds = {};
  final SessionReplyTracker _sessionReplies = SessionReplyTracker();
  String? _activeFocusPeerId;
  String? _pendingViewportFollowContactPeerId;
  int _viewportFollowRequestId = 0;
  String? _editingContactPeerId;
  String? _editingMessageId;
  String? _editingOriginalText;
  StreamSubscription<ContactRequestModel>? _requestSubscription;
  StreamSubscription<ConversationMessage>? _chatSubscription;
  StreamSubscription<ConversationMessage>? _repoChangeSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;
  StreamSubscription<ReactionChange>? _reactionSubscription;
  StreamSubscription<dynamic>? _groupMessageSubscription;
  StreamSubscription<ReactionChange>? _groupReactionSubscription;
  StreamSubscription<GroupModel>? _groupInviteJoinedSubscription;
  StreamSubscription<PendingGroupInvite>? _pendingGroupInviteSubscription;
  StreamSubscription<IntroductionModel>? _introReceivedSubscription;
  StreamSubscription<IntroductionModel>? _introStatusSubscription;
  int _orbitBadgeLoadRequestId = 0;
  ImageQualityPreference _qualityPreference = ImageQualityPreference.compressed;
  ImageQualityPreference _videoQualityPreference =
      ImageQualityPreference.compressed;
  bool _hasMountedOrbitHost = false;
  late final AnimationController _hostSwipeController;
  VoidCallback? _orbitEmbeddedExitAction;
  bool _orbitRowActionOpen = false;
  double _hostViewportWidth = 0;
  int? _hostSwipePointer;
  Offset? _hostSwipeStartPosition;
  String? _hostSwipeStartTab;
  bool _hostSwipeResolved = false;
  bool _hostSwipeClaimed = false;
  VelocityTracker? _hostSwipeVelocityTracker;

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

  bool _isEditingContact(String contactPeerId) =>
      _editingContactPeerId == contactPeerId && _editingMessageId != null;

  void _clearEditState({
    String? contactPeerId,
    bool clearDraft = false,
    bool clearFocus = false,
  }) {
    final targetContactPeerId = contactPeerId ?? _editingContactPeerId;
    if (clearDraft && targetContactPeerId != null) {
      _draftTexts.remove(targetContactPeerId);
    }
    if (clearFocus &&
        targetContactPeerId != null &&
        _activeFocusPeerId == targetContactPeerId) {
      _activeFocusPeerId = null;
    }
    _editingContactPeerId = null;
    _editingMessageId = null;
    _editingOriginalText = null;
  }

  Future<void> _onEditMessage(String contactPeerId, String messageId) async {
    final message = await widget.messageRepository.getMessage(messageId);
    if (!mounted ||
        message == null ||
        message.isIncoming ||
        message.text.trim().isEmpty) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _sessionReplies.clear(contactPeerId);
      _activeQuoteMessageIds.remove(contactPeerId);
      _editingContactPeerId = contactPeerId;
      _editingMessageId = message.id;
      _editingOriginalText = message.text;
      _draftTexts[contactPeerId] = message.text;
      _activeFocusPeerId = contactPeerId;
    });
  }

  void _onCancelEdit(String contactPeerId) {
    if (!mounted || !_isEditingContact(contactPeerId)) return;
    setState(() {
      _clearEditState(
        contactPeerId: contactPeerId,
        clearDraft: true,
        clearFocus: true,
      );
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _onDeleteMessage(String contactPeerId, String messageId) async {
    if (!mounted) return;
    final message = await widget.messageRepository.getMessage(messageId);
    if (message == null || message.isDeleted) return;

    final action = await _showDeleteMessageSheet(
      canDeleteForEveryone: _canDeleteForEveryone(message),
    );
    if (!mounted || action == null || action == _DeleteMessageAction.cancel) {
      return;
    }

    setState(() {
      if (_editingContactPeerId == contactPeerId &&
          _editingMessageId == messageId) {
        _clearEditState(
          contactPeerId: contactPeerId,
          clearDraft: true,
          clearFocus: true,
        );
      }
      if (_activeQuoteMessageIds[contactPeerId] == messageId) {
        _activeQuoteMessageIds.remove(contactPeerId);
      }
    });
    FocusManager.instance.primaryFocus?.unfocus();

    if (action == _DeleteMessageAction.forMe) {
      final deleted = await widget.deleteMessageForMeFn(
        message: message,
        messageRepo: widget.messageRepository,
        reactionRepo: widget.reactionRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      if (deleted > 0) {
        await _refreshContactFeedItem(contactPeerId);
      }
      return;
    }

    final contact = await widget.contactRepository.getContact(contactPeerId);
    final (result, updatedMessage) = await widget.deleteMessageForEveryoneFn(
      p2pService: widget.p2pService,
      messageRepo: widget.messageRepository,
      originalMessage: message,
      reactionRepo: widget.reactionRepository,
      mediaAttachmentRepo: widget.mediaAttachmentRepository,
      mediaFileManager: widget.mediaFileManager,
      bridge: widget.bridge,
      recipientMlKemPublicKey: contact?.mlKemPublicKey,
    );

    if (!mounted) return;
    if (updatedMessage != null) {
      await _refreshContactFeedItem(contactPeerId);
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

  bool _canDeleteForEveryone(ConversationMessage message) {
    final ownPeerId = _identity?.peerId;
    if (ownPeerId == null) return false;
    if (message.isIncoming || message.isDeleted) return false;
    if (message.senderPeerId != ownPeerId) return false;
    return message.status == 'delivered';
  }

  Future<_DeleteMessageAction?> _showDeleteMessageSheet({
    required bool canDeleteForEveryone,
  }) {
    return showModalBottomSheet<_DeleteMessageAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) =>
          _DeleteMessageSheet(canDeleteForEveryone: canDeleteForEveryone),
    );
  }

  void _syncComposerStateForContact(
    String contactPeerId,
    Set<String> visibleMessageIds,
  ) {
    var didChange = false;

    if (_editingContactPeerId == contactPeerId &&
        _editingMessageId != null &&
        !visibleMessageIds.contains(_editingMessageId)) {
      _clearEditState(
        contactPeerId: contactPeerId,
        clearDraft: true,
        clearFocus: true,
      );
      didChange = true;
    }

    final activeQuoteId = _activeQuoteMessageIds[contactPeerId];
    if (activeQuoteId != null && !visibleMessageIds.contains(activeQuoteId)) {
      _activeQuoteMessageIds.remove(contactPeerId);
      didChange = true;
    }

    if (didChange && mounted) {
      setState(() {});
    }
  }

  void _markFeedLoaded() {
    if (_feedLoaded || !mounted) return;
    setState(() => _feedLoaded = true);
  }

  @override
  void initState() {
    super.initState();
    _hasMountedOrbitHost = _activeTab == AppShellTab.orbit;
    _hostSwipeController = AnimationController(
      vsync: this,
      duration: _hostSwipeSettleDuration,
      value: _hasMountedOrbitHost ? 1.0 : 0.0,
    );
    widget.appShellController.addListener(_onShellChanged);
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_FL_SCREEN_INIT',
      details: {'introRepoNull': widget.introductionRepository == null},
    );
    _loadIdentity();
    _loadBackgroundPreference();
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
    _startListeningForGroupInvites();
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
      unawaited(_refreshOrbitBadgeCount());
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

  Future<void> _loadBackgroundPreference() async {
    final pref = await loadBackgroundPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      widget.appShellController.setBackgroundPreference(pref);
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

  Future<void> _refreshOrbitBadgeCount() async {
    final introRepo = widget.introductionRepository;
    final ownPeerId = _peerId;
    final pendingInviteRepo = widget.groupInviteListener?.pendingInviteRepo;
    if ((introRepo == null || ownPeerId == null) && pendingInviteRepo == null) {
      if (mounted) {
        _orbitBadgeCountNotifier.value = 0;
      }
      return;
    }

    final requestId = ++_orbitBadgeLoadRequestId;

    try {
      var introCount = 0;
      if (introRepo != null && ownPeerId != null) {
        await expireOldIntroductions(
          introRepo: introRepo,
          peerId: ownPeerId,
          contactRepo: widget.contactRepository,
          messageRepo: widget.messageRepository,
          bridge: widget.bridge,
        );
        introCount = await introRepo.countPendingIntroductions(ownPeerId);
      }

      var pendingInviteCount = 0;
      if (pendingInviteRepo != null) {
        pendingInviteCount =
            (await pendingInviteRepo.getPendingInvites()).length;
      }

      if (!mounted || requestId != _orbitBadgeLoadRequestId) {
        return;
      }
      _orbitBadgeCountNotifier.value = introCount + pendingInviteCount;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_ORBIT_BADGE_COUNT_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _startListeningForGroupInvites() {
    final listener = widget.groupInviteListener;
    if (listener == null) return;

    _groupInviteJoinedSubscription = listener.groupJoinedStream.listen(
      (_) => unawaited(_refreshOrbitBadgeCount()),
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_GROUP_INVITE_JOINED_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );

    _pendingGroupInviteSubscription = listener.pendingInviteStream.listen(
      (_) => unawaited(_refreshOrbitBadgeCount()),
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_PENDING_GROUP_INVITE_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
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
      _syncComposerStateForContact(contactPeerId, nextMessageIds);

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
    String messageId, {
    bool requireGroupMediaIntegrity = false,
  }) async {
    final attachments = await widget.mediaAttachmentRepository
        .getAttachmentsForMessage(messageId);
    if (attachments.isEmpty) return const <MediaAttachment>[];

    if (requireGroupMediaIntegrity) {
      return resolveGroupFeedMediaForDisplay(
        attachments: attachments,
        mediaFileManager: widget.mediaFileManager,
      );
    }

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
      isUnread:
          !message.isDeleted && message.isIncoming && message.readAt == null,
      isIncoming: message.isIncoming,
      isDeleted: message.isDeleted,
      status: message.isIncoming ? null : message.status,
      editedAt: message.editedAt,
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
      (message) => message.isIncoming && message.isUnread && !message.isDeleted,
    );
    final hasSentMessages = messages.any(
      (message) => !message.isIncoming && !message.isDeleted,
    );
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
      if (!message.isIncoming && !message.isDeleted) {
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
      unreadCount: messages
          .where((message) => message.isUnread && !message.isDeleted)
          .length,
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
      isDissolved: group.isDissolved,
      avatarPath: group.avatarPath,
      avatarCacheBustKey:
          group.lastMetadataEventAt?.toUtc().toIso8601String() ??
          group.avatarBlobId,
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
      if (message.isHidden) {
        await _refreshContactFeedItem(
          message.contactPeerId,
          refreshUnreadCount: refreshUnreadCount,
        );
        return;
      }

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
        media: message.isDeleted
            ? const <MediaAttachment>[]
            : await _loadResolvedAttachmentsForMessage(message.id),
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

      if (displayMessage.isDeleted) {
        _reactionStore.clearMessageIds({displayMessage.id});
      }

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
        media: await _loadResolvedAttachmentsForMessage(
          message.id,
          requireGroupMediaIntegrity: true,
        ),
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

    if (changes.refreshPendingIntroductions) {
      await _refreshOrbitBadgeCount();
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
              !message.isIncoming && _shouldProcessRepositoryChange(message),
        )
        .listen(
          (message) {
            if (!mounted) return;
            if (message.isDeleted || message.isHidden) {
              unawaited(
                _refreshContactFeedItem(
                  message.contactPeerId,
                  refreshUnreadCount: false,
                ),
              );
              return;
            }
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

  bool _shouldProcessRepositoryChange(ConversationMessage message) =>
      message.isDeleted ||
      message.isHidden ||
      _shouldRefreshFromRepositoryChange(message.status);

  bool _shouldRefreshFromRepositoryChange(String status) =>
      status == 'sent' || status == 'delivered' || status == 'failed';

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
              appShellController: widget.appShellController,
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
              appShellController: widget.appShellController,
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
    final sanitizedText = sanitizeMessageText(text);
    final editingMessageId = _isEditingContact(contactPeerId)
        ? _editingMessageId
        : null;

    if (editingMessageId != null) {
      final editingMessage = await widget.messageRepository.getMessage(
        editingMessageId,
      );
      if (!mounted || editingMessage == null || editingMessage.isIncoming) {
        if (mounted) {
          setState(() {
            _clearEditState(
              contactPeerId: contactPeerId,
              clearDraft: true,
              clearFocus: true,
            );
          });
        }
        return;
      }

      final originalText = sanitizeMessageText(
        _editingOriginalText ?? editingMessage.text,
      );
      if (sanitizedText == originalText) {
        if (!mounted) return;
        setState(() {
          _clearEditState(
            contactPeerId: contactPeerId,
            clearDraft: true,
            clearFocus: true,
          );
        });
        return;
      }

      final contact = await widget.contactRepository.getContact(contactPeerId);
      if (contact == null || !mounted) {
        if (mounted) {
          setState(() {
            _clearEditState(
              contactPeerId: contactPeerId,
              clearDraft: true,
              clearFocus: true,
            );
          });
        }
        return;
      }

      final bgTaskId = await callBgBegin(widget.bridge);
      try {
        final (result, message) = await widget.editChatMessageFn(
          p2pService: widget.p2pService,
          messageRepo: widget.messageRepository,
          originalMessage: editingMessage,
          updatedText: sanitizedText,
          senderUsername: identity.username,
          bridge: widget.bridge,
          recipientMlKemPublicKey: contact.mlKemPublicKey,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
        );

        if (!mounted) return;

        setState(() {
          _clearEditState(
            contactPeerId: contactPeerId,
            clearDraft: true,
            clearFocus: true,
          );
        });

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

        if (result != SendChatMessageResult.success && message == null) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Failed to save edit.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_FL_EDIT_SEND_ERROR',
          details: {'error': e.toString(), 'contactPeerId': contactPeerId},
        );
        if (!mounted) return;
        setState(() {
          _clearEditState(
            contactPeerId: contactPeerId,
            clearDraft: true,
            clearFocus: true,
          );
        });
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to save edit.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } finally {
        await callBgEnd(widget.bridge, bgTaskId);
      }
      return;
    }

    // Optimistic: show session reply immediately before network send.
    final quotedMsgId = _activeQuoteMessageIds[contactPeerId];
    final draftText = text;
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
        await _refreshContactFeedItem(contactPeerId, refreshUnreadCount: false);
        if (mounted) {
          setState(() {
            _pendingViewportFollowContactPeerId = contactPeerId;
            _viewportFollowRequestId++;
          });
        }
        _notifyMountedOrbitContactChange(contactPeerId);
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
                appShellController: widget.appShellController,
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

    _introReceivedSubscription = listener.introReceivedStream.listen(
      (_) => unawaited(_refreshOrbitBadgeCount()),
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_INTRO_RECEIVED_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );

    _introStatusSubscription = listener.introStatusChangedStream.listen(
      (intro) {
        unawaited(_refreshOrbitBadgeCount());
        final ownPeerId = _peerId;
        if (!mounted || ownPeerId == null) return;
        if (intro.status != IntroductionOverallStatus.mutualAccepted) return;

        final otherPeerId = intro.recipientId == ownPeerId
            ? intro.introducedId
            : intro.recipientId;
        if (otherPeerId.isEmpty) return;

        unawaited(_refreshContactFeedItem(otherPeerId));
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_INTRO_STATUS_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
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
      isDissolved: groupThread.isDissolved,
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
              groupReactionReplayOutboxRepository:
                  widget.groupReactionReplayOutboxRepository,
              initialPendingMedia: initialPendingMedia,
              initialAttachments: initialAttachments,
              backgroundPreference:
                  widget.appShellController.backgroundPreference,
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
    String? bgTaskId;

    try {
      bgTaskId = await callBgBegin(widget.bridge);
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
    } finally {
      await callBgEnd(widget.bridge, bgTaskId);
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
    final reactionReplayOutboxRepo = widget.groupReactionReplayOutboxRepository;
    if (reactionRepo == null ||
        groupRepo == null ||
        msgRepo == null ||
        reactionReplayOutboxRepo == null) {
      return;
    }

    // Check if toggling (same emoji from same user)
    final currentReactions = _reactionStore.reactionsForMessage(messageId);
    final previousReactions = List<MessageReaction>.from(currentReactions);
    final ownReaction = currentReactions
        .where((r) => r.senderPeerId == identity.peerId)
        .firstOrNull;

    if (ownReaction != null && ownReaction.emoji == emoji) {
      // Toggle off: remove reaction optimistically
      final updated = currentReactions
          .where((r) => r.senderPeerId != identity.peerId)
          .toList();
      _reactionStore.setMessageReactions(messageId, updated);

      final result = await removeGroupReaction(
        bridge: widget.bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: groupId,
        messageId: messageId,
        emoji: emoji,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
      );
      if (result == RemoveGroupReactionResult.groupDissolved) {
        await _restoreGroupReactionStateAfterDissolve(
          groupId: groupId,
          messageId: messageId,
          previousReactions: previousReactions,
        );
      }
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
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
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
    } else if (result == SendGroupReactionResult.groupDissolved) {
      await _restoreGroupReactionStateAfterDissolve(
        groupId: groupId,
        messageId: messageId,
        previousReactions: previousReactions,
      );
    }
  }

  Future<void> _restoreGroupReactionStateAfterDissolve({
    required String groupId,
    required String messageId,
    required List<MessageReaction> previousReactions,
  }) async {
    _reactionStore.setMessageReactions(messageId, previousReactions);
    await _refreshGroupFeedItem(groupId);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('This group has been dissolved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _onGroupReactionTap(
    String groupId,
    String messageId,
    String emoji,
  ) async {
    final groupRepo = widget.groupRepository;
    if (groupRepo == null) return;
    final msgRepo = widget.groupMessageRepository;
    final reactions = _reactionStore.reactionsForMessage(messageId);
    final usernameHintsByPeerId = await loadGroupReactionUsernameHints(
      peerIds: reactions.map((reaction) => reaction.senderPeerId),
      contactRepo: widget.contactRepository,
      groupId: groupId,
      msgRepo: msgRepo,
    );

    final participants = buildGroupReactionParticipantEntries(
      reactions: reactions,
      emoji: emoji,
      members: await groupRepo.getMembers(groupId),
      usernameHintsByPeerId: usernameHintsByPeerId,
      ownPeerId: _peerId,
    );
    if (!mounted || participants.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141A24),
      showDragHandle: false,
      builder: (_) =>
          GroupReactionDetailsSheet(emoji: emoji, participants: participants),
    );
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
          _loadBackgroundPreference();
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

  void _ensureOrbitHostMounted() {
    if (_hasMountedOrbitHost || !mounted) {
      return;
    }
    setState(() {
      _hasMountedOrbitHost = true;
    });
  }

  void _animateHostTo(double target) {
    final normalizedTarget = target.clamp(0.0, 1.0);
    if ((_hostSwipeController.value - normalizedTarget).abs() < 0.0001) {
      _hostSwipeController.value = normalizedTarget;
      return;
    }

    _hostSwipeController.stop();
    _hostSwipeController.animateTo(
      normalizedTarget,
      duration: _hostSwipeSettleDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _registerOrbitEmbeddedExitAction(VoidCallback? action) {
    _orbitEmbeddedExitAction = action;
  }

  void _onOrbitRowActionOpenChanged(bool isOpen) {
    _orbitRowActionOpen = isOpen;
  }

  void _resetHostSwipeTracking() {
    _hostSwipePointer = null;
    _hostSwipeStartPosition = null;
    _hostSwipeStartTab = null;
    _hostSwipeResolved = false;
    _hostSwipeClaimed = false;
    _hostSwipeVelocityTracker = null;
  }

  void _onHostPointerDown(PointerDownEvent event) {
    if (_hostSwipePointer != null) {
      return;
    }

    _hostSwipePointer = event.pointer;
    _hostSwipeStartPosition = event.position;
    _hostSwipeStartTab = _activeTab;
    _hostSwipeResolved = false;
    _hostSwipeClaimed = false;
    _hostSwipeVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _onHostPointerMove(PointerMoveEvent event) {
    if (event.pointer != _hostSwipePointer || _hostSwipeStartPosition == null) {
      return;
    }

    _hostSwipeVelocityTracker?.addPosition(event.timeStamp, event.position);
    final totalDelta = event.position - _hostSwipeStartPosition!;
    if (!_hostSwipeResolved) {
      if (totalDelta.distance < _hostSwipeDecisionThreshold) {
        return;
      }

      _hostSwipeResolved = true;
      if (totalDelta.dx.abs() <= totalDelta.dy.abs()) {
        return;
      }

      final startingTab = _hostSwipeStartTab ?? _activeTab;
      final movingToOrbit =
          startingTab == AppShellTab.feed && totalDelta.dx < 0;
      final movingToFeed =
          startingTab == AppShellTab.orbit && totalDelta.dx > 0;
      final blockedByOrbitRow =
          startingTab == AppShellTab.orbit && _orbitRowActionOpen;
      if ((!movingToOrbit && !movingToFeed) || blockedByOrbitRow) {
        return;
      }

      _hostSwipeClaimed = true;
      if (startingTab == AppShellTab.feed) {
        _ensureOrbitHostMounted();
        _clearFeedComposerFocus();
      }
    }

    if (!_hostSwipeClaimed || _hostViewportWidth <= 0) {
      return;
    }

    final startingTab = _hostSwipeStartTab ?? _activeTab;
    final traveledDistance = switch (startingTab) {
      AppShellTab.feed => (-totalDelta.dx).clamp(0.0, _hostViewportWidth),
      AppShellTab.orbit => totalDelta.dx.clamp(0.0, _hostViewportWidth),
      _ => 0.0,
    };
    final progress = traveledDistance / _hostViewportWidth;

    _hostSwipeController.stop();
    _hostSwipeController.value = switch (startingTab) {
      AppShellTab.feed => progress,
      AppShellTab.orbit => 1.0 - progress,
      _ => _hostSwipeController.value,
    };
  }

  void _finishHostSwipe() {
    if (!_hostSwipeClaimed) {
      _resetHostSwipeTracking();
      return;
    }

    final velocity =
        _hostSwipeVelocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0.0;
    final startingTab = _hostSwipeStartTab ?? _activeTab;
    final progressTowardTarget = switch (startingTab) {
      AppShellTab.feed => _hostSwipeController.value,
      AppShellTab.orbit => 1.0 - _hostSwipeController.value,
      _ => 0.0,
    };
    final shouldComplete =
        progressTowardTarget >= _hostSwipeCompletionThreshold ||
        (startingTab == AppShellTab.feed &&
            velocity <= -_hostSwipeVelocityThreshold) ||
        (startingTab == AppShellTab.orbit &&
            velocity >= _hostSwipeVelocityThreshold);

    _resetHostSwipeTracking();

    if (!shouldComplete) {
      _animateHostTo(startingTab == AppShellTab.orbit ? 1.0 : 0.0);
      return;
    }

    if (startingTab == AppShellTab.feed) {
      widget.appShellController.switchTo(AppShellTab.orbit);
      return;
    }

    final orbitExitAction = _orbitEmbeddedExitAction;
    if (orbitExitAction != null) {
      orbitExitAction();
      return;
    }
    widget.appShellController.switchTo(AppShellTab.feed);
  }

  void _onHostPointerUp(PointerUpEvent event) {
    if (event.pointer != _hostSwipePointer) {
      return;
    }
    _hostSwipeVelocityTracker?.addPosition(event.timeStamp, event.position);
    _finishHostSwipe();
  }

  void _onHostPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _hostSwipePointer) {
      return;
    }

    final startingTab = _hostSwipeStartTab ?? _activeTab;
    final claimed = _hostSwipeClaimed;
    _resetHostSwipeTracking();
    if (claimed) {
      _animateHostTo(startingTab == AppShellTab.orbit ? 1.0 : 0.0);
    }
  }

  void _onShellChanged() {
    if (!mounted) {
      return;
    }
    final activeTab = widget.appShellController.activeTab;
    if (activeTab != AppShellTab.feed) {
      _clearFeedComposerFocus(notify: false);
    }
    setState(() {
      _hasMountedOrbitHost =
          _hasMountedOrbitHost || activeTab == AppShellTab.orbit;
    });
    _animateHostTo(activeTab == AppShellTab.orbit ? 1.0 : 0.0);
  }

  void _onSwitchView(String tab) {
    widget.appShellController.switchTo(tab);
  }

  void _onOrbitEmbeddedExit(FeedRouteChanges? changes) {
    unawaited(_applyRouteChanges(changes));
  }

  void _notifyMountedOrbitContactChange(String contactPeerId) {
    if (!_hasMountedOrbitHost) return;
    _mountedOrbitRouteChangesNotifier.value = FeedRouteChanges(
      changedContactPeerIds: {contactPeerId},
    );
  }

  Widget _buildOrbitHost() {
    return OrbitWired(
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
      groupReactionReplayOutboxRepository:
          widget.groupReactionReplayOutboxRepository,
      groupMessageListener: widget.groupMessageListener,
      groupInviteListener: widget.groupInviteListener,
      groupConversationTracker: widget.groupConversationTracker,
      introductionRepository: widget.introductionRepository,
      introductionListener: widget.introductionListener,
      appShellController: widget.appShellController,
      feedUnreadCountListenable: _totalUnreadCountNotifier,
      pendingPostTargetStore: widget.pendingPostTargetStore,
      postsPrivacySettingsRepository: widget.postsPrivacySettingsRepository,
      externalRouteChangesListenable: _mountedOrbitRouteChangesNotifier,
      initialFilterTab: null,
      onEmbeddedExit: _onOrbitEmbeddedExit,
      onEmbeddedExitActionChanged: _registerOrbitEmbeddedExitAction,
      onRowActionOpenChanged: _onOrbitRowActionOpenChanged,
    );
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
            _notifyMountedOrbitContactChange(cardItem.contactPeerId);
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
      if (!contactPeerId.startsWith('group:') &&
          _isEditingContact(contactPeerId)) {
        _clearEditState(contactPeerId: contactPeerId);
      }
      _activeQuoteMessageIds[contactPeerId] = messageId;
      _activeFocusPeerId = contactPeerId.startsWith('group:')
          ? null
          : contactPeerId;
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
    _groupInviteJoinedSubscription?.cancel();
    _pendingGroupInviteSubscription?.cancel();
    _introReceivedSubscription?.cancel();
    _introStatusSubscription?.cancel();
    _hostSwipeController.dispose();
    _totalUnreadCountNotifier.dispose();
    _orbitBadgeCountNotifier.dispose();
    _mountedOrbitRouteChangesNotifier.dispose();
    _reactionStore.dispose();
    _feedStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = _activeTab;
    final activeFocusPeerId = _visibleActiveFocusPeerId;
    final feedBody = FeedScreen(
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
      orbitBadgeCountListenable: _orbitBadgeCountNotifier,
      expandedCardId: _expandedCardId,
      onToggleExpand: _onToggleExpand,
      onInlineSend: _onInlineSend,
      onViewFullConversation: _onViewFullConversation,
      draftTexts: _draftTexts,
      activeFocusPeerId: activeFocusPeerId,
      pendingViewportFollowContactPeerId: _pendingViewportFollowContactPeerId,
      viewportFollowRequestId: _viewportFollowRequestId,
      onDraftChanged: _onDraftChanged,
      onInputFocusChanged: _onInputFocusChanged,
      editingContactPeerId: _editingContactPeerId,
      onEditMessage: _onEditMessage,
      onDeleteMessage: _onDeleteMessage,
      onCancelEdit: _onCancelEdit,
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
      onGroupReactionTap: _onGroupReactionTap,
      onGroupReactionSelected: _onGroupReactionSelected,
      backgroundPreference: widget.appShellController.backgroundPreference,
    );
    final orbitBody = _hasMountedOrbitHost
        ? _buildOrbitHost()
        : const SizedBox.shrink();
    final body = LayoutBuilder(
      builder: (context, constraints) {
        _hostViewportWidth = constraints.maxWidth;

        return Listener(
          key: const ValueKey<String>('feed-orbit-swipe-host'),
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onHostPointerDown,
          onPointerMove: _onHostPointerMove,
          onPointerUp: _onHostPointerUp,
          onPointerCancel: _onHostPointerCancel,
          child: AnimatedBuilder(
            animation: _hostSwipeController,
            builder: (context, child) {
              final hostProgress = _hostSwipeController.value.clamp(0.0, 1.0);
              final feedOffset = -hostProgress * constraints.maxWidth;
              final orbitOffset = (1.0 - hostProgress) * constraints.maxWidth;

              return ClipRect(
                child: Stack(
                  children: [
                    Transform.translate(
                      offset: Offset(feedOffset, 0),
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: feedBody,
                      ),
                    ),
                    if (_hasMountedOrbitHost)
                      Transform.translate(
                        offset: Offset(orbitOffset, 0),
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: orbitBody,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    return Scaffold(resizeToAvoidBottomInset: false, body: body);
  }
}

enum _DeleteMessageAction { forMe, forEveryone, cancel }

class _DeleteMessageSheet extends StatelessWidget {
  final bool canDeleteForEveryone;

  const _DeleteMessageSheet({required this.canDeleteForEveryone});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final maxHeight = MediaQuery.of(context).size.height * 0.72;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              key: FeedWired.deleteSheetKey,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(18, 20, 28, 0.96),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: const Color.fromRGBO(255, 255, 255, 0.10),
                ),
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
                            color: const Color.fromRGBO(255, 255, 255, 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        l10n.conversation_delete_message_prompt,
                        key: FeedWired.deletePromptKey,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color.fromRGBO(255, 255, 255, 0.94),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DeleteSheetAction(
                        key: FeedWired.deleteForMeKey,
                        label: l10n.conversation_delete_for_me,
                        icon: Icons.delete_outline_rounded,
                        color: const Color(0xFFFF8A80),
                        onTap: () => Navigator.of(
                          context,
                        ).pop(_DeleteMessageAction.forMe),
                      ),
                      if (canDeleteForEveryone) ...[
                        const SizedBox(height: 10),
                        _DeleteSheetAction(
                          key: FeedWired.deleteForEveryoneKey,
                          label: l10n.conversation_delete_for_everyone,
                          icon: Icons.person_remove_alt_1_rounded,
                          color: const Color(0xFFFFB38A),
                          onTap: () => Navigator.of(
                            context,
                          ).pop(_DeleteMessageAction.forEveryone),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _DeleteSheetAction(
                        key: FeedWired.deleteCancelKey,
                        label: l10n.conversation_delete_cancel,
                        icon: Icons.close_rounded,
                        color: const Color.fromRGBO(255, 255, 255, 0.72),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color.fromRGBO(255, 255, 255, 0.04),
            border: Border.all(
              color: const Color.fromRGBO(255, 255, 255, 0.06),
            ),
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
                    fontWeight: FontWeight.w500,
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
