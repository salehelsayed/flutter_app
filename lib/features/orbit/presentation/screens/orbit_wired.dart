import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
import 'package:flutter_app/features/home/application/identity_avatar_resolver.dart';
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
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
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
  final VoidCallback? debugOnHeaderBuild;
  final VoidCallback? debugOnListBuild;

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
    this.debugOnHeaderBuild,
    this.debugOnListBuild,
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
  bool _activeFriendsLoaded = false;
  bool _archivedFriendsLoaded = false;
  bool _activeGroupsLoaded = false;
  bool _archivedGroupsLoaded = false;
  late String _filterTab;
  bool _searchActive = false;
  String _searchQuery = '';
  bool _isSearchTriggerVisible = true;
  final ValueNotifier<Key?> _openRowNotifier = ValueNotifier(null);
  final ValueNotifier<OrbitHeaderProjection> _headerProjectionNotifier =
      ValueNotifier<OrbitHeaderProjection>(const OrbitHeaderProjection());
  final ValueNotifier<OrbitViewProjection> _listProjectionNotifier =
      ValueNotifier<OrbitViewProjection>(const OrbitViewProjection());

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

  static const _animCurve = Cubic(0.22, 0.61, 0.36, 1);

  OrbitHeaderProjection _buildHeaderProjection() {
    return OrbitHeaderProjection(
      userPeerId: _identity?.peerId,
      userAvatarBytes: _avatarBytes,
      allFriends: List<OrbitFriend>.unmodifiable(_activeFriends),
    );
  }

  OrbitViewProjection _buildListProjection() {
    final baseFriends = _filterTab == 'archived'
        ? _archivedFriends
        : _activeFriends;
    final displayedFriends = _searchQuery.isEmpty
        ? baseFriends
        : baseFriends
              .where(
                (friend) => friend.username.toLowerCase().contains(
                  _searchQuery.toLowerCase().trim(),
                ),
              )
              .toList(growable: false);
    final groups = _filterTab == 'archived' ? _archivedGroups : _activeGroups;

    final mergedItems = <OrbitItem>[
      ...displayedFriends.map(OrbitFriendItem.new),
      if (!_searchActive) ...groups.map(OrbitGroupItem.new),
    ]..sort((a, b) => b.sortKey.compareTo(a.sortKey));

    final showLoadingPlaceholders = switch (_filterTab) {
      'archived' => !_archivedFriendsLoaded || !_archivedGroupsLoaded,
      'intros' => false,
      _ => !_activeFriendsLoaded || !_activeGroupsLoaded,
    };

    return OrbitViewProjection(
      allFriends: List<OrbitFriend>.unmodifiable(_activeFriends),
      displayedFriends: List<OrbitFriend>.unmodifiable(displayedFriends),
      groups: List<OrbitGroup>.unmodifiable(groups),
      mergedItems: List<OrbitItem>.unmodifiable(mergedItems),
      activeCount: _activeFriends.length,
      archivedCount: _archivedFriends.length + _archivedGroups.length,
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
      searchActive: _searchActive,
      searchQuery: _searchQuery,
      filterTab: _filterTab,
      showLoadingPlaceholders: showLoadingPlaceholders,
    );
  }

  void _publishHeaderProjection() {
    _headerProjectionNotifier.value = _buildHeaderProjection();
  }

  void _publishListProjection() {
    _listProjectionNotifier.value = _buildListProjection();
  }

  void _publishAllProjections() {
    _publishHeaderProjection();
    _publishListProjection();
  }

  @override
  void initState() {
    super.initState();
    _filterTab = widget.initialFilterTab ?? 'all';
    final hasGroupSurfaces =
        widget.groupRepository != null && widget.groupMessageRepository != null;
    _activeGroupsLoaded = !hasGroupSurfaces;
    _archivedGroupsLoaded = !hasGroupSurfaces;
    _publishAllProjections();
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
    _qualityPreference = pref;
  }

  Future<void> _loadVideoQualityPreference() async {
    final pref = await loadVideoQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    _videoQualityPreference = pref;
  }

  void _loadIdentity() async {
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null || !mounted) return;

      final avatarBytes = await IdentityAvatarResolver.resolve(identity);

      if (!mounted) return;

      _identity = identity;
      _avatarBytes = avatarBytes;
      _publishAllProjections();
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
      if (!mounted) return;

      _activeFriends = active;
      _activeFriendsLoaded = true;
      _blockedPeerIds = _collectBlockedPeerIds(
        activeFriends: _activeFriends,
        archivedFriends: _archivedFriends,
      );
      _publishAllProjections();
    } catch (e) {
      if (mounted) {
        _activeFriendsLoaded = true;
        _publishAllProjections();
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_DATA_ERROR',
        details: {'error': e.toString(), 'segment': 'active'},
      );
    }

    try {
      final archived = await loadOrbitData(
        contactRepo: widget.contactRepo,
        messageRepo: widget.messageRepo,
        includeArchived: true,
      );
      if (!mounted) return;

      _archivedFriends = archived;
      _archivedFriendsLoaded = true;
      _blockedPeerIds = _collectBlockedPeerIds(
        activeFriends: _activeFriends,
        archivedFriends: _archivedFriends,
      );
      _publishAllProjections();
    } catch (e) {
      if (mounted) {
        _archivedFriendsLoaded = true;
        _publishAllProjections();
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_DATA_ERROR',
        details: {'error': e.toString(), 'segment': 'archived'},
      );
    }
  }

  Future<void> _loadGroupData() async {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    if (groupRepository == null || groupMessageRepository == null) {
      _activeGroupsLoaded = true;
      _archivedGroupsLoaded = true;
      _publishListProjection();
      return;
    }

    try {
      final active = await loadOrbitGroups(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
      );
      if (!mounted) return;

      _activeGroups = active;
      _activeGroupsLoaded = true;
      _publishListProjection();
    } catch (e) {
      if (mounted) {
        _activeGroupsLoaded = true;
        _publishListProjection();
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_GROUP_DATA_ERROR',
        details: {'error': e.toString(), 'segment': 'active'},
      );
    }

    try {
      final archived = await loadOrbitGroups(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        includeArchived: true,
      );
      if (!mounted) return;
      _archivedGroups = archived;
      _archivedGroupsLoaded = true;
      _publishListProjection();
    } catch (e) {
      if (mounted) {
        _archivedGroupsLoaded = true;
        _publishListProjection();
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_GROUP_DATA_ERROR',
        details: {'error': e.toString(), 'segment': 'archived'},
      );
    }
  }

  Set<String> _collectBlockedPeerIds({
    required List<OrbitFriend> activeFriends,
    required List<OrbitFriend> archivedFriends,
  }) {
    final blocked = <String>{};
    for (final friend in activeFriends) {
      if (friend.isBlocked) blocked.add(friend.peerId);
    }
    for (final friend in archivedFriends) {
      if (friend.isBlocked) blocked.add(friend.peerId);
    }
    return blocked;
  }

  Future<void> _refreshOrbitFriend(String peerId) async {
    try {
      final friend = await loadOrbitFriendSnapshot(
        contactRepo: widget.contactRepo,
        messageRepo: widget.messageRepo,
        contactPeerId: peerId,
      );
      if (!mounted) return;

      final activeFriends = List<OrbitFriend>.from(_activeFriends)
        ..removeWhere((entry) => entry.peerId == peerId);
      final archivedFriends = List<OrbitFriend>.from(_archivedFriends)
        ..removeWhere((entry) => entry.peerId == peerId);
      final blockedPeerIds = Set<String>.from(_blockedPeerIds)..remove(peerId);

      if (friend != null) {
        if (friend.isArchived) {
          archivedFriends.add(friend);
        } else {
          activeFriends.add(friend);
        }
        if (friend.isBlocked) {
          blockedPeerIds.add(peerId);
        }
      }

      _sortFriends(activeFriends);
      _sortFriends(archivedFriends);
      _activeFriends = activeFriends;
      _archivedFriends = archivedFriends;
      _blockedPeerIds = blockedPeerIds;
      _publishAllProjections();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_FRIEND_REFRESH_ERROR',
        details: {'peerId': peerId, 'error': e.toString()},
      );
      await _loadOrbitData();
    }
  }

  Future<void> _refreshOrbitGroup(String groupId) async {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    if (groupRepository == null || groupMessageRepository == null) return;

    try {
      final group = await loadOrbitGroupSnapshot(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        groupId: groupId,
      );
      if (!mounted) return;

      final activeGroups = List<OrbitGroup>.from(_activeGroups)
        ..removeWhere((entry) => entry.groupId == groupId);
      final archivedGroups = List<OrbitGroup>.from(_archivedGroups)
        ..removeWhere((entry) => entry.groupId == groupId);

      if (group != null) {
        if (group.group.isArchived) {
          archivedGroups.add(group);
        } else {
          activeGroups.add(group);
        }
      }

      _sortGroups(activeGroups);
      _sortGroups(archivedGroups);
      _activeGroups = activeGroups;
      _archivedGroups = archivedGroups;
      _publishListProjection();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_GROUP_REFRESH_ERROR',
        details: {'groupId': groupId, 'error': e.toString()},
      );
      await _loadGroupData();
    }
  }

  void _sortFriends(List<OrbitFriend> friends) {
    friends.sort((a, b) {
      final aTime = a.lastMessageTimestamp ?? '';
      final bTime = b.lastMessageTimestamp ?? '';
      return bTime.compareTo(aTime);
    });
  }

  void _sortGroups(List<OrbitGroup> groups) {
    groups.sort((a, b) {
      final aTime = a.lastActivityTimestamp?.toUtc().toIso8601String() ?? '';
      final bTime = b.lastActivityTimestamp?.toUtc().toIso8601String() ?? '';
      return bTime.compareTo(aTime);
    });
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
      _introsCount = pending.length;
      _groupedIntros = grouped;
      _introducerUsernames = usernames;
      _publishListProjection();
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

  FeedRouteChanges? _buildRouteChanges() {
    final changes = FeedRouteChanges(
      changedContactPeerIds: Set<String>.from(_changedContactPeerIds),
      changedGroupIds: Set<String>.from(_changedGroupIds),
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
      (intro) {
        _loadIntroductions();
        final identity = _identity;
        if (identity == null ||
            intro.status != IntroductionOverallStatus.mutualAccepted) {
          return;
        }
        final otherPeerId = intro.recipientId == identity.peerId
            ? intro.introducedId
            : intro.recipientId;
        if (otherPeerId.isNotEmpty) {
          unawaited(_refreshOrbitFriend(otherPeerId));
        }
      },
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
        await _refreshOrbitFriend(otherPeerId);
      }
    }
    _loadIntroductions();
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
      (message) {
        unawaited(_refreshOrbitGroup(message.groupId));
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
      (message) {
        unawaited(_refreshOrbitFriend(message.contactPeerId));
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
          (contact) {
            unawaited(_refreshOrbitFriend(contact.peerId));
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
      await _refreshOrbitFriend(request.peerId);
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
        _isSearchTriggerVisible = shouldShow;
        if (shouldShow) {
          _searchTriggerController.forward();
        } else {
          _searchTriggerController.reverse();
        }
      }
    }
  }

  void _onSearchOpen() {
    _searchActive = true;
    _publishListProjection();
    _collapseController.animateTo(0, curve: _animCurve);
    _searchDockController.forward();
    _searchTriggerController.reverse();
    _searchFocusNode.requestFocus();
  }

  void _onSearchClose() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    _searchActive = false;
    _searchQuery = '';
    _publishListProjection();
    _collapseController.animateTo(1.0, curve: _animCurve);
    _searchDockController.reverse();
    _searchTriggerController.forward();
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;
    _publishListProjection();
  }

  void _onSearchClear() {
    _searchController.clear();
    _searchQuery = '';
    _publishListProjection();
    _searchFocusNode.requestFocus();
  }

  void _onFilterChanged(String tab) {
    _openRowNotifier.value = null;
    _filterTab = tab;
    _publishListProjection();
  }

  Future<void> _onArchiveFriend(OrbitFriend friend) async {
    try {
      await archiveContact(
        contactRepo: widget.contactRepo,
        peerId: friend.peerId,
      );
      _markContactChanged(friend.peerId);
      await _refreshOrbitFriend(friend.peerId);
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
      await _refreshOrbitFriend(friend.peerId);
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
      await _refreshOrbitFriend(friend.peerId);
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
      await _refreshOrbitFriend(friend.peerId);
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
      await _refreshOrbitFriend(friend.peerId);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DELETE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _onFriendTap(OrbitFriend friend) {
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
          unawaited(_refreshOrbitFriend(friend.peerId));
        });

    // Push first, then let the conversation route perform its own initial
    // read-marking without blocking the transition.
    unawaited(_markConversationReadInBackground(friend.peerId));
  }

  Future<void> _markConversationReadInBackground(String peerId) async {
    try {
      await markConversationRead(
        messageRepo: widget.messageRepo,
        contactPeerId: peerId,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_MARK_READ_ERROR',
        details: {'peerId': peerId, 'error': e.toString()},
      );
    }
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

  Future<void> _applyRouteChanges(Object? result) async {
    final changes = result is FeedRouteChanges ? result : null;
    if (changes == null) return;

    if (changes.reloadAllContacts) {
      await _loadOrbitData();
    } else if (changes.changedContactPeerIds.isNotEmpty) {
      await Future.wait(changes.changedContactPeerIds.map(_refreshOrbitFriend));
    }

    if (changes.reloadAllGroups) {
      await _loadGroupData();
    } else if (changes.changedGroupIds.isNotEmpty) {
      await Future.wait(changes.changedGroupIds.map(_refreshOrbitGroup));
    }
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
        .then((result) => unawaited(_applyRouteChanges(result)));
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
    _headerProjectionNotifier.dispose();
    _listProjectionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OrbitScreen(
      headerProjectionListenable: _headerProjectionNotifier,
      listProjectionListenable: _listProjectionNotifier,
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
      onFilterChanged: _onFilterChanged,
      onArchiveFriend: _onArchiveFriend,
      onUnarchiveFriend: _onUnarchiveFriend,
      onBlockFriend: _onBlockFriend,
      onUnblockFriend: _onUnblockFriend,
      onDeleteFriend: _onDeleteFriend,
      openRowNotifier: _openRowNotifier,
      onGroupTap: _onGroupTap,
      onCreateGroup: _onCreateGroup,
      onArchiveGroup: _onArchiveGroup,
      onUnarchiveGroup: _onUnarchiveGroup,
      onDeleteGroup: _onDeleteGroup,
      onIntroBannerTap: () => _onFilterChanged('intros'),
      onHeaderBuild: widget.debugOnHeaderBuild,
      onListBuild: widget.debugOnListBuild,
    );
  }

  Future<void> _onArchiveGroup(OrbitGroup group) async {
    final groupRepository = widget.groupRepository;
    if (groupRepository == null) return;

    try {
      await archiveGroup(groupRepo: groupRepository, groupId: group.group.id);
      _markGroupChanged(group.group.id);
      await _refreshOrbitGroup(group.group.id);
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
      await _refreshOrbitGroup(group.group.id);
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
      await _refreshOrbitGroup(group.group.id);
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
          unawaited(_refreshOrbitGroup(group.group.id));
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
        .then((result) => unawaited(_applyRouteChanges(result)));
  }
}
