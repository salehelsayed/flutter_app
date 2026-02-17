import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/orbit/application/load_orbit_data_use_case.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_display_wired.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_wired.dart';
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
  final ChatMessageListener chatMessageListener;
  final JsBridge bridge;
  final P2PService p2pService;

  const OrbitWired({
    super.key,
    required this.identityRepo,
    required this.contactRepo,
    required this.contactRequestRepo,
    required this.contactRequestListener,
    required this.messageRepo,
    required this.chatMessageListener,
    required this.bridge,
    required this.p2pService,
  });

  @override
  State<OrbitWired> createState() => _OrbitWiredState();
}

class _OrbitWiredState extends State<OrbitWired> with TickerProviderStateMixin {
  IdentityModel? _identity;
  List<OrbitFriend> _allFriends = [];
  bool _searchActive = false;
  String _searchQuery = '';
  bool _isSearchTriggerVisible = true;

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

  static const _animCurve = Cubic(0.22, 0.61, 0.36, 1);

  @override
  void initState() {
    super.initState();
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
    _loadOrbitData();
    _startListeningForChatMessages();
    _startListeningForContactUpdates();
    _startListeningForContactRequests();
    _scrollController.addListener(_onScroll);
  }

  void _loadIdentity() async {
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null || !mounted) return;
      setState(() => _identity = identity);
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
      final friends = await loadOrbitData(
        contactRepo: widget.contactRepo,
        messageRepo: widget.messageRepo,
      );
      if (!mounted) return;
      setState(() => _allFriends = friends);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_DATA_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _startListeningForChatMessages() {
    _chatSubscription =
        widget.chatMessageListener.incomingMessageStream.listen(
      (_) { _loadOrbitData(); },
      onError: (error) {
        emitFlowEvent(layer: 'FL', event: 'ORBIT_CHAT_STREAM_ERROR', details: {'error': error.toString()});
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'ORBIT_CHAT_STREAM_DONE', details: {});
      },
    );
  }

  void _startListeningForContactUpdates() {
    _contactUpdateSubscription =
        widget.chatMessageListener.contactUpdatedStream.listen(
      (_) { _loadOrbitData(); },
      onError: (error) {
        emitFlowEvent(layer: 'FL', event: 'ORBIT_CONTACT_UPDATE_STREAM_ERROR', details: {'error': error.toString()});
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'ORBIT_CONTACT_UPDATE_STREAM_DONE', details: {});
      },
    );
  }

  void _startListeningForContactRequests() {
    _requestSubscription =
        widget.contactRequestListener.requestStream.listen(
      _onContactRequest,
      onError: (error) {
        emitFlowEvent(layer: 'FL', event: 'ORBIT_REQUEST_STREAM_ERROR', details: {'error': error.toString()});
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'ORBIT_REQUEST_STREAM_DONE', details: {});
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
    final result = await acceptContactRequest(
      requestRepo: widget.contactRequestRepo,
      contactRepo: widget.contactRepo,
      peerId: request.peerId,
    );
    if (!mounted) return;
    if (result == AcceptContactRequestResult.success) {
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

  List<OrbitFriend> get _displayedFriends {
    if (_searchQuery.isEmpty) return _allFriends;
    final q = _searchQuery.toLowerCase().trim();
    return _allFriends
        .where(
          (f) => f.username.toLowerCase().contains(q),
        )
        .toList();
  }

  void _onFriendTap(OrbitFriend friend) async {
    await markConversationRead(
      messageRepo: widget.messageRepo,
      contactPeerId: friend.peerId,
    );

    if (!mounted) return;

    Navigator.of(context).push(
      buildConversationSlideUpRoute(
        builder: (_) => ConversationWired(
          contact: friend.contact,
          identityRepo: widget.identityRepo,
          messageRepo: widget.messageRepo,
          chatMessageListener: widget.chatMessageListener,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
        ),
      ),
    ).then((_) => _loadOrbitData());
  }

  void _onMyQR() {
    Navigator.of(context).push(
      buildConversationSlideUpRoute(
        builder: (_) => QRDisplayWired(
          repo: widget.identityRepo,
          bridgeClient: widget.bridge,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _onScanQR() {
    Navigator.of(context).push(
      buildConversationSlideUpRoute(
        builder: (_) => QRScannerWired(
          bridge: widget.bridge,
          contactRepository: widget.contactRepo,
          contactRequestRepository: widget.contactRequestRepo,
          contactRequestListener: widget.contactRequestListener,
          messageRepository: widget.messageRepo,
          chatMessageListener: widget.chatMessageListener,
          identityRepository: widget.identityRepo,
          p2pService: widget.p2pService,
          ownPeerId: _identity?.peerId ?? '',
        ),
      ),
    );
  }

  void _onClose() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _contactUpdateSubscription?.cancel();
    _requestSubscription?.cancel();
    _collapseController.dispose();
    _searchDockController.dispose();
    _searchTriggerController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OrbitScreen(
      identity: _identity,
      allFriends: _allFriends,
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
    );
  }
}
