// 232: DB v97 adds the direct-message forwarded marker after the v96 media
// library state.
// 235: DB v98 adds the local-only group_media_deletion_journal — the explicit
// per-attachment cleanup authority for group received-media Delete-for-me
// (no wire mapping, no cascade, empty legacy backfill).
// v96+ remains a one-way supported release floor and builds
// fail closed on downgrade opens
// (encrypted_db_opener.dart passes onDatabaseVersionChangeError), and no
// pre-v96 build may be installed over a profile already opened at v96.
const int currentIdentityDatabaseVersion = 98;
