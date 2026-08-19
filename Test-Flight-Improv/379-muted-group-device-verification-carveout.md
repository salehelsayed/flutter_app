# 379 - Muted-Group Device-Tier Verification (Plan 378 G4 Carve-Out)

Status: planning-required (NOT execution-ready — the criteria-validator redesign below is unreviewed)
Type: Modification
Spec: carved out of `Test-Flight-Improv/378-notification-e2e-sound-and-suppression-verification-tdd-plan.md` TC-378-08 / TC-378-09 (gap G4)
Classification: needs-design
Closure tier: device

## Why this is a separate plan

Plan 378 assumed TC-378-08/09 were "criteria const + capture stage branch + a 7-surface
registration checklist, zero new production code". Execution grounding (2026-08-17) proved that
false. Both proposed scenario ids fall into the reaction branch of a **binary** classifier and
collide with hard-coded authoritative assertions. Closing G4 therefore means **redesigning what the
`groups.reaction_notification_campaign` device gate certifies** — a change that deserves its own
plan and its own `/tdd-review`, not an improvised edit inside 378.

Everything else in plan 378 (G1, G2, G3, G5, G6, G-reg) landed and is verified; see 378's
Execution Progress table.

## Verified blockers (each re-read in real source at execution time)

`integration_test/scripts/group_reaction_notification_device_criteria.dart` (2724 lines) dispatches
message-vs-reaction semantics on the id suffix `_message_unread_lifecycle` at **six** sites:
`:1173`, `:1665`, `:1691`, `:1730`, `:1960`, `:2449`. Neither proposed id
(`group_muted_message_suppression_lifecycle`, `group_muted_reaction_background_suppression`) carries
that suffix, so both take the **reaction** branch, which hard-asserts:

| Assertion | Site | Collision with plan 378's TC-378-08/09 |
|---|---|---|
| `expectedProviderSendCount == 2` (literal) | `_validateMeasurements` `:1134-1199` | survivable for a 2-message design, but see next row |
| reaction branch requires `targetMarker` non-empty AND `firstMarker`/`secondMarker` **empty** | `_validateMeasurements` | TC-378-08 is a two-message (control + suppressed) design — needs both markers |
| provider marker flips on the same suffix: `'[PUSH] Notification sent to'` vs `'[PUSH] Group notification sent to'` | `_validateAuthoritativeEvidence` `:1960+` | a muted **group message** emits the *Group* form → 0 matching lines → fail |
| `unreadCount == 0` | `_validateSqlCipherObservation`, `capture_group_reaction_notification_device.dart:3734` | **direct contradiction** — TC-378-08 requires msg2 unread PRESERVED (`read_at` NULL) |
| exactly-2 notification cards on the reaction branch | criteria `:2009-2044` | both muted scenarios assert **zero** cards |
| `relay` + `provider_fcm` evidence read unconditionally | `_validateAuthoritativeEvidence` `:1932-1933`, failures at `:1951-1959`, `:1987-1995` | plan 378's declared evidence-kind set omitted both → would fail regardless of the declared set |

Additional registration surfaces plan 378's checklist omitted:
- `test/integration/group_reaction_notification_device_criteria_test.dart:120-132` — byte-pinned ordered id list.
- `scripts/test/group_reaction_notification_device_contract_test.sh:9-15` — byte-pinned ordered `--list-scenarios` census. (Its pre-existing 5-vs-6 drift from plan 315 was repaired during 378 execution; it now pins 6 and is green. Two new scenarios make it 8.)

So the real surface count is **nine**, not seven — `lib/core/debug/group_reaction_e2e_probe.dart:23-29`
calls its allow-list "the SEVENTH registration surface" and
`integration_test/group_announcement_reaction_notification_proof_test.dart:32-36` calls its `test()`
block "the NINTH".

## Already landed by plan 378 (do NOT redo)

- `lib/core/debug/group_reaction_e2e_probe.dart` — `canonicalBadgeState` observation computed by the
  **production** helper `dbLoadCanonicalNotificationBadgeState`, redacted (hashed conversation ids),
  with an explicit `available:false` branch for partial-schema fixtures.
- `test/core/debug/group_reaction_e2e_probe_badge_observation_test.dart` — 4 host rows incl.
  "muted group excluded from canonical badge observation" (plan 378 TC-378-10, GREEN; causal RED recorded).
- The badge probe is therefore READY; only the device-tier scenarios remain.

## Design question this plan must answer first (the reason it is not execution-ready)

Replace the binary suffix dispatch with an explicit scenario-kind classifier
(`message` / `reaction` / `mutedMessage` / `mutedReaction`) carried as a FIELD on the scenario const,
not derived from the id string — then give the two muted kinds their own authoritative assertion
sets. The invariant that must be proven, not assumed: **the six existing scenarios must classify
identically to today and their assertions must be byte-unchanged.** A reverse mutation (flip one
existing scenario's kind) must re-red its own scenario and nothing else.

Open decisions for the plan author:
1. Does the muted branch assert `unreadCount` > 0 exactly, or `unreadCount` unchanged across the mute toggle?
2. Does TC-378-08 keep plan 378's confound-free sequencing (HOME control card → Group Info → Switch
   bounds-tap → back to HOME → msg2) or split the mute toggle into a separate setup stage?
3. Is the `[PUSH] Group notification sent to` provider count for a muted group still 2 (relay pushes
   regardless of local mute) — needs a live observation before it is pinned.

## Carried-over mechanics that were verified and are still correct

- Mute toggle is drivable through the real UI: `group_info_screen.dart:495-559` is a plain `Row`
  (no `SwitchListTile`); the "Mute Notifications" `Text` (`:528-529`, l10n `app_en.arb:701`) is
  findable, but `Switch.adaptive` (`:550-555`) exposes no text/content-desc — tap the checkable
  `android.widget.Switch` node in that row's vertical band, never the label centre. Post-toggle truth
  is read from the SQLCipher `is_muted` probe, not the UI.
- Retire-on-mute IS production behaviour (`group_repository_impl.dart:533` →
  `emitGroupNotificationReconciliationSignal` → reconciler cancel, host-locked at
  `group_notification_reconciliation_wiring_test.dart:172-197`), but the UI-driven toggle confounds
  device attribution (opening the group already clears the card), so post-toggle card state stays a
  **non-attributing observation**.
- Policy-gate mutation for the device re-red: drop the `isMuted` early return at
  `group_notification_display_policy.dart:109-110`; host siblings re-red at
  `group_message_listener_test.dart:16483+` and `background_message_handler_test.dart:4683-4742`.
- **Correction to plan 378 line 82:** the pure-FCM background-isolate muted read does NOT emit reason
  `muted` for `type=='group_message'`. The four `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` reasons are
  `direct_message_local_state_ineligible` (`:697`), `recent_duplicate_background_push` (`:797`),
  `message_event_already_claimed` / `reaction_event_already_claimed` (`:940`), and
  `event_claim_ownership_lost_before_show` (`:1614`). Any opportunistic logcat assertion must use
  those, not `muted`.

## Deferred / unchanged

- G7 (Doze / permission-denied / channel-disabled / token-refresh / OEM matrix) → GAP-N12.
- iOS presentation legs → GAP-N12 consolidated phase.
