# Session 14 Plan: Verify / Strengthen Go-Side Announcement Writer Enforcement

**Date:** 2026-03-26
**Status:** Plan only

## 1. Real Scope

Re-evaluate the remaining announcement-authority gap at the Go / bridge layer and decide whether Session 14 is still real work or mostly stale evidence collection.

The default target is not new product code. The session should first prove or disprove that the current Go tree already enforces:
- non-admin `group_message` publish attempts in announcement groups are rejected before they are treated as accepted or delivered
- admin publishes in the same announcement groups are still allowed
- the bridge layer still routes group publishes through that enforcement path

Only if the current Go evidence is still too weak should Session 14 add one minimal Go-side regression. Do not broaden into Flutter announcement behavior, which Session 13 already covers directly.

Out of scope:
- announcement UX or product changes
- Flutter-side create / send / react behavior
- scheduled announcements, read receipts, search, or admin tooling
- transport, startup, resume, or rejoin hardening unless a direct dependency appears during verification

## 2. Session Classification

`evidence-gated`

Why:
- the roadmap's older "cross-tree" framing is now partly stale because `go-mknoon/` lives inside this workspace at `flutter_app/go-mknoon`
- `go-mknoon/node/pubsub.go` already contains direct announcement writer enforcement on both the publish path and validator path
- `go-mknoon/node/pubsub_test.go` and `go-mknoon/node/rendezvous_test.go` already appear to prove the contract strongly enough that Session 14 may be evidence-only unless a package-boundary gap remains

## 3. Files and Repos to Inspect Next

Primary roadmap and report context:
- `Test-Flight-Improv/16-session-todo-roadmap-2.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/13-announcement-use-case-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md` only for gate naming and gate rules

Primary Go enforcement path:
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/rendezvous_test.go`
- `go-mknoon/node/group.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`

Inspect only if a Flutter-facing contract question appears:
- `lib/core/bridge/bridge_group_helpers.dart`
- Session 6 / Session 13 Flutter announcement tests as contract context only

## 4. Existing Tests Covering This Area

Current repo-local evidence is already strong:
- `go-mknoon/node/pubsub.go` checks `isAllowedWriter(config, senderPeerId)` inside `PublishGroupMessage(...)` before publish
- `go-mknoon/node/pubsub.go` also rejects unauthorized announcement `group_message` envelopes in the topic validator path
- `go-mknoon/node/pubsub_test.go` contains `TestIsAllowedWriter_AnnouncementAdminOnly`
- `go-mknoon/node/pubsub_test.go` contains `TestIsAllowedWriter_AnnouncementMemberBlocked`
- `go-mknoon/node/pubsub_test.go` contains `TestGroupTopicValidator_AnnouncementNonAdminRejected`, which expects `reject:unauthorized`
- `go-mknoon/node/pubsub_test.go` contains `TestInviteLifecycle_AnnouncementGroup_NewWriterCannotPublish`, which proves a newly added writer is still blocked in an announcement group while the admin publish path remains accepted
- `go-mknoon/node/rendezvous_test.go` contains `TestAnnouncementGroupRendezvousRefresh_UsesSameTTLRefreshPath`, which re-checks admin allowed / reader blocked behavior under announcement config
- `go-mknoon/bridge/bridge.go` routes `GroupPublish(...)` into `n.PublishGroupMessage(...)`, so the bridge package should inherit the node-side enforcement contract

What still looks weaker:
- `go-mknoon/bridge/bridge_test.go` appears chat-heavy around create/publish coverage and does not obviously expose an easy-to-find announcement publish rejection proof yet

## 5. Regression / Tests To Add First

Default answer: none.

Session 14 should first verify whether the current Go tests already prove the contract strongly enough. The current evidence suggests they probably do.

If a new regression is still justified after that check, add exactly one narrow bridge-level proof first:
- extend `go-mknoon/bridge/bridge_test.go`
- create an announcement group through `GroupCreate(...)`
- prove an admin `GroupPublish(...)` succeeds
- prove a non-admin `GroupPublish(...)` on the same announcement group fails with an authorization error before any accepted/delivered interpretation

Only fall back to another node-side regression if the bridge package cannot express that package-boundary proof cleanly.

## 6. Evidence To Capture First

Capture these concrete facts before any code change:
- the exact `PublishGroupMessage(...)` pre-publish authorization check in `go-mknoon/node/pubsub.go`
- the exact validator-side rejection path for unauthorized announcement `group_message` envelopes in `go-mknoon/node/pubsub.go`
- the exact existing Go test names that already prove admin-only announcement writes
- the exact pass/fail status of `go test ./node` and `go test ./bridge`
- the exact `GroupPublish(...)` delegation path in `go-mknoon/bridge/bridge.go`
- whether `go-mknoon/bridge/bridge_test.go` still lacks an announcement-specific publish rejection proof after final inspection
- the fact that `09-network-group-messaging.md` and `13-announcement-use-case-audit.md` are partly stale because they describe the Go proof as outside this repo

## 7. Step-by-Step Implementation Or Evidence-Collection Plan

1. Reconfirm the direct authorization checks in `go-mknoon/node/pubsub.go`.
2. Reconfirm that `go-mknoon/bridge/bridge.go` forwards `GroupPublish(...)` into `n.PublishGroupMessage(...)`.
3. Run `cd go-mknoon && go test ./node`.
4. Run `cd go-mknoon && go test ./bridge`.
5. If both packages pass and the existing node tests remain direct and readable, treat Session 14 as `evidence-gated` rather than implementation-needed.
6. If the bridge package still lacks a sufficiently direct package-boundary proof, add one narrow announcement `GroupPublish(...)` regression in `go-mknoon/bridge/bridge_test.go`.
7. Re-run only the touched Go packages.
8. Only inspect or run Flutter-side tests if a bridge contract change forces a Flutter-visible payload or contract change.

## 8. Risks And Edge Cases

- The older reports explicitly say the Go-side proof cannot be verified from this tree, so Session 14 can waste time solving a stale documentation claim instead of a live code gap.
- Sparse bridge-package coverage is not automatically a bug if the node package already proves the enforcement contract directly and the bridge simply delegates into it.
- A bridge-level regression is only justified if it adds package-boundary proof. Duplicating `node/pubsub_test.go` verbatim would be low-value.
- `GroupPublishReaction(...)` is not the target here. Announcement reactions remain allowed; Session 14 is about `group_message` writer enforcement.
- Do not drift into Session 13 Flutter creation coverage, broader send/read/react flows, or any transport/startup behavior.

## 9. Exact Tests To Run After Implementation

Default direct Go package verification:

```bash
cd go-mknoon && go test ./node
cd go-mknoon && go test ./bridge
```

Conditional only if a Flutter-facing bridge contract changes:

```bash
flutter test test/features/groups/application
flutter test test/features/groups/presentation
```

## 10. Subsystem Gate(s)

No named Flutter subsystem gate is required by default.

Only if a Flutter-visible group contract changes, run:

```bash
./scripts/run_test_gates.sh groups
```

Reason:
- the roadmap limits the Group Messaging Gate to cases where a Flutter-visible group contract changes
- a pure Go evidence pass does not need Flutter integration gate coverage

## 11. Whether Baseline Gate Is Required

No by default.

Reason:
- Session 14 should stay in the Go tree or in evidence-only documentation
- the roadmap says Baseline Gate is required only if this session also changes Flutter code

## 12. Whether Startup / Transport Gate Is Required

No by default.

Reason:
- the scoped enforcement path is announcement publish authorization, not startup, reconnect, resume, or topic rejoin behavior
- only reconsider this if a bridge change unexpectedly alters group startup / rejoin / resume semantics

## 13. Done Criteria

Session 14 is complete when one of these is true:
- `go test ./node` and `go test ./bridge` are green and the session records clear repo-local evidence that non-admin announcement `group_message` publishes are rejected while admin publishes remain allowed
- or one minimal Go-side regression has been added and the relevant Go package tests are green

And all of these are true:
- a future audit can point directly to the Go proof in this workspace instead of saying the contract cannot be verified here
- no Flutter product changes were bundled into the session
- no unrelated Go product scope was added

## 14. Scope Guard

- Do not add announcement UX, admin tooling, scheduled announcements, search, or read receipts.
- Do not broaden into transport, relay, startup, resume, or rejoin hardening unless a direct dependency is exposed by the Go test run.
- Do not run Flutter gates unless a Flutter-visible contract actually changed.
- Prefer evidence capture over duplicate regression expansion. One minimal bridge-level regression is the maximum justified fallback if the current proof still looks too weak.
