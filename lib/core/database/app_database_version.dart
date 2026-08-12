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
// 263: DB v102 adds durable `groups.self_removed_at` authority for retained
// self-removed shells and terminalizes legacy membership-instance work.
// 264: DB v103 adds the exact-membership, revisioned `group_exit_intents`
// state machine. Its legacy backfill is deliberately empty.
// 266: DB v104 adds the bounded, opaque `group_exit_diagnostics` history.
// Its legacy backfill is deliberately empty.
// 330: DB v106 adds identifier-only durable group-notification display
// custody. It intentionally has no foreign keys because the marker precedes
// canonical message/reaction persistence.
// 331: DB v107 adds identifier-only direct-notification display/read/
// reconciliation custody. Direct reaction terminal facts are peer-scoped in a
// separate typed table because the shared reaction table has no lane key.
// 342: DB v108 adds the sender-owned, status-independent exact-envelope
// custody outbox for newly authored ordinary direct text. The migration has
// deliberately empty historical backfill and remains a one-way schema floor.
// 343: DB v109 adds event-scoped exact-envelope custody for newly authored
// direct reaction ADD/REMOVE transitions. Historical reactions are not
// backfilled and v109 remains a one-way schema floor.
// 345: DB v110 adds a nullable, manifest-bound local custody intent for newly
// prepared ordinary direct media. Historical messages are not backfilled,
// and v110 remains a one-way schema floor.
// 347: DB v111 adds independent exact-blob custody plus nullable manifest hash
// and earliest-expiry bindings on v108. Historical rows are not promoted, and
// v111 remains a one-way schema floor.
// 360: DB v112 adds the authenticated remote-contact linked-device roster
// (`direct_contact_device_bindings` + per-contact roster metadata). Legacy
// canonical contact targets are deliberately NOT materialized as bindings, so
// the historical backfill is empty and pre-initialization resolution is the
// unchanged ContactModel peer/ML-KEM. v112 remains a one-way schema floor; the
// installation's own linked role/transport credential are device-local secure
// records and are absent from this schema and from every migration bundle.
// 361: DB v113 adds the blob-free direct-event fanout facts: the per-message
// current generation marker plus the logical-contact/parent columns on the
// v108/v109 outboxes, with generation-first lookup indexes. All four columns
// are nullable and historical rows are never promoted; v113 remains a one-way
// schema floor.
// 362: DB v114 rebuilds only direct_media_blob_custody: attachment_id loses
// its PRIMARY KEY, the natural exact identity becomes (attachment_id,
// direction, recipient_peer_id) under two partial unique indexes, and the
// nullable linked columns contact_account_peer_id /
// recipient_ml_kem_public_key are added (historical rows keep both NULL).
// media_attachments gains the nullable
// direct_media_blob_custody_fingerprint_version discriminator (NULL = exact
// target-specific digest; 2 = sender-local target-independent generation
// digest). Historical rows are never promoted; v114 remains a one-way schema
// floor.
const int currentIdentityDatabaseVersion = 114;
