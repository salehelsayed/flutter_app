import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart'
    show ConversationComposerViewState;

/// Immutable, lane-neutral composer data captured before an optimistic send.
///
/// Draft and quote ownership stays with the Wired adapter. Pending media is
/// copied from [ConversationComposerController], so later composer mutations
/// cannot alter an in-flight operation's restore data.
@immutable
class ConversationComposerSnapshot {
  ConversationComposerSnapshot({
    required this.draftText,
    required this.quotedMessageId,
    required Iterable<PendingComposerMedia> pendingAttachments,
  }) : pendingAttachments = List<PendingComposerMedia>.unmodifiable(
         pendingAttachments,
       );

  final String draftText;
  final String? quotedMessageId;
  final List<PendingComposerMedia> pendingAttachments;
}

/// Owns common composer projection state without choosing direct/group policy.
///
/// Callers derive a complete [ConversationComposerViewState] in their lane
/// adapter, then publish it together with any pending-media replacement. This
/// keeps validation and private/group policy outside while making pending
/// media and semantic notification ownership exact and atomic.
class ConversationComposerController extends ChangeNotifier
    implements ValueListenable<ConversationComposerViewState> {
  ConversationComposerController({
    ConversationComposerViewState initialState =
        const ConversationComposerViewState(),
    Iterable<PendingComposerMedia> initialPendingAttachments =
        const <PendingComposerMedia>[],
  }) : _value = initialState,
       _pendingAttachments = List<PendingComposerMedia>.unmodifiable(
         initialPendingAttachments,
       ) {
    _requireMatchingPendingFiles(_value, _pendingAttachments);
  }

  ConversationComposerViewState _value;
  List<PendingComposerMedia> _pendingAttachments;

  @override
  ConversationComposerViewState get value => _value;

  /// The controller-owned pending media, defensively immutable to callers.
  List<PendingComposerMedia> get pendingAttachments => _pendingAttachments;

  /// File-only projection consumed by the existing public composer view model.
  List<File> get pendingAttachmentFiles => List<File>.unmodifiable(
    _pendingAttachments.map((attachment) => attachment.file),
  );

  /// Publishes a lane-projected view state at most once per semantic change.
  ///
  /// Pending media is replaced even when its file-path projection is
  /// semantically unchanged. That allows corrected byte/dimension metadata to
  /// become the next send snapshot without rebuilding the composer.
  bool publish({
    required ConversationComposerViewState state,
    Iterable<PendingComposerMedia>? pendingAttachments,
  }) {
    final nextPendingAttachments = pendingAttachments == null
        ? _pendingAttachments
        : List<PendingComposerMedia>.unmodifiable(pendingAttachments);
    _requireMatchingPendingFiles(state, nextPendingAttachments);
    _pendingAttachments = nextPendingAttachments;

    if (_composerStatesEqual(_value, state)) return false;
    _value = state;
    notifyListeners();
    return true;
  }

  ConversationComposerSnapshot snapshot({
    required String draftText,
    required String? quotedMessageId,
  }) {
    return ConversationComposerSnapshot(
      draftText: draftText,
      quotedMessageId: quotedMessageId,
      pendingAttachments: _pendingAttachments,
    );
  }

  /// Restores only the common snapshot. The adapter supplies its fully derived
  /// lane projection, including any direct private-policy normalization.
  bool restoreSnapshot(
    ConversationComposerSnapshot snapshot, {
    required ConversationComposerViewState state,
  }) {
    return publish(
      state: state,
      pendingAttachments: snapshot.pendingAttachments,
    );
  }
}

void _requireMatchingPendingFiles(
  ConversationComposerViewState state,
  List<PendingComposerMedia> pendingAttachments,
) {
  final projectedFiles = pendingAttachments
      .map((attachment) => attachment.file)
      .toList(growable: false);
  if (_fileListsEqual(state.pendingAttachments, projectedFiles)) return;
  throw ArgumentError(
    'ConversationComposerViewState.pendingAttachments must match the '
    'controller-owned PendingComposerMedia paths.',
  );
}

bool _composerStatesEqual(
  ConversationComposerViewState left,
  ConversationComposerViewState right,
) {
  return left.isUploading == right.isUploading &&
      left.isProcessing == right.isProcessing &&
      left.processingProgress == right.processingProgress &&
      left.processingCurrent == right.processingCurrent &&
      left.processingTotal == right.processingTotal &&
      left.recordingState == right.recordingState &&
      left.recordingDuration == right.recordingDuration &&
      left.privateMediaEligibility == right.privateMediaEligibility &&
      left.privateMediaPolicy == right.privateMediaPolicy &&
      listEquals(left.amplitudeValues, right.amplitudeValues) &&
      setEquals(
        left.invalidAttachmentIndices,
        right.invalidAttachmentIndices,
      ) &&
      mapEquals(
        left.invalidAttachmentReasons,
        right.invalidAttachmentReasons,
      ) &&
      left.hasTotalSizeOverflow == right.hasTotalSizeOverflow &&
      _fileListsEqual(left.pendingAttachments, right.pendingAttachments);
}

bool _fileListsEqual(List<File> left, List<File> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].path != right[index].path) return false;
  }
  return true;
}
