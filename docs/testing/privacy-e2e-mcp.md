# Privacy: reuse native campaigns and add the missing MCP observations

Execution owner: `flutter_app`. Astra prepares only; no device leg is claimed
here. Use currently available pinned targets and existing setup/build caches,
leases and state guards. Shared behavior defaults to Android physical + Android
emulator; the group campaigns need a second available Android emulator. An
unavailable target is N/A, not a reason to create hardware or stop another run.
No iPhone is needed for these non-parity claims.

Use actual Appium MCP tools for UI, permissions, lifecycle and native shade
observations. Keep synthetic content and exact identities private. Use only
owned disposable accounts/circles and app instances; a Thought sender's audience
must contain only the intended test recipients. Preserve the owner's real
contacts, history, photo library and unrelated notifications. Record exact
source/artifact/configuration and first failures for every leg. A source-built
instrumented campaign does not certify an untested signed store artifact.

## Coverage and execution choices

| Item | Existing coverage to reuse | Additional observation |
| --- | --- | --- |
| GC-004 | online-remove, offline-readd and removed-reaction production campaigns | MCP excluded-content notification preview, with eligible controls |
| DC-013 | existing contact-delete UI, SQL rollback, unrelated history and restart oracle | no duplicate runner |
| DC-016 | `block_unblock_ingress_privacy_test.dart` causal ingress/deletion/alert controls | real MCP block/send/reopen/unblock UI and native alerts |
| TH-001 | real-SQL follow-on/retraction tests for unacknowledged send, restart, atomic enqueue and retirement | MCP connected and offline-recipient Thought deletion |

Keep host/native/MCP scopes in separate receipt columns. Do not fill a missing
device observation with a host test result. Existing native campaign validators
remain authoritative for their typed protocol observations; the new MCP legs
are recorded observations, not another device harness or independent media oracle.

## GC-004 — history/epoch boundary and notification privacy

Planning estimate: 10–20 minutes per existing native campaign plus 10–15 minutes
for the MCP preview leg; each registered native timeout is 2,400 seconds.
Use three available owned Android peers: A/B remain entitled, C is removed.

Reuse these registered checks through their existing executor/setup:

- `production-group-online-remove`:
  `integration_test/scripts/run_production_group_online_remove.dart` and
  `production_group_online_remove_criteria.dart`. This includes the held key
  distribution/media ACL and rejected removed-member publish controls.
- `production-group-offline-readd`:
  `integration_test/scripts/run_production_group_offline_readd.dart` and
  `production_group_offline_readd_criteria.dart`. Retain verified owned process
  death, old/current epochs and exact removed-window/post-readd receipts.
- `production-group-removed-reaction`:
  `integration_test/scripts/run_production_group_removed_reaction.dart` and
  `production_group_removed_reaction_criteria.dart`. It makes an actual rejected
  stale-member attempt and checks SQL reactions, including the original
  five-second absence window. A disabled reaction button is not this protocol proof.

The three inspected oracles have no notification-preview assertion. For that
additional MCP leg, use a separate owned group with the same candidate/config:

1. Establish the actual roster and C's authorized pre-removal content. Enable
   the intended native notification permission/channel, recording its previous
   state. Put C on a background/non-conversation surface and send an eligible
   control. Prove notification delivery actually works and capture its preview.
2. Remove C online; wait for the real membership state before publishing unique
   removed-window text and media. A/B receive/open the content, while C gets
   neither a readable row/full media nor an OS preview disclosing its marker.
   Observe the native shade and existing read-only data for at least 30 seconds,
   then cold-reopen C and check again. Do not clear the whole notification shade.
3. Repeat with C offline before removal; record the actual catch-up/re-add
   boundary through ordinary UI. After explicit re-add/acceptance and current
   authority, fresh entitled content works, including an eligible notification
   control. Removed-window markers stay inaccessible and never appear in a
   notification preview after replay/reopen. Pre-removal authorized history is
   judged by the existing oracle/product policy, not an invented total-wipe rule.
4. Restore only owned permission/channel/UI state. Record source-built native
   results separately from this MCP notification result; do not merge unrelated
   group/run identities into one purported protocol trace.

## DC-013 — existing contact deletion, unrelated chat preserved

Covered by `integration_test/scripts/run_production_contact_delete.dart`,
manifest capability `kx0010` (conversation deletion) or `kx0011` (Orbit deletion).
Planning estimate: 5–10 minutes; one available owned Android emulator suffices.
In the existing executor's prepared SIMS environment, the underlying command is:

```sh
dart run integration_test/scripts/run_production_contact_delete.dart --scenario kx0010
```

Use the registered profile, pinned target, proof directory and real artifact
digests supplied by that executor, rather than fabricating environment values.
`production_contact_delete_criteria.dart:36–49,88–137` requires two independent
histories, actual UI receipts, exact rollback/retry and verified process death;
the deleted contact's history is gone after restart and the other history is
byte-for-byte preserved. Reuse the real-SQL/media contact-deletion host controls
for their storage boundary. Do not perform this fixture on an owner's real chat.

## DC-016 — block/unblock and authorized old-message deletion

Planning estimate: 10–15 minutes on two available owned Android peers.

1. Establish real trusted A/B. Deliver an old B-authored message and an A-authored
   reaction target to both sides. Prove eligible delivery/notification controls,
   then block B through A's supported UI. Capture persisted blocked state.
2. B sends unique text, image/media and a reaction to A's existing target. Retain
   actual send/custody observations. For 30 seconds, A gains no incoming text,
   media, reaction or alert for these markers. Put A on a non-conversation surface
   for native shade checks so an active-chat suppression rule cannot explain it.
3. B deletes **its own previously stored message** through the supported
   delete-for-everyone action. Apply the authorized deletion according to current
   policy even while blocked; it must not authorize new content, reactions or
   ownership of A's messages. Existing host controls cover forged ownership.
4. Restart A without clearing data: block/privacy state holds and excluded
   content stays absent. Unblock B through UI and send a distinct fresh marker;
   ordinary authorized delivery resumes without a second scan or duplicate rows.
   Previously blocked-window content must not be mistaken for this fresh control.
5. Recheck unchanged permission/channel state and an eligible after-control.
   An available third owned peer can supply a concurrent allowed control; it is
   optional hardware, not a closure requirement. Restore only owned state.

Reuse `test/features/conversation/integration/block_unblock_ingress_privacy_test.dart`
and its exact privacy/deletion/reaction/notification assertions. Its host causal
proof is separate from native MCP observation. No app bug or patch is inferred
from a missing notification until the positive controls are established.

## TH-001 — Thought deletion for every actual recipient

Planning estimate: 10–15 minutes, using two or more available owned Android
peers. Prefer two recipients when available; record the actual audience. The
sender must use an isolated test circle, never the owner's unrelated friends.

1. Publish one fresh owned Thought and wait until **every intended recipient**
   has actually opened/seen that exact item. Record its identity, audience and
   creation/expiry. Lifetime is 24 hours (`ThoughtLifetime.duration`); keep the
   case comfortably before expiry, without clock changes. Preserve an unrelated
   owned creator's control; publishing a replacement is not a deletion action.
2. With recipients connected, delete that Thought through the real author UI.
   Each recipient loses the exact item once; reopen without data clear and it
   does not reappear. UI absence alone is not an internal callback-count proof.
3. Repeat with a fresh Thought already visible to all recipients, then take one
   recipient offline **before deletion**. Delete on the author, retain actual
   relay/retry ownership, and restart the author without clearing data. Restore
   the recipient: automatic foreground/inbox catch-up removes the same item
   without a second author action. Other owned content remains unchanged.
4. Retain the exact available read-only follow-on outcome/row observations.
   While delivery is unresolved, ownership must survive local Thought deletion
   and restart. Once all recipients are delivered or accepted into durable relay
   custody, the event and recipient rows retire. Zero local rows before the
   recipient returns is valid if custody already transferred. If this build has
   no existing scoped row observation, leave native row-retirement proof incomplete.

Precise `sent=true, acknowledged=false` fallback and atomic publication/retirement
are already exercised by `post_follow_on_delivery_test.dart`,
`post_follow_on_outbox_repository_test.dart` and `retract_thought_use_case_test.dart`.
Those three tests and their three inspected delivery/database components are
byte-identical to approved `1c8153b45df834cd9ac9c753cc1ac883c6b81bb5` at the
7354 preparation base. The MCP offline leg does not claim that the same exact
unacknowledged-live fault was injected. Reuse the causal host controls for that
assertion; add no production fault seam. Actual Thought retraction code queues
before local deletion and has the acknowledged-send/atomic-retirement fixes.

Report per leg: existing runner/host coverage, MCP observation ready or executed,
first failure/setup blocker/N/A, and exact candidate/configuration. No source or
host-only PASS substitutes for fresh native alert/recipient observations.
