import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_received_media_action_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

// 235: pure capability policy for received-media actions in discussion groups.
// Save/Share require the current row to be displayable-verified; Info and
// Delete-for-me apply to any incoming discussion image/video; Reply follows
// canWrite. Outgoing, non-visual, non-group-lane, and QA rows get no
// received-media action at all.
// 239: announcement recipients get the same local received-media actions
// (Save/Share verified-only, Info/Delete always) but NEVER Reply — not even
// a writable admin.

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

MediaAttachment _attachment({
  String id = 'att-1',
  String messageId = 'msg-1',
  String mime = 'image/jpeg',
  String mediaType = 'image',
  String downloadStatus = 'done',
  String? localPath = 'media/group-1/att-1.jpg',
  String? contentHash = _validContentHash,
  String? encryptionKeyBase64 = 'a2V5',
  String? encryptionNonce = 'bm9uY2U=',
  String? encryptionScheme = kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  MediaOwnerLane? ownerLane = MediaOwnerLane.group,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 1024,
    mediaType: mediaType,
    localPath: localPath,
    downloadStatus: downloadStatus,
    createdAt: '2026-07-10T00:00:00.000Z',
    contentHash: contentHash,
    encryptionKeyBase64: encryptionKeyBase64,
    encryptionNonce: encryptionNonce,
    encryptionScheme: encryptionScheme,
    ownerLane: ownerLane,
  );
}

Set<GroupReceivedMediaAction> _capabilities({
  GroupType groupType = GroupType.chat,
  bool isIncoming = true,
  bool canWrite = true,
  MediaAttachment? attachment,
}) {
  return GroupReceivedMediaActionPolicy.capabilitiesFor(
    groupType: groupType,
    isIncoming: isIncoming,
    attachment: attachment ?? _attachment(),
    canWrite: canWrite,
  );
}

void main() {
  group('GroupReceivedMediaActionPolicy', () {
    test(
      'GMA-01 discussion incoming media capabilities vary safely by action and state',
      () {
        // Fully eligible incoming verified image in a writable discussion
        // group: every received-media action is available.
        expect(
          _capabilities(),
          GroupReceivedMediaAction.values.toSet(),
          reason:
              'verified incoming discussion image with write access '
              'exposes all actions',
        );

        // Verified state gates ONLY Save/Share; Info and Delete-for-me stay,
        // Reply stays with canWrite. Each row breaks exactly one verification
        // input of GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia.
        final unverifiedVariants = <String, MediaAttachment>{
          'pending download': _attachment(downloadStatus: 'pending'),
          'downloading': _attachment(downloadStatus: 'downloading'),
          'failed download': _attachment(downloadStatus: 'failed'),
          'integrity failed': _attachment(downloadStatus: 'integrity_failed'),
          'evicted local copy': _attachment(
            downloadStatus: 'evicted',
            localPath: null,
          ),
          'missing local path': _attachment(localPath: null),
          'missing content hash': _attachment(contentHash: null),
          'malformed content hash': _attachment(contentHash: 'not-a-hash'),
          'missing encryption metadata': _attachment(
            encryptionKeyBase64: null,
            encryptionNonce: null,
            encryptionScheme: null,
          ),
        };
        for (final entry in unverifiedVariants.entries) {
          expect(
            _capabilities(attachment: entry.value),
            {
              GroupReceivedMediaAction.deleteForMe,
              GroupReceivedMediaAction.info,
              GroupReceivedMediaAction.reply,
            },
            reason:
                '${entry.key}: unverified media must never expose '
                'Save/Share but keeps Info, Delete for me, and Reply',
          );
        }

        // canWrite gates ONLY Reply — independently of verified state.
        expect(
          _capabilities(canWrite: false),
          {
            GroupReceivedMediaAction.save,
            GroupReceivedMediaAction.share,
            GroupReceivedMediaAction.deleteForMe,
            GroupReceivedMediaAction.info,
          },
          reason: 'read-only member keeps Save/Share/Info/Delete but not Reply',
        );
        expect(
          _capabilities(
            canWrite: false,
            attachment: _attachment(downloadStatus: 'pending'),
          ),
          {GroupReceivedMediaAction.deleteForMe, GroupReceivedMediaAction.info},
          reason: 'unverified + read-only leaves only Info and Delete for me',
        );

        // Video parity: a verified incoming video exposes the same actions.
        expect(
          _capabilities(
            attachment: _attachment(
              mime: 'video/mp4',
              mediaType: 'video',
              localPath: 'media/group-1/att-1.mp4',
            ),
          ),
          GroupReceivedMediaAction.values.toSet(),
          reason: 'verified incoming discussion video exposes all actions',
        );

        // Outgoing rows get none, regardless of verified state or canWrite.
        expect(
          _capabilities(isIncoming: false),
          isEmpty,
          reason: 'outgoing media rows get no received-media action',
        );

        // Non-visual media gets none.
        expect(
          _capabilities(
            attachment: _attachment(mime: 'audio/mp4', mediaType: 'audio'),
          ),
          isEmpty,
          reason: 'audio attachments get no received-media action',
        );

        // QA groups get none even for verified incoming media with write
        // access. (The announcement capability contract is GMA-13's.)
        expect(
          _capabilities(groupType: GroupType.qa),
          isEmpty,
          reason: 'QA rows get no received-media action',
        );

        // Lane guard: a same-ID direct collision row or an unresolved legacy
        // row (hydrated ownerLane == null) never qualifies.
        expect(
          _capabilities(
            attachment: _attachment(ownerLane: MediaOwnerLane.direct),
          ),
          isEmpty,
          reason: 'direct-owned collision rows get no group media action',
        );
        expect(
          _capabilities(attachment: _attachment(ownerLane: null)),
          isEmpty,
          reason: 'unresolved-lane rows get no group media action',
        );
      },
    );

    test(
      'GMA-13 announcement member and admin get core media capabilities without reply while qa stays empty',
      () {
        const coreActions = {
          GroupReceivedMediaAction.save,
          GroupReceivedMediaAction.share,
          GroupReceivedMediaAction.deleteForMe,
          GroupReceivedMediaAction.info,
        };

        // Member (canWrite=false) and admin (canWrite=true) receive the SAME
        // four capabilities: announcement write permission never leaks Reply.
        for (final canWrite in [false, true]) {
          expect(
            _capabilities(
              groupType: GroupType.announcement,
              canWrite: canWrite,
            ),
            coreActions,
            reason:
                'verified incoming announcement image exposes exactly '
                'Save/Share/Info/Delete for me (canWrite=$canWrite)',
          );
          expect(
            _capabilities(
              groupType: GroupType.announcement,
              canWrite: canWrite,
              attachment: _attachment(
                mime: 'video/mp4',
                mediaType: 'video',
                localPath: 'media/group-1/att-1.mp4',
              ),
            ),
            coreActions,
            reason:
                'verified incoming announcement video exposes exactly '
                'Save/Share/Info/Delete for me (canWrite=$canWrite)',
          );

          // Unverified rows keep only the local metadata/deletion actions.
          expect(
            _capabilities(
              groupType: GroupType.announcement,
              canWrite: canWrite,
              attachment: _attachment(downloadStatus: 'pending'),
            ),
            {
              GroupReceivedMediaAction.deleteForMe,
              GroupReceivedMediaAction.info,
            },
            reason:
                'unverified announcement media keeps only Info and '
                'Delete for me (canWrite=$canWrite)',
          );
        }

        // Direction/type/lane negatives hold for announcements too.
        expect(
          _capabilities(groupType: GroupType.announcement, isIncoming: false),
          isEmpty,
          reason: 'outgoing announcement media gets no received-media action',
        );
        expect(
          _capabilities(
            groupType: GroupType.announcement,
            attachment: _attachment(mime: 'audio/mp4', mediaType: 'audio'),
          ),
          isEmpty,
          reason: 'announcement audio gets no received-media action',
        );
        expect(
          _capabilities(
            groupType: GroupType.announcement,
            attachment: _attachment(ownerLane: MediaOwnerLane.direct),
          ),
          isEmpty,
          reason: 'direct-owned collision rows stay excluded in announcements',
        );
        expect(
          _capabilities(
            groupType: GroupType.announcement,
            attachment: _attachment(ownerLane: null),
          ),
          isEmpty,
          reason: 'unresolved-lane rows stay excluded in announcements',
        );

        // QA fails closed wholesale.
        expect(
          _capabilities(groupType: GroupType.qa),
          isEmpty,
          reason: 'QA rows get no received-media action',
        );
      },
    );
  });
}
