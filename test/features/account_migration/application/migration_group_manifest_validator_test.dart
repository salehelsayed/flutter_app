import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/account_migration/application/migration_group_manifest_builder.dart';
import 'package:flutter_app/features/account_migration/application/migration_group_manifest_validator.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_group_manifest.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('MigrationGroupManifestValidator', () {
    late FakeSecureKeyStore primaryStore;
    late FakeSecureKeyStore sharedStore;
    late MigrationGroupManifestValidator validator;

    setUp(() {
      primaryStore = FakeSecureKeyStore();
      sharedStore = FakeSecureKeyStore();
      validator = MigrationGroupManifestValidator(
        builder: MigrationGroupManifestBuilder(
          primaryStore: primaryStore,
          sharedStore: sharedStore,
          movedAccountPeerId: 'peer-alice',
        ),
      );
    });

    test(
      'fails when the oldest retained generation is missing even if latest exists',
      () async {
        final rows = <Map<String, Object?>>[];
        for (var generation = 4; generation <= 10; generation++) {
          rows.add(
            await _stageCommittedKey(primaryStore, sharedStore, generation),
          );
        }

        final manifest = await validator.validateRows(
          groupRows: [_groupRow()],
          committedGroupKeyRows: rows,
          groupMemberRows: [_movedMemberRow()],
        );

        expect(manifest.isValid, isFalse);
        expect(
          manifest.hasIssue(
            MigrationGroupManifestIssueCode.missingRetainedGroupKey,
          ),
          isTrue,
        );
        expect(
          manifest.issues
              .singleWhere(
                (issue) =>
                    issue.code ==
                    MigrationGroupManifestIssueCode.missingRetainedGroupKey,
              )
              .keyGeneration,
          3,
        );
      },
    );

    test(
      'requires committed retained shared mirrors to exist and match primary bytes',
      () async {
        final rows = <Map<String, Object?>>[];
        for (var generation = 3; generation <= 10; generation++) {
          rows.add(
            await _stageCommittedKey(
              primaryStore,
              sharedStore,
              generation,
              writeShared: generation != 6,
            ),
          );
        }
        await sharedStore.write(sharedGroupPushKeyName('group-1', 8), 'stale');

        final manifest = await validator.validateRows(
          groupRows: [_groupRow()],
          committedGroupKeyRows: rows,
          groupMemberRows: [_movedMemberRow()],
        );

        expect(manifest.isValid, isFalse);
        expect(
          manifest.hasIssue(
            MigrationGroupManifestIssueCode.missingSharedGroupKeyMirror,
          ),
          isTrue,
        );
        expect(
          manifest.hasIssue(
            MigrationGroupManifestIssueCode.sharedGroupKeyMirrorMismatch,
          ),
          isTrue,
        );
        expect(manifest.groups.single.pushPreviewReady, isFalse);
      },
    );

    test(
      'validates pending rotation drafts through primary storage without requiring shared mirrors',
      () async {
        final rows = <Map<String, Object?>>[];
        for (var generation = 3; generation <= 10; generation++) {
          rows.add(
            await _stageCommittedKey(primaryStore, sharedStore, generation),
          );
        }
        final pendingKey = groupKeyMaterialStoreName('group-1', 11);
        await primaryStore.write(pendingKey, 'pending-key-11');

        final manifest = await validator.validateRows(
          groupRows: [_groupRow()],
          committedGroupKeyRows: rows,
          pendingGroupKeyRows: [
            {
              'group_id': 'group-1',
              'key_generation': 11,
              'encrypted_key': secureStoreReferenceForKey(pendingKey),
              'created_at': '2026-06-01T12:11:00.000Z',
            },
          ],
          groupMemberRows: [_movedMemberRow()],
        );

        expect(manifest.isValid, isTrue);
        expect(manifest.groups.single.pendingDrafts.single.keyGeneration, 11);
        expect(
          await sharedStore.containsKey(sharedGroupPushKeyName('group-1', 11)),
          isFalse,
        );
      },
    );

    test(
      'does not require generation two when the retained window starts at three',
      () async {
        final rows = <Map<String, Object?>>[];
        for (var generation = 3; generation <= 10; generation++) {
          rows.add(
            await _stageCommittedKey(primaryStore, sharedStore, generation),
          );
        }

        final manifest = await validator.validateRows(
          groupRows: [_groupRow()],
          committedGroupKeyRows: rows,
          groupMemberRows: [_movedMemberRow()],
        );

        expect(manifest.isValid, isTrue);
        expect(
          manifest.groups.single.retainedGenerationRange,
          const MigrationGroupRetainedGenerationRange(
            minGeneration: 3,
            latestGeneration: 10,
          ),
        );
        expect(
          manifest.groups.single.committedKeys.map((key) => key.keyGeneration),
          [3, 4, 5, 6, 7, 8, 9, 10],
        );
        expect(
          manifest.issues.where(
            (issue) =>
                issue.keyGeneration == 2 &&
                issue.code ==
                    MigrationGroupManifestIssueCode.missingRetainedGroupKey,
          ),
          isEmpty,
        );
      },
    );

    test('rejects missing moved-account active group device', () async {
      final rows = <Map<String, Object?>>[];
      for (var generation = 3; generation <= 10; generation++) {
        rows.add(
          await _stageCommittedKey(primaryStore, sharedStore, generation),
        );
      }

      final manifest = await validator.validateRows(
        groupRows: [_groupRow()],
        committedGroupKeyRows: rows,
        groupMemberRows: [
          {
            'group_id': 'group-1',
            'peer_id': 'peer-bob',
            'role': 'writer',
            'devices_json': GroupMemberDeviceIdentity.listToJsonString([
              const GroupMemberDeviceIdentity(
                deviceId: 'bob-phone',
                transportPeerId: '12D3KooWBobPhone',
                deviceSigningPublicKey: 'bob-signing-pk',
              ),
            ]),
          },
        ],
      );

      expect(manifest.isValid, isFalse);
      expect(
        manifest.hasIssue(
          MigrationGroupManifestIssueCode.missingMovedAccountDevice,
        ),
        isTrue,
      );
    });

    test('rejects duplicate active moved-account group devices', () async {
      final rows = <Map<String, Object?>>[];
      for (var generation = 3; generation <= 10; generation++) {
        rows.add(
          await _stageCommittedKey(primaryStore, sharedStore, generation),
        );
      }

      final manifest = await validator.validateRows(
        groupRows: [_groupRow()],
        committedGroupKeyRows: rows,
        groupMemberRows: [
          {
            'group_id': 'group-1',
            'peer_id': 'peer-alice',
            'role': 'admin',
            'devices_json': GroupMemberDeviceIdentity.listToJsonString([
              const GroupMemberDeviceIdentity(
                deviceId: 'alice-old-phone',
                transportPeerId: '12D3KooWAliceOld',
                deviceSigningPublicKey: 'alice-old-signing-pk',
              ),
              const GroupMemberDeviceIdentity(
                deviceId: 'alice-new-phone',
                transportPeerId: '12D3KooWAliceNew',
                deviceSigningPublicKey: 'alice-new-signing-pk',
              ),
            ]),
            'joined_at': '2026-06-01T12:00:00.000Z',
          },
        ],
      );

      expect(manifest.isValid, isFalse);
      expect(
        manifest.hasIssue(
          MigrationGroupManifestIssueCode.duplicateMovedAccountActiveDevice,
        ),
        isTrue,
      );
    });

    test(
      'rejects missing pending-key repair and missing inbox cursor rows',
      () async {
        final rows = <Map<String, Object?>>[];
        for (var generation = 3; generation <= 10; generation++) {
          rows.add(
            await _stageCommittedKey(primaryStore, sharedStore, generation),
          );
        }

        final manifest = await validator.validateRows(
          groupRows: [_groupRow()],
          committedGroupKeyRows: rows,
          groupMemberRows: [_movedMemberRow()],
          groupMessageRows: [
            {
              'id': 'pending-message-1',
              'group_id': 'group-1',
              'sender_peer_id': 'peer-bob',
              'status': 'pending_key',
              'key_generation': 9,
            },
          ],
          groupMessageReceiptRows: [
            {
              'group_id': 'group-1',
              'message_id': 'pending-message-1',
              'receipt_type': 'delivered',
              'member_peer_id': 'peer-alice',
              'receipt_at': '2026-06-01T12:12:00.000Z',
              'created_at': '2026-06-01T12:12:01.000Z',
              'updated_at': '2026-06-01T12:12:02.000Z',
            },
          ],
        );

        expect(manifest.isValid, isFalse);
        expect(
          manifest.hasIssue(
            MigrationGroupManifestIssueCode.missingPendingKeyRepair,
          ),
          isTrue,
        );
        expect(
          manifest.hasIssue(
            MigrationGroupManifestIssueCode.missingGroupInboxCursor,
          ),
          isTrue,
        );
      },
    );

    test('rejects malformed required durable group state rows', () async {
      final rows = <Map<String, Object?>>[];
      for (var generation = 3; generation <= 10; generation++) {
        rows.add(
          await _stageCommittedKey(primaryStore, sharedStore, generation),
        );
      }

      final manifest = await validator.validateRows(
        groupRows: [_groupRow()],
        committedGroupKeyRows: rows,
        groupMemberRows: [_movedMemberRow()],
        pendingKeyRepairRows: [
          {
            'id': 'repair-missing-message',
            'group_id': 'group-1',
            'payload_type': 'group_message',
            'status': 'pending_key',
            'created_at': '2026-06-01T12:13:00.000Z',
            'updated_at': '2026-06-01T12:14:00.000Z',
          },
        ],
        pendingMembershipMessageRows: [
          {
            'id': 'membership-missing-payload',
            'group_id': 'group-1',
            'sender_peer_id': 'peer-bob',
            'received_at': '2026-06-01T12:15:00.000Z',
          },
        ],
        welcomeKeyPackageTombstoneRows: [
          {
            'group_id': 'group-1',
            'package_id': 'kp-bob-phone',
            'recipient_device_id': 'bob-phone',
            'invite_id': 'invite-bob',
            'consumed_at': '2026-06-01T12:16:00.000Z',
            'expires_at': '2026-06-02T12:16:00.000Z',
          },
        ],
        groupInboxCursorRows: [
          {
            'group_id': 'group-1',
            'created_at': '2026-06-01T12:17:00.000Z',
            'updated_at': '2026-06-01T12:18:00.000Z',
          },
        ],
      );

      expect(manifest.isValid, isFalse);
      expect(
        manifest.hasIssue(
          MigrationGroupManifestIssueCode.malformedPendingKeyRepair,
        ),
        isTrue,
      );
      expect(
        manifest.hasIssue(
          MigrationGroupManifestIssueCode.malformedPendingMembershipMessage,
        ),
        isTrue,
      );
      expect(
        manifest.hasIssue(
          MigrationGroupManifestIssueCode.malformedWelcomeKeyPackageTombstone,
        ),
        isTrue,
      );
      expect(
        manifest.hasIssue(
          MigrationGroupManifestIssueCode.malformedGroupInboxCursor,
        ),
        isTrue,
      );
    });
  });
}

Map<String, Object?> _groupRow() => {'id': 'group-1', 'name': 'Team Chat'};

Map<String, Object?> _movedMemberRow() => {
  'group_id': 'group-1',
  'peer_id': 'peer-alice',
  'role': 'admin',
  'devices_json': GroupMemberDeviceIdentity.listToJsonString([
    const GroupMemberDeviceIdentity(
      deviceId: 'alice-phone',
      transportPeerId: '12D3KooWAlicePhone',
      deviceSigningPublicKey: 'alice-signing-pk',
      mlKemPublicKey: 'alice-mlkem-pk',
      keyPackageId: 'kp-alice',
      keyPackagePublicMaterial: 'kp-public-alice',
    ),
  ]),
  'joined_at': '2026-06-01T12:00:00.000Z',
};

Future<Map<String, Object?>> _stageCommittedKey(
  FakeSecureKeyStore primaryStore,
  FakeSecureKeyStore sharedStore,
  int generation, {
  bool writeShared = true,
}) async {
  final primaryKey = groupKeyMaterialStoreName('group-1', generation);
  final value = 'base64-key-$generation';
  await primaryStore.write(primaryKey, value);
  if (writeShared) {
    await sharedStore.write(
      sharedGroupPushKeyName('group-1', generation),
      value,
    );
  }
  return {
    'group_id': 'group-1',
    'key_generation': generation,
    'encrypted_key': secureStoreReferenceForKey(primaryKey),
    'created_at': '2026-06-01T12:0${generation % 10}:00.000Z',
  };
}
