import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// Every direct-media capability governed by the current durable parent.
///
/// Presentation surfaces may use this vocabulary to stay truthful, but an
/// irreversible action must evaluate it again from freshly loaded rows.
enum DirectPrivateMediaAction {
  openInApp,
  explicitDownload,
  saveToPhotos,
  saveToFiles,
  externalShare,
  internalForward,
  bookmark,
  sharedMedia,
  pictureInPicture,
  reply,
  info,
  deleteForMe,
}

/// Stable, non-sensitive reason for a direct-media capability decision.
enum DirectPrivateMediaEligibilityReason {
  ordinary,
  privateAvailable,
  privateTerminal,
  unsupported,
  parentMissing,
  parentHidden,
  parentDeleted,
  parentNotIncoming,
  attachmentMissing,
  wrongOwner,
  staleIdentity,
  integrityFailed,
  corruptPolicyState,
}

/// Privacy-minimized lifecycle facts permitted on the private Info surface.
///
/// This type deliberately has no caption, MIME, size, dimensions, duration,
/// path, key, nonce, thumbnail, or export-handle field.
class DirectPrivateMediaSafeInfo {
  const DirectPrivateMediaSafeInfo({
    required this.mode,
    required this.state,
    this.expiresAtMs,
    this.terminalAtMs,
  });

  final PrivateMediaMode mode;
  final PrivateMediaLifecycleState state;
  final int? expiresAtMs;
  final int? terminalAtMs;

  @override
  String toString() =>
      'DirectPrivateMediaSafeInfo(mode: ${mode.wireValue}, '
      'state: ${state.wireValue})';
}

/// One typed capability decision from a current direct parent/attachment.
class DirectPrivateMediaActionDecision {
  const DirectPrivateMediaActionDecision._({
    required this.reason,
    required this.safeReplyText,
    required this.safeInfo,
    required this.privateLifecycleState,
  });

  final DirectPrivateMediaEligibilityReason reason;
  final String safeReplyText;
  final DirectPrivateMediaSafeInfo? safeInfo;
  final PrivateMediaLifecycleState? privateLifecycleState;

  bool get requiresPrivacyMinimizedPresentation =>
      reason == DirectPrivateMediaEligibilityReason.privateAvailable ||
      reason == DirectPrivateMediaEligibilityReason.privateTerminal ||
      reason == DirectPrivateMediaEligibilityReason.unsupported;

  bool get isOrdinary => reason == DirectPrivateMediaEligibilityReason.ordinary;

  bool get isPrivateOrUnsupported =>
      reason == DirectPrivateMediaEligibilityReason.privateAvailable ||
      reason == DirectPrivateMediaEligibilityReason.privateTerminal ||
      reason == DirectPrivateMediaEligibilityReason.unsupported;

  bool get canEnterPictureInPicture =>
      allows(DirectPrivateMediaAction.pictureInPicture);

  bool allows(DirectPrivateMediaAction action) {
    if (isOrdinary) return true;

    if (!isPrivateOrUnsupported) return false;

    switch (action) {
      case DirectPrivateMediaAction.reply:
      case DirectPrivateMediaAction.info:
      case DirectPrivateMediaAction.deleteForMe:
        return true;
      case DirectPrivateMediaAction.openInApp:
        return reason == DirectPrivateMediaEligibilityReason.privateAvailable &&
            privateLifecycleState != null &&
            !privateLifecycleState!.isTerminal;
      case DirectPrivateMediaAction.explicitDownload:
        return reason == DirectPrivateMediaEligibilityReason.privateAvailable &&
            privateLifecycleState == PrivateMediaLifecycleState.available;
      case DirectPrivateMediaAction.saveToPhotos:
      case DirectPrivateMediaAction.saveToFiles:
      case DirectPrivateMediaAction.externalShare:
      case DirectPrivateMediaAction.internalForward:
      case DirectPrivateMediaAction.bookmark:
      case DirectPrivateMediaAction.sharedMedia:
      case DirectPrivateMediaAction.pictureInPicture:
        return false;
    }
  }

  /// Suitable for logs and typed denials; contains no parent or attachment
  /// payload data and intentionally omits private duration values.
  String get diagnosticCode => reason.name;
}

/// Central direct-chat action policy.
///
/// Callers pass stable expected identity separately from freshly loaded rows.
/// Any absence, owner mismatch, identity mismatch, invalid policy/state pair,
/// or integrity quarantine fails closed. [attachmentRequired] may be false
/// only for parent-level Reply/Info/Delete capability adaptation after private
/// attachment cleanup; byte-bearing actions always require the exact row.
abstract final class DirectPrivateMediaActionEligibility {
  static DirectPrivateMediaActionDecision evaluate({
    required ConversationMessage? parent,
    required MediaAttachment? attachment,
    required String expectedMessageId,
    String? expectedAttachmentId,
    bool attachmentRequired = true,
    PrivateMediaDirection? requiredDirection = PrivateMediaDirection.incoming,
    bool? requireIncoming,
  }) {
    DirectPrivateMediaActionDecision denied(
      DirectPrivateMediaEligibilityReason reason,
    ) => DirectPrivateMediaActionDecision._(
      reason: reason,
      safeReplyText: '',
      safeInfo: null,
      privateLifecycleState: null,
    );

    if (parent == null) {
      return denied(DirectPrivateMediaEligibilityReason.parentMissing);
    }
    if (parent.id != expectedMessageId) {
      return denied(DirectPrivateMediaEligibilityReason.staleIdentity);
    }
    if (parent.isDeleted) {
      return denied(DirectPrivateMediaEligibilityReason.parentDeleted);
    }
    if (parent.isHidden) {
      return denied(DirectPrivateMediaEligibilityReason.parentHidden);
    }
    final effectiveDirection = requireIncoming == null
        ? requiredDirection
        : requireIncoming
        ? PrivateMediaDirection.incoming
        : null;
    final parentDirection = parent.isIncoming
        ? PrivateMediaDirection.incoming
        : PrivateMediaDirection.outgoing;
    if (effectiveDirection != null && parentDirection != effectiveDirection) {
      return denied(DirectPrivateMediaEligibilityReason.parentNotIncoming);
    }

    final policy = parent.privateMediaPolicy;
    final state = parent.privateMediaState;
    final isConsistent = switch (policy.mode) {
      PrivateMediaMode.ordinary =>
        policy.version == 0 &&
            policy.durationSeconds == null &&
            state == PrivateMediaLifecycleState.none &&
            parent.privateMediaReceivedAtMs == null &&
            parent.privateMediaExpiresAtMs == null &&
            parent.privateMediaRevealedAtMs == null &&
            parent.privateMediaTerminalAtMs == null &&
            parent.privateMediaClockHighWaterMs == null,
      PrivateMediaMode.unsupported =>
        state == PrivateMediaLifecycleState.unsupported,
      PrivateMediaMode.protected ||
      PrivateMediaMode.viewOnce ||
      PrivateMediaMode.disappearing =>
        state == PrivateMediaLifecycleState.available ||
            state == PrivateMediaLifecycleState.opening ||
            state == PrivateMediaLifecycleState.viewing ||
            state == PrivateMediaLifecycleState.consumed ||
            state == PrivateMediaLifecycleState.expired,
    };
    if (!isConsistent) {
      return denied(DirectPrivateMediaEligibilityReason.corruptPolicyState);
    }

    if (attachment == null) {
      if (attachmentRequired) {
        return denied(DirectPrivateMediaEligibilityReason.attachmentMissing);
      }
    } else {
      if (attachment.ownerLane != MediaOwnerLane.direct) {
        return denied(DirectPrivateMediaEligibilityReason.wrongOwner);
      }
      if (attachment.messageId != expectedMessageId ||
          (expectedAttachmentId != null &&
              attachment.id != expectedAttachmentId)) {
        return denied(DirectPrivateMediaEligibilityReason.staleIdentity);
      }
      if (attachment.downloadStatus == 'integrity_failed') {
        return denied(DirectPrivateMediaEligibilityReason.integrityFailed);
      }
    }

    if (policy.mode == PrivateMediaMode.ordinary) {
      return DirectPrivateMediaActionDecision._(
        reason: DirectPrivateMediaEligibilityReason.ordinary,
        safeReplyText: parent.text,
        safeInfo: null,
        privateLifecycleState: state,
      );
    }

    final info = DirectPrivateMediaSafeInfo(
      mode: policy.mode,
      state: state,
      expiresAtMs: parent.privateMediaExpiresAtMs,
      terminalAtMs: parent.privateMediaTerminalAtMs,
    );
    if (policy.isUnsupported) {
      return DirectPrivateMediaActionDecision._(
        reason: DirectPrivateMediaEligibilityReason.unsupported,
        safeReplyText: 'Private media',
        safeInfo: info,
        privateLifecycleState: state,
      );
    }
    return DirectPrivateMediaActionDecision._(
      reason: state.isTerminal
          ? DirectPrivateMediaEligibilityReason.privateTerminal
          : DirectPrivateMediaEligibilityReason.privateAvailable,
      safeReplyText: 'Private media',
      safeInfo: info,
      privateLifecycleState: state,
    );
  }
}
