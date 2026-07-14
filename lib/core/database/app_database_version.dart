// 232: DB v97 adds the direct-message forwarded marker after the v96 media
// library state.
// 235: DB v98 adds the local-only group_media_deletion_journal — the explicit
// per-attachment cleanup authority for group received-media Delete-for-me
// (no wire mapping, no cascade, empty legacy backfill).
// 236: DB v99 adds the group-message forwarded marker
// (group_messages.is_forwarded, default-false, 0/1 CHECK) after the v98
// deletion journal.
// 234: DB v100 adds the direct parent private-media policy/lifecycle seed and
// expiry index. Plan 238 reserves v101 and must follow this migration.
// 238: DB v101 adds the discussion-group message private-media policy/local
// lifecycle seed and expiry index. DB v100 remains exclusively Plan 234.
// v96+ remains a one-way supported release floor and builds
// fail closed on downgrade opens
// (encrypted_db_opener.dart passes onDatabaseVersionChangeError), and no
// pre-v96 build may be installed over a profile already opened at v96.
const int currentIdentityDatabaseVersion = 101;
