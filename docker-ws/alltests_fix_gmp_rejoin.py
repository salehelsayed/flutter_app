"""Group harness fixture rejoin: a removed member keeps a self-removed shell, which production only re-admits after
invite re-entry or after the user deletes the removed group. Model the user-delete-then-rejoin path by running the
production DeleteSelfRemovedGroupShellUseCase before re-importing a joined-group fixture (post-commit media file
reconciliation and avatar-file deletion are no-ops in the discarded fixture sandbox). [roots...]"""
import hashlib, pathlib, sys
rel = 'integration_test/group_multi_device_real_harness.dart'
IMPORT_ANCHOR = "import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';\n"
NEW_IMPORTS = ("import 'package:flutter_app/features/groups/application/delete_self_removed_group_shell_use_case.dart';\n")
HELPER_IMPORT_ANCHOR = "import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';\n"
HELPER_IMPORT = "import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';\n"
CALL_OLD = """  await stack.groupRepo.saveGroup(importedGroup);
  for (final member in members) {
    await stack.groupRepo.saveMember(member);
  }
  await stack.groupRepo.saveKey(key);
"""
CALL_NEW = """  await _deleteSelfRemovedShellBeforeRejoin(stack, group.id);
  await stack.groupRepo.saveGroup(importedGroup);
  for (final member in members) {
    await stack.groupRepo.saveMember(member);
  }
  await stack.groupRepo.saveKey(key);
"""
FUNC_ANCHOR = "Future<String> importJoinedGroupFixture({\n"
FUNC = """/// A removed member keeps a self-removed shell. Production re-admits it only
/// through invite re-entry or after the user deletes the removed group; a
/// fixture rejoin models the latter with the production delete use case.
Future<void> _deleteSelfRemovedShellBeforeRejoin(
  GroupMultiDeviceTestStack stack,
  String groupId,
) async {
  final existing = await dbLoadGroup(stack.db, groupId);
  if (existing == null || existing['self_removed_at'] == null) return;
  var sequence = 0;
  final result = await DeleteSelfRemovedGroupShellUseCase(
    repository: stack.groupRepo,
    prepareMedia:
        ({
          required String groupId,
          required String messageId,
          required String operationId,
        }) => dbPrepareGroupMediaDeleteForMe(
          stack.db,
          groupId: groupId,
          messageId: messageId,
          operationId: operationId,
        ),
    // Post-commit media file cleanup only; the fixture sandbox is discarded.
    runMediaReconciler: () async {},
    operationIdFactory: () =>
        'fixture-self-removed-shell:'
        '${DateTime.now().toUtc().microsecondsSinceEpoch}:${++sequence}',
    snapshotAvatarPath: (_) async => null,
    deleteAvatar: (_) async {},
  ).call(groupId: groupId, selfPeerId: stack.identity.peerId);
  if (result != DeleteSelfRemovedGroupShellResult.deleted) {
    throw StateError(
      'Fixture rejoin could not delete the self-removed shell: $result',
    );
  }
}

"""
roots = sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']
for root in roots:
    p = pathlib.Path(root, rel); s = p.read_text()
    if '_deleteSelfRemovedShellBeforeRejoin' in s:
        print('already', root); continue
    for anchor in (IMPORT_ANCHOR, HELPER_IMPORT_ANCHOR, CALL_OLD, FUNC_ANCHOR):
        assert s.count(anchor) == 1, (root, anchor[:50])
    old_hash = hashlib.sha256(p.read_bytes()).hexdigest()
    if NEW_IMPORTS not in s: s = s.replace(IMPORT_ANCHOR, IMPORT_ANCHOR + NEW_IMPORTS)
    if HELPER_IMPORT not in s: s = s.replace(HELPER_IMPORT_ANCHOR, HELPER_IMPORT_ANCHOR + HELPER_IMPORT)
    s = s.replace(CALL_OLD, CALL_NEW).replace(FUNC_ANCHOR, FUNC + FUNC_ANCHOR)
    p.write_text(s)
    c = pathlib.Path(root, 'tool/testing/legacy_target_contracts.json'); ct = c.read_text()
    n = ct.count(old_hash); c.write_text(ct.replace(old_hash, hashlib.sha256(p.read_bytes()).hexdigest()))
    print('patched', root, 'hash pins', n)
