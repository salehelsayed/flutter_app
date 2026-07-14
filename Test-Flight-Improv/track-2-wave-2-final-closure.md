# Track-2 / Wave-2 Final Closure

Date: 2026-07-13

Status: accepted / closed, including intentional reporting non-goal

## Verdict

Track-2/Wave-2 is closed for the repository-provisioned privacy and forwarding
scope. Plans 238 and 242 are accepted/closed for group and announcement
private-media lifecycle. Plan 249 is accepted/revalidated as the shared batch
foundation, and Plans 250 and 251 are accepted/closed for discussion and
announcement batch forwarding.

Track-2 Plans 244 and 245 are accepted/closed as intentionally not applicable.
Mknoon has no received-media reporting body, backend, queue, receipt, moderation
workflow, or Report UI by product decision. This is not an external-provisioning
blocker and does not claim that reporting was implemented. The same shared
cross-lane decision resolves Plan 246 for its owning Track-3/Wave-3 closure;
Plan 246 is not counted in this Track-2 inventory. The detailed Track-2 product
disposition and preservation record is
[`244-245-received-media-reporting-wave-2-closure.md`](244-245-received-media-reporting-wave-2-closure.md).

## Acceptance Evidence

- Wave-level `host-all`: `1151/1151` commands passed across `1143` Flutter
  files; `11502` tests passed, `1` skipped; all `8/8` Go legs passed. Former
  failures `#407` and `#616` passed in full-suite context. Retained log:
  `/tmp/track2_wave2_host_all_rerun2.log`.
- Reporting preservation: `19/19` focused Flutter invocations (`21/21` cases),
  `2/2` named Go cases, both zero-match production-absence scans, and global
  diff hygiene passed. Retained log:
  `/tmp/plan246_reporting_closure_focused_20260713.log`.
- Forwarding plan gates: `groups` `2171/2171` plus registered Go legs;
  `core-host-all` `310/310` files and `2485` tests with `0` skipped; the
  recorded external `feature-host-all` run was all green; the shared nine-file
  focused aggregate passed `30/30` with causal mutations restored.
- Physical Android Pixel `21071FDF600CSC`: Plan 238's `GPL-01D` SQLCipher,
  `GPL-11` protected viewer, and `GPL-12` real-Go bridge proofs each passed
  `1/1`, exit 0. Plan 242's availability-bounded `GPL-01D`, `APL-03D`,
  inherited `GPL-11`, and actual wired-route `APL-08` proofs each passed `1/1`,
  exit 0. The native claim is limited to route-scoped Android `FLAG_SECURE`
  acquire/release and background cleanup; it does not claim physical
  screenshot/record prevention, account-wide convergence, relay revocation, or
  a reporting proof.
- Final Graphify refresh: `./graphify-arch/refresh_arch_graph.sh --incremental`
  ran once and exited 0; `8` changed code, `2587` unchanged, `0` deleted. The
  refreshed architecture graph at `graphify-arch/graphify-out/graph.json`
  recorded `51767` nodes and `79663` edges; `graphify-arch/tdd-overlay.json`
  recorded `1331` files, `12862` named tests, and `979` production targets.

## Scope And Hygiene

The forwarding wave adds no new schema, wire format, transport, crypto
primitive, Go/libp2p authorization model, native boundary, or durable batch
job. Reporting production/schema/platform/test surfaces were not authored
because Report is an intentional product non-goal; the existing action matrices
continue to fail closed with Report absent.

QR establishes a direct/contact relationship; it does not join or confine an
announcement. Contact Block is enforced by direct/contact paths and future
invite authorization, not by the existing group-message receive path. Group
and announcement users instead control participation through explicit invite
Accept/Decline, device-local notification Mute, and whole-group Leave. Mute
does not discard messages, and Leave retains the last-admin invariant. These
controls are not substitutes for reporting.

The notification-settlement repairs exposed by the broad sweep retained exact
claim identities and behavioral assertions, then passed focused files,
notification aggregates, scoped analysis, diff checks, and the final broad
sweep. This closure synchronization is documentation-only and changes no app
source or test file.

This artifact must not be cited as reporting implementation or end-to-end
reporting proof. Reopen Track-2 Plans 244/245 only after an explicit product
decision authorizes a real reporting organization and user-visible reporting
semantics; external service availability alone is not authorization. Plan 246
retains the same reopen rule in its owning Track-3/Wave-3 closure.
