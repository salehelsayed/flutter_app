import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/contacts/application/archive_contact_use_case.dart';
import 'package:flutter_app/features/groups/application/archive_group_use_case.dart';
import 'package:flutter_app/features/groups/application/unarchive_group_use_case.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/contacts/application/block_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/unarchive_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/unblock_contact_use_case.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/confirmation_dialog.dart';
import 'package:flutter_app/features/orbit/application/load_orbit_data_use_case.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/pass_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/expire_old_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/groups/presentation/screens/create_group_picker_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/orbit/application/load_orbit_groups_use_case.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_display_wired.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_wired.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'orbit_screen.dart';

/// Wired widget connecting OrbitScreen to business logic.
///
/// Manages state, animations, streams, and DI for the Orbit feature.
class OrbitWired extends StatefulWidget {
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final ContactRequestRepository contactRequestRepo;
  final ContactRequestListener contactRequestListener;
  final MessageRepository messageRepo;
  final MediaAttachmentRepository mediaAttachmentRepo;
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
  final String? initialFilterTab;

  const OrbitWired({
    super.key,
    required this.identityRepo,
    required this.contactRepo,
    required this.contactRequestRepo,
    required this.contactRequestListener,
    required this.messageRepo,
    required this.mediaAttachmentRepo,
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
    this.initialFilterTab,
  });

  @override
  State<OrbitWired> createState() => _OrbitWiredState();
}

class _OrbitWiredState extends State<OrbitWired> with TickerProviderStateMixin {
  IdentityModel? _identity;
  Uint8List? _avatarBytes;
  List<OrbitFriend> _activeFriends = [];
  List<OrbitFriend> _archivedFriends = [];
  List<OrbitGroup> _activeGroups = [];
  List<OrbitGroup> _archivedGroups = [];
  late String _filterTab;
  bool _searchActive = false;
  String _searchQuery = '';
  bool _isSearchTriggerVisible = true;
  final ValueNotifier<Key?> _openRowNotifier = ValueNotifier(null);

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  double _lastScrollOffset = 0;

  late final AnimationController _collapseController;
  late final AnimationController _searchDockController;
  late final AnimationController _searchTriggerController;

  StreamSubscription<ConversationMessage>? _chatSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;
  StreamSubscription<ContactRequestModel>? _requestSubscription;
  StreamSubscription<GroupMessage>? _groupMessageSubscription;
  StreamSubscription<IntroductionModel>? _introReceivedSubscription;
  StreamSubscription<IntroductionModel>? _introStatusSubscription;
  ImageQualityPreference _qualityPreference = ImageQualityPreference.compressed;
  ImageQualityPreference _videoQualityPreference =
      ImageQualityPreference.compressed;
  int _introsCount = 0;
  Map<String, List<IntroductionModel>> _groupedIntros = {};
  Map<String, String> _introducerUsernames = {};
  Set<String> _blockedPeerIds = {};
  final Set<String> _changedContactPeerIds = <String>{};
  final Set<String> _changedGroupIds = <String>{};
  bool _reloadAllContactsOnExit = false;
  bool _reloadAllGroupsOnExit = false;

  static const _animCurve = Cubic(0.22, 0.61, 0.36, 1);

  @override
  void initState() {
    super.initState();
    _filterTab = widget.initialFilterTab ?? 'all';
    emitFlowEvent(layer: 'FL', event: 'ORBIT_FL_SCREEN_INIT', details: {});

    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 580),
      value: 1.0, // starts expanded
    );
    _searchDockController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _searchTriggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      value: 1.0, // starts visible
    );

    _loadIdentity();
    _loadQualityPreference();
    _loadVideoQualityPreference();
    _loadOrbitData();
    _loadGroupData();
    _loadIntroductions();
    _startListeningForChatMessages();
    _startListeningForContactUpdates();
    _startListeningForContactRequests();
    _startListeningForGroupMessages();
    _startListeningForIntroductions();
    _scrollController.addListener(_onScroll);
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

  void _loadIdentity() async {
    try {
      final identity = await widget.identityRepo.loadIdentity();
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
        _avatarBytes = avatarBytes;
      });
      // Now that identity is loaded, load introductions
      _loadIntroductions();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_IDENTITY_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadOrbitData() async {
    try {
      final active = await loadOrbitData(
        contactRepo: widget.contactRepo,
        messageRepo: widget.messageRepo,
      );
      final archived = await loadOrbitData(
        contactRepo: widget.contactRepo,
        messageRepo: widget.messageRepo,
        includeArchived: true,
      );
      if (!mounted) return;
      final blocked = <String>{};
      for (final f in active) {
        if (f.isBlocked) blocked.add(f.peerId);
      }
      for (final f in archived) {
        if (f.isBlocked) blocked.add(f.peerId);
      }
      setState(() {
        _activeFriends = active;
        _archivedFriends = archived;
        _blockedPeerIds = blocked;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_DATA_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadGroupData() async {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    if (groupRepository == null || groupMessageRepository == null) return;

    try {
      final active = await loadOrbitGroups(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
      );
      final archived = await loadOrbitGroups(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        includeArchived: true,
      );
      if (!mounted) return;
      setState(() {
        _activeGroups = active;
        _archivedGroups = archived;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_GROUP_DATA_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadIntroductions() async {
    final introRepo = widget.introductionRepository;
    if (introRepo == null || _identity == null) return;

    try {
      final ownPeerId = _identity!.peerId;
      await expireOldIntroductions(introRepo: introRepo, peerId: ownPeerId);
      final pending = await loadIntroductionsForUser(
        introRepo: introRepo,
        peerId: ownPeerId,
      );
      final grouped = groupByIntroducer(pending);
      final usernames = <String, String>{};
      for (final intro in pending) {
        usernames.putIfAbsent(
          intro.introducerId,
          () => intro.introducerUsername ?? 'Unknown',
        );
      }
      if (!mounted) return;
      setState(() {
        _introsCount = pending.length;
        _groupedIntros = grouped;
        _introducerUsernames = usernames;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_INTROS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _markContactChanged(String peerId) {
    _changedContactPeerIds.add(peerId);
  }

  void _markGroupChanged(String groupId) {
    _changedGroupIds.add(groupId);
  }

  void _markReloadAllContacts() {
    _reloadAllContactsOnExit = true;
  }

  void _markReloadAllGroups() {
    _reloadAllGroupsOnExit = true;
  }

  FeedRouteChanges? _buildRouteChanges() {
    final changes = FeedRouteChanges(
      changedContactPeerIds: Set<String>.from(_changedContactPeerIds),
      changedGroupIds: Set<String>.from(_changedGroupIds),
      reloadAllContacts: _reloadAllContactsOnExit,
      reloadAllGroups: _reloadAllGroupsOnExit,
    );
    return changes.hasChanges ? changes : null;
  }

  void _startListeningForIntroductions() {
    final listener = widget.introductionListener;
    if (listener == null) return;

    _introReceivedSubscription = listener.introReceivedStream.listen(
      (_) => _loadIntroductions(),
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_INTRO_RECEIVED_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );

    _introStatusSubscription = listener.introStatusChangedStream.listen(
      (_) => _loadIntroductions(),
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_INTRO_STATUS_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  Future<void> _onAcceptIntro(String introductionId) async {
    if (_identity == null) return;

    final updated = await acceptIntroduction(
      introRepo: widget.introductionRepository!,
      contactRepo: widget.contactRepo,
      p2pService: widget.p2pService,
      bridge: widget.bridge,
      introductionId: introductionId,
      ownPeerId: _identity!.peerId,
      ownUsername: _identity!.username,
      messageRepo: widget.messageRepo,
    );
    if (updated != null &&
        updated.status == IntroductionOverallStatus.mutualAccepted) {
      final otherPeerId = updated.recipientId == _identity!.peerId
          ? updated.introducedId
          : updated.recipientId;
      if (otherPeerId.isNotEmpty) {
        _markContactChanged(otherPeerId);
      }
    }
    _loadIntroductions();
    _loadOrbitData();
  }

  Future<void> _onPassIntro(String introductionId) async {
    if (_identity == null) return;

    await passIntroduction(
      introRepo: widget.introductionRepository!,
      contactRepo: widget.contactRepo,
      p2pService: widget.p2pService,
      bridge: widget.bridge,
      introductionId: introductionId,
      ownPeerId: _identity!.peerId,
      ownUsername: _identity!.username,
    );
    _loadIntroductions();
  }

  void _onIntroSendMessage(String peerId) {
    // Find the contact matching this peerId and navigate to conversation
    final friend = _activeFriends.cast<OrbitFriend?>().firstWhere(
      (f) => f!.peerId == peerId,
      orElse: () => null,
    );
    if (friend != null) {
      _onFriendTap(friend);
    }
  }

  void _startListeningForGroupMessages() {
    final listener = widget.groupMessageListener;
    if (listener == null) return;

    _groupMessageSubscription = listener.groupMessageStream.listen(
      (_) {
        _loadOrbitData();
        _loadGroupData();
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_GROUP_MSG_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_GROUP_MSG_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  void _startListeningForChatMessages() {
    _chatSubscription = widget.chatMessageListener.incomingMessageStream.listen(
      (_) {
        _loadOrbitData();
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_CHAT_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_CHAT_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  void _startListeningForContactUpdates() {
    _contactUpdateSubscription = widget.chatMessageListener.contactUpdatedStream
        .listen(
          (_) {
            _loadOrbitData();
          },
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'ORBIT_CONTACT_UPDATE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
          onDone: () {
            emitFlowEvent(
              layer: 'FL',
              event: 'ORBIT_CONTACT_UPDATE_STREAM_DONE',
              details: {},
            );
          },
        );
  }

  void _startListeningForContactRequests() {
    _requestSubscription = widget.contactRequestListener.requestStream.listen(
      _onContactRequest,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_REQUEST_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_REQUEST_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  void _onContactRequest(ContactRequestModel request) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ORBIT_FL_CONTACT_REQUEST_RECEIVED',
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
      requestRepo: widget.contactRequestRepo,
      contactRepo: widget.contactRepo,
      peerId: request.peerId,
      p2pService: widget.p2pService,
      identityRepo: widget.identityRepo,
      bridge: widget.bridge,
      onProfileDownloaded: widget.chatMessageListener.emitContactUpdate,
    );
    if (!mounted) return;
    if (result == AcceptContactRequestResult.success ||
        result == AcceptContactRequestResult.notPending) {
      _markContactChanged(request.peerId);
      _loadOrbitData();
    }
  }

  Future<void> _declineRequest(
    BuildContext ctx,
    ContactRequestModel request,
  ) async {
    Navigator.pop(ctx);
    await declineContactRequest(
      requestRepo: widget.contactRequestRepo,
      peerId: request.peerId,
    );
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final goingDown = offset > _lastScrollOffset && offset > 100;
    _lastScrollOffset = offset;

    if (!_searchActive) {
      final shouldShow = !goingDown || offset < 50;
      if (shouldShow != _isSearchTriggerVisible) {
        setState(() => _isSearchTriggerVisible = shouldShow);
        if (shouldShow) {
          _searchTriggerController.forward();
        } else {
          _searchTriggerController.reverse();
        }
      }
    }
  }

  void _onSearchOpen() {
    setState(() => _searchActive = true);
    _collapseController.animateTo(0, curve: _animCurve);
    _searchDockController.forward();
    _searchTriggerController.reverse();
    _searchFocusNode.requestFocus();
  }

  void _onSearchClose() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() {
      _searchActive = false;
      _searchQuery = '';
    });
    _collapseController.animateTo(1.0, curve: _animCurve);
    _searchDockController.reverse();
    _searchTriggerController.forward();
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
  }

  void _onSearchClear() {
    _searchController.clear();
    setState(() => _searchQuery = '');
    _searchFocusNode.requestFocus();
  }

  List<OrbitFriend> get _currentTabFriends =>
      _filterTab == 'archived' ? _archivedFriends : _activeFriends;

  List<OrbitFriend> get _displayedFriends {
    final base = _currentTabFriends;
    if (_searchQuery.isEmpty) return base;
    final q = _searchQuery.toLowerCase().trim();
    return base.where((f) => f.username.toLowerCase().contains(q)).toList();
  }

  void _onFilterChanged(String tab) {
    _openRowNotifier.value = null;
    setState(() => _filterTab = tab);
  }

  Future<void> _onArchiveFriend(OrbitFriend friend) async {
    try {
      await archiveContact(
        contactRepo: widget.contactRepo,
        peerId: friend.peerId,
      );
      _markContactChanged(friend.peerId);
      _loadOrbitData();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_ARCHIVE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onUnarchiveFriend(OrbitFriend friend) async {
    try {
      await unarchiveContact(
        contactRepo: widget.contactRepo,
        peerId: friend.peerId,
      );
      _markContactChanged(friend.peerId);
      _loadOrbitData();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_UNARCHIVE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onBlockFriend(OrbitFriend friend) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Block ${friend.username}?',
      description:
          'They won\'t be able to send you messages. You can unblock them later.',
      confirmLabel: 'Block',
    );
    if (!confirmed || !mounted) return;

    try {
      await blockContact(
        contactRepo: widget.contactRepo,
        peerId: friend.peerId,
      );
      _openRowNotifier.value = null;
      _markContactChanged(friend.peerId);
      _loadOrbitData();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_BLOCK_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onUnblockFriend(OrbitFriend friend) async {
    try {
      await unblockContact(
        contactRepo: widget.contactRepo,
        peerId: friend.peerId,
      );
      _markContactChanged(friend.peerId);
      _loadOrbitData();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_UNBLOCK_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onDeleteFriend(OrbitFriend friend) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Delete chat?',
      description:
          'This will permanently remove ${friend.username} and all messages. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    try {
      await deleteContactAndMessages(
        contactRepo: widget.contactRepo,
        messageRepo: widget.messageRepo,
        peerId: friend.peerId,
      );
      _openRowNotifier.value = null;
      _markContactChanged(friend.peerId);
      _loadOrbitData();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DELETE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _onFriendTap(OrbitFriend friend) async {
    await markConversationRead(
      messageRepo: widget.messageRepo,
      contactPeerId: friend.peerId,
    );

    if (!mounted) return;

    Navigator.of(context)
        .push(
          buildConversationSlideUpRoute(
            builder: (_) => ConversationWired(
              contact: friend.contact,
              identityRepo: widget.identityRepo,
              messageRepo: widget.messageRepo,
              chatMessageListener: widget.chatMessageListener,
              p2pService: widget.p2pService,
              bridge: widget.bridge,
              contactRepo: widget.contactRepo,
              mediaAttachmentRepo: widget.mediaAttachmentRepo,
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
          _markContactChanged(friend.peerId);
          _loadOrbitData();
        });
  }

  void _onMyQR() {
    Navigator.of(context).push(
      buildConversationSlideUpRoute(
        builder: (_) => QRDisplayWired(
          repo: widget.identityRepo,
          bridgeClient: widget.bridge,
          onClose: () => Navigator.of(context).pop(),
          onScanPressed: _onScanQR,
        ),
      ),
    );
  }

  void _onScanQR() {
    Navigator.of(context)
        .push(
          buildConversationSlideUpRoute(
            builder: (_) => QRScannerWired(
              bridge: widget.bridge,
              contactRepository: widget.contactRepo,
              contactRequestRepository: widget.contactRequestRepo,
              contactRequestListener: widget.contactRequestListener,
              messageRepository: widget.messageRepo,
              mediaAttachmentRepository: widget.mediaAttachmentRepo,
              chatMessageListener: widget.chatMessageListener,
              identityRepository: widget.identityRepo,
              p2pService: widget.p2pService,
              mediaFileManager: widget.mediaFileManager,
              secureKeyStore: widget.secureKeyStore,
              imageProcessor: widget.imageProcessor,
              ownPeerId: _identity?.peerId ?? '',
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
        .then((_) {
          _markReloadAllContacts();
          _markReloadAllGroups();
          _loadOrbitData();
          _loadGroupData();
        });
  }

  void _onClose() {
    Navigator.of(context).pop(_buildRouteChanges());
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _contactUpdateSubscription?.cancel();
    _requestSubscription?.cancel();
    _groupMessageSubscription?.cancel();
    _introReceivedSubscription?.cancel();
    _introStatusSubscription?.cancel();
    _collapseController.dispose();
    _searchDockController.dispose();
    _searchTriggerController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _openRowNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OrbitScreen(
      identity: _identity,
      userAvatarBytes: _avatarBytes,
      allFriends: _activeFriends,
      displayedFriends: _displayedFriends,
      searchActive: _searchActive,
      searchQuery: _searchQuery,
      scrollController: _scrollController,
      searchController: _searchController,
      searchFocusNode: _searchFocusNode,
      collapseAnimation: CurvedAnimation(
        parent: _collapseController,
        curve: _animCurve,
      ),
      searchDockAnimation: CurvedAnimation(
        parent: _searchDockController,
        curve: _animCurve,
      ),
      searchTriggerAnimation: CurvedAnimation(
        parent: _searchTriggerController,
        curve: Curves.ease,
      ),
      onClose: _onClose,
      onFriendTap: _onFriendTap,
      onMyQR: _onMyQR,
      onScanQR: _onScanQR,
      onSearchOpen: _onSearchOpen,
      onSearchClose: _onSearchClose,
      onSearchChanged: _onSearchChanged,
      onSearchClear: _onSearchClear,
      filterTab: _filterTab,
      activeCount: _activeFriends.length,
      archivedCount: _archivedFriends.length + _archivedGroups.length,
      onFilterChanged: _onFilterChanged,
      onArchiveFriend: _onArchiveFriend,
      onUnarchiveFriend: _onUnarchiveFriend,
      onBlockFriend: _onBlockFriend,
      onUnblockFriend: _onUnblockFriend,
      onDeleteFriend: _onDeleteFriend,
      openRowNotifier: _openRowNotifier,
      groups: _filterTab == 'archived' ? _archivedGroups : _activeGroups,
      onGroupTap: _onGroupTap,
      onCreateGroup: _onCreateGroup,
      onArchiveGroup: _onArchiveGroup,
      onUnarchiveGroup: _onUnarchiveGroup,
      onDeleteGroup: _onDeleteGroup,
      introsCount: _introsCount,
      introsData: OrbitIntrosViewData(
        groupedIntros: _groupedIntros,
        introducerUsernames: _introducerUsernames,
        ownPeerId: _identity?.peerId ?? '',
        onAccept: _onAcceptIntro,
        onPass: _onPassIntro,
        onSendMessage: _onIntroSendMessage,
        blockedPeerIds: _blockedPeerIds,
      ),
      onIntroBannerTap: () => _onFilterChanged('intros'),
    );
  }

  Future<void> _onArchiveGroup(OrbitGroup group) async {
    final groupRepository = widget.groupRepository;
    if (groupRepository == null) return;

    try {
      await archiveGroup(groupRepo: groupRepository, groupId: group.group.id);
      _markGroupChanged(group.group.id);
      _loadGroupData();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_ARCHIVE_GROUP_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onUnarchiveGroup(OrbitGroup group) async {
    final groupRepository = widget.groupRepository;
    if (groupRepository == null) return;

    try {
      await unarchiveGroup(groupRepo: groupRepository, groupId: group.group.id);
      _markGroupChanged(group.group.id);
      _loadGroupData();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_UNARCHIVE_GROUP_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onDeleteGroup(OrbitGroup group) async {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    if (groupRepository == null || groupMessageRepository == null) return;

    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Leave & delete group?',
      description:
          'This will permanently leave the group and delete all messages. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    try {
      await deleteGroupAndMessages(
        bridge: widget.bridge,
        groupRepo: groupRepository,
        groupMessageRepo: groupMessageRepository,
        groupId: group.group.id,
      );
      _openRowNotifier.value = null;
      _markGroupChanged(group.group.id);
      _loadGroupData();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DELETE_GROUP_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _onGroupTap(OrbitGroup group) {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    final groupMessageListener = widget.groupMessageListener;
    if (groupRepository == null ||
        groupMessageRepository == null ||
        groupMessageListener == null) {
      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GroupConversationWired(
              group: group.group,
              groupRepo: groupRepository,
              msgRepo: groupMessageRepository,
              groupMessageListener: groupMessageListener,
              bridge: widget.bridge,
              identityRepo: widget.identityRepo,
              contactRepo: widget.contactRepo,
              p2pService: widget.p2pService,
              mediaAttachmentRepo: widget.mediaAttachmentRepo,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              qualityPreference: _qualityPreference,
              videoQualityPreference: _videoQualityPreference,
              audioRecorderService: widget.audioRecorderService,
              groupConversationTracker: widget.groupConversationTracker,
            ),
          ),
        )
        .then((_) {
          _markGroupChanged(group.group.id);
          _loadOrbitData();
          _loadGroupData();
        });
  }

  void _onCreateGroup(GroupType type) {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    final groupMessageListener = widget.groupMessageListener;
    if (groupRepository == null ||
        groupMessageRepository == null ||
        groupMessageListener == null) {
      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CreateGroupPickerWired(
              groupType: type,
              groupRepo: groupRepository,
              msgRepo: groupMessageRepository,
              groupMessageListener: groupMessageListener,
              contactRepo: widget.contactRepo,
              bridge: widget.bridge,
              identityRepo: widget.identityRepo,
              p2pService: widget.p2pService,
              groupConversationTracker: widget.groupConversationTracker,
            ),
          ),
        )
        .then((_) {
          _markReloadAllGroups();
          _loadOrbitData();
          _loadGroupData();
        });
  }
}
