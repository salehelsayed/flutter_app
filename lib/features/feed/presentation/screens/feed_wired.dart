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
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'feed_screen.dart';

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
  final JsBridge bridge;
  final P2PService p2pService;
  final ContactModel initialContact;

  const FeedWired({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.bridge,
    required this.p2pService,
    required this.initialContact,
  });

  @override
  State<FeedWired> createState() => _FeedWiredState();
}

class _FeedWiredState extends State<FeedWired> {
  String _username = 'Username';
  String? _avatarPath;
  String? _peerId;
  IdentityModel? _identity;
  String _activeTab = 'feed';
  final List<FeedItem> _feedItems = [];
  StreamSubscription<ContactRequestModel>? _requestSubscription;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(layer: 'FL', event: 'FEED_FL_SCREEN_INIT', details: {});
    _loadIdentity();
    _buildInitialFeedItem();
    _startListeningForContactRequests();
  }

  void _loadIdentity() async {
    try {
      final identity = await widget.repository.loadIdentity();
      if (identity == null || !mounted) return;

      setState(() {
        _identity = identity;
        _username = identity.username;
        _avatarPath = identity.avatarPath;
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

  void _buildInitialFeedItem() {
    final item = ConnectionFeedItem.fromContact(widget.initialContact);
    setState(() {
      _feedItems.add(item);
    });
  }

  void _startListeningForContactRequests() {
    _requestSubscription = widget.contactRequestListener.requestStream.listen(
      _onContactRequest,
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

    final result = await acceptContactRequest(
      requestRepo: widget.contactRequestRepository,
      contactRepo: widget.contactRepository,
      peerId: request.peerId,
    );

    if (!mounted) return;

    if (result == AcceptContactRequestResult.success) {
      final contact = request.toContactModel();
      final item = ConnectionFeedItem.fromContact(contact);
      setState(() {
        _feedItems.insert(0, item);
      });
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

  void _onSwitchView(String tab) {
    setState(() {
      _activeTab = tab;
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
      username: newUsername,
      avatarPath: identity.avatarPath,
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

  @override
  void dispose() {
    _requestSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FeedScreen(
        username: _username,
        userAvatarPath: _avatarPath,
        userPeerId: _peerId,
        feedItems: _feedItems,
        onUsernameChanged: _onUsernameChanged,
        p2pService: widget.p2pService,
        onSwitchView: _onSwitchView,
        activeTab: _activeTab,
      ),
    );
  }
}
