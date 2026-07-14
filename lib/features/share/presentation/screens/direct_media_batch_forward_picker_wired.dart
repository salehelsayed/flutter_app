import 'package:flutter/material.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/build_direct_media_library_batch_forward.dart';
import 'package:flutter_app/features/share/application/direct_media_batch_forward_delivery_coordinator.dart';

import 'direct_media_batch_forward_picker_screen.dart';

/// Direct-only state owner for the Shared Media Batch Forward route.
class DirectMediaBatchForwardPickerWired extends StatefulWidget {
  const DirectMediaBatchForwardPickerWired({
    super.key,
    required this.draft,
    required this.sourceContactPeerId,
    required this.contactRepository,
    required this.deliveryCoordinator,
  });

  final DirectMediaLibraryBatchForwardDraft draft;
  final String sourceContactPeerId;
  final ContactRepository contactRepository;
  final DirectMediaBatchForwardDeliveryCoordinator deliveryCoordinator;

  @override
  State<DirectMediaBatchForwardPickerWired> createState() =>
      _DirectMediaBatchForwardPickerWiredState();
}

class _DirectMediaBatchForwardPickerWiredState
    extends State<DirectMediaBatchForwardPickerWired> {
  late final List<TextEditingController> _captionControllers;
  final Set<String> _selectedContactPeerIds = <String>{};
  List<ContactModel> _contacts = const [];
  DirectMediaBatchForwardMatrix? _matrix;
  DirectMediaBatchForwardProgress? _progress;
  bool _isLoading = true;
  bool _isSending = false;
  bool _targetsFrozen = false;
  bool _showSourceUnavailable = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _captionControllers = [
      for (final item in widget.draft.items)
        TextEditingController(text: item.caption),
    ];
    _loadContacts();
  }

  @override
  void dispose() {
    for (final controller in _captionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final candidates = await widget.contactRepository.getActiveContacts();
      final seen = <String>{};
      final active = <ContactModel>[];
      for (final contact in candidates) {
        if (contact.peerId.trim().isEmpty ||
            contact.isArchived ||
            contact.isBlocked ||
            !seen.add(contact.peerId)) {
          continue;
        }
        active.add(contact);
      }
      if (!mounted) return;
      setState(() {
        _contacts = List.unmodifiable(active);
        _isLoading = false;
      });
      _emitStateEvent(
        event: 'DIRECT_BATCH_FORWARD_PICKER_TARGETS_READY',
        phase: 'loading',
        activeContactCount: active.length,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contacts = const [];
        _isLoading = false;
      });
      _emitStateEvent(
        event: 'DIRECT_BATCH_FORWARD_PICKER_TARGETS_FAILED',
        phase: 'loading',
        activeContactCount: 0,
      );
    }
  }

  void _toggleContact(ContactModel contact) {
    if (_isSending || _targetsFrozen) return;
    setState(() {
      if (!_selectedContactPeerIds.add(contact.peerId)) {
        _selectedContactPeerIds.remove(contact.peerId);
      }
      _showSourceUnavailable = false;
    });
  }

  DirectMediaLibraryBatchForwardDraft _editedDraft() {
    return widget.draft.copyWith(
      items: [
        for (var index = 0; index < widget.draft.items.length; index++)
          widget.draft.items[index].copyWith(
            caption: _captionControllers[index].text,
          ),
      ],
    );
  }

  List<String> get _selectedContactsInDisplayOrder => [
    for (final contact in _contacts)
      if (_selectedContactPeerIds.contains(contact.peerId)) contact.peerId,
  ];

  Future<void> _deliverInitial() async {
    if (_isSending || _targetsFrozen || _selectedContactPeerIds.isEmpty) {
      return;
    }
    final contactPeerIds = _selectedContactsInDisplayOrder;
    if (contactPeerIds.isEmpty) return;
    await _runAttempt(
      phase: 'initial',
      contactCount: contactPeerIds.length,
      invoke: () => widget.deliveryCoordinator.deliverInitial(
        sourceContactPeerId: widget.sourceContactPeerId,
        draft: _editedDraft(),
        contactPeerIds: contactPeerIds,
        onProgress: _onProgress,
      ),
    );
  }

  Future<void> _retryFailed() async {
    final priorMatrix = _matrix;
    if (_isSending || priorMatrix == null || priorMatrix.failedCount == 0) {
      return;
    }
    await _runAttempt(
      phase: 'retry',
      contactCount: priorMatrix.failedKeys
          .map((key) => key.contactPeerId)
          .toSet()
          .length,
      invoke: () => widget.deliveryCoordinator.retryFailed(
        sourceContactPeerId: widget.sourceContactPeerId,
        draft: _editedDraft(),
        priorMatrix: priorMatrix,
        onProgress: _onProgress,
      ),
    );
  }

  Future<void> _runAttempt({
    required String phase,
    required int contactCount,
    required Future<DirectMediaBatchForwardAttemptResult> Function() invoke,
  }) async {
    if (_isSending) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSending = true;
      _progress = null;
      _showSourceUnavailable = false;
    });
    _emitStateEvent(
      event: 'DIRECT_BATCH_FORWARD_PICKER_ATTEMPT_STARTED',
      phase: phase,
      activeContactCount: contactCount,
    );

    DirectMediaBatchForwardAttemptResult? result;
    var releaseRequired = false;
    var attemptFailed = false;
    try {
      releaseRequired = true;
      await UploadWakeLockController.acquire();
      result = await invoke();
    } catch (_) {
      attemptFailed = true;
      _emitStateEvent(
        event: 'DIRECT_BATCH_FORWARD_PICKER_ATTEMPT_FAILED',
        phase: phase,
        activeContactCount: contactCount,
      );
    } finally {
      if (releaseRequired) {
        try {
          await UploadWakeLockController.release();
        } catch (_) {
          _emitStateEvent(
            event: 'DIRECT_BATCH_FORWARD_PICKER_WAKE_LOCK_RELEASE_FAILED',
            phase: phase,
            activeContactCount: contactCount,
          );
        }
      }
    }

    if (!mounted) return;
    if (attemptFailed || result == null) {
      setState(() {
        _isSending = false;
        _progress = null;
        _showSourceUnavailable = true;
      });
      return;
    }

    final returnedMatrix = result.matrix;
    setState(() {
      _isSending = false;
      _progress = null;
      _showSourceUnavailable = result!.isDenied;
      if (returnedMatrix != null) {
        _matrix = returnedMatrix;
        _targetsFrozen = true;
      }
    });
    _emitStateEvent(
      event: 'DIRECT_BATCH_FORWARD_PICKER_ATTEMPT_SETTLED',
      phase: phase,
      activeContactCount: contactCount,
      matrix: returnedMatrix,
    );

    if (!result.isDenied &&
        returnedMatrix != null &&
        returnedMatrix.failedCount == 0) {
      _requestClose();
    }
  }

  void _onProgress(DirectMediaBatchForwardProgress progress) {
    if (!mounted || !_isSending) return;
    setState(() => _progress = progress);
    emitFlowEvent(
      layer: 'FL',
      event: 'DIRECT_BATCH_FORWARD_PICKER_PROGRESS',
      details: {
        'phase': progress.phase.name,
        'completedCellCount': progress.completedCellCount,
        'totalCellCount': progress.totalCellCount,
        'sourceOrdinal': progress.sourceOrdinal,
        'sourceCount': progress.sourceCount,
      },
    );
  }

  void _emitStateEvent({
    required String event,
    required String phase,
    required int activeContactCount,
    DirectMediaBatchForwardMatrix? matrix,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: event,
      details: {
        'phase': phase,
        'sourceCount': widget.draft.items.length,
        'activeContactCount': activeContactCount,
        'retainedCellCount': matrix?.cells.length ?? _matrix?.cells.length ?? 0,
        'sentCount': matrix?.sentCount ?? _matrix?.sentCount ?? 0,
        'queuedCount': matrix?.queuedCount ?? _matrix?.queuedCount ?? 0,
        'failedCount': matrix?.failedCount ?? _matrix?.failedCount ?? 0,
      },
    );
  }

  void _requestClose() {
    if (_isSending || _allowPop) return;
    final matrix = _matrix;
    final completion = matrix == null
        ? null
        : DirectMediaBatchForwardCompletion.fromMatrix(matrix);
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(completion);
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSend =
        !_isLoading &&
        !_isSending &&
        !_targetsFrozen &&
        _selectedContactPeerIds.isNotEmpty;
    final canRetry = !_isSending && (_matrix?.failedCount ?? 0) > 0;
    return PopScope(
      canPop: _allowPop && !_isSending,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isSending) _requestClose();
      },
      child: DirectMediaBatchForwardPickerScreen(
        items: widget.draft.items,
        captionControllers: _captionControllers,
        contacts: _contacts,
        selectedContactPeerIds: _selectedContactPeerIds,
        isLoading: _isLoading,
        isSending: _isSending,
        targetsFrozen: _targetsFrozen,
        matrix: _matrix,
        progress: _progress,
        showSourceUnavailable: _showSourceUnavailable,
        onToggleContact: _toggleContact,
        onSend: canSend ? _deliverInitial : null,
        onRetryFailed: canRetry ? _retryFailed : null,
        onClose: _requestClose,
      ),
    );
  }
}
