import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_safety_number.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_picker.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

Widget _localizedMaterialApp({required Widget home}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

// --- FakeIdentityRepository ---

class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;
  FakeIdentityRepository({this.identity});

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

class _ControlledRecoveryIdentityRepository extends FakeIdentityRepository {
  bool beginRecoveryOnNextLoad = false;

  _ControlledRecoveryIdentityRepository({super.identity});

  @override
  Future<IdentityModel?> loadIdentity() async {
    final loaded = await super.loadIdentity();
    if (beginRecoveryOnNextLoad) {
      beginRecoveryOnNextLoad = false;
      groupRecoveryGate.begin();
    }
    return loaded;
  }
}

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String docsPath;

  _FakePathProvider(this.docsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

class _TrackingInviteDeliveryAttemptRepository
    implements GroupInviteDeliveryAttemptRepository {
  final Map<String, GroupInviteDeliveryAttempt> attempts = {};

  String _key(String groupId, String peerId) => '$groupId::$peerId';

  @override
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt) async {
    attempts[_key(attempt.groupId, attempt.peerId)] = attempt;
  }

  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async => attempts[_key(groupId, peerId)];

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async => attempts.values
      .where((attempt) => attempt.groupId == groupId)
      .toList(growable: false);

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async =>
      attempts[_key(groupId, peerId)]?.status ??
      GroupInviteDeliveryStatus.unknown;

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async => {
    for (final attempt in attempts.values.where((a) => a.groupId == groupId))
      attempt.peerId: attempt.status,
  };

  @override
  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  }) async {
    final now = (updatedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = attempts[key];
    attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: status,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: status,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<void> markJoined({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? joinedAt,
  }) async {
    final now = (joinedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = attempts[key];
    attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<void> markRevoked({
    required String groupId,
    required String peerId,
    DateTime? revokedAt,
  }) async {
    final now = (revokedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = attempts[key];
    attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: GroupInviteDeliveryStatus.revoked,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: GroupInviteDeliveryStatus.revoked,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<void> markDeclined({
    required String groupId,
    required String peerId,
    DateTime? declinedAt,
  }) async {
    final now = (declinedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = attempts[key];
    if (existing?.status == GroupInviteDeliveryStatus.joined) {
      return;
    }
    attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: GroupInviteDeliveryStatus.declined,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: GroupInviteDeliveryStatus.declined,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<int> deleteAttempt({
    required String groupId,
    required String peerId,
  }) async => 0;

  @override
  Future<int> deleteAttemptsForGroup(String groupId) async => 0;
}

// --- Test data ---

final testIdentity = IdentityModel(
  peerId: 'peer-admin',
  publicKey: 'pk-admin',
  privateKey: 'sk-admin',
  mnemonic12:
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  mlKemPublicKey: 'mlkem-pk-admin',
  username: 'Admin',
  createdAt: DateTime.now().toUtc().toIso8601String(),
  updatedAt: DateTime.now().toUtc().toIso8601String(),
);

GroupModel makeAdminGroup() => GroupModel(
  id: 'group-1',
  name: 'Test Group',
  type: GroupType.chat,
  topicName: 'topic-1',
  description: 'A test group',
  createdAt: DateTime.now().toUtc(),
  createdBy: 'peer-admin',
  myRole: GroupRole.admin,
);

GroupModel makeMemberGroup() => GroupModel(
  id: 'group-1',
  name: 'Test Group',
  type: GroupType.chat,
  topicName: 'topic-1',
  description: 'A test group',
  createdAt: DateTime.now().toUtc(),
  createdBy: 'peer-admin',
  myRole: GroupRole.member,
);

GroupMember makeMember({
  required String peerId,
  required String username,
  MemberRole role = MemberRole.writer,
  String? publicKey,
  String? mlKemPublicKey,
}) => GroupMember(
  groupId: 'group-1',
  peerId: peerId,
  username: username,
  role: role,
  publicKey: publicKey,
  mlKemPublicKey: mlKemPublicKey,
  joinedAt: DateTime.now().toUtc(),
);

ContactModel makeContact({
  required String peerId,
  required String username,
  required String publicKey,
  String? mlKemPublicKey,
}) => ContactModel(
  peerId: peerId,
  publicKey: publicKey,
  rendezvous: '/ip4/127.0.0.1/tcp/4001',
  username: username,
  signature: 'sig-$peerId',
  scannedAt: DateTime.utc(2026, 4, 30).toIso8601String(),
  mlKemPublicKey: mlKemPublicKey,
);

// --- Helpers ---

/// Pump enough frames for async operations to complete.
/// AmbientBackground has an infinite animation, so pumpAndSettle will timeout.
Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _groupEditRecoveryWaitCopy = 'Please wait while this device catches up.';

String _groupEditRecoveryElapsedCopy(int seconds) => 'Waiting ${seconds}s';

final _tinyPngBytes = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Finder _groupEditNameField() {
  return find.descendant(
    of: find.byKey(const ValueKey('group-edit-name-field')),
    matching: find.byType(TextField),
  );
}

Finder _groupEditDescriptionField() {
  return find.descendant(
    of: find.byKey(const ValueKey('group-edit-description-field')),
    matching: find.byType(TextField),
  );
}

FilledButton _groupEditSaveButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.byKey(const ValueKey('group-edit-save')),
  );
}

Future<void> _seedEditableGroup(
  InMemoryGroupRepository groupRepo, {
  GroupModel? group,
}) async {
  final resolvedGroup = group ?? makeAdminGroup();
  await groupRepo.saveGroup(resolvedGroup);
  await _saveGroupReplayKey(groupRepo, groupId: resolvedGroup.id);
  await groupRepo.saveMember(
    GroupMember(
      groupId: resolvedGroup.id,
      peerId: testIdentity.peerId,
      username: testIdentity.username,
      role: MemberRole.admin,
      publicKey: testIdentity.publicKey,
      mlKemPublicKey: testIdentity.mlKemPublicKey,
      joinedAt: DateTime.now().toUtc(),
    ),
  );
}

Future<void> _pumpEditableGroupInfo(
  WidgetTester tester, {
  required InMemoryGroupRepository groupRepo,
  GroupModel? group,
  IdentityRepository? identityRepo,
  FakeBridge? bridge,
  FakeP2PService? p2pService,
  FakeMediaPicker? mediaPicker,
  ImageProcessor? imageProcessor,
  UploadGroupAvatarFn? uploadGroupAvatarFn,
  InMemoryGroupMessageRepository? msgRepo,
}) async {
  await tester.pumpWidget(
    _localizedMaterialApp(
      home: GroupInfoWired(
        group: group ?? makeAdminGroup(),
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        contactRepo: InMemoryContactRepository(),
        bridge: bridge ?? FakeBridge(),
        identityRepo:
            identityRepo ?? FakeIdentityRepository(identity: testIdentity),
        p2pService: p2pService ?? FakeP2PService(),
        mediaPicker: mediaPicker,
        imageProcessor: imageProcessor,
        uploadGroupAvatarFn: uploadGroupAvatarFn ?? uploadGroupAvatar,
      ),
    ),
  );
  await pumpFrames(tester);
}

/// A [FakeBridge] that throws when a specific command is sent (e.g. a hard
/// `group:inboxStore` failure after a successful publish).
class _ThrowOnCommandBridge extends FakeBridge {
  _ThrowOnCommandBridge(this.command, {super.initialResponses});

  final String command;

  @override
  Future<String> send(String message) async {
    final cmd = (jsonDecode(message) as Map<String, dynamic>)['cmd'] as String?;
    if (cmd == command) {
      throw Exception('Simulated $command failure');
    }
    return super.send(message);
  }
}

/// A [FakeBridge] whose first `group:publish` runs [onPublish] (e.g. simulate a
/// newer remote metadata landing) and then reports a soft failure.
class _PublishFailAfterHookBridge extends FakeBridge {
  _PublishFailAfterHookBridge(this.onPublish);

  final Future<void> Function() onPublish;
  bool _fired = false;

  @override
  Future<String> send(String message) async {
    final cmd = (jsonDecode(message) as Map<String, dynamic>)['cmd'] as String?;
    if (cmd == 'group:publish' && !_fired) {
      _fired = true;
      await onPublish();
      return jsonEncode({
        'ok': false,
        'errorMessage': 'simulated publish failure after remote update',
      });
    }
    return super.send(message);
  }
}

Future<void> _openGroupDetailsEditor(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('group-edit-details-button')));
  await pumpFrames(tester);
}

Future<void> _pickGroupEditPhoto(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const ValueKey('group-edit-pick-photo')));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await pumpFrames(tester, count: 10);
}

Future<void> _tapGroupEditSave(WidgetTester tester) async {
  final saveButton = find.byKey(const ValueKey('group-edit-save'));
  await tester.ensureVisible(saveButton);
  await pumpFrames(tester, count: 2);
  await tester.tap(saveButton, warnIfMissed: false);
}

ImageProcessor _testAvatarImageProcessor([Uint8List? processedBytes]) {
  return ImageProcessor(
    compressFile:
        ({
          required String path,
          required int quality,
          required bool keepExif,
          int minWidth = 1920,
          int minHeight = 1080,
        }) async {
          final outputPath = '${path}_processed.jpg';
          File(
            outputPath,
          ).writeAsBytesSync(processedBytes ?? _tinyPngBytes, flush: true);
          return XFile(outputPath);
        },
  );
}

Future<Directory> _installPathProviderTempDirForTest() async {
  final previousPathProvider = PathProviderPlatform.instance;
  final tempDir = Directory.systemTemp.createTempSync(
    'group_info_wired_avatar_',
  );
  PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  addTearDown(() {
    PathProviderPlatform.instance = previousPathProvider;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  return tempDir;
}

Future<File> _writePickedAvatar(Directory tempDir, String name) async {
  final file = File(p.join(tempDir.path, '$name.jpg'));
  file.writeAsBytesSync(_tinyPngBytes, flush: true);
  return file;
}

Future<void> _waitForInviteStatus({
  required _TrackingInviteDeliveryAttemptRepository repo,
  required String groupId,
  required String peerId,
  required GroupInviteDeliveryStatus status,
}) async {
  for (var i = 0; i < 20; i++) {
    final current = await repo.getStatusForMember(
      groupId: groupId,
      peerId: peerId,
    );
    if (current == status) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for $peerId invite status $status');
}

Future<void> confirmRemoveMemberDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('group-remove-confirm')));
  await pumpFrames(tester, count: 30);
}

Future<void> openRoleActionMenu(WidgetTester tester, String peerId) async {
  final actionButton = find.byKey(ValueKey('group-member-actions-$peerId'));
  await tester.ensureVisible(actionButton);
  await pumpFrames(tester, count: 5);
  await tester.tap(actionButton, warnIfMissed: false);
  await pumpFrames(tester, count: 5);
}

Future<void> confirmRoleChangeDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('group-role-change-confirm')));
  await pumpFrames(tester, count: 30);
}

Future<void> confirmDissolveGroupDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('group-dissolve-confirm')));
  await pumpFrames(tester, count: 30);
}

Future<void> confirmDeleteLocalGroupDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('group-delete-local-confirm')));
  await pumpFrames(tester, count: 30);
}

Future<void> tapLeaveGroupButton(
  WidgetTester tester, {
  int settleFrameCount = 20,
}) async {
  final leaveButton = find.byKey(const ValueKey('group-leave-button'));
  await tester.scrollUntilVisible(
    leaveButton,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(leaveButton);
  await pumpFrames(tester, count: settleFrameCount);
}

Future<void> scrollToDissolveGroupButton(WidgetTester tester) async {
  final dissolveButton = find.byKey(const ValueKey('group-dissolve-button'));
  await tester.scrollUntilVisible(
    dissolveButton,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await pumpFrames(tester, count: 5);
}

Future<void> scrollToDeleteLocalGroupButton(WidgetTester tester) async {
  final deleteButton = find.byKey(const ValueKey('group-delete-local-button'));
  await tester.scrollUntilVisible(
    deleteButton,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await pumpFrames(tester, count: 5);
}

Future<void> _saveGroupReplayKey(
  InMemoryGroupRepository groupRepo, {
  String groupId = 'group-1',
  int generation = 1,
}) async {
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: generation,
      encryptedKey: 'test-group-key-$generation',
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

Future<
  ({
    _TrackingInviteDeliveryAttemptRepository inviteStatusRepo,
    FakeP2PService p2pService,
  })
>
_pumpResendInviteSurface(
  WidgetTester tester, {
  required bool sendMessageResult,
  required bool storeInInboxResult,
  bool hasRecipientSecureKey = true,
}) async {
  final groupRepo = InMemoryGroupRepository();
  final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
  final group = makeAdminGroup();
  await groupRepo.saveGroup(group);
  await _saveGroupReplayKey(groupRepo);
  await groupRepo.saveMember(
    makeMember(
      peerId: 'peer-admin',
      username: 'Admin',
      role: MemberRole.admin,
      publicKey: testIdentity.publicKey,
      mlKemPublicKey: testIdentity.mlKemPublicKey,
    ),
  );
  await groupRepo.saveMember(
    makeMember(
      peerId: 'peer-alice',
      username: 'Alice',
      publicKey: 'pk-alice',
      mlKemPublicKey: hasRecipientSecureKey ? 'mlkem-pk-alice' : null,
    ),
  );
  await inviteStatusRepo.saveAttempt(
    GroupInviteDeliveryAttempt(
      groupId: 'group-1',
      peerId: 'peer-alice',
      username: 'Alice',
      status: GroupInviteDeliveryStatus.needsResend,
      attemptedAt: DateTime.utc(2026, 5, 7, 12),
      updatedAt: DateTime.utc(2026, 5, 7, 12),
      lastError: 'send_failed',
    ),
  );

  final p2pService = FakeP2PService(
    initialState: const NodeState(isStarted: true),
    sendMessageResult: sendMessageResult,
    storeInInboxResult: storeInInboxResult,
  );

  await tester.pumpWidget(
    _localizedMaterialApp(
      home: GroupInfoWired(
        group: group,
        groupRepo: groupRepo,
        contactRepo: InMemoryContactRepository(),
        bridge: FakeBridge(),
        identityRepo: FakeIdentityRepository(identity: testIdentity),
        p2pService: p2pService,
        inviteDeliveryAttemptRepo: inviteStatusRepo,
      ),
    ),
  );
  await pumpFrames(tester);

  return (inviteStatusRepo: inviteStatusRepo, p2pService: p2pService);
}

Future<void> _tapResendInviteButton(
  WidgetTester tester, {
  String peerId = 'peer-alice',
}) async {
  final button = find.byKey(ValueKey('group-member-resend-invite-$peerId'));
  await tester.ensureVisible(button);
  await pumpFrames(tester, count: 5);
  await tester.tap(button, warnIfMissed: false);
  await pumpFrames(tester, count: 40);
}

Map<String, dynamic> _storedGroupReplayEnvelope(String message) {
  return jsonDecode(message) as Map<String, dynamic>;
}

Map<String, dynamic> _decodedGroupReplayPayload(String message) {
  final envelope = _storedGroupReplayEnvelope(message);
  final ciphertext = envelope['ciphertext'];
  if (envelope['kind'] == 'group_offline_replay' && ciphertext is String) {
    return jsonDecode(ciphertext) as Map<String, dynamic>;
  }
  return envelope;
}

class _Gca008RemovalFailureCase {
  const _Gca008RemovalFailureCase({
    required this.name,
    required this.responses,
    required this.expectInboxStore,
    required this.expectGenerateNextKey,
    required this.expectMemberRemoved,
  });

  final String name;
  final Map<String, Map<String, dynamic>> responses;
  final bool expectInboxStore;
  final bool expectGenerateNextKey;

  /// Whether the removal should STAND (no rollback). True for post-broadcast
  /// failures (INV-R2: re-adding would re-grant the rotated-away key); false for
  /// the pre-broadcast failure where rolling back is still correct.
  final bool expectMemberRemoved;
}

Future<
  ({
    InMemoryGroupRepository groupRepo,
    InMemoryGroupMessageRepository msgRepo,
    FakeBridge bridge,
  })
>
_pumpGca008RemovalFailureFixture(
  WidgetTester tester, {
  required DateTime preRemovalWatermark,
  required Map<String, Map<String, dynamic>> bridgeResponses,
}) async {
  final groupRepo = InMemoryGroupRepository();
  final msgRepo = InMemoryGroupMessageRepository();
  final group = makeAdminGroup().copyWith(
    lastMembershipEventAt: preRemovalWatermark,
  );
  await groupRepo.saveGroup(group);
  await _saveGroupReplayKey(groupRepo);

  await groupRepo.saveMember(
    makeMember(
      peerId: 'peer-admin',
      username: 'Admin',
      role: MemberRole.admin,
      publicKey: 'pk-admin',
      mlKemPublicKey: 'mlkem-pk-admin',
    ),
  );
  await groupRepo.saveMember(
    makeMember(
      peerId: 'peer-alice',
      username: 'Alice',
      publicKey: 'pk-alice',
      mlKemPublicKey: 'mlkem-pk-alice',
    ),
  );
  await groupRepo.saveMember(
    makeMember(
      peerId: 'peer-bob',
      username: 'Bob',
      publicKey: 'pk-bob',
      mlKemPublicKey: 'mlkem-pk-bob',
    ),
  );

  final bridge = FakeBridge(
    initialResponses: {
      'group:publish': {'ok': true, 'messageId': 'msg-1'},
      'group:inboxStore': {'ok': true},
      'group:generateNextKey': {
        'ok': true,
        'groupKey': 'fake-rotated-key',
        'keyEpoch': 2,
      },
      ...bridgeResponses,
    },
  );

  await tester.pumpWidget(
    _localizedMaterialApp(
      home: GroupInfoWired(
        group: group,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        contactRepo: InMemoryContactRepository(),
        bridge: bridge,
        identityRepo: FakeIdentityRepository(identity: testIdentity),
        p2pService: FakeP2PService(),
      ),
    ),
  );
  await pumpFrames(tester);

  return (groupRepo: groupRepo, msgRepo: msgRepo, bridge: bridge);
}

Future<void> _removeAliceFromGroupInfo(WidgetTester tester) async {
  final removeButton = find.byKey(
    const ValueKey('group-member-remove-peer-alice'),
  );
  await tester.ensureVisible(removeButton);
  await pumpFrames(tester, count: 5);
  await tester.tap(removeButton, warnIfMissed: false);
  await pumpFrames(tester);
  await confirmRemoveMemberDialog(tester);
}

List<String> _lastUpdateConfigMemberPeerIds(FakeBridge bridge) {
  final updateConfigMessages = bridge.sentMessages
      .where((message) {
        final parsed = jsonDecode(message) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:updateConfig';
      })
      .toList(growable: false);
  expect(updateConfigMessages, isNotEmpty);

  final parsed = jsonDecode(updateConfigMessages.last) as Map<String, dynamic>;
  final payload = parsed['payload'] as Map<String, dynamic>;
  final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
  final members = groupConfig['members'] as List<dynamic>;
  return members
      .map((member) => (member as Map<String, dynamic>)['peerId'] as String)
      .toList(growable: false);
}

void main() {
  group('GroupInfoWired', () {
    setUp(() {
      groupRecoveryGate.resetForTest();
    });

    tearDown(() {
      groupRecoveryGate.resetForTest();
    });

    testWidgets('loads and displays group members on init', (tester) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      final m1 = makeMember(
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
      );
      final m2 = makeMember(peerId: 'peer-alice', username: 'Alice');
      final m3 = makeMember(peerId: 'peer-bob', username: 'Bob');

      await groupRepo.saveMember(m1);
      await groupRepo.saveMember(m2);
      await groupRepo.saveMember(m3);

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('You'), findsOneWidget); // self member shows "You"
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets(
      'UP-001 reloads visible member list from local DB after create add remove and re-add',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );

        Future<void> pumpSnapshot(String snapshotId) async {
          await tester.pumpWidget(
            _localizedMaterialApp(
              home: GroupInfoWired(
                key: ValueKey('up001-$snapshotId'),
                group: group,
                groupRepo: groupRepo,
                contactRepo: InMemoryContactRepository(),
                bridge: FakeBridge(),
                identityRepo: FakeIdentityRepository(identity: testIdentity),
                p2pService: FakeP2PService(),
              ),
            ),
          );
          await pumpFrames(tester);
        }

        await pumpSnapshot('create');
        expect(find.text('You'), findsOneWidget);
        expect(find.text('Bob'), findsNothing);

        await groupRepo.saveMember(
          makeMember(peerId: 'peer-bob', username: 'Bob'),
        );
        await pumpSnapshot('add');
        expect(find.text('You'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);

        await groupRepo.removeMember(group.id, 'peer-bob');
        await pumpSnapshot('remove');
        expect(find.text('You'), findsOneWidget);
        expect(find.text('Bob'), findsNothing);

        await groupRepo.saveMember(
          makeMember(peerId: 'peer-bob', username: 'Bob'),
        );
        await pumpSnapshot('readd');
        expect(find.text('You'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);
      },
    );

    testWidgets('loads invite delivery statuses for member rows', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );
      await groupRepo.saveMember(
        makeMember(peerId: 'peer-alice', username: 'Alice'),
      );
      await inviteStatusRepo.saveAttempt(
        GroupInviteDeliveryAttempt(
          groupId: 'group-1',
          peerId: 'peer-alice',
          username: 'Alice',
          status: GroupInviteDeliveryStatus.needsResend,
          attemptedAt: DateTime.utc(2026, 5, 7, 12),
          updatedAt: DateTime.utc(2026, 5, 7, 12),
        ),
      );

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
            inviteDeliveryAttemptRepo: inviteStatusRepo,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Resend needed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('group-member-resend-invite-peer-alice')),
        findsOneWidget,
      );
    });

    testWidgets('GM-036 mixed invite statuses remain visible after reload', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );
      await groupRepo.saveMember(
        makeMember(peerId: 'peer-charlie', username: 'Charlie'),
      );
      await groupRepo.saveMember(
        makeMember(peerId: 'peer-dave', username: 'Dave'),
      );
      await inviteStatusRepo.saveAttempt(
        GroupInviteDeliveryAttempt(
          groupId: 'group-1',
          peerId: 'peer-charlie',
          username: 'Charlie',
          status: GroupInviteDeliveryStatus.sent,
          attemptedAt: DateTime.utc(2026, 5, 12, 8),
          updatedAt: DateTime.utc(2026, 5, 12, 8),
        ),
      );
      await inviteStatusRepo.saveAttempt(
        GroupInviteDeliveryAttempt(
          groupId: 'group-1',
          peerId: 'peer-dave',
          username: 'Dave',
          status: GroupInviteDeliveryStatus.needsResend,
          attemptedAt: DateTime.utc(2026, 5, 12, 8),
          updatedAt: DateTime.utc(2026, 5, 12, 8),
          lastError: 'send_failed',
        ),
      );

      Future<void> pumpGroupInfo() async {
        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: FakeBridge(),
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
              inviteDeliveryAttemptRepo: inviteStatusRepo,
            ),
          ),
        );
        await pumpFrames(tester);
      }

      Future<void> expectMixedStatusesVisible() async {
        expect(find.text('Charlie'), findsOneWidget);
        expect(find.text('Dave'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('group-member-invite-status-peer-charlie')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('group-member-invite-status-peer-dave')),
          findsOneWidget,
        );
        expect(find.text('Invite sent'), findsOneWidget);
        expect(find.text('Resend needed'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('group-member-resend-invite-peer-charlie')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('group-member-resend-invite-peer-dave')),
          findsOneWidget,
        );
      }

      await pumpGroupInfo();
      await expectMixedStatusesVisible();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpGroupInfo();
      await expectMixedStatusesVisible();

      final daveAttempt = await inviteStatusRepo.getAttempt(
        groupId: 'group-1',
        peerId: 'peer-dave',
      );
      expect(daveAttempt, isNotNull);
      expect(daveAttempt!.status, GroupInviteDeliveryStatus.needsResend);
      expect(daveAttempt.lastError, 'send_failed');
    });

    testWidgets(
      'overlays durable member_joined timeline state onto invite statuses',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-alice', username: 'Alice'),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-bob', username: 'Bob'),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-charlie', username: 'Charlie'),
        );

        for (final member in [
          (peerId: 'peer-alice', username: 'Alice'),
          (peerId: 'peer-bob', username: 'Bob'),
          (peerId: 'peer-charlie', username: 'Charlie'),
        ]) {
          await inviteStatusRepo.saveAttempt(
            GroupInviteDeliveryAttempt(
              groupId: 'group-1',
              peerId: member.peerId,
              username: member.username,
              status: GroupInviteDeliveryStatus.sent,
              attemptedAt: DateTime.utc(2026, 5, 7, 12),
              updatedAt: DateTime.utc(2026, 5, 7, 12),
            ),
          );
        }
        await msgRepo.saveMessage(
          buildMemberJoinedTimelineMessage(
            groupId: 'group-1',
            joinedPeerId: 'peer-alice',
            joinedUsername: 'Alice',
            eventAt: DateTime.utc(2026, 5, 7, 12, 5),
          ),
        );
        await msgRepo.saveMessage(
          buildMemberJoinedTimelineMessage(
            groupId: 'group-1',
            joinedPeerId: 'peer-bob',
            joinedUsername: 'Bob',
            eventAt: DateTime.utc(2026, 5, 7, 12, 6),
          ),
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: FakeBridge(),
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
              inviteDeliveryAttemptRepo: inviteStatusRepo,
            ),
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Joined'), findsNWidgets(2));
        expect(find.text('Invite sent'), findsOneWidget);
        expect(find.text('Invite unknown'), findsNothing);
      },
    );

    testWidgets(
      'shows joined accepted members even when invite status rows are missing',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-alice', username: 'Alice'),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-bob', username: 'Bob'),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-charlie', username: 'Charlie'),
        );

        await msgRepo.saveMessage(
          buildMemberJoinedTimelineMessage(
            groupId: 'group-1',
            joinedPeerId: 'peer-alice',
            joinedUsername: 'Alice',
            eventAt: DateTime.utc(2026, 5, 7, 12, 5),
          ),
        );
        await msgRepo.saveMessage(
          buildMemberJoinedTimelineMessage(
            groupId: 'group-1',
            joinedPeerId: 'peer-bob',
            joinedUsername: 'Bob',
            eventAt: DateTime.utc(2026, 5, 7, 12, 6),
          ),
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: FakeBridge(),
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
              inviteDeliveryAttemptRepo: inviteStatusRepo,
            ),
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Joined'), findsNWidgets(2));
        expect(find.text('Invite unknown'), findsOneWidget);
        expect(find.text('Invite sent'), findsNothing);
      },
    );

    testWidgets(
      'creator lifecycle shows only accepted invited members as joined',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: FakeBridge(),
          inviteDeliveryAttemptRepo: inviteStatusRepo,
        );
        addTearDown(listener.dispose);

        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-alice', username: 'Alice'),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-bob', username: 'Bob'),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-charlie', username: 'Charlie'),
        );

        for (final member in [
          (peerId: 'peer-alice', username: 'Alice'),
          (peerId: 'peer-bob', username: 'Bob'),
          (peerId: 'peer-charlie', username: 'Charlie'),
        ]) {
          await inviteStatusRepo.saveAttempt(
            GroupInviteDeliveryAttempt(
              groupId: 'group-1',
              peerId: member.peerId,
              username: member.username,
              status: GroupInviteDeliveryStatus.sent,
              attemptedAt: DateTime.utc(2026, 5, 7, 12),
              updatedAt: DateTime.utc(2026, 5, 7, 12),
            ),
          );
        }

        for (final member in [
          (peerId: 'peer-alice', username: 'Alice', minute: 5),
          (peerId: 'peer-bob', username: 'Bob', minute: 6),
        ]) {
          await listener.handleReplayEnvelope({
            'groupId': 'group-1',
            'senderId': member.peerId,
            'senderUsername': member.username,
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_joined',
              'member': {'peerId': member.peerId, 'username': member.username},
            }),
            'timestamp': DateTime.utc(
              2026,
              5,
              7,
              12,
              member.minute,
            ).toIso8601String(),
          });
        }
        await _waitForInviteStatus(
          repo: inviteStatusRepo,
          groupId: 'group-1',
          peerId: 'peer-alice',
          status: GroupInviteDeliveryStatus.joined,
        );
        await _waitForInviteStatus(
          repo: inviteStatusRepo,
          groupId: 'group-1',
          peerId: 'peer-bob',
          status: GroupInviteDeliveryStatus.joined,
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: FakeBridge(),
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
              inviteDeliveryAttemptRepo: inviteStatusRepo,
            ),
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Joined'), findsNWidgets(2));
        expect(find.text('Invite sent'), findsOneWidget);
        expect(find.text('Invite unknown'), findsNothing);
      },
    );

    testWidgets(
      'does not let stale member_joined evidence override a current re-invite',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-alice', username: 'Alice'),
        );

        await msgRepo.saveMessage(
          buildMemberJoinedTimelineMessage(
            groupId: 'group-1',
            joinedPeerId: 'peer-alice',
            joinedUsername: 'Alice',
            eventAt: DateTime.utc(2026, 5, 7, 10),
          ),
        );
        await msgRepo.saveMessage(
          buildMemberRemovedTimelineMessage(
            groupId: 'group-1',
            removedPeerId: 'peer-alice',
            removedUsername: 'Alice',
            senderId: 'peer-admin',
            senderUsername: 'Admin',
            eventAt: DateTime.utc(2026, 5, 7, 11),
          ),
        );
        await inviteStatusRepo.saveAttempt(
          GroupInviteDeliveryAttempt(
            groupId: 'group-1',
            peerId: 'peer-alice',
            username: 'Alice',
            status: GroupInviteDeliveryStatus.sent,
            attemptedAt: DateTime.utc(2026, 5, 7, 12),
            updatedAt: DateTime.utc(2026, 5, 7, 12),
          ),
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: FakeBridge(),
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
              inviteDeliveryAttemptRepo: inviteStatusRepo,
            ),
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Invite sent'), findsOneWidget);
        expect(find.text('Joined'), findsNothing);
      },
    );

    testWidgets('covers the deterministic invite status label matrix', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );

      final members = [
        (
          peerId: 'peer-sent',
          username: 'Sent Member',
          status: GroupInviteDeliveryStatus.sent,
        ),
        (
          peerId: 'peer-queued',
          username: 'Queued Member',
          status: GroupInviteDeliveryStatus.queued,
        ),
        (
          peerId: 'peer-resend',
          username: 'Resend Member',
          status: GroupInviteDeliveryStatus.needsResend,
        ),
        (
          peerId: 'peer-cannot',
          username: 'Cannot Member',
          status: GroupInviteDeliveryStatus.cannotSend,
        ),
        (
          peerId: 'peer-joined',
          username: 'Joined Member',
          status: GroupInviteDeliveryStatus.joined,
        ),
      ];
      for (final member in members) {
        await groupRepo.saveMember(
          makeMember(peerId: member.peerId, username: member.username),
        );
        await inviteStatusRepo.saveAttempt(
          GroupInviteDeliveryAttempt(
            groupId: 'group-1',
            peerId: member.peerId,
            username: member.username,
            status: member.status,
            attemptedAt: DateTime.utc(2026, 5, 7, 12),
            updatedAt: DateTime.utc(2026, 5, 7, 12),
            lastError: member.status == GroupInviteDeliveryStatus.cannotSend
                ? 'missing_secure_key'
                : null,
          ),
        );
      }
      await groupRepo.saveMember(
        makeMember(peerId: 'peer-unknown', username: 'Unknown Member'),
      );

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
            inviteDeliveryAttemptRepo: inviteStatusRepo,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Invite sent'), findsOneWidget);
      expect(find.text('In their inbox'), findsOneWidget);
      expect(find.text('Resend needed'), findsOneWidget);
      expect(find.text('Cannot send'), findsOneWidget);
      expect(
        find.text(
          "We don't have the secure info needed to invite this friend. Ask them to open or reinstall the app, then try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('Joined'), findsOneWidget);
      expect(find.text('Invite unknown'), findsOneWidget);

      Finder statusBadge(String peerId) => find.byKey(
        ValueKey('group-member-invite-status-$peerId'),
      );
      for (final peerId in const [
        'peer-sent',
        'peer-queued',
        'peer-resend',
        'peer-cannot',
        'peer-unknown',
      ]) {
        expect(
          find.descendant(
            of: statusBadge(peerId),
            matching: find.text('Joined'),
          ),
          findsNothing,
          reason: '$peerId must remain distinguishable from accepted members',
        );
      }
      expect(
        find.descendant(
          of: statusBadge('peer-joined'),
          matching: find.text('Joined'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'ML-004 mixed B/C/D invite state shows failed recipient as resendable, not joined',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );

        final members = [
          (
            peerId: 'peer-bob',
            username: 'Bob',
            status: GroupInviteDeliveryStatus.sent,
          ),
          (
            peerId: 'peer-charlie',
            username: 'Charlie',
            status: GroupInviteDeliveryStatus.queued,
          ),
          (
            peerId: 'peer-dave',
            username: 'Dave',
            status: GroupInviteDeliveryStatus.needsResend,
          ),
        ];
        for (final member in members) {
          await groupRepo.saveMember(
            makeMember(peerId: member.peerId, username: member.username),
          );
          await inviteStatusRepo.saveAttempt(
            GroupInviteDeliveryAttempt(
              groupId: 'group-1',
              peerId: member.peerId,
              username: member.username,
              status: member.status,
              attemptedAt: DateTime.utc(2026, 5, 7, 12),
              updatedAt: DateTime.utc(2026, 5, 7, 12),
              lastError: member.status == GroupInviteDeliveryStatus.needsResend
                  ? 'send_failed'
                  : null,
            ),
          );
        }
        await msgRepo.saveMessage(
          buildMemberJoinedTimelineMessage(
            groupId: 'group-1',
            joinedPeerId: 'peer-bob',
            joinedUsername: 'Bob',
            eventAt: DateTime.utc(2026, 5, 7, 12, 5),
          ),
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: FakeBridge(),
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
              inviteDeliveryAttemptRepo: inviteStatusRepo,
            ),
          ),
        );
        await pumpFrames(tester);

        Finder statusBadge(String peerId) =>
            find.byKey(ValueKey('group-member-invite-status-$peerId'));

        expect(
          find.descendant(
            of: statusBadge('peer-bob'),
            matching: find.text('Joined'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: statusBadge('peer-charlie'),
            matching: find.text('In their inbox'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: statusBadge('peer-dave'),
            matching: find.text('Resend needed'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: statusBadge('peer-dave'),
            matching: find.text('Joined'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('group-member-resend-invite-peer-dave')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('group-member-resend-invite-peer-bob')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('group-member-resend-invite-peer-charlie')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'UP-005 pending and failed invite states are visually distinct from joined members',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );

        final members = [
          (
            peerId: 'peer-bob',
            username: 'Bob',
            status: GroupInviteDeliveryStatus.sent,
            lastError: null,
          ),
          (
            peerId: 'peer-charlie',
            username: 'Charlie',
            status: GroupInviteDeliveryStatus.queued,
            lastError: null,
          ),
          (
            peerId: 'peer-dave',
            username: 'Dave',
            status: GroupInviteDeliveryStatus.needsResend,
            lastError: 'send_failed',
          ),
          (
            peerId: 'peer-eve',
            username: 'Eve',
            status: GroupInviteDeliveryStatus.cannotSend,
            lastError: 'missing_secure_key',
          ),
        ];
        for (final member in members) {
          await groupRepo.saveMember(
            makeMember(peerId: member.peerId, username: member.username),
          );
          await inviteStatusRepo.saveAttempt(
            GroupInviteDeliveryAttempt(
              groupId: 'group-1',
              peerId: member.peerId,
              username: member.username,
              status: member.status,
              attemptedAt: DateTime.utc(2026, 5, 13, 12),
              updatedAt: DateTime.utc(2026, 5, 13, 12),
              lastError: member.lastError,
            ),
          );
        }
        await msgRepo.saveMessage(
          buildMemberJoinedTimelineMessage(
            groupId: 'group-1',
            joinedPeerId: 'peer-bob',
            joinedUsername: 'Bob',
            eventAt: DateTime.utc(2026, 5, 13, 12, 5),
          ),
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: FakeBridge(),
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
              inviteDeliveryAttemptRepo: inviteStatusRepo,
            ),
          ),
        );
        await pumpFrames(tester);

        Finder statusBadge(String peerId) =>
            find.byKey(ValueKey('group-member-invite-status-$peerId'));

        void expectBadge(String peerId, String label) {
          expect(
            find.descendant(
              of: statusBadge(peerId),
              matching: find.text(label),
            ),
            findsOneWidget,
          );
        }

        void expectNotJoined(String peerId) {
          expect(
            find.descendant(
              of: statusBadge(peerId),
              matching: find.text('Joined'),
            ),
            findsNothing,
          );
        }

        expectBadge('peer-bob', 'Joined');
        expectBadge('peer-charlie', 'In their inbox');
        expectBadge('peer-dave', 'Resend needed');
        expectBadge('peer-eve', 'Cannot send');
        expectNotJoined('peer-charlie');
        expectNotJoined('peer-dave');
        expectNotJoined('peer-eve');
        expect(
          find.byKey(const ValueKey('group-member-resend-invite-peer-dave')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('group-member-resend-invite-peer-bob')),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey('group-member-invite-status-detail-peer-eve'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'UP-006 a re-added member is NOT shown joined until a real rejoin '
      'confirmation arrives (B3.1)',
      (tester) async {
        // B3.1: the admin's OWN members_added re-add event is not a join
        // confirmation. After a removal, the re-added member must show the
        // pending re-invite status ("Invite sent") until a genuine member_joined
        // receipt comes back — not an optimistic "Joined" (the field bug where
        // the admin saw a re-added member as joined before they actually
        // rejoined and obtained the new key).
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
        final group = makeAdminGroup();
        final firstInviteAt = DateTime.utc(2026, 5, 16, 10);
        final removedAt = firstInviteAt.add(const Duration(minutes: 5));
        final readdAt = firstInviteAt.add(const Duration(minutes: 10));

        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-charlie',
            username: 'Charlie',
          ).copyWith(joinedAt: readdAt),
        );
        // A fresh re-invite was SENT at re-add time; no rejoin receipt yet.
        await inviteStatusRepo.saveAttempt(
          GroupInviteDeliveryAttempt(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            status: GroupInviteDeliveryStatus.sent,
            attemptedAt: readdAt,
            updatedAt: readdAt,
          ),
        );
        await msgRepo.saveMessage(
          buildMemberRemovedTimelineMessage(
            groupId: 'group-1',
            removedPeerId: 'peer-charlie',
            removedUsername: 'Charlie',
            senderId: 'peer-admin',
            senderUsername: 'Admin',
            eventAt: removedAt,
          ),
        );
        // Only the admin's own re-add event exists — no member_joined receipt.
        await msgRepo.saveMessage(
          buildMembersAddedTimelineMessage(
            groupId: 'group-1',
            addedMembers: const [(peerId: 'peer-charlie', username: 'Charlie')],
            senderId: 'peer-admin',
            senderUsername: 'Admin',
            eventAt: readdAt,
          ),
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: FakeBridge(),
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
              inviteDeliveryAttemptRepo: inviteStatusRepo,
            ),
          ),
        );
        await pumpFrames(tester);

        final charlieBadge = find.byKey(
          const ValueKey('group-member-invite-status-peer-charlie'),
        );
        expect(find.text('Charlie'), findsOneWidget);
        expect(
          find.descendant(of: charlieBadge, matching: find.text('Invite sent')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: charlieBadge, matching: find.text('Joined')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'UP-006b a re-added member DOES show joined once a real member_joined '
      'receipt arrives after the re-add (B3.1 positive)',
      (tester) async {
        // The truthful-pending rule must not permanently hide a genuinely
        // re-joined member: a member_joined receipt dated AFTER the removal
        // flips the status back to "Joined".
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
        final group = makeAdminGroup();
        final removedAt = DateTime.utc(2026, 5, 16, 10);
        final readdAt = removedAt.add(const Duration(minutes: 5));
        final rejoinReceiptAt = removedAt.add(const Duration(minutes: 8));

        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-charlie',
            username: 'Charlie',
          ).copyWith(joinedAt: readdAt),
        );
        await msgRepo.saveMessage(
          buildMemberRemovedTimelineMessage(
            groupId: 'group-1',
            removedPeerId: 'peer-charlie',
            removedUsername: 'Charlie',
            senderId: 'peer-admin',
            senderUsername: 'Admin',
            eventAt: removedAt,
          ),
        );
        await msgRepo.saveMessage(
          buildMembersAddedTimelineMessage(
            groupId: 'group-1',
            addedMembers: const [(peerId: 'peer-charlie', username: 'Charlie')],
            senderId: 'peer-admin',
            senderUsername: 'Admin',
            eventAt: readdAt,
          ),
        );
        // The member's own rejoin receipt, dated after the removal.
        await msgRepo.saveMessage(
          buildMemberJoinedTimelineMessage(
            groupId: 'group-1',
            joinedPeerId: 'peer-charlie',
            joinedUsername: 'Charlie',
            eventAt: rejoinReceiptAt,
          ),
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: FakeBridge(),
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
              inviteDeliveryAttemptRepo: inviteStatusRepo,
            ),
          ),
        );
        await pumpFrames(tester);

        final charlieBadge = find.byKey(
          const ValueKey('group-member-invite-status-peer-charlie'),
        );
        expect(
          find.descendant(of: charlieBadge, matching: find.text('Joined')),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows cannot-send reason copy from persisted lastError', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );

      final cases = [
        (
          peerId: 'peer-missing',
          username: 'Missing Secure',
          lastError: 'missing_secure_key',
          reason:
              "We don't have the secure info needed to invite this friend. Ask them to open or reinstall the app, then try again.",
        ),
        (
          peerId: 'peer-invalid',
          username: 'Invalid Payload',
          lastError: 'invalid_invite_payload',
          reason:
              'This invite could not be prepared. Reopen the app and try again.',
        ),
        (
          peerId: 'peer-group-key',
          username: 'Group Key',
          lastError: 'group_key_missing',
          reason:
              'This group is missing the secure invite key. Reopen the app and try again.',
        ),
        (
          peerId: 'peer-unknown-error',
          username: 'Unknown Error',
          lastError: 'future_error_code',
          reason:
              'We could not prepare a secure invite for this friend. They may need to open or reinstall the app before you can invite them.',
        ),
        (
          peerId: 'peer-null-error',
          username: 'Null Error',
          lastError: null,
          reason:
              'We could not prepare a secure invite for this friend. They may need to open or reinstall the app before you can invite them.',
        ),
      ];

      for (final caseData in cases) {
        await groupRepo.saveMember(
          makeMember(peerId: caseData.peerId, username: caseData.username),
        );
        await inviteStatusRepo.saveAttempt(
          GroupInviteDeliveryAttempt(
            groupId: 'group-1',
            peerId: caseData.peerId,
            username: caseData.username,
            status: GroupInviteDeliveryStatus.cannotSend,
            attemptedAt: DateTime.utc(2026, 5, 7, 12),
            updatedAt: DateTime.utc(2026, 5, 7, 12),
            lastError: caseData.lastError,
          ),
        );
      }

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
            inviteDeliveryAttemptRepo: inviteStatusRepo,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Cannot send'), findsNWidgets(cases.length));
      expect(find.text(cases[0].reason), findsOneWidget);
      expect(find.text(cases[1].reason), findsOneWidget);
      expect(find.text(cases[2].reason), findsOneWidget);
      expect(find.text(cases[3].reason), findsNWidgets(2));
    });

    for (final scenario
        in <
          ({
            String name,
            bool sendMessageResult,
            bool storeInInboxResult,
            bool hasRecipientSecureKey,
            String expectedSnackBar,
          })
        >[
          (
            name: 'sent',
            sendMessageResult: true,
            storeInInboxResult: true,
            hasRecipientSecureKey: true,
            expectedSnackBar: 'Invite sent to Alice',
          ),
          (
            name: 'queued',
            sendMessageResult: false,
            storeInInboxResult: true,
            hasRecipientSecureKey: true,
            expectedSnackBar: "Invite is in Alice's inbox",
          ),
          (
            name: 'needs resend',
            sendMessageResult: false,
            storeInInboxResult: false,
            hasRecipientSecureKey: true,
            expectedSnackBar: 'Invite still needs to be resent',
          ),
          (
            name: 'cannot send',
            sendMessageResult: true,
            storeInInboxResult: true,
            hasRecipientSecureKey: false,
            expectedSnackBar:
                "Cannot send: we don't have the secure info needed to invite this friend.",
          ),
        ]) {
      testWidgets('shows ${scenario.name} resend snackbar copy', (
        tester,
      ) async {
        await _pumpResendInviteSurface(
          tester,
          sendMessageResult: scenario.sendMessageResult,
          storeInInboxResult: scenario.storeInInboxResult,
          hasRecipientSecureKey: scenario.hasRecipientSecureKey,
        );

        await _tapResendInviteButton(tester);

        expect(find.text(scenario.expectedSnackBar), findsOneWidget);
      });
    }

    testWidgets(
      'revoke shows a pre-confirm dialog and sends only after confirm',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
          ),
        );
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-alice',
            username: 'Alice',
            publicKey: 'pk-alice',
            mlKemPublicKey: 'mlkem-pk-alice',
          ),
        );
        await inviteStatusRepo.saveAttempt(
          GroupInviteDeliveryAttempt(
            groupId: 'group-1',
            peerId: 'peer-alice',
            username: 'Alice',
            status: GroupInviteDeliveryStatus.sent,
            attemptedAt: DateTime.utc(2026, 5, 7, 12),
            updatedAt: DateTime.utc(2026, 5, 7, 12),
            inviteId: 'invite-alice-1',
          ),
        );

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
          sendMessageResult: true,
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: FakeBridge(),
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: p2pService,
              inviteDeliveryAttemptRepo: inviteStatusRepo,
            ),
          ),
        );
        await pumpFrames(tester);

        final button = find.byKey(
          const ValueKey('group-member-revoke-invite-peer-alice'),
        );
        expect(button, findsOneWidget);
        await tester.ensureVisible(button);
        await pumpFrames(tester, count: 5);

        // Tapping revoke opens a pre-confirm dialog and puts NOTHING on the
        // wire yet — a mis-tap must not fire the irreversible revocation.
        await tester.tap(button, warnIfMissed: false);
        await pumpFrames(tester, count: 10);
        expect(
          find.byKey(const ValueKey('group-revoke-confirm')),
          findsOneWidget,
        );
        expect(p2pService.sendMessageCallCount, 0);
        // REVOKE never offers an Undo (the signed envelope is irreversible).
        expect(find.widgetWithText(SnackBarAction, 'Undo'), findsNothing);

        // Cancelling the dialog leaves the invite untouched.
        await tester.tap(find.byKey(const ValueKey('group-revoke-cancel')));
        await pumpFrames(tester, count: 10);
        expect(p2pService.sendMessageCallCount, 0);
        final stillSent = await inviteStatusRepo.getAttempt(
          groupId: 'group-1',
          peerId: 'peer-alice',
        );
        expect(stillSent!.status, GroupInviteDeliveryStatus.sent);

        // Re-open and confirm: NOW the revocation envelope goes on the wire,
        // carrying the EXACT invite id the receiver matches on (HOLE-4), and
        // the local delivery-attempt row flips to revoked.
        await tester.ensureVisible(button);
        await pumpFrames(tester, count: 5);
        await tester.tap(button, warnIfMissed: false);
        await pumpFrames(tester, count: 10);
        await tester.tap(find.byKey(const ValueKey('group-revoke-confirm')));
        await pumpFrames(tester, count: 40);

        expect(p2pService.sendMessageCallCount, 1);
        final envelope =
            jsonDecode(p2pService.lastSendMessageContent!)
                as Map<String, dynamic>;
        expect(envelope['type'], 'group_invite_revocation');
        expect(envelope['id'], 'invite-alice-1');
        expect(envelope['id'] as String, isNotEmpty);

        final attempt = await inviteStatusRepo.getAttempt(
          groupId: 'group-1',
          peerId: 'peer-alice',
        );
        expect(attempt!.status, GroupInviteDeliveryStatus.revoked);
      },
    );

    testWidgets(
      'remove member stays a pre-confirm dialog with no Undo (lock)',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-alice', username: 'Alice'),
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        final aliceRemoveButton = find.descendant(
          of: aliceRow,
          matching: find.byIcon(Icons.remove_circle_outline),
        );
        await tester.ensureVisible(aliceRemoveButton);
        await pumpFrames(tester, count: 5);
        await tester.tap(aliceRemoveButton, warnIfMissed: false);
        await pumpFrames(tester);

        // Tapping remove opens the pre-confirm dialog — removal is NOT
        // optimistic and offers NO Undo (irreversible per INV-R2). Nothing is
        // broadcast until the admin confirms.
        expect(
          find.byKey(const ValueKey('group-remove-confirm')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('group-remove-cancel')),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Undo'), findsNothing);
        expect(bridge.commandLog, isEmpty);

        // Dismissing the dialog still leaves the member and broadcasts nothing.
        await tester.tap(find.byKey(const ValueKey('group-remove-cancel')));
        await pumpFrames(tester, count: 10);
        expect(find.text('Alice'), findsOneWidget);
        expect(bridge.commandLog, isEmpty);
        expect(find.widgetWithText(SnackBarAction, 'Undo'), findsNothing);
      },
    );

    testWidgets('shows identity warning when member keys differ from contact', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final contactRepo = InMemoryContactRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-alice',
          username: 'Alice',
          publicKey: 'pk-alice-current',
          mlKemPublicKey: 'mlkem-alice-current',
        ),
      );
      await contactRepo.addContact(
        makeContact(
          peerId: 'peer-alice',
          username: 'Alice',
          publicKey: 'pk-alice-saved',
          mlKemPublicKey: 'mlkem-alice-saved',
        ),
      );

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      final currentSafety = ContactSafetyNumber.build(
        peerId: 'peer-alice',
        publicKey: 'pk-alice-current',
        mlKemPublicKey: 'mlkem-alice-current',
      );
      final savedSafety = ContactSafetyNumber.build(
        peerId: 'peer-alice',
        publicKey: 'pk-alice-saved',
        mlKemPublicKey: 'mlkem-alice-saved',
      );

      expect(
        find.byKey(const ValueKey('group-member-identity-warning-peer-alice')),
        findsOneWidget,
      );
      expect(find.text('Identity changed'), findsOneWidget);
      expect(find.text('Current safety $currentSafety'), findsOneWidget);
      expect(find.text('Saved safety $savedSafety'), findsOneWidget);
    });

    testWidgets('does not show identity warning when contact keys match', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final contactRepo = InMemoryContactRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-alice',
          username: 'Alice',
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
        ),
      );
      await contactRepo.addContact(
        makeContact(
          peerId: 'peer-alice',
          username: 'Alice',
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
        ),
      );

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Identity changed'), findsNothing);
      expect(
        find.byKey(const ValueKey('group-member-identity-warning-peer-alice')),
        findsNothing,
      );
    });

    testWidgets('shows security status from key epoch and member safety', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final contactRepo = InMemoryContactRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo, generation: 2);
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-alice',
          username: 'Alice',
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
        ),
      );
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-bob',
          username: 'Bob',
          publicKey: 'pk-bob-current',
          mlKemPublicKey: 'mlkem-bob-current',
        ),
      );
      await contactRepo.addContact(
        makeContact(
          peerId: 'peer-alice',
          username: 'Alice',
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
        ),
      );
      await contactRepo.addContact(
        makeContact(
          peerId: 'peer-bob',
          username: 'Bob',
          publicKey: 'pk-bob-saved',
          mlKemPublicKey: 'mlkem-bob-saved',
        ),
      );

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('group-security-status-card')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpFrames(tester, count: 2);

      expect(
        find.byKey(const ValueKey('group-security-status-card')),
        findsOneWidget,
      );
      expect(find.text('Encrypted - key epoch 2'), findsOneWidget);
      expect(find.text('Group key changed to epoch 2'), findsNWidgets(2));
      expect(find.text('1 of 2 members verified'), findsOneWidget);
      expect(find.text('1 member needs verification review'), findsOneWidget);
      expect(find.textContaining('test-group-key-2'), findsNothing);
    });

    testWidgets('counts own member as verified without saved contact', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final contactRepo = InMemoryContactRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);
      await groupRepo.saveMember(
        makeMember(
          peerId: testIdentity.peerId,
          username: testIdentity.username,
          role: MemberRole.admin,
          publicKey: testIdentity.publicKey,
          mlKemPublicKey: testIdentity.mlKemPublicKey,
        ),
      );
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-alice',
          username: 'Alice',
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
        ),
      );
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-bob',
          username: 'Bob',
          publicKey: 'pk-bob',
          mlKemPublicKey: 'mlkem-bob',
        ),
      );
      await contactRepo.addContact(
        makeContact(
          peerId: 'peer-alice',
          username: 'Alice',
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
        ),
      );
      await contactRepo.addContact(
        makeContact(
          peerId: 'peer-bob',
          username: 'Bob',
          publicKey: 'pk-bob',
          mlKemPublicKey: 'mlkem-bob',
        ),
      );

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('group-security-status-card')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpFrames(tester, count: 2);

      expect(find.text('Encrypted - key epoch 1'), findsOneWidget);
      expect(find.text('Current key epoch 1'), findsOneWidget);
      expect(find.text('All 3 members verified'), findsOneWidget);
      expect(find.text('2 of 3 members verified'), findsNothing);
      expect(
        find.textContaining('not verified from saved contacts'),
        findsNothing,
      );
    });

    testWidgets('shows Add Member button for admin role', (tester) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Add Member'), findsOneWidget);
    });

    testWidgets(
      'shows the creator username from the real create flow for other members',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final bridge = FakeBridge(
          initialResponses: {
            'group:create': {
              'ok': true,
              'groupId': 'group-created-with-username',
              'topicName': 'topic-group-created-with-username',
              'groupKey': 'group-key-created-with-username',
              'keyEpoch': 0,
            },
          },
        );
        final viewerIdentity = IdentityModel(
          peerId: 'peer-alice',
          publicKey: 'pk-alice',
          privateKey: 'sk-alice',
          mnemonic12:
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          mlKemPublicKey: 'mlkem-pk-alice',
          username: 'Alice',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        );

        final created = await createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'Created Group',
          type: GroupType.chat,
          creatorPeerId: testIdentity.peerId,
          creatorPublicKey: testIdentity.publicKey,
          creatorMlKemPublicKey: testIdentity.mlKemPublicKey ?? '',
          creatorUsername: testIdentity.username,
        );
        await groupRepo.saveGroup(created.copyWith(myRole: GroupRole.member));
        await groupRepo.saveMember(
          GroupMember(
            groupId: created.id,
            peerId: viewerIdentity.peerId,
            username: viewerIdentity.username,
            role: MemberRole.writer,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: created.copyWith(myRole: GroupRole.member),
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: viewerIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Admin'), findsOneWidget);
        expect(find.text('peer-admin'), findsNothing);
      },
    );

    testWidgets('hides Add Member button for non-admin role', (tester) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeMemberGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Add Member'), findsNothing);
    });

    testWidgets(
      'admin can dissolve a group and the screen switches to read-only state',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-bob', username: 'Bob'),
        );

        final bridge = FakeBridge(
          initialResponses: {
            'group:publish': {'ok': true, 'messageId': 'msg-1'},
            'group:inboxStore': {'ok': true},
            'group:leave': {'ok': true},
          },
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        await scrollToDissolveGroupButton(tester);
        expect(
          find.byKey(const ValueKey('group-dissolve-button')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('group-dissolve-button')));
        await pumpFrames(tester, count: 5);
        expect(
          find.byKey(const ValueKey('group-dissolve-confirm')),
          findsOneWidget,
        );

        await confirmDissolveGroupDialog(tester);

        final updated = await groupRepo.getGroup(group.id);
        expect(updated, isNotNull);
        expect(updated!.isDissolved, isTrue);

        final latest = await msgRepo.getLatestMessage(group.id);
        expect(latest, isNotNull);
        expect(latest!.text, 'Admin dissolved the group');

        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
        expect(bridge.commandLog, contains('group:leave'));

        expect(
          find.text(
            'This conversation is now read-only. Previous messages stay available for reference.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('group-dissolve-button')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('group-leave-button')), findsNothing);
        expect(
          find.byKey(const ValueKey('group-delete-local-button')),
          findsOneWidget,
        );
        expect(find.text('Add Member'), findsNothing);
        expect(
          find.byKey(const ValueKey('group-edit-details-button')),
          findsNothing,
        );
      },
    );

    // B4 (Option A — widget caller, the genuine field bug): when the admin
    // dissolves via the GroupInfo screen, the published group_dissolved audit
    // MUST carry the actor's device/transport binding (the same binding the Go
    // transport stamps on the live message), so verifyGroupTransitionAudit on
    // every receiver matches signed-vs-observed and applies isDissolved. Before
    // the fix, _onDissolveGroup called dissolveGroup without the binding; the
    // signer omitted deviceId/transportPeerId; receivers saw observed-present
    // vs signed-absent and rejected with device_mismatch/transport_mismatch, so
    // the group stayed live for everyone but the dissolver.
    testWidgets(
      'B4 dissolve via screen signs an audit whose actor carries the local '
      'device/transport binding',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        // The admin member carries a registered active device whose transport
        // peer id equals this device's live peer id (peer-admin). This is the
        // realistic shape resolveGroupSenderDeviceBinding resolves against, so
        // the threaded binding is non-empty and lands in the signed audit.
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
          ).copyWith(
            devices: const [
              GroupMemberDeviceIdentity(
                deviceId: 'dev-admin-1',
                transportPeerId: 'peer-admin',
                deviceSigningPublicKey: 'pk-admin',
                keyPackageId: 'kp-admin-1',
              ),
            ],
          ),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-bob', username: 'Bob'),
        );

        final bridge = FakeBridge(
          initialResponses: {
            'group:publish': {'ok': true, 'messageId': 'msg-1'},
            'group:inboxStore': {'ok': true},
            'group:leave': {'ok': true},
          },
        );

        // The local node exposes a non-empty peerId so the widget's
        // _currentSenderDeviceId resolves to 'peer-admin' (the preferred
        // device/transport hint fed into resolveGroupSenderDeviceBinding).
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            peerId: 'peer-admin',
            isStarted: true,
          ),
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: p2pService,
            ),
          ),
        );
        await pumpFrames(tester);

        await scrollToDissolveGroupButton(tester);
        await tester.tap(find.byKey(const ValueKey('group-dissolve-button')));
        await pumpFrames(tester, count: 5);
        await confirmDissolveGroupDialog(tester);

        // Sanity: the dissolve actually completed and published.
        final updated = await groupRepo.getGroup(group.id);
        expect(updated, isNotNull);
        expect(updated!.isDissolved, isTrue);
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        // Decode the signed audit's actor from the proven inboxStore replay
        // path (mirrors dissolve_group_use_case_test's decode pattern).
        final inboxStoreMessage = bridge.sentMessages.firstWhere((message) {
          return (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore';
        });
        final inboxPayload =
            (jsonDecode(inboxStoreMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final replayEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        final replayPlaintext =
            jsonDecode(replayEnvelope['ciphertext'] as String)
                as Map<String, dynamic>;
        final sysPayload =
            jsonDecode(replayPlaintext['text'] as String)
                as Map<String, dynamic>;
        final audit =
            sysPayload[signedGroupTransitionAuditField]
                as Map<String, dynamic>;
        final signedPayload =
            jsonDecode(audit['signedPayload'] as String)
                as Map<String, dynamic>;
        final actor = signedPayload['actor'] as Map<String, dynamic>;

        // The crux of B4: actor must carry a non-empty device + transport
        // binding equal to this device's live peer id. With Option A reverted
        // the binding is omitted and these assertions fail.
        expect(actor['deviceId'], isNotNull);
        expect(actor['deviceId'] as String, isNotEmpty);
        expect(actor['deviceId'], 'dev-admin-1');
        expect(actor['transportPeerId'], isNotNull);
        expect(actor['transportPeerId'] as String, isNotEmpty);
        expect(actor['transportPeerId'], 'peer-admin');
        expect(actor['transportPeerId'], p2pService.currentState.peerId);
        expect(actor['keyPackageId'], 'kp-admin-1');
      },
    );

    testWidgets('toggles mute state and persists it to the repository', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      // 154: capture platform-channel calls so we can assert the mute toggle
      // fires HapticFeedback.selectionClick() instead of a success snackbar.
      // One handler per channel — record every call into a list and return
      // null (safe for HapticFeedback.vibrate, which awaits invokeMethod<void>).
      final platformCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('group-mute-switch')))
            .value,
        isFalse,
      );

      await tester.tap(find.byKey(const ValueKey('group-mute-switch')));
      await pumpFrames(tester, count: 20);

      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('group-mute-switch')))
            .value,
        isTrue,
      );
      expect((await groupRepo.getGroup(group.id))?.isMuted, isTrue);
      // 154: the control already flips (switch + repo above); the success
      // snackbar is dropped and replaced by a tactile selectionClick. Assert
      // BOTH the method string AND the positional arg — every HapticFeedback
      // variant shares the 'HapticFeedback.vibrate' method, so a method-only
      // check would not catch a wrong-haptic mutation.
      expect(
        platformCalls.any(
          (c) =>
              c.method == 'HapticFeedback.vibrate' &&
              c.arguments == 'HapticFeedbackType.selectionClick',
        ),
        isTrue,
        reason: 'mute toggle should fire HapticFeedback.selectionClick()',
      );
      expect(find.text('Notifications muted for this group'), findsNothing);
    });

    testWidgets('hides member remove controls for non-admin role', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeMemberGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );
      await groupRepo.saveMember(
        makeMember(peerId: 'peer-bob', username: 'Bob'),
      );

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
      expect(
        find.byKey(const ValueKey('group-member-actions-peer-bob')),
        findsNothing,
      );
    });

    testWidgets('uses repo myRole instead of stale navigation role on load', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final persistedGroup = makeAdminGroup();
      await groupRepo.saveGroup(persistedGroup);
      await _saveGroupReplayKey(groupRepo);
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );
      await groupRepo.saveMember(
        makeMember(peerId: 'peer-alice', username: 'Alice'),
      );

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: makeMemberGroup(),
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Add Member'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('group-member-actions-peer-alice')),
        findsOneWidget,
      );
    });

    testWidgets(
      'GDR-001 active recovery before opening editor disables Save and shows elapsed wait copy',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        await _seedEditableGroup(groupRepo);
        groupRecoveryGate.begin();

        await _pumpEditableGroupInfo(tester, groupRepo: groupRepo);
        await _openGroupDetailsEditor(tester);

        expect(_groupEditSaveButton(tester).onPressed, isNull);
        expect(find.text(_groupEditRecoveryWaitCopy), findsOneWidget);
        expect(find.text(_groupEditRecoveryElapsedCopy(0)), findsOneWidget);
        expect(find.textContaining('resync'), findsNothing);
        expect(
          find.textContaining(RegExp('group recovery', caseSensitive: false)),
          findsNothing,
        );

        await tester.pump(const Duration(seconds: 2));

        expect(find.text(_groupEditRecoveryElapsedCopy(2)), findsOneWidget);
      },
    );

    testWidgets(
      'GDR-001 recovery ending re-enables Save without losing draft text or selected photo preview',
      (tester) async {
        final tempDir = await _installPathProviderTempDirForTest();
        final pickedAvatar = await _writePickedAvatar(tempDir, 'picked');
        final mediaPicker = FakeMediaPicker()
          ..imageResult = XFile(pickedAvatar.path);
        final groupRepo = InMemoryGroupRepository();
        await _seedEditableGroup(groupRepo);
        groupRecoveryGate.begin();

        await _pumpEditableGroupInfo(
          tester,
          groupRepo: groupRepo,
          mediaPicker: mediaPicker,
          imageProcessor: _testAvatarImageProcessor(),
        );
        await _openGroupDetailsEditor(tester);

        await _pickGroupEditPhoto(tester);
        expect(mediaPicker.pickImageCalls, 1);
        expect(find.text('Failed to pick group photo'), findsNothing);
        await tester.enterText(_groupEditNameField(), 'Queued Name');
        await tester.enterText(
          _groupEditDescriptionField(),
          'Queued description',
        );
        expect(
          find.byKey(
            const ValueKey('group-avatar-image-group-1-memory-none-editor'),
          ),
          findsOneWidget,
        );
        expect(_groupEditSaveButton(tester).onPressed, isNull);

        groupRecoveryGate.end();
        await tester.pump();

        final nameField = tester.widget<TextField>(_groupEditNameField());
        final descriptionField = tester.widget<TextField>(
          _groupEditDescriptionField(),
        );
        expect(nameField.controller!.text, 'Queued Name');
        expect(descriptionField.controller!.text, 'Queued description');
        expect(
          find.byKey(
            const ValueKey('group-avatar-image-group-1-memory-none-editor'),
          ),
          findsOneWidget,
        );
        expect(_groupEditSaveButton(tester).onPressed, isNotNull);
        expect(find.text(_groupEditRecoveryWaitCopy), findsNothing);
      },
    );

    testWidgets(
      'GDR-001 recovery starting after editor opens disables Save and shows wait copy',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        await _seedEditableGroup(groupRepo);

        await _pumpEditableGroupInfo(tester, groupRepo: groupRepo);
        await _openGroupDetailsEditor(tester);

        expect(_groupEditSaveButton(tester).onPressed, isNotNull);
        expect(find.text(_groupEditRecoveryWaitCopy), findsNothing);

        groupRecoveryGate.begin();
        await tester.pump();

        expect(_groupEditSaveButton(tester).onPressed, isNull);
        expect(find.text(_groupEditRecoveryWaitCopy), findsOneWidget);
        expect(find.textContaining('resync'), findsNothing);
        expect(
          find.textContaining(RegExp('group recovery', caseSensitive: false)),
          findsNothing,
        );
      },
    );

    testWidgets(
      'GDR-001 empty-name validation keeps Save disabled after recovery ends',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        await _seedEditableGroup(groupRepo);
        groupRecoveryGate.begin();

        await _pumpEditableGroupInfo(tester, groupRepo: groupRepo);
        await _openGroupDetailsEditor(tester);
        await tester.enterText(_groupEditNameField(), '   ');

        groupRecoveryGate.end();
        await tester.pump();

        expect(find.text(_groupEditRecoveryWaitCopy), findsNothing);
        expect(_groupEditSaveButton(tester).onPressed, isNull);
      },
    );

    testWidgets(
      'GDR-001 recovery rejection during save maps to wait copy without raw recovery text',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        await _seedEditableGroup(groupRepo);
        final identityRepo = _ControlledRecoveryIdentityRepository(
          identity: testIdentity,
        );

        await _pumpEditableGroupInfo(
          tester,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
        );
        await _openGroupDetailsEditor(tester);
        await tester.enterText(_groupEditNameField(), 'Rename during wait');

        identityRepo.beginRecoveryOnNextLoad = true;
        await _tapGroupEditSave(tester);
        await pumpFrames(tester, count: 30);

        final persisted = await groupRepo.getGroup('group-1');
        expect(persisted!.name, 'Test Group');
        expect(find.text(_groupEditRecoveryWaitCopy), findsOneWidget);
        expect(find.textContaining('resync'), findsNothing);
        expect(
          find.textContaining(RegExp('group recovery', caseSensitive: false)),
          findsNothing,
        );
        expect(find.textContaining('groupRecoveryPendingError'), findsNothing);
      },
    );

    testWidgets(
      'GDR-001 recovery-blocked replacement does not commit canonical avatar before metadata success',
      (tester) async {
        final tempDir = await _installPathProviderTempDirForTest();
        final pickedAvatar = await _writePickedAvatar(tempDir, 'replacement');
        final canonicalAvatar = File(
          p.join(tempDir.path, groupAvatarRelativePath('group-1')),
        );
        final mediaPicker = FakeMediaPicker()
          ..imageResult = XFile(pickedAvatar.path);
        final groupRepo = InMemoryGroupRepository();
        await _seedEditableGroup(groupRepo);
        var uploadCalls = 0;
        final UploadGroupAvatarFn uploadAndStartRecovery =
            ({
              required Bridge bridge,
              required String localFilePath,
              required String groupId,
              required List<String> allowedPeers,
              String? blobId,
              String mime = 'image/jpeg',
            }) {
              uploadCalls += 1;
              groupRecoveryGate.begin();
              return Future<GroupAvatarUpload?>.value(
                const GroupAvatarUpload(
                  id: 'avatar-new',
                  mime: 'image/jpeg',
                  size: 4,
                ),
              );
            };

        await _pumpEditableGroupInfo(
          tester,
          groupRepo: groupRepo,
          mediaPicker: mediaPicker,
          imageProcessor: _testAvatarImageProcessor(
            Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]),
          ),
          uploadGroupAvatarFn: uploadAndStartRecovery,
        );
        await _openGroupDetailsEditor(tester);
        await _pickGroupEditPhoto(tester);
        await tester.enterText(_groupEditNameField(), 'Avatar Rename');

        await _tapGroupEditSave(tester);
        await pumpFrames(tester, count: 30);

        final persisted = await groupRepo.getGroup('group-1');
        expect(uploadCalls, 1);
        expect(canonicalAvatar.existsSync(), isFalse);
        expect(persisted!.avatarBlobId, isNull);
        expect(persisted.avatarMime, isNull);
        expect(persisted.avatarPath, isNull);
        expect(find.text(_groupEditRecoveryWaitCopy), findsOneWidget);
      },
    );

    testWidgets(
      'S2a metadata edit hard inboxStore failure reverts name and deletes timeline card',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final original = makeAdminGroup().copyWith(
          name: 'Original Name',
          description: 'Original Desc',
        );
        await _seedEditableGroup(groupRepo, group: original);
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-alice', username: 'Alice'),
        );
        final bridge = _ThrowOnCommandBridge(
          'group:inboxStore',
          initialResponses: {
            'group:publish': {'ok': true, 'messageId': 'msg-1'},
          },
        );

        await _pumpEditableGroupInfo(
          tester,
          groupRepo: groupRepo,
          bridge: bridge,
          msgRepo: msgRepo,
        );
        await _openGroupDetailsEditor(tester);
        await tester.enterText(_groupEditNameField(), 'New Name');
        await _tapGroupEditSave(tester);
        await pumpFrames(tester, count: 30);

        final persisted = await groupRepo.getGroup('group-1');
        expect(persisted!.name, 'Original Name');
        expect(persisted.description, 'Original Desc');
        expect(msgRepo.count, 0);
        expect(find.text('Group details updated'), findsNothing);
      },
    );

    testWidgets(
      'S2a metadata edit soft publish failure reverts and never reports success',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final original = makeAdminGroup().copyWith(
          name: 'Original Name',
          description: 'Original Desc',
        );
        await _seedEditableGroup(groupRepo, group: original);
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-alice', username: 'Alice'),
        );
        final bridge = FakeBridge(
          initialResponses: {
            'group:publish': {
              'ok': false,
              'errorMessage': 'simulated publish failure',
            },
            'group:inboxStore': {'ok': true},
          },
        );

        await _pumpEditableGroupInfo(
          tester,
          groupRepo: groupRepo,
          bridge: bridge,
          msgRepo: msgRepo,
        );
        await _openGroupDetailsEditor(tester);
        await tester.enterText(_groupEditNameField(), 'New Name');
        await _tapGroupEditSave(tester);
        await pumpFrames(tester, count: 30);

        final persisted = await groupRepo.getGroup('group-1');
        expect(persisted!.name, 'Original Name');
        expect(msgRepo.count, 0);
        expect(find.text('Group details updated'), findsNothing);
        expect(find.text('simulated publish failure'), findsOneWidget);
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      },
    );

    testWidgets(
      'S2a metadata revert is monotonicity-guarded and keeps a newer remote update',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final original = makeAdminGroup().copyWith(
          name: 'Original Name',
          description: 'Original Desc',
        );
        await _seedEditableGroup(groupRepo, group: original);
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-alice', username: 'Alice'),
        );

        final bridge = _PublishFailAfterHookBridge(() async {
          // A newer remote group_metadata_updated lands between our local
          // persist and the publish failure.
          final current = await groupRepo.getGroup('group-1');
          await groupRepo.updateGroup(
            current!.copyWith(
              name: 'Remote Name',
              lastMetadataEventAt: DateTime.now().toUtc().add(
                const Duration(minutes: 5),
              ),
            ),
          );
        });

        await _pumpEditableGroupInfo(
          tester,
          groupRepo: groupRepo,
          bridge: bridge,
          msgRepo: msgRepo,
        );
        await _openGroupDetailsEditor(tester);
        await tester.enterText(_groupEditNameField(), 'New Name');
        await _tapGroupEditSave(tester);
        await pumpFrames(tester, count: 30);

        final persisted = await groupRepo.getGroup('group-1');
        // The monotonicity-guarded revert must not clobber the newer remote
        // name back to 'Original Name'.
        expect(persisted!.name, 'Remote Name');
        expect(find.text('Group details updated'), findsNothing);
      },
    );

    testWidgets(
      'S2b metadata soft publish failure enqueues a durable broadcast and keeps the edit',
      (tester) async {
        final enqueued = <GroupPendingBroadcast>[];
        setGroupPendingBroadcastEnqueueSink((b) async => enqueued.add(b));
        addTearDown(() => setGroupPendingBroadcastEnqueueSink(null));

        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final original = makeAdminGroup().copyWith(
          name: 'Original Name',
          description: 'Original Desc',
        );
        await _seedEditableGroup(groupRepo, group: original);
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-alice', username: 'Alice'),
        );
        final bridge = FakeBridge(
          initialResponses: {
            'group:publish': {
              'ok': false,
              'errorMessage': 'simulated publish failure',
            },
            'group:inboxStore': {'ok': true},
          },
        );

        await _pumpEditableGroupInfo(
          tester,
          groupRepo: groupRepo,
          bridge: bridge,
          msgRepo: msgRepo,
        );
        await _openGroupDetailsEditor(tester);
        await tester.enterText(_groupEditNameField(), 'New Name');
        await _tapGroupEditSave(tester);
        await pumpFrames(tester, count: 30);

        // The edit is KEPT (durable retry), not reverted to S2a's fallback.
        final persisted = await groupRepo.getGroup('group-1');
        expect(persisted!.name, 'New Name');
        // A signed broadcast was durably enqueued for retry.
        expect(enqueued, hasLength(1));
        expect(enqueued.single.kind, 'group_metadata_updated');
        expect(enqueued.single.recipientPeerIds, contains('peer-alice'));
        // Honest "will retry" message, never a false success.
        expect(
          find.text('Saved — will retry sending when reconnected'),
          findsOneWidget,
        );
        expect(find.text('Group details updated'), findsNothing);
      },
    );

    testWidgets(
      'GCA-103 post-invite avatar upload includes late invitee in allowedPeers',
      (tester) async {
        final tempDir = await _installPathProviderTempDirForTest();
        final pickedAvatar = await _writePickedAvatar(tempDir, 'gca103-test3');
        final mediaPicker = FakeMediaPicker()
          ..imageResult = XFile(pickedAvatar.path);
        final group = makeAdminGroup().copyWith(
          name: 'test 2',
          description: '222',
        );
        final groupRepo = InMemoryGroupRepository();
        await _seedEditableGroup(groupRepo, group: group);
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-a', username: 'User A'),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-b', username: 'User B'),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-d', username: 'User D'),
        );
        final memberRows = await groupRepo.getMembers(group.id);
        expect(
          memberRows.map((member) => member.peerId),
          containsAll(['peer-admin', 'peer-a', 'peer-b', 'peer-d']),
          reason: 'C has A/B/C/D active member rows before avatar upload',
        );

        var uploadCalls = 0;
        String? capturedGroupId;
        String? capturedLocalFilePath;
        List<String>? capturedAllowedPeers;
        final UploadGroupAvatarFn captureUpload =
            ({
              required Bridge bridge,
              required String localFilePath,
              required String groupId,
              required List<String> allowedPeers,
              String? blobId,
              String mime = 'image/jpeg',
            }) async {
              uploadCalls += 1;
              capturedGroupId = groupId;
              capturedLocalFilePath = localFilePath;
              capturedAllowedPeers = List<String>.from(allowedPeers);
              return GroupAvatarUpload(
                id: 'blob-test-3-avatar',
                mime: mime,
                size: File(localFilePath).lengthSync(),
              );
            };

        await _pumpEditableGroupInfo(
          tester,
          groupRepo: groupRepo,
          group: group,
          mediaPicker: mediaPicker,
          imageProcessor: _testAvatarImageProcessor(),
          uploadGroupAvatarFn: captureUpload,
        );
        await _openGroupDetailsEditor(tester);
        await _pickGroupEditPhoto(tester);
        await tester.enterText(_groupEditNameField(), 'test 3');
        await tester.enterText(_groupEditDescriptionField(), '333');

        await _tapGroupEditSave(tester);
        await pumpFrames(tester, count: 30);

        expect(uploadCalls, 1);
        expect(capturedGroupId, group.id);
        expect(capturedLocalFilePath, isNotNull);
        expect(File(capturedLocalFilePath!).existsSync(), isTrue);
        expect(capturedAllowedPeers, isNotNull);
        expect(
          capturedAllowedPeers,
          containsAll(['peer-admin', 'peer-a', 'peer-b', 'peer-d']),
        );
        expect(
          capturedAllowedPeers!.toSet(),
          hasLength(capturedAllowedPeers!.length),
          reason: 'avatar ACL should not contain duplicate peer ids',
        );
        expect(capturedAllowedPeers, contains('peer-d'));
      },
    );

    testWidgets(
      'TC-200-12 admin picks a non-square photo -> committed preview is square',
      (tester) async {
        final tempDir = await _installPathProviderTempDirForTest();
        final pickedAvatar = await _writePickedAvatar(tempDir, 'tc200-12');
        final mediaPicker = FakeMediaPicker()
          ..imageResult = XFile(pickedAvatar.path);
        // The processor's compress output is a real, decodable non-square (2:1)
        // image; the crop funnel must square it before it reaches the preview.
        // Kept small so the inline pure-Dart crop completes within the pick
        // pump window (squaring is size-independent — 120x60 proves the funnel).
        final nonSquareJpeg = Uint8List.fromList(
          img.encodeJpg(img.Image(width: 120, height: 60), quality: 90),
        );
        final groupRepo = InMemoryGroupRepository();
        await _seedEditableGroup(groupRepo);

        await _pumpEditableGroupInfo(
          tester,
          groupRepo: groupRepo,
          mediaPicker: mediaPicker,
          imageProcessor: _testAvatarImageProcessor(nonSquareJpeg),
        );
        await _openGroupDetailsEditor(tester);
        await _pickGroupEditPhoto(tester);

        GroupInfoScreenAvatarPreview readPreview() =>
            tester.widget<GroupInfoScreenAvatarPreview>(
              find.byType(GroupInfoScreenAvatarPreview),
            );
        // The inline crop resolves asynchronously; pump real time until the
        // committed preview lands so the assertion never races the pick under
        // CPU load (deterministic, not a fixed-window guess).
        for (var i = 0; i < 50 && readPreview().previewBytes == null; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }

        final preview = readPreview();
        expect(preview.previewBytes, isNotNull);
        final decoded = img.decodeImage(preview.previewBytes!)!;
        expect(
          decoded.width,
          decoded.height,
          reason: 'non-square pick must be squared by the normalizer funnel',
        );
      },
    );

    testWidgets(
      'GCA-103 metadata edit refreshes pending invite payload for late invitee',
      (tester) async {
        final group = makeAdminGroup().copyWith(
          name: 'test 2',
          description: '222',
          avatarBlobId: 'avatar-test-3-latest',
          avatarMime: 'image/jpeg',
        );
        final groupRepo = InMemoryGroupRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
        await _seedEditableGroup(groupRepo, group: group);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-bob',
            username: 'Bob',
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-pk-bob',
          ),
        );
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-dana',
            username: 'Dana',
            publicKey: 'pk-dana',
            mlKemPublicKey: 'mlkem-pk-dana',
          ),
        );
        await inviteStatusRepo.saveAttempt(
          GroupInviteDeliveryAttempt(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            status: GroupInviteDeliveryStatus.joined,
            attemptedAt: DateTime.utc(2026, 5, 7, 12),
            updatedAt: DateTime.utc(2026, 5, 7, 12),
          ),
        );
        await inviteStatusRepo.saveAttempt(
          GroupInviteDeliveryAttempt(
            groupId: group.id,
            peerId: 'peer-dana',
            username: 'Dana',
            status: GroupInviteDeliveryStatus.sent,
            attemptedAt: DateTime.utc(2026, 5, 7, 12),
            updatedAt: DateTime.utc(2026, 5, 7, 12),
          ),
        );

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: FakeBridge(),
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: p2pService,
              inviteDeliveryAttemptRepo: inviteStatusRepo,
            ),
          ),
        );
        await pumpFrames(tester);
        await _openGroupDetailsEditor(tester);
        await tester.enterText(_groupEditNameField(), 'test 3');
        await tester.enterText(_groupEditDescriptionField(), '333');

        await _tapGroupEditSave(tester);
        var inviteLogs = <({String content, String peerId})>[];
        for (var i = 0; i < 80; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          inviteLogs = p2pService.sentMessageLog
              .where((entry) {
                final decoded =
                    jsonDecode(entry.content) as Map<String, dynamic>;
                return decoded['type'] == 'group_invite';
              })
              .toList(growable: false);
          if (inviteLogs.isNotEmpty) {
            break;
          }
        }

        final sentTypes = p2pService.sentMessageLog
            .map((entry) {
              final decoded = jsonDecode(entry.content) as Map<String, dynamic>;
              return '${entry.peerId}:${decoded['type']}';
            })
            .toList(growable: false);
        expect(
          inviteLogs.map((entry) => entry.peerId),
          ['peer-dana'],
          reason: 'sent p2p messages: $sentTypes',
        );

        final envelope =
            jsonDecode(inviteLogs.single.content) as Map<String, dynamic>;
        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final refreshedPayload = GroupInvitePayload.fromInnerJson(
          encrypted['ciphertext'] as String,
        );
        expect(refreshedPayload, isNotNull);
        expect(refreshedPayload!.recipientPeerId, 'peer-dana');
        expect(refreshedPayload.groupConfig['name'], 'test 3');
        expect(refreshedPayload.groupConfig['description'], '333');
        expect(
          refreshedPayload.groupConfig['avatarBlobId'],
          'avatar-test-3-latest',
        );
        expect(refreshedPayload.groupConfig['avatarMime'], 'image/jpeg');

        final danaAttempt = await inviteStatusRepo.getAttempt(
          groupId: group.id,
          peerId: 'peer-dana',
        );
        expect(danaAttempt!.status, GroupInviteDeliveryStatus.sent);
      },
    );

    testWidgets(
      'GDR-001 recovery-blocked removal keeps existing canonical avatar until metadata success',
      (tester) async {
        final tempDir = await _installPathProviderTempDirForTest();
        final existingAvatarBytes = Uint8List.fromList([1, 2, 3, 4]);
        final existingAvatarPath = groupAvatarRelativePath('group-1');
        final existingAvatar = File(p.join(tempDir.path, existingAvatarPath));
        existingAvatar.parent.createSync(recursive: true);
        existingAvatar.writeAsBytesSync(existingAvatarBytes, flush: true);
        final group = makeAdminGroup().copyWith(
          avatarBlobId: 'avatar-old',
          avatarMime: 'image/jpeg',
          avatarPath: existingAvatarPath,
        );
        final groupRepo = InMemoryGroupRepository();
        await _seedEditableGroup(groupRepo, group: group);
        final identityRepo = _ControlledRecoveryIdentityRepository(
          identity: testIdentity,
        );

        await _pumpEditableGroupInfo(
          tester,
          groupRepo: groupRepo,
          group: group,
          identityRepo: identityRepo,
        );
        await _openGroupDetailsEditor(tester);
        await tester.tap(find.byKey(const ValueKey('group-edit-remove-photo')));
        await pumpFrames(tester);

        identityRepo.beginRecoveryOnNextLoad = true;
        await _tapGroupEditSave(tester);
        await pumpFrames(tester, count: 30);

        final persisted = await groupRepo.getGroup('group-1');
        expect(existingAvatar.existsSync(), isTrue);
        expect(existingAvatar.readAsBytesSync(), existingAvatarBytes);
        expect(persisted!.avatarBlobId, 'avatar-old');
        expect(persisted.avatarMime, 'image/jpeg');
        expect(persisted.avatarPath, existingAvatarPath);
        expect(find.text(_groupEditRecoveryWaitCopy), findsOneWidget);
      },
    );

    testWidgets(
      'EK004 PREREQ-SIGNED-COMMIT-AUDIT admin metadata edit stores signed replay and audit payloads',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            devices: const [
              GroupMemberDeviceIdentity(
                deviceId: 'device-bob',
                transportPeerId: 'peer-bob-device',
                deviceSigningPublicKey: 'pk-bob',
              ),
            ],
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = FakeBridge();
        final p2pService = FakeP2PService();
        bridge.responses['payload.sign'] = {
          'ok': true,
          'signature': 'sig-metadata',
        };

        // 154: capture platform-channel calls to assert the details save fires
        // HapticFeedback.selectionClick() instead of the success snackbar.
        final platformCalls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          platformCalls.add(call);
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: p2pService,
            ),
          ),
        );
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(const ValueKey('group-edit-details-button')),
        );
        await pumpFrames(tester);

        expect(find.text('Edit Group Details'), findsOneWidget);

        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('group-edit-name-field')),
            matching: find.byType(TextField),
          ),
          'Renamed Group',
        );
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('group-edit-description-field')),
            matching: find.byType(TextField),
          ),
          'Fresh description',
        );

        await tester.tap(find.byKey(const ValueKey('group-edit-save')));
        await pumpFrames(tester, count: 30);

        final updatedGroup = await groupRepo.getGroup('group-1');
        expect(updatedGroup, isNotNull);
        expect(updatedGroup!.name, 'Renamed Group');
        expect(updatedGroup.description, 'Fresh description');
        expect(updatedGroup.lastMetadataEventAt, isNotNull);

        expect(find.text('Renamed Group'), findsWidgets);
        expect(find.text('Fresh description'), findsOneWidget);
        // 154: the field re-render above is the surviving confirmation; the
        // success snackbar is dropped in favour of a tactile selectionClick.
        // Assert method AND arg (every variant shares the method string).
        expect(find.text('Group details updated'), findsNothing);
        expect(
          platformCalls.any(
            (c) =>
                c.method == 'HapticFeedback.vibrate' &&
                c.arguments == 'HapticFeedbackType.selectionClick',
          ),
          isTrue,
          reason: 'details save should fire HapticFeedback.selectionClick()',
        );

        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
        final signIndex = bridge.commandLog.indexOf('payload.sign');
        final publishIndex = bridge.commandLog.indexOf('group:publish');
        final inboxStoreIndex = bridge.commandLog.indexOf('group:inboxStore');
        expect(signIndex, isNonNegative);
        expect(signIndex, lessThan(publishIndex));
        expect(signIndex, lessThan(inboxStoreIndex));

        final publishMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;

        expect(sysText['__sys'], 'group_metadata_updated');
        expect(publishPayload['senderPeerId'], testIdentity.peerId);
        expect(publishPayload['senderPublicKey'], testIdentity.publicKey);
        expect(publishPayload['senderPrivateKey'], testIdentity.privateKey);
        expect(sysText[signedGroupTransitionAuditField], isA<Map>());
        final audit = (sysText[signedGroupTransitionAuditField] as Map)
            .cast<String, dynamic>();
        expect(audit['transitionType'], 'group_metadata_updated');
        expect(audit['groupId'], 'group-1');
        expect(audit['sourceEventId'], publishPayload['messageId']);
        expect(
          audit['signatureAlgorithm'],
          signedGroupTransitionAuditSignatureAlgorithm,
        );
        expect(audit['signature'], 'sig-metadata');
        final auditPayload =
            jsonDecode(audit['signedPayload'] as String)
                as Map<String, dynamic>;
        expect(auditPayload['sourceEventId'], publishPayload['messageId']);
        expect(auditPayload['transitionType'], 'group_metadata_updated');
        expect(auditPayload['transitionOutputHash'], isA<String>());
        expect(auditPayload['preTransitionStateHash'], isA<String>());
        expect(
          (auditPayload['actor'] as Map)['signingPublicKey'],
          testIdentity.publicKey,
        );
        expect(
          audit['signedPayload'] as String,
          isNot(contains(testIdentity.privateKey)),
        );
        expect(sysText['groupConfig']['name'], 'Renamed Group');
        expect(sysText['groupConfig']['description'], 'Fresh description');
        expect(
          sysText['groupConfig'][groupConfigVersionField],
          updatedGroup.lastMetadataEventAt!.toUtc().toIso8601String(),
        );
        expect(sysText['groupConfig'][groupConfigStateHashField], isNotEmpty);
        expect(
          isGroupConfigStateHashValid(
            groupId: 'group-1',
            groupConfig: (sysText['groupConfig'] as Map)
                .cast<String, dynamic>(),
          ),
          isTrue,
        );
        final actorEvent =
            (sysText[groupMetadataActorEventEnvelopeField] as Map)
                .cast<String, dynamic>();
        expect(
          actorEvent[groupMetadataActorEventSignatureField],
          'sig-metadata',
        );
        expect(
          actorEvent[groupMetadataActorEventSignatureAlgorithmField],
          groupMetadataActorEventSignatureAlgorithm,
        );

        final signMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'payload.sign';
        });
        final signPayload =
            (jsonDecode(signMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(signPayload['privateKey'], testIdentity.privateKey);
        expect(
          signPayload['data'],
          actorEvent[groupMetadataActorEventSignedPayloadField],
        );

        final signedPayload =
            jsonDecode(
                  actorEvent[groupMetadataActorEventSignedPayloadField]
                      as String,
                )
                as Map<String, dynamic>;
        expect(signedPayload['eventType'], 'group_metadata_updated');
        expect(signedPayload['groupId'], 'group-1');
        expect(signedPayload['updatedAt'], sysText['updatedAt']);
        expect(signedPayload['groupConfig'], sysText['groupConfig']);
        expect(
          signedPayload['groupConfigVersion'],
          sysText['groupConfig'][groupConfigVersionField],
        );
        expect(
          signedPayload['groupConfigStateHash'],
          sysText['groupConfig'][groupConfigStateHashField],
        );
        final actor = (signedPayload['actor'] as Map).cast<String, dynamic>();
        expect(actor['peerId'], testIdentity.peerId);
        expect(actor['username'], testIdentity.username);
        expect(actor['publicKey'], testIdentity.publicKey);
        expect(jsonEncode(sysText), isNot(contains(testIdentity.privateKey)));
        expect(
          jsonEncode(actorEvent),
          isNot(contains(testIdentity.privateKey)),
        );
        expect(
          actorEvent[groupMetadataActorEventSignedPayloadField] as String,
          isNot(contains(testIdentity.privateKey)),
        );
        expect(jsonEncode(sysText), isNot(contains('senderPrivateKey')));

        final inboxStoreMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:inboxStore';
        });
        final inboxStorePayload =
            (jsonDecode(inboxStoreMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(inboxStorePayload['recipientPeerIds'], ['peer-bob']);
        expect(inboxStorePayload['preserveRecipientPeerIds'], isTrue);
        final directUpdate = p2pService.sentMessageLog.singleWhere(
          (entry) => entry.peerId == 'peer-bob-device',
        );
        final directEnvelope =
            jsonDecode(directUpdate.content) as Map<String, dynamic>;
        expect(directEnvelope['type'], groupMembershipUpdateMessageType);
        expect(directEnvelope['groupId'], 'group-1');
        expect(
          (directEnvelope['relayEnvelope'] as Map<String, dynamic>)['message'],
          inboxStorePayload['message'],
        );
        final replayEnvelope = _storedGroupReplayEnvelope(
          inboxStorePayload['message'] as String,
        );
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['payloadType'], 'group_message');
        expect(replayEnvelope['senderPeerId'], testIdentity.peerId);
        expect(replayEnvelope['senderPublicKey'], testIdentity.publicKey);
        expect(replayEnvelope['signatureAlgorithm'], 'ed25519');
        expect(replayEnvelope['signedPayload'], isA<String>());
        expect(replayEnvelope['signature'], isA<String>());
        expect(replayEnvelope['messageId'], publishPayload['messageId']);
        final replaySignedPayload =
            jsonDecode(replayEnvelope['signedPayload'] as String)
                as Map<String, dynamic>;
        expect(replaySignedPayload['messageId'], publishPayload['messageId']);
        final inboxEnvelope = _decodedGroupReplayPayload(
          inboxStorePayload['message'] as String,
        );
        expect(inboxEnvelope['messageId'], publishPayload['messageId']);
        expect(inboxEnvelope['text'], publishPayload['text']);
        final inboxSysText =
            jsonDecode(inboxEnvelope['text'] as String) as Map<String, dynamic>;
        expect(
          inboxSysText[groupMetadataActorEventEnvelopeField],
          sysText[groupMetadataActorEventEnvelopeField],
        );

        final latestTimeline = await msgRepo.getLatestMessage('group-1');
        expect(latestTimeline, isNotNull);
        expect(
          latestTimeline!.text,
          buildGroupMetadataUpdatedTimelineText('Admin'),
        );
      },
    );

    testWidgets(
      'admin metadata edit signing failure aborts before persist, timeline, publish, and inbox store',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = FakeBridge();
        final p2pService = FakeP2PService();
        bridge.responses['payload.sign'] = {'ok': false};

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: p2pService,
            ),
          ),
        );
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(const ValueKey('group-edit-details-button')),
        );
        await pumpFrames(tester);
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('group-edit-name-field')),
            matching: find.byType(TextField),
          ),
          'Renamed Group',
        );
        await tester.tap(find.byKey(const ValueKey('group-edit-save')));
        await pumpFrames(tester, count: 30);

        final unchangedGroup = await groupRepo.getGroup('group-1');
        expect(unchangedGroup, isNotNull);
        expect(unchangedGroup!.name, 'Test Group');
        expect(unchangedGroup.description, 'A test group');
        expect(unchangedGroup.lastMetadataEventAt, isNull);
        expect(msgRepo.count, 0);
        expect(bridge.commandLog, contains('payload.sign'));
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
        expect(
          find.text('Failed to sign group metadata update'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'EK004 promote member stores signed member_role_updated replay envelope',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-alice',
            username: 'Alice',
            role: MemberRole.writer,
            publicKey: 'pk-alice',
            mlKemPublicKey: 'mlkem-pk-alice',
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = FakeBridge();
        final p2pService = FakeP2PService();

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: p2pService,
            ),
          ),
        );
        await pumpFrames(tester);

        await openRoleActionMenu(tester, 'peer-alice');
        expect(find.text('Make Admin'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('group-member-toggle-admin-peer-alice')),
        );
        await pumpFrames(tester);

        expect(find.text('Make Alice an admin?'), findsOneWidget);
        expect(
          find.text('They will be able to add, remove, and manage members.'),
          findsOneWidget,
        );

        await confirmRoleChangeDialog(tester);

        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        expect(
          find.descendant(of: aliceRow, matching: find.text('admin')),
          findsOneWidget,
        );
        expect(find.text('Alice is now an admin'), findsOneWidget);

        final updatedMember = await groupRepo.getMember(
          'group-1',
          'peer-alice',
        );
        expect(updatedMember?.role, MemberRole.admin);

        expect(bridge.commandLog, contains('group:updateConfig'));
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        final publishMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;

        expect(sysText['__sys'], 'member_role_updated');
        expect(
          DateTime.tryParse(sysText['eventAt'] as String? ?? ''),
          isNotNull,
        );
        expect(sysText['member']['peerId'], 'peer-alice');
        expect(sysText['member']['role'], 'admin');

        final inboxStoreMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:inboxStore';
        });
        final inboxStorePayload =
            (jsonDecode(inboxStoreMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(inboxStorePayload['recipientPeerIds'], ['peer-alice']);
        expect(inboxStorePayload['preserveRecipientPeerIds'], isTrue);
        final replayEnvelope = _storedGroupReplayEnvelope(
          inboxStorePayload['message'] as String,
        );
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['payloadType'], 'group_message');
        expect(replayEnvelope['senderPeerId'], testIdentity.peerId);
        expect(replayEnvelope['senderPublicKey'], testIdentity.publicKey);
        expect(replayEnvelope['signatureAlgorithm'], 'ed25519');
        expect(replayEnvelope['signedPayload'], isA<String>());
        expect(replayEnvelope['signature'], isA<String>());

        expect(p2pService.sentMessageLog, hasLength(1));
        final directUpdate = p2pService.sentMessageLog.single;
        expect(directUpdate.peerId, 'peer-alice');
        final directEnvelope =
            jsonDecode(directUpdate.content) as Map<String, dynamic>;
        expect(directEnvelope['type'], groupMembershipUpdateMessageType);
        expect(directEnvelope['groupId'], 'group-1');
        final directRelayEnvelope =
            directEnvelope['relayEnvelope'] as Map<String, dynamic>;
        expect(directRelayEnvelope['from'], testIdentity.peerId);
        expect(directRelayEnvelope['message'], inboxStorePayload['message']);

        final latestTimeline = await msgRepo.getLatestMessage('group-1');
        expect(latestTimeline, isNotNull);
        expect(
          latestTimeline!.text,
          buildMemberRoleUpdatedTimelineText(
            'Admin',
            'Alice',
            previousRole: MemberRole.writer,
            newRole: MemberRole.admin,
          ),
        );
      },
    );

    testWidgets(
      'demote admin shows confirmation, updates badge, and emits success feedback',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            mlKemPublicKey: 'mlkem-pk-alice',
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        await openRoleActionMenu(tester, 'peer-alice');
        expect(find.text('Remove Admin'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('group-member-toggle-admin-peer-alice')),
        );
        await pumpFrames(tester);

        expect(find.text('Remove admin access from Alice?'), findsOneWidget);
        expect(
          find.text(
            'They will lose admin-only actions after the change syncs.',
          ),
          findsOneWidget,
        );

        await confirmRoleChangeDialog(tester);

        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        expect(
          find.descendant(of: aliceRow, matching: find.text('writer')),
          findsOneWidget,
        );
        expect(find.text('Alice is no longer an admin'), findsOneWidget);

        final updatedMember = await groupRepo.getMember(
          'group-1',
          'peer-alice',
        );
        expect(updatedMember?.role, MemberRole.writer);

        final publishMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;
        expect(sysText['member']['role'], 'writer');
      },
    );

    testWidgets(
      'GCA-009 leave group deletes local messages and pops to first route',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-left-group',
            groupId: group.id,
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'local history to remove',
            timestamp: DateTime.utc(2026, 5, 23, 10),
            createdAt: DateTime.utc(2026, 5, 23, 10),
            isIncoming: false,
            status: 'sent',
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-other-group',
            groupId: 'group-other',
            senderPeerId: 'peer-other',
            senderUsername: 'Other',
            text: 'local history to keep',
            timestamp: DateTime.utc(2026, 5, 23, 11),
            createdAt: DateTime.utc(2026, 5, 23, 11),
            isIncoming: true,
            status: 'delivered',
          ),
        );

        final bridge = FakeBridge();

        // Use a Navigator stack to verify popUntil(isFirst)
        await tester.pumpWidget(
          _localizedMaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: testIdentity,
                          ),
                          p2pService: FakeP2PService(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        // Navigate to group info
        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 20);

        // Verify info screen is showing
        expect(find.byType(GroupInfoScreen), findsOneWidget);

        // Tap Leave Group
        await tapLeaveGroupButton(tester);

        // Verify bridge received group:leave command
        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(await msgRepo.getMessage('msg-left-group'), isNull);
        expect(await msgRepo.getMessage('msg-other-group'), isNotNull);
        expect(await groupRepo.getGroup(group.id), isNull);

        // Verify popped back to first route
        expect(find.byType(GroupInfoScreen), findsNothing);
        expect(find.text('Open Info'), findsOneWidget);
      },
    );

    testWidgets('sole admin leave stays on screen and shows an error', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );

      final bridge = FakeBridge();

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupInfoWired(
                        group: group,
                        groupRepo: groupRepo,
                        contactRepo: InMemoryContactRepository(),
                        bridge: bridge,
                        identityRepo: FakeIdentityRepository(
                          identity: testIdentity,
                        ),
                        p2pService: FakeP2PService(),
                      ),
                    ),
                  );
                },
                child: const Text('Open Info'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Info'));
      await pumpFrames(tester, count: 20);

      expect(find.byType(GroupInfoScreen), findsOneWidget);

      await tapLeaveGroupButton(tester);

      expect(bridge.commandLog, isNot(contains('group:leave')));
      expect(find.byType(GroupInfoScreen), findsOneWidget);
      expect(find.text('Open Info'), findsNothing);
      expect(find.text(lastAdminLeaveBlockedMessage), findsOneWidget);
      expect(await groupRepo.getGroup(group.id), isNotNull);
    });

    testWidgets(
      'BB-010 native leave failure stays on info screen and shows failed leave',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        final bridge = FakeBridge();
        bridge.responses['group:leave'] = {
          'ok': false,
          'errorCode': 'GROUP_ERROR',
          'errorMessage': 'forced leave failure',
        };

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: testIdentity,
                          ),
                          p2pService: FakeP2PService(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 20);

        expect(find.byType(GroupInfoScreen), findsOneWidget);

        await tapLeaveGroupButton(tester);

        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(find.byType(GroupInfoScreen), findsOneWidget);
        expect(find.text('Open Info'), findsNothing);
        expect(find.text('Failed to leave group'), findsOneWidget);
        expect(await groupRepo.getGroup(group.id), isNotNull);
        expect(await groupRepo.getLatestKey(group.id), isNotNull);
      },
    );

    testWidgets(
      'GCA-010 native leave failure rolls back local artifacts after pre-leave broadcast',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await _saveGroupReplayKey(groupRepo, generation: 2);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
          ),
        );
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.admin,
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-pk-bob',
          ),
        );
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            mlKemPublicKey: 'mlkem-pk-charlie',
          ),
        );

        final bridge = PassthroughCryptoBridge();
        bridge.responses['group:leave'] = {
          'ok': false,
          'errorCode': 'GROUP_ERROR',
          'errorMessage': 'forced leave failure',
        };
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-self-removal',
        };
        bridge.responses['group:inboxStore'] = {'ok': true};
        bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'failed-leave-rotated-key',
          'keyEpoch': 3,
        };
        final p2pService = FakeP2PService();

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: testIdentity,
                          ),
                          p2pService: p2pService,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 30);

        expect(find.byType(GroupInfoScreen), findsOneWidget);

        await tapLeaveGroupButton(tester, settleFrameCount: 30);

        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        final publishIndex = bridge.commandLog.indexOf('group:publish');
        final inboxStoreIndex = bridge.commandLog.indexOf('group:inboxStore');
        final generateKeyIndex = bridge.commandLog.indexOf(
          'group:generateNextKey',
        );
        final leaveIndex = bridge.commandLog.indexOf('group:leave');
        expect(publishIndex, isNonNegative);
        expect(inboxStoreIndex, isNonNegative);
        expect(generateKeyIndex, isNonNegative);
        expect(publishIndex, lessThan(leaveIndex));
        expect(inboxStoreIndex, lessThan(leaveIndex));
        expect(generateKeyIndex, lessThan(leaveIndex));
        expect(p2pService.sentMessageLog.length, 2);
        expect(await msgRepo.getMessageCount('group-1'), 0);
        expect(await groupRepo.getGroup('group-1'), isNotNull);
        final members = await groupRepo.getMembers('group-1');
        expect(members.map((member) => member.peerId), [
          'peer-admin',
          'peer-bob',
          'peer-charlie',
        ]);
        final latestKey = await groupRepo.getLatestKey('group-1');
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 2);
        expect(latestKey.encryptedKey, 'test-group-key-2');
        expect(await groupRepo.getKeyByGeneration('group-1', 1), isNotNull);
        expect(await groupRepo.getKeyByGeneration('group-1', 3), isNull);
        expect(find.byType(GroupInfoScreen), findsOneWidget);
        expect(find.text('Open Info'), findsNothing);
        expect(find.text('Failed to leave group'), findsOneWidget);
      },
    );

    testWidgets(
      'writer Leave tears down local membership even when rotation is deferred',
      (tester) async {
        // Non-creator writer voluntary leave: the leaver cannot rotate the key,
        // so the departure rotation is deferred (best-effort). The leave must
        // still reach leaveGroup() and tear down local membership instead of
        // dead-ending on the old "Failed to rotate group key before leaving".
        final writerIdentity = IdentityModel(
          peerId: 'peer-writer',
          publicKey: 'pk-writer',
          privateKey: 'sk-writer',
          mnemonic12:
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 '
              'word11 word12',
          mlKemPublicKey: 'mlkem-pk-writer',
          username: 'Writer',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        );

        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        // myRole == member, createdBy == peer-admin (NOT the leaver): both
        // rotation gates deny the writer.
        final group = makeMemberGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
          ),
        );
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-writer',
            username: 'Writer',
            role: MemberRole.writer,
            publicKey: 'pk-writer',
            mlKemPublicKey: 'mlkem-pk-writer',
          ),
        );
        // A remaining member so the use case attempts (and defers) rotation.
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-pk-bob',
          ),
        );

        final bridge = PassthroughCryptoBridge();
        bridge.responses['group:leave'] = {'ok': true};
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'writer-leave-sys',
        };
        bridge.responses['group:inboxStore'] = {'ok': true};

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: writerIdentity,
                          ),
                          p2pService: FakeP2PService(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 30);

        expect(find.byType(GroupInfoScreen), findsOneWidget);

        await tapLeaveGroupButton(tester, settleFrameCount: 30);

        // The member_removed was broadcast, then leaveGroup() ran and tore down
        // local membership.
        expect(bridge.commandLog, contains('group:publish'));
        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        // Rotation was deferred, not performed: the writer never generated a key.
        expect(bridge.commandLog, isNot(contains('group:generateNextKey')));
        // Local membership torn down (leaveGroup deletes the group).
        expect(await groupRepo.getGroup('group-1'), isNull);
        // No rotation-failed error and no native-leave failure SnackBar.
        expect(
          find.text('Failed to rotate group key before leaving'),
          findsNothing,
        );
        expect(find.text('Failed to leave group'), findsNothing);
        // Popped back to the first route.
        expect(find.byType(GroupInfoScreen), findsNothing);
        expect(find.text('Open Info'), findsOneWidget);
      },
    );

    testWidgets(
      'dissolved local delete clears local state without publishing group leave and pops to the first route',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup().copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
          dissolvedBy: 'peer-admin',
        );
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-dissolved-1',
            groupId: group.id,
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Admin dissolved the group',
            timestamp: DateTime.utc(2026, 4, 5, 12, 0, 0),
            createdAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
            isIncoming: false,
            status: 'sent',
          ),
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: testIdentity,
                          ),
                          p2pService: FakeP2PService(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 20);

        await scrollToDeleteLocalGroupButton(tester);
        expect(
          find.byKey(const ValueKey('group-delete-local-button')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('group-delete-local-button')),
        );
        await pumpFrames(tester, count: 5);

        expect(
          find.byKey(const ValueKey('group-delete-local-confirm')),
          findsOneWidget,
        );

        await confirmDeleteLocalGroupDialog(tester);

        expect(await groupRepo.getGroup(group.id), isNull);
        expect(await groupRepo.getLatestKey(group.id), isNull);
        expect(await groupRepo.getMembers(group.id), isEmpty);
        expect(await msgRepo.getMessageCount(group.id), 0);
        expect(bridge.commandLog, isNot(contains('group:leave')));
        expect(find.byType(GroupInfoScreen), findsNothing);
        expect(find.text('Open Info'), findsOneWidget);
      },
    );

    testWidgets(
      'canceling dissolved local delete keeps the group state and route intact',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup().copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
          dissolvedBy: 'peer-admin',
        );
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-dissolved-2',
            groupId: group.id,
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Admin dissolved the group',
            timestamp: DateTime.utc(2026, 4, 5, 12, 0, 0),
            createdAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
            isIncoming: false,
            status: 'sent',
          ),
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: testIdentity,
                          ),
                          p2pService: FakeP2PService(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 20);

        await scrollToDeleteLocalGroupButton(tester);
        await tester.tap(
          find.byKey(const ValueKey('group-delete-local-button')),
        );
        await pumpFrames(tester, count: 5);

        expect(
          find.byKey(const ValueKey('group-delete-local-cancel')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('group-delete-local-cancel')),
        );
        await pumpFrames(tester, count: 20);

        expect(await groupRepo.getGroup(group.id), isNotNull);
        expect(await groupRepo.getLatestKey(group.id), isNotNull);
        expect(await msgRepo.getMessageCount(group.id), 1);
        expect(bridge.commandLog, isNot(contains('group:leave')));
        expect(find.byType(GroupInfoScreen), findsOneWidget);
        expect(find.text('Open Info'), findsNothing);
      },
    );

    testWidgets(
      'multi-admin leave broadcasts self-removal, rotates key, and pops to first route',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.admin,
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-pk-bob',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            mlKemPublicKey: 'mlkem-pk-charlie',
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = PassthroughCryptoBridge();
        bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'fake-rotated-key',
          'keyEpoch': 2,
        };
        bridge.responses['group:publish'] = {'ok': true, 'messageId': 'msg-1'};
        final p2pService = FakeP2PService();

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: testIdentity,
                          ),
                          p2pService: p2pService,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 30);

        expect(find.byType(GroupInfoScreen), findsOneWidget);

        await tapLeaveGroupButton(tester, settleFrameCount: 30);

        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
        expect(bridge.commandLog, contains('group:generateNextKey'));
        expect(bridge.commandLog, contains('group:leave'));
        expect(
          bridge.commandLog.indexOf('group:publish'),
          lessThan(bridge.commandLog.indexOf('group:leave')),
        );
        expect(
          bridge.commandLog.indexOf('group:inboxStore'),
          lessThan(bridge.commandLog.indexOf('group:leave')),
        );
        expect(
          bridge.commandLog.indexOf('group:generateNextKey'),
          lessThan(bridge.commandLog.indexOf('group:leave')),
        );
        expect(p2pService.sentMessageLog.length, 2);

        final publishMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish' &&
              ((parsed['payload'] as Map<String, dynamic>)['text'] as String)
                  .contains('"__sys":"member_removed"');
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;
        expect(sysText['member']['peerId'], 'peer-admin');
        expect(sysText['member']['username'], 'Admin');

        expect(await msgRepo.getMessageCount('group-1'), 0);

        expect(await groupRepo.getGroup('group-1'), isNull);
        expect(find.byType(GroupInfoScreen), findsNothing);
        expect(find.text('Open Info'), findsOneWidget);
      },
    );

    testWidgets(
      'writer leave broadcasts a durable left-the-group event before local cleanup',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeMemberGroup().copyWith(createdBy: 'peer-bob');
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            permissions: const GroupMemberPermissions(rotateKeys: true),
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-pk-bob',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            mlKemPublicKey: 'mlkem-pk-charlie',
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final leavingIdentity = IdentityModel(
          peerId: 'peer-bob',
          publicKey: 'pk-bob',
          privateKey: 'sk-bob',
          mnemonic12:
              'one two three four five six seven eight nine ten eleven twelve',
          mlKemPublicKey: 'mlkem-pk-bob',
          username: 'Bob',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        );

        final bridge = PassthroughCryptoBridge();
        bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'writer-rotated-key',
          'keyEpoch': 2,
        };
        final p2pService = FakeP2PService();

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: leavingIdentity,
                          ),
                          p2pService: p2pService,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 30);

        expect(find.byType(GroupInfoScreen), findsOneWidget);

        await tapLeaveGroupButton(tester, settleFrameCount: 30);

        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
        expect(bridge.commandLog, contains('group:generateNextKey'));
        expect(bridge.commandLog, contains('group:leave'));
        expect(
          bridge.commandLog.indexOf('group:publish'),
          lessThan(bridge.commandLog.indexOf('group:leave')),
        );
        expect(
          bridge.commandLog.indexOf('group:inboxStore'),
          lessThan(bridge.commandLog.indexOf('group:leave')),
        );
        expect(
          bridge.commandLog.indexOf('group:generateNextKey'),
          lessThan(bridge.commandLog.indexOf('group:leave')),
        );
        expect(p2pService.sentMessageLog.length, 2);

        expect(await msgRepo.getMessageCount('group-1'), 0);

        expect(await groupRepo.getGroup('group-1'), isNull);
        expect(find.byType(GroupInfoScreen), findsNothing);
      },
    );

    testWidgets(
      'GCA-008 pre-broadcast failure rolls back; post-broadcast failure stands without re-grant',
      (tester) async {
        final preRemovalWatermark = DateTime.utc(2026, 5, 11, 10);
        const cases = [
          // Pre-broadcast failure: member_removed never went out, so rolling
          // back and re-adding Alice is still correct.
          _Gca008RemovalFailureCase(
            name: 'publish ok false (pre-broadcast)',
            responses: {
              'group:publish': {
                'ok': false,
                'errorMessage': 'forced publish failure',
              },
            },
            expectInboxStore: false,
            expectGenerateNextKey: false,
            expectMemberRemoved: false,
          ),
          // Post-broadcast failure: member_removed already published. Re-adding
          // Alice would re-grant the rotated-away key (INV-R2), so the removal
          // must STAND.
          _Gca008RemovalFailureCase(
            name: 'inbox store ok false (post-broadcast)',
            responses: {
              'group:inboxStore': {
                'ok': false,
                'errorCode': 'INBOX_FAILED',
                'errorMessage': 'forced inbox failure',
              },
            },
            expectInboxStore: true,
            expectGenerateNextKey: false,
            expectMemberRemoved: true,
          ),
          // Post-broadcast re-key failure: rotation cannot promote. The removal
          // stands (no throw, no rollback); the removed member keeps the OLD key
          // until a later rotation, never re-granted the new one.
          _Gca008RemovalFailureCase(
            name: 'key rotation fails (post-broadcast)',
            responses: {
              'group:generateNextKey': {
                'ok': false,
                'errorCode': 'ROTATION_FAILED',
                'errorMessage': 'forced rotation failure',
              },
            },
            expectInboxStore: true,
            expectGenerateNextKey: true,
            expectMemberRemoved: true,
          ),
        ];

        for (final failureCase in cases) {
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpFrames(tester, count: 2);

          final fixture = await _pumpGca008RemovalFailureFixture(
            tester,
            preRemovalWatermark: preRemovalWatermark,
            bridgeResponses: failureCase.responses,
          );

          expect(find.text('Alice'), findsOneWidget);

          await _removeAliceFromGroupInfo(tester);

          final aliceAfter = await fixture.groupRepo.getMember(
            'group-1',
            'peer-alice',
          );
          final configPeerIds = _lastUpdateConfigMemberPeerIds(fixture.bridge);

          if (failureCase.expectMemberRemoved) {
            // INV-R2: the removal stands; Alice is never re-added anywhere.
            expect(
              aliceAfter,
              isNull,
              reason:
                  '${failureCase.name} must keep Alice removed (no re-grant)',
            );
            expect(
              configPeerIds,
              isNot(contains('peer-alice')),
              reason:
                  '${failureCase.name} must not re-publish a config with Alice',
            );
            expect(find.text('Alice'), findsNothing);
          } else {
            // Pre-broadcast: rollback restores Alice and the prior state.
            expect(
              aliceAfter,
              isNotNull,
              reason: '${failureCase.name} should restore Alice locally',
            );
            expect(aliceAfter!.username, 'Alice');

            final restoredGroup = await fixture.groupRepo.getGroup('group-1');
            expect(
              restoredGroup?.lastMembershipEventAt?.toUtc(),
              preRemovalWatermark,
              reason:
                  '${failureCase.name} should restore the membership watermark',
            );
            expect(
              await fixture.msgRepo.getLatestSystemEventTimestampForTarget(
                'group-1',
                eventType: 'member_removed',
                targetId: 'peer-alice',
              ),
              isNull,
              reason:
                  '${failureCase.name} should delete the failed removal timeline',
            );
            expect(await fixture.msgRepo.getMessageCount('group-1'), 0);

            expect(find.text('Alice'), findsOneWidget);
            expect(
              find.byKey(const ValueKey('group-member-remove-peer-alice')),
              findsOneWidget,
            );
            expect(configPeerIds, contains('peer-admin'));
            expect(configPeerIds, contains('peer-alice'));
            expect(configPeerIds, contains('peer-bob'));
          }

          if (failureCase.expectInboxStore) {
            expect(fixture.bridge.commandLog, contains('group:inboxStore'));
          } else {
            expect(
              fixture.bridge.commandLog,
              isNot(contains('group:inboxStore')),
            );
          }
          if (failureCase.expectGenerateNextKey) {
            expect(
              fixture.bridge.commandLog,
              contains('group:generateNextKey'),
            );
          } else {
            expect(
              fixture.bridge.commandLog,
              isNot(contains('group:generateNextKey')),
            );
          }
        }
      },
    );

    testWidgets(
      'G3: member_removed soft publish failure durably enqueues the broadcast '
      'and keeps the removal (no rollback)',
      (tester) async {
        final enqueued = <GroupPendingBroadcast>[];
        setGroupPendingBroadcastEnqueueSink((b) async => enqueued.add(b));
        addTearDown(() => setGroupPendingBroadcastEnqueueSink(null));

        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
          ),
        );
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-alice',
            username: 'Alice',
            publicKey: 'pk-alice',
            mlKemPublicKey: 'mlkem-pk-alice',
          ),
        );
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-bob',
            username: 'Bob',
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-pk-bob',
          ),
        );

        // floodPublish soft-fails (no fanout), but the durable inbox store and
        // the key rotation still succeed.
        final bridge = FakeBridge(
          initialResponses: {
            'group:publish': {
              'ok': false,
              'errorMessage': 'simulated publish failure',
            },
            'group:inboxStore': {'ok': true},
            'group:generateNextKey': {
              'ok': true,
              'groupKey': 'fake-rotated-key',
              'keyEpoch': 2,
            },
          },
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Alice'), findsOneWidget);
        await _removeAliceFromGroupInfo(tester);
        await pumpFrames(tester, count: 30);

        // The removal STANDS — no rollback that re-adds Alice (which would
        // re-grant the rotated-away key, INV-R2).
        expect(await groupRepo.getMember('group-1', 'peer-alice'), isNull);
        expect(find.text('Alice'), findsNothing);

        // The already-signed member_removed broadcast is durably enqueued for
        // re-push, carrying the canonical (eventAt, sourceMessageId) pair the
        // use case minted (G3 durable resend + G5 canonical pair).
        expect(enqueued, hasLength(1));
        final broadcast = enqueued.single;
        expect(broadcast.kind, 'member_removed');
        expect(
          broadcast.recipientPeerIds,
          containsAll(<String>['peer-alice', 'peer-bob']),
        );
        expect(broadcast.sysText, contains('"__sys":"member_removed"'));
        final updatedGroup = await groupRepo.getGroup('group-1');
        expect(broadcast.sourceMessageId, updatedGroup!.lastMembershipEventId);
        expect(broadcast.eventAt.toUtc(), updatedGroup.lastMembershipEventAt?.toUtc());

        // Convergence still proceeds: durable inbox delivery + key rotation.
        expect(bridge.commandLog, contains('group:inboxStore'));
        expect(bridge.commandLog, contains('group:generateNextKey'));
      },
    );

    testWidgets(
      'removal stands with a keyless bystander and shows a partial-distribution notice',
      (tester) async {
        // Headline P0 (INV-R1/INV-R2): admin removes Alice while remaining
        // member Bob is keyless. Promote-then-defer advances the epoch (Alice
        // loses the live key), the removal is durable (no rollback), and a
        // non-fatal partial-distribution notice is shown.
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
          ),
        );
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-alice',
            username: 'Alice',
            publicKey: 'pk-alice',
            mlKemPublicKey: 'mlkem-pk-alice',
          ),
        );
        // Bob is a keyless bystander (no ML-KEM key) — deferred, NOT a blocker.
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-bob', username: 'Bob', publicKey: 'pk-bob'),
        );

        final bridge = FakeBridge(
          initialResponses: {
            'group:publish': {'ok': true, 'messageId': 'msg-1'},
            'group:inboxStore': {'ok': true},
            'group:generateNextKey': {
              'ok': true,
              'groupKey': 'fake-rotated-key',
              'keyEpoch': 2,
            },
          },
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Alice'), findsOneWidget);
        await _removeAliceFromGroupInfo(tester);

        // Removal is durable: Alice gone, no rollback, never re-added to config.
        expect(await groupRepo.getMember('group-1', 'peer-alice'), isNull);
        expect(find.text('Alice'), findsNothing);
        expect(
          _lastUpdateConfigMemberPeerIds(bridge),
          isNot(contains('peer-alice')),
        );
        // Epoch advanced — the removed member loses the live key.
        expect((await groupRepo.getLatestKey('group-1'))!.keyGeneration, 2);
        // A non-fatal partial-distribution notice is shown (Bob deferred); this
        // is NOT the failure path.
        expect(
          find.text(
            'Member removed. Some members will receive the new key '
            'when they reconnect.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('remove member updates config and refreshes member list', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      final m1 = makeMember(
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
      );
      final m2 = makeMember(peerId: 'peer-alice', username: 'Alice');

      await groupRepo.saveMember(m1);
      await groupRepo.saveMember(m2);

      final bridge = FakeBridge(
        initialResponses: {
          'group:generateNextKey': {
            'ok': true,
            'groupKey': 'fake-rotated-key',
            'keyEpoch': 2,
          },
        },
      );

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: bridge,
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      // Verify Alice is shown
      expect(find.text('Alice'), findsOneWidget);

      // Tap the remove icon button on Alice's row
      final removeButtons = find.byIcon(Icons.remove_circle_outline);
      expect(removeButtons, findsWidgets);

      await tester.ensureVisible(removeButtons.last);
      await pumpFrames(tester, count: 5);
      await tester.tap(removeButtons.last, warnIfMissed: false);
      await pumpFrames(tester);

      expect(find.text('Remove Alice from the group?'), findsOneWidget);
      expect(
        find.text('They will stop receiving new messages from this group.'),
        findsOneWidget,
      );

      await confirmRemoveMemberDialog(tester);

      // Verify bridge received group:updateConfig AND group:generateNextKey
      expect(bridge.commandLog, contains('group:updateConfig'));
      expect(bridge.commandLog, contains('group:inboxStore'));
      expect(bridge.commandLog, contains('group:generateNextKey'));

      // Alice should disappear after the member list refresh
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('remove member broadcasts system message and rotates key', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      final admin = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-admin',
        mlKemPublicKey: 'mlkem-pk-admin',
        joinedAt: DateTime.now().toUtc(),
      );
      final alice = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-alice',
        username: 'Alice',
        role: MemberRole.writer,
        publicKey: 'pk-alice',
        mlKemPublicKey: 'mlkem-pk-alice',
        joinedAt: DateTime.now().toUtc(),
      );
      final bob = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-bob',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-bob',
        mlKemPublicKey: 'mlkem-pk-bob',
        joinedAt: DateTime.now().toUtc(),
      );

      await groupRepo.saveMember(admin);
      await groupRepo.saveMember(alice);
      await groupRepo.saveMember(bob);

      final bridge = FakeBridge(
        initialResponses: {
          'group:generateNextKey': {
            'ok': true,
            'groupKey': 'fake-rotated-key',
            'keyEpoch': 2,
          },
        },
      );
      final p2pService = FakeP2PService();

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: bridge,
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: p2pService,
          ),
        ),
      );
      await pumpFrames(tester);

      // Verify all members are shown
      expect(find.text('You'), findsOneWidget); // admin shows as "You"
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Find the remove button specifically on Alice's row.
      final aliceRow = find.ancestor(
        of: find.text('Alice'),
        matching: find.byType(Row),
      );
      final aliceRemoveButton = find.descendant(
        of: aliceRow,
        matching: find.byIcon(Icons.remove_circle_outline),
      );
      expect(aliceRemoveButton, findsOneWidget);

      await tester.ensureVisible(aliceRemoveButton);
      await pumpFrames(tester, count: 5);
      await tester.tap(aliceRemoveButton, warnIfMissed: false);
      await pumpFrames(tester);
      await confirmRemoveMemberDialog(tester);

      // Verify the live broadcast and replay artifact both ran.
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));

      // Key generation starts after broadcast to preserve the current flow shape
      expect(bridge.commandLog, contains('group:generateNextKey'));
    });

    testWidgets(
      'remove member calls bridge in correct order: updateConfig → publish → inboxStore → generateNextKey',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        final admin = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          mlKemPublicKey: 'mlkem-pk-admin',
          joinedAt: DateTime.now().toUtc(),
        );
        final alice = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-alice',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-pk-alice',
          joinedAt: DateTime.now().toUtc(),
        );

        await groupRepo.saveMember(admin);
        await groupRepo.saveMember(alice);

        final bridge = FakeBridge(
          initialResponses: {
            'group:generateNextKey': {
              'ok': true,
              'groupKey': 'fake-rotated-key',
              'keyEpoch': 2,
            },
          },
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        final aliceRemoveButton = find.descendant(
          of: aliceRow,
          matching: find.byIcon(Icons.remove_circle_outline),
        );
        await tester.ensureVisible(aliceRemoveButton);
        await pumpFrames(tester, count: 5);
        await tester.tap(aliceRemoveButton, warnIfMissed: false);
        await pumpFrames(tester);
        await confirmRemoveMemberDialog(tester);

        // Verify the durable removal replay is encrypted before inbox store,
        // and that key rotation starts only after the replay is persisted.
        expect(bridge.commandLog, contains('group:updateConfig'));
        expect(bridge.commandLog, contains('payload.sign'));
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group.encrypt'));
        expect(bridge.commandLog, contains('group:inboxStore'));
        expect(bridge.commandLog, contains('group:updateKey'));
        expect(bridge.commandLog, contains('group:generateNextKey'));

        final updateConfigIndex = bridge.commandLog.indexOf(
          'group:updateConfig',
        );
        final signIndex = bridge.commandLog.indexOf('payload.sign');
        final publishIndex = bridge.commandLog.indexOf('group:publish');
        final encryptIndex = bridge.commandLog.indexOf('group.encrypt');
        final inboxStoreIndex = bridge.commandLog.indexOf('group:inboxStore');
        final currentKeyResyncIndex = bridge.commandLog.indexOf(
          'group:updateKey',
        );
        final generateNextKeyIndex = bridge.commandLog.indexOf(
          'group:generateNextKey',
        );

        expect(updateConfigIndex, lessThan(signIndex));
        expect(signIndex, lessThan(publishIndex));
        expect(publishIndex, lessThan(encryptIndex));
        expect(encryptIndex, lessThan(inboxStoreIndex));
        expect(inboxStoreIndex, lessThan(currentKeyResyncIndex));
        expect(currentKeyResyncIndex, lessThan(generateNextKeyIndex));
      },
    );

    testWidgets(
      'remove member distributes rotated key to remaining members via P2P',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        final admin = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          mlKemPublicKey: 'mlkem-pk-admin',
          joinedAt: DateTime.now().toUtc(),
        );
        final alice = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-alice',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-pk-alice',
          joinedAt: DateTime.now().toUtc(),
        );
        final bob = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          mlKemPublicKey: 'mlkem-pk-bob',
          joinedAt: DateTime.now().toUtc(),
        );

        await groupRepo.saveMember(admin);
        await groupRepo.saveMember(alice);
        await groupRepo.saveMember(bob);

        final bridge = PassthroughCryptoBridge();
        bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'fake-rotated-key',
          'keyEpoch': 2,
        };
        bridge.responses['group:publish'] = {'ok': true, 'messageId': 'msg-1'};
        final p2pService = FakeP2PService();

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: p2pService,
            ),
          ),
        );
        await pumpFrames(tester);

        // Remove Alice — Bob should remain and receive key distribution
        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        final aliceRemoveButton = find.descendant(
          of: aliceRow,
          matching: find.byIcon(Icons.remove_circle_outline),
        );
        await tester.ensureVisible(aliceRemoveButton);
        await pumpFrames(tester, count: 5);
        await tester.tap(aliceRemoveButton, warnIfMissed: false);
        await pumpFrames(tester);
        await confirmRemoveMemberDialog(tester);

        final keyUpdateMessages = p2pService.sentMessageLog.where((entry) {
          final envelope = jsonDecode(entry.content) as Map<String, dynamic>;
          return envelope['type'] == 'group_key_update';
        }).toList();
        final membershipUpdateMessages = p2pService.sentMessageLog.where((
          entry,
        ) {
          final envelope = jsonDecode(entry.content) as Map<String, dynamic>;
          return envelope['type'] == groupMembershipUpdateMessageType;
        }).toList();

        // Alice receives the direct removal notice; only Bob receives the key.
        expect(membershipUpdateMessages.length, 1);
        expect(membershipUpdateMessages.single.peerId, 'peer-alice');
        expect(keyUpdateMessages.length, 1);
        expect(keyUpdateMessages.single.peerId, 'peer-bob');

        // Verify Bob's message is a group_key_update v2 envelope.
        final envelope =
            jsonDecode(keyUpdateMessages.single.content)
                as Map<String, dynamic>;
        expect(envelope['type'], 'group_key_update');
        expect(envelope['version'], '2');
        expect(envelope['encrypted'], isNotNull);
      },
    );

    testWidgets(
      'EK004 remove member broadcast stores signed member_removed replay envelope',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        final admin = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          mlKemPublicKey: 'mlkem-pk-admin',
          joinedAt: DateTime.now().toUtc(),
        );
        final alice = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-alice',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-pk-alice',
          joinedAt: DateTime.now().toUtc(),
        );
        final bob = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          mlKemPublicKey: 'mlkem-pk-bob',
          joinedAt: DateTime.now().toUtc(),
        );

        await groupRepo.saveMember(admin);
        await groupRepo.saveMember(alice);
        await groupRepo.saveMember(bob);

        final bridge = FakeBridge(
          initialResponses: {
            'group:generateNextKey': {
              'ok': true,
              'groupKey': 'fake-rotated-key',
              'keyEpoch': 2,
            },
          },
        );

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        // Remove Alice
        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        final aliceRemoveButton = find.descendant(
          of: aliceRow,
          matching: find.byIcon(Icons.remove_circle_outline),
        );
        await tester.ensureVisible(aliceRemoveButton);
        await pumpFrames(tester, count: 5);
        await tester.tap(aliceRemoveButton, warnIfMissed: false);
        await pumpFrames(tester);
        await confirmRemoveMemberDialog(tester);

        // Find the group:publish command in sentMessages
        final publishMsg = bridge.sentMessages.firstWhere((m) {
          final parsed = jsonDecode(m) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;

        // Verify system message type and removed member info
        expect(sysText['__sys'], 'member_removed');
        expect(sysText['member']['peerId'], 'peer-alice');
        expect(sysText['member']['username'], 'Alice');
        expect(sysText['removedAt'], isA<String>());

        // Verify groupConfig.members excludes the removed member (Alice)
        final groupConfig = sysText['groupConfig'] as Map<String, dynamic>;
        final memberPeerIds = (groupConfig['members'] as List)
            .map((m) => (m as Map<String, dynamic>)['peerId'] as String)
            .toList();
        expect(memberPeerIds, contains('peer-admin'));
        expect(memberPeerIds, contains('peer-bob'));
        expect(memberPeerIds, isNot(contains('peer-alice')));

        final removedAt = DateTime.parse(sysText['removedAt'] as String);
        final timelineMessage = buildMemberRemovedTimelineMessage(
          groupId: 'group-1',
          removedPeerId: 'peer-alice',
          removedUsername: 'Alice',
          senderId: 'peer-admin',
          senderUsername: 'Admin',
          eventAt: removedAt,
        );

        final inboxStoreMsg = bridge.sentMessages.firstWhere((m) {
          final parsed = jsonDecode(m) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:inboxStore';
        });
        final inboxStorePayload =
            (jsonDecode(inboxStoreMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(inboxStorePayload['recipientPeerIds'], [
          'peer-alice',
          'peer-bob',
        ]);

        final replayEnvelope = _storedGroupReplayEnvelope(
          inboxStorePayload['message'] as String,
        );
        expect(replayEnvelope['recipientPeerIds'], ['peer-alice', 'peer-bob']);
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['payloadType'], 'group_message');
        expect(replayEnvelope['keyEpoch'], 1);
        expect(replayEnvelope['messageId'], isNull);
        expect(replayEnvelope['senderPeerId'], testIdentity.peerId);
        expect(replayEnvelope['senderPublicKey'], testIdentity.publicKey);
        expect(replayEnvelope['signatureAlgorithm'], 'ed25519');
        expect(replayEnvelope['signedPayload'], isA<String>());
        expect(replayEnvelope['signature'], isA<String>());

        final inboxEnvelope = _decodedGroupReplayPayload(
          inboxStorePayload['message'] as String,
        );
        expect(inboxEnvelope['groupId'], 'group-1');
        expect(inboxEnvelope['senderId'], 'peer-admin');
        expect(inboxEnvelope['senderUsername'], 'Admin');
        expect(inboxEnvelope['text'], publishPayload['text']);
        expect(inboxEnvelope['timestamp'], sysText['removedAt']);

        final persistedTimeline = await msgRepo.getMessage(timelineMessage.id);
        expect(persistedTimeline, isNotNull);
        expect(
          persistedTimeline!.text,
          buildMemberRemovedTimelineText('Admin', 'Alice'),
        );
        expect(
          persistedTimeline.timestamp.toUtc().toIso8601String(),
          removedAt.toUtc().toIso8601String(),
        );
      },
    );

    testWidgets(
      'stale non-member removal shows error and emits no removal side effects',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-alice', username: 'Alice'),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-bob', username: 'Bob'),
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          _localizedMaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        final aliceRemoveButton = find.descendant(
          of: aliceRow,
          matching: find.byIcon(Icons.remove_circle_outline),
        );

        await groupRepo.removeMember('group-1', 'peer-alice');

        await tester.ensureVisible(aliceRemoveButton);
        await pumpFrames(tester, count: 5);
        await tester.tap(aliceRemoveButton, warnIfMissed: false);
        await pumpFrames(tester);
        await confirmRemoveMemberDialog(tester);

        expect(find.text('Member not found'), findsOneWidget);
        expect(find.text('Alice'), findsNothing);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:publish'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:inboxStore'),
          isEmpty,
        );

        final members = await groupRepo.getMembers('group-1');
        expect(members.map((member) => member.peerId).toSet(), {
          'peer-admin',
          'peer-bob',
        });
      },
    );

    testWidgets('canceling remove member keeps membership unchanged', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );
      await groupRepo.saveMember(
        makeMember(peerId: 'peer-alice', username: 'Alice'),
      );

      final bridge = FakeBridge();

      await tester.pumpWidget(
        _localizedMaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: bridge,
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      final aliceRow = find.ancestor(
        of: find.text('Alice'),
        matching: find.byType(Row),
      );
      final aliceRemoveButton = find.descendant(
        of: aliceRow,
        matching: find.byIcon(Icons.remove_circle_outline),
      );

      await tester.ensureVisible(aliceRemoveButton);
      await pumpFrames(tester, count: 5);
      await tester.tap(aliceRemoveButton, warnIfMissed: false);
      await pumpFrames(tester);

      expect(find.text('Remove Alice from the group?'), findsOneWidget);
      expect(
        find.text('They will stop receiving new messages from this group.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('group-remove-cancel')));
      await pumpFrames(tester, count: 20);

      expect(find.text('Alice'), findsOneWidget);
      expect(bridge.commandLog, isEmpty);
    });
  });
}
