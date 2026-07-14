import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';

/// 235: a received-media action a discussion-group member may take on one
/// incoming image/video attachment. The UI surfaces exactly what
/// [GroupReceivedMediaActionPolicy] authorizes; side effects live in the
/// wired coordinators, never here.
enum GroupReceivedMediaAction { save, share, deleteForMe, info, reply }

/// 235/239: pure capability policy for received media in chat and
/// announcement groups.
///
/// Fail-closed by construction:
/// - Only `GroupType.chat` and `GroupType.announcement` qualify — QA surfaces
///   are excluded wholesale (their action model is owned by later plans).
/// - Only INCOMING image/video rows qualify; outgoing and non-visual rows get
///   no received-media action.
/// - Only rows loaded under the exact `MediaOwnerLane.group` lane qualify;
///   same-ID direct collisions and unresolved legacy rows never do.
/// - Save/Share additionally require the row to be displayable-verified RIGHT
///   NOW (`canDisplayVerifiedGroupMedia`); the egress adapter re-verifies the
///   reloaded row again immediately before any egress call.
/// - Reply follows the caller's current write capability in chat groups ONLY.
///   Announcement media never grants Reply — not even to a writable admin —
///   so local media actions cannot leak publishing affordances.
class GroupReceivedMediaActionPolicy {
  const GroupReceivedMediaActionPolicy._();

  static Set<GroupReceivedMediaAction> capabilitiesFor({
    required GroupType groupType,
    required bool isIncoming,
    required MediaAttachment attachment,
    required bool canWrite,
    GroupPrivateMediaPolicy mediaPolicy =
        const GroupPrivateMediaPolicy.ordinary(),
  }) {
    if (groupType != GroupType.chat && groupType != GroupType.announcement) {
      return const {};
    }
    if (!isIncoming) return const {};
    if (mediaPolicy.requiresRedaction) return const {};
    final mediaType = attachment.mediaType;
    if (mediaType != 'image' && mediaType != 'video') return const {};
    if (attachment.ownerLane != MediaOwnerLane.group) return const {};

    final actions = <GroupReceivedMediaAction>{
      GroupReceivedMediaAction.deleteForMe,
      GroupReceivedMediaAction.info,
    };
    if (GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment)) {
      actions
        ..add(GroupReceivedMediaAction.save)
        ..add(GroupReceivedMediaAction.share);
    }
    if (groupType == GroupType.chat && canWrite) {
      actions.add(GroupReceivedMediaAction.reply);
    }
    return actions;
  }
}
