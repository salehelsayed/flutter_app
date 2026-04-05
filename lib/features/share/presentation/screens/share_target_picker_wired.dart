import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';

import 'share_target_picker_screen.dart';

/// Wired widget connecting ShareTargetPickerScreen to business logic.
///
/// Loads active contacts and writable groups, allows multi-selection, and
/// delivers the pending share through the bounded batch coordinator.
class ShareTargetPickerWired extends StatefulWidget {
  final ShareIntent shareIntent;
  final IdentityRepository identityRepo;
  final ContactRepository contactRepository;
  final MessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final ChatMessageListener chatMessageListener;
  final Bridge bridge;
  final P2PService p2pService;
  final MediaFileManager mediaFileManager;
  final ImageProcessor imageProcessor;
  final ImageQualityPreference qualityPreference;
  final ImageQualityPreference videoQualityPreference;
  final ActiveConversationTracker? conversationTracker;
  final AudioRecorderService? audioRecorderService;
  final ReactionRepository? reactionRepository;
  final ReactionListener? reactionListener;
  final GroupRepository? groupRepository;
  final GroupMessageRepository? groupMessageRepository;
  final GroupMessageListener? groupMessageListener;
  final ActiveConversationTracker? groupConversationTracker;
  final IntroductionRepository? introductionRepository;
  final ShareBatchDeliveryCoordinator? batchShareCoordinator;

  const ShareTargetPickerWired({
    super.key,
    required this.shareIntent,
    required this.identityRepo,
    required this.contactRepository,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.chatMessageListener,
    required this.bridge,
    required this.p2pService,
    required this.mediaFileManager,
    required this.imageProcessor,
    this.qualityPreference = ImageQualityPreference.compressed,
    this.videoQualityPreference = ImageQualityPreference.compressed,
    this.conversationTracker,
    this.audioRecorderService,
    this.reactionRepository,
    this.reactionListener,
    this.groupRepository,
    this.groupMessageRepository,
    this.groupMessageListener,
    this.groupConversationTracker,
    this.introductionRepository,
    this.batchShareCoordinator,
  });

  @override
  State<ShareTargetPickerWired> createState() => _ShareTargetPickerWiredState();
}

class _ShareTargetPickerWiredState extends State<ShareTargetPickerWired> {
  late final ShareBatchDeliveryCoordinator _batchShareCoordinator =
      widget.batchShareCoordinator ??
      DefaultShareBatchDeliveryCoordinator(
        identityRepository: widget.identityRepo,
        contactRepository: widget.contactRepository,
        messageRepository: widget.messageRepository,
        mediaAttachmentRepository: widget.mediaAttachmentRepository,
        groupRepository: widget.groupRepository,
        groupMessageRepository: widget.groupMessageRepository,
        bridge: widget.bridge,
        p2pService: widget.p2pService,
        mediaFileManager: widget.mediaFileManager,
        imageProcessor: widget.imageProcessor,
        qualityPreference: widget.qualityPreference,
        videoQualityPreference: widget.videoQualityPreference,
      );

  List<ContactModel> _contacts = [];
  List<GroupModel> _groups = [];
  final Set<String> _selectedContactPeerIds = <String>{};
  final Set<String> _selectedGroupIds = <String>{};
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    try {
      final contacts = await widget.contactRepository.getActiveContacts();

      List<GroupModel> groups = [];
      if (widget.groupRepository != null) {
        final allGroups = await widget.groupRepository!.getActiveGroups();
        groups = allGroups
            .where(
              (group) =>
                  group.type != GroupType.announcement ||
                  group.myRole == GroupRole.admin,
            )
            .toList();
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _contacts = contacts;
        _groups = groups;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'SHARE_PICKER_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _toggleContact(ContactModel contact) {
    if (_isSending) {
      return;
    }
    setState(() {
      if (_selectedContactPeerIds.contains(contact.peerId)) {
        _selectedContactPeerIds.remove(contact.peerId);
      } else {
        _selectedContactPeerIds.add(contact.peerId);
      }
    });
  }

  void _toggleGroup(GroupModel group) {
    if (_isSending) {
      return;
    }
    setState(() {
      if (_selectedGroupIds.contains(group.id)) {
        _selectedGroupIds.remove(group.id);
      } else {
        _selectedGroupIds.add(group.id);
      }
    });
  }

  List<ShareTargetSelection> get _selectedTargets {
    return [
      ..._contacts
          .where((contact) => _selectedContactPeerIds.contains(contact.peerId))
          .map(ShareTargetSelection.contact),
      ..._groups
          .where((group) => _selectedGroupIds.contains(group.id))
          .map(ShareTargetSelection.group),
    ];
  }

  Future<void> _sendSelectedTargets() async {
    if (_isSending) {
      return;
    }
    final targets = _selectedTargets;
    if (targets.isEmpty) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _isSending = true);

    try {
      final result = await _batchShareCoordinator.deliver(
        shareIntent: widget.shareIntent,
        targets: targets,
      );

      if (!mounted) {
        return;
      }

      final summary = _buildSummary(result);

      if (result.hasFailures) {
        setState(() {
          _selectedContactPeerIds
            ..clear()
            ..addAll(
              result.results
                  .where(
                    (item) =>
                        item.status == ShareBatchTargetStatus.failed &&
                        item.target.kind == ShareTargetSelectionKind.contact,
                  )
                  .map((item) => item.target.requireContact.peerId),
            );
          _selectedGroupIds
            ..clear()
            ..addAll(
              result.results
                  .where(
                    (item) =>
                        item.status == ShareBatchTargetStatus.failed &&
                        item.target.kind == ShareTargetSelectionKind.group,
                  )
                  .map((item) => item.target.requireGroup.id),
            );
          _isSending = false;
        });
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(summary),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }

      setState(() => _isSending = false);
      Navigator.of(context).pop(result);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(summary), behavior: SnackBarBehavior.floating),
        );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'SHARE_PICKER_SEND_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) {
        return;
      }
      setState(() => _isSending = false);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not share to the selected targets.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  String _buildSummary(ShareBatchDeliveryResult result) {
    final parts = <String>[];
    if (result.sentCount > 0) {
      parts.add('Sent to ${_formatTargetCount(result.sentCount)}');
    }
    if (result.queuedCount > 0) {
      parts.add('saved ${_formatTargetCount(result.queuedCount)} for retry');
    }
    if (result.failureCount > 0) {
      parts.add('failed for ${_formatTargetCount(result.failureCount)}');
    }
    if (parts.isEmpty) {
      return 'Nothing was shared.';
    }
    final sentence = parts.join(', ');
    return '${sentence[0].toUpperCase()}${sentence.substring(1)}.';
  }

  String _formatTargetCount(int count) {
    return '$count target${count == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    return ShareTargetPickerScreen(
      sharedText: widget.shareIntent.text,
      sharedFilePaths: widget.shareIntent.filePaths,
      contacts: _contacts,
      groups: _groups,
      isLoading: _isLoading,
      isSending: _isSending,
      selectedContactPeerIds: _selectedContactPeerIds,
      selectedGroupIds: _selectedGroupIds,
      onToggleContact: _toggleContact,
      onToggleGroup: _toggleGroup,
      onSend: _selectedTargets.isNotEmpty ? _sendSelectedTargets : null,
      onCancel: _isSending ? null : () => Navigator.of(context).pop(),
    );
  }
}
