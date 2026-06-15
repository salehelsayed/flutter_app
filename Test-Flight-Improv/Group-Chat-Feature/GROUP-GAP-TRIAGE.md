# Group-messaging gap triage (baseline)

> **Purpose.** Before planning/implementing the gaps in `GROUP-MESSAGING-BEHAVIOR-AND-TEST-SCENARIOS.md`, separate what is *really open today* from what is *already tested/fixed* and what is *by-design*. Built 2026-06-14 on branch `121-improvements` by inspecting the reliability-sim harness assertion depth + running the host group suite.

## The reframing (most important finding)

**The "gaps" are mostly NOT test-writing work.** The field bugs (S1/S3 metadata, S5 permission leak, S6 recovery, S7 stale snapshot, fanout subset) already have **deep, multi-role device-real scenarios** in the reliability-sim matrix — they are not untested. So the next step after this triage is **not** "write tests for A/B/C." It is, in order:

1. **Run the existing device-sim scenarios** to learn which are red → that tells us which bugs are *actually open* vs *already fixed-uncommitted* (111–121 landed a lot) vs *build-skew*.
2. **Fix only the confirmed-red** ones (root-cause-first; A & C share one engine).
3. **Write the small set of genuinely-new coverage rows** (§"Truly new" below) — the only real test-authoring backlog.

This is much smaller and better-sequenced than a blanket "TDD-plan all 49 NEW scenarios."

## Verification status by category

Legend: 🟢 already-tested (assertion is deep) · 🟡 tested-but-verify-depth · 🔴 genuinely untested (both layers) · ⚪ by-design / product-decision.

### A. Field bugs — already have deep device-sim scenarios → RUN to get red/green

| Field bug | Layer-B scenario (device-real, multi-role) | Depth | Action |
|-----------|--------------------------------------------|-------|--------|
| S1/S3 metadata + photo convergence | `private_admin_metadata_intro_photo_convergence` (a/b/c), `group_admin_metadata_convergence_simulator_test` | 🟢 prompt-driven, asserts avatar **bytes** + late-invitee catch-up | run gate |
| S5 demote permission leak + S6 admin reliability | `private_admin_demotion_enforcement` (a/b/c/**dana**), `regression_group_admin_permissions_and_message_reliability_four_users` (a/b/c/dana) | 🟢 4-role, includes demotion + add-after-demote | run gate |
| S7 stale invite/metadata for late joiner | `scenario7_group_invite_stale_metadata_recovery` (a/b/c/dana) | 🟢 dedicated 4-role scenario | run gate |
| B subset fanout / connectivity | `private_full_mesh_online`, `private_relay_only_delivery`, `private_partition_readd_heal`, `private_non_friend_member_delivery` | 🟢 covers mesh/relay/non-friend | run gate |
| Re-add cluster | `private_offline_readd`, `private_readd_current/active_members/cycles`, `private_rapid_readd`, `private_stale_invite_readd`, `private_late_leave_readd`, `private_rotated_device_readd`, `private_same_user_multi_device_readd` | 🟢 rich | run gate |
| Key epoch / rotation | `private_long_offline_epoch_churn`, `private_stale_lower_key_update`, `private_same_epoch_key_conflict`, `private_partial_key_distribution`; routing `G7` | 🟢 | run gate |
| Membership cap | `private_max_group_size_churn` | 🟢 | run gate |
| Concurrent admin edits | `private_concurrent_admin_membership_edits` (a/b/c/dana) | 🟡 membership covered; same-µs **name** LWW not asserted → extend | run gate + extend |
| Recovery delivery | `private_relay_reconnect_group_recovery`, `private_background_resume_group_delivery`, `private_process_death_matrix`, `group_recovery_e2e_test` (8) | 🟢 (delivery); recovery-**gate UX** is layer A only | run gate |

> **One depth caveat to confirm when you run it:** that `private_admin_demotion_enforcement` asserts the *leak-prevention direction* — i.e. after demotion, the demoted user's edit/add is **rejected by all peers** (not just that a happy-path demotion renders). If it only asserts the happy path, extend it; the runner exists either way.

### B. Truly new — absent from BOTH layers (the real authoring backlog)

| 🔴 Gap | GS | Where to add |
|--------|----|--------------|
| Sender stale-roster omits a member from live + custody | GS-B02 | `private_stale_roster_recipient_omission` (multi-party harness) |
| Remaining peers drop a clean voluntary leaver | GS-H01 | `private_voluntary_leave_convergence` |
| Live dissolve flips all connected peers read-only | GS-I01 | `private_online_dissolve_convergence` |
| Override-empowered writer's removal rejected by receivers | GS-C07 | `private_override_removal_nonconvergence` |
| Reaction on image/video/voice converges | GS-L01 | extend `private_reaction_roundtrip` / new `private_media_reaction_roundtrip` |
| Muted group still raises FCM background notification | GS-K01 | row in `foreground_group_push_drain_test.dart` |
| Group-notification tap routes to correct group | GS-K04 | row in `notification_open_ui_smoke_test.dart` |

### C. Layer-A (host) logic — lock cheaply in `test/features/groups/**`

🟢/🔴 mix — these are use-case/widget logic, *not* reliability-sim: GS-B03 (vacuous-sent), GS-C03 (promoted-can't-add), GS-D01–D08 (recovery-gate UX/error wording), GS-E04 (bridgeError-with-group accept), GS-F01/F02 (security-chip flash), GS-G05 (dedup id), GS-N02/O02–O05, GS-P02–P04.

**Host baseline run** (`flutter test test/features/groups`, default parallelism, 2026-06-14): **+2054 / −1**. The single failure was in `group_membership_smoke_test.dart`; re-running that file serially (`-j 1`) gave **+91 / All tests passed**. ✅ **Confirmed: the −1 is the known pre-existing shared-global-gate-file parallel race, NOT a regression.** Layer-A baseline is **healthy** — the implemented-uncommitted fixes (111–121) hold at the host layer. (Run the full group sweep with `-j 1` for a clean green, or fix the test-isolation race.)

### D. By-design / product-decision — not "bugs to fix"

⚪ GS-M03 (no late-joiner media backfill — intended ACL design), GS-M04 (relay TTL durability), GS-L04 + read-receipt setting (receipts are a sync-only substrate; needs a product decision before any test), GS-C08 (`reader` role unenforced in chat groups — confirm intent).

## What I could NOT determine here (the handoff)

**Layer-B pass/fail requires a device/simulator run** (the `private_*` scenarios run real Go crypto across simulators — not runnable from this host shell). To get the decisive red/green that tells us which field bugs are still open:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group
# or scope to the field-bug scenarios:
dart integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario private_admin_demotion_enforcement
dart integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario scenario7_group_invite_stale_metadata_recovery
```

## Recommended sequence after this triage

1. **You run the group reliability-sim gate** (above). Record which `private_*` field-bug scenarios are red.
2. **Red scenarios → fix track.** If A/C are red, that's the shared accept-gate/local-roster engine → do a *root-cause fix design* (worth a judge-panel workflow) before TDD.
3. **Green scenarios → just need device evidence + commit** (many 111–121 fixes are uncommitted on this branch per project memory).
4. **Authoring backlog = only section B above** (7 truly-new rows) + the 2 "extend" items.
5. Keep this file, the behavior spec, and `group-sim-feature-test-files.md` in sync.
