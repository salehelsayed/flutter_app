import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
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
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/application/announcement_media_forward_request.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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
  final GroupInviteDeliveryAttemptRepository?
  groupInviteDeliveryAttemptRepository;
  final GroupMessageListener? groupMessageListener;
  final ActiveConversationTracker? groupConversationTracker;
  final IntroductionRepository? introductionRepository;
  final ShareBatchDeliveryCoordinator? batchShareCoordinator;
  final AppShellController? appShellController;
  final Future<void> Function(ShareBatchDeliveryResult? result)? onClose;
  final Future<void> Function()? preSendReady;

  /// 236: non-null puts the picker in group-media Forward mode. Destinations
  /// narrow to contacts and writable `GroupType.chat` groups, and Send routes
  /// through [ShareBatchDeliveryCoordinator.deliverGroupMediaForward] — the
  /// dispatch reloads and hash-verifies the source identified here instead of
  /// trusting any picker-carried file path.
  final GroupMediaForwardRequest? groupMediaForwardRequest;

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
    this.groupInviteDeliveryAttemptRepository,
    this.groupMessageListener,
    this.groupConversationTracker,
    this.introductionRepository,
    this.batchShareCoordinator,
    this.appShellController,
    this.onClose,
    this.preSendReady,
    this.groupMediaForwardRequest,
  });

  @override
  State<ShareTargetPickerWired> createState() => _ShareTargetPickerWiredState();
}

class _ShareTargetPickerWiredState extends State<ShareTargetPickerWired> {
  late final TextEditingController _captionController = TextEditingController(
    text: switch (widget.groupMediaForwardRequest) {
      AnnouncementMediaForwardRequest request => request.composedCaption ?? '',
      GroupMediaForwardRequest request => request.initialCaption,
      null => widget.shareIntent.text ?? '',
    },
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
  UploadProgressViewState? _uploadProgress;
  ShareBatchDeliveryPhase? _deliveryPhase;
  String? _inlineFeedback;

  bool get _isInternalForward =>
      widget.groupMediaForwardRequest != null ||
      widget.shareIntent.forwardProvenance != null ||
      widget.shareIntent.directForwardSourceAuthority != null;

  @override
  void initState() {
    super.initState();
    widget.appShellController?.addListener(_onAppShellChanged);
    _loadTargets();
  }

  @override
  void dispose() {
    widget.appShellController?.removeListener(_onAppShellChanged);
    _captionController.dispose();
    super.dispose();
  }

  void _onAppShellChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadTargets() async {
    try {
      final contactsFuture = widget.contactRepository.getActiveContacts();
      final groupsFuture =
          widget.groupRepository?.getActiveGroups() ??
          Future.value(const <GroupModel>[]);
      final results = await Future.wait<Object>([contactsFuture, groupsFuture]);

      final contacts = (results[0] as List<ContactModel>)
          .where(
            (contact) =>
                !_isInternalForward ||
                GroupMediaForwardPolicy.canTargetContact(contact),
          )
          .toList(growable: false);
      final groups = await _filterWritableGroups(
        results[1] as List<GroupModel>,
      );

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

  Future<List<GroupModel>> _filterWritableGroups(
    List<GroupModel> candidates,
  ) async {
    final groupRepository = widget.groupRepository;
    if (groupRepository == null || candidates.isEmpty) {
      return const <GroupModel>[];
    }
    final identity = await widget.identityRepo.loadIdentity();
    final ownPeerId = identity?.peerId.trim();
    if (ownPeerId == null || ownPeerId.isEmpty) {
      return const <GroupModel>[];
    }

    final writableGroups = <GroupModel>[];
    for (final group in candidates) {
      if (await _isWritableGroupTarget(
        groupRepository: groupRepository,
        group: group,
        ownPeerId: ownPeerId,
      )) {
        writableGroups.add(group);
      }
    }
    return writableGroups;
  }

  Future<bool> _isWritableGroupTarget({
    required GroupRepository groupRepository,
    required GroupModel group,
    required String ownPeerId,
  }) async {
    if (group.isArchived || group.isDissolved) {
      return false;
    }
    final forwardRequest = widget.groupMediaForwardRequest;
    if (forwardRequest != null &&
        !GroupMediaForwardPolicy.canTargetGroup(group)) {
      return false;
    }
    if (forwardRequest != null &&
        forwardRequest is! AnnouncementMediaForwardRequest &&
        group.type == GroupType.announcement) {
      return false;
    }
    if (forwardRequest is AnnouncementMediaForwardRequest &&
        group.id == forwardRequest.groupId) {
      return false;
    }
    if (group.type == GroupType.announcement &&
        group.myRole != GroupRole.admin) {
      return false;
    }

    final latestKey = await groupRepository.getLatestKey(group.id);
    if (latestKey == null) {
      return false;
    }

    final members = await groupRepository.getMembers(group.id);
    return members.any((member) => member.peerId == ownPeerId);
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
    if (_selectedContactPeerIds.isEmpty && _selectedGroupIds.isEmpty) {
      return;
    }

    setState(() {
      _isSending = true;
      _uploadProgress = null;
      _deliveryPhase = null;
      _inlineFeedback = null;
    });

    final forwardRequest = widget.groupMediaForwardRequest;
    final holdsMediaWakeLock =
        forwardRequest == null && widget.shareIntent.hasFiles;
    var wakeLockHeld = false;
    ShareBatchDeliveryResult? deliveryResult;
    Object? deliveryError;
    try {
      if (holdsMediaWakeLock) {
        wakeLockHeld = true;
        await UploadWakeLockController.acquire();
      }
      final preSendReady = widget.preSendReady;
      if (preSendReady != null) {
        await preSendReady();
      }
      await _qualityPreferencesReady;
      final targets = await _resolveSelectedTargetsForDelivery();
      if (!mounted) {
        return;
      }
      _syncSelectedTargetsToCurrentRows(targets);
      if (targets.isEmpty) {
        setState(() => _isSending = false);
        return;
      }
      final coordinator = _resolveBatchShareCoordinator();
      deliveryResult = forwardRequest != null
          ? await coordinator.deliverGroupMediaForward(
              request: forwardRequest,
              caption: _composedCaption(),
              targets: targets,
            )
          : await coordinator.deliver(
              shareIntent: _buildComposedShareIntent(),
              targets: targets,
              onProgress: _onDeliveryProgress,
            );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'SHARE_PICKER_SEND_ERROR',
        details: {'error': e.toString()},
      );
      deliveryError = e;
    } finally {
      if (wakeLockHeld) {
        await UploadWakeLockController.release();
      }
    }

    if (!mounted) {
      return;
    }
    if (deliveryError != null) {
      setState(() {
        _isSending = false;
        _uploadProgress = null;
        _deliveryPhase = null;
        _inlineFeedback = AppLocalizations.of(context)!.share_send_failed;
      });
      return;
    }

    final result = deliveryResult!;
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
        _uploadProgress = null;
        _deliveryPhase = null;
        _inlineFeedback = summary;
      });
      return;
    }

    if (result.hasSkippedOversizedGifs) {
      setState(() {
        _selectedContactPeerIds.clear();
        _selectedGroupIds.clear();
        _isSending = false;
        _uploadProgress = null;
        _deliveryPhase = null;
        _inlineFeedback = summary;
      });
      return;
    }

    setState(() => _isSending = false);
    _requestClose(result);
  }

  void _onDeliveryProgress(ShareBatchDeliveryProgress progress) {
    if (!mounted || !_isSending) {
      return;
    }
    setState(() {
      _uploadProgress = UploadProgressViewState(
        sentBytes: progress.sentBytes,
        totalBytes: progress.totalBytes,
      );
      _deliveryPhase = progress.phase;
    });
  }

  Future<List<ShareTargetSelection>>
  _resolveSelectedTargetsForDelivery() async {
    final targets = <ShareTargetSelection>[];
    for (final selected in _contacts.where(
      (contact) => _selectedContactPeerIds.contains(contact.peerId),
    )) {
      final current = await widget.contactRepository.getContact(
        selected.peerId,
      );
      if (current == null ||
          (_isInternalForward &&
              !GroupMediaForwardPolicy.canTargetContact(current))) {
        continue;
      }
      targets.add(ShareTargetSelection.contact(current));
    }

    final groupRepository = widget.groupRepository;
    if (groupRepository == null || _selectedGroupIds.isEmpty) {
      return targets;
    }

    final identity = await widget.identityRepo.loadIdentity();
    final ownPeerId = identity?.peerId.trim();
    if (ownPeerId == null || ownPeerId.isEmpty) {
      return targets;
    }

    for (final group in _groups.where(
      (group) => _selectedGroupIds.contains(group.id),
    )) {
      final latestGroup = await groupRepository.getGroup(group.id);
      if (latestGroup == null) {
        continue;
      }
      final canShare = await _isWritableGroupTarget(
        groupRepository: groupRepository,
        group: latestGroup,
        ownPeerId: ownPeerId,
      );
      if (canShare) {
        targets.add(ShareTargetSelection.group(latestGroup));
      }
    }
    return targets;
  }

  void _syncSelectedTargetsToCurrentRows(List<ShareTargetSelection> targets) {
    final validContactPeerIds = targets
        .where((target) => target.kind == ShareTargetSelectionKind.contact)
        .map((target) => target.requireContact.peerId)
        .toSet();
    final validGroupIds = targets
        .where((target) => target.kind == ShareTargetSelectionKind.group)
        .map((target) => target.requireGroup.id)
        .toSet();
    if (validContactPeerIds.length == _selectedContactPeerIds.length &&
        _selectedContactPeerIds.containsAll(validContactPeerIds) &&
        validGroupIds.length == _selectedGroupIds.length &&
        _selectedGroupIds.containsAll(validGroupIds)) {
      return;
    }
    setState(() {
      _selectedContactPeerIds
        ..clear()
        ..addAll(validContactPeerIds);
      _selectedGroupIds
        ..clear()
        ..addAll(validGroupIds);
    });
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
          groupInviteDeliveryAttemptRepository:
              widget.groupInviteDeliveryAttemptRepository,
          bridge: widget.bridge,
          p2pService: widget.p2pService,
          mediaFileManager: widget.mediaFileManager,
          imageProcessor: widget.imageProcessor,
          qualityPreference: _qualityPreference,
          videoQualityPreference: _videoQualityPreference,
        );
  }

  String? _composedCaption() {
    final caption = _captionController.text.trim();
    return caption.isEmpty ? null : caption;
  }

  ShareIntent _buildComposedShareIntent() {
    return widget.shareIntent.copyWith(text: _composedCaption());
  }

  String _buildSummary(ShareBatchDeliveryResult result) {
    final l10n = AppLocalizations.of(context)!;
    final parts = <String>[];
    if (result.sentCount > 0) {
      parts.add(l10n.share_summary_sent(_formatTargetCount(result.sentCount)));
    }
    if (result.queuedCount > 0) {
      parts.add(
        l10n.share_summary_queued(_formatTargetCount(result.queuedCount)),
      );
    }
    if (result.failureCount > 0) {
      parts.add(
        l10n.share_summary_failed(_formatTargetCount(result.failureCount)),
      );
    }
    if (parts.isEmpty && !result.hasSkippedOversizedGifs) {
      return l10n.share_summary_nothing;
    }
    final summary = <String>[];
    if (parts.isNotEmpty) {
      final sentence = parts.join(', ');
      summary.add('${sentence[0].toUpperCase()}${sentence.substring(1)}.');
    }
    if (result.hasSkippedOversizedGifs) {
      summary.add(
        l10n.share_summary_skipped_gifs(result.skippedOversizedGifCount),
      );
    }
    return summary.join(' ');
  }

  String _formatTargetCount(int count) {
    return AppLocalizations.of(context)!.share_target_count(count);
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
    return PopScope(
      canPop: !_isSending,
      child: ShareTargetPickerScreen(
        sharedText: widget.shareIntent.text,
        sharedFilePaths: widget.shareIntent.filePaths,
        captionController: _captionController,
        contacts: _contacts,
        groups: _groups,
        isLoading: _isLoading,
        isSending: _isSending,
        uploadProgress: _uploadProgress,
        deliveryPhase: _deliveryPhase,
        inlineFeedback: _inlineFeedback,
        selectedContactPeerIds: _selectedContactPeerIds,
        selectedGroupIds: _selectedGroupIds,
        onToggleContact: _toggleContact,
        onToggleGroup: _toggleGroup,
        onSend: _selectedTargets.isNotEmpty ? _sendSelectedTargets : null,
        onCancel: _isSending ? null : () => _requestClose(),
        backgroundPreference:
            widget.appShellController?.backgroundPreference ??
            BackgroundPreference.defaultBackground,
      ),
    );
  }
}
