import 'package:flutter/material.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/group_media_batch_forward.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/share/application/group_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';

import 'group_media_batch_forward_picker_screen.dart';

class GroupMediaBatchForwardPickerWired extends StatefulWidget {
  const GroupMediaBatchForwardPickerWired({
    super.key,
    required this.draft,
    required this.identityRepository,
    required this.contactRepository,
    required this.groupRepository,
    required this.deliveryCoordinator,
  });

  final GroupMediaBatchForwardDraft draft;
  final IdentityRepository identityRepository;
  final ContactRepository contactRepository;
  final GroupRepository groupRepository;
  final GroupMediaBatchForwardDeliveryCoordinator deliveryCoordinator;

  @override
  State<GroupMediaBatchForwardPickerWired> createState() =>
      _GroupMediaBatchForwardPickerWiredState();
}

class _GroupMediaBatchForwardPickerWiredState
    extends State<GroupMediaBatchForwardPickerWired> {
  late final List<TextEditingController> _captionControllers;
  final Set<String> _selectedContactPeerIds = {};
  final Set<String> _selectedGroupIds = {};
  List<ContactModel> _contacts = const [];
  List<GroupModel> _groups = const [];
  GroupMediaBatchForwardMatrix? _matrix;
  GroupMediaBatchForwardProgress? _progress;
  bool _isLoading = true;
  bool _isSending = false;
  bool _targetsFrozen = false;
  GroupMediaBatchForwardDenial? _sourceDenial;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _captionControllers = [
      for (final item in widget.draft.items)
        TextEditingController(text: item.caption),
    ];
    _loadTargets();
  }

  @override
  void dispose() {
    for (final controller in _captionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTargets() async {
    try {
      final identity = await widget.identityRepository.loadIdentity();
      final ownPeerId = identity?.peerId.trim();
      if (ownPeerId == null || ownPeerId.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final results = await Future.wait<Object>([
        widget.contactRepository.getActiveContacts(),
        widget.groupRepository.getActiveGroups(),
      ]);
      final contacts = <ContactModel>[];
      final contactIds = <String>{};
      for (final contact in results[0] as List<ContactModel>) {
        final mlKemKey = contact.mlKemPublicKey?.trim();
        if (contact.peerId.trim().isNotEmpty &&
            contactIds.add(contact.peerId) &&
            GroupMediaForwardPolicy.canTargetContact(contact) &&
            mlKemKey != null &&
            mlKemKey.isNotEmpty) {
          contacts.add(contact);
        }
      }

      final groups = <GroupModel>[];
      final groupIds = <String>{};
      final snapshotRepo =
          widget.groupRepository is GroupForwardAuthorizationSnapshotRepository
          ? widget.groupRepository
                as GroupForwardAuthorizationSnapshotRepository
          : null;
      for (final candidate in results[1] as List<GroupModel>) {
        if (snapshotRepo == null ||
            !groupIds.add(candidate.id) ||
            !_groupTypeAllowed(candidate) ||
            !GroupMediaForwardPolicy.canTargetGroup(candidate)) {
          continue;
        }
        final hydratedKey = await widget.groupRepository.getLatestKey(
          candidate.id,
        );
        final snapshot = await snapshotRepo
            .loadGroupForwardAuthorizationSnapshot(candidate.id);
        final current = snapshot?.group;
        if (current == null ||
            current.id != candidate.id ||
            !_groupTypeAllowed(current) ||
            !GroupMediaForwardPolicy.canTargetGroup(current)) {
          continue;
        }
        if (hydratedKey == null ||
            hydratedKey.groupId != current.id ||
            snapshot!.latestKeyGeneration != hydratedKey.keyGeneration) {
          continue;
        }
        final ownMembers = snapshot.members
            .where((member) => member.peerId.trim() == ownPeerId)
            .toList(growable: false);
        final ownMember = ownMembers.length == 1 ? ownMembers.single : null;
        final canWrite = current.type == GroupType.announcement
            ? current.myRole == GroupRole.admin &&
                  ownMember?.role == MemberRole.admin
            : ownMember?.role == MemberRole.admin ||
                  ownMember?.role == MemberRole.writer;
        if (!canWrite) continue;
        groups.add(current);
      }
      if (!mounted) return;
      setState(() {
        _contacts = List.unmodifiable(contacts);
        _groups = List.unmodifiable(groups);
        _isLoading = false;
      });
      _emitState('GROUP_BATCH_FORWARD_TARGETS_READY');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contacts = const [];
        _groups = const [];
        _isLoading = false;
      });
      _emitState('GROUP_BATCH_FORWARD_TARGETS_FAILED');
    }
  }

  bool _groupTypeAllowed(GroupModel group) {
    if (widget.draft.sourceKind ==
        GroupMediaBatchForwardSourceKind.discussion) {
      return group.type == GroupType.chat;
    }
    if (group.id == widget.draft.sourceGroupId) return false;
    return group.type == GroupType.chat ||
        (group.type == GroupType.announcement &&
            group.myRole == GroupRole.admin);
  }

  void _toggleContact(ContactModel contact) {
    if (_isSending || _targetsFrozen) return;
    setState(() {
      if (!_selectedContactPeerIds.add(contact.peerId)) {
        _selectedContactPeerIds.remove(contact.peerId);
      }
      _sourceDenial = null;
    });
  }

  void _toggleGroup(GroupModel group) {
    if (_isSending || _targetsFrozen) return;
    setState(() {
      if (!_selectedGroupIds.add(group.id)) {
        _selectedGroupIds.remove(group.id);
      }
      _sourceDenial = null;
    });
  }

  GroupMediaBatchForwardDraft _editedDraft() => widget.draft.copyWith(
    items: [
      for (var index = 0; index < widget.draft.items.length; index++)
        widget.draft.items[index].copyWith(
          caption: _captionControllers[index].text,
        ),
    ],
  );

  List<ShareTargetSelection> get _selectedTargets => [
    for (final contact in _contacts)
      if (_selectedContactPeerIds.contains(contact.peerId))
        ShareTargetSelection.contact(contact),
    for (final group in _groups)
      if (_selectedGroupIds.contains(group.id))
        ShareTargetSelection.group(group),
  ];

  Future<void> _deliverInitial() async {
    if (_isSending || _targetsFrozen) return;
    final targets = _selectedTargets;
    if (targets.isEmpty) return;
    await _runAttempt(
      phase: 'initial',
      invoke: () => widget.deliveryCoordinator.deliverInitial(
        draft: _editedDraft(),
        targets: targets,
        onProgress: _onProgress,
      ),
    );
  }

  Future<void> _retryFailed() async {
    final prior = _matrix;
    if (_isSending || prior == null || prior.failedCount == 0) return;
    await _runAttempt(
      phase: 'retry',
      invoke: () => widget.deliveryCoordinator.retryFailed(
        draft: _editedDraft(),
        priorMatrix: prior,
        onProgress: _onProgress,
      ),
    );
  }

  Future<void> _runAttempt({
    required String phase,
    required Future<GroupMediaBatchForwardAttemptResult> Function() invoke,
  }) async {
    if (_isSending) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSending = true;
      _progress = null;
      _sourceDenial = null;
    });
    _emitState('GROUP_BATCH_FORWARD_ATTEMPT_STARTED', phase: phase);

    GroupMediaBatchForwardAttemptResult? result;
    var acquired = false;
    try {
      await UploadWakeLockController.acquire();
      acquired = true;
      result = await invoke();
    } catch (_) {
      result = null;
    } finally {
      if (acquired) {
        try {
          await UploadWakeLockController.release();
        } catch (_) {
          _emitState('GROUP_BATCH_FORWARD_WAKE_LOCK_RELEASE_FAILED');
        }
      }
    }
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _isSending = false;
        _progress = null;
        _sourceDenial = GroupMediaBatchForwardDenial.sourceUnavailable;
      });
      return;
    }

    final returned = result.matrix;
    setState(() {
      _isSending = false;
      _progress = null;
      _sourceDenial = result!.isDenied
          ? result.sourceDenial ??
                GroupMediaBatchForwardDenial.sourceUnavailable
          : null;
      if (returned != null) {
        _matrix = returned;
        _targetsFrozen = true;
      }
    });
    _emitState(
      'GROUP_BATCH_FORWARD_ATTEMPT_SETTLED',
      phase: phase,
      matrix: returned,
    );
    if (!result.isDenied && returned != null && returned.failedCount == 0) {
      _requestClose();
    }
  }

  void _onProgress(GroupMediaBatchForwardProgress progress) {
    if (!mounted || !_isSending) return;
    setState(() => _progress = progress);
  }

  void _requestClose() {
    if (_isSending || _allowPop) return;
    final matrix = _matrix;
    final completion = matrix == null
        ? null
        : GroupMediaBatchForwardCompletion.fromMatrix(matrix);
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(completion);
    });
  }

  void _emitState(
    String event, {
    String phase = 'idle',
    GroupMediaBatchForwardMatrix? matrix,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: event,
      details: {
        'phase': phase,
        'sourceKind': widget.draft.sourceKind.name,
        'sourceCount': widget.draft.items.length,
        'activeContactCount': _contacts.length,
        'activeGroupCount': _groups.length,
        'retainedCellCount': matrix?.cells.length ?? _matrix?.cells.length ?? 0,
        'sentCount': matrix?.sentCount ?? _matrix?.sentCount ?? 0,
        'queuedCount': matrix?.queuedCount ?? _matrix?.queuedCount ?? 0,
        'failedCount': matrix?.failedCount ?? _matrix?.failedCount ?? 0,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend =
        !_isLoading &&
        !_isSending &&
        !_targetsFrozen &&
        (_selectedContactPeerIds.isNotEmpty || _selectedGroupIds.isNotEmpty);
    final canRetry = !_isSending && (_matrix?.failedCount ?? 0) > 0;
    return PopScope(
      canPop: _allowPop && !_isSending,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isSending) _requestClose();
      },
      child: GroupMediaBatchForwardPickerScreen(
        items: widget.draft.items,
        captionControllers: _captionControllers,
        contacts: _contacts,
        groups: _groups,
        selectedContactPeerIds: _selectedContactPeerIds,
        selectedGroupIds: _selectedGroupIds,
        isLoading: _isLoading,
        isSending: _isSending,
        targetsFrozen: _targetsFrozen,
        matrix: _matrix,
        progress: _progress,
        sourceDenial: _sourceDenial,
        onToggleContact: _toggleContact,
        onToggleGroup: _toggleGroup,
        onSend: canSend ? _deliverInitial : null,
        onRetryFailed: canRetry ? _retryFailed : null,
        onClose: _requestClose,
      ),
    );
  }
}
