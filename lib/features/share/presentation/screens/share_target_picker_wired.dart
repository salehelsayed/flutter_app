import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
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
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

import 'share_target_picker_screen.dart';

/// Wired widget connecting ShareTargetPickerScreen to business logic.
///
/// Loads active contacts and writable groups, processes shared media on
/// target selection, and navigates to the appropriate conversation screen.
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
  });

  @override
  State<ShareTargetPickerWired> createState() => _ShareTargetPickerWiredState();
}

class _ShareTargetPickerWiredState extends State<ShareTargetPickerWired> {
  List<ContactModel> _contacts = [];
  List<GroupModel> _groups = [];
  bool _isProcessing = false;

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
        // Filter out announcement groups where user is not admin
        groups = allGroups
            .where((g) =>
                g.type != GroupType.announcement ||
                g.myRole == GroupRole.admin)
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _groups = groups;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'SHARE_PICKER_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onContactSelected(ContactModel contact) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final files = await _processSharedFiles();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        buildConversationSlideUpRoute(
          builder: (_) => ConversationWired(
            contact: contact,
            identityRepo: widget.identityRepo,
            messageRepo: widget.messageRepository,
            chatMessageListener: widget.chatMessageListener,
            p2pService: widget.p2pService,
            bridge: widget.bridge,
            contactRepo: widget.contactRepository,
            mediaAttachmentRepo: widget.mediaAttachmentRepository,
            mediaFileManager: widget.mediaFileManager,
            initialAttachments: files.isNotEmpty ? files : null,
            initialText: widget.shareIntent.text,
            imageProcessor: widget.imageProcessor,
            qualityPreference: widget.qualityPreference,
            videoQualityPreference: widget.videoQualityPreference,
            conversationTracker: widget.conversationTracker,
            audioRecorderService: widget.audioRecorderService,
            reactionRepo: widget.reactionRepository,
            reactionListener: widget.reactionListener,
            introductionRepository: widget.introductionRepository,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
      emitFlowEvent(
        layer: 'FL',
        event: 'SHARE_PICKER_CONTACT_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onGroupSelected(GroupModel group) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final files = await _processSharedFiles();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GroupConversationWired(
            group: group,
            groupRepo: widget.groupRepository!,
            msgRepo: widget.groupMessageRepository!,
            groupMessageListener: widget.groupMessageListener!,
            bridge: widget.bridge,
            identityRepo: widget.identityRepo,
            contactRepo: widget.contactRepository,
            p2pService: widget.p2pService,
            mediaAttachmentRepo: widget.mediaAttachmentRepository,
            mediaFileManager: widget.mediaFileManager,
            initialAttachments: files.isNotEmpty ? files : null,
            initialText: widget.shareIntent.text,
            imageProcessor: widget.imageProcessor,
            qualityPreference: widget.qualityPreference,
            videoQualityPreference: widget.videoQualityPreference,
            audioRecorderService: widget.audioRecorderService,
            groupConversationTracker: widget.groupConversationTracker,
            reactionRepo: widget.reactionRepository,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
      emitFlowEvent(
        layer: 'FL',
        event: 'SHARE_PICKER_GROUP_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  /// Process shared media files (EXIF strip, compress) once on target selection.
  Future<List<File>> _processSharedFiles() async {
    if (!widget.shareIntent.hasFiles) return [];

    final processed = <File>[];
    for (final path in widget.shareIntent.filePaths) {
      try {
        final file = File(path);
        if (!file.existsSync()) continue;

        if (widget.imageProcessor.isProcessableVideo(path)) {
          final result = await widget.imageProcessor.processVideo(
            inputPath: path,
            quality: widget.videoQualityPreference,
          );
          processed.add(File(result.path));
        } else if (widget.imageProcessor.isProcessableImage(path)) {
          final resultPath = await widget.imageProcessor.processImage(
            inputPath: path,
            quality: widget.qualityPreference,
          );
          processed.add(File(resultPath));
        } else {
          processed.add(file);
        }
      } catch (e) {
        // Fallback: use original file
        processed.add(File(path));
      }
    }
    return processed;
  }

  @override
  Widget build(BuildContext context) {
    return ShareTargetPickerScreen(
      sharedText: widget.shareIntent.text,
      sharedFilePaths: widget.shareIntent.filePaths,
      contacts: _contacts,
      groups: _groups,
      onContactSelected: _onContactSelected,
      onGroupSelected: _onGroupSelected,
      onCancel: () => Navigator.of(context).pop(),
    );
  }
}
