# Authoring the 7 new group sim rows — playbook

> Built from a full trace of the reliability-sim harness (2026-06-14). These rows are **device-orchestration scenarios**, not lightweight unit tests — each multi-party `private_*` scenario is bespoke code across 3 files, validated only by a real device/simulator run. This playbook makes the work mechanical and correct so it can be implemented + reviewed safely.

## Reality check (why this is heavier than it looks)

- The 4 multi-party rows live in **`integration_test/group_multi_party_device_real_harness.dart` (47,440 lines)** + the orchestrator + the criteria file. Each needs **role-runner methods + a proof struct + a bespoke verdict-evaluation branch**.
- Pass/fail is **not generic**: `evaluateGroupMultiPartyVerdicts` (criteria `:692`) does structural checks then **per-scenario proof validation** — a new scenario needs its own proof + branch.
- **`dissolveGroup` is not driven by the harness at all yet** (`grep dissolveGroup harness = 0`), so GS-I01 (online-dissolve convergence) needs *new harness plumbing*, not just a new scenario.
- **None of these can be behavior-validated on the host** — they run real Go crypto across simulators. Validation = a device run (the same loop as `DEVICE-REPRO-GUIDE.md`). The host can only gate **compile** (`flutter analyze`) + **discovery** (`--list-scenarios` / `--checks-tsv` count 174 → N).

## The wiring contract — every place a new `private_*` scenario must be registered

| # | File | What to add |
|---|------|-------------|
| 1 | `integration_test/scripts/group_multi_party_device_criteria.dart` (~`:165–262`) | a `const _<name>Requirement = GroupMultiPartyScenarioRequirement(scenario: '<name>', roles: [...])` |
| 2 | same file (~`:531–558` map) | `'<name>': _<name>Requirement,` |
| 3 | same file, `evaluateGroupMultiPartyVerdicts` (`:692`, after the generic checks ~`:760+`) | a **per-scenario proof-validation branch** that reads the `extra` proof your runners wrote and fails with a clear detail string |
| 4 | `integration_test/scripts/run_group_multi_party_device_real.dart`, `_scenariosToRun` `all` list (`:300`, case `'all'` `:510`) | add `'<name>'` so `--list-scenarios` + `all` include it |
| 5 | same file, usage string (`:2520`) | add `|<name>` (cosmetic) |
| 6 | `integration_test/group_multi_party_device_real_harness.dart`: scenario→roles map (`~:297–342`) + dispatch (`~:47039+`) + **N role-runner methods** + a proof struct | the actual scenario logic |

> No `classify_path` change is needed — `run_group_multi_party_device_real.dart` is already a classified group runner that auto-expands via `--list-scenarios`. The **notification rows (K01/K04)** also need no classify change (their host files are already classified). Adding rows here is the §5.2 "no script change" path.

## The role-runner template (proven, from `_runMl016*`, harness `:15908`)

```dart
Future<void> _run<Name>Alice(GroupMultiDeviceTestStack stack, Map<String,Map<String,dynamic>> identities) async {
  final fixture = await _createGroupFixture(stack: stack, identities: identities,
      memberRoles: const ['bob','charlie'], name: '<NAME>');
  writeSharedJson(_signalName('<name>_group_fixture.json'), fixture);
  final groupId = (fixture['group'] as Map)['id'] as String;
  await waitForSharedSignal(_signalName('bob_<name>_joined'));
  // ... drive the action under test (send / leave / demote / dissolve / react) ...
  await _writeVerdict(stack: stack, groupId: groupId, sentMessages: [...], receivedMessages: [...],
      extra: {'<name>Proof': <bespoke proof map>});
}
```

**Helper surface that already exists** (drive these, don't reinvent):
- `_createGroupFixture`, `importJoinedGroupFixture`, `_sendProofMessage`, `_waitForReceivedProofMessage`, `_writeVerdict`
- shared coordination: `writeSharedText/Json` + `waitForSharedSignal/Json` keyed by `_signalName(...)`
- group actions present in the harness: `removeGroupMember` (×7), `leaveGroup`/`broadcastVoluntaryLeave` (×1), `updateGroupMemberRole` (×1, demote via `_demote*`), `updateGroupMetadata` (×1), `uploadGroupAvatar` (×2), `sendGroupReaction` (×2), `rotateAndDistribute` (×30)
- convergence assertions: `_membersConverged`-style helpers, `_keyEpoch(stack, groupId)`, `_hasSavedContact`

**Missing → must be added:** a `dissolveGroup` driver for GS-I01.

## Per-row spec

| Row | Host | Roles | Drives | Asserts | Helpers | Expect | Effort |
|-----|------|-------|--------|---------|---------|--------|--------|
| **GS-H01** `private_voluntary_leave_convergence` | multi-party harness | a,b,c | c leaves voluntarily | a,b drop c from roster + render "c left" + advance epoch; c hard-deletes locally; silent | `leaveGroup`/`broadcastVoluntaryLeave`, `_membersConverged`, `_keyEpoch` | likely **GREEN** (untested-but-correct) — clean coverage add | **S** (closest to Ml016 template) |
| **GS-B02** `private_stale_roster_recipient_omission` | multi-party harness | a,b,c | c sends with a corrupted/lagged local roster missing b's device row | b receives via neither live nor custody; c's `expectedRecipientCount`/status truthfulness | `_sendProofMessage` + roster-mutation seam | likely **RED** (documents the bug) | **M** (needs a roster-corruption seam) |
| **GS-C07** `private_override_removal_nonconvergence` | multi-party harness | a,b(writer+override),c | b (override) removes c | b applies locally; a,c **reject** (receiver admin-only) → divergence | `removeGroupMember` + permission-override setup | **RED**/divergence (documents the asymmetry) | **M** (override grant setup) |
| **GS-I01** `private_online_dissolve_convergence` | multi-party harness | a,b,c | a dissolves while all online | b,c flip read-only in real time (`GROUP_MESSAGE_LISTENER_GROUP_DISSOLVED`) | **NEW** `dissolveGroup` harness driver + `_isDissolved` assert | likely **GREEN** (B4 fixed) but needs new plumbing | **L** (new driver) |
| **GS-L01** `private_media_reaction_roundtrip` | multi-party harness | a,b,c | b reacts to an image/video/voice msg | reaction chip converges on a,c | `sendGroupReaction` + media send + `_waitForReceivedProofMessage` | likely **GREEN** | **M** (adapt `private_reaction_roundtrip`) |
| **GS-K01** muted-FCM-leak row | `integration_test/foreground_group_push_drain_test.dart` | (sim test) | mute group, deliver FCM group push while "backgrounded" | muted group → **no** notification | follow that file's existing push-drain test pattern | **RED** (real bug: mute not honored on FCM path) | **S–M** |
| **GS-K04** tap-routing row | `integration_test/notification_open_ui_smoke_test.dart` | (sim test) | tap a group notification (payload `group:<id>|message:<id>`) | opens the correct GroupConversation | follow that file's notification-open pattern | likely **GREEN** | **S–M** |

## Validation gate (what to run after authoring each)

```bash
flutter analyze integration_test/group_multi_party_device_real_harness.dart \
  integration_test/scripts/group_multi_party_device_criteria.dart \
  integration_test/scripts/run_group_multi_party_device_real.dart            # compiles
dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios | grep <name>   # listed
./scripts/check_reliability_simulation_discovery.sh --checks-tsv | awk -F'\t' '$1=="group"{print}' | wc -l           # 174 → +N
# then behavior-validate on devices (see DEVICE-REPRO-GUIDE.md):
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group
```
Finally: bump the count + file list in `group-sim-feature-test-files.md`.

## Recommended implementation order (cheapest/safest first)

1. **GS-H01** voluntary-leave (S, likely green, proves the template end-to-end).
2. **GS-L01** media-reaction (M, adapt existing reaction roundtrip).
3. **GS-K01 + GS-K04** notification rows (separate files, independent).
4. **GS-C07** override-removal (M, needs override grant).
5. **GS-B02** stale-roster omission (M, needs a roster-corruption seam).
6. **GS-I01** online-dissolve (L, needs a new `dissolveGroup` harness driver).
