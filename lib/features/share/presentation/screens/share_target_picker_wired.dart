import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
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
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
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
  final SecureKeyStore? secureKeyStore;
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
  final Future<void> Function(ShareBatchDeliveryResult? result)? onClose;
  final Future<void> Function()? preSendReady;

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
    this.secureKeyStore,
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
    this.onClose,
    this.preSendReady,
  });

  @override
  State<ShareTargetPickerWired> createState() => _ShareTargetPickerWiredState();
}

class _ShareTargetPickerWiredState extends State<ShareTargetPickerWired> {
  late final TextEditingController _captionController = TextEditingController(
    text: widget.shareIntent.text ?? '',
  );
  late ImageQualityPreference _qualityPreference = widget.qualityPreference;
  late ImageQualityPreference _videoQualityPreference =
      widget.videoQualityPreference;
  late final Future<void> _qualityPreferencesReady = _loadQualityPreferences();
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

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _loadTargets() async {
    try {
      final contactsFuture = widget.contactRepository.getActiveContacts();
      final groupsFuture =
          widget.groupRepository?.getActiveGroups() ??
          Future.value(const <GroupModel>[]);
      final results = await Future.wait<Object>([contactsFuture, groupsFuture]);

      final contacts = results[0] as List<ContactModel>;
      final groups = (results[1] as List<GroupModel>)
          .where(
            (group) =>
                group.type != GroupType.announcement ||
                group.myRole == GroupRole.admin,
          )
          .toList();

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

  Future<void> _loadQualityPreferences() async {
    final secureKeyStore = widget.secureKeyStore;
    if (secureKeyStore == null) {
      return;
    }

    try {
      final values = await Future.wait([
        loadImageQualityPreference(secureKeyStore: secureKeyStore),
        loadVideoQualityPreference(secureKeyStore: secureKeyStore),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _qualityPreference = values[0];
        _videoQualityPreference = values[1];
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'SHARE_PICKER_QUALITY_LOAD_ERROR',
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
      final preSendReady = widget.preSendReady;
      if (preSendReady != null) {
        await preSendReady();
      }
      await _qualityPreferencesReady;
      final result = await _resolveBatchShareCoordinator().deliver(
        shareIntent: _buildComposedShareIntent(),
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
      _requestClose(result);
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

  ShareBatchDeliveryCoordinator _resolveBatchShareCoordinator() {
    return widget.batchShareCoordinator ??
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
          qualityPreference: _qualityPreference,
          videoQualityPreference: _videoQualityPreference,
        );
  }

  ShareIntent _buildComposedShareIntent() {
    final caption = _captionController.text.trim();
    return widget.shareIntent.copyWith(text: caption.isEmpty ? null : caption);
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
    if (parts.isEmpty && !result.hasSkippedOversizedGifs) {
      return 'Nothing was shared.';
    }
    final summary = <String>[];
    if (parts.isNotEmpty) {
      final sentence = parts.join(', ');
      summary.add('${sentence[0].toUpperCase()}${sentence.substring(1)}.');
    }
    if (result.hasSkippedOversizedGifs) {
      final count = result.skippedOversizedGifCount;
      summary.add(
        'Skipped $count oversized GIF${count == 1 ? '' : 's'}.',
      );
    }
    return summary.join(' ');
  }

  String _formatTargetCount(int count) {
    return '$count target${count == 1 ? '' : 's'}';
  }

  void _requestClose([ShareBatchDeliveryResult? result]) {
    final onClose = widget.onClose;
    if (onClose != null) {
      unawaited(onClose(result));
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return ShareTargetPickerScreen(
      sharedText: widget.shareIntent.text,
      sharedFilePaths: widget.shareIntent.filePaths,
      captionController: _captionController,
      contacts: _contacts,
      groups: _groups,
      isLoading: _isLoading,
      isSending: _isSending,
      selectedContactPeerIds: _selectedContactPeerIds,
      selectedGroupIds: _selectedGroupIds,
      onToggleContact: _toggleContact,
      onToggleGroup: _toggleGroup,
      onSend: _selectedTargets.isNotEmpty ? _sendSelectedTargets : null,
      onCancel: _isSending ? null : () => _requestClose(),
    );
  }
}
