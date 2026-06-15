import 'package:flutter_app/features/account_migration/application/migration_pending_work_manifest_validator.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_pending_work_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MigrationPendingWorkManifestValidator', () {
    test('reports blocking ownership identity gaps', () {
      final manifest = const MigrationPendingWorkManifestValidator()
          .validateRows(
            oneToOneMessageRows: const [
              {
                'id': 'msg-missing-peer',
                'status': 'failed',
                'is_incoming': 0,
                'sender_peer_id': 'peer-alice',
              },
            ],
            postRecipientDeliveryRows: const [
              {
                'post_id': '',
                'recipient_peer_id': 'peer-bob',
                'delivery_status': 'failed',
              },
            ],
            groupMessageRows: const [
              {
                'id': 'group-message-missing-group',
                'status': 'failed',
                'is_incoming': 0,
                'sender_peer_id': 'peer-alice',
              },
            ],
            groupPendingKeyRepairRows: const [
              {
                'id': 'repair-missing-message',
                'group_id': 'group-1',
                'payload_type': 'group_message',
                'key_epoch': 4,
                'replay_envelope_json': '{"kind":"group_offline_replay"}',
                'status': 'pending_key',
              },
            ],
          );

      expect(manifest.isValid, isFalse);
      expect(
        manifest.issues.map((issue) => issue.code).toSet(),
        containsAll(const [
          MigrationPendingWorkIssueCode.missingTargetPeerId,
          MigrationPendingWorkIssueCode.missingPostId,
          MigrationPendingWorkIssueCode.missingGroupId,
          MigrationPendingWorkIssueCode.missingMessageId,
        ]),
      );
      expect(manifest.issues.every((issue) => issue.blocking), isTrue);
    });

    test(
      'blocks missing required retry payloads and excludes terminal rows',
      () {
        final manifest = const MigrationPendingWorkManifestValidator()
            .validateRows(
              oneToOneMessageRows: const [
                {
                  'id': 'msg-delivered-in-retry-input',
                  'contact_peer_id': 'peer-bob',
                  'sender_peer_id': 'peer-alice',
                  'status': 'delivered',
                  'is_incoming': 0,
                },
              ],
              oneToOneUnackedMessageRows: const [
                {
                  'id': 'msg-unacked-missing-envelope',
                  'contact_peer_id': 'peer-bob',
                  'sender_peer_id': 'peer-alice',
                  'status': 'sent',
                  'is_incoming': 0,
                },
              ],
              postFollowOnEventRows: const [
                {
                  'event_id': 'follow-missing-envelope',
                  'event_type': 'reaction',
                  'post_id': 'post-1',
                  'sender_peer_id': 'peer-alice',
                  'created_at': '2026-06-01T12:00:00.000Z',
                },
              ],
              postFollowOnRecipientDeliveryRows: const [
                {
                  'event_id': 'follow-missing-envelope',
                  'recipient_peer_id': 'peer-bob',
                  'delivery_status': 'failed',
                },
              ],
              introductionOutboxRows: const [
                {
                  'delivery_id': 'intro-missing-envelope',
                  'introduction_id': 'intro-1',
                  'action': 'introduce',
                  'target_peer_id': 'peer-bob',
                  'sender_peer_id': 'peer-alice',
                  'delivery_status': 'failed',
                  'delivery_path': 'failed',
                },
              ],
              groupInboxRetryRows: const [
                {
                  'id': 'group-inbox-missing-payload',
                  'group_id': 'group-1',
                  'sender_peer_id': 'peer-alice',
                  'status': 'sent',
                  'is_incoming': 0,
                  'inbox_stored': 0,
                },
              ],
              groupPendingKeyRepairRows: const [
                {
                  'id': 'repair-missing-replay',
                  'group_id': 'group-1',
                  'message_id': 'group-message-1',
                  'payload_type': 'group_message',
                  'key_epoch': 4,
                  'status': 'pending_key',
                },
              ],
              groupReactionReplayRows: const [
                {
                  'reaction_id': 'reaction-missing-payload',
                  'group_id': 'group-1',
                  'message_id': 'group-message-1',
                  'sender_peer_id': 'peer-alice',
                  'delivery_status': 'failed',
                },
              ],
            );

        expect(
          manifest.items.where(
            (item) => item.sourceId == 'msg-delivered-in-retry-input',
          ),
          isEmpty,
        );
        expect(
          manifest.issues.map((issue) => issue.code).toSet(),
          containsAll(const [
            MigrationPendingWorkIssueCode.terminalRetryContradiction,
            MigrationPendingWorkIssueCode.missingRequiredPayload,
          ]),
        );
        expect(
          manifest.issues
              .where(
                (issue) =>
                    issue.code ==
                    MigrationPendingWorkIssueCode.missingRequiredPayload,
              )
              .every(
                (issue) =>
                    issue.policy ==
                    MigrationPendingWorkResumePolicy.pauseOnNewPhoneAfterCommit,
              ),
          isTrue,
        );
      },
    );

    test('keeps unsupported and unproven pending upload files blocking', () {
      final manifest = const MigrationPendingWorkManifestValidator()
          .validateRows(
            chatMediaRows: const [
              {
                'id': 'media-absolute',
                'message_id': 'msg-1',
                'local_path': '/var/mobile/Media/DCIM/100APPLE/source.jpg',
                'download_status': 'upload_pending',
              },
            ],
            postMediaUploadRows: const [
              {
                'post_id': 'post-1',
                'position': 0,
                'local_file_path': 'post_media/post-1/raw.jpg',
                'mime': 'image/jpeg',
                'kind': 'image',
              },
            ],
          );

      expect(manifest.isValid, isFalse);
      expect(
        manifest.issues.map((issue) => issue.code).toSet(),
        containsAll(const [
          MigrationPendingWorkIssueCode.unsupportedPendingFilePath,
          MigrationPendingWorkIssueCode.missingRequiredFileManifestItem,
        ]),
      );
      expect(
        manifest.issues.every(
          (issue) =>
              issue.policy ==
              MigrationPendingWorkResumePolicy.pauseOnNewPhoneAfterCommit,
        ),
        isTrue,
      );
    });

    test('blocks private material leakage in pending payload fields', () {
      final manifest = const MigrationPendingWorkManifestValidator()
          .validateRows(
            groupPendingMembershipRows: const [
              {
                'id': 'membership-leaks-key',
                'group_id': 'group-1',
                'sender_peer_id': 'peer-carol',
                'payload_json':
                    '{"kind":"members_added","privateKey":"raw-secret"}',
                'received_at': '2026-06-01T12:00:00.000Z',
                'created_at': '2026-06-01T12:00:00.000Z',
                'updated_at': '2026-06-01T12:00:00.000Z',
              },
            ],
            groupReactionReplayRows: const [
              {
                'reaction_id': 'reaction-leaks-key',
                'group_id': 'group-1',
                'message_id': 'group-message-1',
                'sender_peer_id': 'peer-alice',
                'inbox_retry_payload': '{"private_group_key":"raw-secret"}',
                'delivery_status': 'failed',
              },
            ],
          );

      expect(manifest.isValid, isFalse);
      expect(
        manifest.issues.where(
          (issue) =>
              issue.code ==
              MigrationPendingWorkIssueCode.sensitiveMaterialLeakage,
        ),
        hasLength(2),
      );
      expect(
        manifest.issues
            .where(
              (issue) =>
                  issue.code ==
                  MigrationPendingWorkIssueCode.sensitiveMaterialLeakage,
            )
            .every(
              (issue) =>
                  issue.policy ==
                  MigrationPendingWorkResumePolicy.failOnNewPhoneAfterCommit,
            ),
        isTrue,
      );
    });

    test('valid rows resume only on the new phone after commit', () {
      final manifest = const MigrationPendingWorkManifestValidator()
          .validateRows(
            fileManifestRelativePaths: const ['pending_uploads/msg-1/a.jpg'],
            chatMediaRows: const [
              {
                'id': 'media-valid',
                'message_id': 'msg-1',
                'local_path': 'pending_uploads/msg-1/a.jpg',
                'download_status': 'upload_pending',
              },
            ],
          );

      expect(manifest.isValid, isTrue);
      expect(manifest.items.single.sourceId, 'media-valid');
      expect(
        manifest.items.single.resumePolicy,
        MigrationPendingWorkResumePolicy.resumeOnNewPhoneAfterCommit,
      );
      expect(
        manifest.items.single.resumePolicy.name.toLowerCase(),
        isNot(contains('old')),
      );
    });
  });
}
