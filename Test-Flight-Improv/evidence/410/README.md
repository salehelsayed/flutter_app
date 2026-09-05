# Plan 410 evidence — unread badge for missed calls (2026-09-06)

Messages carried read state; calls did not, so the unread badge could only ever
describe half a conversation.

| File | What it proves |
|---|---|
| `dart_call_unread_green_2026-09-06.txt` | GREEN: 4921 passing, 10 skipped, 0 failing across database, call, orbit, conversation, bootstrap and unit |

## The decisions

**What counts.** An INCOMING call the user never took: `missed`, `cancelled`
(the caller hung up first, which is a missed call from the callee's side) or
`busy`. Not `completed`, `declined` or `failed`, and nothing outgoing — those
are things the user already knows about, and counting them would make the badge
mean "something happened" instead of "something is waiting for you". The rule
lives in ONE place, `kUnreadCallHistoryPredicate`, and `markCallHistoryRead` is
scoped by the same predicate so the column can only ever have one meaning.

**When it clears.** At the same seam that marks messages read, so opening a
conversation clears the whole badge rather than half of it.

**One badge, not two.** The count folds into the existing `unreadCount`:
2 unread messages plus 3 missed calls reads 5. Splitting them would ask the
user to do arithmetic.

**Storage.** Migration 118 adds nullable `call_history.read_at` with no default
and no backfill, so every existing row starts UNREAD — the truthful state for a
call the user has not seen. A trigger guards the timestamp because SQLite
cannot add a CHECK through ALTER.

## The bug the existing suite caught

The registry was updated to 118 while `currentIdentityDatabaseVersion` still
said 117. On a real install the migration would never have run and every unread
query would have hit a column that does not exist. My own new tests all passed,
because they call the migration directly rather than through the version-driven
upgrade path — only the pre-existing migration suite could see it.

## Re-pins this migration required

Every DB bump in this repo re-pins a set of literals; recording the full list so
the next one is cheaper:

- `currentIdentityDatabaseVersion` and every `expect(..., 117)` latest pin
- `registry.last.name` → `118_call_history_read_state`
- offsets from the end (`length - N`), incremented to keep pinning the same
  migration — the repo's convention, stated in `108_..._test.dart`: "The
  assertion itself is unchanged; only its position moved." I first shifted the
  expected VERSIONS instead, and the literal-inventory census caught it.
- `PRAGMA user_version` reads written the long way
- `117_call_history_test.dart`'s exact column census (now includes `read_at`)
  and its "is last" claim, now second-from-last
- the `107` literal-inventory census, whose frozen line text moved
- DTR-18 normalized digests for `application_root.dart` and
  `production_application_bootstrap.dart`, re-pinned with a rationale, never
  weakened
