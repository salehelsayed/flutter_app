# Plans 244-245 - Track-2/Wave-2 Reporting Product Closure

Date: 2026-07-13
Status: accepted / intentionally not applicable
Plans: 244 - 1:1; 245 - discussion group
Cross-lane decision: Plan 246 - announcement received media, owned by Track-3/Wave-3
Production behavior: Report is intentionally absent

## Verdict

Track-2 Plans 244 and 245 are closed. Mknoon intentionally has no reporting
body, backend, gateway, outbox, receipt, moderation process, or Report UI. This
is a confirmed product non-goal, not an external-provisioning blocker and not
an unfinished implementation.

The earlier shared-authority proposal is superseded by
`244-246-shared-media-reporting-authority-decision.md`. That shared decision
also resolves Plan 246's announcement lane, but Plan 246 is closed in its owning
Track-3/Wave-3 record and is not part of this Track-2 plan inventory. No service,
vendor, endpoint, credential, schema, migration, fake gateway, or device fixture
is required to close Plans 244/245.

## Exact User-Control Model

- QR establishes the direct/contact relationship after signed-payload
  validation and initiates the recipient-bound contact request.
- Direct/contact Block and Unblock are explicit local user choices. Block is
  enforced by direct chat/reaction receive paths, contact admission, and other
  contact-scoped features.
- Contact Block does not filter messages/media from an existing member of a
  shared group or announcement. It must not be described as group moderation.
- Group and announcement invitations have explicit Accept/Decline controls.
- Mute suppresses local notifications only; muted messages still persist.
- Leave exits the group/topic and clears local membership data, subject to the
  last-admin invariant.
- Ordinary media actions remain separate local actions and never imply that
  Mknoon received, reviewed, or acted on a report.

## Repository Audit

Graphify anchored the current direct/group received-media controllers, QR and
contact-request path, Block/Unblock controls, group invitation path, and group
listener. Targeted source verification found:

- no production path named for received/group/announcement media reporting,
  reporting authority/gateway, or safety gateway under `lib/`, `android/`,
  `ios/`, `go-mknoon/`, or `go-relay-server/`;
- no reporting gateway/configuration/result model or Report result copy;
- no reporting-specific database migration, native capability, Go/relay
  command, integration fixture, or environment dependency;
- exact direct, discussion, and announcement action matrices with no Report
  capability; and
- no `isBlocked` check in the current group-message receive path, which bounds
  the contact Block claim to direct/contact-scoped paths.

The privacy inventory states that no automated/human moderation, user-report
system, third-party Trust & Safety vendor, or centralized ban list exists. Its
Block description is reconciled to the source-proven direct/contact scope.

## Acceptance Evidence

- Structural reporting-path inventory: PASS, no implementation path found.
- Structural gateway/config/result inventory: PASS, no contract or UI copy
  found.
- Track-2/Wave-2 `host-all`: `1151/1151` commands passed; all `1143`
  Flutter test-file commands completed with `11502` tests passed and `1`
  skipped; all `8/8` Go legs passed. Former suite races at commands `#407` and
  `#616` passed in the clean full rerun. Log:
  `/tmp/track2_wave2_host_all_rerun2.log`.
- Existing causal tests cover direct Report absence, exact discussion and
  announcement action sets, QR mutual contact convergence, blocked-peer
  no-auto-add, invitation Accept/Decline, muted-message persistence, explicit
  Leave, and announcement reader no-publish authorization.
- Consolidated focused revalidation passed `19/19` serialized Flutter
  invocations (`21/21` cases), `2/2` named Go cases, both zero-match production
  reporting scans, and global diff hygiene. Retained log:
  `/tmp/plan246_reporting_closure_focused_20260713.log`.
- No reporting production or test fake was added.

Focused exact revalidation is recorded by the three canonical plans. It ran in
the root-owned serialized slot; this closure did not run another full
`host-all`.

## Change And Scope Record

- Product decision/docs: reconciled from external-provisioning-pending to
  accepted/intentionally-not-applicable.
- Production, schema, platform, localization, Go, relay, and reporting tests:
  unchanged.
- Existing ordinary media, QR/contact, Block/Unblock, invite, Mute, Leave, and
  authorization behavior: unchanged.
- Device/relay reporting proof: N/A because no reporting boundary exists by
  design.
- Graph refresh: not required for documentation-only closure.

## Reopen Rule

Reopen Plans 244/245 only after an explicit product decision changes the
reporting non-goal and authorizes both a real reporting organization and
user-visible reporting semantics. External provisioning alone is not a reopen
condition. Plan 246 retains this same rule in its owning Track-3/Wave-3 closure.
