# Group A: messaging reliability execution

Execution owner: `flutter_app`. Astra prepared these instructions from source;
no new device result is claimed. Use actual Appium MCP tools and the existing
setup checks, candidate/build caches and device leases. Pin available targets,
source, artifact and feature/relay configuration. Default shared behavior uses
one USB Android and an available Android emulator; the full linked/group legs
use a third owned instance when available. Missing hardware is N/A by project
policy; a missing artifact, feature fixture or observation is a separate blocker.

Owner relay rule, clarified 2026-10-26: remote test traffic explicitly uses the
Hetzner test relay; owned disposable local relay/coturn fixtures are also allowed.
AWS is reserved for the owner's pre-publish store-build lanes; this
preparation grants no AWS exception. The coordinator reports both services at
v1.11.2; Astra has not inspected either deployment. No deployment, configuration
or service changes on either relay. If an existing campaign/artifact cannot be
bound to Hetzner or its intended local fixture, stop that leg and report it;
never use its production/default fallback. Fault only an owned emulator or
local fixture. Existing hermetic host fixtures stay local and do not contact AWS. Keep identities,
addresses, synthetic content and raw evidence private; mail paths/redacted facts.

| Item | Existing coverage | Additional execution |
| --- | --- | --- |
| DC-007 | sender-offline native oracle; UI/status, receipt and strict-media SQL host controls | MCP in-flight/failure/recovery glyphs; terminal manual Retry only on its actual branch |
| DC-020 | linked addressing/event/blob runner and real-SQL fanout controls | actual eligible installation convergence, mutations, offline replay and rollback |
| DC-017 | owned Go inbox-service withdrawal plus real-SQL retry/replay | emulator-scoped relay unavailability with healthy client networking |
| RG-003 | real relay handler retention/pages/expiry and app key/backlog controls | bounded available-device catch-up; no mandatory days of idling |
| RG-004 | real receiving listener queue/SQL and authenticated relay rejection sequence | reuse these causal host boundaries; no new push or packet injector |

Use existing typed campaign validators for their observations. New MCP facts
remain manual recorded observations; no new boolean-only verdict adapter is
needed. Do not put these case IDs into the earlier Python checker as aliases
for a different journey. Report host, instrumented native and signed-candidate
UI scopes separately, retaining first failures and original deadlines.

## DC-007 — truthful in-flight, failure and retry UI

Planning estimate: 10–15 minutes for the MCP status leg, excluding existing
campaigns. Reuse `production-catalog-direct-sender-offline` /
`run_production_direct_sender_offline.dart` for its actual node-stop, persisted
failed row, visible automatic pending state, supported recovery, exact identity,
transport label and both process restarts. Its registered timeout is 7,200
seconds. That runner requires its original disposable Android-emulator pair;
do not substitute a physical peer for that guard. It is partial DC-007 evidence,
not OS-airplane-mode or an envelope-less
terminal manual-Retry proof (`TESTING.md:2453–2469`).

1. Establish owned A/B and an eligible delivered control. Record the real
   outgoing row identity and transport. Send through the composer during an
   existing scoped delay/failure condition, observing the first UI state before
   it settles. Capture the actual semantic status and matching available
   read-only custody/receipt observations; a fast successful send that skipped
   the observation does not prove in-flight UI.
2. Preserve current product semantics: one tick can mean `sending`/`pending`;
   the double-check delivered ladder is retired. Reached direct messages show
   their actual transport; `inboxed/inbox` and `delivered/inbox` keep the same
   inbox glyph. Compare the accessible label and persisted state, not a new
   interpretation of a tick (`letter_card.dart:1162–1189,1223–1283`). Before the
   relevant transport ACK, custody or delivery receipt exists, UI must not claim
   that reached state; transport success is not a receiver-read confirmation.
3. Observe the actual failure/retry policy. An automatically recoverable queued
   item must not be treated as terminal or get an invented manual Retry step.
   For strict media, existing hermetic fixture/SQL coverage uses
   `upload_storage_block`/`upload_storage_restore` only on its owned filesystem
   root and proves same-generation/ciphertext recovery and receipt settlement
   (`TESTING.md:2478–2505`). The corresponding existing owned local fixture may
   support a separate instrumented native leg; never apply storage faults to
   Hetzner/AWS or call local-fixture evidence a remote signed-candidate pass.
4. Restore only the owned fault. Automatic recovery must use the original
   logical message/attachment, deliver once and leave no stale in-flight UI
   after the existing retry/receipt convergence deadline. Reopen both apps:
   text/order, status and actual supported transport remain consistent. Record
   elapsed time and the existing deadline; do not extend it to obtain a pass.
5. Separately exercise a **real envelope-less terminal failed-message** Retry
   affordance if the existing owned setup can produce one. Capture failure,
   one explicit Retry, recovery and no duplicate row. Do not manufacture it by
   editing SQL or interpret an automatic media retry as this branch. If no
   existing setup can produce/observe it, keep this native subleg incomplete
   and reuse its host controls; report the precise missing precondition.

Host anchors: `conversation_wired_sending_to_failed_test.dart`,
`letter_card_test.dart`, `retry_failed_messages_delivered_truthfulness_test.dart`,
`delivered_status_minting_sites_test.dart`, `handle_delivery_receipt_use_case_test.dart`,
`delivery_receipt_roundtrip_test.dart` and
`direct_media_storage_retry_sqlite_test.dart`. Their fake transport/crypto or
widget time does not establish actual network timing on a signed candidate.

## DC-020 — authorized linked direct installations

Planning estimate: 15–25 minutes for the manual convergence leg, excluding setup.
This is conditional P0 when the feature is enabled **or supported persisted
linked state exists**. Default-off authoring is not permission to ignore an
already initialized roster or committed work.

Reuse `integration_test/scripts/run_invite_reliability_multi_device.dart` with
scenario `direct_linked_device_event_blob_fanout` and the executor's explicit
physical-Android-first/emulator-second `-d` pair. Its existing 12-minute role
readiness bound remains unchanged. The scenario supplies the four narrowly
scoped direct selectors, not `MKNOON_ENABLE_MULTI_DEVICE_SYNC`
(`run_invite_reliability_multi_device.dart:102–117`). Preserve its actual profile
and disposable guards; do not substitute the group B1b campaign.
Set `MKNOON_RELAY_ADDRESSES` explicitly to the executor's verified Hetzner test
profile or intended disposable local fixture: this runner otherwise defaults
to production (:19,52). Confirm every
role's artifact actually contains the override before launch; otherwise stop.

That runner proves linked-origin identity mapping, one blob-free event, one
image, actual emulator receive/download/ACK and exact offline target custody.
The offline sibling is an inert identity that never starts
(`invite_reliability_runner_contract.dart:28–36`); this is not full convergence
on two active installations, edit/delete/reaction replay or a native flag rollback.

1. Prepare owned sender A and account B's primary/linked installation B1/B2.
   Use existing authenticated direct-linked admission and initialized roster
   observations. Record logical account versus physical transport roles. If
   the approved build/setup cannot admit the required real installations,
   record that blocker rather than seeding fake authority through SQL or
   counting the inert offline fixture as a running installation.
2. Record actual build selectors: direct-linked admission and blob-free event
   fanout must be enabled for new text/edit/delete/reaction fanout. Media has a
   separate selector and is not required to prove this blob-free case. Preserve
   group same-user flags. A disabled feature with no persisted linked state is
   outside this conditional journey; label that reason separately from hardware.
3. A sends a text; B1/B2 converge on the same logical conversation and event
   identity without duplicate logical rows. Exercise authorized text edit,
   reaction add/remove and delete-for-everyone through actual UI. Repeat with
   one eligible installation offline, then restore/reopen it: ordered retained
   mutations converge once and the deletion tombstone does not resurrect text.
   Include a reply from the admitted linked installation to check physical
   transport maps to its logical author, not a new unrelated contact/thread.
4. For rollback, first observe an actually committed per-target batch with an
   unresolved target. Only use an already approved paired selector-off build
   with the same data-preserving installation/configuration; no live production
   flag change. Reopen and restore that target: committed work still drains,
   receiving remains valid and durable identity is preserved. New initialized
   fanout must follow the selector-off refusal policy, not silently send to one
   legacy target. Restore the original owned build/configuration afterward.
5. Native rollback is incomplete if the paired artifact, admission or existing
   scoped per-target row observation is unavailable. UI equality alone does
   not prove committed-work survival. Reuse the host fanout/drain controls and
   keep their exact scope separate. Do not erase linked credentials to simulate
   rollback or require unavailable extra hardware.

Source contracts: `direct_linked_devices_flag.dart:14–23` and
`direct_linked_event_fanout_flag.dart:16–30`. Host anchors include migration 113,
`direct_linked_device_addressing_foundation_test.dart:1044–1310`, the send/edit/
delete/reaction use-case tests, `drain_direct_inbox_custody_outbox_use_case_test.dart`
and `pending_message_retrier_direct_inbox_custody_test.dart`.

## DC-017 — relay outage without changing production services

Planning estimate: 10–15 minutes, excluding topology/setup. Use a rooted owned
Android emulator as the fault subject and an available owned peer. Keep client
networking and the production node started; airplane mode, recipient offline
or a stopped client node do not isolate this fault.

1. Prove a healthy control and the actual text route/custody dependency. Save
   the emulator package UID, all configured Hetzner relay endpoints/address families
   and original owned rule state privately. Existing direct peer connectivity
   can bypass a relay outage: prove this attempt requires the affected relay.
   A successfully delivered direct message is not an outage failure/retry case.
2. Through the executor's existing emulator fault control, create only a
   run-owned OUTPUT chain/jump scoped to this app UID and those relay endpoints,
   covering their actual IPv4/IPv6 transports. No global flush, host firewall
   change, unrelated peer block, relay administration or service command. Retain
   rule installation/hit counters and an independent healthy-network control.
   Network rules are a narrow protocol fault; all app UI still uses Appium MCP.
3. Send unique ordered texts during the fault. Prove attempted relay access
   actually failed, no custody ACK or recipient delivery occurred through an
   alternate route, and original sender rows survive. UI stays truthful under
   DC-007's current semantics. Preserve a pre-outage message/control.
4. Remove only this run's exact jump/rules/chain. Leave networking otherwise
   unchanged. Automatic retry delivers the original IDs once, in order; replay
   and both app restarts preserve them. Send a fresh after-control. Record rule
   absence, original configuration and exact cleanup even after a failed attempt.
5. If the existing emulator control cannot isolate all configured routes or
   cannot prove actual failed custody, mark this native fault leg blocked. Do
   not create a second networking/UI harness, widen the outage to unrelated
   peers, use an AWS fallback or change a remote service. An existing owned local
   fixture profile is allowed with its source-built/configuration scope explicit.

Reuse `TestCatalogDC017OwnedRelayServiceOutageAndReplay` in
`go-relay-server/catalog_relay_outage_recovery_test.go:16–125`: it removes only
the owned inbox handler, proves healthy peer bytes, restores fresh owners over
the same Redis backend, then checks ordered exact-ID replay/ACK. The separate
`relay_outage_sqlite_replay_test.dart` preserves both started clients, SQLite
reopen, same envelopes and receipt convergence (`TESTING.md:2532–2540`). Neither
component alone is a live remote-service-daemon or signed-device outage proof.

## RG-003 — retention, pages, expiry and later delivery

Planning estimate: 10–20 minutes for bounded native catch-up; no days-long wait.
Bind actual policy/configuration: `go-relay-server/inbox.go:28–41` defines direct
100/group 500 retained-entry caps and seven-day TTLs; the group reply byte
budget is separate. The app's seven-day group backlog and eight-generation
key policy are separate contracts. Respect protected-custody admission/ACK
semantics; do not claim unlimited offline retention or silently drop protected
obligations to manufacture capacity.

Reuse `catalog_relay_recovery_test.go:37–225` for real framed handler retrieval:
fixture timestamps at six/eight days, exact-ID pages, repeated page before ACK,
expiry, expired group cursor gap, authorized opaque epochs and later traffic.
It changes only owned fixture records, not any host/device/service clock; it is
memory-backend/handler proof, not app key availability or Redis process durability.
Reuse the existing inbox cap/TTL tests, group backlog policy/drain and group
key-ring eviction tests for those distinct boundaries (`TESTING.md:5687–5704`).

For the native leg, reuse the existing ordered direct/group campaign or MCP
catch-up on owned available peers. Record actual offline dwell and retained
count within capacity. Cross an **observed actual** request/page byte boundary
when supported, retain continuation/cursor evidence and compare exact IDs/order
after automatic drain and reopen. Do not confuse chat scroll pagination with
relay pages. If native limits/capacity cannot cross a page in this profile,
keep the controlled host page proof and label native short catch-up accurately.
An owned group epoch transition may be included with the recipient continuously
authorized and existing observable key state; otherwise keep that native subleg
unrun and reuse the host key controls. After catch-up/expiry, fresh direct/group
traffic must work without resetting the receiver. No clock changes, bulk
remote inbox filling or 101/501-message eviction experiment on real accounts.

## RG-004 — rejection cannot wedge subsequent valid delivery

Covered at the existing causal host boundaries. Reuse
`rejected_events_preserve_valid_delivery_test.dart:175–363`: actual production
listener, real SQL/contact authority, malformed/decrypt-failed input, unchanged
history/contact, then exact valid delivery and deduplicated replay. Lines
323–358 exercise the real subscription/queue after rejection, not just manually
calling a parser again; crypto/transport remain test seams.

Reuse `TestRG004RejectedRelayRequestsPreserveValidDelivery` in
`catalog_relay_recovery_test.go:228`: authenticated local streams reject malformed
JSON, unknown actions, missing-recipient ACL and spoofed group sender while
preserving prior custody and later valid store/retrieve/ACK on the same owners.
Existing group listener/replay and contact-request boundary tests remain the
corresponding host controls. No new native injection boundary was identified in
this preparation; do not send malformed traffic to a remote relay, add a push injector or
call an unrelated later UI send proof of a native rejection. A specifically
uncovered runtime failure should be reported with its actual receiving boundary
before adding a test-only adapter. No new app defect was established here.

Report each item as existing scoped coverage, ready MCP leg or precise missing
precondition, with source/artifact/configuration, private raw evidence paths and
cleanup. None of these preparation/source facts is a fresh device PASS.
