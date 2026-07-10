import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';

enum AnnouncementForwardCaptionMode { keep, remove, edit }

/// Local-only request for forwarding one received announcement attachment.
///
/// Source identity and ownership are used only to re-load the local row. They
/// are deliberately absent from [ForwardProvenance] and every wire payload.
class AnnouncementMediaForwardRequest extends GroupMediaForwardRequest {
  final AnnouncementForwardCaptionMode captionMode;
  final String? editedCaption;

  const AnnouncementMediaForwardRequest({
    required super.groupId,
    required super.messageId,
    required super.attachmentId,
    required super.initialCaption,
    required super.provenance,
    this.captionMode = AnnouncementForwardCaptionMode.keep,
    this.editedCaption,
  });

  factory AnnouncementMediaForwardRequest.forTest({
    String groupId = 'announcement-group',
    String messageId = 'announcement-message',
    String attachmentId = 'announcement-attachment',
    String initialCaption = '',
    required AnnouncementForwardCaptionMode captionMode,
    String? editedCaption,
  }) => AnnouncementMediaForwardRequest(
    groupId: groupId,
    messageId: messageId,
    attachmentId: attachmentId,
    initialCaption: initialCaption,
    provenance: const ForwardProvenance(
      operationDedupKey: 'announcement-forward-test-operation',
    ),
    captionMode: captionMode,
    editedCaption: editedCaption,
  );

  MediaOwnerLane get sourceOwner => MediaOwnerLane.group;

  String? get composedCaption => switch (captionMode) {
    AnnouncementForwardCaptionMode.keep => initialCaption,
    AnnouncementForwardCaptionMode.remove => null,
    AnnouncementForwardCaptionMode.edit => () {
      final value = editedCaption?.trim() ?? '';
      return value.isEmpty ? null : value;
    }(),
  };

  Map<String, Object?> get privacySafeDiagnostic => const {'isForwarded': true};
}

MediaOwnerLane announcementForwardDestinationOwner({required bool isContact}) =>
    isContact ? MediaOwnerLane.direct : MediaOwnerLane.group;
