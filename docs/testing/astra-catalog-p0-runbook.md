# Catalog P0 owner runbook — first batch and remaining queue

Source base: `921bfe7591da0e21f75164c59dada208ecfa7a27` in
`/Volumes/CrucialX9/flutter_app-astra-update-relay-sims`.
The 30 requested requirements are captured with the source catalog digest in
`.codex-test-logs/astra-update-relay-sims/item3/catalog-source-snapshot.json`. This document confers no execution or coverage
credit. Batch one has three new scenarios applied and registered in the own worktree,
with seven existing complementary scenarios mapped for eight Catalog rows.
Analysis is clean for all 14 changed Dart files. The first batch passes 35
causal oracle/registry tests and three focused Go host contracts. Scoped host
lanes pass: production journey contracts 1240, SIMS contracts 368, runtime roots
21, Maestro flow contracts 9, and workflow 306; these lanes overlap, so the
counts are not unique tests to sum. Fresh workflow retry 020 passes after the
legacy source-pin/group target metadata repairs. Retry 019 aborted on swap
growth before any unittest ran. First attempts remain in ignored item3
artifacts. Final selection metadata validates and the explicit base/local
preview has no unmapped paths. Wider
required selection remains **NOT RUN**. Further drafts remain ignored and
unregistered. No device scenario has been run by Astra. Every host launch
needs fresh Mac resource and lease checks, including the unchanged load1 <=80
gate, and must respect an active coordinator quiet hold.

Execution owner: `flutter_app`. Astra authors source and host tests only. Use
distinct available disposable emulator roles; each count below is the number
of simultaneously required roles, regardless of the historical pin variable
names. Unavailable exact topology is `N/A (target unavailable by project
policy)`. All call runs require emulator audio input **OFF**, with that setting
recorded by the execution owner. Source registration, a host oracle test, RTP
counters or a UI state cannot certify audible content. Content-audio proof
remains **needs the test-build audio hook (not approved)**.

## Intended queue after registration and host validation

| Order | Catalog rows | Scenario / complementary legs | Emulators | Current state |
| --- | --- | --- | --- | --- |
| 1 | DC-002, DC-003 | `production.direct_catalog.ordered_offline_replay` | 2 | Applied; focused host tests pass; scoped host selection passes; wider required checks NOT RUN. 100 online messages, 10 recipient-offline messages, exact logical IDs/order before and after both restarts. |
| 2 | GC-002, GC-005 | `production.group_catalog.ordered_text_recovery`, plus existing `production.group_catalog.private_process_death_matrix` for GC-005 membership cuts | 3 | Applied; focused host tests pass; scoped host selection passes; wider required checks NOT RUN. Neither leg alone proves GC-005. |
| 3 | VC-003 | Existing `kx0002` **and** `kx0003` | 2 | Existing registrations; both role legs need fresh proof. Preserve prior failure evidence. |
| 4 | VC-005 | Existing `kx0005` **and** `kx0006` | 2 | Existing registrations; cold and locked callback legs are complementary. No completed-call claim. |
| 5 | VC-006 | Existing `kx0007` **and** `kx0008` | 2 | Existing registrations; busy admission and microphone-denied admission are separate required legs. Content-audio limitation remains. |
| 6 | DC-004, DC-007, DC-022 | Direct send checkpoint and offline-status/retry scenarios being authored | 2 | DC-004 applied; focused host tests pass; scoped host selection passes; wider required checks NOT RUN; DC-007/DC-022 remain incomplete. Use real persisted custody and same logical ID; no invented automatic offline queue or delivered double-check UI. |
| 7 | DC-006 | Direct quote, reaction add/remove, edit, deletion and durable replay | 2 | Ignored source draft in batch-two; unregistered, unformatted and unvalidated. Uses real quote, reaction add/remove, edit, delete UI receipts and stable IDs/tombstones after restart; no claim about raw quote/reaction fields absent from the observer. |
| 8 | DC-013 | Contact purge with actual chat/media and an unrelated preserved chat, then restart | 3 | Not authored completely; call-history-only fixtures are insufficient. |
| 9 | DC-016 | Blocked ingress/alerts, authorized stored-message deletion exception, unblock and fresh delivery | 2 | Not authored completely; do not replace the deletion exception with blanket rejection. |
| 10 | GC-001 | Real create, accept/decline, add-member and policy-correct history legs | 4 | Six existing complementary scenarios are source-mapped in the ignored batch-two draft; fresh execution still needs distinct available role pins. |
| 11 | GC-009 | Existing quote/reaction legs plus received-media delete-for-me persistence/locality | 3 | Existing quote/reaction coverage is partial; local media deletion leg not authored completely. |
| 12 | IN-002, IN-003, IN-009 | Selective introducer topology, real picker/consent UI, pass fences and durable offline outbox | 3 | IN-002 has an ignored producer/oracle/probe and six UI-recipe source drafts, unregistered and unvalidated. IN-003/IN-009 remain source fit only. Default full-mesh preparation is unsuitable; the existing intro probe actively drains inbox and must follow a natural-delivery UI witness. |
| 13 | VC-004 | Existing `kx0015`/`kx0016`/`kx0017` native-card legs plus actual in-app incoming/active name privacy | 2 | Native cards alone are insufficient; in-app leg not authored completely. |
| 14 | VC-017 | Same-call bounded interruption, current recovery deadline and terminal late-recovery fence | 2 | Not authored completely; no audibility claim without the unapproved audio hook. |
| 15 | VC-023 | Saved always-relay setting, actual relay-only candidate selection, unavailable-relay failure/no direct fallback, restored-service call | 2 | Not authored completely. Existing forced-relay profile masks preference propagation; a source-bound test-profile variant is needed. |

For the existing call cohort, the repository's current safe adapter is
`docker-ws/run_sims_safe.py device-audio`; it supports an ignored exclusion file
for selecting the required KX legs. Do not run its whole default cohort merely
to close these rows. The scoped commands below preserve that existing fixture owner and exclude
unrequested KX rows. The wrapper still includes its existing base call proof;
interpret only the actual scenario receipts within their recorded scope.
The group membership companion is already registered in
`tool/sims/critical_features.json`; its three-role topology must be rebound to
three distinct available emulators by the existing disposable-manifest route.

## First-batch commands for the execution owner

Only `flutter_app` executes this section. Astra has not run it. Start from the
exact integrated candidate in the execution owner's checkout. Resolve and pin
available targets through that owner's normal preflight, and set its existing
ignored `docker-ws/local_devices.env` or allowlisted environment inputs. Keep
all emulator roles distinct. The pair needs `SIMS_ANDROID_EMULATOR_DEVICE_ID`
and `SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID`; the three-person group also needs
`SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID`. The historical `FOURTH` name does
not require four running emulators. Do not enable the physical-row opt-in.

Use the existing disposable relay input; the dedicated direct-text and call
wrappers own their local fixture replacements. No production account, relay
or device state belongs in this document or mailbox. Confirm emulator audio
input **OFF** before the call cohort and record that fact in private evidence.
Run one campaign at a time, with the existing fresh lease/resource preflight;
load1 above 80 keeps the launch on hold. Every failed attempt needs cleanup
review before a fresh invocation, and original failures remain visible.

The following prepares only ignored exclusion files. It launches no scenario:

```sh
export ASTRA_P0_RUN="build/kayan-safe/catalog-p0-$(date +%Y%m%dT%H%M%S)"
python3 - <<'PY'
import json, os, pathlib, subprocess

out = pathlib.Path(os.environ['ASTRA_P0_RUN'])
out.mkdir(parents=True, exist_ok=False)
rows = {c['id']: c for c in json.loads(
    pathlib.Path('tool/sims/critical_features.json').read_text())['capabilities']}
listed = json.loads(subprocess.check_output(
    ['python3', 'docker-ws/run_sims_safe.py', 'major', '--list'], text=True))
major = {r['id'] for r in listed['rows']}

def closure(wanted):
    selected = set(wanted)
    while True:
        deps = {dep for key in selected for dep in rows[key].get('dependencies', [])}
        if deps <= selected:
            return selected
        selected |= deps

for label, scenario in {
    '01-direct': 'production.direct_catalog.ordered_offline_replay',
    '02-group': 'production.group_catalog.ordered_text_recovery',
    '03-group-membership': 'production.group_catalog.private_process_death_matrix',
}.items():
    keep = closure({scenario})
    assert keep <= major, (label, 'missing registered owner/dependency')
    (out / (label + '.exclude')).write_text('\n'.join(sorted(major - keep)) + '\n')

calls = json.loads(subprocess.check_output(
    ['python3', 'docker-ws/run_sims_safe.py', 'device-audio', '--list'], text=True))
call_rows = {r['id'] for r in calls['rows']}
keep_kx = {'kx0002', 'kx0003', 'kx0005', 'kx0006', 'kx0007', 'kx0008'}
assert keep_kx <= call_rows, 'missing required complementary call leg'
(out / '04-calls.exclude').write_text('\n'.join(sorted(
    key for key in call_rows if key.startswith('kx') and key not in keep_kx)) + '\n')
PY
```

Run each line separately, assess its actual scenario verdict and cleanup, then
continue to the next line. Do not paste the list as an unattended script:

```sh
python3 docker-ws/run_sims_safe.py major --exclude-file "$ASTRA_P0_RUN/01-direct.exclude" --output "$ASTRA_P0_RUN/01-direct"
python3 docker-ws/run_sims_safe.py major --exclude-file "$ASTRA_P0_RUN/02-group.exclude" --output "$ASTRA_P0_RUN/02-group"
python3 docker-ws/run_sims_safe.py major --exclude-file "$ASTRA_P0_RUN/03-group-membership.exclude" --output "$ASTRA_P0_RUN/03-group-membership"
python3 docker-ws/run_sims_safe.py device-audio --exclude-file "$ASTRA_P0_RUN/04-calls.exclude" --output "$ASTRA_P0_RUN/04-calls"
python3 docker-ws/run_sims_safe.py device-text --output "$ASTRA_P0_RUN/05-direct-cut"
```

For `major`, the safe launcher retains global policy-blocked rows in its
summary even when those rows are excluded. An overall `BLOCKED`/exit 78 with
child exit 0 therefore does not establish failure of a selected scenario or a
passing full suite. Read the selected scenario's source-bound native report
and checkpoint, keep the overall wrapper status, and report both scopes. No
`NOT RUN` row becomes covered merely because an exclusion file names it.

The direct cut must use `device-text`, whose outer adapter starts the private
one-shot committed-custody checkpoint before preparing the APK. Invoking only
the inner Dart runner lacks that fixture. A missed 2.5-second cut deadline is
a harness failure with no product verdict. The sender's stored `failed` status
alone does not imply a visible manual Retry action; durable ordinary text can
render in the automatic pending-recovery lane.

## Explicit fixture deferrals

| Catalog rows | Verdict | Reason / owner direction |
| --- | --- | --- |
| CR-001, CR-002, CR-003, CR-005, CR-006, CR-007, CR-012, CR-018 | **NOT RUN** | **needs consent-capable fixture**. Per Kayan `m-6bbcb313`, no new consent infrastructure. The bounded source-fit review is in `.codex-test-logs/astra-update-relay-sims/item3/CR-source-fit.json` and `.codex-test-logs/astra-update-relay-sims/item3/CR-fixture-notes.md`; the separate debug/non-E2E Appium text-paste route is fixture entry, not optical camera proof. |
| DC-020 | **NOT RUN** | **needs linked-installation fixture**. Per Kayan `m-085e261a`, do not build one. See `.codex-test-logs/astra-update-relay-sims/item3/DC020-fixture-notes.md`. The default-off authoring flag alone does not remove persisted linked-installation authority or make this row N/A. |

## Verdict discipline

Record per-scenario exact source/configuration/artifact digests, available role
count, first attempt and any cleanup-reviewed fresh invocation. A row with
complementary legs stays incomplete until each required leg passes. A scenario
failure remains visible; a repaired harness needs fresh execution, and a
passing host oracle does not stand in for device proof. Missing fixtures above
retain the exact NOT RUN labels. An app bug proven by a test is reported and
that row stops; Astra does not edit `lib/` to repair it under this assignment.
