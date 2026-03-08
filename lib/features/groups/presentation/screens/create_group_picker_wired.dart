import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/groups/presentation/screens/create_group_picker_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

/// Wired widget for the new group creation flow.
///
/// Loads contacts, manages selection state, calls [createGroupWithMembers],
/// and navigates to [GroupConversationWired] on success via pushReplacement
/// (so back goes to group list).
class CreateGroupPickerWired extends StatefulWidget {
  final GroupType groupType;
  final GroupRepository groupRepo;
  final GroupMessageRepository msgRepo;
  final GroupMessageListener groupMessageListener;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final P2PService p2pService;
  final ActiveConversationTracker? groupConversationTracker;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final MediaFileManager? mediaFileManager;
  final ImageProcessor? imageProcessor;
  final ImageQualityPreference qualityPreference;
  final ImageQualityPreference videoQualityPreference;
  final AudioRecorderService? audioRecorderService;
  final ReactionRepository? reactionRepo;

  const CreateGroupPickerWired({
    super.key,
    required this.groupType,
    required this.groupRepo,
    required this.msgRepo,
    required this.groupMessageListener,
    required this.contactRepo,
    required this.bridge,
    required this.identityRepo,
    required this.p2pService,
    this.groupConversationTracker,
    this.mediaAttachmentRepo,
    this.mediaFileManager,
    this.imageProcessor,
    this.qualityPreference = ImageQualityPreference.compressed,
    this.videoQualityPreference = ImageQualityPreference.compressed,
    this.audioRecorderService,
    this.reactionRepo,
  });

  @override
  State<CreateGroupPickerWired> createState() => _CreateGroupPickerWiredState();
}

class _CreateGroupPickerWiredState extends State<CreateGroupPickerWired> {
  List<ContactModel> _contacts = [];
  final Set<String> _selectedPeerIds = {};
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(
      layer: 'FL',
      event: 'CREATE_GROUP_PICKER_FL_INIT',
      details: {'groupType': widget.groupType.toValue()},
    );
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final allContacts = await widget.contactRepo.getActiveContacts();

      // Exclude self
      final identity = await widget.identityRepo.loadIdentity();
      final selfPeerId = identity?.peerId;

      if (!mounted) return;
      setState(() {
        _contacts = allContacts
            .where((c) => c.peerId != selfPeerId)
            .toList()
          ..sort((a, b) => a.username.compareTo(b.username));
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CREATE_GROUP_PICKER_FL_LOAD_CONTACTS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _onToggle(ContactModel contact) {
    setState(() {
      if (_selectedPeerIds.contains(contact.peerId)) {
        _selectedPeerIds.remove(contact.peerId);
      } else {
        _selectedPeerIds.add(contact.peerId);
      }
    });
  }

  Future<void> _onStartGroup(String? name) async {
    setState(() => _isCreating = true);

    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) throw StateError('No identity found');

      final selectedContacts = _contacts
          .where((c) => _selectedPeerIds.contains(c.peerId))
          .toList();

      final result = await createGroupWithMembers(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        p2pService: widget.p2pService,
        identity: identity,
        selectedContacts: selectedContacts,
        type: widget.groupType,
        name: name,
      );

      if (!mounted) return;

      // Navigate to conversation, replacing this screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GroupConversationWired(
            group: result.group,
            groupRepo: widget.groupRepo,
            msgRepo: widget.msgRepo,
            groupMessageListener: widget.groupMessageListener,
            bridge: widget.bridge,
            identityRepo: widget.identityRepo,
            contactRepo: widget.contactRepo,
            p2pService: widget.p2pService,
            groupConversationTracker: widget.groupConversationTracker,
            mediaAttachmentRepo: widget.mediaAttachmentRepo,
            mediaFileManager: widget.mediaFileManager,
            imageProcessor: widget.imageProcessor,
            qualityPreference: widget.qualityPreference,
            videoQualityPreference: widget.videoQualityPreference,
            audioRecorderService: widget.audioRecorderService,
            reactionRepo: widget.reactionRepo,
          ),
        ),
        result: FeedRouteChanges(changedGroupIds: {result.group.id}),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CREATE_GROUP_PICKER_FL_CREATE_ERROR',
        details: {'error': e.toString()},
      );
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create group')),
        );
      }
    }
  }

  void _onBack() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CreateGroupPickerScreen(
      contacts: _contacts,
      selectedPeerIds: _selectedPeerIds,
      onToggle: _onToggle,
      onStartGroup: _onStartGroup,
      onBack: _onBack,
      isCreating: _isCreating,
    );
  }
}
