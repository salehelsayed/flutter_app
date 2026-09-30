"""Group multi-device/multi-party harness: wire GroupRepositoryImpl like production (removed-shell authority +
membership watermark), copied verbatim from production_application_bootstrap.dart. Without them product code fails
closed ("Removed-shell persistence capability is unavailable") on every remove/re-add/accept scenario.
Both checkouts; exact-match guards; refreshes legacy source hash pins for the harness file if present."""
import hashlib, pathlib, re

HARNESS = 'integration_test/group_multi_device_real_harness.dart'
PROD = 'lib/app/bootstrap/production_application_bootstrap.dart'
IMPORT_ANCHOR = "import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';\n"
NEW_IMPORT = "import 'package:flutter_app/core/database/helpers/self_removed_group_shell_db_helpers.dart';\n"
DELETE_ANCHOR = "  final groupRepo = GroupRepositoryImpl(\n    dbInsertGroup: (row) => dbInsertGroup(db, row),\n"
WATERMARK = """    dbAdvanceGroupMembershipWatermark:
        ({required groupId, required eventAt, required eventId}) =>
            dbAdvanceGroupMembershipWatermark(
              db,
              groupId: groupId,
              eventAt: eventAt,
              eventId: eventId,
            ),
"""
END_ANCHOR = """    dbHasGroupExitCleanupPending: (groupId) async {
      final row = await dbLoadGroupExitIntentForGroup(db, groupId);
      return row?['state'] == 'cleanup_pending';
    },
  );
  final groupMediaKeyAccess = GroupMediaKeyAccess(
"""

def production_block(root):
    lines = pathlib.Path(root, PROD).read_text().split('\n')
    start = next(i for i, l in enumerate(lines) if l.strip() == 'selfRemovedShellAuthorityEnabled: true,')
    purge = next(i for i in range(start, len(lines)) if 'dbPurgeSelfRemovedGroupShellFn:' in lines[i])
    end = next(i for i in range(purge, len(lines)) if lines[i].strip() == '),')
    assert lines[end + 1].strip() == ');', lines[end + 1]
    block = lines[start:end + 1]
    assert all(l.startswith('      ') or not l.strip() for l in block)
    return '\n'.join(l[2:] if l.strip() else l for l in block) + '\n'

import sys as _sys
ROOTS = _sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']
for root in ROOTS:
    p = pathlib.Path(root, HARNESS); s = p.read_text()
    if 'selfRemovedShellAuthorityEnabled: true' in s:
        print('already', root); continue
    old_hash = hashlib.sha256(p.read_bytes()).hexdigest()
    assert s.count(IMPORT_ANCHOR) == 1 and s.count(DELETE_ANCHOR) == 1 and s.count(END_ANCHOR) == 1, root
    assert 'dbAdvanceGroupMembershipWatermark' not in s[s.index(DELETE_ANCHOR):s.index(END_ANCHOR)]
    s = s.replace(IMPORT_ANCHOR, IMPORT_ANCHOR + NEW_IMPORT)
    s = s.replace(DELETE_ANCHOR, DELETE_ANCHOR + WATERMARK)
    block = production_block(root)
    s = s.replace(END_ANCHOR, END_ANCHOR.replace("    },\n  );\n", "    },\n" + block + "  );\n", 1))
    p.write_text(s)
    new_hash = hashlib.sha256(p.read_bytes()).hexdigest()
    c = pathlib.Path(root, 'tool/testing/legacy_target_contracts.json'); ct = c.read_text()
    n = ct.count(old_hash); c.write_text(ct.replace(old_hash, new_hash))
    print('patched', root, 'block lines', block.count('\n'), 'hash pins replaced', n)
