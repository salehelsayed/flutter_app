// 228: DB v96 (media library owner-lane + local viewer state) is a one-way
// supported release floor — v96+ builds fail closed on downgrade opens
// (encrypted_db_opener.dart passes onDatabaseVersionChangeError), and no
// pre-v96 build may be installed over a profile already opened at v96.
const int currentIdentityDatabaseVersion = 96;
