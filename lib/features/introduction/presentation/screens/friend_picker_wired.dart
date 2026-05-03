import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/application/send_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/presentation/screens/friend_picker_screen.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// Stateful wrapper that manages selection state for FriendPickerScreen.
///
/// Loads available friends on init, filters out the recipient and blocked
/// contacts, then delegates rendering to [FriendPickerScreen].
class FriendPickerWired extends StatefulWidget {
  final ContactModel recipient;
  final ContactRepository contactRepo;
  final IntroductionRepository introRepo;
  final P2PService p2pService;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final Function(List<IntroductionModel>) onIntroductionsSent;
  final BackgroundPreference backgroundPreference;

  const FriendPickerWired({
    super.key,
    required this.recipient,
    required this.contactRepo,
    required this.introRepo,
    required this.p2pService,
    required this.bridge,
    required this.identityRepo,
    required this.onIntroductionsSent,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  State<FriendPickerWired> createState() => _FriendPickerWiredState();
}

class _FriendPickerWiredState extends State<FriendPickerWired> {
  final Set<String> _selectedPeerIds = {};
  String _searchQuery = '';
  List<ContactModel> _availableFriends = [];
  bool _isLoading = true;
  bool _isSending = false;
  int _sendCompletedCount = 0;
  int _sendTotalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final contacts = await widget.contactRepo.getActiveContacts();
    final identity = await widget.identityRepo.loadIdentity();
    final selfPeerId = identity?.peerId;

    final filtered = contacts.where((c) {
      if (c.peerId == widget.recipient.peerId) return false;
      if (c.peerId == selfPeerId) return false;
      if (c.isBlocked) return false;
      return true;
    }).toList();

    if (mounted) {
      setState(() {
        _availableFriends = filtered;
        _isLoading = false;
      });
    }
  }

  void _onToggleFriend(String peerId) {
    setState(() {
      if (_selectedPeerIds.contains(peerId)) {
        _selectedPeerIds.remove(peerId);
      } else {
        _selectedPeerIds.add(peerId);
      }
    });
  }

  Future<void> _onSend() async {
    if (_isSending || _selectedPeerIds.isEmpty) return;

    setState(() {
      _isSending = true;
      _sendCompletedCount = 0;
      _sendTotalCount = _selectedPeerIds.length;
    });

    final identity = await widget.identityRepo.loadIdentity();
    if (identity == null) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _sendCompletedCount = 0;
          _sendTotalCount = 0;
        });
      }
      return;
    }

    final friendsToIntroduce = _selectedPeerIds
        .map((id) => _availableFriends.where((c) => c.peerId == id).firstOrNull)
        .whereType<ContactModel>()
        .toList();

    if (friendsToIntroduce.isEmpty) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _sendCompletedCount = 0;
          _sendTotalCount = 0;
        });
      }
      return;
    }

    try {
      // Use the send_introduction_use_case which saves records locally
      // AND sends P2P messages to both recipient and introduced friends.
      final introductions = await sendIntroductions(
        contactRepo: widget.contactRepo,
        introRepo: widget.introRepo,
        p2pService: widget.p2pService,
        bridge: widget.bridge,
        introducerPeerId: identity.peerId,
        introducerUsername: identity.username,
        recipientPeerId: widget.recipient.peerId,
        recipientUsername: widget.recipient.username,
        recipientMlKemPublicKey: widget.recipient.mlKemPublicKey,
        friendsToIntroduce: friendsToIntroduce,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            _sendCompletedCount = completed;
            _sendTotalCount = total;
          });
        },
      );

      if (mounted) {
        setState(() {
          _isSending = false;
          _sendCompletedCount = 0;
          _sendTotalCount = 0;
        });
        widget.onIntroductionsSent(introductions);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _sendCompletedCount = 0;
          _sendTotalCount = 0;
        });
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = BackgroundReadableColors.resolve(
      widget.backgroundPreference,
    );
    final theme = Theme.of(context);
    final themedChild = _isLoading
        ? Container(
            height: 300,
            decoration: BoxDecoration(
              color: readableColors.surfaceBase,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Center(
              child: CircularProgressIndicator(
                color: readableColors.isLightSurface
                    ? const Color(0xFF157A39)
                    : const Color(0xFF1DB954),
                strokeWidth: 2,
              ),
            ),
          )
        : FriendPickerScreen(
            recipientUsername: widget.recipient.username,
            availableFriends: _availableFriends,
            selectedPeerIds: _selectedPeerIds,
            searchQuery: _searchQuery,
            isSending: _isSending,
            sendCompletedCount: _sendCompletedCount,
            sendTotalCount: _sendTotalCount,
            onSearchChanged: (query) => setState(() => _searchQuery = query),
            onToggleFriend: _onToggleFriend,
            onSend: _onSend,
            onClose: () => Navigator.of(context).pop(),
          );

    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where(
            (extension) => extension is! BackgroundReadableColors,
          ),
          readableColors,
        ],
      ),
      child: themedChild,
    );
  }
}
