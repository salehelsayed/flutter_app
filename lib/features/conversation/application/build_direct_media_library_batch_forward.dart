import 'dart:io';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:uuid/uuid.dart';

import 'received_media_action_controller.dart';

typedef DirectMediaLibraryBatchForwardOperationTokenFactory = String Function();

String _defaultOperationToken() => const Uuid().v4();
bool _defaultFileExists(String path) => File(path).existsSync();

/// A complete-batch denial. Reasons deliberately carry no source identity,
/// contact payload, path, caption, token, key, nonce, or media bytes.
enum DirectMediaLibraryBatchForwardDenial {
  invalidSelection,
  sourceNotEligible,
  contactScopeMismatch,
  nonVisualSource,
  invalidOperationToken,
}

/// One immutable, locally held ordinary-forward draft.
///
/// This is not a wire or persistence model. Session 02 may edit [caption] by
/// replacing this value, while sibling captions and operation tokens remain
/// independent.
class DirectMediaLibraryBatchForwardItemDraft {
  const DirectMediaLibraryBatchForwardItemDraft({
    required this.identity,
    required this.resolvedPath,
    required this.parentTimestamp,
    required this.caption,
    required this.forwardProvenance,
  });

  final DirectReceivedMediaActionIdentity identity;
  final String resolvedPath;
  final String parentTimestamp;
  final String caption;
  final ForwardProvenance forwardProvenance;

  DirectMediaLibraryBatchForwardItemDraft copyWith({String? caption}) =>
      DirectMediaLibraryBatchForwardItemDraft(
        identity: identity,
        resolvedPath: resolvedPath,
        parentTimestamp: parentTimestamp,
        caption: caption ?? this.caption,
        forwardProvenance: forwardProvenance,
      );

  @override
  String toString() => 'DirectMediaLibraryBatchForwardItemDraft(redacted)';
}

/// An immutable, canonically ordered set of `1..10` source drafts.
///
/// It intentionally has no destination, shared caption, batch token, transport
/// state, or persistence handle.
class DirectMediaLibraryBatchForwardDraft {
  DirectMediaLibraryBatchForwardDraft({
    required Iterable<DirectMediaLibraryBatchForwardItemDraft> items,
  }) : items = List.unmodifiable(items);

  final List<DirectMediaLibraryBatchForwardItemDraft> items;

  DirectMediaLibraryBatchForwardDraft copyWith({
    Iterable<DirectMediaLibraryBatchForwardItemDraft>? items,
  }) => DirectMediaLibraryBatchForwardDraft(items: items ?? this.items);

  @override
  String toString() =>
      'DirectMediaLibraryBatchForwardDraft(itemCount: ${items.length})';
}

/// Atomic result of initial build or dispatch-time revalidation.
class DirectMediaLibraryBatchForwardResult {
  const DirectMediaLibraryBatchForwardResult.ready(this.draft) : denial = null;

  const DirectMediaLibraryBatchForwardResult.denied(this.denial) : draft = null;

  final DirectMediaLibraryBatchForwardDraft? draft;
  final DirectMediaLibraryBatchForwardDenial? denial;

  bool get isReady => draft != null && denial == null;

  @override
  String toString() => isReady
      ? 'DirectMediaLibraryBatchForwardResult(ready, '
            'itemCount: ${draft!.items.length})'
      : 'DirectMediaLibraryBatchForwardResult(denied: $denial)';
}

class _QualifiedSource {
  const _QualifiedSource({
    required this.identity,
    required this.parent,
    required this.resolvedPath,
  });

  final DirectReceivedMediaActionIdentity identity;
  final ConversationMessage parent;
  final String resolvedPath;
}

class _QualificationBatchResult {
  const _QualificationBatchResult.ready(this.sources) : denial = null;

  const _QualificationBatchResult.denied(this.denial) : sources = null;

  final List<_QualifiedSource>? sources;
  final DirectMediaLibraryBatchForwardDenial? denial;
}

/// Builds and revalidates the hidden Plan-249 direct-source foundation.
///
/// Every exact identity is delegated to Plan-234's mandatory
/// [qualifyCurrentDirectMediaRow]. Only the Plan-249 additions — one direct
/// contact scope, visual kind, cardinality, atomicity, canonical order,
/// independent captions, and independent operation tokens — live here.
class BuildDirectMediaLibraryBatchForward {
  BuildDirectMediaLibraryBatchForward({
    required DirectParentMessageLoader loadParentMessage,
    required MediaAttachmentRepository mediaAttachmentRepository,
    DirectMediaLibraryBatchForwardOperationTokenFactory operationTokenFactory =
        _defaultOperationToken,
    String Function(String storedPath) resolveStoredPath =
        MediaFileManager.resolveStoredPathSync,
    bool Function(String resolvedPath) fileExists = _defaultFileExists,
  }) : _loadParentMessage = loadParentMessage,
       _mediaAttachmentRepository = mediaAttachmentRepository,
       _operationTokenFactory = operationTokenFactory,
       _resolveStoredPath = resolveStoredPath,
       _fileExists = fileExists;

  final DirectParentMessageLoader _loadParentMessage;
  final MediaAttachmentRepository _mediaAttachmentRepository;
  final DirectMediaLibraryBatchForwardOperationTokenFactory
  _operationTokenFactory;
  final String Function(String storedPath) _resolveStoredPath;
  final bool Function(String resolvedPath) _fileExists;

  Future<DirectMediaLibraryBatchForwardResult> build({
    required String contactPeerId,
    required List<DirectReceivedMediaActionIdentity> identities,
  }) async {
    if (!_hasValidInput(contactPeerId, identities)) {
      return const DirectMediaLibraryBatchForwardResult.denied(
        DirectMediaLibraryBatchForwardDenial.invalidSelection,
      );
    }

    final qualification = await _qualifyAll(
      contactPeerId: contactPeerId,
      identities: identities,
    );
    if (qualification.denial != null) {
      return DirectMediaLibraryBatchForwardResult.denied(qualification.denial!);
    }

    final items = <DirectMediaLibraryBatchForwardItemDraft>[];
    final seenTokens = <String>{};
    for (final source in qualification.sources!) {
      final String token;
      try {
        token = _operationTokenFactory();
      } catch (_) {
        return const DirectMediaLibraryBatchForwardResult.denied(
          DirectMediaLibraryBatchForwardDenial.invalidOperationToken,
        );
      }
      if (token.trim().isEmpty || !seenTokens.add(token)) {
        return const DirectMediaLibraryBatchForwardResult.denied(
          DirectMediaLibraryBatchForwardDenial.invalidOperationToken,
        );
      }
      items.add(
        DirectMediaLibraryBatchForwardItemDraft(
          identity: source.identity,
          resolvedPath: source.resolvedPath,
          parentTimestamp: source.parent.timestamp,
          caption: source.parent.text,
          forwardProvenance: ForwardProvenance(operationDedupKey: token),
        ),
      );
    }
    return DirectMediaLibraryBatchForwardResult.ready(
      DirectMediaLibraryBatchForwardDraft(items: items),
    );
  }

  /// Re-reads every exact source immediately before Session 02 may dispatch.
  /// Paths and order are refreshed; captions and tokens are preserved by the
  /// complete `(messageId, attachmentId)` identity. No token is ever minted.
  Future<DirectMediaLibraryBatchForwardResult> revalidateForDispatch({
    required String contactPeerId,
    required DirectMediaLibraryBatchForwardDraft draft,
  }) async {
    final identities = [for (final item in draft.items) item.identity];
    if (!_hasValidInput(contactPeerId, identities)) {
      return const DirectMediaLibraryBatchForwardResult.denied(
        DirectMediaLibraryBatchForwardDenial.invalidSelection,
      );
    }

    final originals =
        <
          DirectReceivedMediaActionIdentity,
          DirectMediaLibraryBatchForwardItemDraft
        >{for (final item in draft.items) item.identity: item};
    final preservedTokens = <String>{};
    for (final item in draft.items) {
      final token = item.forwardProvenance.operationDedupKey;
      if (token.trim().isEmpty || !preservedTokens.add(token)) {
        return const DirectMediaLibraryBatchForwardResult.denied(
          DirectMediaLibraryBatchForwardDenial.invalidOperationToken,
        );
      }
    }

    final qualification = await _qualifyAll(
      contactPeerId: contactPeerId,
      identities: identities,
    );
    if (qualification.denial != null) {
      return DirectMediaLibraryBatchForwardResult.denied(qualification.denial!);
    }

    final refreshed = <DirectMediaLibraryBatchForwardItemDraft>[];
    for (final source in qualification.sources!) {
      final original = originals[source.identity];
      if (original == null) {
        return const DirectMediaLibraryBatchForwardResult.denied(
          DirectMediaLibraryBatchForwardDenial.invalidSelection,
        );
      }
      refreshed.add(
        DirectMediaLibraryBatchForwardItemDraft(
          identity: source.identity,
          resolvedPath: source.resolvedPath,
          parentTimestamp: source.parent.timestamp,
          caption: original.caption,
          forwardProvenance: original.forwardProvenance,
        ),
      );
    }
    return DirectMediaLibraryBatchForwardResult.ready(
      DirectMediaLibraryBatchForwardDraft(items: refreshed),
    );
  }

  bool _hasValidInput(
    String contactPeerId,
    List<DirectReceivedMediaActionIdentity> identities,
  ) {
    if (contactPeerId.trim().isEmpty ||
        identities.isEmpty ||
        identities.length > 10) {
      return false;
    }
    final unique = <DirectReceivedMediaActionIdentity>{};
    for (final identity in identities) {
      if (identity.messageId.trim().isEmpty ||
          identity.attachmentId.trim().isEmpty ||
          !unique.add(identity)) {
        return false;
      }
    }
    return true;
  }

  Future<_QualificationBatchResult> _qualifyAll({
    required String contactPeerId,
    required List<DirectReceivedMediaActionIdentity> identities,
  }) async {
    final sources = <_QualifiedSource>[];
    for (final identity in identities) {
      final DirectMediaCurrentRowDecision decision;
      try {
        decision = await qualifyCurrentDirectMediaRow(
          identity: identity,
          loadParentMessage: _loadParentMessage,
          mediaAttachmentRepo: _mediaAttachmentRepository,
          resolveStoredPath: _resolveStoredPath,
          fileExists: _fileExists,
        );
      } catch (_) {
        return const _QualificationBatchResult.denied(
          DirectMediaLibraryBatchForwardDenial.sourceNotEligible,
        );
      }
      if (!decision.isQualified) {
        return const _QualificationBatchResult.denied(
          DirectMediaLibraryBatchForwardDenial.sourceNotEligible,
        );
      }
      final parent = decision.parent!;
      final current = decision.current!;
      if (parent.contactPeerId != contactPeerId) {
        return const _QualificationBatchResult.denied(
          DirectMediaLibraryBatchForwardDenial.contactScopeMismatch,
        );
      }
      if (current.mediaType != 'image' && current.mediaType != 'video') {
        return const _QualificationBatchResult.denied(
          DirectMediaLibraryBatchForwardDenial.nonVisualSource,
        );
      }
      final String resolvedPath;
      try {
        resolvedPath = _resolveStoredPath(decision.storedPath!);
        if (!_fileExists(resolvedPath)) {
          return const _QualificationBatchResult.denied(
            DirectMediaLibraryBatchForwardDenial.sourceNotEligible,
          );
        }
      } catch (_) {
        return const _QualificationBatchResult.denied(
          DirectMediaLibraryBatchForwardDenial.sourceNotEligible,
        );
      }
      sources.add(
        _QualifiedSource(
          identity: identity,
          parent: parent,
          resolvedPath: resolvedPath,
        ),
      );
    }
    sources.sort(_compareSourcesNewestFirst);
    return _QualificationBatchResult.ready(sources);
  }

  static int _compareSourcesNewestFirst(
    _QualifiedSource left,
    _QualifiedSource right,
  ) {
    final timestamp = right.parent.timestamp.compareTo(left.parent.timestamp);
    if (timestamp != 0) return timestamp;
    final message = right.identity.messageId.compareTo(left.identity.messageId);
    if (message != 0) return message;
    return right.identity.attachmentId.compareTo(left.identity.attachmentId);
  }
}
