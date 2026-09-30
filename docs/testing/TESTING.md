# Mknoon regression checks and testing knowledge

Last reviewed: 2026-09-11 against `f1761aa17e782283f734200f969a9622f3f837ce`
plus the explicitly recorded local workflow changes. This file records verified
testing lessons and limitations. It is not a release approval or a run ledger.

## Current architecture and build boundary

Feature-dependent group-media and dual-path notification debug composition now
lives in `lib/debug/`. Its relocation removed 16 existing core dependency
exceptions and the nine newly unapproved imports; the exact remaining ratchet is
153. The `debug-composition-boundaries` selection covers both old and new paths,
the exception snapshots, and the existing causal debug tests. Preserve the
build-profile, entrypoint, discovery, and group-gate contracts when moving these
helpers. Focused evidence is in
`.codex-test-logs/failure-fixes-20260920/architecture-debug.log`.

The current application uses Flutter with native Go, not the earlier QuickJS
core. `lib/app/bootstrap/production_application_bootstrap.dart:5296` constructs `GoBridgeClient` over method/event
channels. Android's `android/app/build.gradle.kts:431` connects `buildGoAar` to
`preBuild`; `ios/Podfile:63` ensures the GoMknoon/NSE frameworks. `pubspec.yaml`
currently declares `1.0.1+119`, and its bundled asset entries contain icons,
JPEGs and MP4s; no JavaScript asset or QuickJS dependency was found in the
current pubspec/lockfile. Keep JavaScript test/tooling discovery and bundle
identity handling because retained tooling and future bundled assets can still
change; do not assume the old runtime architecture is active.

The existing App Store artifact entry point is
`scripts/build_ios_appstore_ipa.sh --build-number=<candidate-number>`; it applies
`tool/build/voice_call_release_defines.json`. The original testing-wrapper work
did not build or distribute an IPA; later local candidate identities are recorded
in `Network-Arch/IPV6-Infra-Ops.md`. Candidate evidence must bind the actual selected build
configuration and signed artifact, not just the Dart revision or version label.

## Sources of truth

- `tool/testing/selection.json` owns check selectors, requirements, timeouts,
  affected-area mappings, and mandatory membership. Edit executable mappings
  there; do not maintain a second selection list in this document or skills.
  The exact `UI-25-UIUXPolish/ui-ux-polish.zip` documentation exclusion was
  verified against its six Markdown members, each identical to the adjacent
  unpacked file; it does not exempt other archives or executable changes.
- `python3 scripts/mknoon_checks.py discover` generates the inventory from the
  existing runners/files. Its output distinguishes file/suite discovery from
  runner-reported test cases. Discovery does not establish assertion coverage.
- `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`, and
  `scripts/run_flutter_full_regression.sh` retain their existing gate/full-runner
  responsibilities. The wrapper adds deterministic change/release selection and
  evidence checks; it does not replace Flutter, Go, native, or JavaScript runners.
- Wrapper reports default to ignored `.codex-test-logs/checks-*/` directories;
  use that ignored directory for raw runs; arbitrary `artifacts/` paths are not automatically ignored. Legacy
  full runs retain `.full_regression_logs/`. Keep tokens, keys, personal data, and private
  message content out of shared reports. Use synthetic fixture content.
- `docs/**/*.md` is already indexed by `codex-memory/config.json`. No new memory
  database or service is required. Read this file before selecting tests; use
  Codex document recall for focused prior decisions and targeted source searches
  for code impact in Codex. Claude's separate navigation configuration is unchanged.

Codex's Graphify integration was removed on 2026-09-11. Document-memory
advisories use source searches for code questions, checkpoints accept absent
legacy graph metadata, and every document-memory experiment profile keeps the
retired Codex graph gates off. The `codex-tooling` selection runs the host
contracts for this boundary. Historical graph telemetry remains readable;
Claude's graph tooling and generated graphs remain installed. An already
running Codex session may retain previously loaded agent/skill instructions
until a new session starts.
Verified evidence: `.codex-test-logs/codex-graphify-removal-checks/results.json`
records 247 passing Codex host tests plus passing fast/workflow/schema checks.
Python check selectors must enumerate files: wildcard expansion is implemented
for Flutter selectors, while the Python runner forwards paths to `unittest`.
The retained Graphify contracts use `.claude/skills/graphify/SKILL.md` and
reject reinstating the retired Codex hook. Their direct-media precision proof
now points to `direct_conversation_route_authority_contract_test.dart`, where
the production routing assertion moved. The `graphify-tooling` selector runs
the existing 53-test suite; all 53 pass in
`.codex-test-logs/all-tests-y227gs8x/checkpoint-003-repaired/results.json`.

Fresh-checkout verification exposed two Codex integration errors: the tests
unconditionally read ignored `.codex/config.toml` and `.codex/hooks.json` from
the development machine. Clones intentionally have no such local overrides.
The integration tests now accept their absence and still reject checkpoint
configuration when those files exist, with isolated positive/negative fixtures.
No private editor configuration is copied into CI. The existing `codex-tooling`
manifest area already selects this test file. The original failed selection and
diagnostic rerun remain in the CI evidence root under
`publish-worktree/.codex-test-logs/publish-run/` and `publish-codex-diagnostic.log`.

The iOS Firebase project/bundle source contract also reads the ignored local
`ios/Runner/GoogleService-Info.plist`. An isolated checkout without that declared
input fails before its assertions. For authorized local validation, restore the
existing configured file byte-for-byte, record its hash separately from the
tracked-source inventory, and preserve the original missing-input failure.
Do not claim runtime-input equivalence from source hashes alone. The
[group replay preservation receipts](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/group-media-replay-transport/ios-config-input-restoration.json)
record this boundary without logging configuration contents.

## Daily commands

Run from the repository root. `BASE_REF` must name the verified intended
comparison revision. For a pull request, resolve the merge base against its
actual target branch; do not assume the previous commit is the baseline.

```bash
python3 scripts/mknoon_checks.py discover --list-runners
python3 scripts/mknoon_checks.py validate
python3 scripts/mknoon_checks.py plan --mode change --base "$BASE_REF" --local
python3 scripts/mknoon_checks.py run --mode change --base "$BASE_REF" --local
```

`--local` includes staged, unstaged, and untracked changes as well as the committed
comparison. Review both sides of renames/deletions. Omit it only for a clean
committed candidate. Plans report selection reasons, unmapped impact, requirements,
and unknown runtimes. An unmapped behavior change widens checks and remains a
visible gap; unknown does not mean safe.

For a release, resolve `PUBLISHED_REF` from the actual distribution record for
the previous published build. An operator-provided reference is an attestation
that it identifies that build; a newest tag alone is not verification.

```bash
python3 scripts/mknoon_checks.py validate
python3 scripts/mknoon_checks.py plan --mode release --base "$PUBLISHED_REF"
python3 scripts/mknoon_checks.py run --mode release --base "$PUBLISHED_REF" --device-config "$DEVICE_CONFIG"
```

The release selection always retains mandatory checks, including on a
documentation-only diff. Required manual/device evidence is additional work;
passing automated checks alone does not complete release acceptance. Supply
reviewed evidence and the exact distribution artifact with
`--evidence "$EVIDENCE_FILE" --candidate-artifact "$CANDIDATE_ARTIFACT"`.
Repeat `--candidate-artifact` for multiple signed platform artifacts; the optional
`--build-label '1.0.1(117)'` records an intended version, not proof of its contents.
Never use real user conversations, production identities, or production service
credentials for these checks.

The initial routine release target is approximately 20–40 minutes, including
build/setup and tests. Current unknown runtimes remain unknown until measured.
Do not omit essential or high-risk checks to meet the target. Broad affected
directories can legitimately take longer; optimize from measured reports.

An executable run writes `plan.json`, `results.json`, and `summary.txt` in its
new ignored artifact directory (or the explicit `--output` directory). Invalid
plans/prerequisites write `error.json`; discovery writes `inventory.json`.
Keep the files for a run together.
Results separate selected paths, actual completed counts, skips, commands,
duration, exit status, first attempt and diagnostic rerun. Flutter reports its
observed test-event span separately from SDK startup/compilation/shutdown time;
verified SIMS reports supply build durations. Unexecuted builds remain unknown. `PASS`, `FAIL`,
`BLOCKED`, and `NOT RUN` differ; non-success results have nonzero exit codes.
`--only bootstrap,contacts` is a diagnostic subset: omitted selected requirements
stay NOT RUN and cannot produce an overall green result. `--rerun-failed` permits
one host diagnostic rerun and preserves the original failure. Device campaigns
require diagnosis and cleanup review before a fresh invocation; they are never
blindly retried by this flag. Shared reports retain
allowlisted completion facts and raw-output hashes, not arbitrary private logs;
use existing redacted AppDiagnostics/SIMS receipts for product checkpoints.
Flutter and Go `skipped_cases` retain the same hashed case identity as failures
(including the Go parent/package hashes), so an incomplete selection can be
traced back to its source without copying dynamic names or skip reasons into
shared reports. This metadata does not convert a skip into a pass. Parser
contracts cover private-name/reason canaries and retain the blocked verdict.

## Device setup, automation ownership, and recovery

Appium MCP is the default for live UI work: navigation, permissions, notification
taps, lifecycle reproduction, and screenshots. Use the actual MCP tools. Before
adding a custom device harness, identify the concrete assertion that Appium MCP
and existing tests cannot prove. Reuse existing protocol, native, backend, and
media runners for those gaps; their fixture injection and internal observations
are not replaced by a screenshot. Conversely, an API or internal trace alone is
not evidence that the intended UI was usable. If the MCP connection fails,
diagnose that connection before proposing another UI driver. The manifest's
`ui_driver_reason` makes existing campaign exceptions reviewable; validation
requires a nonempty reason but cannot judge its correctness.

When the user reserves a discovered device for another session, record its ID
in the ignored configuration's `reserved_device_ids` list. The wrapper clears
ambient reservations and forwards only that explicit list. SIMS retains raw
discovery and its digest, but removes reserved runtime/AVD aliases from the
execution-available pool. A required additional peer that is then unavailable
uses the existing policy N/A result; an ordinary missing pin, failed discovery,
or conflicting reserved-and-pinned assignment still blocks. This does not boot,
stop, or control the reserved target.

The friends fixture reset must wait on each pinned simulator through
`xcrun simctl bootstatus <id> -b`; it does not need a desktop application named
Simulator. On this installed Xcode, `open -a Simulator` failed after the owned
QA applications were uninstalled, before any friendship scenario started. All
three selected targets were already booted, and explicit boot-readiness probes
passed without installing or controlling an app. The original failure and
cleanup probe are retained in `friends-headless-setup-repair-001/`. The native
recheck passed the first three scenarios, then exposed a separate missing-side
fixture race. Its retained system-message timestamps show B accepting the old
invitation before the replacement arrived; the action poll can finish after
three idle half-second polls while the sender waits ten seconds before resend.
The missing-side fixture now completes the resend phase before starting its
existing acceptance phase. Original final state/contact assertions and deadlines
remain unchanged. Evidence: `friends-missing-side-failure-001/causal-review.json`;
the exact repaired native scenario passed in `friends-resend-phase-native-002/`,
including mutual acceptance and both contact assertions. The full friends owner
remains pending. The copy scenario must also wait for exact system-message
readiness before navigation/snapshot. Its `introduction_action=none` returns
immediately; `poll_cycles` does not wait for incoming copy in that branch.
The failed C snapshot had no introduction/message, while subsequent actual
Appium MCP source and screenshot showed the exact expected copy. The existing
message expectation poll now accepts an explicitly requested `system` transport;
ordinary chat still rejects system rows, and hidden/deleted rows remain rejected.
Both copy phases use their existing poll budgets and unchanged host deadlines.
Evidence: `friends-copy-failure-001/` (first snapshot, MCP source/screenshot,
causal review, and focused failing/passing readiness tests). Broader notification
fixture contracts passed630tests and workflow240 with zero skips. The native
recheck passed all send-copy assertions, then failed external-drive screenshot
output with NSCocoaError513/EPERM. The same pinned `simctl io` screenshot succeeded
on internal `/tmp`; the shell could write the retained destination. The helper
now captures into an owned internal temp directory, moves unchanged PNGs into
the artifact directory, and cleans up on exit. Its exact three-target probe
passed with valid PNGs and no leftover temp directory (`friends-screenshot-path-repair-001/`).
The complete native copy recheck passed in `friends-screenshot-path-native-001/`,
including acceptance/contact assertions and all six screenshots (visually
reviewed and retained with hashes). The full friends owner remains pending.

Split-brain's first acceptance must use the acceptance-only phase. Calling the
send helper there replaced the invitation while B accepted the old ID; the
retained A/C snapshots held the new pending ID. The repaired native scenario
passed the unchanged intermediate split, reconnect, mutual-acceptance and contact
assertions (`friends-split-brain-native-001/`, command 0). Its host sequencing
contract executes the scenario through trace-only device seams and rejects the
original two-send sequence. Workflow 240 and provider 5 passed with zero skips.
The following folded-duplicate send phase exposed another passive snapshot race:
B/C initially recorded no introductions, while the existing four-peer settle
probe later recorded both introductions and one folded item without resending.
Both recipients must gate their send-phase snapshot on both introducers' exact
system messages using the existing 90-cycle budget. Original pending/folding and
terminal-contact assertions remain required. The complete repaired four-peer
scenario passed (`friends-folded-readiness-native-001/`), including both pending
introductions, folded acceptance and exactly one terminal contact per peer.
All 40 intro-runner preservation tests, 240 workflow tests and five provider
contracts passed. Original evidence: `friends-folded-readiness-failure-001/`.
Full owning checks remain pending.

The group multi-party integration harness must register `testWidgets` before
awaiting platform runtime configuration; put asynchronous configuration in
`setUpAll` and keep registration-time names independent of late runtime fields.
The retained source039 attempt registered too late (`Can't call test() once
tests have begun running`), producing 109 preidentity scenario failures. Also,
Flutter 3.47.2 ignores the deprecated `drive --no-build` flag for prebuilt launch;
pass the attested `--use-application-binary` path to reuse the prepared iOS app.
The focused launch and criteria contracts passed. Native GE-001 then passed
with all three role identities/verdicts in 87 seconds and no Xcode rebuild in
any role log; the complete owning group sweep remains pending. Evidence: `.codex-test-logs/all-tests-y227gs8x/`
`restart-checkpoint-016-major-source039/group-sweep-first-failures/` and
`source040-host-group-repair/`.

Muted-group header targeting must prefer the localized accessible info-button
label. The retained physical Android tree exposes `content-desc="Group
information"`; selecting only unlabeled buttons returned null before the mute
assertion. The captured-shape regression failed before the fix, and all 70
muted-group host criteria tests passed afterward. The fresh complete native
campaign then passed all three scenarios and six assertions; its unchanged
report verified after the generated-cache quarantine described below. The
original failure receipt's `lastUiDump.path` is relative to the capture directory,
not the checkout. Evidence: `restart-checkpoint-016-major-source039/`
`muted-group-first-failure/` under the same ignored run root.

The private-media outbox restore runner must retain a bound diagnostic before
its existing network/app restoration. The first phase-two sender failure lost
the endpoint reason during cleanup. Failure receipts now map only exact fixed
harness messages to diagnostic codes; unknown errors retain their type with an
`unknown` code, never their message. The host retains only the run hash, role,
phase, expected status, and bounded diagnostic tokens. These files are explicitly
`diagnosticOnly`, not success artifacts. The privacy regression reproduced the
missing code; all 33 endpoint/conversation/wiring/connectivity tests passed.
The original device failure's cause remains unproven until a fresh native run.
Evidence: `source042-private-outbox-diagnostics/` under the same ignored run root.

The whole-suite source digest excludes generated `__pycache__/*.pyc` files,
while retaining Python source and intentional bytecode fixtures outside those
cache directories. A parser diagnostic generated one cache during a muted-group
campaign; all three native scenarios passed, but the original verifier rejected
the cache-only digest change. Quarantining that sole generated file made the
unchanged report verify successfully. The cache was restored and the original
rejection retained. The digest regression failed before the fix; all 27 cache,
report, and filesystem-verification tests passed afterward. Evidence:
`source040-muted-dns-retry/muted-group/source-digest-causal-probe.json` and
`source041-token-source-digest-repair/` under the same ignored run root.

The Docker host-tool bridge must pass its random token as `--token=value`.
`secrets.token_urlsafe` can start with a hyphen, which argparse rejects when the
value is passed as a separate argument. The existing Docker-update contract now
forces that token shape without changing production randomness; it reproduced
the failure and passed after the fix. The first owning SIMS contract attempt
remains 53 passed/one failed until its full recheck completes.

An isolated checkout must retain the SIMS shell adapter used by its contracts,
even when `.claude/skills/sims/scripts/run_with_devices.sh` is ignored by Git.
Restore the exact repository copy rather than dropping the adapter contracts.
Physical-iOS group media custody also requires the configured fixture driver to
resolve inside the execution checkout; an identical executable in the main
checkout is rejected. These are preparation requirements, not device proof.

Before a long run, resolve available targets and use a fresh wrapper invocation
with the intended source, resolved SDK, isolated configuration, and artifact.
`scripts/device_campaign_preflight.py`, called by `scripts/mknoon_checks.py`, adds
the following setup checks before launching a registered device campaign:

- Private per-device leases coordinate wrapper processes across checkouts for
  the same workstation user, independently of checkout-specific build locks.
  They last through execution and report verification and release on process
  exit. These leases do not coordinate an older launcher or external Appium
  client; the operator must also establish who owns each target.
- For pinned Android targets, a bounded, read-only activity-process dump checks
  for active instrumentation. An active owner blocks the campaign. Android
  `dumpsys` can print an internal `DUMP TIMEOUT` and still exit zero; a header
  alone therefore cannot establish idle automation. The reviewed parser rejects
  internal errors and requires the exact opening process-dump header, a unique
  process-ready state record, and the final `mForceBackgroundCheck` record. Empty,
  truncated, or unfamiliar output remains unavailable evidence. End only your
  own Appium session through MCP before handing off; preserve foreign sessions.
  iOS automation ownership still needs an explicit check outside this Android
  probe.
- Audited `--list-scenarios` entry points check Dart startup and native-asset
  preparation without entering a device journey. A zero exit without the
  expected scenario is insufficient. This addresses the previously observed
  macOS SQLite hook problem: an attested Android APK does not warm the host Dart
  dependency. It does not certify every dependency of every campaign.
- Setup failures report a checkpoint and recovery guidance. Shared receipts
  retain probe status, timing, and output hashes, not arbitrary device dumps or
  dependency output. Reproduce the specific probe for private diagnosis; redact
  any retained raw evidence under `.codex-test-logs/`.

The agent should repair known reversible setup problems within existing
authorization, recheck, and continue. Examples include preparing pinned host
dependencies and releasing its own stale automation session. Investigate an
unknown failure with the smallest relevant probe; do not repeatedly rebuild or
rerun the entire campaign. Ask the user only when information, access, or new
authorization is genuinely required. A failed prerequisite never authorizes
killing a foreign process, changing credentials, broadening network access, or
weakening a test. Prior approvals apply only within their actual scope.

On the available iPhone 11 / iOS 26.5 with Xcode 27, the pinned Appium MCP
runtime created an XCUITest session and read device information and UI elements
with `appium:xcodeOrgId=397R9Q4WMX`, `appium:xcodeSigningId=Apple Development`,
`appium:updatedWDABundleId=com.facebook.WebDriverAgentRunner`, and
`appium:wdaLaunchTimeout=420000`. Preserve these signing settings; do not mix
this path with `appium_prepare_ios_real_device`. After an Appium QA runtime
reinstall, run `bash docker-ws/repair_appium_ios_real_device.sh` as instructed by
the supplied repair procedure. No reinstall or preparation call was needed for
the observed successful session. Session deletion and an empty MCP session list
did not stop its surviving WDA `xcodebuild` child; verify ownership and end only
that child before handing the device to another campaign. The receipt at
`.codex-test-logs/all-tests-y227gs8x/appium-mcp-transport-001/readiness.json`
proves automation readiness, not Mknoon behavior or a signed candidate.

The user authorizes unlocking the connected test iPhone through actual Appium
MCP when needed. Read `IPHONE_PIN` locally from the ignored repository `.env`;
never copy its value into tracked code, command arguments, reports, screenshots,
or retained tool output. Inspect the lock screen, use Appium's unlock action,
and enter the PIN through the observed passcode UI if required. Preserve the
signing configuration above. A native and WDA automation-enable timeout was
cleared after the user entered the password; the unchanged native diagnostic
then reached its notification assertion (`ios-card-probe-003.xcresult`).
Appium also created a session and read the UI again (`ios-card-probe-004/`).
This recovery is distinct from the installation stall below.
If the automation-enable failure returns, an already-unlocked-since-boot flag
alone does not establish XCTest readiness. The later `iphone-fresh-runner-001/`
probe rebuilt WDA successfully with the same signing team and bundle ID and
`useNewWDA=true`, but its launched runner still timed out enabling automation.
The MCP session list was empty afterward and no Xcode child remained. No PIN
was used: the MCP unlock action requires an active session, and this failure
occurs before one exists. Keep this failure separate from signing/install errors.
The subsequent `iphone-device-syslog-probe-001/` capture confirms that the
phone's test manager receives the session, authorizes the WDA process and enters
`AutomationMode` before the same timeout. `devicectl` reports no passcode required.
A subsequent read-only CoreDevice screenshot captured during the same MCP
session startup shows the actual OS prompt: “Enter iPhone Passcode for ‘XCTest’ —
Enable UI Automation.” This is separate from ordinary screen unlock and from the
Developer settings toggle. It appears before Appium has a session, so Appium
cannot enter the PIN at that boundary; the device owner must authorize the
visible XCTest prompt. A screenshot after the timeout shows the unlocked home
screen instead, so inspection must occur during startup. Xcode 27's
`devicectl device capture screenshot` can capture this state without an XCTest
session; the older screenshotr service did not work on this device. Evidence is
in `iphone-automation-screen-probe-001/automation-gate-screen.private.png` under
the same ignored run directory. This capture is a bounded setup diagnostic,
not an alternative UI automation driver. The optional RemoteXPC tunnel warning
is not evidence of the observed authorization failure. The redacted triage note
remains advisory, and no PIN was read or used.
After the user restarted the phone, `iphone-home-screen-retry-001/` still
captured the authorization prompt and timed out. The next same-signed attempt,
`iphone-home-screen-retry-002/`, created an Appium session and read the live UI
successfully without a PIN being read or entered by the agent. The exact
authorization-state change is unknown; do not attribute it to a signing repair.
This receipt establishes automation readiness only. At that point the main
`com.mknoon.app` package was absent and required candidate installation.

A separate CoreDevice installation stall can occur after XCTest has already
enabled automation. In `ios-group-deployed-006/`, the first selector waited for
Xcode to complete Mknoon's launch. A clean WDA rebuild then stalled at install,
and native installation of that same valid signed 2.8-MB WDA bundle timed out
at sixty seconds. The supplied WDA cleanup and a developer-image remount did
not resolve it. After confirming no active XCTest/Appium owner, restarting the
same-user Mac CoreDevice XPC service changed the unchanged native install to a
2.034-second success; the next actual Appium MCP session also started
successfully with the original signing settings. Retain the failed attempts,
check ownership before any service recovery, and rerun the small installation
probe before another campaign. This establishes environment recovery only;
it does not pass notification delivery. Evidence is in
`.codex-test-logs/all-tests-y227gs8x/ios-group-launch-probe-001/` and
`ios-group-launch-probe-002/`.

The iOS group notification campaign must settle the normal app's notification
permission before waiting for push-token registration. Its existing preparation
selector already handles the identified permission alert; running that selector
after the registration wait deadlocked a fresh normal install at setup. In
`ios-group-deployed-007/`, three setup XTests passed, but the normal app then
waited on notification authorization. Actual Appium MCP inspection confirmed
the alert, and allowing it produced three recipient-owned
`relay_push_registration_success platform=ios` events in the same app process.
The capture now runs existing notification preparation before the unchanged
three-minute registration wait. Evidence is retained in
`.codex-test-logs/all-tests-y227gs8x/ios-registration-probe-001/`.
The device log archive established this causal result. Both default and legacy
`idevicesyslog` live-stream probes initially returned only connection markers.
Ordinary failure cleanup omitted the campaign's iOS logger, leaving an orphan
with the exact command and start time of the normal-install boundary. After
ending that owned process, live system events resumed; relaunching the normal
app through Appium MCP produced fresh live registration success in 4.096 seconds
(`ios-registration-probe-002/fresh-registration-verdict.json`). Ordinary cleanup
now closes the iOS logger and attempts every cleanup action while preserving
the first failure. The permission and logging probes are not delivery proof;
an owning notification campaign rerun remains required.

Successful public NSE proof records intentionally have empty `details`; the
private `kind` field is not exposed by `nsePublicProofPayload`. The next group
campaign (`ios-group-deployed-008/`) passed registration and native inventory
for the exact expected message, but its old log parser still required that
private field and timed out. The retained device archive shows one receive,
one successful decrypt and an authorized active content handoff. Group capture
now accepts the structured public success marker only after the existing native
inventory validator binds the expected phase, nonce, device and group/event
hashes; absent or mismatched native phase still rejects it. Legacy typed markers
remain supported, with exact kind boundaries. Production logging is unchanged.
Evidence is retained under `ios-nse-probe-001/` in the same run directory.

The group notification setup stops the Android app before clearing its private
entries. An in-place install can restart background writers: attempt
`ios-group-deployed-009/` failed deleting `shared_prefs` while the app was still
running. Stopping that owned process made the exact deletion succeed and the
path remain absent (`android-reset-probe.json`). This reset precedes the push
delivery window; the delivery lifecycle still forbids force-stop.

On the same iOS/Xcode combination, a descendant query ending in `firstMatch`
escaped an index-bound SpringBoard notification container. The group tap test
counted an unrelated card as matching the expected title and body, alongside
the actual Mknoon card. The native diagnostic, recording and actual Appium MCP
hierarchy establish the mismatch (`ios-card-probe-003.xcresult` and
`ios-card-probe-004/selector-review.json` in the same run directory). Match both
texts against one resolved `XCUIElementSnapshot` tree per card instead. The
unchanged exact-one-card and cold-open assertions then passed on the retained
notification (`ios-card-probe-005/result.xcresult`, 16.340 seconds), with the
unrelated card rejected. This focused pass does not replace a fresh full
message-and-reaction campaign.

The subsequent campaign passed fresh message inventory and tap, then exposed a
reaction-fixture binding defect: the Android observer emitted the expected
collapse hash only for messages, so the host sent an all-zero sentinel for the
reaction. The existing production `boundedReactionEventIdentity` formula,
applied to the recorded reaction event, matched the actual delivered request
hash exactly. Re-observing that retained card with the correct hash passed the
unchanged full-horizon native contract (`ios-group-deployed-011/` and
`reaction-collapse-native-probe-001/`). The fixture observer now reuses that
identity helper for reactions too; the host requires the hash in both phases.
The two-phase artifact validator also uses the existing current native receipt
validator instead of its stale v1 shape, preserving exact identity, source,
duplicate and deadline requirements. Host regressions retain rejection of the
old schema, zero collapse hash and a reaction bound to the message collapse ID.
The fresh complete campaign `ios-group-deployed-012/` then passed both native
inventory windows, both notification taps and final artifact validation, with
seven actual XCTest invocations passing and no failed or skipped cases. That
campaign closes these two defects on its recorded candidate; later candidate
changes still require the affected owner checks.

The announcement campaign's legacy launch also needs the existing signed setup
profile and permission selector before identity collection. Its profile build
previously omitted the identity-export permission, while a Local Network prompt
remained visible. Ordinary host environment variables were then absent from
XCTest: the unchanged compiled selector passed after forwarding them through
`TEST_RUNNER_`. Keep its XCTest app in Profile and use `ENABLE_TESTABILITY=YES`,
as the central builder does, so `RunnerTests` can import the app module. The
focused Profile probe passed, allowed Local Network, and exported an identity
whose digest matched the native/Dart readiness receipt. Evidence is under
`.codex-test-logs/all-tests-y227gs8x/announcement-profile-probe-001/`; this setup
proof does not establish announcement reaction delivery or tap behavior.

Announcement evidence must accept the relay's current `outcome=success` provider
records and the NSE's privacy-safe `FLOW_PROOF` records. Profile builds do not
emit Dart debug flow events; cold tap proof therefore requires XCTest to assert
the app is stopped before tapping, then prove the group and target are visible.
One card observation may appear once on stdout and once through NSLog, with
identical content; repeated stdout observations or conflicting mirrors fail.
The original `ios-announcement-deployed-004/` ran five passing native cases and
the real SQLCipher probe but failed its stale artifact reader. Keep that failed
result. Its live command journal subsequently gained cleanup records, breaking
the earlier artifact checksum. Artifact writers now retain a separate immutable
capture journal while preserving the full live journal for cleanup review.
The fresh `ios-announcement-deployed-006/` passed all five native cases, the
physical SQLCipher probe and final artifact validation after cleanup. Its
capture journal still matched the recorded bytes and digest. Successful
cleanup now also flushes the separate live journal, matching failure-path
retention; the immutable capture snapshot remains the artifact reference.

The full inventory binds the eight announcement/chat XCTest methods to exact
native receipts from those existing campaigns. Their source-declared case
counts must match the raw XCTest log exactly (five announcement invocations,
seven chat invocations, including both preparation/tap windows). Missing,
duplicate, failed, skipped or unexpected cases cannot be replaced by a parent
completion marker. This avoids standalone runs of fixture-dependent methods
after the campaign has consumed their notifications; it does not reuse a
historical run as evidence for a new candidate.

The earlier recommendation to reset Android group fixtures with `pm clear` is
superseded: it violates the retained Keystore-state contract. Guarded Android
children already bypass their own reset, but standalone reset paths must also
preserve Keystore entries. They now stop the app, validate and remove its private
file inventory, then reinstall the same APK to repair package-managed cache roots
before staging identity inputs. The existing no-clear source sentinel exposed
the earlier repair in `first-wake-shared-guard-change-001/` (62 other state-guard
tests passed); its focused post-fix assertion passes in
`group-reset-keystore-green-001.log`. Fresh group campaigns remain required to
verify startup with this reset. The historical recovery observation remains: in
`ios-announcement-deployed-005/`, the unchanged kernel started a VM with no
application isolate and Appium showed a blank screen; restarting preserved the
failure. Appium's app-data clear followed by the same setup input produced a
valid identity and the ready Orbit screen. The precise retained platform state
was not identified. Keep the original failure and the bounded causal probe in
`announcement-android-startup-probe-001/`. The fresh owning run
`ios-announcement-deployed-006/` completed setup and passed the full scenario.

A full adapter that fails before launch now retains the numeric OS error code
without copying exception text or private paths into the shared report.
`media-stable-id-ios-continued-001/` predates this diagnostic and has no raw
startup error, so its exact cause is unproven. The system volume independently
ran out of space while the external workspace had ample room. Inactive test
recovery data was relocated with verified file hashes; this project's inactive
DerivedData is preserved externally with its original path linked to it.
Repeated SDK-cache write failures also required moving the idle Flutter 3.47.2
engine-artifact cache externally. All 571 files, their modes and links were
verified before replacing the original cache path with a symlink; SDK source,
Dart SDK and the shared Gradle daemon's source-directory watchers stayed in
place. Flutter 3.47.2 / Go 1.25.0 and the notification/recovery host checks passed
afterward (`flutter-engine-artifacts-relocation.json` in the retained directory).
When resuming after a host restart, revalidate saved network environment settings.
The retained run environment contained an expired localhost `https_proxy`; Xcode
package resolution failed before compilation. Removing that stale setting and
successfully rerunning `xcodebuild -resolvePackageDependencies` restored the
central production iOS build. The failure, probe and attested preparation result
are retained in `restart-20260923-spm-probe-001/`,
`restart-20260923-spm-probe-002/` and `ios-production-central-build-004/` under the
same all-tests run directory. Build preparation alone proves no device scenario.

Prepare CocoaPods before freezing an isolated macOS candidate. Its Go-binding
script phase serializes absolute input paths into the tracked Xcode project;
first preparation rewrote the main-checkout prefix and equivalent path quoting
for the isolated checkout. The parsed project was otherwise identical, and
substituting that one file's preimage reproduced the original candidate digest.
The wrapper correctly invalidated the first `FEED_INIT` assertion pass for source
drift. A fresh owning rerun passed on the stable prepared candidate with no drift
gap (`restart-macos-input-path-review-001.json` and
`restart-checkpoint-003-feed-init-stable/`). Preserve the invalidated original;
do not exclude the tracked build configuration from candidate fingerprints.

Future test temporary files use a short, private external `TMPDIR` outside the
checkout. A temporary root beneath the checkout makes nested `dart run` discover
the app's ancestor `pubspec.yaml` and execute native build hooks inside otherwise
isolated host fixtures. The unchanged benchmark boundary test passed with only
`TMPDIR` moved outside the package tree (`external-temp-package-probe-001.log`).
Retained paths and verification are in
`.codex-test-logs/all-tests-y227gs8x/retained-system-temp-recovery-001/`.

The Android keepalive campaign's warm-dial terminal can precede the production
disconnect callback. A cached dial success alone does not prove the dropped-send
precondition (`connected=false`). The campaign now observes the latest exact
target `[CONN]` callback within the same 16-second warm window and retains only
readiness booleans, the terminal name and elapsed time. It does not force a
disconnect or change the send assertions. A fresh physical Android/emulator
run remains required to establish its runtime timing. The
affected host check passed all 195 cases without skips in
`keepalive-readiness-change-001/`; the original
`checkpoint-006-major` failure remains retained. TC-187-20 preserves healthy
connection reuse even when a stale keepalive drop mark exists.

Android activity checks must match the complete application ID. A word boundary
after `com.mknoon.app` also matches the sibling `com.mknoon.app.ui25proof`.
The `reaction-head-deployed-001/` campaign timed out at its stopped-app boundary;
the retained post-cleanup native snapshot in `reaction-head-stop-probe-001/`
has no target PID but contains the sibling's activity. Keep both attached and
resumed checks exact, and preserve the rejection of a real target activity.
The fresh owner `reaction-head-deployed-002/` passed the complete head-provenance
campaign and its artifact validation on the same Android pair. The original
failure and the separate sibling app remain preserved.

The central-prebuilt head campaign now observes SQLCipher at its existing five
unread UI boundaries through the existing intro file channel. The debug/E2E-only
`direct_notification_state_observe` action performs SELECTs in one transaction;
it cannot drain the inbox, navigate, or mark messages read. Requests bind the
run, nonce, phase, contact and unique message markers; receipts hash identities.
The campaign rejects mismatched counts, premature reads and changing message
identities. Six observer tests and 74 bridge tests passed in
`direct-notification-observation-shadow-001/host-applied-001.log`; native evidence
for this extension is still required. A head artifact without the five SQL
receipts does not satisfy the strict TC-16 database evidence requirement.

Review triage dry-run payloads even when credential checks succeed. Android
serials can occur in failure prose and JSON as well as `adb -s` arguments.
The first `reaction-head-deployed-001/triage-dry-run.private.log` exposed that
redaction gap and was not sent. The redactor now covers those serial forms;
the advisory result remains separate from actual test and cleanup evidence.
Native address-update logs also contain `/ip6/` relay multiaddresses outside
`MKNOON_RELAY_ADDRESSES` assignments. The background-reconnect dry run exposed
that gap and was not sent; its advisory used a reviewed, address-free state
excerpt instead. Redact full, compressed and IPv4-mapped IPv6 multiaddresses
while preserving timestamps and transport/port details. Credential-pattern
checks alone do not establish that device and relay identifiers were scrubbed.

Keep campaign-specific readiness checks in their existing runner: complete
fixture setup, prove the required authenticated peer round trip and provider
path, and bind evidence to the actual source/configuration/artifact. A generic
setup pass does not establish those facts. Capture state before fault injection
and verify owned-state restoration afterward, including radios, permissions,
app state, and any temporary relay changes. Follow the user's explicit retention
instructions for authorized changes. Never copy private PIN/unlock helpers into
shared tooling or put secrets in a report.

After a launched device campaign fails or blocks, the wrapper preserves the
first result, sets `cleanup_review_required`, and leaves later device campaigns
`NOT RUN`. It does not automatically retry devices even with `--rerun-failed`.
The agent must diagnose the failure and verify cleanup before a fresh invocation;
the wrapper cannot certify that human/agent review occurred. Keep the original
failure visible when recording a later diagnostic success. Identify timing
problems with existing causal tests and monotonic timing; do not move assertions
or lengthen deadlines merely to obtain a pass.

The automation-conflict and host-hook causes are supported by the existing
Android audio ownership and SQLite dependency entries below. The new guard's
host contracts are in `scripts/test/device_campaign_preflight_test.py` and the
wrapper execution tests: they use disposable processes and mocked observations,
not live phones. The timeout/partial-frame causal regression, including a
source-supported complete idle frame, is retained with the
[reviewed parser repair](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/preflight-timeout-fix/files.json).
At source `a98dce09`, the exact [workflow selection](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/preflight-timeout-fix/workflow/results.json)
passed 86 tests and the separate [codex-tooling selection](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-codex-tooling/results.json)
passed 249 tests across eight files, both with no failures or skips. Each was a
diagnostic subset: omitted checks stayed `NOT RUN`. A later
[bounded live probe](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/preflight-timeout-fix/live-idle-proof/receipt.json)
confirmed complete idle frames on the available physical Android and emulator,
both API 37, using parser `13f9e6ca`. It required no unlock and restored owned
automation afterward. This establishes format compatibility for those observed
targets; campaign recovery still requires its own execution evidence.

The Android app-state guard must distinguish an unavailable package lookup from
an absent package. A timed-out `pm path` was previously converted into empty
output, allowing a contradictory absent/running snapshot. Host-process failures
now block capture; empty or failed package lookups require an independent,
successful package inventory. Capture rejects package/process disagreement
before force-stop. Foreground detection matches the exact application component:
`com.mknoon.app.ui25proof/com.mknoon.app.MainActivity` is not `com.mknoon.app`.
The existing recovery decoder already rejected inconsistent manifests and remains
authoritative. The `android-state-guard-contract` selection preserves these
regressions and original backup/restore contracts. Evidence is retained under
`.codex-test-logs/all-tests-y227gs8x/`: the original cancelled checkpoint 005,
`guard-foreground-red.log`, `guard-foreground-green.log` (66 passing tests,
including legacy binding), and `live-guard-probe-repaired.json` with verified
capture/restoration on the connected Pixel 6 and existing API 35 emulator.
This does not establish restoration of the earlier API 37 emulator's original
private data; its incomplete backup remains an unresolved recovery limitation.

The TC-07 background-crypto campaign has a separate attached-process activity
parser. It must also match the component's exact package, including when a
sibling package uses `com.mknoon.app.MainActivity` as its activity class. Its
former substring match rejected quiescence while only `com.mknoon.app.ui25proof`
was attached. `reaction-durable-deployed-005/` retained both setup and cleanup
failures, with zero provider sends; APK bytes and notification permission were
restored. The existing parser contract reproduces that failure and preserves
rejection of actual resumed, pausing and process-attached target activities.
The repaired parser distinguishes both apps in the retained physical snapshot
(`crypto-quiescence-probe-001/parser-review.json`). Its contract test is included
in `notification-payload-harness-contract`.

FCM token freshness in that campaign uses a timestamp produced on Android.
Validate its age against a fresh UTC read from the same pinned phone, preserving
the existing nonnegative, at-most-two-minute window. In
`reaction-durable-deployed-006/`, a valid bundle failed the former host-clock
comparison. The bounded setup-only capture in `crypto-bundle-probe-001/` had no
bundle contract errors but appeared 848 milliseconds in the future on the Mac.
The parser still rejects genuinely future or older-than-two-minute observations;
the runner now obtains Android's subsecond UTC time before checking freshness.
The fresh `reaction-durable-deployed-007/` crypto owner passed one reaction,
twelve ordinary-message cases and three authorization-rejection cases, with
sixteen successful provider sends and verified fixture, APK and permission
restoration. The owning artifact assertion passed after cleanup.

The first durable direct-reaction publication cannot require an existing
reaction completion row: SQL transaction B writes that row only after the native
notification effect. When an exact READY display-outbox entry is present, final
background validation uses its event/reaction/actor tuple and current canonical
message/reaction state; the enclosing final barrier still reloads the exact
READY row last. Existing completion rows, when present, must match. Callers
without a READY entry still require the completion row. Deletion, privacy,
read-acknowledgment and authority checks remain in force.
The existing real-SQLite test previously preseeded the completion row and missed
this circular requirement. Removing that seed reproduced `unknown` instead of
`keep` (`durable-reaction-first-publication-red-001.log`); the repair passed
1,219 affected push tests, 460 recovery tests and nine SQL handoff tests.
The physical Android durable-reaction owner in `reaction-durable-deployed-007/`
then proved `osPosted`, no fallback and no deferrals, exact reaction copy and a
conversation tap against deployed relay SHA `8ce3cd49a8562417e73748abc6a0cda1744e95499857b281be6f5cea8aa913c3`.

Normal-APK restoration can restart the campaign's Android app. Its cleanup must
force-stop that exact package and verify process/activity absence both before
installing the replacement and before returning. Stopping only after install
left a queued System UI relaunch in `reaction-durable-deployed-008/`, observed
174 milliseconds after the stop. Otherwise the following first-wake campaign correctly rejects a live
app before backing up private data. The first failure and native PID snapshots
are retained in `reaction-durable-deployed-007/` and
`first-wake-initial-state-probe-001/`; the corrected cleanup requires a fresh
sequential durable-reaction/first-wake run.

Contact and wake setup commands are consumed before their first receipt. After
the matching completed receipt, leave that ready peer running for the next
exchange. A redundant cold relaunch raced the next peer's authorization send in
attempt 008: its direct dial failed before the receiving listener started, and
the wake token arrived through inbox recovery later. The original 60-second
persistence deadline remains unchanged. The redacted event timeline and native
logs are retained in `reaction-wake-setup-probe-008/`; a fresh owning device
campaign must verify the removed restarts. The triage note is advisory only.

Attempt 009 passed the durable-reaction owner and the subsequent first-wake
stopped-app baseline capture, closing those setup and handoff repairs. First-wake
then retained its notification card but failed private-data restoration. Streaming
archive comparison found five changed cache-directory modes on the emulator;
the physical phone also lost 38 cache members after the reinstall used to repair
package metadata. This is covered by the existing `AndroidAppStateGuard`, which
preserves privileged cache directories, replays cache contents after metadata
repair, and verifies a canonical full-archive digest. First-wake now reuses that
guard, retaining its 256 MiB backup limit, idle/empty-notification precondition,
and post-restoration artifact boundary. Its artifact assertion requires entries
for both exact devices. The first failure and metadata-only comparison remain
in `reaction-durable-deployed-009/` and `first-wake-restoration-probe-009/`;
the fresh `reaction-durable-deployed-010/` owner passed in 361.163 seconds. It
required one actual notification from the stopped Profile/AOT receiver, emitted
no measurement-only receipt, and verified both exact devices' package, private
data, permissions, empty notification state and idle process before deleting
the host backup and writing PASS. The deployed relay SHA remained `8ce3cd49a8562417e73748abc6a0cda1744e95499857b281be6f5cea8aa913c3`.

Android `am start -W` may report the equivalent abbreviated production component
`com.mknoon.app/.MainActivity` and `Status: timeout` while the exact app process
is alive. The reconnect campaigns share one launcher that checks component
identity and the live PID; an isolated package may not substitute `.MainActivity`
for the actual `com.mknoon.app.MainActivity` class. Identity readiness retains
its own unchanged deadline. The live causal probe and the 63 guard/10 launcher
checks are retained in `.codex-test-logs/all-tests-y227gs8x/physical-launch-probe.log`
and `repair-device-run-001/`. One-second process-runner fixtures use shell
processes so their kill/reap and inherited-pipe assertions do not accidentally
measure cold Dart compilation under load.

## Device configuration and evidence

Keep `DEVICE_CONFIG` in an ignored local artifact path. It is an operator
attestation of isolated fixtures, accounts and services, with live discovered
IDs; it must never contain tokens or production credentials. Example structure
(replace the example IDs and fixture reference with actual isolated setup):

```json
{
  "isolated_test_environment": true,
  "fixture_reference": "artifacts/release-fixtures/setup-receipt.json",
  "devices": {
    "android_physical": "discovered-usb-id",
    "android_emulator": "discovered-emulator-id"
  }
}
```

Add `ios_simulator` or `ios_physical` only for applicable available platform
checks. `python3 scripts/mknoon_checks.py devices` records discovery; the raw
platform commands in the signed checklist remain useful for setup.

The evidence JSON uses `baseline` equal to the resolved baseline in the current
plan, `source_sha256` and `rules_sha256` from that plan's `identity`, an
`artifact_sha256` mapping of each signed artifact basename
to SHA-256, and `checks` keyed by the manifest's manual check ID. Each check
record contains `status` (`PASS`, `FAIL`, or `BLOCKED`), `reviewer`, `observed_at`,
`assertions_observed` (the exact assertion IDs from the selected check), and
`receipts` containing `{ "path": "artifacts/...", "sha256": "..." }`.
An early manual failure may record `failed_assertion` naming a required assertion
and a receipt without inventing results for the subsequent assertions. A PASS
still requires all required assertion IDs. Use
`shasum -a 256 "$CANDIDATE_ARTIFACT"` and the same command for each receipt
to calculate hashes. The wrapper verifies identity, required assertion IDs and
receipt bytes; it does not independently interpret a screenshot or establish
that an operator's attestation is true. Retain the reviewed original receipts.
Do not fabricate evidence merely to fill the schema.

## Full regression and CI

The full inventory routes direct-media custody, production one-to-one audio,
and fixed-wake recovery through their existing outer fixture adapters. These
adapters start the local service before compiling the relay address into the
APK. The main SIMS partition excludes those three scenarios and their dedicated
build rows; full-inventory validation requires an alternate owner for every
excluded row and verifies that command flags match the declared partition.
Partition metadata survives binding and report verification, and a filtered
SIMS plan cannot claim release eligibility. The current full plan records the
complete check and obligation counts. The routing repair passed 182 workflow tests
and all 192 SIMS host tests in
`.codex-test-logs/all-tests-y227gs8x/fixture-routing-run-001/`; these host results
do not substitute for execution of the fixture-owned device scenarios.

A completed host suite with recorded skips remains BLOCKED, including its
coverage obligations, but does not prevent independent device campaigns from
executing. Explicit dependencies still require PASS; assertion failures,
timeouts, missing completion/files, and zero-test runs still stop dependent
device work. The fixed-wake adapter uses its existing `com.mknoon.app` FCM
profile with the app-state capture/restore guard; a disposable package without
a matching Firebase registration cannot establish production delivery.
These contracts passed all 185 workflow tests in
`.codex-test-logs/all-tests-y227gs8x/host-readiness-repair-001/`.

The relay integration subprocess entry point returns during ordinary discovery;
its parent tests still launch it with `GO_WANT_REDIS_HELPER=1` and validate the
real child operations. A helper-only discovery skip was incorrectly blocking
full coverage. The owning integration package completed 1,543 reported tests
with no failures or skips in `host-fixture-closure-001/` under the same run root;
that count includes the helper entry point, not an extra product scenario.

Project-memory real-corpus tests accept `PROJECT_MEMORY_TEST_MEMORY_DIR` for an
existing external fixture at a different host mount; the production default path
assertion remains independent and unchanged. Absolute provenance paths count
against recall's fixed budget. On this Mac, the longer home path displaced Q8's
required facts; replacing only that prefix in a diagnostic graph restored the
answer (`memory-path-budget-probe-001.json`). A private temporary copy of the
existing 100 files, verified byte-for-byte with modification times preserved,
passed all 22 original tests without raising budgets or changing expectations
(`memory-path-fixture-probe-002.log`). Keep that fixture alive for the whole run
and retain its provenance manifest; never synthesize memory facts.

The audio oracle requires the existing production-audio fixture to be ready
before the oracle starts. Starting it after the NSE-lite check was too late
in the full schedule; the original missing-credentials failure is retained in
`full-stable-001/` under the same run root. A ready-first retry passed all 15
oracle tests and verified fixture teardown and private credential removal.
Do not extend issued credential lifetimes or synthesize credentials to repair
this ordering problem.

The background-push-crypto Robolectric class now explicitly selects SDK 34,
matching the bundled Robolectric 4.13 runtime. Its default inherited SDK 36
failed before any test body (`targetSdkVersion=36 > maxSdkVersion=34`). The
three unchanged plugin/bridge assertions pass with the explicit test SDK in
the readiness run above. Production SDK settings are unchanged; these mocked
bridge tests do not establish live device cryptography or notification delivery.

The notification runner's no-device listing can begin with repeated
`Running build hooks...` progress text without a newline. Preflight removes
only that exact leading text before matching a complete scenario-ID line;
failed commands, timeouts, arbitrary prefixes and missing scenarios still block.
The preflight and platform-binding repairs passed 188 workflow tests and the
existing 10-case connectivity-launch contract in
`.codex-test-logs/all-tests-y227gs8x/platform-preflight-repair-run-001/`.

Fixed-wake device observation must capture the live notification dump alongside
the independent sender/recipient log reads, and collect slower relay diagnostics
after observing the generic card. Fast warm recovery can retire that card in
about a second; serial sampling missed its entire lifetime in
`notification-recovery-repair-001/`, even though ingress, custody and recovery
had succeeded. Keep the original two-minute observation deadline and exact
opaque +1/rich +0 route assertions. The concurrent-read helper also timestamps
the actual dump completion and propagates every failed read. All 538 notification
contract tests passed in `notification-observation-host-run-002/`, including a
held-log regression; the fresh `notification-recovery-repair-002/` passed all
six device assertions with independent report verification and state restoration.
These paths share the run root above; the original failure remains retained.

The swipe-back and group-conversation polish proofs require the real iOS
binding. Both legacy catalogs pin swipe-back to `ios-simulator-a`; the full
catalog also pins group polish there. A source comment referring to another
test is not execution ownership. The original Android swipe-back failure is
retained in `full-stable-002/` under the same run root. The unchanged proofs
passed all three swipe-back and five group-rendering cases on the available
iPhone 17 Pro / iOS 26.5 simulator in `ios-platform-repair-probe-001/`, alongside
the strict analyzer gate. Flutter's recursive extended-attribute cleanup can
take several minutes before Xcode starts; a booted simulator on its home screen
during that preparation does not establish that a test has launched.

The project-memory suite deliberately pins its external fixture at
`/claude-home/.claude/projects/-workspace/memory`. On this macOS host the
existing directory is under
`~/.claude-docker-home/.claude/projects/-workspace/memory`. Mounting that real
directory read-only at the expected container path passed all 22 existing
tests with no skips (`project-memory-real-fixture-001.log` under the same run
root). The five skips from the original host invocation remain in its report;
this separate fixture verification does not rewrite the canonical full result.

Preview without running the long suite, then run only when explicitly intended:

```bash
python3 scripts/mknoon_checks.py full --plan
python3 scripts/mknoon_checks.py full --base "$BASE_REF" --device-config "$DEVICE_CONFIG"
```

Use a clean isolated checkout; add `--local` only for an intentionally recorded
working-tree candidate. Full planning records the current bytes without starting
product tests. It returns exit 2 when reconciliation finds uncovered or manual
obligations; the complete `plan.json` remains available for review. Execution
without a device config can run host selections, while campaigns stay blocked.

```bash
python3 scripts/mknoon_checks.py full --plan --jobs 3 --flutter-workers 4 --sims-jobs 2
python3 scripts/mknoon_checks.py full --base "$BASE_REF" --local \
  --jobs 3 --flutter-workers 4 --sims-jobs 2 --device-config "$DEVICE_CONFIG"
```

All three worker limits default to **1**, accept 1–64, and belong to the recorded
plan. `--jobs` schedules checks with declared nonconflicting resources;
`--flutter-workers` bounds each compatible Flutter batch, including the existing
host gate through `MKNOON_HOST_FLUTTER_WORKERS`; `--sims-jobs` enables the existing
SIMS scheduler and sets `SIMS_MAX_PARALLEL`. `SIMS_HOST_CONCURRENCY` receives the
host worker bound. Unknown metadata serializes. Device/device-control names
share ownership, staging-relay exclusions remain intact, and all host prerequisites
finish before device campaigns. Failed dependencies stay unrun. The checkout
lock remains, with an additional cooperating cross-checkout lease for shared
Flutter/native/AAR outputs. SIMS Flutter/native host rows also share an exclusive
build resource. This does not fence unmanaged external build processes.

`selection.json` owns `full_inventory`: audited listing expansion, automatic
source selectors, source registrations, scenario catalogs and explicit exclusions.
`discover` and `full --plan` reconcile tracked and nonignored source files,
nested packages and Go modules against those selections. Each obligation has a
stable path/selector/configuration identity. Fixtures, generated/vendor/archive
files and support applications are labeled. Unknown source tests and missing
scenario mappings remain visible gaps, not successful wrapper registrations.
The static reliability classification listing does not start Dart or execute
scenarios; detailed `--records-tsv`/`--checks-tsv` retain their expansion checks.

Full SIMS commands now execute proofs: `--prepare-builds` is not an execution
command. SIMS automatically prepares unique build profiles and hands attested
artifacts to its existing adapters. Cache validation still binds source,
entrypoint, compile defines, platform/architecture, toolchain, provider/signing
configuration and artifact bytes. Runtime-only reuse remains limited to existing
supported profiles. Legacy routes without that adapter continue their own builds;
no unchecked file-existence shortcut was added. Full mode sets
`SIMS_GROUP_MULTI_PARTY_SCENARIO=all`; direct and change-mode callers retain the
nine-case smoke default. The adapter requires one terminal report row for every
one of the 109 actual catalogue keys (the aggregate `all` key is not a scenario).
A zero child exit with a missing, duplicated or failed scenario is incomplete.
Both group-media platforms have typed SIMS owners; the iOS row declares its
signed iOS bundle and Android companion dependencies/read resources. Only those
attested artifacts reach the child; ambient artifact paths remain rejected.
New capabilities append without shifting existing array indices used by runtime
root mappings; discovery contracts check the preserved indices and new suffix.

Production-bootstrap migration Wave 2 resumed on 2026-09-28. Waves 3–5 remain
paused except the shared registrations required by Wave 2 gates. The current
acceptance matrix, preservation decisions and candidate evidence limits are
recorded in [the Wave 2 resumption checkpoint](production-bootstrap-migration-crosswalk.md#wave-2-resumption-checkpoint).
No overall migration closure or retirement is established.

On current integrated-main source identity
`e6130e3970c8ed93590cc5f15ea08a684d654467523dced88dc8ebc420861572`, the
explicit-base/local wrapper subset passed workflow (241), provider-schema (5),
runtime-roots (20), SIMS plan contracts (235), debug composition boundaries
(121), Maestro flow contracts (9), production journey contracts (582) and strict
group-media preservation (129), with zero failed cases. Its broader candidate
report remains `BLOCKED`: 149 checks were selected, eight ran, 141 remained
`NOT RUN`, and 604 local paths remain unmapped. Provider delivery, sound, routing,
notification-open and private-media device campaigns were not run because the
required isolated device/account/service configuration is absent. These results
are not a full affected-selection or full-host pass.
The candidate-bound wrapper ledger is retained in
`.codex-test-logs/production-bootstrap-migration-20260928/wave2-resumption-001/host-prereq-002/`.

**Superseded setup conclusion:** `tool/testing/config.local.json` is not a
required filename. The later review accepted the existing ignored configuration
through explicit `--device-config` and reported no Wave 2 campaign setup reason
in `.codex-test-logs/production-bootstrap-migration-20260928/wave2-review-001/preview/plan.json`.
That was a configuration preview, not provider or scenario proof. The active
continuation rechecked the live pair and uses its own ignored device configuration
for USB Android `21071FDF600CSC` and available emulator `emulator-5554`; retain
each actual campaign result and cleanup separately in the crosswalk.

For the Wave 2 sound journey, S5–S13 send encrypted media *descriptors* with
notification copy and metadata but no playable fixture bytes. The conversation
UI may show “Loading media” or “Media unavailable” on either peer; those labels
do not prove media transfer and are outside the sound assertion. The separate
private-media journey must prove actual bytes, viewer open/close and ownership.
S16 also crosses an Android background-isolate boundary: a native audible card
can be posted while the foreground-isolate request observer remains unchanged.
The 2026-09-28 attempt in detached candidate
`/Volumes/CrucialX9/flutter_app-wave2-candidate-20260928/.codex-test-logs/wave2-frozen-016/sound-run-001/`
retained a real background
`osPosted`/`silent=false` event, one stored message, accepted FCM delivery,
native ingress, and a later duplicate suppression; its old observer-only wait
timed out and cleanup restored both peers exactly. The additive S16 proof now
requires a run-marked background publication event and first native card with
exact copy, stable ID and the preserved OS disposition check. This diagnostic
finding is not a passing complete sound campaign.
The next attempt, retained under the same candidate's `wave2-frozen-017/`,
captured that first audible native card but used the handler's legacy
background-post event (`silent=false`) rather than its durable event shape;
the extra durable-only requirement failed, and cleanup again passed. The
production proof accepts either observed event shape while retaining the
same native and duplicate checks.
The later `wave2-frozen-018/` attempt completed all 17 case observations and
S16's first native/OS verifier, but the final oracle failed. Its live-path
request was an exact silent update to the same native card; it must not be
counted as another audible post. Replaying that evidence also exposed an
independent S16 gap: the receiver's readiness was offline before the send,
and its committed message transport was `inbox`. The original S16 assertion
requires a paused receiver whose bridge remains connected. The bounded
diagnostic moves the original 11-second tone cooldown before backgrounding,
records readiness immediately after pause, and reads the committed transport;
`inbox` recovery cannot certify the connected seam.
The S16-only `wave2-frozen-019/` diagnostic found the receiver online just
after pause but an inbox-transport message after a 28-second Maestro send.
The narrow `wave2-frozen-020/` diagnostic used the retained harness's actual
production `sendChatMessage` use case immediately after pause: readiness stayed
online, the committed transport was `direct`, one audible live local request
appeared, the first native card passed the unchanged S16 OS verifier, and the
later provider callback was suppressed as a duplicate. That diagnostic
deliberately omits S1–S15, so its wrapper failure does not certify the full
sound campaign. The final oracle now accepts the observed live publication
path and still rejects inbox transport, a second audible request, changed card
identity or missing provider deduplication.
The next full sound attempt, `wave2-frozen-021/sound-run-001/`, completed
S1–S11 but failed while authoring S12's announcement descriptor. Its sender
log shows an in-place group-topic recovery beginning immediately before the
production send; the send returned `error`, and exact cleanup passed for both
Android peers. The additive fixture now retains the first error and permits
one bounded retry of that same production send only when no message row was
created and the recovery gate has cleared. This is a fixture timing repair,
not a relaxation of the original S12 notification assertions. A later full
campaign must prove the result. Speaker tone remains unobserved because the
emulator audio could not be monitored; OS card/channel checks cannot replace
that acoustic observation.
The subsequent full candidate run under `wave2-frozen-022/sound-run-001/`
passed all 17 sound observations (S1–S16 plus S15's post-clear control),
including S14's before-update first card and S16's connected direct transport,
provider ingress and duplicate suppression. The preserved S16 native verifier
returned `audibleStrict` pass; the scenario oracle had no failures, and exact
cleanup passed on `21071FDF600CSC` and `emulator-5554`. It used source
`83a9a919bb042b1cfb77a49d9b96d7133f24d45e4f9be4ec3884e9d876fb6081`
and built two previously unattested profile artifacts. S12 succeeded on its
first send in this run, so the conditional recovery retry remains unexercised.
The wrapper's overall `BLOCKED` classification is due to deliberately unrun
checks outside this one-campaign subset, not a failed sound assertion.
The first current-candidate notification-open run,
`wave2-frozen-023/open-run-001/`, failed its warm other-chat wait after the
receiver had persisted the exact incoming row. The receiver's Android log
recorded a durable background `osPosted` card and a suppressed duplicate FCM
callback, while its foreground-isolate request list stayed empty. The old
additive wait required that foreground list to grow, so it missed a real
headless notification; exact device cleanup passed. The replacement now
captures the active Android card before tapping, verifies its package,
channel, title, exact body and unique card identity, and keeps the same
30-second bound. The original warm/cold/same-peer route, unread and cold
initial-payload assertions remain in the oracle. The new native-card parser
and headless/negative criteria tests pass; a full device rerun is still
required.
The first rerun under `wave2-frozen-024/open-run-001/` failed before sending:
Maestro's driver startup timed out on the physical Android target. Its cleanup
passed, and a pinned read-only Maestro hierarchy probe then started correctly.
The fresh `wave2-frozen-025/open-run-001/` run passed warm other-chat,
cold-start and same-peer cases with an empty oracle, accepted provider/native
ingress receipts, exact native cards before each tap, zero new builds and two
attested cache hits. The cold case recorded process death and a fresh
initial-payload route event; cleanup restored both peers exactly. Its source
identity is `19f590e3abc2b798f94908ebe2945b5c0b96468103e518c27c15e1a2b56b1e84`.
As with sound, the one-campaign wrapper remains overall `BLOCKED` only because
the unrelated selected checks were intentionally not run in that invocation.
The current-source private-media run,
`wave2-frozen-026/private-run-001/`, passed its production-entrypoint local
journey with an empty oracle, including projection, committed SQL and exact
bytes, incoming open/close, protected viewer window, file ownership and
attachment cleanup, cold persistence and consumed refusal. It reused the
attested `android.e2e.main` artifact with zero rebuilds; exact cleanup passed
on both Android targets. Its source identity is the same
`19f590e3abc2b798f94908ebe2945b5c0b96468103e518c27c15e1a2b56b1e84`.
The native/crypto/policy owners remain separate from this local UI journey.
The full current-source routing run,
`wave2-frozen-027/routing-run-001/`, passed all 27 ordered observations with
an empty oracle and exact two-peer cleanup. S14 persisted exact lower-case
`relay fallback` text on both peers over relay transport, closing the prior
case-sensitive text mismatch without changing the original three-minute
deadline. The `android.e2e.main` artifact was an attested cache hit with zero
new builds. Source identity was again
`19f590e3abc2b798f94908ebe2945b5c0b96468103e518c27c15e1a2b56b1e84`.
The first final-source sound rerun, `wave2-frozen-028/sound-run-001/`, failed
at S3 before a message was sent. The sender's screenshot retained the exact
composer text, and its log recorded `GROUP_SEND_MSG_USE_CASE_RECOVERY_PENDING`
while an in-place announcement-topic recovery overlapped the UI tap. This is
the same production recovery gate implicated in the earlier S12 timing
failure. The existing five-case `production_group_recovery_hold_test.dart`
passes and exact device cleanup passed. The failure is retained; the prior
17-case sound pass has an earlier source identity, so a fresh full run is
required to align sound with the other current-source campaigns.
The fresh `wave2-frozen-029/sound-run-001/` passed all 17 sound observations
on source `19f590e3abc2b798f94908ebe2945b5c0b96468103e518c27c15e1a2b56b1e84`,
including the S14 first card, S15 post-clear control, and S16 paused-connected
direct message with accepted FCM/native ingress and duplicate suppression.
Its S16 preserved native verifier returned `audibleStrict` pass, the campaign
oracle was empty, both attested artifacts were cache hits with zero builds,
and exact cleanup restored both Android peers. This establishes current-source
OS card/channel and internal disposition evidence; the emulator speaker was
not monitorable, so acoustic sound remains unobserved.
The first focused host run on that source passed seven of eight selected
checks; `sims-plan-contract` failed one companion-artifact test because its
fixture supplied a filename but no existing APK or attestation digests. The
executor correctly rejected the incomplete companion. The test now prepares
a real temporary APK and both digests, retains the absent-dependency negative
control, and passes all 21 tests in `sims_executor_test.dart`. The original
failed wrapper report is retained at `wave2-frozen-030/host-focused-001/`.
This test-only source change requires fresh final-source campaign evidence.
The fresh focused wrapper on source
`e12057b99186b265e34c95c4a5ed392fdf4d2ed1503a9c3bb274f40311abf3fb`
passed all eight selected checks: workflow, provider schema, strict group
media manifest, runtime roots, debug composition boundaries, SIMS plan
contract, production journey contracts and Maestro flow contracts. Its
receipt is `wave2-frozen-031/host-focused-001/`. The wrapper remains overall
`BLOCKED` because the broad dirty-tree selection contains intentionally
unrun checks; there is no failing assertion among the eight executed gates.

The subsequent integrated-main wave-boundary `host-all` ran with Flutter
3.47.2 and a pinned available iOS simulator. Its original log is
`.codex-test-logs/production-bootstrap-migration-20260928/wave2-continuation-001/host-all-final-001.log`.
Plan 371 passed eight iOS XCTest methods; Plan 373 passed its native mutation,
restoration and NSE proofs; Plan 374 passed nine Android classes and 75 methods
after the user's separately approved exact manifest registration. The Flutter
batch ran 18,328 tests and failed five broad-tree assertions: three unchanged
DTR-18 fingerprints against concurrently changed source, the analyzer
suppression inventory after `third_party/video_compress` appeared, and a
runtime-root directive in preserved beta video-compress evidence. The Go
libp2p contract leg failed two local `DialPeer` calls during the full sweep;
both exact tests passed when rerun alone. Preserve the initial failure. The
full host gate therefore remains failed; focused or native passes cannot
replace it. The separately approved bootstrap caller-census patch registers
three new Wave 2 journey send callers without changing assertions. Generated
iOS Pods now inherit the app's existing iOS 15 minimum, repairing the Xcode 27
native prerequisite. The final candidate identity after these changes is
`48f5fd4fcbc941d838f0a63da638c6d3bf110efae447661e8a2b6671cb9dd18e`;
fresh device receipts on that exact source are separate from the earlier
`19f590e3abc2b798f94908ebe2945b5c0b96468103e518c27c15e1a2b56b1e84`
campaign passes.
The later root-cause repair restored the one missing beta video-compress
`subscription.dart` beside its already preserved `compress_mixin.dart`; the
added file matches the vendored package byte-for-byte. After separate
shadow-copy verification and exact user approvals, the DTR-18 original test
has only its two reviewed bootstrap fingerprint constants updated, and the
analyzer original test has only `third_party/video_compress` registered as an
expected package root. The original runtime-root, DTR-18 and analyzer files
then passed 29 tests together. The first failed host sweep remains retained.
The fresh full host sweep at `wave2-continuation-002/host-all-002.log` exited
zero: 18,333 Flutter tests passed with two skips, the Go and relay legs
passed, Plan 371 passed its iOS native owner, Plan 373 passed its iOS
NSE/native owner, and Plan 374 passed nine Android native classes with 75
JUnit methods. The passing wave-boundary gate does not replace the separate
device receipts.
The final-source notification-open rerun
`wave2-frozen-035/open-run-002/production-notification-open-0-sims.json`
passed all three warm-other-chat, cold-start and same-peer assertions with
independent report verification, two attested cache hits, zero builds, and
exact cleanup of both pinned Android peers. Its proof is
`build/sims/proofs/production.notification_open/attempt-k9BbhV/`. The
one-campaign wrapper is overall `BLOCKED` only because other selected checks
were intentionally `NOT RUN`.
The first final-source private-media attempt
`wave2-frozen-035/private-run-002/` passed its scenario and exact cleanup,
but the wrapper's immediate independent report verification blocked that
invocation. Running the exact `verify-report` command afterward passed; the
first wrapper block remains retained. A fresh full invocation at
`wave2-frozen-035/private-run-003/production-private-media-0-sims.json`
passed the production local journey, independent report verification, one
attested cache hit with zero builds, and exact cleanup. Its proof is
`build/sims/proofs/production.private_media_local/attempt-WP74GE/`.
The first final-source routing attempt
`wave2-frozen-035/routing-run-001/` reached S9 and timed out in the Maestro
batch-send flow without reporting steps. Its first failure and exact cleanup
remain retained. A pinned read-only Maestro hierarchy probe then passed.
The fresh full `wave2-frozen-035/routing-run-002/production-routing-0-sims.json`
passed all 27 ordered cases on final candidate source, with an empty oracle,
independent report verification, one attested cache hit, zero builds, and
exact two-peer cleanup. S14 stored exact lower-case `relay fallback` on both
peers with relay transport; the original three-minute deadline remained.
Its proof is `build/sims/proofs/production.routing_smoke/attempt-cVi14A/`.
The final-source sound run
`wave2-frozen-035/sound-run-001/production-notification-sound-0-sims.json`
passed all 17 observations (S1–S16 plus S15 post-clear), independent report
verification, two attested profile cache hits, zero builds, and exact
two-peer cleanup. S14 retained its first-card-before-update capture; S16 had
a connected, online paused receiver, accepted provider/native ingress and
duplicate suppression. Its unchanged native OS verifier returned
`audibleStrict` pass and the oracle was empty. The proof is
`build/sims/proofs/production.notification_sound/attempt-2tPq7W/`.
The user could not monitor this S16 run, so this proves OS card/channel
disposition and internal behavior, not an acoustic speaker tone. A later
S16-only diagnostic retained native `audibleStrict` and exact cleanup but
intentionally lacked the other 16 receipts, so it cannot certify the full
campaign. A Mac microphone recording detected the Pixie Dust reference when
played through Mac speakers, but found no matching waveform during that S16
diagnostic. Android Settings showed the emulator's notification stream at
5/7, unmuted and routed to speaker; its sound preview likewise produced no
clear microphone signal. The user subsequently heard a tone but could not
identify whether it coincided with the Mknoon S16 notification or Settings
preview. Acoustic S16 attribution remains unverified. Diagnostic artifacts
are under `wave2-continuation-001/acoustic-s16-001/` and the candidate's
`wave2-frozen-036/sound-s16-acoustic-001/`.
The final candidate's eight-check focused wrapper
`wave2-frozen-035/host-focused-001/` passed workflow, provider schema,
strict group-media manifest, runtime roots, debug composition boundaries,
SIMS plan contracts, production journey contracts and Maestro flow contracts
on the same `48f5fd4fcbc941d838f0a63da638c6d3bf110efae447661e8a2b6671cb9dd18e`
source. Its overall `BLOCKED` result reflects the other selected checks
intentionally `NOT RUN` by `--only`, not a failure among these eight.
On integrated main source `914ac51ae5bbfc3818be44f09c4a26bd160371d129f377716004b51f980dcab0`, the first explicit-base/local Wave 2 selection
`wave2-continuation-002/main-wave2-run-001/` passed those same eight focused
host checks. Its notification-open and sound setup checks each timed out
after 15 seconds reading `dumpsys activity processes` from pinned emulator
`emulator-5554`; neither launched a scenario. Three immediate direct repeats
of that exact read returned in under a quarter-second, establishing an
intermittent probe timeout, not unavailable hardware. The private-media
campaign passed setup and made one cold `android.e2e.main` build, then its
first `alice-reopen` Maestro flow timed out without step results before any
media assertion. The first failure is `attempt-VozCOG/first-failure.txt`;
`cleanup.json` verifies exact restoration of both Android peers. A fresh
Appium page-source read and a pinned Maestro hierarchy probe on the physical
phone succeeded after cleanup. The wrapper left routing unrun for cleanup
review. The cause of the Maestro startup timeout remains a hypothesis; these
results are setup/automation evidence, not passing device assertions.
A fresh `wave2-continuation-002/main-private-run-002/` passed setup and both
peer reopen flows, but the following projection-open Maestro invocation
timed out before step output. Its `attempt-CkxFQn/first-failure.txt` and
`cleanup.json` retain the second failure and exact restoration. The host was
simultaneously running repeated iOS native builds with a load average around
124, so resource contention is a hypothesis rather than an established app
failure. Preserve both attempts and rerun only after the host load settles.
After the host gate passed, `wave2-continuation-002/main-open-run-001/` stopped
before scenario launch because the USB Pixel's Android process census showed
an active Appium UiAutomator2 instrumentation owned outside this task's MCP
sessions. The pinned phone and emulator remained available; another owner's
automation session is a device-ownership prerequisite, not a product failure.
On 2026-09-29 the user authorized taking over the USB Pixel. Its active Appium
instrumentation was released without stopping the unrelated Appium server or
other devices. The available and selected Wave 2 pair remained USB Pixel
`21071FDF600CSC` and `emulator-5554`; `emulator-5556` was never a campaign
target. The current-main notification-open first run at
`wave2-continuation-003/main-open-run-002/` reached its provider send and
failed before a case assertion because the adapter read only stdout while the
provider helper emitted redacted rejection diagnostics on stderr. A focused
parser test and analyzer pass preceded a fresh run. That fresh run at
`main-open-run-003/` identified FCM `404 UNREGISTERED`, with exact cleanup.
The token had been claimed before a deliberate app reopen; current bootstrap
rotates the cached FCM token on its first eligible read after each process
start. The journey now claims after reopen and again after the cold tap starts
a new process. `main-open-run-004/` then passed all three original cases,
accepted provider sends and native ingress, empty oracle, wrapper report
verification, and exact two-peer cleanup. Its proof is
`build/sims/proofs/production.notification_open/attempt-ftEuOX/`.
On the same `bb29798e632479a820b8b4849894a32ba517e7f5344859187d91e07d16de1dc4`
source, `main-private-run-001/` passed the real private-media journey, empty
oracle, wrapper report verification and exact cleanup in
`build/sims/proofs/production.private_media_local/attempt-rzBO1g/`.
The first routing attempt `main-routing-run-001/` recorded through G1 and
failed at G2 because Maestro enumerated an unrelated temporarily offline
ADB emulator, despite its pinned Pixel target. It did not drive that emulator;
the first failure and exact cleanup remain in `attempt-gSPx0s/`. A pinned
read-only Pixel hierarchy probe passed. Fresh `main-routing-run-002/` passed
all 27 ordered cases, empty oracle, wrapper report verification and exact
cleanup in `build/sims/proofs/production.routing_smoke/attempt-r987Ml/`.
S14 stored exact lower-case `relay fallback` with relay transport on both
peers. These three passing one-campaign wrapper runs are overall `BLOCKED`
only because other selected checks were intentionally `NOT RUN`.
The first two current-main sound attempts remain failed. `main-sound-run-001/` recorded S1 and
S2 before a no-step Maestro leave-chat invocation timed out after 110 seconds;
`attempt-UTaiEs/first-failure.txt` and `cleanup.json` retain failure and exact
restoration. A pinned read-only Pixel hierarchy probe then passed.
`main-sound-run-002/` failed before S1 when Bob's reopen Maestro invocation
timed out after 110 seconds without step output; `attempt-wEw0Qe/` retains
the first failure and exact cleanup. Host load was high around the first
timeout and fluctuated during the second; resource contention is a hypothesis,
not a proved cause. The second run began on source identity
`0c0b6fccb7514726d74bd15636e1951df18b4b3698c571e75467c89838458703`,
different from the three passing main wrapper fingerprints. Preserve that
distinction. Fresh `main-sound-run-003/` passed all 17 observations, including
S14 first-card identity and S16 background provider delivery, accepted FCM
and native ingress, the original `audibleStrict` native disposition, empty
oracle, independent report verification and exact two-peer cleanup in
`build/sims/proofs/production.notification_sound/attempt-T6INKk/`. Its
wrapper fingerprint was
`b5e11c661e396bd857224695c7516ea6786c36752145786012946e0f67e7e624`.
The four passing integrated-main SIMS reports nevertheless have the identical
campaign source digest
`82d32bb186b69fea5fe9b77dbf811ca997a47afaa629ff19a2f3e058f43a94fc`
and sender/provider APK digests
`3b2729fd2b9d9d0330aa827daf8d836687848b460218a37371c56b92d99d5a1e`
and `51e19f1740ac2054c0c257e3acb310184d601b54ba7fc58d007cca8c4bc83211`.
The broader wrapper source identity changes with non-campaign checkout files;
the concurrently active call campaign wrote untracked inputs into this
checkout. Across these four passing runs, the build ledger records two cold
builds followed by four attested cache hits. All four selected device checks
passed; each one-campaign wrapper is overall `BLOCKED` only because its other
selected checks were intentionally `NOT RUN`.

For this S16, `adb -s emulator-5554 shell dumpsys audio` retained a SystemUI
`USAGE_NOTIFICATION` MediaPlayer started at 15:34:26.912, 0.616 seconds after
the S16 `OS_POSTED` event in the native log. The playback event reported no
mute, speaker device ID 2 and a stop at 15:34:28.770; the notification stream
was unmuted at volume 5/7 with ringer mode normal. The correlated excerpt is
`attempt-T6INKk/S16-android-audio-playback.txt`. This proves an Android
speaker playback event beyond the card/channel disposition, but not a measured
acoustic waveform or a person hearing the S16 tone. The user could not
monitor this arrival, so S16 acoustic attribution remains open.

The fresh focused wrapper `wave2-continuation-003/host-focused-run-001/`
passed eight selected host checks on the sound-run wrapper fingerprint. The
first subsequent full `host-all` at
`wave2-continuation-003/host-all-final-003.log` passed 18,333 Flutter tests
with two skips but failed the original UP-012 group membership notification
assertion once in the batch. The exact case passed alone and all 91 tests in
its original file passed together in `group-up012-focused-001.log` and
`group-membership-file-001.log`; the batch-only cause is unproved. The
complete Dart `host-all` rerun at `host-all-dart-rerun-001.log` passed 18,334
tests with two skips, including UP-012. Preserve the first batch failure.
The first run's Go/relay tails and Plan 374 Android native 9-class/75-method
owner passed. Plans 371 and 373 stopped before XCTest because the host
invocation lacked `MKNOON_NATIVE_IOS_SIMULATOR_ID`. The user then permitted
available iOS simulators other than iPhone 15, or connected iPhones, for
separate iOS-specific checks. Pinned native reruns use the available iPhone
17 Pro simulator `674DFFF6-5F38-4235-93F6-AF7FBF86AE65`. Plan 371 passed
its native host contract in `ios-native-371-001.log`; the XCTest result in
`/tmp/plan371-native.Q1GeXu/` records eight passed and zero failed methods.
The user requested a stop for reboot during Plan 373. Three intentional
mutations each re-redded and restored Swift source hash
`e0900f0c246af544ac60a83b21f715ddfeae6c293a37ca483bcd36510149b650`.
The restored XCTest build was interrupted before its 28-method verdict;
`ios-native-373-001.log` and `/tmp/plan373-native.HdQXuo/` retain the
partial evidence. At that reboot checkpoint, the check was unrun to
completion, not failed; the 2026-09-30 result below supersedes this status.

A bounded `emulator-5554` scrcpy audio-capture positive control was
inconclusive: Android Settings started a notification-sound preview
MediaPlayer, but `sound-audio-positive-001.opus` had no sustained signal above
-55 dB. The capture, device trace and analysis are retained under
`wave2-continuation-003/`. This recorder cannot establish S16 acoustics from
the current probe. The user could not monitor the S16 arrival; do not treat
the earlier heard tone of uncertain timing as attributable to that case.

The bounded follow-up used macOS ScreenCaptureKit global system-audio capture.
Its positive control recorded two Android Settings notification previews at
windows consistent with SoundPicker's notification MediaPlayer starts, with
about 0.78 seconds capture latency. App-only filtering remained silent, so the
positive control applies to global capture only. A fresh full sound run on the
pinned Pixel and `emulator-5554` used two attested APK cache hits and no builds,
but stopped after S7: a return-home Maestro invocation timed out after 110
seconds without step results. Its seven observations, first-failure record and
exact two-peer cleanup are in `wave2-continuation-003/main-sound-run-004/` and
`build/sims/proofs/production.notification_sound/attempt-kO09aL/`. It never
reached S15 or S16, so no S16 waveform was captured. Retain the earlier passing
17-case `main-sound-run-003/` and its unmuted speaker-path trace separately;
neither the positive control nor the playback trace proves acoustic hearing of
that S16 arrival. Sound exploration was deliberately stopped at this bound.

The user accepted the earlier S16 `audibleStrict` receipt and correlated
unmuted SystemUI notification MediaPlayer on the emulator speaker at volume
5/7 as sufficient audible-device evidence for **WAVE 2 COMPLETE** on
2026-09-30. This is native speaker-path evidence; no S16 waveform or human
hearing is claimed. The failed S7 repeat and its exact cleanup remain retained
as first-attempt evidence, without replacing the passing 17-case receipt.

For Plan 373 iOS native verification, use the repository's Flutter 3.47.2 SDK
and pin the available iPhone 17 Pro simulator
`674DFFF6-5F38-4235-93F6-AF7FBF86AE65`. The first resumed run with the
default Flutter 3.41.4 tool failed before assertion because stale plugin
metadata left both Swift Package Manager and CocoaPods producing
`WebRTC.framework`; its log remains `ios-native-373-002.log`. Correct-SDK
`flutter pub get` and `pod install` removed the duplicate producer. The next
`ios-native-373-003/` native wrapper passed exact Go/fixture/binding checks,
three intended one-test XCTest mutation failures, one restored-source pass and
the exact 28-method XCTest set (28 passed, zero failed/skipped). Its cleanup
removed owned DerivedData and restored Swift SHA-256
`e0900f0c246af544ac60a83b21f715ddfeae6c293a37ca483bcd36510149b650`.
Do not count the setup failure or the earlier reboot interruption as a failed
native assertion. The original-file audit in
`wave2-continuation-003/final-original-preservation-audit.json` confirms all
282 baseline `integration_test` files unchanged and lists wider dirty-tree
test differences separately; it does not certify unrelated modifications.

The integrated-main checkpoint validates testing metadata and observes passing
bootstrap (21), Go-wrapper (4), group-harness (357), Maestro-flow (9), production
journey (582) and UI-action (263) host checks. Both focused wrapper invocations
also report source changes during execution and invalidate candidate evidence:
concurrent unrelated main edits were preserved. These counts are diagnostic
observations, not a stable-candidate acceptance result. The complete outcomes,
source fingerprints and raw logs are retained in
`.codex-test-logs/production-bootstrap-migration-20260927/integration-checkpoint-001/`.

At the 2026-09-27 integration checkpoint, six production runners lacked
reliability-discovery classification and three reaction runners lacked
runtime-root registrations. Those original failures remain retained. Wave 2
resumption added the exact support classifications and reaction entrypoints;
current workflow (241), SIMS plan (235) and runtime-root (20) checks pass. The
final classification output is retained in
`.codex-test-logs/production-bootstrap-migration-20260928/wave2-resumption-001/reliability-discovery-final.stdout.tsv`.

At the 2026-09-27 integration checkpoint, the architecture boundary check
rejected the unchanged beta evidence path ending
`step-035-assertCondition-[0-9]+_items_pending.json`. The evidence bytes remain
unchanged. The checker now accepts glob punctuation only as literal characters
from NUL-delimited Git filenames while preserving strict canonical path checks
and wildcard rejection for user-authored exact paths. A temporary-repository
regression test exercises the literal filename; the current debug-boundary check
passes 121 cases. The initial failure and preservation audit remain in
`workflow-failure-review.json`, `boundary-checks-002/` and
`post-verification-preservation-audit.json`.

The additive `ProductionSharedXCTest` consumer verifies the central prepared
bundle's profile, input digest, artifact bytes/permissions/link manifest and
signed product graph before use. Every selector receives independent fixture,
relocated plist and xcresult paths; a matching single method/class receipt,
bound fixture assertions and verified restoration are all required. Only
`test-without-building` is executable through this consumer. Original fresh-build
owners remain unchanged. The 29 focused host cases (including retained plist
relocation and repaired flow-identity contracts) passed in
`production-bootstrap-migration-20260927/wave4-xctest-causal-003.log`.
Codesign and child execution are simulated in these host cases; actual shared
bundle execution and native scenario evidence remain pending.

The foreground group-push simulator campaign must prepare both role-specific
iOS apps before launching either timed peer. Its previous serial `flutter drive`
builds let Alice publish readiness and start the five-minute Bob-identity wait
while Bob was still compiling. The native failure is retained in
`.codex-test-logs/all-tests-y227gs8x/reliability-held-route-probes-003/logs/001.log`.
The runner now builds each role with the same run ID, database name, shared
directory and relay defines used at launch, saves each fresh app before the next
build replaces `Runner.app`, and uses Flutter's `--use-application-binary` path.
Peer and scenario deadlines stay unchanged. Three host contracts check build
ordering, exact role/configuration retention, failure before peer launch, and
the existing Android path. The fresh native attempt recorded below passed.

The subsequent native run reached both peers and recovered the exact S1
message, but its notification assertion observed zero rather than one. The
older harness had supplied only tracker/lifecycle inputs; the current listener's
compatibility notification path requires `AppVisibilitySuppressionReader`.
The harness now reuses `TrackerBackedAppVisibility` from the existing shared
test fakes with its original tracker and lifecycle closure. The one-notification
assertion and all scenario deadlines remain unchanged. The first assertion
failure is retained in `foreground-group-preparation-device-probe-003/` under
the all-tests run directory. Attempt `foreground-group-preparation-device-probe-004`
then passed S1 recovery and S2 live-plus-push deduplication, each with exactly
one notification. S3 failed before its missing-member eligibility check because
its fallback call also lacked required visibility and durable presentation
authority. That call now reuses the same visibility reader and the existing
`DurableNotificationToneLease` fixture from the host non-current-group test,
with a run-owned temporary directory and teardown. S3 still requires one drain
attempt, no fallback display, and zero generic notifications. The original
failures remain retained. Attempt
`foreground-group-preparation-device-probe-005` reached the next S3 assertion:
the deliberately failed drain returns `notificationNeededAfterDrainFailure`,
not the older `notificationNeeded`. The harness and its verdict predicate now
expect the precise existing result, which keeps canonical recovery incomplete;
the one-drain/no-notification assertions remain intact.
Fresh attempt `foreground-group-preparation-device-probe-006` passed all three
scenarios on the existing iPhone 17 Pro and iPhone Air simulators: S1 recovered
the missed message with one notification, S2 retained one message and one
notification, and S3 recorded the precise failed-drain result with one drain,
no fallback display, and zero generic notifications. This closes the focused
repair; the complete owning suite still requires its fresh full invocation.

The additive production-entrypoint pilot must reopen after prerequisite contact
seeding, because the first startup already selected the first-contact surface.
For a fresh fixture containing a discussion group, normal reopening reaches
Orbit's inner circle without the persistent Feed/Orbit navigation bar. Open
the all-chats view before selecting its group row. Appium MCP confirmed the
group-row and composer identifiers and return to the list after keyboard
dismissal in `.codex-test-logs/production-bootstrap-migration-20260927/pilot-ui-probe-001/`.
UiAutomator2 ID lookup needs `disableIdLocatorAutocompletion=true` for these
verbatim Flutter resource identifiers. Focused keyboard input enabled Send;
an unfocused `setValue` changed exposed text without enabling that action in
this probe. These observations establish the UI path, not foreground-push
scenario completion. First failures and exact restoration receipts remain in
`pilot-device-001-raw/` and `pilot-device-004-raw/`. The probe reused the same
APK with one cache hit and zero builds; its scenario result is deliberately
non-passing in `pilot-ui-probe-wrapper-001/`.
The group message's accessibility label combines sender, exact message text,
timestamp and status. Match the escaped message as a complete line within that
label; whole-label equality fails even when the exact message is visibly sent.
`pilot-device-006-raw/` preserves the screenshot, hierarchy and successful
restoration from that failure. `pilot-message-label-probe-001.log` reproduces
the mismatch with Java's regex engine, accepts the exact line, and rejects
prefix, suffix, scenario and run-ID changes. Repository equality and row-count
assertions remain independent and unchanged.

Production-bootstrap foreground-push fixtures also include the real periodic
group recovery owner. Leaving only the native topic does not sustain a live gap
through a Maestro send: pilot `007` observed automatic rejoin 17 seconds after
leave and rejected S1 because the row arrived before push. The additive fixture
holds the existing serialized recovery gate, waits for earlier passes, and
releases it before S2; its three-minute expiry rejects continued observations.
The foreground-push targeted drain, real listener, native notification boundary
and exact S1/S2/S3 oracle remain active. Evidence:
`.codex-test-logs/production-bootstrap-migration-20260927/pilot-device-007-raw/`.
This failed attempt is preserved and is not scenario-passing evidence.
Fresh production-entrypoint attempts `pilot-device-008` and
`pilot-device-009-warm` passed all S1/S2/S3 predicates, each exact Maestro flow,
and exact restoration of both Android targets. Their shared APK SHA-256 is
`c55bf61da656fc32ca4e17b679b88f5f40eae3d6c90df7dd365cdb39da5d6338`.
The cold attempt built once; the unchanged warm attempt recorded zero builds
and one cache hit. Raw evidence and restoration reviews are retained in their
corresponding `-raw/` directories. The owning wrapper invocations used a
diagnostic subset, so these are selected-pilot passes, not full-suite passes.
Maestro's exact `xcodebuild -version` probe is read-only; the child-build guard
allows that single query while still refusing default or explicit builds.

Production notification observations must preserve the incoming silent decision
separately from the effective native silent decision. The optional observer
records exact contact/payload/notification-ID identity and hashes of the native
title/body without retaining their plaintext. A causal host probe overrides
only the native publication's silent argument and verifies the upstream value
remains distinct; an observer exception still permits the real plugin call.
The unchanged notification-service suite plus new observer/runtime probes passed
58 tests in `production-bootstrap-migration-20260927/wave2-sound-observer-probes-001.log`.
These observations do not establish speaker sound or complete the sound journey.
The first production notification-open attempt passed its selected 512 host
tests but failed on real background delivery before any notification tap.
`wave2-device-001-raw/` and `wave2-device-001/cleanup-review.json` retain the
failure and exact restoration. The small `background-probe-001/` used actual
Appium MCP with that same attested APK. A foreground control delivered over
relay; a send after a confirmed paused observation did not reach the receiver
while its observation control still responded. Earlier queued inbox content
appeared after resume. Thus Android's later process freeze is not the sole
explanation, and extending observation deadlines is not a repair.
The ordinary `android.e2e.main` profile suppresses provider push registration
(`shouldEnableProductionPushRegistration`); a provider-enabled background proof
needs a matching Firebase client. The available main-checkout client config
binds only `com.mknoon.app`. The user specified reuse of that production
configuration, superseding the request for a separate disposable-package client.
The existing `android.production_fcm` profile enables production registration
with that package. Replacement integration must bind the matching artifact to
the available Android emulator receiver and preserve its existing package/data
through the exact app-state guard; it must not relabel the client as
`com.mknoon.sims.connectivity` or replace the physical sender's production app.
The unfinished mixed sender/receiver adapter is now integrated into main. Its
new `android.production_fcm.journey` profile fixes the receiver package without
changing the original provider profile. Separate prepared input/artifact digests,
per-peer package operations and both state guards are implemented, but dedicated
causal tests, provider readiness and device execution remain pending. The current
`production-journey-contracts` host gate passes 582 cases, but does not establish
provider readiness or real background delivery. The replacement's real
background assertion remains unpassed; original logical-lifecycle harnesses and
their assertions are retained. These artifact paths are relative to
`.codex-test-logs/production-bootstrap-migration-20260927/`.
The additive sound journey preserves S1–S16 and S15's post-clear control,
using real navigation/visibility, production-owned descriptor projection and
the unchanged original native disposition oracle. S14 must retain an actual
first-card capture whose package, ID and body identify the first message; a
capture after the second message cannot prove the intermediate audible card.
The 39 causal and composition probes passed in
`production-bootstrap-migration-20260927/wave2-sound-causal-probes-002.log`.
The original disposition contract initially rejected the unclassified new
runner; adding its exact manifest-owned support classification restored that
unchanged contract (`wave2-sound-original-disposition-003.log`). Syntax checks
and analysis pass. Device scenario evidence remains pending.

A native XCTest build can fail although a generic Runner build succeeds when
the optional Go framework is absent: `GoBridge` is compiled behind
`canImport(GoMknoon)`, while the original critical-task XCTest owner references
that type. The frozen pilot candidate's missing framework inputs caused the
visibility owner's compile failure and prevented the NSE mutation from reaching
its named semantic assertion. The latter source was restored byte-for-byte.
Retained evidence: `production-bootstrap-migration-20260927/wave1-host-all-002/`
(including `cleanup-review.json`). The same gate's Android native owner passed
nine classes/73 methods. Provisioned frameworks in the later candidate pass
the original freshness checks, but do not close either failed native owner
until those owners actually execute on that candidate.

The additive production routing oracle retains the original 27 ordered case
receipts and reuses the unchanged pure direct/group predicates. It also binds
their inputs to actual peer, message, group and key-generation identities and
rejects missing intermediate lifecycle/deletion receipts. Fixed upload and LAN
observations retain their original informational scope. The 54 focused checks,
including original DTR preservation contracts, and 613 selected host checks
passed in `production-bootstrap-migration-20260927/wave2-routing-causal-probes-002.log`
and `wave2-routing-host-001/`. Device routing remains pending. The measured
receiver polling interval starts after the UI send flow completes; it must not
be reported as cross-device end-to-end latency.

Repeated production journey reopen actions must allocate independent evidence
directories. Routing device attempt 001 reached S6, then the second Alice
reopen reused `alice-reopen-maestro`; the adapter correctly refused to overwrite
the first PASS receipt before launching another flow. Both devices restored
exactly. The replacement host helper now allocates a fresh directory per flow,
retains adapter errors, and requires the exact successful child receipt. Four
causal tests cover repeated labels, later failure, missing receipts and foreign
receipts. Evidence: `production-bootstrap-migration-20260927/`
`wave2-routing-device-001/cleanup-review.json`, `wave2-routing-device-001-raw/`
and `wave2-flow-identity-causal-001.log`. This repair does not certify the
remaining routing scenarios or change any original harness.

The later cached routing attempt reached S14 after recording the cases through
S12/S13, then retained a three-minute exact-row timeout. Requested text contained
`relay fallback`; the actual delivered row contained `relay Fallback`, with a
successful send timing event. The new UI regex checks had accepted that case
change. Both Android package states restored exactly
(`routing-catalog-cached-device-001/cleanup-review.json`). Appium subsequently
entered the exact text, and small Maestro probes passed with both visible and
hidden keyboards. The original transformation was not reproduced, so IME
interference remains a hypothesis. The additive direct-send flow now dismisses
the keyboard before entry and checks explicit case-sensitive exact composer and
bubble text. The host exact-row assertion and three-minute deadline are retained.
The diagnostic's final SQL snapshot omitted the required `groupIds` list and was
rejected; its UI receipts remain valid but it is not a routing scenario PASS.
Both devices restored exactly; the owned Appium session was deleted
(`routing-input-cached-ui-probe-001/diagnostic-review-002.json`). Full routing
execution remains pending after this flow change.

The wider host run exposed an unawaited asynchronous write in the new synthetic
flow adapter fixture. The real adapter already writes its receipt before exit.
The synthetic adapter now writes synchronously; its four contracts pass after
the repair. The original failure remains in `wave2-private-host-001/`
`production-journey-contracts-1.raw.log`. That frozen host run passed 3,755 tests,
failed this one new case and skipped none; it is not a passing affected gate.

The additive private-media application oracle binds the production conversation
projection, real committed sender view-once SQL sequence, exact pending owner
path and bytes, attachment/file cleanup, and fresh-process consumed refusal.
Its 43 positive/negative cases and six composition/original preservation checks
passed in `production-bootstrap-migration-20260927/wave2-private-causal-001.log`.
The original device-local encryption, policy, download, expiry and native privacy
proofs remain independently required. Host oracle tests alone do not establish native privacy or remote revocation;
the later device evidence and its scope are recorded below.

Private device attempts 002 and 003 retained projection failures and exact
restoration receipts. Real protected bytes render the plan-301 thumbnail;
missing bytes render the 88-pixel outgoing card without an Open action because
`localMediaAvailable` is false. The unchanged protected-photo widget test and
production outgoing-placeholder guard establish this distinction. The new
oracle requires both variants; original mounted-widget assertions remain
unchanged. The recipient extension additionally uses canonical incoming storage,
actual UI open/consume/cold-refusal and committed SQL observations. Sender native
window evidence requires FLAG_SECURE absent before open, present during viewing
and absent after closure. The first failures remain in
`wave2-private-device-003/cleanup-review.json` and its retained raw evidence;
the later extended device result is recorded below.

The extended private-media oracle passed 67 causal cases, alongside all seven
unchanged protected-photo thumbnail widget tests (`private-recipient-causal-001.log`).
The extended controls/runner analyze cleanly (`private-recipient-analysis-002.log`).
The extended recipient/native-window campaign subsequently passed on the pinned
physical Android/emulator pair in `wave2-private-device-004/results.json`: four
assertion groups, no oracle failures and exact package restoration on both targets.
The central APK required one build (172.206 seconds), and scenario execution took
498.999 seconds. Raw observations remain in `wave2-private-device-004-raw/`.
This local application proof does not replace the independent crypto, expiry,
download, remote-revocation or account-wide proofs, nor the final full selection.

The additive production invitation module retains the original F/C/D decline,
exact resent-ID revocation, and stale-to-fresh metadata convergence. Forty-four
causal oracle checks plus six composition/original DTR checks passed in
`group-invite-causal-001.log`; analysis is clean in `group-invite-analysis-003.log`.
Creation, decline and revocation use the existing UI; bounded controls read
production-owned repositories and retain the original explicit inbox/config-request
protocol legs. Appium MCP exploration confirmed that declined sender rows have
no Resend action. The original declined-to-resend protocol operation therefore
uses a one-shot, exact-attempt control over the existing production use case.
D retains fixed fresh-metadata setup without a broadcast, because a UI edit
could converge the recipient before its config request and mask a resync defect.
The initial Appium MCP probe created and declined an invitation, exposing a
missing invitation-delivery repository edge at the ordinary home StartupRouter.
The omitted edge caused no initial delivery-attempt persistence and an unknown
sender status. The production repair forwards the existing repository; the
new wiring sentinel passes. Its original source-fingerprint update is separately
proposed and unapplied. The retained decline card also requires a terminal UI
assertion, not disappearance of the group name. Evidence and exact restoration:
`text-entry-probe-001/diagnostic-review.json`. Actual F/C/D campaign receipts remain pending; host checks do not certify
delivery. The later revocation exploration is recorded below.
The repaired-build Appium probe confirms delivery-attempt persistence, sender
Sent/Declined/Revoked UI states, the exact fresh second invite, and its recipient
revocation tombstone. `group-ui-probe-001/diagnostic-review.json` binds those
observations and exact restoration. Its snapshot failure reproduced as a dynamic
enum lookup through an untyped empty-list fallback; `production_group_invite_controls_test.dart`
now exercises the real snapshot action over typed member models. The typed
fallback repair passes; the first red remains in `group-invite-controls-causal-001.log`.
The four selected host gates subsequently passed 380 tests with zero failures
and zero skips in `groups-host-001/` (bootstrap 21, Maestro contracts 9,
production journey contracts 330, runtime-root contracts 20). The wrapper
remains a diagnostic subset with omitted obligations; it is not full closure.
The separate registration probe passed 25 tests in `group-invite-registration-001.log`.
The latest preservation audit passed all 2,411 original files, with only the three
approved file exceptions (`groups-original-preservation-audit-001.json`).

The additive startup/resume performance route observes the production-owned
node through early, bounded flow capture and drives actual OS pause/resume.
Its interval is the production readiness window's `totalMs`, not process entry
to first frame. Six fresh fixture identities/processes retain the original B
cold/distribution distinction; hot core/node operations retain M's existing
production method calls. BR healthy, degraded and extended background paths
use actual lifecycle observations, and recovery retains explicit connected-relay
faults and production health/inbox operations. The original thresholds remain:
initial cold sendable/optional online below six seconds, optional native
discoverability below five seconds, cold relay gap at most five seconds,
full hot-node readiness waits ten seconds, degraded-state wait fifteen seconds, resume
readiness waits thirty seconds and extended background at least thirty seconds.
The registered proof measures one available physical Android target. It uses
the separately attested `android.e2e.performance_relay` production profile with
the existing `DISABLE_LOCAL_DISCOVERY` compile flag. Ordinary journey profiles
retain their prior configuration. Capture, activation and oracle contracts
passed in `performance-causal-001.log`; actual performance validation is pending.
The initial ordinary-profile device attempt failed the unchanged cold dotted
readiness bound even though production timing recorded sendable at 554 ms and
relay-ready at 555 ms: later state was `onlineDirect`. A single-phone causal
probe also failed, refuting the second-fixture-only hypothesis. Production starts
LAN discovery; the original component benchmark does not provide that service.
The relay-only variant preserves the original dotted predicate and deadlines
without disconnecting other applications or changing the phone's disabled
mobile-data setting. Both failures and exact package restoration remain in
`groups-performance-device-001/cleanup-review.json` and
`performance-single-peer-probe-001/diagnostic-review.json`.
The original benchmark dispatches,
GP/H simulator/CLI boundaries and other performance families remain independently
required. No original measurement or execution owner is replaced.

The frozen C8 production invitation campaign passed all F/C/D stages and its
oracle on the pinned physical/emulator pair, with exact restoration on both
phones (`groups-performance-device-001/results.json` and its cleanup review).
This is the initial candidate's device evidence; subsequent main-checkout
reconciliation and the complete multi-party catalog still require validation.

The first multi-party replacement, `production.group_catalog.private_abc_create`,
uses production UI for three-person creation, both pending-invitation accepts,
and the first message. Read-only controls observe the existing SQL repositories;
the catalog invocation does not bind fixture import, forced join or direct-send
shortcuts. Its host oracle checks both intermediate invitations and consumed
identities, readable join rows, pre-send absence, exact message identity/count,
initial epoch and configuration convergence before calling the unchanged original
`evaluateGroupMultiPartyVerdicts` oracle. The selection helper keeps all 109 cases
and the original smoke/slice order; this first module does not cover the other
108 cases. Thirty-six focused checks passed in `catalog-causal-003.log`; original
oracle/selector and composition preservation checks passed 574 tests in
`catalog-original-oracle-preservation-001.log`. The first three-target campaign
completed every UI flow, both consumed invitations, readable joins and the exact
initial message on all peers, but the unchanged terminal oracle rejected different
configuration hashes on Alice versus Bob/Charlie. This is a failed scenario,
not completed catalog coverage. Exact restoration passed on all three targets;
`catalog-device-001-raw/` and `catalog-device-001/cleanup-review.json` retain it.
Field-level configuration digests now support a causal comparison without
exporting key material or changing the complete-state predicate. The configuration
observer, oracle and expanded graph guard passed 40 tests in
`catalog-config-causal-001.log`. The curated diagnostic selection previously passed 421 journey,
9 Maestro and 20 runtime-root checks in `catalog-host-002/`; omitted required
checks still prevent a full-suite verdict.
The first field-digest probe did not reach configuration comparison: production
recorded two selected contacts, but both member additions hit the existing
recovery gate during an in-place relay recovery, leaving zero invite recipients.
The two-minute pending-invite timeout and exact three-target restoration remain
in `catalog-config-probe-001/diagnostic-review.json`. This refutes a UI-selection
failure; it does not resolve the earlier configuration divergence. The additive
runner now observes actual transport readiness and the existing recovery gate
before creating a group, within its existing bounded observation deadline. It
does not release or bypass the gate. Forty focused observer/oracle/graph tests
pass in `catalog-readiness-causal-001.log`. The fresh diagnostic reached both
accepted groups and isolated the sole non-hash difference: the creator and both
authenticated invitation payloads retained null `metadataUpdatedAt`, while each
recipient changed it to `createdAt` (`catalog-config-probe-002/diagnostic-review.json`,
exact restoration on all three targets). The on-join response sender uses creation
time as its initial metadata timestamp; the receiver previously treated that
same initial echo as a newer edit. The receiver now uses the identical creation
floor for its strictly-newer check, preserving null for an unchanged initial
configuration. Authentication still runs first, and actual newer edits still
apply. The additive encrypted request/response regression first reproduced the
failure (`catalog-config-convergence-red-001.log`); 83 focused original and new
checks now pass (`catalog-config-convergence-causal-001.log`). The C10 affected
selection then passed 3,204 group tests, 357 original harness contracts and 439
production-journey contracts, with zero failures or skips (`catalog-next-host-001/`).
That source also includes the next reaction module's return-boundary observation;
its live acceptance and queued-retry distinction passed four additive tests plus
the existing send/roundtrip tests. The selected wrapper remains incomplete for
omitted checks. The fresh full device attempt passes the unchanged oracle, with the same
configuration hash on all three roles and exact package restoration on each
(`catalog-device-002/results.json`, `catalog-device-002/cleanup-review.json`,
`catalog-device-002-raw/`). It used one central build (38.011 seconds), zero child
builds, and four scenario action receipts. This closes ML-001 on that candidate;
the other 108 cases and final stable-candidate closure remain incomplete.

The additive PL-009 reaction module preserves the exact case identity through
its shared create/accept/message observer and the unchanged original oracle.
It requires a real successful send result, independent receiver stream events on
Alice and Charlie, and exactly one matching SQL reaction per role; optimistic
local storage with a queued publish cannot pass. The observation attaches to the
existing production send return and listener stream and is bounded by target,
sender, count, lifetime and controller disposal. Seventy-two focused tests pass
in `catalog-reaction-criteria-causal-002.log`, including refusal of queued publish,
missing stream events, stale/foreign reactions and divergent epoch/configuration.
The initial two failed negative tests are retained in the preceding `001` log.
Fourteen graph/shortcut checks pass in `catalog-reaction-shortcut-guard-001.log`;
both catalog cases refuse fixture imports, forced joins and protocol send
shortcuts. Analysis is clean in `catalog-reaction-criteria-analysis-001.log`.
Appium MCP then exercised the real message long-press, full picker, horizontal
category swipe and 🔥 selection using the previously attested creation APK.
The exact target displayed the selected reaction; the owned session was deleted
before verified restoration on all three targets
(`catalog-reaction-cached-ui-probe-001/diagnostic-review.json`). This is UI
exploration only, with zero builds; it does not establish PL-009 publish/stream
proof. The full-picker control lacked an accessibility identifier, so its existing
action now exposes `message_reaction_more`. Eleven original/new widget checks
pass in `catalog-reaction-ui-causal-004.log`, and all nine Maestro receipt checks
pass in `catalog-reaction-maestro-contracts-001.log`. The additive reaction flow
uses the observed menu/category path. Metadata validates and the pinned three-peer
selection has no missing setup prerequisites (`catalog-reaction-plan-001/`).
The complete manifest `production-journey-contracts` command then passed 486 tests
with zero failures or skips (`catalog-reaction-curated-direct-001/`); this direct
host invocation is separate from wrapper-wide/device closure. The original-file
preservation audit passes 2,558 tests/harnesses under its recorded scope, including
later accepted main test edits and only the three exact approved file exceptions
(`reaction-original-preservation-audit-002.json`). The earlier audit's broad name
match also included testing documentation/inventory infrastructure; its scope
correction does not change any executable selector. The actual observation-enabled
PL-009 device campaign remains pending; these results do not close that case.

The next catalog module, RT-001, is a production-composed protocol timing case.
Its original harness awaits each real add/remove/re-add return and spaces the
next call by 500 ms. Appium/Maestro picker navigation cannot establish a fixed
interval measured from the domain operation's asynchronous return; waiting for
receiver UI convergence would also remove the original rapid-churn condition.
The required adapter is therefore limited to a once-only Bob operation on the
already UI-created target, calling the same production send/remove functions
with existing bridge/repository owners and the original two 500 ms delays.
Creation, invitation acceptance and target send remain UI operations. Independent
receiver-stream removal and SQL convergence remain required. Its host oracle
is implemented alongside the original RT-001 oracle; runtime/device proof is
still pending. The runtime adapter now binds only Bob, validates the exact armed
target and current identity, consumes its sole attempt before awaiting transport,
and refuses arguments, repeat attempts and failed observation streams. Four
focused tests exercise the actual production send/remove functions with fake
transport, including stopping after queued add or removal
(`catalog-toggle-execution-causal-001.log`). The complete curated host lane passes
536 tests with zero failures or skips (`catalog-toggle-curated-direct-001/`),
and analysis is clean (`catalog-toggle-analysis-003.log`). These are host results;
the RT-001 device case remains pending. No generic send, fixture import, service
construction or retry endpoint is authorized by this bounded case.

PL-010 requires an actual reaction attempt by Charlie after removal, with the
old target still stored locally. The removed-member UI does not offer an
authorized reaction action, so UI automation alone cannot prove that the domain
operation rejects the attempt or that receivers remain unchanged. Its
adapter is limited to one Charlie send on a previously observed run-owned target,
after independently observed membership exclusion. Group creation, acceptance,
target send and Alice's removal action remain UI operations. The unchanged
original oracle, actual send return, empty local/remote reaction rows and original
five-second receiver absence window remain required. The shared message and
reaction criteria pass 108 focused cases (`catalog-removed-reaction-criteria-001.log`);
the new controls and graph/shortcut preservation tests pass 34 cases
(`catalog-removed-reaction-controls-001.log`). The control's actual production
send call returns `notMember` after removal without bridge publication or local
reaction storage. Appium MCP separately removed Charlie through the ordinary
UI and observed two members/key epoch 2; the owned session ended and all three
fixtures restored exactly (`catalog-removed-cached-ui-probe-001/`). This diagnostic
is not PL-010 proof. The additive runner/flow is registered, and a stable member
removal identifier preserves the same action. Its widget and flow-identity checks
pass five cases (`catalog-removed-ui-causal-002.log`); the first semantics failure
is retained in `001`. Complete PL-010 device proof remains pending. This gap does
not authorize a generic send or removal control.

The relay-only cold prerequisite passed on the physical Pixel with actual
`onlineDotted`, send/inbox readiness and exact restoration
(`performance-relay-cold-probe-001/`). A full attempt then failed on the second
identity because `production_reopen_seeded` required an all-chats surface that
fresh, contact-free identities do not show. The performance helper now uses the
existing launch-only `production_resume` flow for fresh samples; all six identity,
PID, timing and readiness predicates remain. The focused second-identity probe
passed with exact restoration and zero builds (`performance-relay-fresh-probe-001/`).
The first full attempt remains retained in `performance-relay-device-001-raw/`;
these prerequisites do not establish full B/M/BR completion.
The next attempt completed all six cold samples, then failed because the additive
runner incorrectly imposed M's ten-second usability wait on B's core-only
operation. The unchanged B-Sim-3 harness measures `startNodeCore` return and
optional online timing; `P2PService.startNodeCore` intentionally omits warm tasks.
M-Sim-Hot uses full `startNode` and retains both ten-second waits. The additive
runner now keeps those scopes separate and performs the core-only observation
last, checking actual already-running resynchronization without using it as an
application-readiness claim. Forty-two oracle checks passed in
`performance-core-scope-causal-001.log`; the six cold samples, failed hot-core wait
and exact restoration remain in `performance-relay-device-002-raw/`.
The third full attempt completed cold and full hot-start samples, then observed a
real relay outage during the healthy-resume interval; its required already-online
event was absent (`performance-relay-device-003-raw/`). A single Maestro session
still spent about thirteen seconds paused and observed an outage, so separate
driver startup alone is an insufficient explanation. A one-second Appium MCP
background/resume probe emitted the exact already-online event with the same
process and identity; its session was deleted before exact package restoration
(`performance-relay-appium-probe-001/diagnostic-review.json`). The new healthy flow
uses one session and an explicit empty permission map because fixture setup already
grants notifications; the default Maestro launch grants permissions again. This
flow passed the focused device probe: launch took about 114 ms, the exact healthy
event appeared, the existing APK was reused with zero builds, and exact cleanup
passed (`performance-relay-healthy-probe-002/diagnostic-review.json`). Full B/M/BR
evidence remains pending. Actual
paused state is captured at the framework callback and is immutable, window-bound,
and unavailable after disposal or expiry. Fifty-five focused tests and nine
Maestro contracts passed in `performance-healthy-causal-002.log` and
`performance-healthy-maestro-001.log`. These diagnostic outcomes do not relax
the original healthy predicate or readiness deadlines.
The fourth full attempt passed healthy, degraded and extended resume, then the
new foreground recovery control rejected its command after observed relay loss
(`performance-relay-device-004-raw/`, exact restoration verified). The control had
added a second must-still-be-degraded check absent from the original M-Sim-2.
An additive causal test reproduced rejection after automatic reconnection. The
control now retains the actual post-disconnect loss observation within that
measurement window, requires foreground state, and invokes the real health
check and inbox drain exactly once. Missing observations, stale windows, repeated
operations and real operation failures remain rejected. Seventy focused checks
pass in `performance-recovery-causal-001.log`. The device probe deliberately
waited for automatic reconnection before the recovery command and passed with
actual recovery timing events, the same process/node, and exact restoration
(`performance-relay-recovery-probe-001/diagnostic-review.json`). Full B/M/BR
validation is separate from this causal probe. The fresh fifth full scenario
passed all twelve stages on the C10 candidate, using zero builds and one cache
hit, with exact restoration (`performance-relay-device-005/results.json`,
`performance-relay-device-005-raw/` and its cleanup review). Its selected wrapper
is still BLOCKED for omitted obligations; this is neither the final C11 identity
nor full migration closure. All four earlier full failures remain retained.

The additive composition guard covers admitted production-journey controls,
registered replacement runners and shared adapters. Six causal negative probes
reject implicit/explicit constructors, prefixed legacy-stack calls and named
repository factories (`composition-guard-host-scope-001.log`, nine tests total).
Its scope does not constrain intentionally isolated original component harnesses.

Fresh isolated checkouts must provision the pinned Flutter SDK's missing Gradle
wrapper files before build fingerprints are calculated. C8's first APK build
created three ignored wrapper files; the next build therefore had a different
source closure and Gradle-toolchain fingerprint. A read-only reconstruction
reproduced both exact input hashes, while the two APK hashes were equal
(`build-reuse-diagnostic-001.json`). Actual costs remain two builds, 68.345 and
50.081 seconds. Provisioning preserves existing wrapper files and records copied
SDK hashes; removing these real inputs from fingerprints is not a remedy.

For native XCTest setup, frameworks must exist before CocoaPods resolves the
conditional Go dependencies. The original C2 Pods configuration omitted GoMknoon
search/link flags, so `canImport(GoMknoon)` excluded the GoBridge type and native
371/373 stopped at compilation. The pinned framework import probe passes;
regenerating Flutter's iOS configuration before `pod install` retains the
repository's SwiftPM/CocoaPods split and restores the original lockfile bytes.
A direct early pod install temporarily added SwiftPM plugins to CocoaPods; that
generated configuration was corrected before any native build. Semantically
identical Xcode project sorting was also restored to its original bytes.
Native execution remains separate from these setup observations.
The C11 dependency preparation now completes with the Go frameworks and existing
local plist present before Flutter configuration and CocoaPods resolution.
`catalog-native-pods-preparation-001/review.json` verifies byte-identical original
Podfile lock, Xcode project and workspace files after setup. The iOS export
binding check also exits successfully (`catalog-native-bindings-probe-001.log`).
Neither setup result replaces fresh native 371/373 execution.
The earlier C9 original 371 run passed its Android checks, then failed at the
generic Runner build because the isolated checkout omitted the existing ignored
`ios/Runner/GoogleService-Info.plist`. The plist was copied byte-for-byte from the
main checkout and parsed without exposing credentials. No XCTest ran; the
original harness removed its owned DerivedData and the failure/cleanup review
remain in `native-retry-002/`. The later C11 `native-retry-004/` completed both
original 371 and 373 routes successfully: native 373's three mutations re-redded
the intended assertion, byte-exact source restoration passed, all 28 selected
Runner XCTest cases passed, and the generated binding phase was a digest no-op.
Owned DerivedData cleanup completed. The wrapper's overall BLOCKED disposition
reflects omitted full checks; it is not an integrated-main or full-suite PASS.

The MD-004 multi-device group runner also started its five-minute
`cli_group_join_fixture.json` deadline before the primary app finished building.
The first attempt is retained in
`.codex-test-logs/all-tests-y227gs8x/reliability-held-route-probes-004/logs/002.log`;
its primary log had not reached a test, and its owned Xcode build survived the
Flutter parent. Cleanup reviewed that exact process tree and terminated only
its descendants and the two owned simulator fixture apps. The existing
foreground campaign's preparation implementation now lives in
`integration_test/_support/prepared_ios_harness.dart` and serves both runners.
MD-004 prepares both exact role binaries before starting either the CLI peer or
an app; its CLI fixture path, relay defines, run ID, database names and five-minute
fixture deadline remain unchanged. Six host process contracts pass, including
both original foreground paths and the new MD-004 build-failure/Android controls.
Fresh native verification of the shared implementation is recorded below.
The next native attempt (`group-multi-device-preparation-device-probe-002`)
built both roles, synchronized membership, and delivered the CLI message with
the expected sibling unread count. It then timed out at the one-notification
assertion: the shared stack, like the foreground fixture above, still omitted
the visibility reader required by the listener's compatibility path. The stack
now reuses `TrackerBackedAppVisibility` with its existing paused lifecycle and
the same group tracker. All 227 existing group-listener tests passed and analysis
was clean (`md004-visibility-repair-001/`); the fresh native result follows.
The affected-group wrapper check also passed all 3,195 tests with zero skips
(`md004-visibility-change-001/results.json`). Main and isolated checkout input
identities match in `isolated-source-identity-review-006.json`.
Fresh native attempt `group-multi-device-preparation-device-probe-004` passed
on the existing iPhone 17 Pro and iPhone Air: both roles reported three passing
native tests, and the sibling completion signal followed the original
one-notification and device-local unread assertions. Role builds completed
before timed peers started (81.8 and 48.9 seconds). Earlier failures remain
retained; the complete owning suite still requires its final full invocation.
The soak runner had the same build/readiness coupling: its 120-second fixture
timer expired during Flutter preparation, before a fixture or scenario was
observed (`reliability-held-route-probes-031/logs/003.log`). It now uses the
existing simulator preparation helper before starting either peer, preserving
that readiness limit and the five-minute soak duration. Physical-device launch
paths are unchanged. The focused native recheck passed all three tests and
the five-minute soak, including four disconnects and two inbox-store rounds
(`soak-build-deadline-native-001/`). Preparation took 186 seconds; the app
fixture followed CLI fixture creation by 15.417 seconds. Workflow checks passed
240 cases with zero skips. The failed attempt, preparation log, timing receipt
and cleanup review remain in `soak-build-deadline-repair-001/`.

The CLI group-recovery fixture must use `currentIdentityDatabaseVersion` and
the shared production create/upgrade registry. Its old version-101 handwritten
list omitted migration 099, so a real relay delivery failed when the repository
inserted `group_messages.is_forwarded`. The first failure remains in
`reliability-held-route-probes-005/logs/001.log` under the all-tests run directory.
The fixture now reuses the registry; 18 migration tests and 337 group-harness
contracts passed, and analysis was clean (`group-recovery-schema-repair-001/`
and `group-recovery-schema-change-001/`). Its full legacy entry now invokes the
existing CLI-peer campaign too: a standalone fixture invocation without its peer
returns without exercising recovery. Both route contracts bind the runner and
fixture source hashes. The fresh group-recovery route passed on the physical
Android phone against the deployed relay (`reliability-held-route-probes-006/`),
including both live and offline message recovery.

Android invitation peers must retain their test installations until the
existing signal broker has finished. Flutter 3.47.2 defaults `flutter test`
to uninstall on role exit. In `reliability-held-route-probes-006/logs/002.log`,
decline, revocation and configuration convergence completed and the primary
exited successfully, but its final `alice_done` signal never reached the host;
the sibling timed out. Both app packages were absent after the run. The runner
now uses Flutter's existing `--no-uninstall` option on Android, preserving the
app-private signal files after a role stops. Existing deadlines and latency
capture barriers are unchanged. Twenty runner contracts and the expanded
357-test group-harness check passed with zero skips
(`invite-final-signal-diagnostic-001/`, `invite-final-signal-change-001/`).
The fresh invitation-reliability route passed on both Android devices in
`reliability-held-route-probes-007/`; the primary and sibling both completed
successfully with the original final-signal wait intact.
The runner now captures initially absent Android packages with the existing
`AndroidAppStateGuard` and restores that absence only after both role exits,
signal synchronization and host validation succeed. Pre-existing installations
are excluded from this cleanup, and failed runs retain diagnostic state.
This preserves the final signals without leaving a newly created install that
blocks the subsequent sound campaign. The fresh Android pair passed and both
main packages were absent afterward (`reliability-held-route-probes-014/logs/001.log`,
`invite-owned-install-cleanup-repair-001/native-restoration.json`); the existing
20 invitation runner contracts and 63 state-guard contracts also passed.

Real-repository direct-message harnesses must bind the existing
`DirectInboxCustodyDbBindings.loadOwnerForMessageId` callback as well as stage,
load, failure and completion callbacks. The repository's current
`supportsDirectTextInboxCustody` contract requires this owner lookup. Seven
constructions in the notification-during-other-chat, routing, Wi-Fi fallback,
soak and basic smoke harnesses omitted it. The notification sender therefore
returned `missing_direct_inbox_custody_capability` before attempting delivery;
the receiver subsequently timed out waiting for its notification. The repair
only supplies the existing callback, preserving production behavior and native
assertions. Ninety repository/database tests passed. The next native attempt
sent successfully but exposed a separate missing receiver delegate:
`dbApplyIncomingOrdinaryTextMutation`. Without that callback, the repository
refuses the decrypted ordinary text before persistence. Nine constructions in
the same harnesses plus transport and conversation-bridge now bind the existing
atomic database helper, as the notification-sound harness already does.
The 80-test database-helper suite and 21 legacy-runner contracts passed.
The fresh notification-during-other-chat route then passed its warm, cold and
same-peer routing assertions on the simulator pair
(`reliability-held-route-probes-011/logs/001.log`). The other changed harnesses
still require their own native results. Evidence and preimages:
`custody-harness-binding-repair-001/` and
`custody-harness-incoming-repair-002/`; both preceding failed runs are retained.

Routing smoke must attach its existing incoming router and chat/deletion
listeners before starting the node, and retain them across node restarts.
The broadcast stream survives restart: replacing its listener after startup
can lose the inbox replay between the drain and subscription. Both peers must
bind the existing ordinary-text mutation and incoming deletion database
callbacks; voice/media fixtures must also bind the existing generic-save and
outgoing media-custody delegates. The direct S8 receipt is a boolean, whereas
the group G5 receipt is a timing map; their criteria must preserve that
distinction. Host verdicts for S3, S8, S9, S10 and S11 now require actual receiver
receipts, committed deletion and successful send outcomes. Previously some
returned PASS despite missing delivery or failed sends. The focused criteria,
router and deletion-listener tests pass, and all 19 direct routing checks passed
in `reliability-held-route-probes-015/logs/001.log`. That owning route still
failed before its group assertions because simulator installation ran out of
disk space; it is not a complete routing pass. The unchanged group app then
installed in 2.142 seconds after verified storage recovery
(`routing-install-space-recovery-001/install-probe.json`). Keep the first false
green, corrected-criterion failures and later environment failure separately;
the fresh complete route passed all 27 checks (19 direct and eight group) in
`reliability-held-route-probes-020/logs/001.log`, with a hash-bound PASS receipt
in that directory's `routes.json`. The broader `full-sims` owner remains pending.

The subsequent invitation-latency closure completed all 30 samples, but its
`create|online-cold` median was 1,458.2 ms against the unchanged 1,300 ms limit.
Both role exits were successful; the host performance rejection still makes
the route fail. The live-send phase dominated this cell, and existing bridge
responses identify relay transport. Numeric-only native stream-open, write and
ACK timings are retained in the existing send-response flow event. A second
30-sample capture failed at 1,387.28 ms and identified relay stream opening
at 746–1,034 ms. Group creation now starts the existing connection-only
`warmPeer` operation for unique validated recipient transport IDs before local
group persistence, overlapping connection setup with that work. Invitation
encryption, delivery and persistence still follow their original order.
The fresh 30-sample closure passed with a 1,252.374 ms cold-create median;
all recipients observed exactly one event. Neither the 1,300 ms limit nor
the cold-recipient restart conditions changed. Two causal tests verify that
group creation proceeds while warming is pending; affected group checks
passed 3,197 tests, with 162 schema and 627 notification contracts passing.
Evidence: `reliability-held-route-probes-007/logs/002.log`,
`reliability-held-route-latency-timing-probe-001/`,
`invite-warm-overlap-repair-001/`, `invite-warm-change-001/`, and
`reliability-held-route-latency-warm-probe-001/`. Retain both first failures;
do not replace closure mode or relax its limit to obtain a pass.

The 1,252.374 ms pass did not establish a stable margin: the later owning
`restart-checkpoint-014-reliability-permissions/` run completed all thirty
samples but failed at 1,385.823 ms. Its production post-frame settlement marker
was delayed by the harness's 100 ms frame pumps plus 40 ms polling pauses.
A live-binding probe with late asynchronous completion measured median
113.029 ms versus 24.402 ms after using 16 ms pumps without the extra pause;
the earlier fast-completion probe did not reproduce and is retained. The helper
now pumps near 60 Hz, preserving the production callback, all samples, actual
cold node restarts and the 1,300 ms gate. Affected harness contracts passed 357
checks. The native recheck (`invite-latency-frame-native-001/`) reduced median
navigation settlement to 90.335 ms, but still failed the overall gate at
1,392.872 ms because other phases took longer. This remains an unresolved
performance shortfall; neither role success nor the cadence correction closes
it. Captured send responses identify relay transport. The harness artifact's
`direct` label means live wire acknowledgment, not independent evidence of a
direct network path.

The invitation runner's initial-install state guard must restore from its outer
`finally`, including host performance rejection and unsuccessful role exits.
Its earlier success-only restoration left run-created Android installations
after both latency failures and later blocked the sound campaign before launch.
The original retained manifest proved both packages were initially absent;
loading that manifest through the existing guard restored both targets. A
failure injected immediately after real guard capture reproduced a retained
recovery directory with the original runner and verified restoration with the
fixed runner, preserving the original exception and excluding success output.
Evidence: `invite-failure-cleanup-repair-001/restoration.json` and
`invite-failure-cleanup-repair-001/failure-probe-result.json`. This cleanup
repair does not resolve the remaining latency shortfall.

Both media-journey full routes must enable the existing
`GIF_MANUAL_ACCEPTANCE=true` test define. Without it the native image journey
passes but the animated-GIF acceptance case is skipped, as retained in
`reliability-held-route-probes-008/logs/003.log`. The existing GIF assertions
cover the picker preview, sender/receiver grids and full-screen viewers; the
fresh run executed them as well as the image case and passed with no skips
(`reliability-held-route-probes-009/logs/001.log`).

The Android sound campaign deliberately requires an absent test package before
any child starts, because it verifies exact notification-card/channel baseline
restoration. A retained invitation test install therefore blocks its setup;
remove only the explicitly authorized test package under its device leases.
The first complete Android run passed all 16 programmatic/OS scenarios and
restored both baselines, but failed its five-second signal-sync cleanup bound.
The synchronizer had checked its stop flag only before a whole batch, allowing
remaining file/device operations to continue after the Flutter roles exited.
It now checks the same flag between operations, preserving the cleanup limit.
A one-off probe executing the original/current synchronizer with held I/O
failed/passed respectively; existing sound-disposition contracts and analysis
passed. The fresh complete device campaign then passed all 16 scenarios,
stable conversation card IDs, cleanup and exact state restoration
(`reliability-held-route-probes-013/logs/001.log`). Evidence:
`notification-sound-setup-recovery-001.json`,
`reliability-held-route-probes-012/logs/001.log`, and
`notification-sound-sync-repair-001/`. Non-interactive OS/channel evidence does
not establish that a person heard sound from the speaker.

The media sound sequence (S5–S13) must retain its card within each conversation
and clear only between lanes. Clearing after each item conflicts with the
primary-channel continuity assertion: the next tone-debounced item is then a
first silent publication, which correctly uses the silent channel. Checkpoint
`restart-checkpoint-012-reliability/` retained this S12 failure with `silent=true`
and an exact restored Android baseline. The fixture now preserves the card;
production channel selection, the disposition contract, S14's strict same-ID
silent-update assertion and deadlines are unchanged. Existing active-card and
first-silent preservation tests passed (17); the notification change gate passed
88 tests. `notification-sound-channel-native-001/` passed all sixteen
programmatic/OS scenarios and exact restoration. Its media flags were audible;
S14 separately observed `[false, true]` on the primary channel. The subsequent
owning run `restart-checkpoint-013-reliability-repaired/` also passed all sixteen
sound cases and exact restoration; S13 observed `silent=true` on the retained
primary card (`sound-retained-summary.json`). This supplies native evidence for
the repaired media debounce path. The parent reliability run failed later in
the separate iOS notification matrix and is not a full-family pass.

Host-only full-run fixtures must use a temporary lease directory with the real
lease implementation. Otherwise a concurrent native campaign can block a
synthetic task on `mknoon.shared-native-build`. The cancellation fixture also
must not signal the test process unless its owned child actually started:
after a blocked run returns, the runner has already restored the signal handler.
The first failures are retained under `shared-preparation-change-002/` and
`shared-preparation-change-003/` in the all-tests run directory. The CLI fixture
and seven scheduling/cancellation checks passed while a real native build held
the global lease (`host-cli-lease-isolation-test-001.log` and
`host-full-fixture-lease-focused-001.log`). Production lease paths and exclusion
remain unchanged; the complete workflow recheck is recorded below.
The broader run then exposed the same global-lease dependency in CI acceptance
and synthetic device/postprocessing fixtures (`shared-preparation-change-005/`).
Isolation now belongs to their shared `RepositoryFixture`; explicit fixture
lease directories still take precedence. All 19 affected CI, scheduler and
cancellation checks passed while the native campaign held the global lease
(`shared-repository-lease-focused-001.log`). The expanded 230-test workflow had
previously completed in 177.156 seconds and then hit its 180-second aggregate
budget during concurrent compilation. Its aggregate budget is now 360 seconds;
the individual fixture and device deadlines and selected assertions are unchanged.
The complete workflow recheck passed all 230 tests with zero skips in 146.817
seconds (`shared-preparation-change-006/results.json`) while native preparation
continued. This validates the host fixture repair, not the remaining device suite.
The duplicate `full-workflow` selection must preserve that canonical aggregate
budget as well as its exact test list. It still used 180 seconds after the change
entry had moved to 360; checkpoint `restart-checkpoint-015-major-source038/`
stopped at 180 seconds with cleanup OS error 1 and no retained raw test output.
The same 240-test suite had just passed in 214.349 seconds through change mode.
The full entry now matches the existing 360-second budget; individual fixture
and device deadlines remain unchanged. A composition contract checks both the
selection and budget against the canonical workflow entry. Evidence:
`full-workflow-budget-repair-001/`; owning verification remains pending.

The generic `testNotificationTap`, `testColdNotificationTap`, and
`testTapExistingNotification` full-suite entries use the existing simulator
APNs fixture campaign's explicit `--native-selector` mode. It accepts only the
three declared single-case pairings, requires zero automatic retries, pins the
simulator, disables parallel XCTest cloning, and forwards actual native method
results for exact receipt validation. Warm/cold native-to-Dart routing assertions
remain in the campaign. These methods have no physical-only or real-provider
assertion; physical APNs/NSE, reaction and Local Network proofs retain their
separate owners. Focused host contracts verify orchestration, fail-closed
argument handling, fixture ownership and both build paths. The synthetic direct
matrix sender must exist in the recipient contact repository before launch;
otherwise cold routing fails, and a native foregrounding assertion alone can
falsely accept a warm route failure. The runner stages the matching contact via
the existing debug-only `intro_e2e_config.json` repository seam, enables
`E2E_TEST_MODE` and `PRODUCTION_FCM` in both build paths, refuses foreign fixture
commands, and rejects
`REMOTE_NOTIFICATION_ROUTE_ERROR` as well as the cold bridge error. Production
missing-contact behavior remains unchanged. All three exact native selectors
passed with their host route assertions in `restart-checkpoint-010-notification-fixture/`
and `restart-checkpoint-011-notification-preservation/`; the full matrix remains
a separate obligation. The original warm false-positive and cold failure, copied-log
causal probe, 73 passing Dart preservation tests, and 236 passing workflow
contracts are retained in the all-tests run directory under
`notification-contact-fixture-repair-001/` and the checkpoint reports.

The production-push opt-in is required even for simulator fixture pushes:
ordinary E2E mode suppresses push registration and its OS permission request.
In `restart-checkpoint-013-reliability-repaired/`, native warm preparation passed
but the body assertion failed after the host push; current native settings were
still authorization 0 / alert 0. Warm host relaunch now requires fresh authorized
alert settings before sending, and the full matrix binding explicitly sets
`--retries 0` (the runner default is also zero). The source-028 probe
`notification-permission-warm-probe-001/` started at authorization 0, observed the
real permission request become authorized, then passed the original two-stage
warm tap and routing assertions. Twelve focused orchestration/binding tests,
twelve permission/push preservation tests, and 238 workflow contracts passed.
This probe does not close the full twelve-case matrix or certify provider delivery.

Cold delivery also requires permission preparation on its own simulator. The
next full matrix passed all six warm cases, then failed cold direct video because
the second simulator had never launched to request permission. Actual Appium
MCP inspection confirmed authorization 0 and the visible permission prompt,
without granting it (`notification-cold-permission-failure-001/`). Installation
now uses the existing native warm preparation helper, verifies authorized alerts,
and terminates that setup launch before scenario execution. Its log/result bundle
is separate from the exact selected test receipt. The unchanged cold direct-video
tap and routing checks then passed from initial authorization 0 in
`notification-cold-permission-probe-001/`; workflow contracts passed 240 with no
skips. The original complete xcresult and exported recording are retained. The
fresh full matrix then passed all six warm and six cold cases with zero retries
(`reliability-held-route-probes-032/logs/007.log`, native result directory
`20260923T171221Z`). This verifies the complete simulator matrix; the broader
full reliability owner and real-provider proofs remain separate obligations.

The six payload XCTest methods already execute inside
`notifications.ios_payload_fast_path`. Their full-suite ownership reuses that
existing three-phase campaign instead of requiring six independent UI fixture
setups. `sims_native_xctest_receipts.py` joins the verified parent artifact to
each phase receipt by SHA-256, then verifies the recorded UI-log hash and the
exact native selector counts using the shared XCTest parser. All three phase
receipts must belong to one capture. Both the exact capability and its scoped
method receipt are required; a parent-only PASS, changed/missing log, duplicate
phase, skipped case or unexpected selector cannot complete the method. Native
receipt failure also blocks the full owner. Offline contracts exercise this
join and the real executor's status propagation with synthetic process output;
they are not physical-device proof. Fresh full-suite closure remains pending.

`full_inventory` also owns exact singleton reaction selections, all eight UI
performance dispatches, the 17 original benchmark dispatches and their distinct
CLI-peer fixtures, native proof wrappers, true-release PB266 instrumentation,
plugin JUnit and standalone Dart assertion mains. FEED aliases its existing
direct `registerFeedPerf()` entrypoint, including its explicit skipped cases.
Changed standalone Dart mains reuse these exact assertion-enabled adapters in
change selection. Changed device tests also reuse a unique exact native adapter
already named by `full_inventory.obligations`, including PB266's release
instrumentation recipe. Unknown or ambiguous non-host test ownership still fails
closed; no generic device command is invented.
JUnit adapters inspect exact selected-class reports even when Gradle exits
nonzero, so an observed assertion failure remains FAIL instead of being hidden
as a process/setup blocker. Passing XML cannot override a nonzero process exit,
and the wrapper's stale-report rejection still applies. The PB266 release proof
exposed this boundary with a real device failure: its three schema-version
expectations still named 117 after production moved to 119. Schema bumps must
keep the head, upgraded-database and fresh-database expectations aligned with
`currentIdentityDatabaseVersion`; encrypted reopen, wrong-key rejection,
migration idempotence and Settings remount assertions remain required. The first
failure and parser RED are retained under
`.codex-test-logs/all-tests-y227gs8x/native-config-repair-002/pb266-first-failure-review/`.
The same stale 117-versus-119 head assertion later stopped all six cases in
`direct_inbox_custody_outbox_sqlcipher_proof_test.dart` before database creation
(`sims-reliability-continued-002/full-sims-0-routes/logs/013.log` under that run
root). Review related native proofs when the schema advances: direct inbox,
direct notification/reaction, group exit, group notification and self-removal
proofs also compare the upgraded or freshly opened database to the current
head. Their historical starting versions and downgrade-refusal boundaries
remain fixed; updating the final head must not remove custody/data assertions.
The group-notification export manifest also reports the current schema, so its
stale 116 expectation required the same correction. All six affected native
proof files then passed on the physical Android target (eleven cases across
`sqlcipher-device-probes-001/` and `sqlcipher-device-probes-002/` under that run
root); these focused probes do not close the complete reliability owner.
The protected reliability PB266 route reuses the existing full-regression
profile-drive command: a default debug `flutter test` invocation violates its
explicit `kDebugMode == false` prerequisite. The independent
`full.native.pb266-release` adapter still requires true release instrumentation;
profile execution does not satisfy that variant. Source-pinned legacy records
must be reviewed and refreshed when the proof file changes.
The six previously missing UI performance dispatches select desktop macOS,
where their registrations execute; mobile self-skips are not performance proof.
The iOS media stable-ID leg has its own pinned simulator selection. General UI
and posts routes remain in legacy.

The protected `gate benchmark-sim` partitions those same 17 scenarios into
`A,B,BR,C,D,E,F,G,I,J,K,L,M,N,R` on the pinned `android-physical` role and `GP,H`
on the pinned `ios-simulator-a` role (`devices.ios_simulator`). Both roles are
leased and freshly preflighted before either invocation. Each invocation uses
an exact `--scenarios` list and must return exactly one target/selection-bound
`FULL_BENCHMARK_SELECTION` receipt after its children complete. An independent
assertion failure does not omit the other partition or erase the failure;
cancellation and timeout still stop owned work. Android ROUTING_PATHS retains
its inline CLI fixture and pinned stage channel with all eight stage proofs.

GP/H retain the existing iOS simulator + host Go CLI topology documented in
`Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
(H-Sim, GP-Sim and the simulator rerun notes). This is specifically a shared
host-filesystem protocol: the scripts pass an absolute private temporary
`BENCHMARK_SHARED_DIR` and run ID; the app harnesses use `File` directly at
`gp_<run>_<name>` / `h_<run>_<name>`. GP also reads the absolute
`CLI_PEER_FIXTURE` through `loadCliPeerFixture`. There is no Android or physical
iPhone path broker in these scripts. Protected GP/H therefore reject those
roles (and desktop roles) before launching any child. The boundary regression
executes the actual harness file helpers with the captured compile defines,
proving fixture and signal path agreement; its synthetic leaves do not certify
an installed simulator app or produce product benchmark results.

GP/H must observe the exact Flutter benchmark `testStart` before starting the
three-minute peer-fixture handshake. `independent-checkpoint-001/` exhausted the
old handshake deadline during the iOS build, with only the loading test started.
The existing completion observer now provides a separate bounded startup wait
and rejects an early child exit; signal deadlines and terminal assertions are
unchanged. Four causal startup tests and all 193 workflow checks passed in
`benchmark-start-change-002/` under `.codex-test-logs/all-tests-y227gs8x/`.
The separate group-publish and timeout-accuracy owners subsequently passed on
the pinned iOS simulator in `benchmark-device-repair-001/results.json` under
the same run root. Those recorded-candidate passes do not replace final full
verification after later changes.

Protected benchmark scripts require `MKNOON_RELAY_ADDRESSES`, supplied from
`full_suite.relay_addresses`, before any child starts. The bounded parser accepts
comma-separated DNS/IP TCP (optionally WS/WSS) or UDP/QUIC-v1 multiaddresses with
Ed25519/SHA-256 libp2p peer IDs; missing, empty and malformed inputs fail closed.
The same normalized list is sent explicitly as Go `start.params.relayAddresses`
and Flutter `--dart-define=MKNOON_RELAY_ADDRESSES=...`. Only direct, unprotected
invocations with the variable absent retain legacy public defaults. The audited
route hashes the suite, both independently launching scripts, the boundary and
completion helpers, and the host-file protocol sources.

The full legacy command depends on the SIMS aggregate. Its curated host paths
emit explicit `HOST_RESULT_ALIAS host.dart.all <path>` rows and consume the
canonical host result. The seven old directory sweeps, host benchmark duplicate
and exact duplicate typed campaign routes are omitted with result aliases in the
ledger. Direct legacy invocation retains its 95-route default. Go tagged/race
variants and non-equivalent platform/configuration routes remain distinct;
protected legacy work uses the exact per-route contracts in
`tool/testing/legacy_target_contracts.json`. Each known leaf verifies its target
owner source hashes, acquires its own device leases and completes fresh
preflight before any build, preparation or device action. Unknown routes or
changed owners block that route; independent known routes remain runnable.
This is not universal assertion-level deduplication of nested legacy composites.

Additional adapters execute inside `mknoon_checks.py`'s existing scheduler and
leases. `--plan` records each concrete command template, target role and required
configuration key. Runtime values belong under `full_suite` in `--device-config`;
per-check overrides live under `full_suite.adapters.<check-id>`. For example:

```json
{
  "isolated_test_environment": true,
  "fixture_reference": "private/isolated-fixture-receipt.json",
  "devices": {
    "android_physical": "PINNED_USB_ANDROID",
    "android_emulator": "PINNED_ANDROID_EMULATOR",
    "ios_physical": "PINNED_USB_IPHONE",
    "ios_simulator": "PINNED_IOS_SIMULATOR",
    "macos": "macos"
  },
  "full_suite": {
    "service_account": "private/provider.json",
    "relay_target": "AUTHORIZED_STAGING_TARGET",
    "relay_key": "private/staging-key",
    "relay_addresses": "AUTHORIZED_RELAY_ADDRESSES",
    "group_staging_manifest": "private/group-staging.json",
    "direct_staging_manifest": "private/direct-staging.json",
    "group_media_ios_fixture_driver": "private/group-media-observer",
    "ios_ui_fixtures": "private/ios-ui-fixtures.json",
    "adapters": {
      "full.reaction.android_physical_recipient": {
        "staging_manifest": "private/direct-staging.json",
        "capture_manifest": "private/direct-capture.json"
      }
    }
  }
}
```

These are placeholders, not a runnable provider configuration. Supply only live
pinned targets and authorized isolated fixtures. Four-party group campaigns use
`devices.ios_simulator_a` through `_d` plus the existing explicit
`full_suite.ios_disposable_simulator_ids` authorization. An absent optional target
is `N/A (target unavailable by project policy)` after successful live discovery;
unknown discovery, absent configuration/credentials, or an unavailable supplied
target remains precisely blocked. Missing fixtures are runtime prerequisites,
separate from inventory completeness.

Physical iOS group-notification scenarios require a physical Android sender
and physical iPhone recipient. Their group staging manifest uses `provider=apns`
and the scenario-specific `iosCapture` selectors returned by
`groupReactionNotificationIosSelectorsFor`; neither the Android FCM group
manifest nor the separate iOS payload-fast-path attestation has that schema.
Reuse the existing selector helper and staging validator when preparing this
configuration. The chat-group iOS capture additionally requires the existing
central `android.production_fcm` and `ios.device.production` artifacts through
its four prebuilt artifact/report arguments. Prepare them with
SIMS `--prepare-builds`; the capture joins exact artifact bytes, cache-adjacent
attestations and build reports no older than one hour. A prepared build or
accepted manifest is not a passing device scenario. The full-suite adapter also
passes the existing `--no-child-builds` setup-app path and exact directory digest,
so a prepared signed setup app is reused instead of rebuilt inside the capture.
Configuration/topology
failures and their cleanup journals remain in the original run artifacts.

The physical-iPhone setup attempt in
`.codex-test-logs/all-tests-y227gs8x/ios-group-deployed-004/` passed its one
permission-settling XCTest but failed before identity export or notification
assertions. The native receipt said `dart_main_not_reached`; the retained
unified log instead established a Dart `setup entry launch binding rejected`
exception. Dart's iOS process-environment implementation returns an empty map,
so `Platform.environment` cannot carry XCTest launch inputs. The existing
setup-entry channel now reads only the three accepted launch fields from its
native coordinator, in memory, with the same profile gate and acknowledgement
binding. Host tests preserve rejected profiles, malformed inputs and receipt
privacy. The exact native entry test also passed on the available iPhone 17 Pro
simulator (`ios-startup-native-001/result.xcresult`, one test, zero skips);
the physical iPhone startup probe then passed the existing receipt classifier
with its fresh launch hash and exact identity-export bytes
(`ios-group-startup-probe-002/startup-verdict.json`). Appium observed the running
app and relay readiness; its later screenshot shows a Local Network prompt,
which was not graded as settled by this startup probe. Group notification
delivery remains a separate campaign assertion.
The original receipt, app diagnostics and Appium ownership/cleanup review are
retained under `ios-group-startup-probe-001/` beside that attempt.

The subsequent `ios-group-deployed-005/` attempt passed that initial startup
boundary, then timed out on contact fixture completion. Its device log confirmed
that the host's contact-stage `--terminate-existing` relaunch omitted the setup
inputs and failed the entry gate. Preserve the same campaign-owned setup binding
on every setup launch, including the existing group-creation and target-author
XCTest selectors. The host uses CoreDevice's `DEVICECTL_CHILD_` environment
forwarding only during Plan-397 fixture staging; the XCTest selectors share the
existing validation and forwarding helper. Production-normal and trace-only
launch paths retain their own behavior. Keep the original three-minute contact
completion deadline and success assertion. First-failure evidence is retained in
`ios-group-contact-probe-001/`; the prior ready receipt alone does not prove that
a later unbound process started successfully.

The wrapper's temporary Python execution fixture must declare its isolated
resource. Without that declaration, conservative unknown-resource handling takes
the shared native-build lease, and three otherwise passing wrapper self-tests
block when a Flutter check runs concurrently. The retained first failure,
serial diagnostic pass and held-lease reproduction are
`ios-startup-mapping-001.log`, `ios-startup-mapping-002.log` and
`ios-startup-mapping-lease-reproduction.json`. The fixture regression rejects
any native/device lease request while still executing its real Python child;
production build/device ownership rules remain in force.

XCTest adapters build into fresh private DerivedData and run each exact method,
checking named passing test cases rather than accepting `TEST SUCCEEDED` alone.
`ios_ui_fixtures` is a private JSON object keyed by `Class/testMethod`; each entry
contains `target_id` and an `environment` object with the method's `MKNOON_`
variables. Its prepared application, notification, call and provider state must
match that method's source contract. Fixture helpers that wait for a host action
still need that live fixture; the adapter does not invent a notification/call.
The synchronized group-media XCTest stays owned by its existing iOS controller.
The empty macOS `testExample` template and the Java FlutterTestRunner bootstrap
are documented support; the latter's actual Dart assertions additionally run in
a true release instrumentation variant. The APNs ten-minute external-provider
capture stays explicitly manual. No manual capture, deployment or simulator-wide
shutdown helper is launched automatically.

Composite file, scenario, listing and result-alias mappings carry exact
`receipt_bindings` by capability or route. Every original attempt participates:
an unavailable child remains N/A, a missing or duplicate child remains NOT RUN,
and an earlier child FAIL survives later PASS. Parent PASS cannot replace a
child receipt. Filtered or ambiguous runner argv cannot own a whole file. The
host batch's audited `Flutter batch path` listing retains its canonical
`host.dart.all` owner; full mode does not launch a second automatic host batch.
The legacy dispatch's exact file-to-route mappings are explicit in the manifest.
Their registration does not waive runtime prerequisites or target protection.

The wrapper passes its leased runtime assignments to SIMS through
`SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON`. Binding pins every supplied role,
blocks discovered but unprotected targets and automatic preparation, and retains
policy N/A for genuinely absent targets. Extra configured roles used by nested
legacy SIMS routes also receive device leases and Android preflight. Omitted
pins cannot inherit an ambient peer. Opaque SIMS rows declaring `unknown`
resources block under this boundary because their device selections are not
accounted for; a shared build lease never substitutes for device ownership.

Native proof adapters `full.native.371` and `full.native.373` require
`devices.ios_simulator`. The wrapper leases that exact ID and rechecks its live
simulator availability before invoking the native script. Both scripts require
`MKNOON_NATIVE_IOS_SIMULATOR_ID`, select only that ID, reject protected-map
mismatches and refuse fallback. Their host and simulator assertions remain one
combined obligation: absent simulator hardware makes the combined adapter N/A,
not a claim that host execution proved XCTest assertions. Native/XCTest failures
retain the campaign cleanup barrier. Availability checks do not establish that
external iOS automation is idle.

Before their native Xcode builds, both adapters refresh Flutter's generated
configuration with `flutter build ios --simulator --debug --config-only --no-pub
--target lib/main.dart`, the existing notification-smoke preparation path.
Running Flutter integration tests first can leave `Generated.xcconfig` pointing
to a deleted temporary `flutter_test_listener/.../listener.dart`; Xcode then
fails in `kernel_snapshot_program` before XCTest starts. The retained
`native-371-build-probe-001` logs under `.codex-test-logs/all-tests-y227gs8x/`
show that failure and the same build succeeding after the configuration refresh.
The subsequent `native-config-repair-002` owning checks passed: Plan 371 ran two
Android methods and eight exact XCTest methods; Plan 373 verified all three
intentional mutation failures, restored-source GREEN and its 28-method native
baseline with zero skips. The final wrapper reported no source/configuration
drift. Original failures remain retained. The Swift compiler's separate
exit-zero/incomplete-output diagnostic also appeared in the successful build;
it was not the proven blocker.

The Plan 373 intentional mutation runs use `-collect-test-diagnostics never`:
Xcode 27 otherwise spent 600 seconds collecting a simulator sysdiagnose after
each expected assertion failure. Exact semantic failure logs, xcresults,
one-failure/zero-skip checks, fixture census, fresh DerivedData and source-hash
restoration remain required. Restored-source and baseline runs retain ordinary
failure diagnostics. The original three diagnostic collections are retained in
`native-config-repair-002`. The later `vc204-373-repair-001` owner passed all
three exact mutation checks, restored-source GREEN (one test), the 28-method
baseline and privacy/binding checks. Every phase had zero skips. Its original
report retains a cancellation-time toolchain-drift diagnostic: omitted checks
left the cancellation event on the reporting thread, cancelling final version
probes. A fresh version/package comparison matched every original identity
field, and a causal wrapper test reproduced that false diagnostic. Final audits
must clear the reporting thread's check cancellation state after workers drain;
the cancellation gap and unfinished checks remain unchanged.

`devices.android_emulator_second` and `devices.ios_simulator_a` through `_d`
are supported extra roles. `ios_simulator` aliases the `_a` role; conflicting
pins are invalid. Every forwarded SIMS target, including configured extra roles
and the macOS performance target, is protected and leased; each configured
Android role gets instrumentation preflight. Do not supply an unpinned target
through ambient environment variables.

The protected full invocation executes all **80 selected legacy routes** and all
**67 cleaned reliability selections** through `scripts/legacy_target_contracts.py`.
The shell listings still determine the selection; their ordinary direct defaults
remain unchanged (95 routes for direct full regression). The reliability adapter
is serialized with `performance.global` and has an explicit legacy build
exception because its audited children own their existing builds. Device
ownership comes from each route's leases and preflight. The `unknown` resource
guard remains in force for opaque SIMS rows.

Group-lifecycle route identities retain the `:GROUP_SIM_SCENARIO=<value>`
suffix, but their Flutter argument must be `--dart-define=GROUP_SIM_SCENARIO=<value>`
with the key only once. A duplicated key made the dispatcher register its
unknown-scenario failure before entering any scenario. The original device
failure is retained in
`.codex-test-logs/all-tests-y227gs8x/sims-reliability-continued-003/full-sims-0-routes/logs/023.log`.
The binding regression compares all four selected values against the existing
Dart dispatcher's cases; route labels, scenario assertions, and device pins stay
unchanged. The corrected four native scenarios passed seven cases in
`group-dispatch-device-probes-001/` under that run root, after all 197 runner
contracts passed. This focused verification does not close the complete owner.

Use the same one-command full runner with an explicit baseline and pinned config:

```bash
python3 scripts/mknoon_checks.py full --base "$BASE_REF" --local \
  --device-config "$DEVICE_CONFIG" --jobs 3 --flutter-workers 4 --sims-jobs 2
```

`isolated_test_environment: true` and `fixture_reference` are required for device
routes. Set `full_suite.relay_addresses` to the authorized isolated relay; the
adapter never substitutes the legacy production default. Supply the provider
and signing inputs already required by each typed campaign. Missing fixture or
provider inputs remain BLOCKED. Static SDK/analyzer/classification commands run
without device pins. Successful discovery is required before an absent optional
target can become N/A; an invalid supplied pin never becomes N/A.

Roles stay local to each route. Android-capable two-peer transports use
`android_physical` plus `android_emulator`. Existing wrappers whose protocol uses
host-shared simulator directories receive `ios_simulator` (canonical alias
`ios_simulator_a`) and `ios_simulator_b`; four-role wrappers additionally receive
`ios_simulator_c` and `_d`. The intro reset route requires
`full_suite.ios_disposable_simulator_ids` naming exactly those four pinned IDs.
No absent optional simulator is selected or booted automatically. The direct
private-media journey receives its actual `--sender`/`--recipient` arguments;
the visibility proof receives fresh build/artifact/result directories and its
exact scenario. All original general UI, posts, and scenario selections remain.

The device-local private-media journey must create its fixture database at
`currentIdentityDatabaseVersion` through the existing production migration
registry. Its prior fixed version 100 lacked the custody-intent column added
by migration 110, while the current message serializer already writes that
column. The retained sender diagnostic at
`.codex-test-logs/all-tests-y227gs8x/private-media-sender-causal-probe-001/`
failed at the first fixture insert. Historical migration-boundary proofs keep
their explicit versions; this journey instead tests current production writers,
SQL state transitions, and rendering. Its protected route also pins the native
harness source. The journey runner intentionally discards raw child output,
so its generic exit-code failure alone does not establish a cause; capture the
exact existing leaf privately before diagnosing it.
After the schema correction, the next native failure reached the old inline
Delete expectation for a consumed view-once receipt. That presentation was
superseded by the compact receipt and outer long-press menu: the existing
`direct_private_media_card_test.dart` proves the outer Reply/Delete paths.
The native journey now opens that same menu after attachment cleanup and
repumping, requires a visible Delete action and the exact message callback,
and retains the absent-inline-action and privacy checks. The 134 existing
card/viewer/artifact cases passed in `private-media-terminal-host-001/` under
the same run root; native journey closure remains separate.

The sender pending-open subproof exercises the one-shot SQL lifecycle and must
seed **view-once**, then tap its `private-media-card-visual` tile. Plan 302 made
outgoing protected opens lease-free and repeatable; expecting `opening` from a
protected row is stale. Existing real-database tests in
`direct_private_media_sender_pending_open_test.dart` preserve protected reopen
and byte-retention behavior. The native fixture keeps its exact
`available → opening → viewing → consumed` sequence and attachment/file deletion
assertions. Grant settlement/release also covers assertions before route push,
so a failed assertion cannot leave controller disposal awaiting an unmounted
viewer. The related 154 host cases passed without skips, and the complete
physical-Android/available-emulator journey passed in
`.codex-test-logs/all-tests-y227gs8x/private-media-journey-device-probe-004/`.

The SQLCipher capability file includes a cross-platform artifact case that
skips when neither portability define is supplied. Full legacy routes now use
`scripts/migration_sqlcipher_portability.py` to run the existing Android export,
copy only that run's snapshot/metadata through pinned `adb run-as`, and run the
existing verifier on an available iOS simulator. These native assertions prove
cipher parameters, checksum, schema and rows; Appium UI cannot establish them.
The adapter requires three cases and zero skips on each platform. Android export
uses Flutter's `--no-uninstall` until `run-as` transfers the fixture, then removes
the unique fixture and its test app before verification. The six native cases
passed without skips in
`.codex-test-logs/all-tests-y227gs8x/sqlcipher-portability-device-probe-001/`:
the physical Android's snapshot was imported by the available iPhone 17 Pro
simulator. The 200 workflow and five provider-schema cases also passed in
`private-media-portability-change-002/`; full owning checks remain separate.

Each route writes a private log and an exact hash-bound receipt. The parent
requires unique, ordered child identities, matching summaries and unchanged
logs. Reliability source and scenario obligations join these route receipts;
parent success cannot replace a missing child. Device failures retain the
cleanup barrier; host-only routes can still run. Original first failures remain
visible after a diagnostic rerun.
Child execution and parent inspection share skip/empty-run detection, including
Flutter's expanded `+2 ~1` output. A zero exit with a skip blocks the child and
holds later device routes for cleanup review; an earlier skipped child cannot
be reported as PASS merely because a later route already failed.
Skip counters must occur in Flutter's timed progress syntax: protocol estimates
such as `Sending ~100KB` are not skipped tests. ANSI-colored counters still count,
and the zero-test sentinel must not match `100 tests passed`. The causal red and
28 passing parser/legacy-receipt contracts are retained under
`.codex-test-logs/all-tests-y227gs8x/legacy-approximate-size-parser-repair-001/`.
The original transport receipt remains BLOCKED even though its 37 device
scenarios and 32 host assertions passed; replaying its log through the repaired
parser is diagnostic evidence, not a replacement for the owning full-suite run.
The protected Wi-Fi fallback route explicitly passes `--retry 0`; its standalone
runner otherwise repeats a failed device campaign twice before returning.
Preserve the first attempt and review cleanup before a fresh invocation.
The iOS notification runner accepts `IOS_NOTIFICATION_TAP_SMOKE_RETRIES=0` for
the same purpose. Its negative selector contract explicitly requests one retry;
inheriting a zero-retry campaign environment legitimately satisfies the gate.
Keep Flutter 3.47.2's default DDS enabled for the Android Wi-Fi fallback runner.
With `--no-dds`, all four device scenarios and four host assertions passed, but
test loading failed with `streamListen: invalid 'streamId'` for the integration
golden comparator. Removing that option produced a complete device/host PASS
in `reliability-held-route-probes-023/logs/001.log`; the first failed result is
preserved in attempt 021. The standalone Dart VM did not reproduce this Flutter
engine failure, so its host probe is not evidence of mobile compatibility.
The full legacy Wi-Fi entry must also use this CLI runner: all four device
scenarios require its peer fixture. The former standalone route could execute
zero scenarios and accept an empty failure list. Both device and host summaries
now require exactly S1 through S4. The corrected full entry passed all four
device and four host results in `wifi-full-owner-native-002/`; wrapper contracts
passed 233 cases with zero skips in `notification-wifi-completeness-change-001/`.

The iOS tap runner requires the actual emitted readiness line, including mode
and title-configuration fields. A log-stream predicate, Xcode environment
export, empty ready file, or incomplete marker is not readiness. Four causal
counterexamples failed before repair; seven flow/readiness contracts passed
afterward in `ios-readiness-repair-001/`. Initial XCTest compilation runs during
setup, before the unchanged 120-second readiness handshake. Each scenario still
refreshes its bundled tap configuration and retains native routing assertions.
The compilation allowance must be explicit at the three callers that launch
XCTest. Applying it to ordinary readiness calls delays even a one-second probe
until the 1,800-second case-start budget expires. The approved readiness fix
preserves that build allowance at campaign callers and the supplied deadline
elsewhere. The unchanged emitted-event contract passes, as do seven isolated
probes including delayed build readiness; evidence is in
`.codex-test-logs/production-bootstrap-migration-20260927/approved-readiness-original-test-001.log`
and `proposed-notification-readiness-probe-001.log`. Preserve the initial five
timeout errors in `pilot-device-002/workflow-1.raw.log`. The protected legacy
registry must bind the approved harness bytes; its former digest correctly
blocked execution in `pilot-device-003/workflow-1.raw.log`.
The notification matrix's first attempt passed three warm cases, then failed
to locate the group-image body while Springboard logged XPC interruptions.
Later actual MCP inspection found the exact delivered card. Its focused native
rerun passed in `ios-group-image-single-probe-001/`; neither that later card nor
the rerun proves the original UI failure's cause or replaces the full matrix.

`ROUTING_PATHS` now requests CLI unregister at the actual R-Sim-3 boundary. A
fresh run secret authenticates a bounded loopback request carrying run, target,
stage and nonce. The host waits for the CLI's successful namespace acknowledgment;
the app validates and consumes the exact response before sending the stage's
message. The host also requires the matching app print receipt. Registration
is restored afterward. The existing R-Sim-7 offline/reconnect phases use the
same channel for acknowledged stop/restart and relay/circuit readiness.

The channel supports iOS simulators and macOS loopback, plus an explicitly
pinned Android `adb reverse tcp:0` mapping removed during cleanup. Physical iOS
has no supported stage transport and produces an aggregate failure, while
independent scenarios still run. Inline run-specific peer identity avoids an
unreadable host fixture path on Android. No ambient signal file is accepted.
The reader still requires all eight distinct stage completions and rejects
`[SKIP]`/`[BLOCKED]`, wrong names, missing/duplicate stage or consumption receipts.
A failed scenario cannot yield `FULL_BENCHMARK_COMPLETED` or stop an independent
peer scenario from being attempted.

The causal host contracts are runnable without a product/device campaign:

```bash
python3 -m unittest -v scripts/test/mknoon_full_legacy_binding_test.py
flutter test --no-pub test/tool/sims/legacy_target_contract_binding_test.dart \
  test/tool/sims/routing_stage_handshake_test.dart
```

These use real local subprocesses, synthetic inventory and fixture tool/peer
boundaries. They verify orchestration, leases and stage coordination; they do
not certify product measurements, physical-device behavior or a signed build.
The former blanket-block tests were replaced by protected positive execution
and invalid-command/binding refusal assertions; the privacy, native-pin,
filtered-selection and exact-child regressions remain required.

`results.json` joins obligations to original attempts, records scheduling wait and
execution durations, and retains allowlisted integer SIMS cache/build/profile
timings and typed schedule traces. Capability/profile IDs must come from the
selected source plan; nested verdict details, resource diagnostics and arbitrary
producer strings stay private. Separate install timing is null where a legacy
adapter does not expose it. Raw SIMS reports, adapter fixture exceptions and `*.raw.log` files are private
and excluded from the CI artifact allowlist. The host regressions in
`scripts/test/mknoon_full_review_regression_test.py` cover these receipt, binding
and argv-scope boundaries using synthetic evidence and production binding code.
`scripts/test/mknoon_full_composition_test.py` exercises the combined adapters,
exact mappings, per-step privacy, pinned native selectors and unknown-command
refusal. The legacy binding suite exercises all 147 selected route launches,
receipt corruption controls and the benchmark stage channel.
Timeouts/cancellation kill owned process groups, retain partial results and leave
unstarted work unrun. Failed first attempts remain failures after diagnostic
reruns. Never merge green partitions from different candidates; source or
configuration drift invalidates the invocation.

Verification uses temporary Git repositories and real fixture subprocesses for
serial/parallel equivalence, exact argv/configuration, prerequisite blocking,
scenario completeness, native completion readers, resource exclusion, dependency
failure, cancellation and raw-evidence retention. Group full mode, benchmark
failure propagation and the declared iOS companion artifact handoff have causal
RED/GREEN receipts. Native manifest contracts require both the original host CPU
resource and the shared native build lock. SDK-dependent verification uses the
real pinned Flutter 3.47.2 SDK. The existing Python timeout test still requires
`ps`, which this worker sandbox denies; its assertion remains intact. The legacy
simultaneous shell contract still depends on the absent
`.claude/skills/sims/scripts/run_with_devices.sh`. The standalone iOS bootstrap
contract checks the current group request v2/result v3/host receipt v3 schemas;
projection fixtures include `authorizedTransportPeerIds`, including its empty
list value, in exact projection comparisons. Support/manual source exceptions
are hash-bound so adding assertions to those files requires ownership review.
Full product/physical-device and signed-candidate execution: **NOT RUN**.
No speedup or release acceptance is inferred from fixture timing. Full regression
is not the default per-plan gate; follow the wave/release cadence in `AGENTS.md`.

`.github/workflows/mknoon-checks.yml` uses the same wrapper and selection manifest
for three distinct acceptance modes. Its final hosted job always runs after
metadata and selected execution; only a PR emits **`Mknoon regression checks`**,
the exact status context to require on `main`. A manual change diagnostic emits
`Mknoon change diagnostics`; release dispatch emits `Mknoon signed-release
acceptance`; scheduled/manual full execution emits `Mknoon full regression`.
These other contexts cannot substitute for a PR's selection or certify a
different candidate. PR activity includes base-branch edits, and there are no
path filters or privileged `pull_request_target` jobs. No push-to-main job is
needed for enforcement when the pending ruleset requires PR integration.

`ci-plan` resolves the merge base of the event's **PR head and target SHAs**,
checks both parents of GitHub's synthetic merge candidate, and records all
three identities. The selected checks execute that merge candidate. Comparing
from the true common ancestor can conservatively include target-branch changes
present in the candidate. Computing `merge-base HEAD PR_BASE` after checking out
the synthetic merge incorrectly returns the target tip instead. A dispatch
requires an explicit full baseline SHA; a release SHA remains an operator
attestation of the actual distribution record. A schedule uses its candidate
SHA and runs the existing full command list.

Metadata publishes an independent `plan.json` and a portable `plan_sha256` job
output. `ci-run` reconstructs selection on the execution host before calling the
existing runner. `ci-verify` reconstructs it again on a hosted runner and checks
the execution plan/results against that output, the candidate source/rules,
baseline, event, repository, workflow, run ID and attempt. Per-host Python paths
and prerequisite discovery are excluded from the portable fingerprint;
execution toolchain facts remain bound between the execution plan and report.
Every selected ID must appear exactly once with matching commands/paths and
complete original attempts. Missing results, skips, cancellation, incomplete
counts, stale evidence, unresolved impact and a metadata-only success all fail
the final check. A queued job without a runner leaves acceptance pending; it
never establishes PASS. Source-build tests cannot certify a signed artifact.

Test execution remains opt-in through `MKNOON_TEST_RUNNER_ENABLED == 'true'` and
requires an isolated disposable self-hosted runner labeled `mknoon-test`.
Both the workflow gate and `ci-run` refuse fork execution on that host. GitHub
contributor approval permits the hosted metadata workflow; it does not override
that restriction. After reviewing the exact fork revision, a maintainer can
bring the reviewed contribution into an origin branch and open a corresponding
PR subject to the same gate. The original fork PR remains blocked; do not post
a substitute success or use a privileged workflow to execute its code.

All selected jobs, including release/full jobs, share
`mknoon-shared-test-devices`, retain `cancel-in-progress: false` and `queue: max`,
and the wrapper retains its checkout resource lock. A single dedicated device
pool must not be shared with unmanaged local campaigns or another repository's
jobs; GitHub concurrency groups do not serialize other repositories. Ordinary
change/release jobs have a six-hour ceiling; full jobs retain 4,320 minutes
(three days). These are limits, not measured completion promises. Timeout or an
unfinished campaign remains incomplete. If full measurement exceeds its bound,
partition existing routes at one revision before claiming the cadence completes.

Artifacts use run-ID/attempt names and never overwrite prior attempts. Only the
allowlisted wrapper plan/result/partial/error/summary files are uploaded, with
hidden-file inclusion enabled for their ignored `.codex-test-logs` parent.
Nested device logs, signing material and raw receipts are not uploaded. A
diagnostic rerun within a report preserves its failed first attempt. Re-running
only failed GitHub jobs cannot borrow a successful metadata plan from an older
attempt: use a fresh complete workflow attempt and retain the earlier artifacts
and conclusions in the review. A later run does not erase a previous failure.

The CI unit files `mknoon_checks_test.py`, `mknoon_ci_checks_test.py` and
`testing_inventory_test.py` execute isolated Python/Git/parser fixtures. Their
exact paths are excluded only from the broad infrastructure area and still map
to `workflow` in `selection.json`; unknown infrastructure retains broad coverage.
The manifest also retains shared bridge/storage/lifecycle/native/build consumers
and adds the direct/group projection suites to notification changes: current
listeners, retry owners and reconciliation import these shared notification
contracts. Executable selectors remain solely in the manifest.

Local validation of this CI boundary passed 57 selector/CI tests and five
inventory tests, including real temporary Git histories and isolated failing
test subprocesses. After repairing the clean-checkout portability defect above,
the publishing candidate passed all five selected groups (workflow, bootstrap,
contacts, provider schema and Codex tooling): **323 tests, zero failed/skipped,
98.637 seconds**, with no diagnostic subset. Candidate/plan and observed counts
are in the evidence root below under
`publish-worktree/.codex-test-logs/publish-fixed-run/`. The earlier two failed
integration tests and diagnostic rerun remain preserved separately; the initial
development-tree 321-test pass is under `change-run/`. These results validate
this tooling change, not the separate unpublished application commit. Rule
validation, Python compilation and whitespace checks passed. Actionlint 1.7.12 initially reported the existing
custom runner label and its unsupported `queue` schema field. With that label
declared in an ignored local config, only `queue: max` remains unsupported;
all other lint checks pass when that exact diagnostic is excluded. The retained
queue behavior is covered by [GitHub's current workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency)
and the existing remote run. This is an explicit linter limitation, not an
unqualified lint pass or a newly executed CI campaign. Both diagnostics remain
in the ignored evidence root.

### Remote observation and pending activation

Read-only revalidation on **2026-09-13** resolved origin `main` to
`ad3529a041528c07dd6714a98c0f70fefeb2366b`; the clean starting local HEAD was
`1df147ccfc7ded0336ea28ed9f4b2d0039a48b81`, one preserved unpublished commit
ahead. Initial validation compared local changes against that starting HEAD;
the publishing candidate and its latest validation use origin main directly,
excluding the unrelated application commit. Source and remote receipts are
retained in ignored `.codex-test-logs/ci-enforcement-20260913-15_yatv1/`.

The authenticated API returned Actions enabled, this workflow active, **zero
repository runners, variables and secrets**, `main.protected=false`, empty
repository/branch rules, and `Branch not protected` from the protection endpoint.
The token reports administrative capability; no administrative action was
authorized or taken. The existing fork approval setting is
`first_time_contributors`, with read-only workflow token defaults and PR-review
approval disabled. Administrative endpoints that are inaccessible in future
audits must be reported as **unknown**, never inferred disabled from a 403/404
alone. Here the successful branch/rules queries corroborate the protection 404.

The actual [scheduled run 34745389097](https://github.com/salehelsayed/flutter_app/actions/runs/34745389097)
at `5a9bb5c94503d3e48dca734f4d2b2cb06fe8141a` was marked success, but its jobs
showed `metadata=success` and `selected=skipped`. Its logs record 37 wrapper and
five inventory tests, with no selected application/full execution. This refutes
the earlier statement that no remote run/schedule had been observed; it does
not validate this local implementation or a full campaign. Current origin main
had no check runs. **Activation remains BLOCKED; remote enforcement is not
verified.** The user subsequently authorized publishing this CI change, then
deferred runner setup because no dedicated test machine is available. The
publishing branch is based directly on origin `main`, preserving the separate
unpublished application commit locally. Runner activation and the required
main-branch rule are deferred together; enabling the rule without a runner
would block every merge.

[Draft PR #2](https://github.com/salehelsayed/flutter_app/pull/2) exercised this
boundary in [run 34773008050](https://github.com/salehelsayed/flutter_app/actions/runs/34773008050)
at PR head `bc7f331d87d67492ada4d3b716edd875db247ad1`. Hosted metadata passed
57 selector/CI and five inventory tests, and uploaded the expected five-check
plan for synthetic merge `800d274a340a575a2aa33bbd057a07a27df9b391` against the
verified main baseline above. `selected=skipped`; the final **Mknoon regression
checks** job failed with exit 2 and `CI selected job disabled, skipped,
cancelled, failed or not completed`. The downloaded plan's source hash matches
the locally tested publishing candidate. This verifies refusal of skipped
execution, not successful remote regression execution or main enforcement.
The metadata log and downloaded plan remain in the evidence root as
`remote-pr-metadata.log` and `remote-pr-expected-1/plan.json`.

The minimal pending activation actions, requiring explicit authorization, are:

1. Review this CI change through its pull request and complete the selected
   checks before integration. Do not register a required context as satisfied
   by the historical metadata-only run.
2. Register one dedicated disposable/ephemeral runner with labels
   `[self-hosted, mknoon-test]`. Its clean image needs Python 3.11+ (`tomllib`), Flutter
   **3.47.2** (the current pubspec floor) with matching Dart/resolved packages,
   Go **1.25.0**, Node, and the native toolchains required by selected checks.
   A macOS image with Xcode/CocoaPods plus Android SDK/JDK/adb supports the current
   cross-platform selection. Use a dedicated USB Android phone plus an available
   emulator for ordinary two-peer proof; add live iOS targets for applicable iOS
   boundaries. Prepare isolated fixture services using existing SIMS contracts.
   The runner must contain no developer credentials, signing keys, production
   service credentials or production app data. Do not attach the credentialed
   development host merely by adding a label. No paid capacity is provisioned
   by this change.
3. Place the live, isolated device-config JSON described above at
   `/opt/mknoon-ci/device-config.json` on that runner. Set the existing variables:

   ```bash
   gh variable set MKNOON_TEST_DEVICE_CONFIG --repo salehelsayed/flutter_app --body /opt/mknoon-ci/device-config.json
   gh variable set MKNOON_TEST_RUNNER_ENABLED --repo salehelsayed/flutter_app --body true
   ```

   Enabling this gate also enables the existing weekly full schedule. The PR
   path needs no signed-artifact/evidence variables. Mount those reviewed input
   files only for release dispatch and then set `MKNOON_CANDIDATE_ARTIFACT` and
   `MKNOON_MANUAL_EVIDENCE` to their runner-local paths. Signing happens through
   the existing release process, not this CI workflow. For multiple platform
   artifacts use the local wrapper's repeatable `--candidate-artifact` option;
   the CI variable currently supplies one artifact per release dispatch.
4. Inspect a fresh permitted PR run through metadata, selected execution,
   uploaded plan/results, and the final verdict at the current merge SHA. If a
   runner is queued/offline, report pending/BLOCKED. Then create the following
   minimal main ruleset, with **no bypass actors**. GitHub Actions app ID 15368
   was verified from the actual run's check records. Save the exact JSON to a
   reviewed local file and, only after approval, submit it with
   `gh api --method POST repos/salehelsayed/flutter_app/rulesets --input <file>`:

   ```json
   {
     "name": "Mknoon main regression checks",
     "target": "branch",
     "enforcement": "active",
     "bypass_actors": [],
     "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
     "rules": [
       {
         "type": "pull_request",
         "parameters": {
           "required_approving_review_count": 0,
           "dismiss_stale_reviews_on_push": false,
           "require_code_owner_review": false,
           "require_last_push_approval": false,
           "required_review_thread_resolution": false
         }
       },
       {
         "type": "required_status_checks",
         "parameters": {
           "strict_required_status_checks_policy": true,
           "do_not_enforce_on_create": false,
           "required_status_checks": [
             {"context": "Mknoon regression checks", "integration_id": 15368}
           ]
         }
       }
     ]
   }
   ```

5. Read back `/rulesets`, the created ruleset, `/rules/branches/main`, and the
   PR's required check/merge state. Confirm a failing or incomplete selected
   result blocks integration and a complete candidate-bound result satisfies
   the required context with strict branch freshness. Do not infer enforcement
   from workflow YAML, administrative capability, or a green summary alone.

Ruleset fields follow the [GitHub rules API](https://docs.github.com/en/rest/repos/rules#create-a-repository-ruleset).
The pending rule requires ordinary PR regression only. Signed release approval
still requires the actual previous published baseline, mandatory-plus-affected
automated checks, available-device journeys, exact signed artifact/configuration
hashes, all required manual receipts and review of outstanding full failures.
Historical runs and host-source passes cannot fill missing signed evidence.

## What the inspected checks establish

The manifest labels inspected checks separately from discovered directory
selections and records limitations alongside every proposed release check.
Representative assertions were inspected; the entire inventory was not audited.

| Boundary | Verified assertion scope | Remaining device/artifact proof |
| --- | --- | --- |
| Bootstrap/returning identity | Phase order, error propagation, identity routing and awaited direct/group recovery | Actual launch, secure storage, preserved contacts/groups/history |
| Contact and direct chat | Mutual contact rows without reciprocal loop; received content, status, order, duplicate counts in both directions | Real QR/camera, real crypto/transport path, disk persistence after restart |
| Offline/group | Fake inbox drain/deduplication; selected three-member fanout, truthful sent state, route-away persistence and fallback recovery | Physical disconnection, live group offline catch-up and path evidence |
| Media | Transformed ciphertext differs; receiver file bytes equal original; separate widget test opens typed received-media viewer | Received transfer and native decode/open in the same real peer journey |
| Notifications | Foreground/background policy and warm/cold payload route callbacks | OS tray/effect, muted conversation, real tap navigation and platform background limits |
| Migration | Real host SQLite FFI schema/data preservation and post-migration writes | Actual previous-published signed build upgraded in place with native secure storage |
| Bridge/call | Dart method/event channel contracts and signaling/mailbox convergence | Native binding, actual bidirectional audible audio and end-call cleanup |

Exact selectors and paths are in the manifest. Useful assertion anchors include
`two_user_message_exchange_test.dart` (bidirectional exchange),
`one_to_one_media_encryption_round_trip_test.dart` (receiver byte equality),
`conversation_received_media_actions_test.dart` (typed viewer opening), and
`full_migration_chain_test.dart` (seeded data preservation). The legacy media
envelope fixture proves a format fixture, not communication with an old binary.

Initial static discovery found 1,959 candidate test files across Flutter
host/device, Go modules, Python unittest, shell contracts, Node JavaScript, JVM
JUnit, Android instrumentation, XCTest and XCTest UI. A further 343 files were
classified as helpers/fixtures/generated support rather than test files. These
are a dated discovery snapshot; use the generated inventory for current counts.
The existing host runner listed 1,496 planned items, SIMS listed 32 capabilities,
and its contracts runner listed 54 command groups. The completeness gate
classified 1,583/1,583 Dart test files. None is an actual test-case count.
The legacy full script's “95-case” label refers to runner items, some containing
whole suites. Generated/parameterized counts must come from runner output;
do not count `test(...)` strings as executions. Runner listings took about
1.55s, 0.51s and 0.02s respectively and executed no assertions.

## Shared dependency lessons

- Video preparation has a native `video_compress` call and a composer lifecycle.
  A Dart deadline must request native cancellation, stop its progress listener,
  release the composer, and keep completed siblings. The direct and group wired
  tests cover recovery and retry; `image_processor_test.dart` covers idle and
  overall deadlines, cancellation, and late results. The share-batch test
  preserves the metadata-stripping boundary: a timed-out transcode must not
  substitute the raw source. These host fakes do not establish that a device's
  native codec obeys cancellation; repeat the 7 s R2-4 attachment on an
  available Android target for that proof.
  R2-4's 2026-09-28 Pixel emulator probe found Transcoder 0.10.5 blocked in
  `eglSwapBuffers` with its software encoder output unconsumed (details and
  first-attempt evidence in `artifacts/beta-20260927/BETA_REPORT_R2.md`). A
  Dart timeout clears the composer but cannot free that native job; the plugin
  rejects every later video in the same process. The local `video_compress`
  fork now compiles against Transcoder 0.11.2. That version initially rejected
  the R2-4 clip's out-of-order decoded timestamps; a tested monotonic timestamp
  adapter lets it complete. On the available Android emulator, five consecutive
  picks in one app process produced five processed MP4s, and `ffmpeg` decoded
  the first output (5.88 s, 176 frames). Host tests prove that an unsettled
  timed-out job blocks later compression with a visible error, the direct/group
  notice expires above the composer, and external share skips unsanitized
  videos after timeout or native failure. The later R2-5 beta on the same
  emulator found that 0.11.2 still stalled on four of four 30 fps synthetic
  videos at `eglSwapBuffers`; each left an unfinished MP4. The local fork now
  caps Android transcodes at 15 fps and unlinks the current output on cancel,
  failure, or abandoned late completion. Three consecutive picks of the
  30 fps `r25_motion.mp4` fixture in one emulator process produced complete
  90-frame, approximately six-second MP4s; `ffmpeg` decoded the first with no
  errors. The final debug APK (SHA-256
  `1986711011a978d53085690bec19ab75b00654688c109c76824e61cacc1568e9`)
  repeated that result on `emulator-5556`; its decoded output and `ffprobe`
  summary are retained in ignored `.codex-test-logs/r2-5-final-emulator-output.*`.
  The 4:4:4 fixture also produced a complete MP4, but exposed a
  thumbnail extraction null-frame error, now handled by a fallback lookup and
  one typed native error. A real Android handset, prolonged-stall cleanup on
  the revised build, and receiver-side delivery remain untested; host tests
  cannot prove hardware codec behavior. The `TranscodeOutputGuard` JVM tests
  cover partial-file unlink and successful-file retention; the selected
  affected-media host lane passed 637 tests. The change wrapper selected the
  lane but did not launch it because another campaign owned the shared
  native-build lease; the direct host result is retained in ignored
  `.codex-test-logs/r2-5-affected-media.log`.
- Bridge/event and transport/lifecycle changes affect direct messages, groups,
  media, notification consumers, and calls. A bridge-only unit test cannot
  establish that these consumers still behave correctly.
- Identity/contact/key authority and storage/migration state feed all peer
  communication and restart recovery. Select dependent feature checks as well
  as the changed subsystem's tests.
- Notification visibility, mute, canonical read state and tap routing cross
  conversation/group boundaries. Foreground fake-policy tests and native final
  effect tests establish different facts and must not be substituted for each
  other.
- A media delivery receipt does not prove receiver bytes can be opened. Preserve
  both receiver-byte and viewer tests and require their real-device conjunction
  for a signed release.
- Test helpers, runner configuration, dependencies, native permissions/build
  configuration, bundled assets and selector changes can affect consumers far
  beyond nearby tests. Keep conservative mappings until evidence supports
  narrower impact.

- Tap gestures can retain a recognizer while an index-based slot changes entity.
  UI-25 widget regressions reproduced wrong-peer activation in Orbit and wrong
  contact selection in the invite, create-group and introduction picker factories.
  Keying the gesture owner by entity cancels the old press; Orbit retains its
  separate seat/entrance state. Tests release the old press after replacement,
  then verify a fresh tap activates the visible entity exactly once.
- The shared recording button retains immediate provisional start, but stop/send
  must use the winning tap recognizer and one primary pointer. Raw pointer-up
  previously sent after dragging off and a second pointer produced duplicate
  stops. `voice_record_button_test.dart` covers those causal failures, quick
  start cancellation, removal, target edges and semantic activation. Direct and
  group conversation consumers remain separate preservation obligations.
  A stationary start must survive the Tooltip long-press deadline; touch
  tooltips cannot compete with the recording tap recognizer. Removing an idle
  mic after the tap-down deadline rejects that recognizer during descendant
  teardown, while the owning element is inactive. Cancellation must still abort
  the provisional start once, without `Feedback.forTap`'s render-object lookup.
  The pending-idle-start teardown test reproduced the inactive-element exception
  before removing that feedback call and passed afterward; receipts are
  `.codex-test-logs/ui25-taps-high/correction/l2-{red,green}.jsonl`.
- Recording action names follow the existing composer phase: arming cancels
  startup, an active stop also sends, stopping exposes no activation, and
  auto-stop review has separate send/discard actions. The localized action
  [tests](../../test/features/conversation/presentation/widgets/action_discoverability_test.dart)
  traverse the active semantics tree and assert single callbacks and
  disabled states in English, German and Arabic. Standard `IconButton` names
  are exposed through the SDK's tooltip semantic field; custom gesture controls
  use one named button node without a second activation handler.
  Orbit's create action uses `Semantics.identifier` separately from its spoken
  open/closed label. Stable keys preserve its semantic node across scrim and
  menu insertion; both FAB anchors retain identity after selection/dismissal.
- **Call Answer during voice capture (R2-3):** the beta T28 Android callee
  accepted the call while a voice note still held the shared microphone lease;
  call audio returned `mediaConflict` and the call ended `mediaFailed`. The
  capture owner now finishes before in-app native Answer, and call audio repeats
  the handoff for notification answers. Direct and ordinary group composers
  hold completed audio for review without sending it. Focused host tests cover
  a pending permission/start, delayed stop, stop error, Answer ordering, and
  both review surfaces. The first affected-suite run exposed three expected
  source-shape fingerprint/signature assertions; retaining `_onRecordStop()`
  and repinning the reviewed group handoff made the exact tests and the full
  affected conversation/group host suites pass. First failures are under
  `.codex-test-logs/r2-3-affected-screens/`, final passing suites under
  `.codex-test-logs/r2-3-affected-screens-final/`. These source tests do not
  establish a connected call on installed devices; repeat T28 with a current
  two-peer Android build.
  The [fixture contract](../../test/integration/group_reaction_notification_device_criteria_test.dart)
  now matches Android `resource-id`, as documented by the
  installed SDK. These host assertions do not establish native identifier
  exposure, actual screen-reader focus, or user comprehension.
- The horizontal reply recognizer already arbitrates against vertical scrolling;
  a second threshold applied to each delta discarded slow right swipes. The
  waveform's provisional tap-down likewise sought even when a later scroll or
  pointer cancel rejected the tap. `swipe_to_quote_bubble_test.dart` and
  `waveform_seek_bar_test.dart` preserve slow-input accumulation and seek-on-tap
  completion. The navigation badge is decorative and must not intercept its
  underlying button. These UI-25 results are host widget evidence, with raw
  first failures and corrections under `.codex-test-logs/ui25-taps-high/`;
  native input, screen readers and installed-build proof remain separate.

- Notification setup Retry must retain the actual coordinator future at the
  app-shell owner. A `VoidCallback` that discards that future cannot by itself
  establish pending state or prevent a second permission-refresh request.
  `push_registration_health_surface_test.dart` exercises the real coordinator
  with deferred registration, failure/recovery, rapid activation, and notifier
  clear/disposal fencing. Permission denial retains its settings action.
- The approved UI-25 loading label fits Orbit's existing top-strip reservation;
  skeleton geometry and settled list position are unchanged. Geometry checks
  must advance the existing zero-delay, 400 ms row entrance before comparing
  settled coordinates. Settings network choices wrap without a scale-down box
  at 320 logical pixels and 2x text in English, German and Arabic, but the first
  no-overflow host assertions did not detect glyphs clipped by the outer stadium.
  The row and settings readability tests now load the pinned SDK's Roboto and Noto Naskh Arabic fonts:
  each of four name-prefix characters must have a complete visible renderer box,
  and every network-label character must lie inside the segmented renderer's
  actual resolved inner clipping path (including its vertical target inset).
  The separate shape-only differential deliberately omits target-size gates so
  the originals' FittedBox/small targets cannot mask clipping attribution; its
  selected-label-only variant also prevents another label from masking the
  selected choice. Row
  stress includes both badges/counts and the formatter's English `Active now`
  in all locales; that formatter is not localized. The host font environment
  still differs from the native device, which remains a separate proof boundary.
  Raw REDs, exact source restoration hashes and normal/stress host renders are
  under the additive `approved-050608/native-layout-correction/` evidence root.
  The existing media preference failure key is consumed only in the catch branch that
  restores the prior matrix; a deferred-write test confirms no restoration
  message during pending work and successful retry clears the error.
  These are host widget/persistence boundaries, not native rendering or
  screen-reader proof. The `ui-approved-recovery-readability` check owns the
  executable selection. MediaGrid's composition tests must mount the production
  localization delegates now that even its loading leaf contains localized
  text; missing delegates caused three wrapper failures without changing the
  existing aspect-ratio and thumbnail assertions. First failures and focused receipts are under
  `/Users/I560101/.hermes/profiles/se/artifacts/mknoon-ui-ux/approved-050608/implementation-logs/`.

## Signed-candidate checklist

Use isolated accounts and disposable fixture data on discovered targets. Run
`flutter devices --machine`, `adb devices`, and, when relevant,
`xcrun simctl list devices available`; pin every command to the returned IDs.
The default non-iOS-specific two-peer topology is a USB Android phone plus an
available Android emulator. Use available iOS targets for iOS boundaries or an
explicit Android/iOS parity claim. An unavailable OS/model-specific optional
leg is `N/A (target unavailable by project policy)`; do not invent a required
hardware matrix. Essential journey evidence still needs an available topology.

Record signed artifact hash/build number, source/configuration and bundled
JavaScript identities, distribution-record baseline, target IDs/OS versions,
isolated service configuration, observed results and redacted evidence paths.
Use the manifest's required evidence IDs when recording the following journeys:

1. Launch with existing identity; verify contacts, groups, and history. Add a
   contact through the supported QR flow and start a conversation.
2. Exchange distinct synthetic content in both directions; verify received
   content, truthful state, no duplicates, then reopen and verify persistence.
   Exercise representative direct and relay/inbox paths and record the actual
   observed path; fallback cannot prove the requested path.
3. Send to a small group; disconnect one member and verify that member catches
   up without missing/duplicate content after reconnecting.
4. Transfer representative media and have the recipient open/play the received
   file. Record the content identity/open outcome, not only a delivery badge.
5. Verify background notification, tap to the intended conversation, foreground
   behavior, and a muted conversation on applicable candidate platforms.
   On iOS, correlate notification lock ownership with background/suspension
   and resume, and preserve the existing-installation notification ledger.
   An unidentified suspension lock remains an open release investigation.
6. Interrupt connectivity during a pending send, reconnect, and verify recovery,
   final state, content and duplicate counts.
7. Install the actual previous published build with fixture data, upgrade in
   place to the signed candidate, and verify retained data. Separately exchange
   messages between old-build and new-build peers in both directions.
8. When audio calling is included, connect, verify audible audio in both
   directions, end the call, and verify both endpoints leave the call.
   Include a cold VoIP wake while capability is disabled and queued/coalesced
   pushes; verify each required CallKit report completes. A retained PushKit
   receiver and fake provider tests do not alone certify the OS boundary.
   Also place a background incoming call six minutes after the last successful
   VoIP push, confirming suspension before the invite. Correlate provider
   acceptance, device PushKit receipt, CallKit presentation, native/Dart adoption
   and media. Verify actual signed APNs environment/topic, cancellation/expiry
   and retired-predecessor successor-audio ownership independently. Preserve a
   missed first attempt; a successful immediate retry does not satisfy this leg.

Source/configuration/bundle/artifact changes invalidate prior candidate evidence.
Host-source tests never certify an untested signed artifact. Missing evidence is
incomplete; a failed first attempt followed by a passing diagnostic rerun remains
visible and cannot become an ordinary first-attempt PASS.

## Diagnostics and confirmed lessons

- **R2-7 short chat viewport:** the Pixel 7a landscape keyboard left about
  128 logical pixels for the direct chat, and the normal header plus composer
  overflowed (device screenshot in
  `artifacts/beta-20260927/run-20260927-205235/maestro/t34_landscape_android/`).
  `conversation_screen_test.dart` reproduces a RenderFlex overflow with the
  captured physical size and IME inset before the compact layout, then checks
  that direct history retains visible height, the header returns when the
  keyboard closes, and an unsent draft survives the height transition.
  `group_conversation_screen_test.dart` checks the same constraint and draft
  retention for a quoted group composer. The compact layout hides secondary
  banners and previews only while height is below 260 logical pixels; their
  state remains mounted in the owning screen and they return at normal height.
  `app_diagnostic_error_handlers_test.dart` checks the fixed, content-free
  debug log marker for future RenderFlex overflows. Host layout tests establish
  Flutter constraints, not a rebuilt Android device screenshot.

- **Legacy group dissolve/removal audit identity:** when a member has no device
  roster, `resolveGroupSenderDeviceBinding` returns no device binding, so its
  account-signed transition omits device/transport fields. Go publication fills
  both envelope fields with the account peer ID; legacy inbox delivery may
  expose only that transport alias. Comparing these aliases to absent audit
  fields reproduced R2-1's `device_mismatch` then `transport_mismatch` sequence
  from `artifacts/beta-20260927/BETA_REPORT_R2.md`. This is a legacy identity
  representation mismatch, not evidence that arbitrary relay identities may
  replace a signed transport. The receiver accepts omitted bindings only with
  an empty device roster and account-equivalent envelope identities; explicit
  signed bindings, rostered/revoked devices, admin authorization and signatures
  remain checked. A valid removal of the receiving member also ends its active
  membership despite divergent pre-state, while rejoin/freshness checks and the
  state-hash gate for removing other members remain intact. The focused
  `group_terminal_transition_binding_test.dart` exercises live listener delivery,
  inbox replay, one timeline/stream update, key cleanup, duplicate suppression
  and rejection controls. Causal red/green logs are retained under
  `.codex-test-logs/r2-group-transitions-{red,green}.log`; the existing `groups`
  mapping discovers this suite in `affected-groups`. The scoped wrapper report
  `.codex-test-logs/r2-group-transitions-checks/results.json` records 3,229 group,
  88 notification and four small-group smoke tests passing with no skips,
  including all 24 focused R2 cases. Its whole-worktree status remains incomplete
  because unrelated selected checks were not run. These are host tests with fake
  bridge crypto/storage, not a rebuilt two-device production-relay proof.

- **Wake command staging:** stop and await the old Android command poller before
  deleting its prior result and publishing the next one-use command. Starting
  the prepared activity must not force-stop after publication. The native
  observer in `source046-wake-token-native/` recorded the presenter consuming
  its command and writing `running/p2p_ready` in PID 11903, followed by a harness
  restart to PID 12163 with no command remaining; the original three-minute
  wait then failed. Both generic contact and typed endpoint staging now use the
  same stop-before-publication boundary. Three behavioral regressions cover an
  active old poller, delayed shutdown and failed shutdown; all failed with the
  unsafe ordering and pass after repair. Evidence is in
  `.codex-test-logs/all-tests-y227gs8x/source047-wake-staging-repair/`.
  The complete native campaign remains required; deadlines and token assertions
  are unchanged.
- **iOS receiver bootstrap diagnostics:** a failed helper can emit a typed result
  while the payload driver reports only a generic missing-handoff failure.
  Retain an allowlisted failure code from exactly one matching result schema,
  status and privacy declaration. Unknown, duplicate, oversized, malformed or
  secret-bearing records yield only `unavailable`; helper timeout and missing
  output have separate fixed codes. Never persist arbitrary helper detail or
  APNs handoff material in the causal diagnostic. Parsing/privacy regressions
  are in `source047-focused-green.log` under the same ignored run root. This
  repairs lost diagnostic information; it does not establish the original
  physical iOS handoff failure's cause or prove native delivery.

- **Strict group wake accounting:** durable Android rich admission, its capacity
  fallback, and preselected iOS routes must preserve the strict group logical
  `attempted` counter. Count once when the inbox launches the logical wake;
  provider retries and duplicate custody must not count again, and ordinary
  group-topic/direct traffic must not increment this counter. The existing
  provider-outage recovery test reproduced actual provider attempts with a zero
  counter delta for both token-storage routes. The causal red and overlay green
  are in `.codex-test-logs/all-tests-y227gs8x/strict-group-metric-{red,green-002}.log`.
  This establishes an accounting regression, not live notification delivery.
  The applied change passed all 1,526 relay tests with no skips in
  `relay-metric-run-001/`. The Go 1.25.0 binary ending `aa913c3` was deployed to
  EC2; retained-message restart checks and all six dual-stack TCP/WSS/QUIC
  protocol probes passed in `relay-metric-deploy/`. A fresh strict-group device
  result remains required for the campaign's notification claims.
- **Android launch components:** successful provider and retry launches can name
  the same activity as `com.mknoon.app/.MainActivity` or
  `com.mknoon.app/com.mknoon.app.MainActivity`. The group command-journal
  validator uses one exact-component set for provider preparation and both
  central-prebuilt and rebuilt exact-ADD retry paths. Existing stage, exit,
  device-binding and probe-order checks remain in place; a different activity
  is rejected. Captured full-name commands reproduced stale shorthand-only
  rejection in the provider and both retry branches. The unchanged artifacts
  pass diagnostic validation after repair; all 135 validator tests pass.
  Evidence is in `source045-group-component-repair/` and
  `source046-group-retry-component-repair/` under
  `.codex-test-logs/all-tests-y227gs8x/`. These diagnostics do not replace a
  fresh complete native group campaign.
- **Real audio fixture preparation:** compiling/linking the Go relay and audio
  oracle inside the Dart scenario can consume its entire 30-second limit before
  audio executes. The opt-in real fixture test now compiles exact-candidate
  binaries during suite loading, then uses an exact-command shim preserving
  the original selectors, single execution and Go limits. The audio case keeps
  its original deadline and all bidirectional payload/route assertions. Unique
  prepared tools are removed in suite teardown; preparation is not a scenario
  pass. The repaired fixture completed with its Go process at 6.75 seconds in
  `source045-focused-green.log`; the two full focused files passed 137 cases.
- **Bounded journal publication:** `recordTerminal` may return after its 200 ms
  caller-impact budget while atomic persistence continues. Tests asserting the
  published JSON must observe the existing atomic-writer completion seam before
  reading disk; they must not extend the production deadline. The affected push
  suite passes 1,219 tests without skips in `emission-builds-change-001/` under
  `.codex-test-logs/all-tests-y227gs8x/`. The emission test registers the assertion
  for its compile-time configuration: ordinary builds stay default-on, while
  the manifest's separate explicit-rollback command runs the existing disabled
  assertion (one pass). Both configurations are full-suite obligations.
  The same boundary applies to a failed writer's temporary-file cleanup: the
  caller can return before the writer throws and its owned temporary is removed.
  The preservation test now holds the injected writer past the caller budget,
  releases its failure, and observes cleanup under the existing test timeout
  before asserting unchanged complete slots. The old immediate assertion was
  reproduced in `journal-late-cleanup-red-001.log`; all 11 journal tests pass in
  `journal-late-cleanup-green-001.log` under
  `.codex-test-logs/all-tests-y227gs8x/`. Production timing is unchanged.
  Concurrent slot tests have the same boundary: a fixed clock and nonce do
  not make the bounded caller a disk-write join. The controlled probe holds
  all 12 atomic writers beyond the unchanged caller budget, reproducing the
  old zero-record read; it then releases them and observes all publications
  before asserting 12 distinct slot files. All 11 journal tests pass in
  `source044-journal-concurrent-repair/green.log` under the same run directory.

- **Background reconnect smoke observes transitions:** the real-device test's
  plain `Online` state can exist entirely between its 500 ms polling ticks.
  In `sims-legacy-continued-001/full-sims-0-routes/logs/006.log` under
  `.codex-test-logs/all-tests-y227gs8x/`, the state stream recorded truthful
  send/inbox readiness without relay readiness at +2,104 ms, followed by dotted
  `Online.` at +2,434 ms; polling nevertheless timed out. Subscribe after the
  fresh proof-window reset and retain the actual emitted snapshot, so startup
  observations cannot satisfy the resumed proof and automatic recovery cannot
  erase it. Keep the original 15-second observation deadline, both capability
  assertions, absent relay readiness, subsequent dotted-state assertion, and
  listener cleanup. The repaired original test passed on the physical Android
  against the deployed relay in `background-reconnect-device-probe-001/`.
  `background-reconnect-change-001/` passed 1,285 transport/lifecycle tests and
  196 runner contracts with no skips; the full reliability owner still needs
  its separate complete rerun. No production recovery timing changed.

- **iOS reconnect duration and suspended recovery:** correlate authenticated relay
  peers to consenting diagnostic owners before attributing endpoint reports.
  The September 16 incident peer matched iOS build `1.0.1+118`: one reconnect
  finished at 10:15:01 UTC with 862,179 ms reported by Flutter and 136,659 ms
  by the native bridge; the next finished at 10:20:03 in 960/959 ms. The same
  endpoint reported a failed reconnect on September 15. Flutter stopwatch and
  native uptime durations do not prove continuous foreground waiting. Native
  `record()` timestamps events when its asynchronous queue processes them, not
  when the bridge method starts; two retained September 15 traces demonstrate
  materially delayed timestamps. Do not reconstruct exact invocation times or
  suspension duration from those native event pairs. The initial investigation
  found `performImmediateHealthCheck` joining an existing recovery future while
  `callP2PRelayReconnect` had no Dart watchdog. Those waits predated September
  diagnostics (February/March source history); they did not identify a newly
  introduced regression or the phone's exact native failure phase.
  Causal fault-injection tests subsequently reproduced both a missing reconnect
  reply and a missing status reply pinning every coalesced health check. The
  bridge now bounds reconnect at the native 30-second budget plus a 500 ms
  delivery margin, and status at five seconds. Late replies cannot mutate the
  completed caller, inbox draining resumes after reconnect timeout, and the next
  healthy poll succeeds. This is not a 30.5-second bound on the complete health
  check, which also polls status and performs readiness work.
  Go owners and joiners now share one original recovery deadline. Timeout keeps
  exclusive native mutation ownership until work returns; it must not start a
  competing host restart. Completion is promise-specific, and a panic in the
  owned goroutine publishes a failure and releases ownership. The initial node
  lock and an uninterruptible native Stop are not cancelled by these deadlines.
  Preserve that limitation rather than claiming an arbitrary native deadlock
  is repaired. Red/green ownership, panic, race and Dart receipts are under
  `artifacts/relay-startup-20260916/tdd-go/` and `tdd-dart/`.
  The controlled fault harness also passed with diagnostics off/on on Android
  API 35 (`emulator-5564`) and the available iOS 26.5 simulator. With 9,760
  retained diagnostic events in a >4 MiB archive, the missing reply completed
  through the watchdog after about 30.5 seconds, then a healthy reply completed
  in 19–20 ms. Native drain and relay responses were injected in this harness;
  this establishes Dart recovery isolation, not actual OS/native recovery or
  reproduction of the private phone's incident. Preserve the separate native
  lifecycle proof and its relay configuration. The first iOS attempt timed out
  during its build before tests ran; the successful retry is separately retained
  under `artifacts/relay-startup-20260916/tdd-device/`.
  Separate native trials passed four real OS pause/resume cycles on each target
  against the actual Go relay server running locally over TCP. Diagnostics-off
  and diagnostics-on order was rotated; every trial restored send and inbox
  readiness, and enabled trials did so before a held diagnostic upload was
  released. Each enabled trial drained 64 actual native bridge observations and
  observed the native reconnect event. These use a bounded native backlog and
  local upload callback, separately from the >4 MiB Dart fault harness. They do
  not prove WAN/QUIC behavior, physical deep suspension, cellular handover or
  signed-release behavior. Receipts are `tdd-device/android-native-os-local/`
  and `tdd-device/ios-native-os-local/`. The first Android native trial against
  production failed before backgrounding because the relay was unreachable;
  retain that failure separately from the passing local-relay trials.
  After the authorized EC2 reboot, four additional Android OS cycles passed
  against the public relay, restoring both readiness capabilities in 881–951 ms
  with diagnostics off/on and local diagnostic uploads held pending. This
  establishes public-relay recovery for those trials, not which transport won
  every dial or the cause of the earlier private-phone incident. Receipt:
  `tdd-device/android-native-os-public-after-reboot/summary.json`.
  Bounded, consenting
  event projections and the private-identity-free correlation receipt are in
  ignored `artifacts/relay-startup-20260916/`.

- **Relay process health does not establish connection readiness:** the September
  16 production investigation observed successful TCP connects followed by TLS
  and SSH-banner timeouts while `relay-server` remained active without restarting.
  The 1 GiB `t3.micro` had no swap; kernel memory PSI reached
  `full avg60=67.67`, and journald repeatedly reported memory-pressure cache
  flushing. EC2 reachability checks, CPU credits and attached-volume checks
  remained healthy. Collect host pressure alongside protocol probes; an active
  systemd service or passing EC2 checks cannot clear an app connectivity incident.
  The diagnostic projection reads retained records before applying its report
  window/limit, so a small output limit does not bound collection memory. A live
  projection was attempted before the severe measured stalls; its contribution
  is unresolved. Retained one-minute memory-stall rates stayed below 0.5% during
  the earlier 10:15:32–10:20:03 UTC relay connection gap, so the later stall
  cannot establish that gap's cause. Earlier Redis loopback timeouts predated
  the projection, but the unavailable private iPhone's original startup delay
  is not causally attributed to host pressure. The diagnostic reader was later
  absent and a fresh verified-TLS WebSocket upgrade completed in 398 ms.
  The scheduled diagnostic monitor also reads the entire retained corpus before
  filtering. Its deployed memory ceiling was 768 MiB on the 914 MiB guest;
  this is a configured ceiling, not measured consumption. Incident-window
  service receipts show successful scans every five minutes, taking roughly
  27 seconds and eight CPU-seconds each, including 10:19:07–10:19:34 UTC.
  Diagnostic uploads additionally scan the collector's full in-memory record
  map and synchronously persist each accepted event. These establish shared
  resource costs, not proof that a monitor scan caused a client reconnect gap.
  A later recurrence made EC2 instance reachability fail while system/EBS
  checks remained healthy. The authorized reboot restored SSH, WSS and native
  app readiness at the unchanged public IP. A subsequent monitor cycle consumed
  at least 213 MiB and left 35.8 MiB available, but did not reproduce the severe
  stall. The local Python reader repair now reduces old events to baseline
  signatures/counts and latest health while scanning; its causal test retained
  512 old event objects before repair and at most 24 afterward. Fifty focused
  tests and 600 independent differential cases preserve consent, baseline
  errors, stable snapshot ties, cross-run joins and monitor-counter ordering.
  Loss samples retain only the first 2,048 plus overflow evidence, and standalone
  reports skip unused monitor samples. Active-window rows and compact metadata
  still grow with their cardinality, and all record files are still scanned.
  The approved one-file reader deployment preserved the installed schema,
  monitor, wrappers and timer, with no service restart. The next scheduled
  cycle (12:48:45–12:49:08 UTC) succeeded: sampled monitor memory peaked at
  129.16 MiB versus 213.42 MiB before repair, and minimum available guest RAM
  was 102.75 MiB versus 35.81 MiB. Verified WSS upgrades passed before, during
  and after in 396/369/345 ms; no monitor or relay cgroup OOM events occurred.
  These are single-cycle observations with different timing and workloads;
  sampled peaks are lower bounds, not controlled maxima or proof against
  recurrence. Receipts, the protected-backup location and the first zero-write
  deployment preflight failure are in `tdd-monitor-memory/`.
  A September 17 recurrence confirmed that the reader repair did not remove
  the host capacity risk: the same 914 MiB guest still had no swap. Daily OS
  upgrades began at 06:02:46 UTC, memory-pressure flushing followed at 06:06,
  and DHCPv6 configuration timed out at 06:07. EC2 instance reachability failed
  from 06:41 while system/EBS checks and CPU credits remained healthy. The
  kernel recorded a global OOM kill of `relay-server` at 07:04:56 UTC, with
  roughly 281 MiB resident in the relay and concurrent upgrade/monitoring
  processes consuming the remaining budget. Historical Prometheus samples put
  available RAM at 81 MiB at 06:02:37 and 35 MiB at 06:03:22, before the next
  call-monitor run at 06:03:31 and app-monitor run at 06:04:36. The previous
  app scan had completed at 06:00:15. Relay RSS fell from 326 to about 311 MiB
  across that onset, within its 274–339 MiB overnight range; the upgrade service
  later reported a 144.3 MiB cgroup memory peak. This supports OS updates as the
  likely initiating extra load, not a sudden relay RSS surge. Diagnostics still
  overlapped the later collapse, and missing per-process historical peaks
  prevent sole-cause attribution or quantifying its contribution. Evidence:
  `memory-attribution-{discovery,history,onset}.json` in the same ignored run.
  The relay then
  repeatedly failed its required IPv6-listener check. An authorized EC2 reboot
  at 13:20:35 UTC restored SSH, IPv6 listeners and all cloud health checks at
  the unchanged public IP. Authenticated QUIC, WSS and TCP smoke checks plus
  a QUIC relay reservation passed; Redis-backed durable control-plane startup
  was observed. One initial IPv6 startup failure recovered automatically.
  Subsequent samples found about 133 MiB available between cycles and 59 MiB
  during the next scheduled diagnostic scan. That scan completed successfully
  without new OOM events or further relay restarts; five following verified WSS
  upgrades passed in 350–406 ms. This establishes recovery, not a capacity fix.
  No application deployment or host memory configuration was changed.
  Redacted receipts and the live-test command
  are in ignored `.codex-test-logs/relay-incident-20260917/`.
  The September 18 recurrence again exhausted the no-swap guest. The app scan
  finished at 02:53:20 UTC; `apt-daily` started at 02:54:14, and retained
  metrics fell to 31.25 MiB available at 02:54:37 before the next app scan.
  Network route configuration failed at 03:11, and the kernel killed the relay
  at 03:42:15 with 321.74 MiB resident; `apt-check` held 98.38 MiB in that OOM
  snapshot. The relay subsequently failed its IPv6 listener check repeatedly.
  This supports maintenance-triggered pressure on an already full host, with
  overlapping diagnostics; the OOM-triggering allocator is not itself proof
  of which workload caused the shortage.
  The authorized repair added `/swapfile.mknoon` (1 GiB, mode 0600) to
  `/etc/fstab`; the generated active swap unit and `swap.target` dependency
  verify persistence configuration without a second reboot. Persistent
  `90-mknoon-memory-guard.conf` service drop-ins set MemoryHigh/MemoryMax/
  MemorySwapMax to 128/256/256 MiB for the app monitor, 64/128/128 MiB for the
  call monitor, and 192/384/384 MiB for both APT daily services. Original fstab
  and operation receipts are under server-side
  `/var/backups/mknoon-memory-guard/20260918T083357Z/`.
  A scheduled app scan and a deliberate overlap of both diagnostics monitors
  with a read-only `apt-check` completed successfully. During the overlap,
  sampled available RAM stayed at or above 154.73 MiB; all ten verified WSS
  upgrades passed in 345–1,061 ms, with no new OOM or relay restart. The final
  host sample had 262 MiB available and 227 MiB swap used. Authenticated QUIC,
  WSS, TCP and relay-reservation checks passed, and all EC2 checks recovered.
  This verifies the observed overlap and deployed memory budgets; it does not
  replay package installation or prove all future workloads fit this host.
  At the user's subsequent explicit request, automatic APT maintenance was
  disabled persistently: both daily timers, both daily services and
  `unattended-upgrades.service` are masked and inactive. The override
  `/etc/apt/apt.conf.d/99zz-mknoon-disable-periodic` sets APT periodic enable,
  package-list updates, downloads, unattended upgrades and autoclean to zero.
  Automatic security updates are therefore disabled too; manual APT commands
  remain available. No installation was running when maintenance was stopped.
  Original settings and the change receipt are under server-side
  `/var/backups/mknoon-package-maintenance/20260918T084951Z/`.
  Verification found no scheduled APT timers or package processes, no new OOM,
  and the same running relay PID/restart count. Three verified WSS upgrades
  passed in 372–382 ms. Action and verification receipts are in the incident's
  ignored `stop-maintenance/` directory; its temporary /32 SSH rule was also
  removed and absence verified. The swap and diagnostic memory limits remain
  in place; the APT memory limits apply only if those services are re-enabled.
  The temporary current-client /32 SSH rule was removed and absence verified.
  No application code or binary was deployed. Selection metadata validation
  and the diagnostics Python subset passed; the broader pre-existing dirty
  application selection remains NOT RUN and its overall wrapper status is
  BLOCKED, not a full-check pass. Receipts, including the bounded historical
  metrics and exact changes, are in ignored
  `.codex-test-logs/relay-incident-20260918/`.
  Authenticated Identify also exposed a separate stale TCP advertisement:
  `/etc/mknoon/relay-server.env` explicitly retained `RELAY_SERVER_IP=13.60.15.36`
  after the instance address had changed to `13.60.250.19`. Correcting only that
  assignment and restarting the relay service changed the live address contract
  from failure to pass; direct TCP at port 4005 authenticated the expected peer.
  Validate peer-advertised addresses as well as DNS and TLS. This proves a
  configuration defect, not its contribution to the private phone's delay.
  The live TCP smoke fixture independently retained the same obsolete IP.
  Replacing only that fixture address with `/dns4/mknoun.xyz/tcp/4005` changed
  its timeout to a pass while preserving peer authentication and dial limits;
  all five live smoke tests and three transport comparisons passed.
  Redacted first failures, kernel/host observations and AWS metrics are retained
  in ignored `artifacts/relay-startup-20260916/`.

- **Old pending-send notification boundary:** delivered-history suppression
  does not establish an age policy for undelivered backlogs. A verified private
  iPhone incident on 2026-09-12 linked three 11:50:28 Berlin push receipts to
  message traces whose Android build 112 send attempts failed on September 9.
  The same authenticated sender started build 118 seconds before today's relay
  submissions; the receiver also ran build 118 and the September 10 relay fix
  was still active. Recovery then drained retained obligations without an
  authored-age cutoff, while quiet history repair required canonical delivered
  proof. The sender's final diagnostics explicitly record `failed/send_failed`;
  relay receipt timestamps place their upload seconds later on September 9.
  That proves a working diagnostic upload path then, not an uninterrupted
  internet outage until September 12. A failed send or missing acknowledgment
  does not identify the underlying connection failure. This supports startup
  recovery of old pending messages; it does not
  prove which retry branch ran, unchanged ciphertext, or that the recipient had
  never read the content. Preserve separate coverage for stale pending delivery
  and already-delivered replay. Propagated traces establish lineage; NSE handoff
  and `committed=true` do not prove OS display or first-ever insertion. Read-only
  evidence and attribution limits are in ignored
  `.codex-test-logs/old-push-20260912-0953UTC/report.md`.
  Automatic initial-direct-message recovery now carries separate `quietRecovery`
  intent after **more than 24 hours** from the original durable timestamp.
  Fresh sends, the exact 24-hour boundary and explicit manual retries keep
  normal policy. Recovery preserves ciphertext, custody/ACK and unread state;
  it does not claim delivery or seed delivered/visible notification admission.
  Receiver schema v119 retains the sidecar through staging and restart;
  canonical notification eligibility and history exclude quiet rows. Mixed
  inbox pages retain per-row policy. A delayed normal duplicate cannot clear
  durable quiet intent: duplicate/manual receipt and edits reuse the original
  display identity rather than granting a new alert. The `quiet-recovery` check
  preserves these controls. Android FCM native tests assert durable scheduling without a card;
  the existing NSE TC-373-06 gate includes quiet-row rejection with an alertable
  control. Relay quiet history survives ACK/restart and fences provider work
  that has not begun. Already-started provider requests cannot be recalled;
  a previously accepted visible iOS wake can still use its generic fallback
  when NSE retrieves only quiet rows. Newly generated quiet wakes are
  background-only;
  old Android routing-only jobs without ciphertext cannot reconstruct the exact
  suppression identity. Quiet iOS background wakes may defer canonical fetching
  until the next active runtime. These source/test results do not establish
  signed-device behavior or live APNs/FCM effects. Relay v1.10.7 was deployed
  on 2026-09-12 with the quiet policy and Redis claim repair; both phone apps
  still require an update for the complete cutoff. The matched executable,
  durable backend, restart stability and rollback receipt are recorded in
  ignored `.codex-test-logs/relay-deploy-20260912-_vw27ewh/`. Test evidence is
  under `.codex-test-logs/quiet-recovery-24h/` and the adjacent
  `quiet-recovery-sender-*` / `quiet-recovery-go-*` logs.
  Redis wake-claim WATCH retries must reset both the candidate claim and the
  claimed flag at every transaction attempt. Otherwise a losing worker can
  return an aborted claim after observing the winning worker, causing duplicate
  provider alerts. A deterministic conflict regression holds one worker after
  its snapshot, commits the competing claim, then verifies the loser returns
  no claim. Red/green evidence is retained in the adjacent
  `quiet-recovery-go-claim-conflict-*` logs.
  Mixed-version recovery additionally requires action-level relay admission:
  `store_quiet_v1` and `store_custody_quiet_v1` preserve the existing storage
  and custody owners, but an older relay rejects them before accepting a row
  whose unknown quiet sidecar it would discard. Ordinary/manual stores retain
  their existing actions. Updated retrieval requests declare `quietRecovery`;
  older receivers continue draining ordinary rows while quiet rows remain in
  custody for an upgraded runtime. Both pending and destructive legacy reads
  preserve those hidden rows, and pagination counts only eligible rows. Redis
  applies destructive selection inside the existing transaction. Existing
  sidecar-aware senders remain accepted by the updated relay. A sender/relay
  upgrade alone does not establish quiet display on an old recipient binary.
  Tagged Go compatibility fixtures cover rejection through store, retrieval and
  explicit ACK; production relay tests cover authenticated attribution, both
  backends and old/new reader pagination. SQLite reopen and Dart receive tests
  preserve original age/bytes/owner, the exact 24-hour boundary, unread state,
  mixed pages and durable quiet disposition after delayed normal duplicates.
  The exported mobile inbox JSON builders previously dropped the relay's
  quiet flag, including protected pending retrieval. The shared NSE response
  had the same omission. Five actual bridge roundtrips reproduced that loss;
  all four projections now retain the
  additive flag on quiet rows while preserving normal row shape, identity,
  encrypted bytes and protected custody authority. Node/NSE decoding and
  Dart-only quiet tests alone did not cover these projection boundaries. The
  memory-bounded iOS extension's fail-closed stub remains unchanged.
  Evidence is in `.codex-test-logs/dual-stack-recovery/`.
- **Integrated dual-stack evidence boundaries:** the production relay address
  plan retains IPv4, requires an explicit assigned public native IPv6 address,
  and refuses startup after an incomplete opted-in bind. DNS IPv6 advertisement
  remains an operator assertion about proxy/DNS readiness, not a live probe.
  The production-handler socket fixture in `dual_stack_application_test.go`
  exercises TCP, WS and QUIC across both same-family and both mixed-family
  pairings. It pins a single relay address per peer and verifies authentication,
  reservation, signed rendezvous record, Redis-backed quiet custody/retrieval/ACK
  and call-control bytes/sender attribution. A no-listener client cannot silently
  replace that requested relay family with another path. The fixture's initial
  request-only protobuf decoder, memory-only custody setup and empty-inbox status
  assumptions failed before correction; those setup failures remain retained.
  These are native host socket and production-handler checks, not phone UI,
  audible media, a native IPv6-only network or DNS64/NAT64.
  September 14 read-only public probes separately authenticated the expected
  relay on IPv4/IPv6 TCP 4005, WSS 4001 and QUIC 4002, acquired reservations and
  received their own empty inbox/call mailbox and credential responses. The
  initial relay executable was a separately hashed v1.10.7. A malformed admission
  probe (no recipient/payload and no stored row) confirmed that it rejected both
  new quiet actions as unknown; that failure remains recorded. The subsequently
  authorized relay deployment uses clean merge `74ecbafeec31cf92c5efd1137f9feac85b2a855b`
  and running binary SHA-256
  `7e8927194308e91f9bab78098cbe2ff9d7db1839341daa7ef02b9fc6c036aa2b`.
  Six public TCP/WSS/QUIC mixed-family cases passed signed rendezvous,
  reservations, ordinary and both quiet store actions, legacy-reader retention,
  sender/byte preservation, call-control exchange and ACK cleanup using fresh
  identities without push tokens. Ordinary and protected test rows survived the
  relay restart; Redis, identity/configuration and listeners were preserved.
  The first three-second readiness guard triggered a rollback before startup
  finished. The corrected guard checks the current PID's peer/backend summary
  within 60 seconds, then verifies public authenticated requests. A version label
  or successful relay-only activation remains insufficient for client behavior.
  Runtime owners are recorded in `Network-Arch/IPV6-Infra-Ops.md`; historical
  repair scripts are not canonical deployment inputs. Current DNS/listeners do not establish packet
  delivery, and public empty reads do not establish text/call success.
  The independent host TURN matrix uses fresh credentials validated by current
  native Go, socket binding to Wi-Fi, strict TLS hostname/certificate validation,
  authenticated response integrity, explicit permission/channel creation and
  Refresh(0) cleanup. Connection and requested allocation families vary
  independently. Both IPv4 UDP-control cases timed out on returned data after
  successful allocation/permission/channel binding; both IPv6 UDP-control cases
  and all eight TCP/TLS cases returned 100 exact bidirectional synthetic payloads
  each. All 24 allocations were explicitly released. A new IPv4 UDP diagnostic,
  captured on the server for only its two synthetic control sockets, returned
  6/6 payloads and cleaned up both allocations. A longer follow-up then returned
  10/11 sent payloads for IPv4 allocation before timing out, while IPv6 allocation
  returned 100/100. Both allocations in each trial were explicitly released.
  The narrow server capture saw ten incoming and ten outgoing ChannelData frames
  in the failed case; it cannot distinguish upstream loss from a changed NAT
  mapping outside that capture filter. No server/application fault is inferred
  from that observation alone. These first failures remain visible alongside
  the diagnostic reruns. After the authorized relay update, six host smoke cases
  passed UDP/TCP/TLS with IPv4 control/IPv4 allocation and IPv6 control/IPv6
  allocation: fresh validated credentials, permissions/channels, authenticated
  responses, 100 exact returned payloads each and all 12 allocations released.
  Those receipts are in `dual-stack-priority4/deploy-20260914T1123Z-74ecbafe/`;
  they do not rerun cross-family allocations or erase earlier UDP failures.
  Host TLS success does not supersede
  the separate pinned Android native TLS trust failure below. Port-443-only
  calling remains unsupported by the observed credential URLs/control endpoint.
  Evidence is in `.codex-test-logs/dual-stack-priority4/`; network scenarios,
  signed-device media, idle APNs and actual published-build compatibility retain
  separate candidate-bound requirements in the executable manifest.
  **Remaining IPv4/IPv6 scenarios, September 14 follow-up:** current host
  messaging-fault controls pass 19 parent/subtest records; the production relay
  TCP/WS/QUIC family fixture passes 13, and the exact tagged old/new quiet/IPv4
  relay integration command passes 15, all without skips. Ten additional Dart
  quiet-policy/migration/durable-fallback controls pass. These do not certify
  phone text display or pending-message reopen on an IPv6-only access network.
  The existing Pixel 6/API 37 plus API 35 emulator UDP proof passes 32 endpoint
  observations, with 16 local TURN and 16 direct routes, all selected local
  candidate families IPv4. Both endpoint receipts have advancing bidirectional
  RTP, secure readiness and eight closed calls. Its explicit ICE restarts do
  not prove native detection/recovery after loss of an established IPv6 leg.
  The separate production-entrypoint IPv4 fixture passes all 27 assertions for
  one call and its Pion oracle; app state and native call surfaces are restored.
  Neither artifact is signed-release or human-audible evidence.

  A live relay audit found no assigned global IPv6 on any interface, despite
  coturn's retained sockets. Networkd had reported `ens5: Failed` after a route
  timeout. Most new public TURN comparisons stopped at fresh credential
  retrieval, including the explicit IPv4 bootstrap variant. The native public
  attempt had two `REQUEST_REJECTED` credential results, zero fresh bundles,
  no endpoint media receipts and two zero-exit Flutter drivers: this remains
  a failed fixture prerequisite, not an audio stall or a passing no-path control.
  Established IPv6 audio failure, native IPv6-only and DNS64/NAT64 complete app
  journeys remain unverified. A namespace on the relay isolates component
  traffic but is not a device-facing access network or a translator. Exact
  topology, remaining prerequisites and current evidence are maintained in
  `Network-Arch/IPV6-Infra-Ops.md`, with raw receipts in
  `.codex-test-logs/network-gaps-20260914/`.

  **Relay recovery prerequisite recheck, 19:11 UTC:** the hostname's IPv4
  address changed after the outage, so the old numeric fixture pin remained
  unusable. The current address passed SSH verification against the existing
  host key; global IPv6 was assigned and matched DNS. Relay/TURN TCP ports
  responded over both families, and the unchanged production-default hostname
  helper obtained two validated fresh credential bundles. Rediscover numeric
  pins before resuming tests. These observations clear the service-readiness
  blocker; they do not rerun native UDP audio, explain historical packet loss
  or supply the missing IPv6-only/NAT64 device networks. Exact source/helper
  hashes and receipts are linked from the canonical network verification record.

  **Focused IPv4 UDP follow-up after recovery:** fresh serial UDP4/IPv4,
  UDP6/IPv4 and TCP4/IPv4 host probes each pass the three predeclared 100/100
  trials, as does the local UDP4/IPv4 control. The UDP4/IPv6 serial comparison
  retains one 75/76 data timeout, one pass and one allocation timeout. A separate
  six-trial paced UDP4 set (three per allocation family, 20 ms, 100-byte records)
  returns all 600 records with no duplication/reordering/stale responses/control
  retries and releases all twelve allocations. Exact sequence joins at the
  relay's ingress/egress capture boundary account for all 1,800 captured packets
  across the three serial UDP4/IPv4 trials and six paced trials, with zero kernel
  drops. Later successes do not explain the original aligned 10/11 timeout or
  locate the uncaptured UDP4/IPv6 failures.
  The packaged relay-host fixture also passes 15/15 in a fresh isolated namespace
  using the exact public-service coturn 4.6.1 executable. All 1,500 records return
  without loss/duplication/reordering; all 30 allocations, its server, generated
  credential config and remote directory are cleaned up. This is component
  preservation, not a repaired public mapping or an IPv6-only device network.

  A separate **confirmed configuration defect, since repaired at 20:28 UTC**: after its
  public IPv4 changed, coturn continued advertising the old address. Three
  external UDP-peer trials each return 0/3 at the advertised allocation address;
  three fresh paired controls each return 3/3 at the current server address and
  allocated port. Same-server TURN hairpin can mask this defect, so two successful
  allocations or their echo/media exchange are insufficient external reachability
  evidence. The operator helper's `--external-ip-only` mode changes only the
  public mapping, preserves other config bytes/certificates/hooks, requires the
  exact preview hash, refuses active allocations and rolls back failed restarts.
  Its five offline regressions and actual non-mutating relay preview are separate
  from the subsequently authorized live deployment. No application recovery code,
  media retransmission or global deadline changes are justified by these findings.

  Native public UDP media now passes on Pixel 6/API 37 and an owned fresh API 35
  emulator: both endpoint verdicts, opposite caller directions, explicit ICE
  restarts, eight secure bidirectional RTP phase receipts and clean hangup.
  The emulator capture proves IPv4 UDP **media** to TURN; the physical endpoint's
  connection family remains unobserved. The existing DNS fixture affects only
  that disposable emulator. QEMU uses unconnected UDP sockets and can timestamp
  captures with an epoch offset from the host: preserve the two failed family
  observer attempts, and use capture-relative media recency plus host file
  freshness. Observer regressions reject control-only/one-way/wrong-port/stale
  traffic, mixed-family ambiguity and wrong process/capture ownership.
  This wrapper uses a local signaling broker and explicit restarts, so it does
  not prove production signaling, spontaneous fault recovery, audible sound or
  signed-release behavior. Tested APK SHA-256 is
  `4b117a6e5bc54ea8ae8634e48e5afd7c17c338732d5142af42a2689fb8546f86`
  (Flutter 3.47.2, flutter_webrtc 1.6.0, Android WebRTC 144.7559.14).
  Canonical topology, configuration/binary hashes, separate failed/passing
  artifacts and cleanup are in `Network-Arch/IPV6-Infra-Ops.md`; private raw
  evidence is under `network-gaps-20260914/udp4-focus-20260914T191758Z/`.
  After manifest validation, the resolving Flutter 3.47.2 explicit-base local
  wrapper passes 11 checks/938 cases with zero skips/failures or identity gaps;
  28 other combined-selection checks remain NOT RUN. The exact source/rules and
  report hashes are recorded in the canonical network entry. This focused result
  does not validate unrelated shared edits or replace the wave/release gates.

  **Authorized configuration application:** the user requested the reviewed
  mapping repair after the undeployed result. Fresh preflight found the same
  config and zero allocations. The IPv4-only helper applied the one-line change
  and restarted coturn at 20:28 UTC, preserving the certificate/key, renewal hook,
  both binaries and the running messaging relay process. All three advertised
  external-peer cases now receive 3/3, as do all three paired controls; all six
  allocations release. Original serial UDP4/IPv4, UDP4/IPv6 and TCP4/IPv4 controls
  each pass 3/3 at 100/100 records. The UDP6/IPv4 comparison separately retains a
  31/32 data timeout, a permission/channel timeout and one pass. IPv4 captures
  account for all 600 ingress/egress records with zero kernel drops. The older
  10/11 timeout remains unexplained; the address repair is not its diagnosis.
  Both native Android endpoints pass two opposite-direction calls and eight
  secure RTP/restart phases with the same `4b117a6e…` APK; the emulator capture
  again proves IPv4 UDP media. Host TLS verification passes both families.
  Cleanup restores settings and removes only disposable fixtures/data. The
  explicit-base local operations check passes 3 checks/91 cases with no gaps;
  36 other combined-selection checks remain NOT RUN. Source/rules are unchanged
  from the earlier 938-case run; these receipts remain separate. Exact before/after
  config hashes, artifact identity and scope are in the canonical network record,
  with raw evidence under `network-gaps-20260914/udp4-apply-20260914T202634Z/`.

  **Independent TURN probe framing:** the retained TLS stream parser had been
  reused for UDP. An unpadded 101-byte ChannelData datagram reproduced a false
  timeout because the parser waited for stream padding; concatenating the next
  datagram could also consume its header as padding. The maintained
  `integration_test/scripts/turn_path_probe.py` keeps UDP datagrams separate,
  permits optional padding, preserves TCP/TLS buffering, demultiplexes stale
  STUN responses/media and validates response integrity. Only STUN control
  transactions may retry within the existing probe deadline; media never does.
  Ten socket/namespace-guard regressions preserve these boundaries and bounded
  cleanup. Use a full Python 3 standard library for the standalone fixture;
  Debian's `python3-minimal` lacks `hmac` and fails before any socket setup.
  The full-library Docker attempt also stopped before coturn: its network-none
  namespace contained down tunnel placeholders, which the strict loopback-only
  guard rejects. That guard remains intact; these are not successful trials.
  The original capture was decoded, with ten frames each way and sequences
  0–4 from both senders at the same relay capture boundary. The historical
  payloads were aligned **100-byte** records, so the repaired padding bug does
  **not** explain their missing eleventh payload. Its cause stays unresolved.
  Predeclared three-trial comparisons and first failures are retained. Fifteen
  isolated relay-host coturn component trials passed both control families,
  both sampled allocation families and 101-byte UDP, with all 30 allocations
  released. Do not promote those loopback/host results to native-app recovery,
  NAT64, production availability or signed-media acceptance.
  Its actual runtime identified coturn 4.6.3; the first private relay driver
  omitted the binary/whole-probe digests. The packaged command captures these
  identities; its first relay attempt stopped at SSH. The post-recovery packaged
  execution uses the different, exact public-service 4.6.1 binary and passes as
  recorded above. Keep these two fixture/binary identities separate.
  The earlier explicit-base focused wrapper run passed 11 checks/931 cases with
  no skips or identity gaps; 26 other combined-selection checks remain NOT RUN.
  The exact source/rules digests, omissions and report hash are recorded in the
  canonical network verification boundary. This is not full change/release
  acceptance; each executed source retains its own wrapper report.

  Both platform Go binding stamps were stale relative to current source/tooling.
  Running the existing ensure scripts rebuilt them; current digests then matched.
  Existing signed outputs were retained and hashed before preparing a new build.
  A new signed artifact cannot establish the identity of the previous published
  artifact, and export-name checks alone cannot establish native freshness.
  The integration Dart sweep retained one first-attempt group-media timing
  failure: the ordinary download started after the GPL-04A fixture's two-second
  `_waitUntil` deadline. The entire three-test file passed in a separate run
  without modification. The fixture now observes the actual `media:download`
  bridge completion, asserts exactly one download and waits for listener
  teardown, instead of polling a two-second wall-clock deadline. All three
  cases pass through the explicit-base wrapper after this test-only repair;
  production deadlines and private-policy assertions are retained. The original
  full sweep remains failed; it was not relabeled or repeated for this fixture
  change. Current simulator XCTest executed 79 lifecycle/store/NSE tests
  successfully; unsigned simulator APNs-registration errors do not establish
  signed-device push behavior. The Android native proof's first debug build
  lacked its generated `native_assets.json`; preserving and invalidating only
  that build-cache directory allowed a fresh build. Keep the original failure;
  do not clear application data or broadly clean retained signed outputs.
  The fresh disposable Android APK then passed the existing Pixel/emulator
  native UDP and TCP matrices (eight cases plus restarts per transport). Its
  WebRTC binaries match the new signed AAB for all three bundled ABIs, but its
  debug entry point and isolated signaling broker remain a separate artifact
  boundary. The TLS matrix failed at its first protected call with an ICE
  gathering/exchange deadline and no selected pair; both zero-exit Flutter
  drivers were correctly overridden by the harness's failed endpoint receipts.
  This run did not capture a new native TLS certificate error. A fresh server
  chain check still fails against the 36 extracted pinned native certificates
  at ISRG Root X2, and passes with that root added only to an isolated verifier
  input. This confirms the current chain remains incompatible with those roots;
  it does not substitute for a repaired native TLS media trial or modify trust.
  The first TCP attempt attached to an unrelated emulator Flutter VM and failed
  before media proof. A separate diagnostic passed after stopping that app on
  the owned emulator without clearing its data. Avoid concurrent unrelated
  Flutter debug processes on this harness's test targets; preserve first results
  and do not mistake driver exit zero for executed media assertions.
  The existing local production-call adapter subsequently passed 27 assertions
  with the normal application entry point, fresh accounts/contacts, a disposable
  production relay/coturn pair, native Answer, per-endpoint RTP, controls and
  teardown. Its separate Pion oracle proved exact known-Opus bytes. The existing
  SIMS artifact validator and wrapper inspector accepted that source/debug proof;
  it remains distinct from signed distribution, human-audible audio and APNs.
  `integrated-call-report.json` and `device-audio-supplement.json` retain the
  artifact binding. A focused current Go socket run also executed all 14 selected
  IPv6/address/fallback cases without skips. Follow-up execution identifies the
  historical conditional gaps: the four conversation files containing the ten opt-in
  custody skips pass 278 cases with
  `MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true`; the exact emission
  rollback case passes with `MKNOON_EMIT_WAKE_TOKEN=false`. Those are explicitly
  different build configurations from the default candidate. The skipped host
  SQLCipher capability is exercised by the existing native integration test:
  its disposable Android app passes real export, portability export and staged
  open/row retention. The same three tests also pass on the available iOS
  simulator: the portability leg verifies the Android snapshot's exact checksum,
  applies its cipher parameters and reads the expected schema/rows on iOS.
  Both use the disposable `com.mknoon.sims.sqlcipher` identity, fixture keys and
  synthetic data, without opening or resetting a user's database. Source/debug
  native portability does not certify the unknown previous published binary or
  the signed release artifacts.
  `TestHolePunchFeasibility_LoopbackUpgradeObservable` and
  `TestFeasibility_DirectUpgrade_TcpLane` still skip because forced-public
  loopback hosts do not produce an observed DCUtR upgrade; the IPv6 address-event
  case passes. No NAT upgrade is claimed. The original four skipped wrapper
  selections remain incomplete, with separate configuration/native supplements
  in `continuation-execution-supplements.json`. The explicit-base focused wrapper
  passes workflow, provider schema and the repaired fixture; omitted selections
  remain NOT RUN in that focused report. No unrelated broad suite was repeated.
  The ten conversation skips were subsequently removed: persisted-generation
  retry tests execute independently of the rollout selector, and voice/composer
  tests explicitly enable their existing injected custody selector. All ten
  original cases now execute in the ordinary host configuration with unchanged
  assertions and deadlines. Their focused run passes ten cases with zero skips
  in `.codex-test-logs/all-tests-y227gs8x/ten-tests-attempt-001.jsonl`.
- **Established dual-stack messaging failure:** a fresh IPv6 handshake stall
  was already covered, but did not prove recovery of a reused connection.
  A socket-scoped loopback proxy first delivered over IPv6, then discarded
  traffic without FIN/RST. Repeated chat and inbox sends remained trapped on
  that connection after stream deadlines; resetting only the stream did not
  retire the multiplexed connection. **The original timeout-only retirement
  decision is superseded:** a later source-level regression reproduced an ACK
  read deadline closing a healthy shared connection and resetting independent
  traffic. Ordinary/quiet direct sends and ordinary/protected inbox receipts
  all failed before the repair. This is controlled local evidence, not a
  production incident attribution. The committed-message fixture uses the
  existing receiver timeout override to hold application commit past the
  unchanged sender ACK reserve, and resolves confirmation only after its
  synthetic file commit. Production receipt/confirmation timing is unchanged.
  TCP/yamux and QUIC fixtures assert both hosts' exact connection identity,
  bidirectional sibling bytes before/during/after the timeout, no recipient
  ACK, and a later ordinary send on the original connection.
  A timeout now resets only its stream and marks its connection for the next
  existing retry. That retry coalesces a connection-bound multistream handshake
  within its current budget; it never uses peer-level ping to select another
  connection. Any returned negotiation bytes (including unsupported/partial
  responses) preserve the connection. Only an admitted independent stream with
  a completely written request and no response through its bounded deadline
  permits retirement. Protocol resource admission is also enforced; partial
  writes remain inconclusive. Stream admission/resource rejection, resets,
  cancellation and expired admission do not establish dead transport. A canceled inconclusive
  check may retain an idle suspect for a later retry; no background work is
  retained, and Stop clears the state. Hidden stream-open failures only mark
  an unchanged sole candidate, never close an earlier snapshot. Exact host and
  connection ownership fence shutdown and successors. Message command and
  committed-ACK deadlines remain unchanged; inbox connect/check/I/O share the
  existing attempt deadline instead of renewing I/O time after a check.
  A coalesced waiter also observes its own half-budget check deadline, leaving
  its I/O reserve even when another operation owns a longer check; the owner
  retains the single probe. A gated real-connection regression fails when that
  waiter is allowed to consume its entire command budget.
  Native fixtures observe
  selected IPv6 before the fault and selected IPv4 on the subsequent attempt
  without restarting either node, including quiet sends, uncached negotiation,
  ACK loss after receive, relay custody and an open stream still registered on
  the dead connection. A separate same-peer healthy connection remains usable
  through concurrent retirement checks. A no-retirement mutation stays trapped
  on the established IPv6 connection, preserving the need for recovery.
  Identify advertisements in this fixture are restricted to its intended IPv4
  target so an unfaulted advertised IPv6/QUIC route cannot satisfy fallback.
  The original drop conditions and proxy socket are retained. Initial failing
  assertions and fixture diagnostics, focused race checks and the explicit-base
  change selection are retained in ignored
  `.codex-test-logs/shared-connection-recovery/`.
  A UDP blackhole also preserves TCP
  and TLS WebSocket messaging, with the selected address observed and a
  fixture-local trusted certificate for WSS. Dart integration separately proves
  one display identity after ACK loss and inbox fallback, plus retained failure
  and restart drain; it uses
  fake crypto/network, while the database reopen fixture uses real host SQLite.
  These tests establish neither public IPv6 reachability nor signed mobile or
  deployed WSS behavior. Initial setup failures (wrong TCP/WS fixture listener,
  default Go 1.27 QUIC incompatibility, and default Flutter 3.41.4 below the
  repository SDK floor) remain in the evidence root. Use the repository's Go
  1.25.0 and Flutter 3.47.2 toolchains, without changing dependency pins.
  The check wrapper's toolchain header observes the ambient `go version`, while
  `execute_plan` pins child checks with `GOTOOLCHAIN=go1.25.0`; retain explicit
  pinned runtime evidence when the ambient header reports another version.
- **Voice-upload incident boundary:** a 2026-09-10 iPhone incident showed
  “Uploading media” from about 18:56 until 19:10 Berlin. The relay received only
  131,072 of 670,610 bytes before a stream reset; the phone then disconnected
  for 10m43s and retried after the user returned to the app. The retry completed
  in 322ms, followed by relay message storage in about 114ms. This establishes
  failed transfer plus delayed client retry, not a long relay delivery queue.
  The user observed the initial stall before leaving the app. Generic iOS
  `operation=other` bridge failures do not identify its precise cause, and the
  displayed upload label does not prove transfer liveness. Preserve event
  occurrence versus later diagnostic receipt timestamps, and distinguish relay
  storage/push success from recipient acknowledgment. Read-only evidence and
  remaining attribution limits are under ignored
  `.codex-test-logs/voice-upload-delay-20260910-1856/report.md`.
- **Voice-upload stall recovery:** an idle timer around local file reads
  cannot interrupt a blocked network write or final receipt. Upload streams
  now apply the 10-second idle budget to network reads/writes, including
  READY and same-relay custody probes, while retaining the absolute ceiling
  and phase-aware custody rules. Local libp2p stall tests first reproduced
  the missing deadline, then verified complete byte-identical retry and
  same-relay duplicate-proof recovery; race checks also pass. A foreground
  voice failure releases its lease and composer activity before requesting
  one debounced media retry through the existing connectivity/lease checks.
  It adds no idle polling and does not bypass stored retry limits. Pending
  attachment metadata alone renders a waiting label/icon; completed uploads
  waiting for message delivery do not claim upload activity. Widget tests
  cover queued and thrown voice sends, retained recordings, and cleared
  activity. These source fixes do not identify the original network reset
  cause or certify an installed iPhone build. Red/green evidence is retained
  under `.codex-test-logs/voice-upload-delay-20260910-1856/`.
- **Upload feature parity:** the same native upload stream serves direct and
  group photo/video/GIF/voice attachments, posts/pass-along, and group avatars;
  profile pictures use `profile_upload`, which has the same network idle guard.
  The follow-up audit reproduced missing foreground retry hints for retained
  direct photos and group media, plus a group voice projection exception that
  left the composer busy. All retained direct-media branches now request retry
  after releasing their leases. Group media does likewise, with a separate
  debounced hint that preserves network-restored priority, account/connectivity
  checks, and the group recovery gate. Each hint causes one pass; automatic
  failure does not create a new hint or an idle polling loop. Group voice
  cleanup also clears activity after exceptions without deleting the recording
  or touching a newly bound conversation. These host regressions establish
  source behavior; they do not certify a signed iPhone build. Audit evidence
  is under `.codex-test-logs/upload-feature-audit-20260910/`.
  Group pending-card tests must expect the waiting label without active upload
  progress. The background-task unmount fixture must await the native begin
  signal after durable file work; a fixed real-time delay followed only by
  fake-time widget pumps does not establish that boundary. Preserve initial
  broad-run failures when recording diagnostic or corrected-file reruns.
- **Relay payload coverage:** the obsolete empty top-level-notification
  placeholder was retired only after the five existing chat builder tests all
  rejected an injected top-level notification. Existing reaction serialization
  controls remain. The restored final payload selection passes on Go 1.25.0;
  this proves payload construction, not live FCM/APNs delivery. Private mutation
  and restoration evidence is in the crash investigation's
  `release-followup-20260911/go-relay-review/`.
- **Go failure evidence:** the check wrapper retains hashes of the package,
  full test name and top-level test name, including dynamic subtests, without
  copying raw labels or logs. Use `go list` and `go test -list` with the same
  canonical digest to identify a focused rerun. Package-only process failure
  is not invented as a failed test. The original build-118 broad run predates
  this capture and retains only its failed count/output hash; later diagnostic
  failures must not be silently attributed to that unnamed first failure.

- **TestFlight termination evidence:** the four reports investigated in
  [the 2026-09-10 record](testflight-crashes-2026-09-10.md) contain one
  `0xbaadca11` call-report enforcement termination and three `0xdead10cc`
  suspension-with-lock terminations. Allocator, regexp and GC frames in these
  SIGKILL snapshots are not proof of memory corruption or an engine defect.
  The committed PushKit receiver-retention correction is verified in matching
  distributed 115 and 117 binaries; 115 is the earliest established inclusion.
  The notification coordination lock can still span awaited work. Its existing
  same-isolate contention queue addresses a different condition and must not
  be claimed as a suspension fix. R4's ledger stack supports a probable owner;
  R2/R3 do not identify the locked file. Keep candidate background/CallKit
  evidence incomplete until the manifest's added iOS assertions are observed.
  Scoped iOS background admission now encloses notification BSD locks, rejects
  refused/already-expired grants before action admission. On normal completion,
  Dart ends the assertion after unlock/close; native expiration may end it while
  admitted work remains pending. Existing direct-outbox retry preserves work
  refused admission.
  Native registry tests and three physical iPhone 13/iOS 26.5 Release AOT
  private-container transactions passed with an existing record preserved.
  A controlled 70-second owner outlived its grant at 27.68 seconds and remained
  held through suspension; resume preserved the record. This is a demonstrated
  limit, not a complete `0xdead10cc` fix or signed App Group/NSE proof. Protect
  admission/error/cleanup order with the mandatory notification-lock check and
  native `GoBridgeCriticalTaskTests`; retain expiration and signed-candidate
  evidence separately. Bounded snapshots add local lifecycle/owner-count
  evidence. Counts exclude
  acquisitions before observation/consent, other isolates and native/SQLite
  owners. Uploads use the previous closed-schema aggregate shape while local
  exports retain the new operation/lifecycle fields, so an older receiver does
  not reject an ordinary mixed batch. Inspect the local export for attribution.
  Four real `CXProvider` component runs (two foreground/two background) also
  preserve per-report completion ordering and terminal cleanup; these are
  separate from unexecuted live PushKit delivery. Six real notification-registry
  operations preserve seeded rows and bracket actual UN publication/removal
  with lock ownership and unlock-before-lease-end. These private-container
  component runs do not establish App Group/NSE or expiration safety.
- **Historical native badge ownership:** six supplemental iPhone reports sample
  a badge writer waiting in `flock`; a waiter does not identify the held file's
  owner. The old writer retained its descriptor through the asynchronous badge
  callback and could block the serial queue needed to release it. Commit
  `a9ec8e12d` releases the descriptor after synchronous submission and preserves
  bounded revision repair. This exact condition fails two existing native tests
  on the historical implementation and passes all seven on the current one;
  matching binary disassembly verifies inclusion in distributed 115/117,
  earliest established 115. Keep those seven methods in the existing
  `run_ios_nse_native_373.sh` selection. This does not prove that synchronous
  badge/state I/O cannot outlive background execution. Private causal evidence:
  crash investigation `remaining-20260911/native-badge-writer/`.
- **Debug crash provenance:** supplemental 107/110 reports match the Flutter
  3.41.4 debug engine, including distinct debug dylibs sharing build 110.
  Matched binary instructions establish allocation-failure aborts in two
  compiler incidents and rejected execution of the generated JIT capability
  probe in one signing incident. They do not establish a leak, jetsam, bad
  application signing, or an upstream fixing version. Eight anonymous executable
  page faults remain unresolved; native dSYMs do not identify their generated
  Dart functions. A retained Release/AOT configuration establishes a different
  execution mode, not a general memory-safety verdict. Keep these separate from
  the supplied TestFlight suspension reports and retain exact UUID matching.
- **Native visibility read admission:** Runner's shared visibility file lock is
  separate from the Dart notification ledger. Its read now holds an existing
  native background assertion and checks liveness after coordinator queue
  admission and again after acquiring the file lock, before reading state.
  A refused read returns unavailable and clears Dart suppression authority;
  it must not skip lifecycle writes or change NSE read behavior. Six native
  behavior regressions join the two existing privacy/lifecycle tests in
  `run_app_visibility_native_371.sh`; they exercise real flock ownership,
  controlled queue/file contention, retained entered-operation ownership and
  unchanged incumbent/future-schema data. The MethodChannel authority regression
  protects null-read notification policy. The visibility suite passes eight
  tests without Go; the combined real-module registry/visibility suite passes
  20, and focused Dart tests pass 12. An optimized, debugger-free iPhone 11
  component also passes foreground/background/resume reads with the real UIKit
  registry, actual flock ordering and seeded bytes preserved. Pre-change and
  queue-only failures remain in `remaining-20260911/visibility-review/`; the
  physical receipt is in `visibility-physical/`. This private-container proof
  does not certify App Group/NSE or a signed candidate. Already-entered I/O may
  still outlive expiration; admission protection is not complete suspension
  safety.
  New build retention stores
  exact IPA/archive/dSYMs, input hashes, filtered binary patches and untracked
  source archives. Excluded credential/configuration inputs remain hash-only;
  older captures and compilation-time transient changes remain explicit gaps.
  Keep source and distribution evidence separate even when labels agree.

- **Android reconnect harness admission:** `am start -W` can return exit zero
  with `Status: timeout` while Flutter is still completing first-run migrations.
  The reconnect runner accepts that status only with the requested component,
  no launch error and a live PID, then retains its bounded identity-readiness
  check. The old launcher failed before the device journey; the corrected
  phone/emulator campaign passed queued-message drain and reconnection checks.
  Keep the exact host contract and real device proof separate, and retain
  initial failures when a harness correction enables a subsequent pass.

- **Overlapping local discovery startup:** a physical Pixel 6 / API 37 debug
  cold launch at `5a9bb5c94503d3e48dca734f4d2b2cb06fe8141a` retained the fresh
  identity but emitted an unhandled Bonsoir `isReady` assertion from
  `BonsoirDiscoveryService.startAdvertising`, through `LocalP2PService.start`
  and `startEarlyLocalDiscovery`. Startup, warm-up and router entry points
  overlapped while native readiness was pending, replacing the broadcaster.
  The coordinator now shares one pending start and clears it for a failed-start
  retry. The causal host regression observed three starts before the fix and one
  afterward; early ordering, composition and late-disposal compensation remain
  covered. Updated physical Android cold launches retained identity without the
  assertion. Relay readiness alone still does not prove LAN discovery. Redacted
  evidence is retained in
  `.codex-test-logs/live-phones-20260912T084648Z/android-local-discovery.redacted.log`.
  A separate host fixture reproduced four overlapping native starts when
  resume and a libp2p address refresh bypassed that startup future. The existing
  `LocalP2PService` now joins pending startup and coalesces advertising refreshes,
  publishing a newer port snapshot before the shared refresh completes. The
  fixture observes one active start and one subsequent refresh; existing failed
  startup retry, Bonsoir error containment, denial gating and disposal controls
  still pass. Evidence is under `.codex-test-logs/dual-stack-recovery/`.

- **iOS discovery errors during resume:** physical iPhone13 / iOS 26.5 emitted
  an unhandled Bonsoir `PlatformException(discoveryError)` with native code
  `-65569` (`DefunctConnection`) after suspension. Captured events showed the
  existing resume path replacing the browser and discovering peers afterward;
  this was an unhandled stream error, not proof of failed recovery. The existing
  subscription now consumes errors and records only a fixed reason and numeric
  native code. No error message, peer or address is copied into that diagnostic.
  The factory-seam regression reproduces the error and preserves stop/start
  recovery, without adding a new retry or native lifecycle owner. First device
  failures and host red/green evidence remain under
  `.codex-test-logs/live-phones-20260912T084648Z/`.
  The final normal profile build reproduced native code `-65569` after
  Appium-confirmed suspension on both physical iPhone11 and iPhone13. Both
  emitted the handled diagnostic, restarted discovery and found peers again,
  with no unhandled exception in that captured resume window. The redacted
  timestamp/line receipt is `final-ios-resume-proof.json` in that evidence root.

- **iOS DNS-SD resolve handle lifetime (R2-2):** four beta iPhone crash reports
  in `artifacts/beta-20260927/crash/` implicate the vendored Bonsoir discovery
  resolver. Its read handler could call `DNSServiceProcessResult` while main
  deallocated the same handle, and its callback mutated a service object off
  main while Flutter serialized it. The fork now cancels each read source and
  deallocates in its cancel handler on the resolver queue; service updates and
  event delivery run on main. The `bonsoir_darwin` iOS simulator pod build passed
  on 2026-09-28. No long-running device discovery soak has yet established
  crash-free operation; the build is compilation evidence only.

- **Disposable transport profile contract:** the debug activation policy allows
  iOS disposable profiles and requires distinct account/transport authority
  for Android disposable profiles. The behavior cases in
  `debug_e2e_composition_root_test.dart` protect both modes and invalid authority.
  Keep the production source contract focused on the nullable root-owned
  handoff; the former unconditional Android-or-iOS text assertion contradicted
  that existing policy and failed the combined host sweep.

- **Runtime preservation inventory:** the DTR-10 database-floor anchor must
  advance with the production schema (v119 for durable quiet recovery).
  DTR-18 body fingerprints also include reviewed changes within an existing
  adapter: the committed incoming group-media key requalification under its
  lifecycle lease and the quiet message annotation delegate do not relocate
  repository ownership. Keep the exact fingerprints and repository behavior
  tests together; older fingerprints failed the combined sweep despite the
  retained data-layer placement.

- **Group media proof schema:** endpoint admission, Android receipts, shared
  criteria and iOS boundary validation must require exactly
  `currentIdentityDatabaseVersion`. Literal schema 104 checks rejected the
  current schema 118; actual phone/emulator PRAGMA receipts confirmed 118 after
  the correction. Tests accept the current schema and reject obsolete/future
  versions while preserving cipher, role and path checks. Passing this setup
  boundary is separate from successful media transfer. The subsequent P269
  control proved a distinct-device fixture with no signed creation/genesis/
  completion rows; the production authority resolver correctly refused it.
  Do not fabricate proof rows or weaken authority admission to turn that
  fixture green. Authenticated linked-bootstrap media proof is a separate leg.
  The pinned libp2p 0.39.1 client filters private-IP relay addresses before
  circuit advertisement; a warm connection alone does not establish readiness.
  A DNS4 name verified to resolve to the same local fixture on both devices
  restores the unchanged circuit-readiness assertion. Keep its local-network
  scope explicit. The shared linked-device harness also requires the four
  strict-reaction staging/ownership/terminalization callbacks already wired in
  production, and must pass its group message repository to strict REMOVE.
  Missing dependencies produced `unauthorizedSenderKey` and `notMember` in the
  device fixture. Real SQLite tests now exercise that fixture's constructor;
  authorization checks and all reaction assertions remain intact.

- **Group media proof authority modes:** the retained distinct-primary P269
  setup declared an initialized device identity without authenticated linked
  bootstrap. That fixture is not evidence of a production authorization defect.
  The explicit Android `accountBoundLegacy` proof mode now uses normal node
  startup and the existing create/invite/accept use cases. Account and transport
  IDs must match within each ordinary primary, and the two accounts must differ.
  The default remains `distinctAccountAndTransport`; iOS keeps that mode. Build,
  endpoint, runner and artifact declarations must agree. Absent legacy mode is
  compatible only with the default; null, malformed, mismatched and old-APK
  receipts are refused. Real SQLCipher/schema, media/render, ACL, retry and reset
  assertions remain required. Host fixture tests do not certify native crypto.
  The separate linked-group B1b pass covers its actual linked bootstrap scope.
  The invite-accept wiring sentinel checks both branches: legacy mode omits
  device/transport/key-package IDs, while distinct mode supplies the complete
  tuple; both retain the account and ML-KEM material. Its former unconditional
  tuple assertion rejected the intentional legacy branch. Preserve these
  authority checks when changing the proof composition.
  Account/transport equality belongs to that explicit legacy fixture mode.
  Production distinct-primary protected replay must instead use the active
  local node transport from the existing P2P service, independently of the
  incoming destination. The composition previously substituted the account ID
  in both authority and content lanes. Its [causal regression and verification](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/group-media-replay-transport/validation-summary.json)
  retain wrong-route failures, actual-composition recipient/cutover controls and
  real SQLite key/history/reconciliation application with explicit fake crypto.
  Foreground and recovery roots supply the same runtime binding; absent or
  changed runtime stays prerequisite-waiting, and linked credentials must match
  account, public key and current transport. Leaf authentication remains required.
  Scoped host passes do not certify native cryptography or an installed transfer.
  Strict sender completion must use the durable publication contract: the
  canonical atomic commit marks the parent sent/inboxStored, clears its wire
  envelope and retry payload, and moves exact stored custody to cleanup pending.
  It does not change the durable attachment's `upload_pending` status; the
  coordinator's returned `done` attachment is an in-memory copy. The fixture's
  action, SQL probe, controller and criteria must join that raw sender status to
  terminal parent identity and immutable manifest/ciphertext/custody evidence.
  Receiver and legacy `done` requirements remain. Cleanup may retire custody
  before a later probe, so preserve the exact pre-publication stored proof;
  missing or pending parent publication must not pass. The [real-SQL regression](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/group-media-strict-preparation-diagnostics/sender-real-sql/scope.json)
  retains the old oracle failure and successful MP4 publication with explicit
  fake crypto/upload. It does not explain the earlier installed preparation
  refusal or establish native transfer success.
  Protected group uploads require the relay's media-custody admission gate as
  well as acknowledged inbox custody. Relay media admission now defaults to
  enabled for an unset or blank `DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED`.
  Explicit `false`/`0` and unrecognized nonempty values still reject new uploads;
  accepted blobs remain downloadable and acknowledgeable while draining.
  The [default-admission regression](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/relay-media-admission-default-on/validation-summary.json)
  first reproduces refusal with a genuinely unset variable, then passes actual
  framed upload/download/ACK for both direct and group ciphertext. The focused
  custody race suite passes 102 cases and the selected relay suite passes
  1,302, with no failures or skips; the counts overlap. The whole change wrapper
  remains NOT RUN because other selected checks were omitted. The separate static
  ownership failure in the group-media debug adapter is now corrected: its
  observer delegates to the canonical prepared-group upload function. The
  exact four network owners remain unchanged. The compile-gated process-death
  barrier is registered only as a typed schema reader, and the contract passes.
  Relay process-handoff tests that prove drain mode must explicitly set
  `DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED=false`; an unset variable now
  exercises enabled admission. Device-fixture snapshots contain process-global
  selected-route counters, so their contract compares against the captured
  baseline, including a seeded nonzero prior observation, rather than assuming
  every fixture starts at zero. Fixtures register cleanup immediately after
  creation. The repaired integration suite passes 1,539 cases with no failures;
  its helper-only process entry remains skipped and the wrapper consequently
  reports incomplete execution. Original failures and the repaired owning run
  remain in `.codex-test-logs/all-tests-y227gs8x/checkpoint-002/` and
  `checkpoint-003-repaired/` respectively.
  Source defaults do not change an existing deployed process: an older relay
  needs an explicit enabled environment setting or a binary upgrade. These Go
  tests do not establish a passing physical-device media scenario. The subsequent
  [AWS10 attempt](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-group-media-10/investigation.md)
  verifies matching epoch-2 authority and observes successful protected transfers,
  but fails the post-restart `receiver_recover` endpoint with an unclassified
  `StateError`. Its closed failure receipt omits the exact recovery condition;
  final reset removes the intermediate state. Do not assign app-versus-fixture
  causality or claim completed recovery/rendering from the package-level network
  trace. The subsequent [AWS11 correction and device proof](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-group-media-11/final-review.json)
  close recovery and rendering on the physical Android/emulator pair. The
  restart query had excluded every group custody fingerprint, although the
  shared recovery coordinator supports the strict owner. A real SQLite
  regression first reproduces the missing committed attachment. The query now
  includes fingerprinted rows only with exact group/message/attachment-scoped
  incoming committed custody; missing or crossed custody stays excluded and
  the durable fingerprint never demotes to legacy transfer. Paging, secure-key
  hydration and post-commit exclusion pass alongside the existing no-demotion
  sentinel. The affected storage/recovery and strict-media selections pass
  298 and 129 cases respectively, with overlapping coverage and no skips/failures.
  Recovery failure receipts now preserve a closed checkpoint, error code and
  completed work/attempt counts before reset; arbitrary exception text remains
  excluded. The 159-case schema selection passes. AWS11 proves a fresh receiver
  process, unchanged committed JPEG custody, JPEG attempt two, one MP4/voice
  attempt each, all three rendered surfaces, and zero second-pass retry work.
  Source, APK and cleanup identities are retained; earlier failures keep their
  original verdicts. The final batch full host sweep remains unrun.
  AWS admission is now persistently enabled by explicit user instruction,
  with one restart and verified post-test health; the previous off-restoration
  policy is superseded for this deployment. The deployed binary is unchanged.
  An isolated relay fixture can exercise
  the real handlers with both gates enabled and Redis behavior backed by
  in-process miniredis; that does not certify a deployed cloud configuration or
  persistent Redis. Bind its address to the actual APK configuration and restore
  only its owned device port mappings. The [group06 audit](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-group-media-06/independent-final-review/review.json)
  verifies those inputs and cleanup while retaining the failed transfer verdict.
  Native upload diagnostics preserve only the response boolean and allowlisted
  error code; they must not alter the returned map, exceptions or retry policy.
  A missing diagnostic does not establish that native upload was never called.
  Protected incoming content commits its parent, attachments and custody before
  publishing a parent projection with no transient media. Emitting that parent
  alone does not start automatic downloads. Dispatch the existing tracked
  recovery owner using the exact durable group-owned attachments after the
  applied commit, without awaiting transfer in the publication callback.
  The [causal database regression](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/group-media-protected-receive-dispatch/application-test/scope.json)
  reproduces the old missing dispatch after a real SQLite commit and checks
  duplicate/rejected content, shutdown ownership and unchanged pending custody.
  It uses explicit fake crypto and a held network callback; it is not a native
  download or ACK proof. A key-only host authority fixture must first establish
  a signed historical membership snapshot through the real replay path before
  testing content admission; current membership rows alone are insufficient.
  This requirement also applies to normal creation for an initialized,
  distinct-device roster. The retained [real creation-path failure](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/group-media-created-authority-application/causal-red.json)
  ran creation, its generated invitation, receiver materialization and key
  rotation through production owners. Key COMPLETE/reconciliation succeeded,
  but protected content remained prerequisite-waiting without authenticated
  membership history. This is separate from the earlier fixture-only
  uninitialized-bootstrap refusal.
  Creation now decides from the validated proposed roster, including a first
  physically bound invitee whose creator remains account-bound. It reuses the
  canonical per-member `memberAdd` owner: persist PREPARED with the signed
  proposed configuration and frozen complete recipient bindings, commit the
  member/native configuration/watermark, then activate or durably abort.
  Delivery includes the newly added recipient. Protected creation retains the
  final canonical configuration for invitations and omits the contradictory
  legacy aggregate publication. Ordinary uninitialized creation preserves its
  legacy path. A runtime-owner cutover is rejected; failed cancellation or an
  ambiguous commit retains durable ownership and stops the batch instead of
  continuing later contacts or reporting readiness.
  The [verified host evidence and input bridge](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/group-media-authority-history-readiness/port-preparation/independent-final-review.json)
  include 39 creation-owner cases, six actual-composition SQLite cases, and
  affected-group/schema/storage/strict-media passes of 3,181/144/286/113, plus
  520 passes across the 39 remaining selected creation consumers. Counts
  overlap; all executed cases had zero failures/skips. The four-check wrapper
  retains its overall NOT RUN status and 102 omitted rows. Frozen execution
  source `3a622591` is bound to guarded MAIN `48b6149e` and STAGE `5f4bcccb`
  through exact payload and selection equivalence, not a claim of repeated
  execution on those roots. The SQLite regression now admits protected media
  after actual creation/invite/membership replay/key rotation, without seeded
  metadata or an unrelated harness action. Cryptography and queued network
  delivery remain explicit fakes. The six-case callback at that frozen source
  also omitted production's `requireMembershipVersion` postcondition; it is
  not complete validation of production authority projection. The retained
  [production-callback regression](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/group-media-invite-watermark-convergence/production-callback-red.log)
  uses `applyProductionCanonicalProtectedSystemAuthorityReplay` and reproduces
  retryable membership replay after a real signed invite stores the same event
  timestamp without its event ID. Keep the generic SQL refusal of an equal
  timestamp with a missing/conflicting event ID; authenticated invite data must
  preserve the complete version rather than bypass that check. Signed group
  configurations now carry optional `membershipVersion` with the committed
  `eventAt` and `eventId`. The complete configuration is covered by the existing
  invite signature. Validate both fields against the authenticated freshness
  watermark before materialization; retain the ID only when the accepted
  timestamp still matches. A raised re-entry freshness floor must not retain an
  older event ID. Pre-commit configuration overrides omit the pair, including
  an override equal to the stored timestamp. Legacy invitations without the
  pair retain their behavior; resending an invite to an already joined group
  does not silently repair older timestamp-only rows.
  Both application-test peers now use the actual production replay callback,
  including its complete membership-version postcondition. The
  [eight-file validation](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/group-media-invite-watermark-convergence/validation-summary-final-eight.json)
  retains focused 63, strict 124, preservation 154, and qualified schema/storage
  144/286 passes on their exact recorded inputs; these counts overlap. The
  initial 237-file consumer run remains FAIL (3,612 passes, two failures, three
  declared skips). The corrected smoke and widget files pass 88 and 245 cases.
  The other 235 files retain their unchanged-input qualification, including
  three explicit default-off direct-media cases; skipped cases were not run.
  Build signed-invite fixtures with
  `loadCurrentInviteMembershipFreshnessState`: combining a complete timestamped
  version with an old hash-only proof watermark is an inconsistent invitation
  and must remain rejected. The subsequent
  [AWS campaign](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-group-media-08/independent-final-review/review.json)
  failed receiver authority readiness, with full device and AWS restoration.
  Its process trace alone does not prove the exact database tuple. These host
  passes do not certify native transfer or close the open device capability.
  Host waits retain an allowlisted timeout stage and already-matched endpoint
  observations before reset. Keep polling intervals and deadlines unchanged;
  missing or mismatched endpoint results must not become successful receipts.
  A strict local authority is not proof of convergence to a later creator
  rotation. Before repair, the receiver readiness helper accepted any settled
  epoch without an expected creator epoch or authority argument. The retained
  [AWS09 investigation](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-group-media-09/investigation.md)
  records strict receiver acceptance at epoch 1, creator latest-key reads at 2,
  receiver reads still at 1, and a host comparison failure before media send.
  The [focused counterexample and comparison control](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-group-media-09/diagnosis/authority-readiness-reproduction/result.json)
  reproduce premature readiness through the unchanged helper and the exact
  host comparison: old settled authority fails, while the fresh version passes.
  SQLite is real; cryptography/delivery and the complementary receiver identity
  projection are explicit fakes. The four live comparison inputs were not
  retained because artifact construction throws before writing and final reset
  removes endpoint files. The exact live failing term and eventual production
  convergence remain unproven for that failed attempt. The
  [nine-file readiness correction](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/group-media-authority-target-readiness/validation-summary.json)
  now passes a closed creator target through the host command and actual debug
  composition to the receiver: group digest, key epoch, authority digest/event
  time and roster digest must all match its strict local observation. The
  existing thirty-second bound and 200 ms polling interval remain unchanged.
  The final cross-peer comparison is unchanged. The host first retains the
  four observations, identity digests, process IDs and rotation counts in a
  closed diagnostic; its `not_yet_compared` marker is never a passing proof.
  The real-SQLite regression first fails with premature readiness, then passes
  by waiting through old strict authority until the exact target arrives.
  Timeout, malformed/wrong-group command and failed-comparison retention
  controls pass in the 151-case schema selection. Workflow has 86 passes and
  analysis is clean. The first wrapper Flutter-startup failure is retained;
  the exact selected command subsequently passes without source changes, so
  the whole initial wrapper is not relabeled PASS. These host results do not
  certify the whole corrected AWS APK scenario. AWS10 now verifies the exact
  creator/receiver target on the phone/emulator pair, then fails later in receiver
  recovery after process restart, as recorded above. AWS11 retains matching
  authority and passes the subsequent recovery/rendering proof after the SQL
  correction. The earlier AWS09 and AWS10 failures remain preserved.

- **Widget waits for durable group uploads:** real file validation, copying and
  hashing can outlive a short `runAsync` delay. Advancing Flutter's fake clock
  with repeated `pump` calls does not establish that this work finished. In the
  serialized-upload cancellation test, wait on the existing upload-started
  predicate with `pumpUntilAsyncWorkSettles`, retaining its bound and all
  cancellation, completed-leaf, no-publication and wake-lock assertions. The
  [closed failure and repair](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/group-media-invite-watermark-convergence/conversation-diagnosis/proposal.json)
  show durable preparation completing after the old assertion failed; teardown
  then removed the temporary file. This establishes the inadequate test wait,
  not a production cancellation defect. The corrected case and its complete
  245-case file pass with stable source/configuration.

- **Strict forwarded-media fixture consistency:** prepared group-media staging
  writes its parent and attachments into the same database. Pairing it with an
  unrelated in-memory message repository hides that durable parent and omits
  strict prepared-content capability, so a refused send can invoke new-message
  rollback. A queued presentation result alone does not prove dispatch. The
  strict forwarding regression must use the real group-message repository over
  the media fixture database and its secure-key/lifecycle scope, and assert
  actual dispatch plus retained attachment/custody and forward provenance.
  Fake blob encryption used with the real prepared-publication database must
  preserve AES-GCM framing length: ciphertext has plaintext length plus a
  16-byte authentication tag. A copy-only fake reaches custody but correctly
  fails the SQL manifest/plaintext-size join. Correct the fake framing, retain
  that first failure, and keep actual cryptography outside the host proof claim.

- **Bootstrap fingerprint review:** DTR-18 is a structural ownership contract,
  not a runtime crash test. The secure-key scope and direct/group retry bindings
  add dependencies at the existing app bootstrap; they do not move an owner.
  Rebaseline the two bootstrap fingerprints only after checking the exact diff
  and reconstructing the old identities. Keep the notification callback count,
  URI rewrites, import sets and relocation assertions intact. The September 11
  review demonstrates three stale-fingerprint failures and a four-test pass;
  behavior remains covered by the separate startup and media tests.

- **Linked-group terminal verdict capture:** Flutter may uninstall a completed
  endpoint before the host retains its app-private verdict. Both B1b roles now
  opt into the existing group multi-party capture handshake. Publish the linked
  completion signal before waiting, because the sibling needs it to finish.
  Capture both original verdicts, synchronize held roles, stop the broker, then
  deliver target-only capture acknowledgements. An acknowledgement attests
  captured bytes, never application success. Controlled tests cover immediate
  uninstall, dependent sibling completion, captured false verdicts and refusal
  to acknowledge missing/conflicting capture. Keep the original application
  criteria and completion deadline. The existing launch-spec suite is included
  in `group-harness-contract`; native device evidence remains separate.

- **Strict group media waveform canonicalization:** an ordinary image has a
  nullable attachment waveform, while its protected manifest canonicalizes
  absence to an empty list. Comparing these with the generic null-sensitive
  waveform predicate rejected a valid image as
  `strict_group_media_manifest_mismatch` on the Android phone/emulator pair.
  Normalize absence only at this local attachment-to-manifest boundary. Leave
  signed bytes/hash checks, nonempty sample equality and durable-row equality
  unchanged. The existing send-use-case suite protects absent/empty image,
  matching voice, different samples, missing committed samples and uncommitted
  samples; its absent-image case fails before the correction. This is a
  separate feature-preservation defect, not an established iOS crash cause.
  The mandatory `strict-group-media-manifest` check pairs those cases with the
  existing TC-365-02a upload descriptor sentinel. Its fixture/host limits stay
  separate from native device custody and ACK evidence.

- **Strict group media secure-key ownership:** SQL stores a canonical secure
  key reference while the signed media commitment contains the resolved key.
  Raw string comparison rejects valid persisted media. Resolve exact canonical
  references before entering SQLite, under the existing media lifecycle lock's
  exclusive scope, and hold ownership through commit or rollback. The immutable
  proof is bound to its database, attachment, message and reference and becomes
  unusable when its callback ends. Never persist the resolved key as a repair.
  Canonical absence also admits either SQL null or an empty waveform array;
  changed nonempty samples remain invalid. Twenty-four existing real-database
  fixture cases cover legacy and secure rows, reopened data, recipient shrink,
  completion, malformed references, key-read failure, stale/cross-database
  proofs and actual key-mutation exclusion. Removing ownership permits the key
  to change during SQL in the controlled RED test. Foreground and headless
  compositions pass this scope explicitly; protected reconciliation obtains it
  before the page transaction and releases it after commit or rollback.
  TC-364-03a protects that page boundary and exact ACK ordering. These cases
  join `strict-group-media-manifest`; the existing repository and recovery
  suites form `group-media-storage-preservation`. Fake secure storage and host
  SQLite do not establish native keychain or iOS suspension safety. This is a
  separate confirmed storage defect, not an attributed TestFlight crash cause.

- **Incoming group key representations and ACK:** protected receive inserts
  its attachment projection directly, so existing incoming rows can contain
  the legacy key value inside encrypted SQL. Outbound staging's canonical
  secure-reference expectation must not be applied unconditionally to those
  rows. Under the existing attachment lock, the two incoming-group commit and
  local-deletion callbacks now verify the actual stored representation before
  SQL: exact legacy equality, or canonical per-attachment reference plus exact
  secure-store value. Only the proven key field changes in the expected map;
  stale nonce, size, hash, waveform, owner, message, fingerprint and custody
  still refuse promotion. Key-read failure propagates and releases ownership.
  Keyless local deletion remains valid because it does not decrypt. The
  existing real-database download and deletion tests now cover both persisted
  key representations; deletion also retains its keyless case. Reopened legacy
  data, secure-read ordering, unchanged storage and no ACK before durable
  commit are protected. Direct/outbound producers retain their existing
  canonical staging path. These source/database regressions are distinct from
  native crash attribution; device and signed-candidate evidence stays in the
  investigation record.

- **Direct-media contact handoff:** generic intro commands are consumed before
  awaited work completes. Staging both commands and then cold-relaunching each
  app lets the old receiver consume its command before the host kills it;
  the replacement has no command and the old receipt appears stalled. Stop
  and verify both previous processes absent before staging either command,
  then start both without another force-stop. Controlled old-poller and failed
  stop-verification regressions protect this handoff. Initial custody actions
  also stop before staging: retaining their config until completion did not
  prevent an old process from starting effects or deleting a failed request.
  Resume/reopen paths already used the correct order and remain unchanged.

- **Remote ICE drain capacity:** authenticated ICE can overtake its earlier
  SDP within the existing 64-sequence reordering window. The executor could
  retain 64 candidates but submitted them as one batch to a WebRTC wrapper
  limited to eight; nine or 64 ended negotiation. The executor now reads the
  engine's batch capacity, preserves order and future generations, and fences
  each batch against closure, call replacement and generation changes. A later
  partially applied batch terminalizes through existing cleanup without replay;
  answer delivery now shares the coordinator's hangup interruption fence.
  `call_remote_ice_drain_test.dart` covers authenticated admission through the
  real executor and wrapper, including 0/1/8/9/64, overflow, configured capacity,
  deduplication, malformed material, relay policy, restart and controlled waits.
  It is registered in `call-signaling` in the existing selection manifest.
  `.codex-test-logs/remote-ice-drain/red-reordered.log` retains the failing
  single-batch counterexample; `focused.log` records the passing regression and
  preservation suites. Crypto primitives and native WebRTC remain fakes, so this
  evidence establishes the application boundary, not live audio or device RTP.
- **Mixed ICE policies and media privacy:** relay-only is a local gathering and
  transport policy. Authenticated remote host, server-reflexive, peer-reflexive
  and relay candidates must pass the same structural/native validation under
  either local policy. Applying the local relay filter to remote trickle ICE or
  embedded SDP terminated otherwise valid mixed-policy negotiation. The engine
  now separates common fingerprint/video/candidate validation from local SDP
  privacy validation; local trickle and SDP also reject unsanitized TURN `raddr`
  and `rport`. Native `iceTransportPolicy=relay` remains the primary control at
  creation and server replacement/restart; filtering SDP alone does not prevent
  direct connectivity checks. No SDP rewriting or policy downgrade is used.
  The locked `flutter_webrtc` 1.6.0 package declares WebRTC SDK 144.7559.09;
  the native TURN/TLS repair below overrides only Android resolution to .14.
  Its M144 source maps relay to `CF_RELAY`, sanitizes TURN related addresses when
  reflexive candidates are forbidden, and skips remote DNS/mDNS resolution in
  relay mode. The stats sampler follows `localCandidateId`; a remote relay with
  an ordinary local host/reflexive candidate cannot prove local compliance.
  Native testing also caught M144 changing a TURN candidate to `prflx` after
  address remapping while retaining its TURN port. `RTCStatsCollector` exposes
  `relayProtocol` for exactly that local case. The sampler now recognizes only
  known local UDP/TCP/TLS relay protocols on `prflx`; generic `protocol`, URLs,
  remote relay fields and missing/unrecognized local evidence cannot certify it.
  See the SDK's [stats collector](https://github.com/webrtc-sdk/webrtc/blob/30d5e63ae91da483e06577b5c35ee91cc5e5c3db/pc/rtc_stats_collector.cc#L1037)
  and [candidate remapping](https://github.com/webrtc-sdk/webrtc/blob/30d5e63ae91da483e06577b5c35ee91cc5e5c3db/p2p/base/connection.cc#L1812).
  The production family extension derives only `ipv4`, `ipv6` or `unknown`
  inside the adapters. Local diagnostic route and both candidate families use
  the same unambiguous selected-pair references; malformed/duplicate references,
  conflicting selections, hostnames, redaction and mapped/compatible ambiguity
  preserve unknown. The existing readiness/privacy predicate remains separate.
  Whole-pair relay involvement does not certify the local route. Candidate
  addresses describe candidates or TURN allocations; standard stats expose
  neither client's TURN socket family, so both remain unknown even with numeric
  TURN URLs or related addresses. The recorded generation identifies the stats
  read's owner, not an unexposed native candidate generation. Reads spanning a
  restart are omitted from diagnostics, and RTP progress resets at restart.
  The executor supplies provisional/terminal failure classification at its
  existing decision boundary; diagnostic exceptions cannot alter recovery,
  readiness, cleanup or deadlines.
  Go command sidecars distinguish typed failed socket attempts, authenticated
  connections and actual message/inbox streams. They preserve protocol and
  direct/circuit classification, with separate endpoint-to-relay attribution.
  A circuit address prefix cannot prove its underlying relay socket's family
  or the relay-to-peer leg. Fallback requires failed candidate evidence and a
  later successful connection/stream for the same target, protocol and leg
  within one command; changing relay targets clears that correlation. Ordinary
  IPv4 success and hidden attempts inside a successful libp2p dial prove no
  fallback. Inbox acceptance and recipient ACK remain distinct; a write or
  successful diagnostic record promotes neither delivery nor notification.
  New fields use the closed local vocabulary in
  `lib/core/diagnostics/local_connection_diagnostics.dart`. Both collectors strip
  them from uploads while retaining event identity and local export evidence;
  the fixed v1 receiver schemas remain unchanged and reject unprojected
  extensions. Existing consent, retention, buffer limits and sample cadence
  remain in force; Go sidecars retain at most 12 coarse records per command.
  No raw address, IP hash, candidate, credential, message or new native log is
  emitted by this extension. APNs provider/callback/presentation stages remain
  separate: ordinary app diagnostics have no supported courier-family source.
  Host regression evidence, exact commands, initial fixture failures and scoped
  wrapper omissions are retained under `.codex-test-logs/privacy-family/`.
  These host contracts do not establish live routes, APNs delivery, audible
  media, or signed-candidate behavior.
  Host regressions cover all four policy combinations in both directions,
  embedded/trickle ICE before and after restart, egress, and late negotiation
  work after hangup. Existing fingerprint, sender, size/capacity and generation
  sentinels remain required. Red/green and separate native evidence are retained
  under `.codex-test-logs/mixed-call-policy/`. The optional existing real-adapter
  integration test extension audits raw native candidates, wrapper egress,
  gathered SDP address fields, selected local native statistics and advancing
  bidirectional RTP. Its local broker bypasses production signaling and cannot
  prove authenticated libp2p delivery, audible audio, or signed/iOS parity.
  Production Appium calls subsequently exposed a timing boundary: TURN rejected
  a private remote host candidate with CreatePermission 403, and native ICE
  reported failure before later public trickle candidates arrived. Initial
  negotiation now retains its existing canonical deadline for this specific
  checklist failure, allowing later connected events to supersede it. A native
  failed snapshot has a distinct engine error; adapter/configuration/privacy
  errors and standalone established-call failure remain terminal. The bounded
  reconnect classification below supersedes immediate termination for a
  confirmed checklist failure within an owned reconnect. Terminal pending events
  cannot be overwritten by a later provisional ICE failure. Host tests cover
  both event/snapshot orderings, stale readiness, recovery and unchanged timeout
  cleanup. The physical Android/iPhone13 production path then connected in both
  mixed-policy directions; temporary redacted native diagnostics proved local
  TURN/UDP on the protected Android and direct UDP in normal mode. Those
  diagnostic hooks were removed from production source. Normal app Appium runs
  also exercised iPhone11 background CallKit acceptance with its saved relay
  setting. These observations establish connection and selected Android routes,
  not measured audible quality or independently captured iOS selected pairs.
  Evidence, including the first failures, is retained under
  `.codex-test-logs/live-phones-20260912T084648Z/`.
  That Appium run also retained two iPhone13 background attempts with no incoming
  presentation before the caller's `noAnswer` deadline. A later call woke the
  same final build from Appium-confirmed suspended state; PushKit reported
  `metadata_required`, accepted the payload and presented CallKit. Aggregate
  relay APNs counters advanced from 22 to 23 successful sends in that successful
  window with no provider rejection counters. These shared counters cannot
  establish delivery of either earlier missing ring. A follow-up recovered
  per-call relay records proving provider acceptance for both original misses,
  and reproduced another miss at 12:50:03 UTC on the unchanged app after about
  six minutes without a VoIP push. The iPhone stayed suspended through the
  caller's `noAnswer` deadline, without a recorded PushKit callback. Its system
  archive then recorded a development APNs keep-alive failure and reconnection
  at 12:54:19–12:54:20 UTC. Both original misses likewise preceded development
  APNs keep-alive failures/reconnections. The new failed connection used IPv6
  TCP port 5223 over Wi-Fi. This is evidence of an APNs connection failure;
  attribution to the router, ISP or Apple remains a hypothesis. Provider
  acceptance is not phone delivery, and neither rapid retries nor the separate
  Bonjour error containment fixes this boundary. With the same app, token and
  epoch, an Appium-controlled Pixel hotspot comparison used IPv4 APNs and
  presented the incoming call after the same six-minute idle interval. The
  hotspot shared the original Wi-Fi uplink; this was not an independent ISP
  comparison. After restoring the original Wi-Fi, a fresh-connection call
  worked, but the six-minute idle call at 13:12:46 UTC missed again, with
  provider acceptance and no incoming presentation before `noAnswer`. The
  complete archive identified its failed development connection C552 as IPv6,
  with keep-alive failure at 13:16:58 UTC; earlier IPv4 observations were for
  a different connection, C551. Re-reading both complete archives on September
  14 confirms C552 used **TCP 443**, with APNs ALPN and an IPv6 Wi-Fi flow;
  C551 used IPv4 TCP 5223. The earlier C542/5223 attribution must not be
  generalized to C552. The new exports are retained under
  `.codex-test-logs/dual-stack-priority4/apns-dated-*.private.json` and concern
  the older `20260912T105911Z` development build, not candidate 120.
  Do not infer the environment's route from an
  arbitrary APNs connection or an address-filtered subset. The original-Wi-Fi /
  hotspot / original-Wi-Fi idle comparison failed / passed / failed without an
  app or token change. Both failed development connections used IPv6 and the
  passing hotspot used IPv4, but that comparison alone does not isolate IP
  version from the changed local network path. A follow-up on the original
  Wi-Fi, with the same installed app and original router DNS upstream, observed
  another IPv6 miss and an IPv4 pass after suspension; both courier connections
  used TCP 5223. This strengthens the address-family/path hypothesis but does
  not establish a permanent fix. DNS filter selection is not route evidence:
  `apsd` reused a cached numeric IPv4 endpoint when IPv6-only answers were
  requested. Identify the development courier connection in the complete
  native archive for each trial. The historical DNS-filter experiment also
  depended on APNs bootstrap/configuration lookups; its sandbox bootstrap
  lookup had no IPv6 address. That experiment is dated evidence, not an app
  repair or authorization to alter user/router DNS. Any further environment
  experiment needs an explicitly authorized isolated test network. A post-restart comparison retained
  another IPv6 idle miss: the first observed PushKit callback followed an APNs
  keep-alive failure/reconnect, about 54 seconds after invite acceptance and
  after cancellation. Its payload kind was not independently identified.
  On the next IPv4 trial, PushKit arrived about 183 ms after provider acceptance
  and CallKit presented, but Dart invalidated its native lifecycle and ended
  the call about 15 ms later. Preserve this end-to-end failure separately from
  network wake delivery. The retained unadopted terminal from the earlier
  attempt exposed a journal handoff regression: iOS had retired it to a durable
  receipt while Dart still fenced every different descriptor. Host red/green
  tests cover recovery only after acknowledgement of the exact old terminal,
  both cancellation/presentation orderings and both new-call admission orders.
  Missing receipts, live predecessors and adopted-call fences remain protected.
  Receipt acknowledgement must also leave a successor's shared native audio
  and timeout work intact. Appium subsequently exercised that exact sequence
  on the physical iPhone 13 and Pixel 6. Native journal copies established an
  unadopted cancelled predecessor before each successor. In the final profile
  build (`20260913T102834Z`), the same iOS process acknowledged the old terminal
  through sequence 2, adopted the next incoming call after over six minutes
  suspended, claimed audio and completed terminal cleanup; both phones showed
  Connected. A separate outgoing call exercised the same retained predecessor
  and completed in both UIs. These are causal lifecycle recovery checks, not
  merely fresh-call retries. The observed development courier used IPv4 TCP
  5223; these passes do not establish recovery of the failed IPv6 connection.
  Audible quality and screen lock were not independently asserted. In that run the added
  native successor-audio unit test was syntax-checked but not executed under
  the user's restriction against building an iOS test harness. The existing
  RunnerTests target subsequently executed 78 lifecycle/store tests on the
  available iPhone 17 Pro simulator, including
  `testRetiredTerminalReceiptDoesNotReleaseSuccessorAudio`, with zero failures.
  `.codex-test-logs/call-fallback-priority2/ios-lifecycle.xcresult` and its log
  retain the executed XCTest evidence. These native controller/store fixtures
  use fake platform ports; they do not establish live APNs or audible audio.
  The September 14 incoming-call investigation additionally executed all 119
  selected RunnerTests lifecycle, PushKit registry, journal and parser tests on
  the available iPhone 17 Pro simulator, with zero failures/skips. The curated
  iOS token/shared lifecycle host selection passed 116 tests. These preserve
  required reporting, cancellation-before-delivery, expiry, duplicate/coalesced
  pushes, exact retired-terminal acknowledgement and successor audio ownership.
  The source/configuration and `.xcresult` receipts are retained under
  `.codex-test-logs/apns-idle-20260914/`; simulator results remain distinct from
  physical APNs evidence.
  The real HTTP VoIP provider now has opt-in private response receipts, separate
  from the existing development alert adapter. Focused pinned Go 1.25.0 tests
  cover optional/missing/malformed/duplicate response IDs, real response status
  despite body-read failure, distinct attempts, default-off/owner/consent/window
  limits, retention and observer/disk/full-queue failure without changing sends.
  Its focused APNs/wake/diagnostics run passed 141 tests and the receipt race run
  passed. The operator-report regression confirms private IDs stay out of shared
  output. Native/Dart delivery owners and invitation expiry policy are unchanged;
  this is an evidence repair, not a demonstrated OS-delivery fix or deployment.
  The initial wrapper and pinned Go repeat each retained 1,288 passing and eight
  failing relay cases during the live relay outage; one post-recovery pinned
  repeat retained the same live QUIC/WSS/TCP smoke failures. TCP still hardcodes
  the old IP, while macOS application DNS remained stale after authoritative DNS
  changed. These failures were not bypassed with networking changes. An
  intervening unpinned Go 1.27 diagnostic rerun
  panicked in `crypto/tls` and is not a substitute for the pinned toolchain.
  Preserve these first failures and report unexecuted selections explicitly.
  A normal debug APK also needs the existing Gradle property
  `enableAndroidNativeCalls=true` alongside Dart call defines; the first local
  Pixel build omitted it and correctly rejected native capability setup. Its
  replacement was built/installed with that property, preserving both artifacts
  and the existing identity. Do not classify that setup failure as APNs loss.
  The physical September 14 repeat set used the existing isolated Pixel 6 caller
  (Debug 1.0.1(121)) and iPhone 13 recipient (Profile 1.0.1(120), signed
  development, sandbox registration independently matched to the call actor).
  After a successful control, all four predeclared idle calls presented: two
  unlocked after 522.8/394.5 seconds and two locked after 389.6/413.6 seconds of
  OS-confirmed suspension. Native callback-to-report monotonic durations were
  50/54/55/46 ms. Both unlocked calls and the second locked call completed normal
  native answer, adoption, verified media and cleanup (3/4 full idle journeys).
  The first locked call presented but the automation's slider gesture exceeded
  the normal caller deadline; retain its no-answer outcome. An earlier control
  also presented but missed answer due to the wrong accessibility locator. A
  user unlock interrupted one setup interval before any send; that interval was
  archived and restarted, not counted as a call or hidden by a retry.
  The retained Appium MCP/WDA session was a separate process; no recipient app
  polling, debugger or developer-service/container collection ran during idle.
  USB power, existing Wi-Fi and Focus/lock observations are recorded in
  `.codex-test-logs/apns-idle-20260914/REPORT.md`. APNs courier family and current
  Apple delivery logs remain unavailable; these development passes establish
  neither production parity nor a universal reliability guarantee.
  Preflight should inspect the existing diagnostic owner quota: the first two
  controls retained metadata only because the isolated caller reached 5 MiB.
  Its old reports were privately archived before using the app's normal clear
  and re-enable controls. Later per-trace event truncation also requires keeping
  completeness fields: the second locked call's reserved terminal summaries
  verified media on both endpoints even though later caller media rows dropped.
  Missing ordinary rows do not establish a missing callback or media failure.
  A fresh six-check wrapper subset passed 652 tests without the earlier source
  invalidation; overall selection remains incomplete and the Go lane failed.
  This app lifecycle correction cannot repair an OS APNs connection that has
  not delivered a push. The specific network or OS defect
  and a permanent fix remain unconfirmed. These
  observations concern development/sandbox APNs, not a
  verified TestFlight/production APNs candidate. Redacted per-call and OS
  evidence is under `.codex-test-logs/iphone13-background-wake-20260912T123246Z/`.
  Same-Wi-Fi follow-up evidence is under
  `.codex-test-logs/iphone13-ip-family-20260912T150922Z/`.
  The lifecycle fix, exact host commands, final-build device evidence and
  verified restoration of Automatic DNS are recorded in
  `.codex-test-logs/iphone13-ip-family-20260913T092100Z/REPORT.md`.
  The Pixel 6 (API 37) / Android emulator (API 35) TCP run passed all eight
  policy/direction cases and their restarts: 32 endpoint observations, including
  16 protected observations with sanitized native egress and selected local TURN.
  The final receipt records 6 or 8 real host candidates plus 2 relay candidates
  from normal peers, and exactly 2 relay candidates from protected peers. Thus
  the native mixed-policy cases exercised remote non-relay ingress explicitly.
  One normal endpoint selected a local host candidate while the protected peer
  selected its local relay, establishing an actual direct/TURN media pairing.
  The initial UDP attempt failed reverse all/all negotiation because the proof
  delayed SDP publication until full candidate gathering. The physical answerer
  failed ICE before its late answer was sent; a repeat also exhausted the proof's
  gathering deadline before sending the reverse offer. Production already sends
  SDP promptly. The proof now matches that ordering and exchanges bounded,
  generation-specific candidate batches while both endpoints gather. It accepts
  gathering completion only after a current-generation candidate, then audits
  native gathered SDP separately. That bounded audit allows 60 seconds because
  native UDP gathering was observed near 40 seconds even with working media;
  it does not gate SDP publication or extend production call deadlines.
  The current native run exercises remote
  trickle ICE; embedded remote SDP remains covered by the host regressions and
  earlier full-gather TCP evidence. This changes the proof, not media policy or
  production signaling. The test relay port range also stays below this macOS
  host's ephemeral UDP range after an observed startup bind conflict.
  The corrected UDP matrix passed all eight policy/direction cases and restarts:
  32 endpoint observations, including 16 protected observations (12 local relay
  and 4 local TURN-backed `prflx`). SDP acknowledgment took 24–317 ms while the
  longest gathering observation took about 40 seconds. The red/green receipts
  and scoped checks are retained under `.codex-test-logs/mixed-call-udp/`.
  The same final APK also passed the complete TCP preservation matrix.
  Earlier fixture failures and the native selected-pair regression remain in
  the evidence directory; a later passing run does not erase them. The runner
  requires explicit endpoint receipts because this Flutter driver was observed
  exiting zero even when its device log reported failed integration tests.
  Direct libp2p signaling can independently reveal an address; this media policy
  does not make all application traffic anonymous.
  The existing Android native proof now also admits an unreachable documentation
  IPv6 candidate alongside all native candidates and reports selected address
  families, DTLS readiness and actual bad-pair requests. The Pixel 6/API 35
  emulator TCP fallback matrix passed all eight policy/direction cases and
  restarts (32 endpoint observations); native stats recorded 75 requests toward
  the bad IPv6 candidate. Both before and after physical Wi-Fi removal, every
  selected pair was IPv4 TURN/TCP. This proves permitted-path continuity, not
  loss of an established IPv6 media path. Physical Wi-Fi was restored.
  The hostname fixture binds an IPv4-only test proxy to the disposable TURN
  server. The emulator resolved both loopbacks for `localtest.me`, observed
  IPv6 TCP failure, and completed authenticated native TURN allocation and
  bidirectional media through IPv4. Its 32 proxy connections and selected
  relay statistics are separate from DNS evidence. The first attempt required
  dual-stack DNS on both peers and failed because the Pixel returned only IPv4;
  that fixture prerequisite failure remains visible. The hostname leg therefore
  runs on the explicitly discovered emulator. This uses public loopback DNS
  (rejecting non-loopback answers), test-local sockets and no production TURN
  account. A subsequent native run used test-local UDP sockets to receive and
  discard 303 TURN/UDP datagrams while the configured TURN/TCP path carried
  secure bidirectional media in all 32 endpoint observations. It recorded 64
  bad-IPv6 connectivity-check requests and retained all 16 protected local TURN
  observations. This is scoped TURN/UDP loss, not a device-wide UDP firewall
  test. SDP publication took at most 406 ms; the separate gathering audit took
  at most 877 ms. Both endpoints closed between calls, the next calls succeeded,
  fixture sockets/containers/packages were released, and physical Wi-Fi was
  restored. Audible sound, an established IPv6-path loss and signed-candidate
  behavior remain unasserted by this local-broker campaign. Evidence is under
  `.codex-test-logs/call-fallback-priority2/`.
  The same existing runner accepts an explicit JSON-line credential client for
  deployed transport isolation. The client must use the production validated
  provider; credentials remain in memory, are fresh for each call, and are reused
  only within that call's unexpired restart. The deployed authority permits six
  requests per subject per minute. A rapid matrix reached that limit after six
  calls; an independent seventh-request diagnostic returned
  `TURN_CREDENTIALS_RATE_LIMITED`. Space test calls before creating the peer,
  without changing setup/recovery deadlines or relaxing credential validation.
  The paced EC2 TURN/TCP matrix passed 32 endpoint observations, including all
  four policy pairings in both directions, 16 protected observations, 24 selected
  TCP relay observations and eight direct observations. All selected families
  were IPv4; all observations had DTLS and advancing bidirectional RTP. Sixteen
  fresh credential requests succeeded. SDP publication took at most 512 ms and
  the independent gathering audit at most 1,616 ms.
  **Initial deployed TLS failure, retained before the Android repair:** the Android matrix connected
  its normal peers directly, then failed to gather a usable relay for the first
  mixed protected case. Repeated native diagnostics retained `ContinueSSL`
  failure and bounded cleanup. The host's certificate-verified TURN/TLS client
  separately allocated and exchanged 100 exact synthetic payloads per family,
  over both IPv4 and IPv6. Those host passes do not certify Android native TLS.
  The pinned Android WebRTC `144.7559.09` library contains 36 extracted DER
  certificates and no ISRG roots. EC2's served YE2/Root YE/ISRG chain failed
  independent verification against those certificates; adding the required
  ISRG Root X2 to a temporary verification file made that check pass. This
  supports a native trust-anchor incompatibility diagnosis. The inspected `.09`
  validation path used built-in trust and preserved verification failure without
  a successful custom verifier; the mutable upstream M144 branch now includes
  the later repair and cannot identify that old binary. No native trust bypass,
  pin change or service modification was made in that initial campaign. Its TLS
  failure is superseded only within the follow-up's proven scope below.
  Raw/redacted evidence and first failures are
  under `call-fallback-priority2/remaining/` in the ignored test-log directory.
  **Verified Android TURN/TLS repair:** the follow-up began with clean `main` and
  explicit comparison base `74ecbafeec31cf92c5efd1137f9feac85b2a855b`; later
  documentation-only commits through `fcaf1d6ab` were preserved. Current TLS 5349
  over both families serves the complete valid YE2/Root YE/X2-cross-X1 chain for
  `mknoun.xyz`, matching coturn/Certbot files and key public hashes. nginx 4001
  independently serves that chain. Neither expiry (leaf valid September 7 to
  December 6, 2026), a missing intermediate, nor stale copies explain the failure.
  The old AAR matches its upstream digest and all 36 retained roots match binary
  DER bytes and the upstream generated root set. No ISRG X1/X2 anchor is present;
  current chains fail against the unmodified roots at X2. Either X1 or X2 added
  separately to an offline control makes verification pass, while both real
  Android system stores already trust the public chain. The server already sends
  the CA's default X1-compatible chain; its offered alternatives cannot reach
  one of the old 36 anchors.

  The only application code/build change is Android's module-scoped override to
  WebRTC SDK `144.7559.14`, the first published Android M144 patch with upstream
  whole-chain platform trust fallback. The resolved AAR's upstream SHA-256 is
  `44c243bb0c6ac5b0a4425e6211f7994b0d60df3cf2f5721c20c6a88aa1a68f64`; bundled
  native slices match it. This patch also includes Android audio fixes, so the
  preservation matrix remains necessary. The old roots remain compiled in;
  platform fallback and native hostname checks are independently observed.
  `flutter_webrtc` 1.6.0, Flutter, Go, iOS/desktop dependencies, call policy, credentials, deadlines,
  ICE/lifecycle fencing and production Dart code are unchanged. iOS still uses
  `.09`; this is not iOS parity or a signed-device/release pass.
  Gradle dependency insight resolves `.14` for both debug and release classpaths;
  the media fixtures were debug builds. Android build `1.0.1(120)` was subsequently
  rebuilt at the user's request: its signed AAB SHA-256 is
  `7f1d4e8fcb5c24cf6654620fe0c4b708ecb7bb4e053e7e56d7b9ec9a32a73018`, retained in
  `build/releases/1.0.1+120/android-turn-tls-20260914T132035Z/` with provenance.
  All three bundled native slices exactly match the `.14` AAR, and the release
  DEX retains `PlatformCertificateVerifier.verifyServerChain([[B)Z` for JNI.
  The manifest identifies `com.mknoon.app`, version `1.0.1`, code `120`; all 389
  signed entries verify with the same release signer and no unsigned payload.
  The earlier `.09` AAB remains preserved under `android-priority4/` and is
  superseded as the current Android candidate. The new AAB is unpublished and
  has not undergone signed-device media validation.

  After a debug integration-test run, Flutter 3.47.2's `--no-pub` also skips
  release-mode plugin regeneration. A stale `GeneratedPluginRegistrant.java`
  then references `IntegrationTestPlugin`, while Gradle excludes this dev-only
  plugin from release, causing `compileReleaseJavaWithJavac` to fail. The initial
  failed build is retained. Letting the release build perform its normal pub get
  and plugin regeneration fixes the generated metadata; the dependency lock and
  all recorded build inputs remained unchanged. Do not hand-edit the generated
  registrant or include the test plugin in the production release. Evidence is
  in `.codex-test-logs/native-turn-tls-build120-20260914/`.

  A fresh `.09` baseline repeats `all-relayOnly-0` failing without a selected pair
  on both endpoints after direct cases pass. Both drivers return zero, with failed
  endpoint verdicts. The retained before APK's relevant source matches the review
  base. With `.14`, the same Pixel/API 35 emulator pair passes all 32 mixed-policy
  TLS observations. A separate TLS-only relay/relay mode passes eight observations:
  two fresh calls in opposite directions with their ICE restarts, exact native
  `relayProtocol=tls`, sanitized egress, platform chain validations, advancing
  bidirectional RTP and both peers closed before the next call. One intended
  `turns:` service is supplied; UDP/plain TCP/direct cannot satisfy that fixture.
  The runner now requires exact case/generation coverage, both endpoint verdicts,
  RTP, local relay provenance and closure, not just driver exit status.

  Native wrong-hostname controls reject four fresh peers after successful chain
  validation at the independent TLS name check. The self-signed loopback fixture
  rejects four peers at the platform trust check; its listener records eight
  `unknown_ca` alerts and no accepted handshake. Timeout, DTLS readiness and a
  generic TCP label cannot satisfy these controls. No tester trust store was
  changed, and no verifier bypass or production endpoint downgrade was used.

  Separate IPv4- and IPv6-isolated emulator runs each pass eight endpoint
  observations, covering both calls/restarts. Native resolution admits only the
  required family, and owned QEMU/netsimd socket observations independently
  confirm that emulator-to-TURN connection family. Selected allocation/candidate
  addresses are IPv4 in both runs. Automatic private DNS and Wi-Fi were disabled
  only on the owned emulator to retain one virtual network; its original settings
  were restored and verified. The physical peer's TURN socket family remains unknown. The
  initial IPv6 observer failure missed QEMU's netsimd child; native media had
  advanced, but the complete run was correctly failed until attribution was
  fixed. The first IPv4 trial failed its resolver guard when both families
  appeared on the next call. Preserve both fixture failures; neither is a
  certificate/ICE regression, and neither is silently accepted as family proof.

  Subsequent full TCP and UDP matrices each pass 32 endpoint observations, 16
  fresh credential requests and eight closed calls per endpoint. TCP records 24
  local TCP relay observations and eight direct observations. UDP records 16
  local UDP relay observations, including all protected endpoints; normal peers
  also retain direct and server-reflexive paths. All observations have DTLS and
  advancing bidirectional audio RTP. Direct local candidates were IPv6 in the
  TLS matrix and IPv4 in TCP/UDP; unavailable remote families remain unknown.
  Receipts are `tls-ipv4-network-diagnostic/result.json`,
  `tls-ipv6-single-network/result.json`, `preservation-tcp/result.json` and
  `preservation-udp/result.json`. After closure the owned emulator has no
  established TURN/TLS socket. Disposable packages, owned ADB reverse/forward
  rules and the DNS container are removed; the test emulator is stopped with
  its data retained. Production app data and phone trust/network settings are
  preserved.

  The existing Certbot hook has a prepared replacement with protected snapshots,
  whole-chain/hostname/date/order/key preflight, atomic pair promotion, coturn-only
  SIGUSR2 and served-leaf verification/rollback. Five offline tests cover valid
  promotion and malformed, missing/reversed intermediate, wrong-host, untrusted,
  mismatched-key, near-expiry and reload-failure controls. A local coturn daemon
  additionally preserves its PID and existing TLS binding stream while fresh
  connections see the replacement leaf. Fixture CAs certify these mechanics
  only; public-root compatibility is proved by the separate native calls above.
  Five host harness controls reject false receipts/alternate paths and test
  isolated DNS/socket attribution. The first wrapper invocation exposed a host
  test import-path error (direct execution had passed); the test now also imports
  correctly under the wrapper's `python -m unittest` command. That first failure
  remains visible. Both added `integration_test/scripts` files also require
  explicit support classifications in `check_reliability_simulation_discovery.sh`;
  its first two-unclassified-files failure and subsequent corrected discovery
  pass are retained. Check commands must use the package-config SDK, Flutter
  3.47.2/Dart 3.13.2: the initial PATH selected Flutter 3.41.4, so the wrapper
  correctly refused the 24 Flutter groups before executing their tests. The
  corrected-SDK run is separate evidence, not a relabeling of that refusal.
  Stable focused wrapper diagnostics subsequently pass `workflow` (64),
  `affected-media` (537), `native-turn-tls-operations` (10), `affected-calls`
  (929), `call-signaling` (419) and `production-audio-harness-contract` (128).
  The two diagnostic reports have the same candidate identity and no input-change
  gaps; they are `final-diagnostic-checks/results.json` and
  `native-causal-checks/results.json`. These are diagnostic subsets, so required
  omitted checks correctly remain `NOT RUN`, not an overall wrapper pass.

  The broader corrected-SDK run retains its first discovery failure and an
  input-change gap because documentation/classification was edited while it ran.
  Its per-check observations cannot certify one unchanged complete candidate.
  Remaining broad gate limitations are ten conversation skips, one push skip,
  one storage skip and two Go-core skips (1,843 Go-core cases passed, none failed).
  Go-relay separately passed 1,286 cases. The seven selected SIMS checks—audio,
  group media, group mute, media, Android notifications, iOS notifications and
  reconnect—were not run through that wrapper because its isolated account/
  service configuration was not supplied. The native fixtures above do not
  impersonate those production-UI journeys or their report schema. No full
  `host-all`, signed-device campaign or release acceptance is claimed.
  Neither the hook nor a new app was deployed. Exact operational
  installation/rollback remains in `go-relay-server/docs/turn-operations.md`.
  Private evidence and original failures are under
  `.codex-test-logs/native-turn-tls-20260914/`. Audible two-way sound, signed
  distribution, iOS parity and a whole-device IPv6-only/NAT64 network remain
  separate from this native source/debug proof.
  Flutter drive can leave VM-service ADB forwards after exiting. The native
  proof runner snapshots existing rules and removes only new forwards matching
  its own device and recorded driver port. An actual ADB ownership control
  verified removal while preserving pre-existing rules, an unrelated new rule
  on the same device and a logged port belonging to the other device. Fifteen
  leaked forwards identified from these campaigns' logs were removed; unrelated
  forwards were preserved. Receipts are in `remaining/forward-cleanup-control/`
  and `remaining/owned-forward-cleanup.json` under the same evidence root.
- **Readiness observation exceptions:** native snapshot reads can throw
  `WebRtcAdapterException(other)` after recording a fixed WebRTC read stage.
  The real engine wrapper now translates this to `observationUnavailable`;
  readiness retries it and `notReady` on the existing cadence/sample cap without
  resetting the canonical setup/reconnect deadline or reusing successful media
  evidence. Per-read timeouts return the same conservative snapshot as the
  aggregate deadline; partial transceiver/statistics reads cannot certify
  readiness. Explicit transport/configuration/relay-policy failures and
  unexpected exceptions request one exact-call canonical failure. Closed or
  replaced work is fenced before dispatch; successful cleanup still belongs to
  the coordinator/audio owner. Executor diagnostics retain only fixed stages,
  codes and counts; native stage diagnostics retain the failing read boundary.
  `call_readiness_exception_test.dart` uses the real coordinator, executor,
  audio controller and engine wrapper with fake platform/signaling ports and
  captures unhandled asynchronous errors. It checks initial/later observation,
  bounded retry, terminal cleanup, dispatch errors and subsequent-call isolation.
  Engine tests additionally cover native stats failure, incomplete reads and
  optional diagnostic sink failure. Red/green evidence is retained under
  `.codex-test-logs/readiness-exceptions/`. These are host lifecycle and ownership
  proofs, not live microphone, libp2p, audible audio or signed-device evidence.
- **TURN availability and frozen call policy:** normal (`all`) setup and restart
  may attempt direct media after a five-second credential timeout or a typed
  transient service failure. Preserve the approved STUN entries supplied by the
  production build configuration; direct host candidates alone do not prove
  LAN or arbitrary-NAT reachability. Relay-only still requires unexpired TURN.
  Invalid/expired bundles,
  unsupported responses, explicit authorization rejections and unknown errors
  fail closed. Legacy native `UNAVAILABLE` responses are also ambiguous and
  fail closed: only the new classified `TRANSIENT` native code is eligible for
  fallback. Go preserves non-transient rejections across relay attempts;
  connection errors before authentication are conservative unless a deadline is
  proven. One validated bundle is retained per call, reused only while unexpired
  on transient refresh failure, and cleared on close. There is no persistent
  storage or background retry loop.
  Initial preparation and restart recheck exact call ownership after awaiting
  credentials. Late results never install credentials or trigger a restart;
  a later canonical restart fetches again with the call's frozen policy and
  replaces old ICE servers, including clearing TURN on a transient outage.
  `call_turn_policy_test.dart` exercises the real coordinator, preparer, provider,
  executor and WebRTC wrapper using a virtual clock and controlled futures.
  It also caught reconnect timer scheduling after the credential wait; scheduling
  now precedes restart so retrieval consumes the existing 15-second window.
  Focused bridge/provider tests preserve strict validation and coarse diagnostics.
  The production composition test preserves native audio-failure diagnostics
  after startup cleanup ends the call; stale success remains fenced so it cannot
  notify native readiness for a retired call.
  These host tests model selected direct/TURN routes; they do not prove live
  Wi-Fi calling, TURN allocation or audible device media. Red/green evidence is
  retained under `.codex-test-logs/turn-policy/`.
- **Saved call privacy and rollout policy:** availability of **Always relay
  calls** no longer selects a transport. Its stable secure-store preference is
  independent of `VOICE_CALL_FORCE_RELAY_ENABLED`; the release defines disable
  that restriction for normal calls after the mixed-policy proofs below, while
  the production-audio Sims profile explicitly retains it for its TURN oracle. No build
  flag seeds or overwrites the preference. An absent value permits normal mode;
  read errors, a two-second read timeout and unknown values resolve relay-only.
  The settings sheet waits for durable writes, reports failures and disables
  changes when a read fails. The production composition captures the policy at
  the coordinator's first admitted session, before ringing/native adoption or
  media allocation, and retains it in that call's executor for ICE restarts.
  Later preference changes affect subsequent calls, including when the settings
  feature is hidden. Approved STUN comes from the operator's build configuration
  and is kept alongside the existing authenticated TURN provider.
  Production composition, secure-storage MethodChannel, settings-sheet and real
  WebRTC-adapter configuration tests cover these boundaries. Appium on physical
  Android, iPhone11 and iPhone13 additionally verified the enabled preference
  across installed app updates and terminate/activate. Fresh
  identities and contacts also survived normal app updates on all three phones.
  These installed debug/profile observations do not certify a signed release.
  The current Pixel 6/API 37 and API 35 emulator native media proof passed the
  eight policy/direction cases plus restarts over UDP and TCP: 64 endpoint
  observations, with local TURN and sanitized egress on all 32 protected
  observations. Normal/all peers selected direct routes on Wi-Fi and TURN/TCP
  when physical Wi-Fi was disabled and TURN remained reachable over USB; the
  original Wi-Fi setting was restored. Evidence is retained under
  `.codex-test-logs/call-transport-settings/`. This local-broker proof does not
  exercise production signaling, the settings-to-native wake journey, audible
  media, iOS parity or signed artifacts. Opening the direct-first source default
  does not certify publication of a signed release. Direct libp2p signaling may
  independently reveal an address.
  The mixed-policy driver must be classified as a support wrapper in reliability
  simulation discovery. An unclassified driver also fails the global discovery
  assertion used by the PiP native contract; it does not indicate a PiP failure.
  Pin the SDK resolved by this checkout's package configuration: using the
  shell's Flutter 3.41.4 with these Flutter 3.47.2 packages failed native-asset
  kernel loading and Flutter UI compilation; the pinned 3.47.2 build passed.
- **Sustained call-event delivery:** adapter and engine history capacity is not
  a lifetime callback quota. The old delivered-event totals fabricated overflow
  once capacity was reached, even with synchronous consumers keeping up. Both
  layers now keep delivering while evicting old diagnostic history. The native
  emitter handles reentrant callbacks with at most a disconnect edge plus the
  latest event. The executor likewise retains one coalesced record (at most two
  pending events) behind one asynchronous drain; terminal failure supersedes
  ordinary updates and provisional initial ICE failure, while a disconnect
  cannot hide the latest recovery state. Production
  consumers keep stream subscriptions unpaused and coalesce awaited work in the
  executor. This does not bound buffers created by arbitrary paused subscribers.
  Candidate queues, batch capacities and the coordinator's pending-event limit
  remain independent and enforced. ICE restart still advances generation; it
  does not reset an event-delivery quota. `call_engine_event_delivery_test.dart`
  drives a fake native peer through both real emitters and the real executor and
  coordinator, checking 65/256/1,000 consumed callbacks, slow readiness, priority,
  reentrancy, close and stale callbacks. The build contract now asserts complete
  delivery and bounded history rather than the defective lifetime cutoff.
  `.codex-test-logs/event-delivery/` retains red/green evidence. These deterministic
  host tests establish application queue and cleanup behavior, not native callback
  frequency, long-duration device memory usage or live call quality.
  Confirmed ICE checklist exhaustion during an already-owned reconnect had
  also caused premature terminal cleanup. The virtual-clock regression ended
  at four seconds instead of retaining the existing 15-second window in both
  event-first and snapshot-first orderings. Native aggregate failure now carries
  explicit ICE-failed evidence before it qualifies for reconnect recovery;
  unclassified transport, configuration, closed and privacy failures remain
  terminal. A bounded disconnect handoff and classification captured at event
  receipt preserve both recovery and pending hard-failure priority through
  asynchronous/reentrant delivery. No new recovery owner, setup deadline or
  restart budget is introduced. Tests recover at 14 seconds or clean up at
  exactly 15 seconds, retain the 30-second setup deadline, and connect the next
  call. Initial provisional failure remains covered separately. The original
  four failures and passing call/bridge/composition preservation suite (1,037
  tests) are retained under `.codex-test-logs/call-fallback-priority2/`. These
  controlled native-port/coordinator sequences establish classification and
  ownership, not the IP family of a live media path.
  Graph replacement also owns complete native adapter shutdown. Clearing the
  current graph before its asynchronous close finishes allowed a replacement
  to attach, then the old Android EventChannel cancellation or trailing detach
  cleared that same engine's new listener. Register withdrawal before publishing
  unavailable, await complete unbind and shutdown before replacement, and retire
  each exact graph once. Late startup results must recheck graph identity and
  terminal state; shutdown must join an owner already removed from the current
  graph. Failed cleanup leaves replacement disabled when native release is
  uncertain. The composition regression holds both real-adapter close boundaries,
  then verifies replacement `PRESENTED` acknowledgement as `ADOPTED` and canonical
  Answer acceptance. Queued replacement, terminal shutdown, stale refresh and
  failed cleanup are covered in the existing `call-signaling` selector. The
  [145 source receipt](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate145-source/graph-withdrawal/files.json)
  retains both first causal failures and the 216-test composition/Android/iOS
  preservation pass. This proves the source race; it does not by itself attribute
  the historical 144 device Answer loss or certify the replacement APK.
- **Local Android audio isolation:** the existing production-call journey now
  fixes its build/cache/driver identity to `com.mknoon.sims.productionaudio`.
  Its activity class remains `com.mknoon.app.MainActivity`. Keep native calls
  enabled and Google Services disabled only for this local relay/coturn proof;
  the FCM profile must retain its provider configuration. Assert resolved build
  arguments and semantic owners, rather than global source-text occurrence
  counts. The exact system-owned Answer, RTP/oracle and cleanup assertions
  remain required; host contracts cannot certify actual audio or publication.
  UIAutomator reads must be coalesced per device: concurrent Connected/control
  assertions otherwise compete for Android's UiAutomation connection. Treat a
  missing-file message from `adb exec-out cat` as an unavailable capture even
  when its host exit code is zero; it never proves that a control is absent.
  The September 20 Start-voice-call timeout also retained an emulator screenshot
  with a System UI ANR dialog covering the conversation. A later Appium MCP
  capture confirmed the dialog was still present; selecting its Wait action
  removed it. This establishes an OS-overlay obstruction, not an app-control
  regression or passing audio journey. Preserve the original failure, recover
  the owned test target, and retain the unchanged semantic assertion and
  deadline for the fresh campaign. Evidence is under
  `.codex-test-logs/failure-fixes-20260920/appium_*` and the original timestamped
  failure captures in `build/sims/proofs/android.production_1to1_audio_call/`.
  The September 21 fresh run passed all 27 unchanged assertions on USB Pixel
  `21071FDF600CSC` plus the available, responsive `emulator-5556`; the original
  `emulator-5554` stalled Android services during Appium setup. The source/debug
  APK was freshly prepared, then consumed through its attested cache identity.
  The wrapper verified the scenario report; native calls were released on both
  peers, app state was restored, and neither disposable package process remained.
  Receipts and retained captures are under
  `.codex-test-logs/failure-fixes-20260920/audio-after-host/` and `audio-proof/`.
  This scenario PASS does not turn diagnostic omissions, unrelated unmapped
  workspace additions, skipped host cases or missing provider fixtures into
  complete release coverage. A failed Flutter discovery with live ADB targets
  is an observation failure, not evidence that the hardware is unavailable.
  Appium's embedded MCP process needs its own `ANDROID_HOME` or
  `ANDROID_SDK_ROOT`; a working shell `adb` does not establish that environment
  in an already-running MCP server. A fresh instance of the unchanged local
  stdio server with the installed SDK path can create both pinned Android
  sessions without resetting app data. While Appium UiAutomator2 owns a target,
  do not run the separate FastUiDump instrumentation: it competes for the
  UiAutomation connection and can fail before any app assertion. The same
  restriction applies to shell `uiautomator dump`: the broader 148 notification
  campaign retained twelve `UiAutomationService ... already registered` failures
  and twelve empty XML files despite an exact owned card. Empty output is an
  unavailable observation, not evidence that the card is absent. Root's
  [scoped A/B/A ownership comparison](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-notifications-android-02/diagnosis/owned-appium-cli-exclusivity-aba.json)
  records CLI failure/no XML while an owned Appium session exists, then success
  and a valid 120-node dump after deleting only that session. Retire only the
  owned competing session before handing UI ownership to a CLI campaign; do not
  run both drivers together. The [restoration audit](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-notifications-android-02/independent-restoration-review/review.json)
  keeps the repeated card-tap cleanup failure separate from subsequent successful
  app-state/AppOp/final card-channel checks and exact guard restoration. Preserve
  that failed campaign; its A6 replay does not certify warm FCM delivery. Use
  Appium for its UI actions/reads, and separate exact-call diagnostics/PCM from UI
  control.
  Identity export also precedes deferred live services. The local audio campaign
  must await both peers' existing exact-step, no-action `skip_snapshot` setup
  receipts before the first contact introduction. That preamble establishes that
  the setup consumer ran; it does not certify healthy relay transport. Require
  the expected skipped snapshot and check the original three-minute bound after
  every completion read and cleanup await. Keep failure diagnostics to closed
  progress fields, never raw setup identities/keys. The [two-file fixture proof](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/audio-setup-readiness/files.json)
  retains the causal delayed-consumer failure, 55 focused and 136 curated passes,
  and clean analysis. The [guarded main/campaign port](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/audio-setup-readiness/main-and-stage-port.json)
  remains separate from the frozen aggregate and does not assign the cause of
  the earlier actual caller dial failures.
  The third audio campaign still fails contact introduction after this barrier.
  The isolated local-relay fixture correction uses the existing targeted relay
  probe before the exact-receipt retry; it does not change production endpoint
  publication or treat identity export as transport readiness. Its
  [focused and preservation receipts](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/audio-contact-relay-repair/final-preservation-summary.json)
  retain 126 focused, 136 curated and 71 final preservation passes with overlap;
  the later [Audio04 device proof](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-audio-04/independent-proof-review/review.json)
  passes 27 assertions on stage `f2f75000…`, including actual native controls,
  production bidirectional RTP plus a separate exact Pion oracle, native cleanup
  and exact guard restoration. Earlier failed audio attempts remain unchanged;
  this is not decoded-PCM or physical-transducer proof.
  B13 must create two real notification-capable contenders. An ordinary live
  send can commit first, allowing the real custody store to suppress redundant
  provider notification. The
  [retained notifications03 diagnosis](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-notifications-android-03/independent-restoration-review/b13-diagnosis/diagnosis.json)
  records this ordering and the campaign FAIL; relay rows do not export a full
  message identity, so do not overstate row attribution. Background FCM staging
  plus generic relay success is also insufficient to release an unrelated send.
  The isolated fixture encrypts once, stores through the real paired sender,
  then requires the full staged message/sender/ciphertext tuple and actual FCM
  receipt before an exact nonce-bound, single-use release of the same wire.
  The receiver remains pinned through release. Its later stored/listener proof
  must identify a notify-capable live transport, rejecting silent inbox replay;
  original one-card/audible-channel/typed-suppression gates remain unchanged.
  Failed exact sender receipts now retain only fixed, allowlisted error and
  cleanup codes in the diagnostic-only host observation before retirement and
  app restoration. This does not relax live acknowledgement or custody gates;
  the original source042 sender failure had no retained code and its cause
  remains unproven (all-tests-y227gs8x/source042-android-payload-native).
  Cancellation retires only this action and preserves the original failure;
  held completion or cleanup cannot extend its original three-minute budget.
  [Seven-file host verification](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/notification-dual-path/final-wrapper/results.json)
  passes 150 tests; plain Dart scenario listing verifies that host protocol
  imports do not pull in Flutter. The fixture batch is [guard-ported](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/notification-dual-path/combined-port/main-port.json)
  to MAIN and the campaign checkout. Notifications04 and 06 each retain a
  passing B13 partial inside a failed whole campaign; Notifications05's failed
  stable-card sample was not retained, so its exact card/channel outcome remains
  unexplained. Failure-only snapshots add observation, not a product repair.
  The [current stage wrapper](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/notification-b13-scoped-probe/combined-port/stage-wrapper/results.json)
  passes 169 host tests with zero failures/skips; omitted checks remain NOT RUN.
  Notifications06 later [fails token-refresh setup](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-notifications-android-06/independent-final-review/review.json)
  with complete restoration. Two [real-coordinator host regressions](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/notification-token-startup-quiescence/freeze.json)
  reproduce valid startup/resume coalescing registering the latest token under
  `resume` while the fixture expects `token_refresh`. The corrected precondition
  requires one completed startup, no unmatched observed coordinator attempts,
  and an unchanged sequence for 500 ms within the original three-minute bound,
  including after-read checks. This is observed stability, not introspection of
  every pending await; the original exact `token_refresh` success, same-PID and
  no-relaunch gates remain required. The separately guarded
  [three-pair cold/B13 diagnostic](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-notification-b13-diagnostic-01/independent-final-review/review.json)
  fails on its first B13 leg after a passing cold leg, with complete restoration.
  Its retained failure snapshot shows two textual records with identical exact
  native-key, card-ID and primary-channel hashes, while the channel census stays
  one: the card parser counts the same native identity twice. This establishes
  a fixture-counting defect for this attempt, not Notifications05's unretained
  state or a production channel migration. The exact-native-key parser now
  deduplicates only identical complete identities; conflicting or incomplete
  records and all stable-card/deadline gates remain conservative. The
  [second diagnostic](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-notification-b13-diagnostic-02/independent-final-review/review.json)
  fails because silent inbox storage precedes the released live path; restoration
  completes, and its strict live discriminator correctly refuses a pass.
  Receiver FCM plus exact staged sender/message/ciphertext must authorize release
  before any SSH journal wait. Mandatory fresh relay corroboration then uses the
  captured qualifying receiver proof after validated same-wire live completion;
  staging cleanup cannot erase that proof. Both the two-minute receiver bound
  and original three-minute total bound are checked after awaited work. The
  [530-test curated result](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/notification-live-release-latency/validation/completion.json)
  and [guarded three-file port](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/notification-live-release-latency/port-preparation/guarded-port/receipt.json)
  verify this host fixture correction, not a new device pass or an exclusive SSH
  cause for the prior failure. Six separate proofs
  are required to complete this diagnostic. The
  [third diagnostic](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-notification-b13-diagnostic-03/independent-final-review/review.json)
  now retains all six: three cold/B13 pairs pass on the same original APK,
  including real live relay storage, one audible card and typed suppression.
  Every journal read follows acknowledged live completion; exact restoration
  and secure lock pass. This `DIAGNOSTIC_PASS` cannot substitute for a whole
  notification campaign PASS on final app source.
  Retained warm FCM/B11 evidence may satisfy a separately reviewed
  [provider-only prerequisite](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/wrapper-dispatch/sixth-provider-ready.json)
  for another campaign when exact staged-message/device/ciphertext binding is
  retained. Time-window relay success alone has no recipient attribution and
  the parent notification campaign remains FAIL.
  On debug 138, Appium's physical-origin Ringing → lock → normal private
  unlock → natural Ringing return → relock → remote Answer passed with
  Connected screenshots before/after eight-second bidirectional decoded PCM,
  exact owner retention, normal End, cleanup and secure lock. Retain the first
  Appium attempt's orchestration timeout separately; it sent no Answer or PCM.
  A later locked-incoming Cancel passed terminal/UI behavior, but its deferred
  resource read cannot establish a twenty-second cleanup deadline or exercise
  a late-admission race. See the [Appium follow-up evidence](../../.codex-test-logs/audio-call-beta-fixes-20260917/appium/138-appium-ringing-physical-02/appium-ui-connection-review.json)
  and [scenario boundaries](audio-call-beta-scenarios.md). These checks do not
  establish the cause of the original 137 failures or physical audibility.
  Notification presence or UI XML alone does not prove a visible incoming-call
  screen. On the available API 37 Pixel 6/emulator pair, baseline debug
  `1.0.1(122)` showed foreground Answer/Decline, but received locked calls could
  leave `MainActivity` behind keyguard. The VC204 notification-count assertion
  does not establish this display boundary. Require a drawn app window, an
  untouched screenshot with visible native controls, secure-keyguard occlusion,
  and accessibility output containing only the intended call surface. Bind
  action results to the new diagnostic attempt; old conversation history can
  produce a false decline pass.
  The corrected native call surface grants lock-screen visibility only after
  mounting an opaque cover. Flutter must remain drawable through its first
  actual frame: hiding it earlier stalls the shared window's pre-draw gate.
  After that draw, hide its native ancestor; already-rendered activities can
  hide it immediately. Accessibility importance alone is insufficient for
  uncompressed framework queries or cached virtual nodes. Restore visibility
  and focus only when the covered window stops or the phone unlocks. Qualified
  node/call startup must not await a rendered home frame; ancillary navigation
  work retains its home-route boundary.
  Native adapter detach must permit reattachment on the same engine while
  disposal and superseded owners remain invalidated. A queued Dart end after
  native Decline/End must acknowledge the exact retained terminal once cleanup
  completes; returning the “new terminal appended” flag instead falsely
  invalidated calling authority and revoked the endpoint. Unknown, ACK-retired
  and predecessor UUIDs remain rejected without affecting a successor.
  VC204 Dart-end expectations in outgoing, network-transition, process-recovery
  and repeated-cleanup phases must confirm this retained completed terminal; the
  exactly-one terminal event and duplicate remote/Telecom/audio no-op checks
  remain required.
  Debug `1.0.1(127)` with identical APK hashes on both targets passed a genuinely
  process-absent locked incoming Decline, a subsequent Answer with bidirectional
  RTP progress, native End, and another incoming Decline. Incoming and answered
  accessibility trees exposed only native call controls. Accepted controls
  persisted beyond the original ring TTL. Final checks found no pending native
  call file, active call service or app notification, and keyguard restored.
  The long-call diagnostic trace hit its per-call cap and omitted a cleanup
  event: preserve the initial harness assertion failure and use the retained
  terminal outcomes, both peers' raw cleanup-ready/Telecom removal evidence,
  subsequent-call success and final live state to establish cleanup.
  Evidence, exact candidate/configuration hashes, 258 passing native tests,
  focused startup checks and all earlier failed attempts/corrections are in
  `.codex-test-logs/android-incoming-fix-20260916T134938Z/`. Baseline evidence
  remains in `.codex-test-logs/android-incoming-ui-20260916T131536Z/`. A separate
  baseline provider-to-device ingress miss remains unexplained; do not classify
  every absent screen as a presentation defect. APP_BACKGROUND network blocking
  during fixture setup and explicit endpoint revocation after faulty cleanup
  are distinct observed failures. These checks establish neither audible audio
  quality nor signed-release behavior; broader unexecuted selections remain
  NOT RUN in the reports.
  Outgoing readiness must render cancellable **Connecting** on the first
  Flutter frame, including graph recovery, contact/endpoint lookup and
  permission checks. The local 30-second preflight deadline ends at canonical
  admission; it must not cancel an admitted call later. Duplicate taps share
  one pending request. Cancellation and replacement fence every asynchronous
  continuation, including admitted signaling/native registration; terminal
  events can interrupt outgoing preparation. Late native adoption must reject
  the canceled session without revoking a successor's calling authority.
  Widget/coordinator/adapter regressions cover these races and preserve a
  schema-valid first-frame timing event (`outgoing_preparing`, `durationMs`).
  Two production-graph regressions now isolate the previously untested
  preflight native-reconciliation wait and final issued-wake authority read
  after endpoint resolution. Each proves the exact operation is pending,
  cancels the unadmitted request, releases the operation, and observes no new
  session, native outgoing registration or invite. A distinct control request
  then admits with one matching native registration and invite identity.
  Native reconciliation uses the real Android adapter with a retained previous
  terminal acknowledgement; it does not substitute a generic delay. The
  [reviewed two-boundary receipt](../../.codex-test-logs/android-audio-beta-20260916/cancellation-boundaries-137/ready.json)
  and [independent review](../../.codex-test-logs/android-audio-beta-20260916/cancellation-boundaries-137/root-review.json)
  bind the complete116-test file, bootstrap6 and signaling438 passes to
  unchanged production source. Initial fixture-key assertion failures remain
  preserved; counts overlap and broader selected checks remain incomplete.
  Android Back during the local unadmitted preflight is a cancellation input.
  After canonical admission, ConversationWired permits route Back and the
  global outgoing overlay exposes explicit Cancel; it has no Back-cancel
  binding. Setup navigation tests must distinguish a canceled attempt from a
  continuing exact call with reachable controls after return, and must never
  attribute an explicit later Cancel to Back. The original137 Connecting/Back
  helper's must-cancel assertion failed while the call continued ringing;
  its absent post-Back pixels cannot establish which route was displayed.
  Microphone preflight denial has a distinct `microphoneDenied` start result
  and displays **Microphone permission is needed to make calls.** before
  canonical admission. Denied and permanently denied share this feedback;
  the existing permission request occurs once. Cancellation still wins over
  a late permission result, while permission-adapter exceptions retain generic
  failure feedback. The [causal source receipt](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate140-source/microphone-feedback/summary.json)
  covers the real composition and ConversationWired path, not an OS permission
  dialog or a candidate's device behavior.
  Provider wake acceptance establishes custody only. Caller **Ringing** and
  ringback require authenticated remote ringing; a recipient may answer while
  the caller still shows Connecting. The earlier focused affected-calls receipt
  (935 passing tests), initial failures and corrections remain under
  `.codex-test-logs/android-outgoing-ux-20260916/`; that snapshot does not certify
  subsequent source changes or device timing.
  For killed-app Android call proof, compare the pinned callee's wall clock with
  the caller/host before diagnosing a missing worker. On 2026-09-29,
  `emulator-5556` lagged the host and USB Pixel by about 81 seconds: FCM started
  the app process, but `CALL_ANDROID_WAKE_PARSE` rejected the call as
  `too_far_future` before admission. The emulator's automatic time detector
  preferred a stale telephony suggestion over a fresh network suggestion;
  correcting its telephony time restored native admission and named full-screen
  presentation. The [R2-9 handoff](../../artifacts/beta-20260927/R2-9_ANDROID_KILLED_LOCKED_CALL_HANDOFF.md)
  records the raw device receipts and the remaining late-presentation and
  caller-Ringing limitations. A dispatched relay wake alone is not evidence
  that Android accepted the wake. Keep the callee process absent, `stopped=false`,
  and the screen asleep for more than 30 seconds before each exact locked-call
  attempt: immediate-after-lock calls presented in 3–26 seconds, but the
  original debug APK presented an exact-idle call only after the caller's
  30-second timeout. Fixed-shape Dart step timings showed cumulative process,
  worker, database/identity, and native-presentation delay, rather than one
  indefinitely blocked Dart step. The profile and non-debuggable release-mode
  APKs also had variable late presentation; one release attempt finished its
  worker before Dart started the network node, while another reached native
  presentation in under one second after Android process start. Neither build
  produced a verified connected Answer. Do not count fast
  immediate-after-lock calls toward the R2-9 3/3 exact-idle pass condition;
  the linked handoff retains the raw timestamps and build identities.
  A later non-wiping cold start of the **emulator process**, using the same
  installed R28 APK, restored Android Appium and produced three consecutive
  killed/locked calls after at least 35 seconds idle: native presentation in
  1.790–2.459 seconds after process start, Answer controls found in 9.708–10.766
  seconds after caller tap, and both iPhone 15 simulator and Android Connected.
  A fourth call presented in 1.695 seconds with Android automation disconnected;
  the iPhone showed Ringing before automation reattached. This supersedes the
  earlier W1 failure verdict only for that recovered baseline, not current-source
  or signed-candidate validation. The cause remains unproven; NFC/UWB service
  crashes persisted after restart. Check the app PID **after** `am kill` and
  again before dialing: a remaining process invalidates killed-app evidence.
  See the handoff's emulator recovery section and ignored `coldboot-recovery/`
  receipts for exact conditions, connected-state evidence, and the late Answer
  on the fourth control (not a connected-call pass).
  The later quiet-Mac R2-9 run passed W1 6/6, but W3 still lagged native
  presentation by 6.3–8.8 seconds. Its L2a logs show native `PRESENTED` at
  18:17:31.361, a foreground signaling start refused at 18:17:34.022 because
  P2P was not started, P2P core ready at 18:17:35.383, and authenticated
  `ringing` send attempted at 18:17:37.228. The current startup change keeps
  that start attempt waiting for the P2P ready event, with an eight-second
  bound; its focused causal test, affected-calls and call-signaling lanes pass
  under Flutter 3.47.2. The first candidate still showed `Ringing` 6.1 s after
  native presentation on a killed, locked emulator: headless P2P was ready
  before presentation, while foreground startup delayed the reply. The next
  candidate sends authenticated `ringing` from a separate headless run after
  presentation, verifying the exact live native descriptor and leaving the
  mailbox invite for foreground adoption. Two clock-aligned killed/locked
  runs first observed caller `Ringing` 3.2 s after native presentation, with
  about 0.43 s Appium polling; a third showed `Ringing` but its emulator clock
  jumped, so no precise native-to-caller delta is claimed. One clean headless
  run reached direct custody; another reached mailbox custody after direct
  delivery was unacknowledged. A fourth killed/locked call connected after
  Appium tapped the full-screen Answer control, and both peers showed
  Connected. This is W3 evidence on emulator-5554 and iPhone 15 simulator;
  physical Android and busy-Mac timing remain unmeasured. The original R28
  APK, app-data inode, and full-screen permission were restored. The
  focused 48 Dart tests, Flutter analysis, and Android call worker's 35 JVM
  tests passed. The affected-calls, android-call-native, and final
  call-signaling lanes passed; the latter now includes the core headless
  admission test in the selection manifest. The complete shared-tree
  selection remains BLOCKED because unrelated checks were not run. The
  explicit-base local selection includes unrelated dirty-tree checks left
  NOT RUN; see `.codex-test-logs/r29-w3-startup-20260929/` and the R2-9
  handoff for first-attempt and follow-up artifacts.
  The R2-9 headless `ringing` reply exposed an R2-10 killed-app Decline
  regression: ringing and decline both signed sender sequence 1, so the caller
  admitted ringing and rejected the later decline as non-monotonic. The
  [R2-10 handoff](../../artifacts/beta-20260927/R2-10_ANDROID_KILLED_APP_DECLINE_DROPPED_HANDOFF.md)
  preserves the original 3/3 failures and the subsequent fix. Headless decline
  now signs sequence 2. Its causal test sends actual ringing and decline
  replies into the caller replay store and also checks decline without prior
  ringing; it failed before the fix and passed after. Both headless reply tests
  are in the mandatory `call-signaling` selection. On debug APK
  `1.0.0-06d5ab570.r210` (SHA-256 beginning `0383e1661cb5`), Appium-driven
  Pixel_7a emulator to iPhone 15 simulator proof passed killed-app notification
  Decline 3/3 (caller declined in 1.81–2.46 s), killed + locked full-screen
  Decline, killed + locked Answer 3/3, K1, B1, D1, L1 and F1. K1 and two L2
  native-presentation-to-caller-Ringing intervals were 1.99–2.64 s. Caller
  cancellation and no-answer timeout cleared Android's incoming UI. Two
  unlocked and one locked setup calls timed out before Appium could tap
  Decline; do not count them as app failures or as successful decline trials.
  Focused tests, `affected-calls`, and the updated `call-signaling` lane passed;
  unrelated selected checks remain NOT RUN in the shared-tree wrapper report.
  See `.codex-test-logs/r2-10-device/`,
  `.codex-test-logs/r2-10-decline-checks/`, and
  `.codex-test-logs/r2-10-final-signaling/`. This is debug emulator/simulator
  evidence, not signed-release or physical-Android evidence. At the user's
  explicit request, the fixed APK remains installed on `emulator-5556` with
  its app data and full-screen access retained.
  Locked-call name/avatar/theme/state are an ephemeral display-only projection
  bound to the already authenticated native call. Push payloads cannot supply
  display authority, and metadata is not persisted. Native audio activation
  alone must remain Connecting; canonical connection state owns Connected and
  elapsed time. Mute/speaker availability and actions use existing call/audio
  owners, while the opaque first-draw and hidden-Flutter privacy boundary
  remains intact. An ordinary app launch relinquishes the locked surface; an
  explicit ongoing-notification tap can reopen only the exact accepted incoming
  call, without Answer replay or automatic full-screen presentation. Stale
  native IDs cannot reopen or control a successor.
  Reopening the same authenticated call before `onStop` may reuse a retired
  native view. Rendering must restore its parent action row as well as its
  individual controls; ringing and accepted-call regressions preserve exact
  action identity and prevent repeated Answer. A retained Android TextView
  stores pixel size after SP conversion and does not reapply it when fontScale
  changes. The native cover reapplies its label/caption SP sizes on configuration
  changes, using Android's current conversion, including nonlinear scaling.
  The same-instance resize/restore regression first failed on all four tested
  API levels; `font-scale-causal-red-results/` and
  `font-scale-regression-green-results/` retain that evidence under the beta
  campaign root. Build134's `134-visual-variants/native-font-measurement.json`
  verifies actual resizing on the same retained native view, with readable
  controls and exact setting restoration. Nonlinear Android scaling means the
  caller name need not grow by the same factor as smaller captions; wrapped
  labels require screenshot inspection alongside measured glyph bounds.
  Actual Light appearance requires the app's Background → Signal preference;
  changing Android night mode alone leaves the app's other background choices
  dark. The first Light native run exposed white system status icons against
  cream despite readable call controls. Native icon appearance must follow the
  opaque cover while it is visible and restore the prior appearance on removal,
  preserving unrelated window flags and the terminal-cover privacy interval.
  Candidate135 applied both light-status appearance flags, but actual locked
  Light screenshots still showed white status icons on cream. Requested window
  flags alone are not contrast evidence; icon ownership was not proven. A
  contrast region must use the actual status-bar inset and cover position,
  without a guessed height or painting into the Light body/navigation region.
  Candidate136 cold/warm Light incoming/active screenshots verify the actual 128px
  dark status inset, legible white icons and retained cream body/dark navigation
  handle. The visual review is separate from the passing digital-audio and
  cleanup result; the original preference and secure keyguard were restored.
  Cold native ringing screenshots also exposed a generic identity/avatar until
  foreground projection arrived. Authenticated headless admission already has
  the sender and local contact record; display fields must cross that existing
  bounded completion after cleanup and exact identity/expiry checks. They are
  optional volatile presentation data, never admission authority or push data.
  Candidate135 cold Dark and Light screenshots show authenticated caller name
  and avatar at initial ringing; the Light fixture rechecks PID absence and
  non-force-stopped package state immediately before Start. Retain that
  precondition after all readiness operations, since those operations can
  otherwise invalidate a prior process-absence check.
  An actionable accessibility tree and `HAS_DRAWN` do not prove visible call
  pixels. The beta campaign reproduced a black ordinary launch with no
  `FLAG_SECURE` and a visible full-screen Android starting surface above the
  app. Install the API31 splash-exit listener before Flutter's `onCreate` for
  ordinary launches as well as call restores; removing the OS-delivered splash
  grants no locked-call authority. A controlled incoming trace refuted late
  registration for that path: its listener ran and its remaining system window
  record was hidden. WindowManager's residual starting-window count alone is
  therefore not a failure oracle; correlate actual pixels and SurfaceFlinger
  visibility. Candidate133 passed two consecutive cold incoming calls with
  rendered controls and complete cleanup. The separate 72-second emulator
  startup delay recovered in the same process, with skipped-frame and database
  lock warnings but no retained visible splash after its callback. Preserve it
  as a setup failure, without inferring a single underlying cause. See the
  [beta findings](audio-call-beta-findings.md) for exact artifact/run provenance.
  Android CallStyle can render the caller-person label instead of the builder's
  content title. R2-6's native notification test first failed on API 28, 33,
  and 34 with the generic caller label, then passed when the factory read the
  authenticated, in-memory call presentation for both incoming and ongoing
  notifications. The native bridge test covers refreshing a ringing
  notification when the contact name arrives after the first post; an unknown
  caller still uses the generic label. These JVM tests establish payload and
  ownership wiring, not actual SystemUI rendering. The later R2-6 beta showed
  the actual Android ringing notification stayed generic for 12 seconds and
  acquired the name only after Answer. Foreground projection awaited avatar
  rendering before sending metadata, and the Android adapter dropped a name
  sent before the native call bound. The revised projection sends the name
  before the avatar, maps `incomingValidating` to the native `preparing` state,
  and the adapter replays the latest early presentation after successful native
  binding. Focused Dart tests cover both races; a privacy-safe native log line
  records acceptance and refresh without the name. The
  [second R2-6 beta](../../artifacts/beta-20260927/BETA_REPORT_R2.md) confirmed
  that the real name reached Android while ringing (`named=true` six times),
  but all 60 presentation updates reported `refreshed=false`; SystemUI showed
  the Flutter `Unknown contact` placeholder until Answer. The pending-journal
  refresh check excluded the adopted call after its ADOPTED acknowledgement,
  although the controller still accepted its metadata. Refresh must use the
  exact active incoming lifecycle, including adopted custody, and unresolved
  Flutter placeholder text must stay out of native metadata. The adopted-call
  bridge regression passed with the native lifecycle and notification factory
  tests (105/105), and the focused Flutter projection tests passed (96/96).
  A foreground call from iPhone 15 simulator
  `FB7E3D88-B92D-4028-9CA7-A9CD9D34615F` to Pixel 7a emulator
  `emulator-5556` then showed `Beta iPhone` in the Android notification while
  it was still ringing:
  `dumpsys notification` reported CallStyle `callType=1` and title `Beta iPhone`,
  and the native log recorded `named=true refreshed=true` followed by
  `refreshed=false` for unchanged metadata. The
  [Appium screenshot](../../.codex-test-logs/r2-6-late-name/ringing-notification-appium.png)
  and [native log](../../.codex-test-logs/r2-6-late-name/android-logcat-proof.txt)
  preserve that proof. It used a debug APK with voice-call Dart defines and
  `enableAndroidNativeCalls=true`, SHA-256
  `e181255896018f603837ef5ef6e0eae3bff32101b3bf7503bd58925ef1a7c548`.
  Background incoming delivery remains unverified because the known relay
  wake-up failure can prevent the call reaching Android.

  The [R2-8 background-call handoff](../../artifacts/beta-20260927/R2-8_ANDROID_BACKGROUND_CALLS_HANDOFF.md)
  records three beta runs where the first Android call wake failed, the relay
  then sent no further wake, and the foreground app reported an unchanged call
  token. A read-only production check on 2026-09-28 found the relay active with
  `RELAY_SERVER_IP=13.60.250.19`, while `mknoun.xyz` resolved to
  `51.21.194.144`. The relay's Firebase service account and the Android app
  both identified project `mknoon-c6e62`, so the configured projects matched.
  The journal recorded `wake=failed` without the provider category. After the
  Pixel restarted, an exact read-only encoded-key query found its
  `standard_call` record, and a Firebase `validate_only` call with that record's
  token returned HTTP 404, `NOT_FOUND`, structured `UNREGISTERED`, and
  `NotRegistered` message class without delivering a push. The
  [redacted receipt](../../.codex-test-logs/r28-background-calls/fcm-validate-only.log)
  is the causal provider evidence: the relay's invalid-token classification is
  correct, while re-publishing the same token cannot restore reachability.
  The client must replace its cached FCM token and publish the replacement to
  both chat and call routes. The 2026-09-29 implementation shares a serialized
  first-read delete/get across chat and call and republishes the call token on
  start, resume, and advertisement. Host tests cover both behaviors. A second
  `validate_only` provider probe against the newly registered token returned
  HTTP 200 and `validate_only_accepted=True` without delivering a push; the
  [redacted receipt](../../.codex-test-logs/r28-background-calls/fcm-validate-only-final-apk.log)
  retains that result. After explicit
  approval, the production relay IP was corrected to `51.21.194.144`. The
  first restart's 20-second health deadline was shorter than the observed
  roughly 37-second startup and rolled back to the saved environment; that
  restored service returned HTTP 200 on metrics. A retry with a 90-second
  deadline completed, and a separate read-only check found the service active,
  metrics HTTP 200, TCP 4005 open, and two new IPv4 announcement lines with no
  old IPv4 announcement. The [restart timeline](../../.codex-test-logs/r28-background-calls/relay-ip-service-events.txt)
  retains the rolled-back first attempt and successful retry. Both Android
  devices subsequently logged the new IPv4 on fresh app start without the old
  one in the circuit-address list.

  The final Android proof APK, SHA-256
  `f903db1ba37d38159ca2dfc22531e6e534c4fb4bf15c467896ede092e134e0a2`,
  used Flutter 3.47.2, Android arm64 debug, release voice-call defines,
  production FCM, E2E mode, and native Android calls. On USB Pixel 6
  `21071FDF600CSC` and emulator `emulator-5556`, Appium MCP proved foreground,
  warm-background (over 30 seconds), repeated same-process background, and
  killed-process (`stopped=false`) calls connected after Android notification
  answer. The killed-process caller recorded `wake=dispatched`. A first
  killed-process answer missed the 30-second caller deadline during lengthy UI
  inspection; the faster repeat connected, and the first logs remain preserved.
  The warm-background notification originally said `MKnoon caller`; the final
  authenticated-name update showed the saved contact `puxel`, and iPhone →
  Android calls showed `Beta iPhone`. The
  [live evidence](../../.codex-test-logs/r28-background-calls/live-device-evidence.md)
  records the exact targets, screenshots, first attempts, and build identity.
  Android → foreground iPhone also connected. An extra Android → backgrounded
  iPhone call failed after the iPhone verified the invite because presentation
  returned `presented=false`. The [installed iOS build's defines](../../artifacts/beta-20260928/build-r2-7/defines_ios.txt)
  set `VOICE_CALL_IOS_NATIVE_ENABLED=false`, so this attempt cannot establish
  native iOS background-callee parity. The [R2-8 handoff](../../artifacts/beta-20260927/R2-8_ANDROID_BACKGROUND_CALLS_HANDOFF.md)
  distinguishes the Android passes from that open iOS parity leg. Focused
  Flutter call (243), adapter (67), and iOS preservation (56) tests passed;
  the Android native lifecycle test and full native lane built successfully.
  The explicit-base change selector's affected-calls, affected-push, and
  call-signaling lanes passed. Its overall result was `BLOCKED` because the
  already dirty shared working tree selected many other required checks that
  were not run; do not treat the subset as full repository validation.

  An earlier selected affected-calls host lane passed 1,200
  tests when run alone. Its first overlapping attempt retained four failures
  caused by a missing macOS SQLite native asset; the asset was present before
  the passing sequential run. Raw attempts are retained in ignored
  `.codex-test-logs/r2-5-affected-calls*.log`. The change wrapper also left
  `android-call-native` unrun because another campaign owned the shared
  native-build lease; focused bridge and notification factory JVM tests passed
  directly. A real notification test
  must bind the unique designated app
  row and current invitation, stabilize its action bounds, and re-resolve them
  immediately before input. A screenshot and an Answer coordinate do not prove
  Answer delivery: candidate136 physical03 actually delivered OPEN_INCOMING and
  timed out; physical04 delivered Answer, connected and passed fresh decoded
  PCM after stable targeting. Preserve both raw results. Restore only a shade
  opened by the helper. A retained NotificationShade focus blocked the intervening
  no-attempt fixture retry even while MainActivity was resumed; that was a
  harness setup failure, not a splash or call-delivery failure.
  The physical target can use headerless_view_row/status_bar_latest_event_content
  under expandableNotificationRow without a separate app-name header. Require
  that observed structure, unique caller/status/action markers and the exact
  current app notification; reject conflicting explicit headers and duplicates.
  On the emulator, the inner notification content can be nonclickable while
  its enclosing exact SystemUI expandableNotificationRow owns the content
  action. Candidate137's first cold attempt retained this actual XML and failed
  before input. A narrow ancestor-owner correction reached real openIncoming
  on the next attempt; it did not establish Answer or media. Flutter incoming
  semantics may combine the exact peer, Incoming call, Decline and Answer as
  newline-delimited content-desc text while retaining standalone actionable
  buttons. An identity/status gate must recognize that actual shape without
  accepting an arbitrary substring or treating label text as an action. The
  second cold attempt omitted rejected live trees, so its exact surface remains
  unobserved despite the independently reproduced host gate mismatch. Retain
  these limitations in the [beta findings](audio-call-beta-findings.md).
  Cleanup timing must distinguish a late admission placeholder from retained
  ringing/audio. A new FCM wake163ms after native cleanup created admission_v1;
  its worker finished in925ms, but the unchanged foreground service has a30s
  backstop. The helper's25s timeout sampled the placeholder at age23.772s;
  later resources were absent. Preserve that first timeout and avoid labeling
  the graph_not_owner reason alone as a stuck worker or known lease owner.
  The 137 Answer/Cancel records also show successful terminal cleanup followed
  by a fresh admission task, quick graph_not_owner completion, and a new
  admission service still present at the twenty-second deadline. This
  ordinary-admission release policy predates the handover changes; only the
  decline-reply worker mode explicitly releases that placeholder. The existing
  STOP operation checks call UUID, not admission mode or service instance, so
  applying it to every completed worker could stop a same-call service that
  has upgraded to ringing or active. An earlier-release design needs causal
  ownership/upgrade preservation tests. Later clear readbacks do not establish
  the actual thirty-second timeout callback. Simultaneous-End cases retained
  the same service class but lacked the late-task sequence; do not transfer
  precise causality from the Answer/Cancel cases to those archives.
  The [source diagnosis](../../.codex-test-logs/android-audio-beta-20260916/137-admission-cleanup-tail-source-diagnosis.json)
  retains original pre-task127 provenance, exact event joins and the missing
  same-call upgrade/instance fences in the then-current generic release operation.
  The source repair uses the WorkRequest UUID as a separate admission owner.
  Worker completion may retire only the matching call/owner while the service
  remains in admission mode; ringing, active and successor work are preserved.
  Unresolved foreground-owned admission must retain its prestarted service
  unless an exact native terminal tombstone exists: `graph_not_owner` can
  precede foreground presentation and is not proof that the wake is obsolete.
  Canonical active audio can upgrade the same admission directly, without an
  intervening ringing command. The native service/worker tests exercise these
  boundaries, including deferred completion followed by later presentation.
  A terminal tombstone must outlive delayed wake/admission work even when the
  original invitation has expired. Retain the exact UUID until the later of
  invitation expiry and terminal observation plus75s (45s wake horizon plus
  the30s admission backstop), with a32-entry cap. This retention does not extend
  invitation or admission validity, and does not weaken the exact WorkRequest,
  call UUID and admission-mode release guards. The [retention regressions](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate140-source/terminal-retention/summary.json)
  preserve ringing/active upgrades and successors; their host/native evidence
  does not certify cleanup on an untested APK.
  A later admission wake for a UUID with a retained authenticated terminal
  must retire its admission placeholder without waiting for worker completion.
  The service first satisfies Android's foreground-start obligation, then
  releases only the current matching WorkRequest owner in admission mode.
  Explicit decline-reply work keeps its custody; unknown/error terminal reads,
  other calls, successor work and ringing/audio upgrades remain protected.
  The [early terminal-release regressions](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate142-source/early-terminal-admission/summary.json)
  reproduce delayed-worker cleanup and preserve those ownership boundaries.
  This source proof does not turn a prior twenty-second device timeout into
  a pass or establish prompt cleanup on an untested candidate.
  A foreground-owned wake can still leave admission without any native journal:
  the 145 receiver-offline-through-expiry failure records exact-trace
  `deferred / graph_not_owner`, incomplete admission persistence, an owner-matched
  release refusal and the 30.001 s backstop. Later-drained persisted event timestamps
  establish that sequence; a late capture does not certify prompt resource cleanup.
  See the [retained source review](../../.codex-test-logs/audio-call-beta-rest-20260917/appium/145-net02-physical-01/native-admission-source-review.json).
  Candidate 146 adds a bounded process-only original call/WorkRequest/wake/expiry
  token before foreground delivery. Only a cryptographically authenticated remote
  terminal bound to the current account/issued wake grant, followed by the exact
  mailbox ACK, may commit it. Failed ACK retries retain only the bounded exact-frame
  proof and original token; shutdown and changed authority invalidate it. Empty,
  arbitrary expired and deferred mailbox results never gain release authority.
  Native capture and commit use strict read-only protected-journal observation:
  unreadable storage, live ownership or pending cleanup refuse settlement without
  snapshot receipt pruning or journal mutation. Current token/mode, successor and
  decline fences apply; START still foregrounds before honoring a pre-start receipt.
  Exact successful commits also use the existing bounded terminal tombstone so an
  already-ACKed duplicate wake cannot recreate the placeholder. New bridge work runs
  off-main behind the registration executor to avoid blocking older Telecom callbacks.
  [Dart 304 focused checks](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate146-source/foreground-admission/summary.json),
  the [complete 420-test native wrapper](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate146-source/native-settlement/wrapper-run/results.json)
  and [73-method headless tail](../../.codex-test-logs/audio-call-beta-rest-20260917/final146-native374/completion.json) preserve
  these boundaries. The exact native wrapper includes compilation; subsets leave
  omitted IDs NOT RUN. The first 146 expiry assertion remains FAIL: its admission
  sample preceded exact-owner release by 263 ms, while later source-bound native
  records and fixed FLOW prove authenticated terminate/ACK/commit and release 957 ms
  after observed ingress ([qualified receipt](../../.codex-test-logs/audio-call-beta-rest-20260917/appium/146-net02-physical-01/source-settlement-review.json)).
  A prospective never-presented receiver gate distinguishes mandatory foreground
  admission from incoming call ownership: same PID, exact trace/run/one work,
  authenticated terminal ACK and applied stop within the original earlier observed
  push/START+4 s; async push append must never move the bound later. This is
  retained processing evidence, not an exported FCM callback/network arrival. No
  ringing/audio/journal, four stable clear seconds and bounded proof export. Caller
  terminal+20 s and fresh PCM control remain required. Its 46 causal helper tests
  retain the 145 thirty-second rejection; no retrospective case PASS is granted.
  The 145 foreground mailbox subtype was not retained, so that historical cause
  remains narrower than the verified 146 terminal-settlement sequence.
  The separate prospective 146 [physical-origin](../../.codex-test-logs/audio-call-beta-rest-20260917/appium/146-net02-physical-03/independent-evidence-review.json)
  and [reverse](../../.codex-test-logs/audio-call-beta-rest-20260917/appium/146-net02-emulator-01/independent-evidence-review.json)
  cases pass exact release within 2.051 s/1.007 s, original caller cleanup, stable
  resource clearance and distinct eight-second PCM/End controls. The first 146
  assertion failures remain retained; these named replays do not relabel them.
  A separate Telecom dependency requires provider callbacks to return before
  a nested `CallControlScope.disconnect` can finish. The actual 146 cellular
  Answer failure records `onSetInactive`, a nested disconnect and Telecom's
  five-second callback timeout; this is distinct from a UI actor budget or
  the earlier leaked synthetic call. Candidate 147 keeps the existing bounded
  durable-terminal ACK, then queues the exact captured session's disconnect
  on the process-owned scope without awaiting or joining it inside
  `onSetInactive`; rejected `onSetActive` uses the same rule. Queue acceptance
  is not provider-release completion. Exact-session local markers, deduplication,
  cancellation and registration retirement preserve replacement ownership;
  diagnostics distinguish completion/failure/retirement. The one-attempt
  750-ms provider await policy remains; synchronous Binder work can outlast
  coroutine cancellation off the callback, so no strict physical-release time
  is inferred from that timeout alone. Two causal serialized-provider failures
  and [433 passing native tests in 28 suites](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate147-source/native-callback/full-green-counts.json)
  verify the repair and preservation rules in the isolated source tree. The
  [exact main 147 native wrapper](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate147-source/main-native-results.json)
  independently confirms 433 tests in 28 classes, with no failures or skips;
  its omitted IDs remain NOT RUN. These counts certify JVM assertions, not
  new Go/Flutter execution or device acceptance. The
  [146-to-147 dependency audit](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate147-source/146-to147-dependency-bridge.json)
  confirms three native-file changes, unchanged Dart/configuration inputs and
  21 passing source-inspection sentinels; the first enumeration-guard failure
  remains retained. The first installed 147 focus
  attempts failed before transport was restored: the first
  actor case, post-install control and ordinary-relaunch control all failed
  preflight before any native callback. The relaunch receipt proves PID
  absence and a fresh process on both targets. The
  [boundary review](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate147-source/startup-unavailable/readiness-boundary-review.json)
  distinguishes responsive local node status from token-publication timeouts
  and relay-connect warm failures; exact network cause remains unassigned.
  Host TLS/DNS observations do not establish call-protocol readiness;
  [independent shipped-transport probes](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate147-source/startup-unavailable/probe/results.jsonl)
  also fail authenticated WSS/QUIC connection. Fresh resumed probes now pass
  both transports; this does not rewrite those first failures or assign a
  server root cause. The [qualified installed 147 AUDIO05 ledger](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate147-source/audio05-review/147-qualified-audio05-ledger.json)
  verifies both caller directions, with the emulator answering its owned
  synthetic managed call. Actual Phone Answer, two exact ACTIVE samples,
  sole-source PCM/current process, exact successful onSetInactive callback
  and both connected local-user terminals qualify the intentional end.
  A generic completed terminal is still rejected. Resource/focus/UI retirement
  completes within twenty seconds of Answer, followed by a distinct fresh
  eight-second PCM call. Callback reads use the observed device epoch start;
  global count-limited log tails can omit those lines before tag filtering.
  Android transient ANSWERED is pending only; it never substitutes for ACTIVE
  or extends the original four/eight-second actor bounds. Raw 147 attempts
  02–05 and the first 146 callback-timeout failure stay retained.
  Historical 137 cleanup failures remain separate from source verification.
  The [repair change selection](../../.codex-test-logs/audio-call-beta-fixes-20260917-checks-final/results.json)
  passes affected calls (965) and the complete native runner (356 JUnit cases),
  plus signaling, notifications, startup, bootstrap and diagnostics. Existing
  call-directory and native call-package selectors include these regressions;
  no mapping was narrowed. That earlier invocation passed nine check IDs and
  omitted 55 selected IDs. Those historical subset counts do not describe the
  frozen 148 aggregate (`5f953f03…`) or its 84-ID selection. The prior separately
  validated audio fixture port (`0f0b0897…`) has an 85-ID plan. Concurrent MAIN
  wrapper/test/mapping changes and the new isolated fixture batch retain their
  own identities until guarded integration; no final combined identity is
  inferred. The
  [current coverage ledger](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-retry02-validation-ledger.json)
  records 17,024 PASS, 13 SKIP and zero FAIL across all 1,496 planned files,
  including all 1,331 distinct paths in 68 Flutter selectors, with source and
  configuration unchanged during execution. Literal wrapper execution and
  dependency-equivalent older receipts remain separately identified; file
  overlap never converts an omitted wrapper ID into PASS. Thirteen Dart and two
  historical Go skipped branches remain unexecuted. Actual broader
  [reconnect](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-reconnect-01/results.json) and
  [group-mute](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-device-group-mute-01/results.json) wrappers and guards pass;
  group mute covers all three required scenarios. The later Audio04 wrapper and
  guard also pass. The later direct-media custody campaign passes its four
  capability groups. Android notification campaign07 passes nine scenarios,
  with its unavailable UID permission override explicitly N/A; the receipt
  remains bound to its actual source and APK. Group-media campaign06 remains
  FAIL after both strict authority checks passed. Its isolated relay accepted
  three protected uploads, but no final transfer artifact or detailed endpoint
  failure was retained. The owned relay, reverse mappings and device state were
  restored. The [current source-aware ledger](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-current-validation-ledger.json)
  preserves these actual attempts separately from the frozen host aggregate.
  Physical iOS notification is N/A without an eligible USB target.
  The interrupted first 148 aggregate stays FAIL, and later
  fixture edits retain separate scoped validation. The [primary device ledger](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/debug-evidence/primary-148-closure.json)
  separately closes both-direction installed history identity, exact call-channel
  restoration and near-expiry native Answer, each with distinct fresh PCM.
  Process-interruption tests must keep the interrupted source and fresh
  recovery call distinct. A passing recovery audio probe does not pass the
  source's cleanup deadline. Successful restoration can overwrite helper
  cleanup dumps; an unretained first-failure service mode stays unknown.
  Append later cleanup samples and preserve the original deadline and first
  timing failure instead of replacing them during error cleanup.
  An encrypted `pending_native_call_v1.bin` file establishes durable journal
  custody, not a live service or media owner. Existing Android startup paths
  in `MknoonCallAndroidRuntime.reconcilePersistedDescriptor` retire expired
  descriptors; `MknoonCallLifecycleController.reconcileAdoptedJournal` records
  provider loss for an adopted journal, and
  `settleUnconsumableTerminalBeforeAttach` settles its terminal record before
  fresh Flutter attachment. An adopted record recreated after process death
  must retain its exact `PROVIDER_REMOVED` terminal until acknowledgement;
  deleting it merely to satisfy a file-presence cleanup assertion would discard
  durable custody. The active microphone-revoke/process helpers may defer this
  file for the exact receiver/trace with a recorded earlier PID and empty
  own-process observations bracketing each resource sample. An alive restarted
  PID alone does not qualify. Candidate 144 adds a separate strict terminal
  outbox proof: two identical current protected-record snapshots, bound to the
  earlier verified PCM nonce/native-owner digest and the same restarted PID,
  must report JOURNAL/ADOPTED/PROVIDER_REMOVED, the exact terminal sequence,
  no live owner and no pending native cleanup. Foreground service, call
  notifications and current Telecom calls must also be absent. Wrong owner,
  successor, changed PID/record, active state and failed reads cannot qualify.
  Query and Telecom-read time count toward the original twenty-second deadline
  and four-second stable-clear observation; late first proof never resets it.
  After the UI
  observer joins and exact permission restoration completes, ordinary Appium
  activation must show a fresh app process, no stale call controls and fully
  clear resources before the distinct recovery call. The
  [causal helper regressions](../../.codex-test-logs/audio-call-beta-rest-20260917/appium/deferred-journal-summary.json)
  retain the original twenty-second live-resource bound and a separate bounded
  activation check; they change no production lifecycle behavior.
  The [144 observer/preservation tests](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate144-source/terminal-outbox/summary.json)
  pass 98 native cases; the [strict helper tests](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate144-source/terminal-outbox/helper-summary.json)
  pass 50 host cases. The debug-only, DUMP-protected receiver's `journal_snapshot`
  operation never creates a runtime, starts audio, publishes a PCM session,
  reconciles, acknowledges or deletes. Its store reader avoids normal snapshot's
  receipt pruning, rejects corrupt/unavailable records instead of reporting
  empty, refuses AtomicFile sidecars without recovering them, and uses only an
  existing keystore key. No identifiers, handles, keys or payloads are exported.
  These tests are not installed-device acceptance.
  The 148 `history_snapshot` observation binds a nonce-salted call/account/row
  digest to the already-open canonical database and current foreground/native
  owner. It neither opens storage nor writes/acknowledges history. Owner, account,
  graph and same-call terminal changes are checked after awaited reads; native
  reply time is an absolute five seconds. Stable row identity excludes read_at.
  [Both installed REL03 directions](audio-call-beta-scenarios.md#current-appium-repair-follow-up)
  prove zero exact rows while live, one added after End and the same row after
  actual process termination/PID absence and ordinary restart, followed by
  distinct fresh PCM controls. Native expiry observation is separately bounded
  to one current owner, sixteen events and ninety seconds. Collect its volatile
  synchronous native ordering before bulk diagnostic archives; a later archive
  timeout still fails and cannot extend the original cleanup deadline.
  The [143 physical-receiver revoke review](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate144-source/terminal-outbox/143-retrospective-review.json)
  finds an exact native `provider_reset` terminal commit before the failed
  cleanup samples, while an alive headless process retained the encrypted file
  without service or call notification. Later ordinary activation clears it.
  This retrospectively supports terminal custody, but does not supply the
  missing contemporaneous protected-record/Telecom observation; the original
  FAIL remains. No production cleanup or immediate terminal ACK was added.
  The [141 microphone-revoke failure](../../.codex-test-logs/audio-call-beta-rest-20260917/appium/141-sys01-revoke-emulator-01/result.json)
  retained a file after services and call notifications disappeared, but did
  not retain PID absence or decoded journal phase. Its original FAIL remains;
  the [separate ordinary-activation audit](../../.codex-test-logs/audio-call-beta-rest-20260917/appium/141-sys01-revoke-emulator-01-restoration-audit/result.json)
  later observed journal clearance and secure lock, without proving the
  interrupted source's original deadline or passing its missing PID gate.
  An early result's empty outcome list may be qualified by an exact terminal
  in its already-retained final archive, without rewriting the original result.
  Edge helpers can finish source/control audio and call-resource checks while
  leaving the phone unlocked. The 137 physical caller-offline row positively
  observed that inter-row lock failure; the following row later verified lock.
  Inspect an explicit lock command's result before starting the next row,
  and preserve workflow restoration separately from functional audio PASS.
  Notification app-op restoration needs the original raw output and operation
  scope. The 137 edge helper normalized `No operations` to `default`, discarding
  the separately reported effective default. Its emulator notification-denial
  setup and restoration assertions failed before a bound call; after scoped
  restoration the grant and every permission flag matched, but raw `allow`
  differed from saved normalized `default`. Since the initial raw output was
  not retained, exact literal mode restoration remains unproven. Preserve that
  failure and functional restoration separately; do not repeat a known
  unsupported mutation merely to obtain another control. The
  [retained classification](../../.codex-test-logs/android-audio-beta-20260916/137-sys02-notification-physical/failure-classification.json)
  records the original snapshot, scoped restore and final clear/locked state.
  Restored OS permission does not establish app notification registration:
  the137 final physical Settings capture reported failed device registration while
  the grant and flags match. No fresh delivery test followed, and the banner
  does not establish the cause of earlier readiness failures. The
  [final device audit](../../.codex-test-logs/android-audio-beta-20260916/137-final-device-audit/final-audit.json)
  keeps permission, registration readiness, resources and secure lock separate.
  Push registration must retain a bounded retry after initial binding lookup
  fails; leaving `_started` set after canceling that retry can strand readiness.
  Explicit Retry and resume refresh current OS permission even when a cached
  result exists. A newer refresh generation cannot be satisfied by an older
  in-flight grant or denial. Account cutover, disable and disposal fence both
  paths; automatic token/timer retries keep their existing no-reprompt policy.
  The [binding regression](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate140-source/push-recovery/audio-beta-push-binding-red.log),
  [permission regression](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate140-source/push-recovery/audio-beta-push-permission-red.log)
  and [focused verification](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate140-source/push-recovery/audio-beta-push-recovery-final.log)
  establish these source defects without assigning the137 banner or missing
  Start control to them. A visible existing recovery action and a failed
  harness readiness lookup also remain different observations.
  A visible registration warning can also be absent from the platform
  accessibility tree: a Navigator's route-level `BlockSemantics` swallowed the
  preceding app-shell banner in a real `MaterialApp(builder: ...)` composition.
  Keep a stable `Semantics(container: true)` boundary around the Navigator
  subtree so the warning and Retry remain reachable alongside pushed routes.
  The [active-tree regression and preservation checks](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate142-source/push-health-semantics/files.json)
  invoke Retry through semantics and preserve route state and navigation while
  warnings appear/disappear. With the real health surface inside the modal
  call layer, warning/Retry and private route controls remain inaccessible
  through the terminal notice and return only after dismissal. Widget finders
  or a raw-tree readiness result alone do not refute a visible warning.
  Isolated Android debug builds must carry the existing ignored
  `android/app/google-services.json` input. The Gradle debug path warns but
  still builds when it is absent; the plugin then generates no Firebase
  resources. The [presence-only build audit](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate143-source/firebase-readiness/missing-build-config.json)
  found that exact omission while a fresh 142 process reported failure to load
  `FirebaseOptions` from resources. Preserve the source-attempt failures, copy
  the existing configuration privately, and verify its hash plus generated
  resource/artifact inclusion without logging contents. A native call wake or
  notification alongside this failure does not prove the Dart default
  Firebase app initialized.
  Independently, best-effort startup initialization can fail while the
  registration coordinator is already reachable. Every registration attempt
  must establish readiness before subscribing to token refresh or requesting
  permission/tokens; false readiness remains transient and retryable rather
  than becoming permission denial. Concurrent startup and Retry share one
  initialization. The [causal readiness regressions](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate143-source/firebase-readiness/files.json)
  cover explicit/timer recovery, actual default-consumer `core/no-app`,
  no automatic re-prompt and late successful/failed initialization after
  disable, disposal or account cutover. This source repair does not replace
  the missing build input or establish successful registration on a new APK.
  Foreground startup can also overlap a headless recovery lease. The retained
  143 process failed before `runApp` on typed `lease_unavailable` while native
  authority reported ACTIVE/RECOVERY; later MAIN intents did not rerun the
  failed preparation. Candidate 144 waits only for that typed contention,
  polling native authority every 250 ms for at most 30 seconds, then exposes
  localized Retry on the same paused preparation. It never forces takeover or
  duplicates DB/composition work; native/headless denial rules remain unchanged.
  Shutdown cancels the wait/Retry, late grants retire before DB opening, and
  uncertain partial-open custody remains DRAINING. The [97 focused tests and
  bootstrap check](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate144-source/startup-lease/summary.json)
  verify these fences. The original startup failure remains retained. Later
  [144 revoke/restored controls](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate144-source/device-evidence-ledger.json)
  and [145 process restoration](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate145-source/process-evidence-ledger.json)
  plus actual terminal process relaunch/fresh calls verify installed ordinary
  recovery. They do not deliberately inject the exact lease-contention race;
  that scheduling boundary remains established by the causal source tests.
  Audio restoration must compare every retained stream/device index, including
  streams aliased to media. The 134 supported-slider test restored all eleven
  maps at its own cutoff; a later final audit found three physical speaker-index
  differences. One actual Media slider adjustment restored MUSIC 6 and
  ACCESSIBILITY 4, while aliased TTS remained 4 versus its original 5. The time
  and cause of that drift are unretained. Do not replace the original expected
  map or claim exact restoration from the visible Media value alone. The
  [scoped slider readback](../../.codex-test-logs/android-audio-beta-20260916/137-final-device-audit/physical-media-slider-step01.json)
  preserves this partial restoration; no supported independent TTS restore was
  established, and no further volume trial or hidden setter was used.
  Emulator `gsm list` returning only `OK` is not sufficient evidence that a
  synthetic cellular interruption was restored. In the
  [retained 143 fixture restoration](../../.codex-test-logs/audio-call-beta-rest-20260917/appium/143-cold-emulator-01/emulator-owned-cellular-fixture-restoration.json),
  the console was empty while Telecom's current `CallsManager.mCalls` still
  contained a managed SIM call in `RINGING`; canceling only the designated
  synthetic number cleared that native call in 449 ms. Keep the earlier failed
  cases and their false console-only restoration claims visible rather than
  rewriting them. Before injection, require an empty modem list and no managed
  or unrelated current Telecom call; only an explicitly app-owned self-managed
  call may remain as the source-call baseline. After any attempted injection,
  always cancel the exact owned fixture number even if the console omits it,
  then require both console and current native clearance. Unknown dump shapes
  or observation failures are not empty-state proof. The
  [causal helper checks](../../.codex-test-logs/audio-call-beta-rest-20260917/appium/cellular-telecom-cleanup-summary.json)
  retain the original console-only failure and the bounded cleanup regression.
  The eight-second watchdog starts restoration; its preliminary observations
  precede the separate four-second cancel/clear window, so it does not establish
  complete native cleanup within eight seconds of injection.
  The [scenario catalog](audio-call-beta-scenarios.md) retains these source,
  control and restoration boundaries with their exact evidence.
  An unlocked native-to-Flutter handoff exposed retained chat history and
  enabled background call/recording actions in the platform accessibility tree.
  The foreground modal call layer now blocks preceding semantics while keeping
  the translucent visual and existing focus exclusion. Actual-tree regressions
  invoke call controls through semantics, keep background actions hidden through
  the terminal notice, and restore them after dismissal. Preflight's existing
  semantics/focus exclusion remains covered separately. Widget-level semantics
  finders can see cached detached nodes; verify membership in the active
  semantics tree. Localized German/Arabic status and duration regressions cover
  incoming, outgoing/preflight and active call screens. The 211-test focused
  receipt (three existing media-flag skips), initial failures and final two-test
  semantics receipt are retained in the campaign's
  `semantics-localization-regression.log` and `semantics-final.log`; these do not
  certify the subsequent candidate's device accessibility or visual capture.
  While the global call surface covers a retained route, its underlying
  animations must stop ticking. `TickerMode` suspends the covered route during
  ringing, connection and the terminal notice, then resumes the same route
  state after dismissal. The [counter-based regression](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate140-source/covered-animation/covered-animation-red.log)
  and [widget verification](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate140-source/covered-animation/covered-animation-green.log)
  prove ticker behavior, not a cause or measured reduction of device heat,
  CPU usage or battery drain.
  A strictly parsed Android FCM call wake also signals the existing foreground
  mailbox drain, without passing call identity or payload arguments to Dart.
  Delivery requires the exact ACTIVE FOREGROUND lease owner and a ready Dart
  handler; completion rechecks owner, generation and binding. Coalescing and
  stale-reply fences preserve the existing headless admission path. Neither a
  process singleton nor the last registered Flutter engine establishes writable
  authority. The retained
  [129 warm delivery failure](../../.codex-test-logs/android-audio-beta-20260916/129-p2e-signal-03/result.json)
  showed a ready receiver graph and working Go status/inbox operations alongside
  generic `bridge_unavailable`. Foreground lease contention is an inference
  from that source path, not a captured exception from this attempt. The
  corrected classifier reports `graph_not_owner` only for an actual
  `PlatformException` with `lease_unavailable`; other bridge failures remain
  distinct. A missing incoming screen must retain its delivery failure verdict.
  The debug PCM oracle binds the exact adopted native audio owner to its ACTIVE
  FOREGROUND engine, WebRTC plugin and lease generation. FlutterFire's headless
  registration can replace a plugin singleton: the retained
  [128 oracle rejection](../../.codex-test-logs/android-audio-beta-20260916/128-p2e-signal-01/result.json)
  reports `webrtc_audio_processing_unavailable`, an instrumentation failure
  corrected by engine binding in build 129. Do not classify an arbitrary zero
  PCM measurement as the same instrumentation failure. Corrected nonce-bound
  [emulator-to-physical](../../.codex-test-logs/android-audio-beta-20260916/129-e2p-signal-01/signal/summary.json)
  and [physical-to-emulator](../../.codex-test-logs/android-audio-beta-20260916/129-p2e-signal-04/signal/summary.json)
  evidence requires decoded remote signal, exact-owner retention and processor
  removal on both peers. Detector tests reject silence, the local tone and a
  repeated single tone. This proves the capture-post-processing to remote
  render-pre-processing path; it does not prove physical microphone capture,
  speaker audibility or perceived quality, and retains no audio samples.
  A valid probe owner and active callbacks do not by themselves prove decoded
  continuity. Candidate137's physical-origin layout row retained its owner and
  engine, removed processors, and reported no invalid/muted frames, yet failed
  its after-transition signature threshold in both directions. Native
  disconnect/reconnect and canonical recovery occurred during that probe;
  subsequent normal End and clean resources do not upgrade the failed media
  check. Detector-match counts are not packet-loss percentages, and temporal
  coincidence with rotation/font changes does not establish their causality.
  See the [retained result](../../.codex-test-logs/android-audio-beta-20260916/137-layout-physical/result.json)
  and [beta findings](audio-call-beta-findings.md).
  Muting can stop capture callbacks entirely. Negative mute proof therefore
  requires a positive baseline, a retained exact owner, current muted controls,
  zero remote signature, sustained reverse-direction audio, and a positive
  unmute control; zero capture alone is not a failure or sufficient proof.
  Candidate133 completed this full sequence in both originating directions.
  Android route selection, decoded media, OS volume changes and physical
  audibility are separate assertions. A successful shell volume command with
  unchanged readback does not prove a volume change. Record first failures and
  verify the saved volume and route after any alternate OS-control procedure.
  Candidate134's supported Android Settings Call volume slider changed and
  restored physical earpiece/speaker and emulator speaker indices, with fresh
  decoded PCM after each change/restoration and exact equality of all recorded
  stream/device index maps. The retained `134-audio03-os-slider-physical01/`
  receipt is separate from133's unsuccessful shell setters and hardware-key
  restoration failure; successful API invocation alone is not volume evidence.
  Channel policy restoration also includes Android ownership metadata. If call
  channel importance is not user-locked, an off/on Settings round trip adds a
  persistent ownership bit that supported controls cannot remove. The135
  channel-only inspection therefore records INCOMPLETE without mutation; this
  does not block independent global notification/full-screen permission cases.
  The later owned shell actor snapshots the exact channel Parcel, changes only
  its importance and restores the full original bytes, including ownership bits.
  A host-independent ninety-second watchdog and scoped early restoration protect
  host interruption. Concurrent foreign edits are preserved and cannot yield
  exact-restoration PASS. Both 148 actual incoming-call directions now pass
  source, exact restoration and distinct eight-second PCM controls. Android
  package-list filters also return substring companion packages: select exactly
  one valid `com.mknoon.app` UID, rejecting duplicate/malformed own rows without
  rejecting legitimate companions. The original parser failure remains retained
  with [causal verification](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/debug-evidence/channel-uid-files.json).
  Scoped warm-wake/channel/mailbox/composition/headless checks passed 152 tests
  with the pinned Flutter SDK in
  `.codex-test-logs/android-audio-beta-20260916/android-warm-call-wake-host-pinned.log`.
  Native evidence contains 288 passing tests in `warm-call-wake-native/results/`
  and 88 passing notification/presentation tests in
  `ongoing-notification-return-results/` under the same run root. These are
  source checks, not acoustic or signed-release proof. The separate bootstrap
  preservation rerun passed 6 tests after updating only the intentional
  channel-wiring fingerprints; retain the first stale-fingerprint failures and
  the original/focused wrapper reports, rather than relabeling the full
  selection as passed. Debug build 130's installed candidate identity is recorded in
  [artifact-130.json](../../.codex-test-logs/android-audio-beta-20260916/artifact-130.json)
  (APK SHA-256 `dfc3fdbc72b85906e8d263a16c90ed77852fb552d377604b5ac4f3ce11852eea`).
  Each subsequent candidate has its own installed-artifact receipt; later
  scenario verdicts must use fresh attempts bound to that candidate. Do not
  pool evolving builds into a single reliability rate. Reliability cleanup
  requires absence of the pending native
  call file, call service and ongoing call notification before the next call;
  historical Connected events, reused traces and successful setup alone do not
  establish a completed call or a fresh audio proof. Preserve setup failures
  separately from attempted-call failures and keep the first failed evidence
  when resuming a campaign.
  A connected callback can precede fresh remote restart negotiation. If the
  native connection then stays connected, no second callback is guaranteed.
  Recovery readiness sampling must also start after successful current offer
  or answer SDP, with call, phase, generation and epoch fences. Start it outside
  the coordinator-owned effect's awaited dispatch chain to avoid self-wait.
  A reconnect episode has its own local generation: timestamps and native ICE
  generation can remain unchanged across separate interruptions. Scope restart
  deduplication to that episode, and carry it through queued media readiness,
  local failure and reconnect-timeout events. A timer callback and its queued
  admission must both still own the exact timer before removing it or ending
  a call; canceling the old timer must invalidate an already queued callback.
  Newer focus loss similarly invalidates a queued stale recovery at coordinator
  admission. These guards preserve the original15s reconnect deadline rather
  than resetting it. [Episode and focus evidence](../../.codex-test-logs/audio-call-beta-rest-20260917/recovery/source-review.json)
  and the [queued-timeout regression](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate140-source/reconnect/audio-beta-timer-episode-red.log)
  are source proofs, separate from historical secure-transition device causes.
  An offline terminal send may fail immediately while local history, native
  acknowledgement and context cleanup complete. Its bounded delivery owner
  retains only the already sealed envelope and immutable destination metadata;
  retries reuse message ID, sequence, ciphertext and expiry without recreating
  call context. Retention ends at the original signal/endpoint expiry or15s
  after signal creation, whichever is earlier, with at most five retries and
  four pending entries.
  Revalidate current account and exact endpoint authority before writing.
  Shutdown quiesces retained retries immediately but preserves the existing
  one normal app-shutdown terminal send before closing the service. The
  [signaling source manifest](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate140-source/signaling-retry/candidate140-signaling-retry-files.json)
  retains causal cleanup, expiry, authority and shutdown regressions.
  Reconnect signaling uses a separate disposable retry handle only for typed
  transient transport failure. It resumes the exact failed encrypted write
  and any remaining candidate tail without resending an accepted prefix or
  rerunning native restart/SDP creation. Four jittered attempts stay within the
  original canonical15s timeout; exhausted transport work waits for that
  timeout instead of becoming an early authority failure. End remains
  responsive while retry authorization or transport is pending. Call, episode,
  native ICE generation, authority, expiry and shutdown are rechecked after
  awaited work, including the first detached offer. The [reconnect manifest](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate140-source/reconnect/files.json)
  records those host constraints. The production Go bridge's explicit
  `CALL_CONTROL_UNAVAILABLE` must retain this transient classification through
  the real authority client; other explicit relay refusal codes, including
  unauthorized, stale-epoch and unrecognized codes, stay fatal. Its [causal correction](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate141-source/authority-code/candidate141-authority-code-files.json)
  preserves the same budgets and exact bytes. TURN credential connection setup
  has an earlier independent boundary: typed local `ENETDOWN`, `ENETUNREACH`
  and `EHOSTUNREACH`, like a proven deadline, are transient and may use the
  existing still-valid credential cache. A libp2p dial aggregate permits that
  classification only with an allowed root cause, a complete nonempty set of
  attempts and every branch independently proven transient. Mixed trust
  failures, arbitrary joined errors, skipped causes, permission denial and
  malformed responses remain fatal. The [Go classification regressions](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate141-source/turn-network/files.json)
  exercise actual socket and libp2p error types; candidate proof requires a
  rebuilt Go bundle as well as Flutter source. Candidate140's failed NET03
  prompt-terminal gate remains a failure: the retained single failed lookup
  is consistent with this defect, but its exact bridge code was not retained.
  A fresh recovery PCM PASS does not replace that failed source-call verdict.
  A projected `TURN_CREDENTIALS_REJECTED` does not identify the original native
  error: the Dart boundary also maps unrecognized, initialization and bridge
  failures to that value. The [bounded diagnostic regression](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate142-source/turn-diagnostics/files.json)
  retains only allowlisted original bridge codes, fixed failure stages/types,
  booleans and bounded aggregate metadata. Go retains classified sentinels
  instead of raw transport errors; diagnostic inspection is capped at eight
  aggregate entries and 32 unwrap steps per branch. Unknown text and fields
  are not logged, and a failing diagnostic observer cannot replace a typed
  result. These advisory values do not change fallback classification or the
  reconnect deadline. Candidate 141's retained projected rejection still lacks
  the original Go cause; rebuilding the Go bundle and retaining the new fields
  on a fresh device attempt is required before assigning that cause.
  Candidate137's readiness-sampling regression failed as Reconnecting before
  its sampling fix; eight focused cases cover immediate recovery, stale snapshots/SDP, duplicate
  watches and initial-negotiation preservation. The existing structural
  readiness predicate and 15-second reconnection deadline remain unchanged.
  The exact executor suite passes 49, affected calls 958 and signaling 436; counts
  overlap. The [source/coverage receipt](../../.codex-test-logs/android-audio-beta-20260916/candidate137-source-delta-and-host-coverage.json)
  records source-matched native 339 evidence and current omitted selections.
  Two candidate 136 secure-transition calls ended with media_stalled, including
  a matched run without a PCM probe. Their incomplete retained snapshots do
  not prove this race caused those exact failures. Candidate 137's secure
  lock/unlock/relock calls passed in both originating directions with fresh
  before/after PCM; the physical-origin receiver now records remote restart,
  remote offer and mediaRecovered in sequence. A subsequent no-baseline
  control failed with media_failed during a rejected private unlock attempt;
  its cause remains under investigation. Keep these distinct outcomes in the
  [beta findings](audio-call-beta-findings.md), rather than declaring the full
  lifecycle campaign passed.
  Candidate137's separate ringing handoff accepted Answer but never reached
  Connected: both native transports reported FAILED, followed by the unchanged
  initial-negotiation timeout and media_failed. This is distinct from a
  reconnect-readiness sampling failure; the 137 recovery-only branch does not
  execute in that phase. Fresh successful TURN reads after acceptance do not
  prove the returned lifetime, allocation or selected candidate path. Preserve
  those missing observations and the exact accepted-to-timeout interval rather
  than assigning a cause from the source's default credential lifetime. The
  [source review](../../.codex-test-logs/android-audio-beta-20260916/137-secure_ringing-physical/media-failed-source-review.json)
  also distinguishes orchestration markers from actual input brackets; their
  subtraction must not be described as exact tap timing.
  Native `audio/activate` records the controller's service submission; it does
  not establish that Android applied microphone foreground mode. The separate
  `audio/configure` event and fixed `CALL_ANDROID_FOREGROUND_AUDIO` outcome
  observe the actual `startForeground` operation, preserve its exception and
  isolate diagnostic failures. Neither proves ICE connection or decoded PCM.
  Outgoing preparation diagnostics similarly distinguish endpoint lookup,
  context binding and native adoption failures before transport send, using
  only fixed schema values and suppressing canceled/stale work. The terminal
  outcome remains `signaling_failed`; an exception at one boundary does not
  establish why it failed. A terminal `media_failed` with a canonical
  `connectedAt` displays **Call audio was interrupted**, including when the
  terminal projection is the first observed after returning to the app; only
  never-connected calls display **Call audio could not start**.
  The per-call diagnostics count and byte caps remain bounded. Under pressure,
  retain attempt start and terminal records ahead of lower-priority events,
  and prefer recent canonical transitions, media outcomes and native admission/
  audio outcomes over routine traffic. Identical repeated state records must
  not displace distinct transitions. Eviction still marks truncation, dropped
  count and completeness; it does not promise a complete history or recover
  events lost in historical archives. The [priority-retention manifest](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate140-source/diagnostic-retention/candidate140-diagnostic-retention-files.json)
  preserves the causal regressions and unchanged privacy schema. An
  independently retained, exact-process FLOW observer may retain only allowed
  state/trigger/reason enums and timestamps, with single-attempt attribution.
  Stop and join every observer before private credential entry, resume from a
  fresh boundary afterward, and reject delayed payloads timestamped inside the
  gap. Missing events during that gap remain unobserved; neither faster archive
  polling nor a generic terminal reason establishes their cause.
  Preparing's Stopwatch duration measures app-local entry to its frame
  callback. Bind it to one fresh attempt/event and report the outcome alongside
  n/median/worst, including failed calls; it is not physical tap or scanout
  latency. Actual input requires the command's before/after bracket, and
  cross-device intervals require compatible pre/post clock calibration. The
  ordinary helper's answer_tap event occurs after input and cannot establish
  an Answer-latency upper bound by subtraction. A capped archive may omit the
  exact canonical Connected event even when calibrated input and live UI/media
  proof exist; retain that timing gap. A scheduled post-connection PCM sample
  measures its own signal boundary, not first media or first speech. The beta
  aggregator's [32-test receipt](../../.codex-test-logs/android-audio-beta-20260916/137-preparing-summary-ready.json) preserves these distinct labels and excludes
  ambiguous/unbound/duplicate callback records.
  A terminal summary captured before the remote terminal arrives can be empty
  even when later retained exact-trace commit/finish records prove completion.
  Candidate137's reverse fast-Answer case demonstrates this snapshot ordering.
  Keep the original result and cite the later retained records in its review;
  do not replace it with a new call or count a review as another attempt.
  Ordinary Decline and untouched online timeout are distinct protocols from
  fault-injection recovery. Candidate137 passed both directions of each with
  exact matching source outcomes, cleanup before the next Start, and four
  distinct immediate twelve-second PCM controls. Count those eight attempts
  once using their own boundaries; the source wrapper is not a ninth call.
  Keep resource and thermal observations separate from a successful digital
  audio/control result. Preserve each call's starting condition, samples and
  subsequent idle readings; differing thermal baselines cannot establish a
  direction-dependent effect. A brief process CPU sample and cleared call
  resources do not isolate charging, GPU, modem or ambient heat. A short PSS
  series does not prove a leak. The [beta findings](audio-call-beta-findings.md)
  retain the first ten-minute result, its thermal rise and measured cooldown.
  Parse `Cached temperatures` and `Current temperatures from HAL` separately,
  including sensors with negative type values; cached CPU temperatures in the
  retained dump are not contemporaneous HAL measurements. The [current-source
  149 comparison](../../.codex-test-logs/audio-call-thermal-20260919/summary.json)
  kept screen/power/sampling conditions fixed across three ten-minute phases:
  idle/call/post-call CPU averaged 7.02/63.99/6.92% of one core, while all thermal
  samples remained status 0. The call's battery-service temperature rose
  34.8→35.8°C, peaked at 36.1°C after End, and reached 35.1°C after cooldown.
  Native audio threads dominated the measured increase; thirty-second Flutter
  frame observations counted 0/30/0 frames. This did not reproduce historical
  throttling or isolate a defective function, and no with/without `TickerMode`
  comparison was performed. Changed starting conditions, debug build, PCM duty
  and unmeasured ambient/power contributions prevent a thermal-fix claim.
  Endpoint PCM/control/cleanup and [owned-state restoration](../../.codex-test-logs/audio-call-thermal-20260919/restoration.json)
  passed separately; they do not certify heat, energy use or perceived speech.
  The current SIMS CLI treats `--prepare-builds` as a build-only selection.
  Its successful attestation does not execute the audio capability. The change
  wrapper previously supplied that flag. Its corrected dispatch executes the
  selected capability; diagnostic-subset omissions remain NOT RUN without
  being mislabeled failed host prerequisites. Actual host FAIL/BLOCKED still
  blocks device execution. Fixed disposable package bindings prevent these
  account-resetting campaigns from selecting the primary app, and real FCM
  campaigns require a matching downloaded Firebase client. The [dispatch
  and preservation verification](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/wrapper-dispatch/)
  retains causal failures and the first build-only/unrun attempts. New host
  tests outside the core/feature globs must also remain classified by the
  existing legacy call lane. The first 148 aggregate discovered the new debug
  observer test but failed the legacy completeness sentinel (1598/1599).
  [Explicit registration and causal verification](../../.codex-test-logs/audio-call-beta-rest-20260917/candidate148-source/legacy-classification/)
  restore 1599/1599; discovery alone is not a passing classification gate.
  The existing
  `run_production_audio_call_sims.dart --mode major --scenario
  android.production_1to1_audio_call` adapter owns the disposable relay,
  authenticated coturn and Pion oracle, then invokes both preparation and
  actual execution. Bare central execution without its attested fixture fails
  closed. Retain the wrapper's first incomplete result when running this
  separate diagnostic; `.codex-test-logs/call-fallback-priority2/production-audio/`
  records the observed build-only plan and zero device-capability execution,
  and `production-audio-execution/` records the missing-fixture refusal.
  The outer adapter passed all 27 production-call device assertions on the
  available Pixel 6 and API 35 emulator; independent report verification also
  passed. `production-audio-fixture/` retains the exact APK binding, native
  Answer, bidirectional RTP, controls, cleanup/restoration and the separately
  bound known-Opus Pion oracle. This source/debug campaign does not establish
  physical audible sound, deployed-service behavior or signed distribution.
  A separate deployed EC2 follow-up reused that driver, observer and app-state
  guard with fresh identities and the default `mknoun.xyz` services. Two
  relay-only calls selected TURN/UDP; two normal calls selected direct media.
  Both endpoints passed structural readiness, separate advancing bidirectional
  RTP diagnostics, native Answer, controls and terminal release; each mode
  completed a second call. `ec2/observer-profile/` retains exact build arguments,
  APK hashes, observer receipts and allowlisted media-progress observations.
  Both deployed DNS families passed host TCP 3478 and certificate-validated
  TLS 5349 probes; those listener probes do not establish TCP/TLS TURN media.
  The EC2 follow-up did not fault the service or prove an established IPv6
  media-path loss. The local fixture/Pion attestation is not reused as an EC2
  verdict. Endpoint observation hashes are nonce-salted: compare a sample and
  terminal receipt within one endpoint/run, not across endpoint nonces.
  A subsequent exact signed Android release caller (`1.0.1(119)`, APK
  `6bfe15f3ca35a975aaa72a041e93cb10118b70351a1fd41af33317b42a1cd7dd`)
  completed two deployed calls with the disposable debug Pixel callee. The
  discovered API 37 emulator ran with a read-only AVD overlay. Fresh contacts
  used the signed app's actual acceptance UI, then required an encrypted current
  call-wake receipt. The first attempt requested that receipt before acceptance
  and correctly failed its `encrypted_current_grant_required` precondition;
  retain it separately. Both calls passed native Answer, signed call controls,
  native callee structural readiness and inbound/outbound RTP, terminal binding,
  native release and next-call success. Separate advancing-RTP diagnostic samples
  were retained for the second call; the first call's retained diagnostics did
  not establish advancing counters. Coarse `turn_tls` diagnostics group TCP/TLS
  and do not override the separately failing native TLS transport isolation.
  This is one signed caller with a debug callee, not two signed endpoints, iOS
  parity, upgrade proof or release approval. The existing disposable driver
  correctly rejects the production package; its guard was preserved, with
  separate UI-only actions confined to the read-only emulator.
  Automated acoustic checks decoded the committed known-Opus fixture, injected
  four 997/1499 Hz bursts into the emulator microphone, and captured host-mic PCM
  while the Pixel selected its speaker and muted its microphone. The first
  capture's undrained pipe truncated sampling; a concurrent reader fixed that
  instrumentation problem. Later captures completed but did not detect the
  expected burst pattern. Injection acceptance and nonzero source PCM are not
  proof of remote decoded audio or audible speaker output. A read-only VM stats
  attempt could not discover the owned callee's VM endpoint. No human listening
  or raw microphone recording is claimed/retained, and audible output remains
  unverified. `remaining/followup-summary.json` and its linked run artifacts
  distinguish the native, production-signaling, signed and acoustic boundaries.
  Switching a Flutter 3.47 build from device-test Debug to Release with
  `--no-pub` can retain a generated Android plugin registrant that references
  the excluded `integration_test` plugin. Both the first and serial retry failed
  compilation. A normal Release build regenerated the platform metadata and
  passed with the existing lockfile/pins and canonical call defines; signature
  verification passed. Regenerating metadata is not a native regression test.
  Retry only inside the existing semantic deadline and reopen the native shade
  for each Answer attempt because an incoming window may replace it. The
  foreground WebRTC harness uses the same current-call guard and per-call TURN
  provider lifecycle as production; its importing readiness test belongs in the
  call-signaling gate so preparer API changes cannot leave it uncompilable.
  The foreground relay campaign's three-second p95 gate remains independent of
  transport success: a typed latency failure reports the measured p95 after
  valid direct/UDP/TCP media and cleanup legs, rather than hiding it as an
  unexpected malformed-evidence exception. A latency failure is still FAIL and
  produces no passing campaign artifact.
  The Pixel 6/API 35 emulator run passed all 27 actual audio assertions with
  both native call resources released and original app state restored.

- **iOS build identity:** device-profile cache arguments must include the same
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS` supplied to Xcode. The production
  receiver-bootstrap flag was used by the builder but omitted by the pure
  fingerprint helper; the regression now fails on that omission and preserves
  Release/no-DEBUG arguments. This protects artifact identity, not native
  termination behavior. Shared NSE sources compiled in RunnerTests require the
  target-only test marker in Debug, Release and Profile. Keep that marker
  independent of global Swift condition overrides and avoid making test-only
  imports depend on DEBUG. The same Release app/NSE/test build now compiles;
  the five existing native configuration assertions preserve target isolation.

Reuse `AppDiagnostics` and `docker-ws/app_diagnostics.py` before adding logging.
Their existing schema/privacy tests constrain bounded structured diagnostics.
Observed receive/decrypt/store/media events may locate a failed boundary; endpoint
correlation alone does not prove custody, displayed content, or recipient open.
Only report a checkpoint that the retained instrumentation actually observes.
State an investigation area separately from a proven root cause.

- **Go final-only diagnostic records:** `app_diagnostics_store.go` leaves the
  ordinary-event slice nil when only finals have been stored, so JSON contains
  `events: null`. The Python reader treats only that null as an empty list;
  missing/empty lists retain their behavior and other non-list values remain
  invalid records. `test_go_final_only_null_events_retains_valid_final` fails on
  the original reader with one invalid record and no final observation.
  Synthetic preservation tests cover finish/crash/hang report and streaming
  observations, malformed finals/events, consent/erase/epoch and retention
  filters, file/count bounds, strict JSON, drop accounting, output privacy,
  receipt-time windows and detail limits. Finals still require schema validation;
  accepting the Go representation does not establish a missing start or duration.

- **Queued relay diagnostic publication:** accepted contexts carry both actor
  privacy generation and exact admitted trace lifetime. Clear, participant erase,
  disable/re-enable, successful expiry and same-ID recreation must invalidate old
  spans, bindings, authority references and private APNs receipts at publication,
  not only enqueue. APNs capture snapshots actor/context before queue admission;
  the worker checks lifetime under the same lock as persistence. Keep valid new
  contexts, trace-less compatibility, provider behavior, capture caps, quota
  accounting and public-schema privacy as separate controls. Parent causal probes
  reproduce stale publication on inherited source and pass unchanged on the
  reviewed candidate; these host tests do not prove live APNs or phone behavior.
  The reviewed main composition has 1,340 passing Go race leaves with five
  explicitly skipped live transport cases and 55 disjoint operator Python tests.
  A subsequent main `go-relay` wrapper run completed its Go process without test
  failures, but correctly remains BLOCKED for those five skips; 66 other selected
  checks were NOT RUN by that diagnostic subset. Do not call it whole-tree green.
  This source integration is distinct from the deployed-base relay binary and
  does not establish rollout completion or mobile distribution.

- **Native diagnostic test worker exhaustion:** the full Android suite exhausted
  its shared Robolectric worker heap in `MknoonAppDiagnosticSpoolTest`, producing
  13 heap errors and a consent assertion failure in the exhausted process.
  The Gradle daemon's heap setting does not size the test worker. A bounded
  2 GiB test worker, one fork at a time, recycled after 20 classes passed the
  focused spool/resource tests and all 572 full-suite cases with no skips.
  Production spool code was unchanged; this is test-process evidence, not a
  production memory-use claim. Keep the full-suite check as well as the focused
  test because an isolated pass cannot reproduce accumulated SDK sandboxes.
  Original JUnit failures remain in `.codex-test-logs/all-tests-20260920/`;
  corrected full-suite XML and the Gradle log are in
  `.codex-test-logs/failure-fixes-20260920/`.
- **Confirmed diagnostic performance regression:** recording app/call events
  could synchronously scan and JSON-encode the retained archive on Flutter's
  UI isolate despite `unawaited` persistence; native collectors also queued
  unbounded per-event archive rewrites. A multi-megabyte settings export was
  laid out as one selectable text widget. Collection now uses indexed admission,
  coalesced persistence, background serialization, bounded native queues/batches,
  and an 8,192-character visible preview while preserving full copy/export.
  Retained build 112/113 source manifests include an earlier bootstrap that
  awaited diagnostic initialization before launch; the build 115 source removes
  that dependency. The retained build 118 candidate already contains the later
  archive and native admission repairs (`app_diagnostics.dart` matches
  `0fd4abf1b`). Its source closure is retained under
  `artifacts/testflight-crash-investigation-20260910/remaining-20260911/build-candidate/source`.
  Build receipts alone do not prove which IPA was uploaded or installed; do not
  attribute the original archive defect to every device reporting build 118.
  A subsequent causal regression loaded 9,760 events and 1,000 bindings into a
  >4 MiB archive and reproduced a distinct remaining cost: supported upload
  responses acknowledging no events forced an unchanged archive rewrite on
  each resumed retry. The app collector now forces persistence only when an
  event is acknowledged; newly recorded data still persists and a later valid
  ACK remains durable. Red/green and 128 focused preservation tests are retained
  under `artifacts/relay-startup-20260916/tdd-diagnostics/`. Eliminated disk I/O
  is proven; its causal role in the production multi-minute delay is not.
  Moving a full snapshot to `Isolate.run` was insufficient: a physical Pixel 6
  profile with a 3.8 MB archive still showed periodic frame gaps up to 94 ms.
  The shared persistent archive worker therefore receives changed rows only;
  ordinary retention checks skip the archive walk until expiration is due.
  Preserve this distinction when adding diagnostic work: asynchronous disk I/O
  or background encoding alone does not prove a nonblocking foreground path.
  The one-second Dart write window can lose the newest diagnostic observations
  on abrupt termination; explicit flush, lifecycle, clear and consent boundaries
  bypass that window. This never changes the underlying message/call outcome.
  App/call diagnostic and settings regressions cover blocked/failed writers,
  explicit-flush joining, consent races, quotas, terminal preservation and full
  clipboard export. The `diagnostics` selector now includes those consumers.
  An earlier physical Pixel 6 profile compared disabled, original and updated
  collection in three rotated repetitions with 9,760 retained events and 600
  new observations. Ten-event admission median fell from 69.35 ms to 3.42 ms;
  frame total-span p95 was 8.37 ms versus 8.22 ms with diagnostics disabled.
  The updated collector had no ticker gaps over two 90 Hz frame intervals,
  but small additional jitter remained. This isolated Android profile used
  the actual Dart collector with native collection and transport disabled;
  it does not certify whole-app behavior, physical iOS, battery or a signed
  release. Exact inputs, source identities and repeated results are under
  ignored `.codex-test-logs/diagnostics-ux/device-iterations/02-incremental-writer/`;
  the earlier full-snapshot iteration and its residual pauses remain alongside
  it. Red/green logs are retained under `.codex-test-logs/diagnostics-ux/`.
  Follow-up CPU profiling attributed most residual admission time to secure ID
  generation, validation and duplicate JSON byte encoding. UUID generation now
  requests the same 16 secure bytes in four 32-bit draws, preserving all 122
  random UUIDv4 bits. Closed schema membership is cached. Exact quota counting
  avoids allocating event JSON buffers; its cache contains only fixed schema
  strings and cannot grow with runtime IDs. Preserve differential coverage
  against Dart's JSON encoder, including Unicode/surrogates, escaping, integer
  limits, finite doubles, mutable containers and quota boundaries when changing
  this counter or upgrading the SDK. Worker persistence also caches encoded
  event rows; unchanged history is copied into the atomic file without repeated
  JSON traversal. An intermediate host writer benchmark reduced median 64-row saves
  from 22.366 ms to 2.804 ms with identical output bytes; filesystem write volume
  is unchanged. Evidence is under `writer-fragment-benchmark/` and
  `device-iterations/03-residual-profile/` within the ignored diagnostics run.
  Large private binding and upload-acknowledgment indexes also caused periodic
  pauses when copied, transferred and encoded in full on every save. Ordinary
  saves now transfer individual binding and acknowledgment changes; the worker
  retains encoded metadata entries as well as rows. Bindings use a cached expiry
  deadline, so fresh entries are not rescanned on each save. The first commit,
  clear/opt-out and failure retry still supply full sanitized metadata. Preserve
  synchronous snapshot ownership before awaiting, removal-before-reinsertion
  ordering for binding eviction, ACK removal on event expiry/eviction, and full
  reset semantics. Real-file regressions cover those boundaries and restart.
  File assembly uses a reusable 64 KiB buffer; its intermediate host benchmark
  increased write latency by roughly 2–2.5 ms and did not by itself remove the
  phone's metadata-rich save pauses. Do not attribute a frame improvement to
  buffering alone. A separate GC trace associated only some pauses with garbage
  collection; synchronous metadata work remained another candidate. All phone
  acceptance comparisons exclude VM sampling and GC polling. Full intermediate
  results, including worse tails, are retained in
  `device-iterations/performance-review.md` within the ignored diagnostics run.
  With metadata deltas, three physical Pixel 6 repetitions using 1,000 bindings,
  9,760 acknowledged seed events and 600 new observations each had zero frame
  spans or ticker gaps over 16.7 ms, matching the disabled control. The preceding
  metadata-rich version had seven long frame spans and nine long ticker gaps,
  reaching 46.176 ms. All retained IDs, bindings, ACKs and queued-event assertions
  passed. Evidence is under `device-iterations/07-metadata-deltas/metadata-rich/`;
  this remains a bounded isolated Android workload, with the limits above.
  A newly added joining-flush regression first failed, then passed after the
  flush also waited for newly admitted state.
- **Confirmed widget teardown race:** `conversation_wired_test.dart`
  `TC-366-01b` waits for the initial loading shell to disappear, which does not
  join the unawaited `_recoverVisibleMedia` database query. A curated run left
  sqflite's 10-second lock-acquisition warning timer pending at widget teardown;
  the exact case passed unchanged in isolation. Neither diagnostics collector
  is active in that case. Do not treat a disappearing loading indicator or a
  passing isolated repeat as proof that background database work has completed.
  Preserve the initial failure separately from any diagnostic rerun. The stack,
  source audit and both execution results are under ignored
  `.codex-test-logs/diagnostics-ux/device-iterations/07-metadata-deltas/`.
  The September 16 affected-conversation selection failed the same case; its
  unchanged whole-file diagnostic rerun passed 173 tests with three skips.
  Test, widget and database fixture matched baseline `ece276853`; the case uses
  fake P2P recovery and does not initialize diagnostics. The wrapper retained
  the failing test identity but discarded its raw exception, so today's exact
  failure mechanism is not independently proven. Preserve both results under
  `artifacts/relay-startup-20260916/tdd-change-investigation/` rather than
  relabeling the original lane as PASS.
  The September 21 change lane failed the same case; its unchanged isolated
  case and whole-file reruns passed (180 whole-file cases, three skips), again
  without a retained raw exception from the lane. The case now closes its
  owned database inside `tester.runAsync` before the final pump and Flutter's
  pending-timer check; `addTearDown` remains a failure-path fallback. The
  updated whole file also passed 180 cases with the same three skips; the
  exact affected-conversation lane then completed 2,618 passed, zero failed
  and ten pre-existing skipped cases. Its wrapper classification remains
  BLOCKED for skips, not PASS. This
  closes the known cleanup gap without changing production recovery or its
  assertions; retain the original lane failure and the exact lane diagnostic
  under `.codex-test-logs/failure-fixes-20260920/`.
- **Group live-first dedupe test synchronization:** notification publication in
  `maybeShowNotification` precedes the awaited durable remote-announcement
  marker. `FakeNotificationService.shown` therefore cannot establish marker
  completion. The group listener symmetric-dedupe test now joins its admitted
  handler with `stop()` before checking the exact marker and consuming it;
  payload, message ID and consume assertions remain unchanged. The first broad
  lane failure did not retain its raw exception, and the unchanged focused
  test passed; this identifies a source-level synchronization gap, not a proven
  attribution of that original exception. The updated exact affected-groups
  lane passed all 3,195 cases with no skips. Keep both results under
  `.codex-test-logs/failure-fixes-20260920/`.
- **Standalone diagnostic harness discovery:** the PiP native-contract suite
  inventories every integration harness and driver, including files named
  `_harness.dart`. Adding the relay/diagnostics harnesses without explicit
  classifications failed that contract. Three support registrations repaired
  it; the exact suite passed all 12 tests and discovery classified all 293
  records. An intervening SQLite native-asset download timeout occurred before
  tests and remains separate from the passing retry. An attested Android APK
  build does not warm the separate macOS native-asset hook used by a Dart SIMS
  runner. The [verified notification preflight](../../.codex-test-logs/audio-call-beta-rest-20260917/final148-sqlite-native-asset-preflight/results.json)
  replays the real pinned sqlite3 3.1.4 hook via the runner’s no-device scenario
  listing, verifies its declared asset checksum, then observes an unchanged
  cached output on immediate repetition. The original failed download is
  retained; neither APK build nor host preflight supplies push-delivery proof.
  This inventory script
  classifies paths without building or executing native scenarios, so its exact
  selection mapping runs the affected-media inventory contract plus workflow
  and schema checks. Native source/runner mappings and mandatory release checks
  remain unchanged. Evidence: `tdd-change-investigation/discovery-registration-assessment.json`
  within the ignored relay investigation artifacts.
  The same new harness is a legitimate app-resume consumer and also needs its
  single explicit entry in the relocation contract's importer census. The
  four-test census suite passed after that addition; exact equality, production
  source hashes and architecture guards remain unchanged. Preserve its first
  failure under `tdd-change-investigation/layering-census-assessment.json`.
- **Archived-source analysis and workspace access metadata:** strict analysis
  included historical Dart copies under `artifacts/`, producing 98,277 archive
  diagnostics alongside five current-source lint issues. Exclude the historical
  artifact tree, keep current sources subject to strict analysis, and repair
  those five lint issues. The strict command then passed; routing/binding and
  suppression-ratchet preservation tests also passed. Root `info.plist` contains
  workspace access metadata whose timestamp can change during builds; exclude
  only that exact root file from candidate identity. The regression verifies
  that `ios/Runner/Info.plist` changes still change the candidate identity.
  Evidence: `.codex-test-logs/all-tests-y227gs8x/analyzer-repaired.log`,
  `analyzer-routing-preservation.log`, and `workspace-metadata-green.log`.
  These repairs do not turn the interrupted checkpoint 005 host batch into a
  completed result; its owning checks require fresh execution.
- **Confirmed runner hazard, prior evidence:**
  `artifacts/phantom-notification-20260910/host-runner-audit.md` records a
  222-path 1:1 Flutter invocation with 3,747 passes and four skips in about
  157 seconds, followed by an in-flight shell edit causing an unbound status
  and exit zero. These are historical results, not validation of this candidate.
  Lesson: preserve runner status independently, reject zero/incomplete execution,
  record skips, and do not edit a running runner. The new workflow's failure
  tests reproduce the exit-zero/unbound-variable mechanism in a disposable shell
  fixture and verify its corrected control. The historical runner itself was
  not executed.
- **Confirmed shared build hazard, prior evidence:** the same audit records
  parallel native manifest checks writing the same gomobile AAR and corrupting
  it; sequential checks restored it (about 18 seconds plus six seconds).
  Keep shared native artifact mutations serialized or use isolated outputs.
- **Historical product counterexample:**
  `artifacts/phantom-notification-20260910/predeployment_reproduction.md` records
  an intentionally failing old-notification-history Go overlay and a passing
  retained-history control. This is prior evidence, not an old-worktree test
  performed during this implementation. Do not claim all selected checks have
  demonstrated sensitivity to historical broken versions.
- **Documented acceptance limitation:**
  `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`
  (§ GAP-N05) separates bounded Dart/native final-effect proofs from outstanding
  physical Apple, activation/operations and release acceptance. Preserve that
  distinction; host success cannot close those conditions.

For a newly confirmed regression, update the relevant entry using:
**symptom → cause or first confirmed failing boundary → affected behavior →
regression test → selection-rule update → evidence**. Mark hypotheses explicitly.
Preserve unresolved failures until a same-revision result and explanation resolve
them; do not hide them through quarantine or overwritten rerun records.

## Skill use and maintenance

Explicit invocations in a new Codex session opened at this repository are:

```text
Use $mknoon-change-check with base <verified-ref> for my local changes.
Use $mknoon-release-check with previous published revision <verified-ref>.
Use $mknoon-test-maintenance for the changed tests and confirmed regression.
Use $mknoon-all-tests to run every repository test and report all failures and gaps.
Use $mknoon-all-tests, fix failures as you go, and continue the remaining tests.
```

The skills live in `.agents/skills/<name>/SKILL.md` with name/description
frontmatter. Start a new session if this running session's skill catalog predates
their creation; no plugin installation is required. The AGENTS skill invocation
policy still requires an explicit request by name. Ordinary coding work uses the
same scripts directly, without invoking a skill automatically.

Existing `run-flutter-host-gates`, `flutter-test-orchestrator`, and
`flutter-full-regression-runner` were inspected as prior art. They provide host
execution, advisory selection, or full sweeps; they lack this baseline-aware
release evidence contract. The four repository-local skills are small adapters over one
wrapper, not copies of selector logic or a new orchestration system.

`mknoon-all-tests` uses the full-inventory workflow described above, including
host, backend, native, device, contract and performance obligations. It audits
expanded child receipts and reports failures, unrun checks, coverage gaps and
availability-bounded device exclusions separately. Its private-media checklist
is a completeness sentinel, not a restriction on selection. Creating or auditing
the skill does not launch a full regression run; invoking it by name does.

Its optional repair mode works between completed wrapper checks: fresh `--only`
invocations include the selected check's dependency closure, preserve original
failures, verify repairs and continue the remaining queue. It does not pause
inside a composite suite or resume an existing wrapper ledger. Source changes
require affected rechecks and retain earlier evidence under its original
candidate identity. One final full run on the stable repaired candidate is
required before claiming complete passing execution; diagnostic checkpoints
across different candidates cannot establish that claim.

When tests, runners, fixtures, shared dependencies, configuration or confirmed
regressions change, refresh discovery, inspect the affected assertions, update
the manifest and this knowledge, and validate before claiming completion.
Deleted/renamed tests must not leave stale green references. CI must report gaps
and preserve artifacts, never rewrite tracked rules or testing memory.

To refresh and validate a saved inventory snapshot, then test the workflow:

```bash
python3 scripts/mknoon_checks.py discover --list-runners --output .codex-test-logs/inventory-review
python3 scripts/mknoon_checks.py validate --inventory .codex-test-logs/inventory-review/inventory.json
python3 -m unittest discover -s scripts/test -p '*checks_test.py'
python3 -m unittest discover -s scripts/test -p 'testing_inventory_test.py'
```

The saved-inventory check rejects missing entries and a changed discovery
fingerprint; refresh and inspect the difference rather than accepting stale
metadata. Do not commit generated inventory/run artifacts into testing memory.


## Implementation validation and open failures (2026-09-10)

The final inventory refresh discovers 1,960 candidate test files across ten runner
families, with 343 helper/fixture/generated files distinguished. Dynamic test-case
counts remain unknown until execution. Safe listings measured 2.284 seconds total:
1,496 host commands, 32 SIMS full capabilities, 54 orchestration contract groups and
95 legacy full routes. These are separate counts and overlapping inventories.

The workflow itself has 32 selector/runner contracts and five inventory contracts.
They pass, including Git rename/delete/local-diff fixtures, mandatory selection,
real isolated Python processes, SDK mismatch, zero/skipped execution, the
historical exit-zero shell-error mechanism, strict SIMS receipts, timeout cleanup,
manual evidence and preserved first failures. No application test was added or
weakened by this implementation.

A real wrapper diagnostic selection executed all 13 mandatory host groups plus
workflow, existing Python diagnostic and Node provider checks: **432 passed,
2 failed, zero skipped, 65.035 seconds total**. The report retains every omitted
changed-area/device check as NOT RUN and reports overall FAIL; this was a bounded
workflow validation, not validation of the entire pre-existing working-tree diff.
The measured per-group values (including failures) are in each check's
`runtime_basis`; estimates do not imply success or include unknown device builds.
Evidence: `.codex-test-logs/workflow-compatible-host/results.json` and
`summary.txt`; source fingerprint and commands are retained there.

Two earlier failures remain in the retained evidence and mandatory selections:

- Attachment long-press action context: the case declared at
  `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart:250`.
  Investigate context-overlay action wiring and the widget fixture; exact cause
  is unproven. The `media-viewer` selection retains this failure.
- Migrated-out erase preserving delivered notifications while clearing iOS
  recovery: the case declared at
  `test/features/identity/presentation/screens/startup_router_recovery_test.dart:508`.
  Investigate migration erase/recovery sequencing and the fixture; exact cause
  is unproven. The `startup` selection retains this failure.

The later crash-investigation run passed both complete suites (19 media-viewer
and 26 startup tests) without modifying their production paths or tests. The
difference in outcomes remains unexplained; those passes do not establish a
fix for the earlier failures. The retained first failures remain authoritative
for their own run. See the focused investigation record and
`artifacts/testflight-crash-investigation-20260910/check-final/results.json`.

Physical Android local-reset regression: on Pixel 6 / API 37 at
`5a9bb5c94503d3e48dca734f4d2b2cb06fe8141a`, choosing **Erase local data** on
the migrated-out screen and cold-launching produced
`SQLiteNotADatabaseException: file is not a database (code 26)` followed by an
unhandled `DatabaseException`. The old migrated-out erase deleted the
secure-storage registry (including the database key) without removing the
encrypted database. Production now closes and removes the encrypted database,
its SQLite sidecars and rekey recovery files before erasing the key. Failed
close/deletion preserves the key and migrated-out authority. The canonical lease
remains held until normal teardown to prevent reopening during erasure.
Real temporary-file tests cover removal and failure propagation; startup tests
cover ordering, durable authority and notification-preservation guards. The
device erase/restart journey has not been repeated after this fix, so a passing
host erase or secure-key deletion alone does not prove that native journey.
This is separate from the earlier notification-preservation fixture failure.
Redacted device evidence:
`.codex-test-logs/live-phones-20260912T084648Z/android-reset-regression.redacted.log`.

A two-file diagnostic rerun reproduced both failures (43 passed, two failed,
9.470 seconds); focused failed-case reruns also failed. Sanitized follow-up
receipts live in `.codex-test-logs/workflow-diagnostic-followup/`. The exact failed
assertion was not exposed by the machine errors. Flutter's reported line 174
belongs to its `testWidgets` wrapper, not either suite; current reports retain the
reported location URL to avoid attributing framework lines to app tests.

The first attempt with the default PATH was BLOCKED before Flutter cases ran:
Flutter 3.41.4 was selected while `.dart_tool/package_config.json` resolved Flutter
3.47.2. `.codex-test-logs/workflow-real-host/` preserves that 124.066-second attempt.
Use the SDK matching the candidate's package configuration (3.47.2 in this
checkout); the new preflight rejects a mismatch without repeating every suite.
The compatible SDK was selected only for the test process; no SDK or production
configuration was repaired during this task.

The release preview without a published baseline correctly returned BLOCKED
(exit 2), recorded in `.codex-test-logs/workflow-missing-release-baseline/`.
No actual previous published revision or signed AAB/IPA was supplied for build
1.0.1(117). Device campaigns, signed upgrade/compatibility/audio checks and full
regression were not executed. The inventory found a USB Pixel, USB iPhones and
available iOS simulators; Android AVDs Codex_API35 and Pixel_7 exist but were not
running. Disposable device identities/services were not established, so existing
apps/data were not touched. Unavailable version-specific hardware is N/A under
project policy; this does not turn missing essential journey evidence into PASS.

CI YAML was parsed locally and its commands/metadata validated. No remote CI run,
schedule activation, runner provisioning, branch protection or distribution
artifact validation occurred. Existing full entry points have some inherited
coverage overlap; do not sum their counts as unique cases. Weekly execution has a
three-day job budget and does not cancel an active run; queued runs use `queue: max`.
Measure the first full run before claiming the cadence is sufficient. If it hits
its budget, retain its incomplete report and divide the existing routes into
same-revision partitions before relying on scheduled completion. GitHub's
[self-hosted execution limit](https://docs.github.com/en/enterprise-cloud%40latest/actions/reference/limits)
is five days; the full-run command retains its own bounded process timeouts.

`prior_full_failures` exposes known local full-run failures without replacing them
with unrelated green runs. The mandatory `signed-full-review` evidence records
review of unresolved failures, revision consistency and untested conditions.
Legacy/SIMS raw nested logs remain private local evidence. CI exports only the
wrapper's restricted plan/result/partial/error/summary files; inspect and redact
any additional screenshots or diagnostic artifacts before sharing them.

The local Git exclude file ignored AGENTS.md and .agents/. Narrow tracked
.gitignore exceptions now expose AGENTS.md and the three Mknoon skills while
leaving other local skill directories excluded. Their instructions and adapters
can therefore travel with the repository instead of remaining machine-only.


Final preservation checks ran through the real wrapper in 14.810 seconds:
workflow contracts, Flutter bootstrap, Python diagnostics and Node provider
checks all passed. The omitted worktree checks remained NOT RUN and unresolved
mappings kept overall status BLOCKED, as intended. See
`.codex-test-logs/workflow-final-sentinels/results.json`. Final metadata,
byte-compilation, skill references, YAML parsing and whitespace validation passed.
The last focused contract run passed all 32 wrapper and five inventory tests.
The final inventory and its validation are in
`.codex-test-logs/workflow-final-inventory/`.

Graphify's separate process audit reported historical navigation cadence/handoff
violations and classified the new tooling files as pending impact work. This is
not a product-test result. No app-owned production code changed; the project
explicitly excludes tooling-only edits from the post-edit affected/refresh step.
No claim of passing that process audit or token savings is made.
