import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
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
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/application/load_reactions_use_case.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/remove_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
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
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_wired.dart';
import 'package:flutter_app/features/orbit/presentation/navigation/orbit_route_transition.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/settings/presentation/navigation/settings_route_transition.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';
import 'feed_screen.dart';

enum _MediaSource { gallery, camera, videoCamera }

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

  const FeedWired({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.messageRepository,
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
  });

  @override
  State<FeedWired> createState() => _FeedWiredState();
}

class _FeedWiredState extends State<FeedWired> {
  String _username = 'Username';
  Uint8List? _avatarBytes;
  String? _peerId;
  IdentityModel? _identity;
  String _activeTab = 'feed';
  final FeedStore _feedStore = FeedStore();
  final FeedReactionStore _reactionStore = FeedReactionStore();
  bool _feedLoaded = false;
  int _totalUnreadCount = 0;
  String? _expandedCardId;
  final Map<String, String> _draftTexts = {};
  final Map<String, String> _activeQuoteMessageIds = {};
  final SessionReplyTracker _sessionReplies = SessionReplyTracker();
  String? _activeFocusPeerId;
  StreamSubscription<ContactRequestModel>? _requestSubscription;
  StreamSubscription<ConversationMessage>? _chatSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;
  StreamSubscription<ReactionChange>? _reactionSubscription;
  StreamSubscription<dynamic>? _groupMessageSubscription;
  StreamSubscription<IntroductionModel>? _introReceivedSubscription;
  StreamSubscription<IntroductionModel>? _introStatusSubscription;
  ImageQualityPreference _qualityPreference = ImageQualityPreference.compressed;
  ImageQualityPreference _videoQualityPreference =
      ImageQualityPreference.compressed;

  List<FeedItem> get _feedItems => _feedStore.items;

  @override
  void initState() {
    super.initState();
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
    _startListeningForContactUpdates();
    _startListeningForReactions();
    _startListeningForGroupMessages();
    _startListeningForIntroductions();
  }

  void _loadIdentity() async {
    try {
      final identity = await widget.repository.loadIdentity();
      if (identity == null || !mounted) return;

      // Load file-based avatar if avatarVersion is set
      Uint8List? avatarBytes = identity.avatarBlob;
      if (identity.avatarVersion != null) {
        try {
          final appDir = await getApplicationDocumentsDirectory();
          final avatarFile = File(
            p.join(appDir.path, 'media', 'avatars', '${identity.peerId}.jpg'),
          );
          if (avatarFile.existsSync()) {
            avatarBytes = await avatarFile.readAsBytes();
          }
        } catch (_) {}
      }

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

      setState(() {
        _feedStore.replaceAll(items);
        _feedLoaded = true;
      });
      _loadReactionsForFeed();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_DB_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadTotalUnreadCount() async {
    try {
      final count = await widget.messageRepository
          .getTotalUnreadCountExcludingArchived();
      if (!mounted) return;
      setState(() => _totalUnreadCount = count);
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

      setState(() {
        _feedStore.replaceContactSnapshot(
          contactPeerId: contactPeerId,
          connectionItem: snapshot.connectionItem,
          threadItem: snapshot.threadItem,
        );
        _feedLoaded = true;
      });
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
      );
      if (!mounted) return;

      setState(() {
        _feedStore.replaceGroupSnapshot(
          groupId: groupId,
          threadItem: threadItem,
        );
        _feedLoaded = true;
      });
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

      setState(() {
        _feedStore.replaceContacts(contactItems);
        _feedLoaded = true;
      });
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
      );
      if (!mounted) return;

      setState(() {
        _feedStore.replaceGroups(groupItems);
        _feedLoaded = true;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_GROUP_SECTION_REFRESH_ERROR',
        details: {'error': e.toString()},
      );
      await _refreshFeed();
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
        setState(() {
          _feedStore.upsertConnection(item);
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to add contact. Please try again.'),
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

  void _onIncomingChatMessage(ConversationMessage message) {
    if (!mounted) return;
    _sessionReplies.clear(message.contactPeerId);
    unawaited(_refreshContactFeedItem(message.contactPeerId));
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
    unawaited(_refreshContactFeedItem(contact.peerId));
  }

  void _onSendMessage(ConnectionFeedItem item) async {
    final contact = await widget.contactRepository.getContact(
      item.contactPeerId,
    );
    if (contact == null || !mounted) return;

    await markConversationRead(
      messageRepo: widget.messageRepository,
      contactPeerId: item.contactPeerId,
    );

    if (!mounted) return;

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
    final results = await Future.wait([
      widget.contactRepository.getContact(contactPeerId),
      loadConversation(
        messageRepo: widget.messageRepository,
        contactPeerId: contactPeerId,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      ),
    ]);

    final contact = results[0] as ContactModel?;
    final messages = results[1] as List<ConversationMessage>;
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
              initialMessages: messages,
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

    try {
      final contact = await widget.contactRepository.getContact(contactPeerId);
      if (contact == null || !mounted) return;

      final quotedMsgId = _activeQuoteMessageIds[contactPeerId];
      final (result, _) = await sendChatMessage(
        p2pService: widget.p2pService,
        messageRepo: widget.messageRepository,
        targetPeerId: contactPeerId,
        text: text,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        bridge: widget.bridge,
        recipientMlKemPublicKey: contact.mlKemPublicKey,
        quotedMessageId: quotedMsgId,
      );

      if (!mounted) return;

      if (result == SendChatMessageResult.success) {
        _draftTexts.remove(contactPeerId);
        _activeQuoteMessageIds.remove(contactPeerId);
        _sessionReplies.track(contactPeerId, SessionReply.justNow(text));
        // Mark as read on successful inline reply
        await markConversationRead(
          messageRepo: widget.messageRepository,
          contactPeerId: contactPeerId,
        );
        await _refreshContactFeedItem(contactPeerId);
      } else {
        final errorText = result == SendChatMessageResult.encryptionRequired
            ? 'Cannot send: contact does not support encryption.'
            : 'Message failed to send. Try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorText),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_INLINE_SEND_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message failed to send. Try again.'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onViewFullConversation(String contactPeerId) {
    _onReplyToMessage(contactPeerId);
  }

  void _onAttach(String contactPeerId) {
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
      List<File> files;

      switch (source) {
        case _MediaSource.camera:
          final picked = await picker.pickImage(source: ImageSource.camera);
          if (picked == null || !mounted) return;
          final path = await _processMediaPath(picked.path);
          files = [File(path)];
        case _MediaSource.videoCamera:
          final picked = await picker.pickVideo(source: ImageSource.camera);
          if (picked == null || !mounted) return;
          _showProcessingSnackBar();
          final path = await _processMediaPath(picked.path);
          if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
          files = [File(path)];
        case _MediaSource.gallery:
          final picked = await picker.pickMultipleMedia();
          if (picked.isEmpty || !mounted) return;
          final hasVideo = picked.any(
            (xf) => widget.imageProcessor.isProcessableVideo(xf.path),
          );
          if (hasVideo) _showProcessingSnackBar();
          final processedFiles = <File>[];
          for (final xf in picked) {
            final path = await _processMediaPath(xf.path);
            processedFiles.add(File(path));
          }
          if (hasVideo && mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
          files = processedFiles;
      }

      final contact = await widget.contactRepository.getContact(contactPeerId);
      if (contact == null || !mounted) return;

      await markConversationRead(
        messageRepo: widget.messageRepository,
        contactPeerId: contactPeerId,
      );

      if (!mounted) return;

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
      const SnackBar(
        content: Text('Processing video\u2026'),
        duration: Duration(minutes: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Processes a media file (image or video) and returns the processed path.
  Future<String> _processMediaPath(String path) async {
    final processor = widget.imageProcessor;
    if (processor.isProcessableVideo(path)) {
      final result = await processor.processVideo(
        inputPath: path,
        quality: _videoQualityPreference,
      );
      return result.path;
    }
    return processor.processImage(inputPath: path, quality: _qualityPreference);
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

  void _startListeningForGroupMessages() {
    final listener = widget.groupMessageListener;
    if (listener == null) return;
    _groupMessageSubscription = listener.groupMessageStream.listen(
      (message) {
        if (!mounted) return;
        unawaited(_refreshGroupFeedItem(message.groupId));
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

  void _onGroupTap(GroupThreadFeedItem groupThread) {
    final groupRepo = widget.groupRepository;
    final msgRepo = widget.groupMessageRepository;
    final listener = widget.groupMessageListener;
    if (groupRepo == null || msgRepo == null || listener == null) return;

    final group = GroupModel(
      id: groupThread.groupId,
      name: groupThread.groupName,
      type: groupThread.groupType,
      topicName: '/mknoon/group/${groupThread.groupId}',
      createdAt: DateTime.now(),
      createdBy: '',
      myRole: GroupRole.member,
    );

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
            ),
          ),
        )
        .then((_) => unawaited(_refreshGroupFeedItem(groupThread.groupId)));
  }

  Future<void> _onGroupInlineSend(String groupId, String text) async {
    final identity = _identity;
    final groupRepo = widget.groupRepository;
    final msgRepo = widget.groupMessageRepository;
    if (identity == null || groupRepo == null || msgRepo == null) return;

    try {
      final (result, _) = await sendGroupMessage(
        bridge: widget.bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: text,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
      );

      if (!mounted) return;

      if (result == SendGroupMessageResult.success) {
        await _refreshGroupFeedItem(groupId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Message failed to send. Try again.'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_GROUP_INLINE_SEND_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message failed to send. Try again.'),
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

  void _onAvatarTap() {
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
            ),
          ),
        )
        .then((_) {
          _loadIdentity();
          _loadQualityPreference();
          _loadVideoQualityPreference();
        });
  }

  void _onSwitchView(String tab) {
    if (tab == 'orbit') {
      Navigator.of(context)
          .push(
            buildOrbitSlideUpRoute(
              builder: (_) => OrbitWired(
                identityRepo: widget.repository,
                contactRepo: widget.contactRepository,
                contactRequestRepo: widget.contactRequestRepository,
                contactRequestListener: widget.contactRequestListener,
                messageRepo: widget.messageRepository,
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
              ),
            ),
          )
          .then((result) {
            final changes = result is FeedRouteChanges ? result : null;
            unawaited(_applyRouteChanges(changes));
          });
      return;
    }
    if (tab == 'groups') {
      _navigateToGroups();
      return;
    }
    setState(() {
      _activeTab = tab;
    });
  }

  void _navigateToGroups() {
    final groupRepo = widget.groupRepository;
    final msgRepo = widget.groupMessageRepository;
    final listener = widget.groupMessageListener;
    if (groupRepo == null || msgRepo == null || listener == null) return;

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GroupListWired(
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
            ),
          ),
        )
        .then((result) {
          final changes = result is FeedRouteChanges ? result : null;
          unawaited(_applyRouteChanges(changes));
        });
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
          content: const Text('Failed to update username. Please try again.'),
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

    // Clear quote when collapsing (1:1 only)
    if (_expandedCardId == cardId && cardItem is ThreadFeedItem) {
      _activeQuoteMessageIds.remove(cardItem.contactPeerId);
    }

    // Clear session reply when expanding so expanded messages become visible (1:1 only)
    if (_expandedCardId != cardId && cardItem is ThreadFeedItem) {
      _sessionReplies.clear(cardItem.contactPeerId);
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
    _requestSubscription?.cancel();
    _chatSubscription?.cancel();
    _contactUpdateSubscription?.cancel();
    _reactionSubscription?.cancel();
    _groupMessageSubscription?.cancel();
    _introReceivedSubscription?.cancel();
    _introStatusSubscription?.cancel();
    _reactionStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FeedScreen(
        username: _username,
        userAvatarBytes: _avatarBytes,
        userPeerId: _peerId,
        feedItems: _feedItems,
        feedLoaded: _feedLoaded,
        onUsernameChanged: _onUsernameChanged,
        p2pService: widget.p2pService,
        onSwitchView: _onSwitchView,
        activeTab: _activeTab,
        onSendMessage: _onSendMessage,
        onReplyToMessage: _onReplyToMessage,
        totalUnreadCount: _totalUnreadCount,
        expandedCardId: _expandedCardId,
        onToggleExpand: _onToggleExpand,
        onInlineSend: _onInlineSend,
        onViewFullConversation: _onViewFullConversation,
        draftTexts: _draftTexts,
        activeFocusPeerId: _activeFocusPeerId,
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
      ),
    );
  }
}
