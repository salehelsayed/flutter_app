# TestFlight termination investigation — 2026-09-10

Updated 11 September. All four supplied reports and 22 supplemental Mknoon
incidents have a disposition; there are no duplicates. Two existing source
corrections are verified in distributed builds 115/117. New notification and
native visibility read admission protections are local, with demonstrated
expiration limits. No native crash family is newly proven eliminated.
Historical generated-code faults and six unattributed suspension incidents
remain unresolved. A fresh signed local1.0.1(118) IPA is built and verified,
with its archive, symbols and source retained; it has not been uploaded.
This is **not a green release verdict**.

Private evidence is under `artifacts/testflight-crash-investigation-20260910/`.
Below, `N/` means its `remaining-20260911/` directory and `F/` means
`release-followup-20260911/`. `N/final-report-dispositions.json` is the complete
per-file/per-build inventory with separate cause, target, validation and
source/distribution fields. Its audit verifies every original hash. Raw reports,
incident/tester identifiers and personal content are excluded from this record.
The previous detailed record is preserved in ignored evidence at
`N/investigation-record-before-consolidation.md`; this file is the concise
current verdict, not a second memory system.

## Target and evidence boundary

Target: branch `feat/ipv6-happy-eyeballs`, HEAD
`f1761aa17e782283f734200f969a9622f3f837ce`, plus substantial pre-existing tracked
and untracked changes. Original snapshots are `initial-status.txt` and
`initial-diff.patch`; the resumed snapshot is `N/starting-status.txt`,
`starting-diff.patch` and `starting-identity.json`. No preceding task-owned file
drift was found at resumption. Unrelated local changes are preserved.

Current bootstrap constructs `GoBridgeClient`; Runner images contain Go runtime
frames. The active application is Flutter with native Go, not an assumed
QuickJS core. Bundled dependency JavaScript is inventoried separately and does
not supply an application-core JavaScript crash mapping. No SDK/plugin upgrade,
storage reset, protocol/routing change, commit, push or publication was made.

Physical iPhone access is restricted to the user-authorized **iPhone 11 and
iPhone 13**; **iPhone 17 is excluded**. Both permitted phones were accessible.
Their personal `com.mknoon.app` installs were preserved (11: build111;
13: build260907203036). Prior authorization for available Android devices,
emulators and iOS simulators remains separate. Physical iPhone checks use iOS
26.5; final native tests use the available iPhone 16e/iOS26.5 simulator.
Unavailable exact crash OS/model combinations are **N/A by project policy**,
not blockers or failed gates. Every executed device command pins its target in
its private receipt.

## Complete supplied inventory

Four ZIPs contain eight readable members: four Apple text crash reports and four
TestFlight feedback JSON files. Every member was analyzed; none is duplicate,
unreadable, unrelated or omitted. No screenshot/application log was supplied;
one feedback references an absent screenshot. The tester remembers no preceding
action. All four are main `Runner`, `com.mknoon.app`, version1.0.1, arm64 native,
TestFlight/beta, `EXC_CRASH(SIGKILL)`, zero exception codes, triggered thread0.
Application role is unknown; application-specific text and last-exception
backtrace are absent. Feedback's arm64e device field is not an image slice.

| Report | Build | Occurrence, UTC+02 | Launch, UTC+02 | Since launch | Device / OS |
| --- | --- | --- | --- | --- | --- |
| R1 | 114 | Sep9 11:27:47.7377 | Sep9 10:38:32.4390 | 2,955.2987s | iPhone18,2 /26.6.1(23G83) |
| R2 | 115 | Sep10 16:48:00.4041 | Sep10 16:44:58.8800 | 181.5241s | iPhone17,3 /26.6.1(23G83) |
| R3 | 117 | Sep10 16:50:04.3590 | Sep10 16:46:45.4147 | 198.9443s | iPhone18,2 /26.6.2(23G90) |
| R4 | 117 | Sep10 16:37:06.4606 | Sep10 11:21:18.4376 | 18,948.0230s | iPhone18,2 /26.6.1(23G83) |

Feedback submission times, respectively, are Sep9 09:30:03.984UTC and Sep10
14:49:49.563,14:50:19.953,14:37:59.439UTC. They are not crash/export times.
Export/download time is unknown. ZIP timestamps lack timezone; conflicting
feedback uptime is not substituted for report launch time. `archive-inventory`,
`file-inventory` and `report-inventory` JSON files retain all original names,
incidents, hashes, image identities, raw addresses and metadata.

Scoped `idevicecrashreport --keep --filter Runner` copies from permitted phones
add 24 files: **22 unique main Mknoon reports**, one separate Mknoon UI-test
runner and one unrelated Apple BackgroundShortcutRunner substring match. Both
other processes are explicitly excluded using their metadata. All device
originals and copies remain unchanged. The 22 occurrences span Aug21–Sep7;
collection on Sep11 is not occurrence time. They are not all TestFlight reports
and are not the app's overall crash rate. No same-run evidence for R1–R4 was
recovered. `N/device-diagnostics/` contains complete metadata, all relevant
threads, binary images, associated-evidence gaps and original-file mappings.

## Build and symbol identities

| Original build | Runner UUID, arm64 | App UUID, arm64 | Source mapping |
| --- | --- | --- | --- |
| 114 | `6B642C33-44D0-3AF4-83B4-A21B41936107` | `13371CD1-7CDC-9E73-651A-A13694F4E926` | Partial: retained revision `d8b919c5b34575d570a78eb5fbbc4203f56f875b`, dirty=true, limited hashes; matching Runner/App dSYMs unavailable |
| 115 | `6ACBE8EC-94C5-36E2-8077-A0EEB3A9A932` | `4B7893E1-A2CB-DC36-2437-D76B6C7C9BAA` | Partial: commit.txt names target HEAD, but dirty inputs are not reconstructed; matching archive/dSYMs available |
| 117 | `CCD1E6DF-2765-34D9-B655-41507152A237` | `D337A5CD-37B7-D2C3-7E1B-AD866AB54748` | Partial: byte-identical retained IPA/report records target HEAD and96 dirty files; complete dirty source/config absent; matching archive/dSYMs available |

Original IPA SHA256 values:114 `aa41b3449ab1fb04b4aa0fc8dec91b348fb9aef76e21bf023a538ef54057b097`;
115 `414c8c6465a23a2e106f235ecfddb425c2665b154208ac37b4f3e275e6acc313`;
117 `7529f87ddb9a0282236f5b65eeaaa96fd969a2f2e0b055100423f559fa6bbda9`.
All share Flutter `4C4C4406-5555-3144-A11D-DFFB6B5E42CD` and SQLCipher
`7EF12B0B-AC15-3E24-876E-FAAEEFEE53A2`. Runner embeds Go1.25.0.114 metadata
records Flutter3.47.2; equal engine UUIDs alone do not establish every historical
SDK/lockfile. Archive metadata identifies Xcode17F113/iOSSDK26.5; Apple's
AppStoreTools processing versions are not substituted for compiler versions.

115's matching archive was created Sep9 14:34:25UTC;117's Sep10 09:04:23UTC.
117's build report timestamp is Sep10 10:57:38 with timezone unknown.116 has
retained artifacts created Sep10 06:59:12UTC but no supplied crash or verified
upload record. Chronology follows this evidence, not version-number ordering.
Read-only GitHub checks found no retained assets, Actions artifacts or runs for
the relevant Sep8–11 window. Historical bundle/configuration and JavaScript
hashes are in `provenance/ipa-inventory.json`, per-build metadata and
`resume-all/provenance/`.

The supplemental build labels are107,110,260821155111,260821172431,
260822195853,260822223526,260826174343,260826234650,260827111701,
260827123536,260829114633,260907113535: **15 affected labels** including the
original three. Exact supplemental app archives/dirty manifests are unavailable
in repository/conventional retention locations. The aggregate inventory records
per-build UUID requirements; dates and version strings are clues, not exact
source mappings. Build110 includes two different Runner.debug.dylib identities.

All11 non-lock reports match arm64 Flutter debug UUID
`4C4C441B-5555-3144-A1FA-318E70EFE420` from the local Flutter3.41.4/Dart3.11.1
SDK, engine`e4b8dca3f1b4ede4c30371002441c88c12187ed6`. All have debug dylibs
and no AOT App image. The four unattributed supplemental suspension reports
instead match release Flutter UUID`4C4C445B-5555-3144-A163-2D7F68E92244`;
its matching dSYM directory is empty and atos supplies no new function names.
These release incidents cannot be dismissed as debug crashes.

Native symbols were used only after UUID/architecture matching.115/117 native
symbols and R4's Dart AOT symbols are usable;114 remains partial. Raw addresses
and original reports remain beside derived atos/disassembly output. No newer
app symbols or indiscriminate Dart symbolication were substituted. Anonymous
JIT addresses still require same-run generated-code mappings.

## Verdicts and causal evidence

There are **seven provisional evidence groups**, plus six separately unattributed
suspension incidents. A provisional group is not proof of one common root cause.
[Apple's termination-code documentation](https://developer.apple.com/documentation/xcode/sigkill)
supports the OS mechanisms below, not incident-specific ownership.

| Family / reports | Actual affected builds | Cause | Target code / fix | Verified distributed inclusion | Validation / gap |
| --- | --- | --- | --- | --- | --- |
| Call-report enforcement R1 | 114 | Probable PushKit obligation violation | Existing receiver-retention fix verified, `f1761aa17` | 115 and117; earliest established115 | Historical3 tests FAIL; native/current tests and4 real CallKit component runs PASS. Exact push/trigger and live PushKit campaign unavailable. |
| Dart notification ledger R4 | 117 | Probable coordination lock during suspension; exact held file unproved | New local scoped admission/diagnostics; expiry remains unresolved | None established | Historical admission controls FAIL; current tests,3 physical transactions and6 native UN operations PASS.70s owner exceeded grant. |
| Badge callback retention S02–S06,S15 | 260826174343,260826234650,260827123536,260829114633,260827111701 | Probable report cause; old async lock-retention defect confirmed independently | Existing `a9ec8e12d` fix verified; unchanged production | 115 and117; earliest established115 | Historical2 FAIL→current7 PASS, real Darwin flock. Reports show waiters, not held-file owners. |
| Native visibility read S09 | 260907113535 | Probable visibility lock at suspension | New local read admission guard before queue/after flock; entered-I/O expiry unresolved | None established | Pre-change4 FAIL, queue-only1 FAIL→final8 PASS; full registry+visibility20 PASS; physical11 three phases PASS. Exact historical source/owner unproved. |
| Compiler allocation S07,S08 | 110, distinct debug dylibs | Confirmed immediate null-allocation fatal; underlying mapping failure unresolved | Witnessed JIT compiler path differs from Release/AOT; no speculative patch | No fixing-build claim | Matched binary proof; no heap/vm_map diagnostics or historical runtime reproduction. |
| Anonymous executable faults S12,S13,S16–S18,S20–S22 | 107(2),110(6) | Unresolved instruction translation faults; grouping provisional | Underlying applicability unresolved; observed debug runtime differs from Release/AOT | Unknown | All reports/registers/VM ranges reviewed; generated function identities missing. |
| Rejected JIT probe S19 | 110 | Confirmed rejection of generated JIT capability probe; signing/debugger reason unresolved | Specific debug probe does not apply to verified Release/AOT configuration | No fixing-build claim | Exact engine/register/instruction proof; historical launch authorization unavailable. |
| Unassigned R2,R3,S01,S10,S11,S14 | 115,117,260822195853,260821155111,260821172431,260822223526 | Six individually unresolved owners | Unresolved; no common-cause or fix claim | Unknown | All relevant threads read; same-run lock/owner attribution missing. |

**R1:** FRONTBOARD`0xbaadca11` occurs with an idle main run loop. Historical
receiver creation depended on capability/startup ordering; retaining the PushKit
receiver independently addresses an actual reporting-obligation gap.
`MknoonVoipPushRegistry`, `MknoonCallNativeBridge` and `MknoonCallKitController`
callers and completion paths were checked, including disabled capability and
queued/coalesced work. Matching115/117 machine code verifies the existing fix.
[Apple DTS's delayed-enforcement explanation](https://developer.apple.com/forums/thread/768136)
supports the hypothesis without proving the precise114 trigger. Current
production was left unchanged; live provider delivery remains untested.

**R2–R4:** RUNNINGBOARD`0xdead10cc` identifies suspension while retaining a file
or SQLite lock, not OOM. R2 samples GC/deserialization plus a file-open worker;
R3 samples idle main plus a file-read worker. Neither identifies an owner. R4's
main stack traverses `isCanonicalUtc`/ledger codec/`LocalNotificationLedgerStore._load`,
supporting a probable notification lock. Allocator/regexp/Flutter top frames do
not establish corruption or an upstream defect. `bounded_posix_flock.dart` now
brackets admission with the existing native `CriticalTaskRegistry`; ordinary
completion unlocks/closes before ending the grant. Refused work remains in the
existing direct outbox for retry. Local diagnostics retain bounded lifecycle and
owner observations; aggregate uploads preserve the old schema. Counts exclude
unobserved acquisitions, other isolates and native/SQLite owners.

A controlled70s owner outlived its iPhone grant at27.678s and retained its lock
through75s. Resume preserved the seed record; no SIGKILL occurred. Two controlled
host cases using real Darwin flock and mocked grant/liveness further confirm
that invalidating a lease cannot revoke
already-running/unpublished work safely. A helper-only forced unlock would
violate storage ordering. The limit is demonstrated; no complete suspension
fix is claimed. This conclusion also applies to unidentified owners outside
Dart's notification registry.

**Badge:** the old writer kept its FD through asynchronous UN completion on a
serial queue. A successor could block that queue on flock while the queued
completion needed it to unlock. `a9ec8e12df75ee84242a6dd9b828ece4020eb94a`
releases after synchronous submission, retaining bounded revision repair.
`IosNotificationRecovery.swift` is unchanged from that fix through HEAD/target.
Both Runner/NSE callers use it. Matching115/117 disassembly verifies unlock/close
after submission; a Git message alone is not the distribution evidence.
Existing durable state is reread; no migration/deletion is needed. The six
stacks identify waiters, not owners; another held file remains an alternative.
Synchronous badge/state work is still not proven suspension-safe.
`N/native-badge-writer/final-verdict.json` preserves exact diffs/addresses and
native RED/GREEN commands. Seven existing tests were added to the existing373
runner's selection, preserving its original21 and all failure/skip validators.

**Visibility:** S09 samples `read`→`Data(contentsOf:)`→native snapshot
`loadStateUnlocked/readSnapshot`→coordinator→platform handler. This native read
path is separate from R4's Dart ledger. Source history shows`3c7e704e` introduced Runner's
blocking read;`ffe37b71` added a bounded NSE-only reader and preserved Runner's
path. Both pre-change Runner/store files exactly matched HEAD, with no later
guard/reversion. Exact affected dirty source remains inferred, not verified.

The new `IosAppVisibilityCoordinator.readSnapshot` begins the existing native
grant before queue admission, rechecks after the queue, and passes a read-only
liveness predicate into `IosAppVisibilitySnapshotStore.readSnapshot`. The store
checks it after process/file-lock acquisition, before reading persisted state.
Refusal returns existing unavailable/null; Dart clears cached suppression and
allows notifications. On normal return both locks are released before grant end.
The unchanged UIKit registry declarations move outside the Go import guard,
preserving no-Go compilation without a second task owner. Lifecycle writes,
route publication, NSE reads, data formats and storage location are unchanged.
Dropping lifecycle writes could leave stale foreground suppression, so they are
not subject to the new read refusal. Already-entered I/O and delayed main-thread
expiry delivery remain unresolved. `N/visibility-review/` holds history,
independent review, original/final bytes, controlled failures and final hashes.

**Debug incidents:** exact engine instructions connect compiler returnPC`0x6ff848`
to a failed non-executable allocation and fatal branch with “Out of memory.”
The vm_map error, allocation size and memory footprint are absent; this is not
proof of jetsam, physical RAM exhaustion or a leak. One report has a secondary
allocation failure while formatting the first compiler failure. Tagged source
line90 differs from embedded binary line96, so it is corroboration only.

S19's argument11, indirect call/return address and exact `mul w0,w0,w0; ret`
bytes identify the generated square-function JIT probe at launch age0.1313s.
[Dart's virtual-memory implementation](https://raw.githubusercontent.com/dart-lang/sdk/3.11.1/runtime/vm/virtual_memory_posix.cc)
corroborates this. Debugger/AMFI authorization and historical signature state
remain unknown. Eight SIGBUS reports instead show instruction translation faults
in anonymous executable shared memory: seven share40 retained bytes/page+0x90,
one differs/page+0xc4. These bytes are not in the matched engine file; no Dart
function can be named. Code mapping/lifetime, execution authorization and pointer
corruption remain alternatives. No SDK upgrade is justified. Candidate
[Release/AOT mode](https://docs.flutter.dev/testing/build-modes) establishes a
different execution path, not general memory/signing safety. Exact evidence and
all11 per-report mappings are in `N/nonlock-review/final-nonlock-verdict.json`.

**Other suspension incidents:** S01 has parked/Bonjour workers; S10 active close;
S11 timer scheduling; S14 active rename. All main threads are idle. S01/S10
report the device unlocked, S11/S14 locked; every app role remains unknown.
Neither device lock state nor a sampled file operation identifies file ownership.
`N/idle-lock-review/final-idle-verdict.json` retains independent verdicts and
matching-release-symbol attempts. No old-date/debug-only dismissal is justified.

## Changes and regression protection

New native admission changes affect only
`ios/Runner/IosAppVisibilityCoordinator.swift`,
`ios/NotificationService/IosAppVisibilitySnapshot.swift` and the conditional
boundary in `ios/Runner/GoBridge.swift`. Six behavior cases extend
`IosAppVisibilitySnapshotTests`; one extends the existing Dart authority test.
The371 runner selects all8 visibility methods;373 selects all28 original+badge
methods. Existing mandatory `notification-lock-diagnostics` includes the four
visibility Dart files and native-source/runner mappings. All28 mandatory checks
remain. `TESTING.md` records verified causes and limitations. No already-correct
PushKit/badge production fix was rewritten.

Earlier device validation also exposed three **separate current media defects**,
not proven causes of the supplied native reports. Their focused local fixes,
regressions and final device proofs remain included in the candidate:

| Boundary | Correction / preservation | Evidence |
| --- | --- | --- |
| Outbound strict group manifest | `send_group_message_use_case.dart` normalizes absent waveform only at manifest comparison; nonempty samples, signed bytes and custody stay exact. Original contract comes from`8d86501e46`. Six focused cases protect it. | `resume-all/android/group-media-waveform/` |
| Group SQL authority | `GroupMediaKeySnapshot` resolves and binds secure references before SQL, under existing media ownership through commit/rollback. Reopened legacy keys remain valid; wrong/stale/cross-database proofs reject. No plaintext SQL rewrite or keychain I/O in a transaction. | `resume-all/android/group-media-key-boundary/`, composition review;24 focused DB+39 recovery/composition tests |
| Incoming group commit/delete | `media_attachment_repository_impl.dart` proves legacy raw or secure-reference key representation under the existing lifecycle lock before exact SQL callback; other comparisons remain. Metadata-only previews do not hydrate keys. | `resume-all/android/group-media-receiver-delete/`, post-decrypt review;28 repository/download cases, deletion/preservation controls |

Later share-forward/DTR18 fixtures and P269 harness identity/schema/ordinary
primary-account setup were corrected without changing production authority
mode. The empty relay placeholder was retired only after five real payload tests
rejected a notification-injection mutation; restored exact relay checks pass.
Go check reporting now retains hashed failed-test identities; it cannot recover
the older unnamed failure retroactively. Exact merged deltas and failures remain
in `F/primary-merge-receipt.json`, `root-final-delta-review.json` and family
receipts. No historical distributed inclusion is inferred for these media fixes.

## Validation performed

Counts below are executions, often overlapping, not unique tests. All commands,
source/configuration identities, initial failures and cleanup records remain in
ignored evidence. No successful compilation substitutes for runtime validation.

| Check | Result and conditions | Evidence |
| --- | --- | --- |
| Visibility causal controls | Pre-change read4 FAIL/11 assertions; queue-only contention1 FAIL/2 assertions. Final8 PASS on iPhone16e/iOS26.5,48.041s, no-Go UIKit target. | `N/visibility-review/native-test/` exact xcodebuild argv/xcresults |
| Shared native preservation | 20 PASS/0 FAIL/0 SKIP,86.650s: all12 unchanged registry tests+8 visibility tests, actual full GoBridge and retained Go/Flutter frameworks. | Same folder, with-Go final command/results |
| Physical final visibility | iPhone11/iOS26.5, optimized Swift arm64, no debugger, one PID: foreground1.19ms/background3.92ms/resume8.23ms. Each read observes held flock, one native end, inactive task and unlocked FD at return; synthetic seed bytes unchanged. Disposable bundle removed. | `N/visibility-physical/final-receipt.json` |
| Badge causal controls | Historical2 FAIL→restored7 PASS; real Darwin locks with exact existing XCTest cases/full production recovery source in private SwiftPM target. | `N/native-badge-writer/` |
| Focused Dart policy | 12 PASS using Flutter3.47.2: authority, snapshot, wiring and route tests; null-read rejection clears stale suppression and only a new generation restores exact authority. | `N/visibility-dart/command.json`, `results.json` |
| Final affected wrapper | 1,488 PASS/0 FAIL/1 conditional SKIP,493.528s: workflow42, affected-push1,188, bridge127, provenance15, notification-lock116. Overall BLOCKED: omitted checks remain NOT RUN; six existing unmapped paths remain. | `N/affected-checks/run-artifacts/results.json` |
| Conditional skip | Explicit emission rollback skips under ordinary configuration. Its existing separate false-define run passes1; current test, production dependency and lockfile hashes match. Broad result remains unchanged. | `N/affected-checks/skip-audit.json`, `F/release-checks/complementary-configurations/` |
| Prior native/physical controls | Existing130 native PASS; old receiver3 FAIL/18 assertions and old lease4 FAIL/13 assertions. Four real CallKit runs(2foreground/2background),3 ledger transactions and6 UN operations PASS with seeded rows retained.70s owner outliving grant remains a demonstrated limit. | `continuation/`, `resume-all/ios/`, `N/lock-reassessment/` |
| Prior Android journeys | Linked-group, direct-media4 assertions, reconnect3, audio27 and ordinary P269 media PASS on the authorized physical Pixel6+available emulator topology. Real JPEG/MP4/voice, process/database reopen and interrupted retry exercised. Fixture failures and distinct-authority controls remain separate. | `resume-all/android/`, `F/p269-review/` |
| Prior complete cohort | 20,356 PASS/5 FAIL/21 SKIP across100 checks;78 PASS/19 BLOCKED/3 FAIL checks. Share fixture and3 DTR18 failures corrected; original unidentified Go failure retained. | `F/release-checks/` |
| Prior corrective checks | Go1.25 exact full rerun1,793 PASS/0 FAIL/2 known DCUtR feasibility SKIP; final affected1,069 PASS; exact relay12 PASS. First fixture/setup failures retained. | `F/go-core-review/`, `final-focused-checks/`, `go-relay-review/` |

Physical visibility is a private-container component proof. It does not exercise
AppGroup/NSE/APNs, a finite grant duration, actual suspended-state termination,
or the signed118 IPA. It uses seeded state to isolate reads; lifecycle semantics
are protected separately by the existing native tests. No personal account/data
was used. Simulator16e was restored to shutdown and its disposable app removed.

Native setup failures are retained separately from app behavior: the first
all-eight private target contained an invalid fixture extension and ran no tests;
a valid extension with the exact existing privacy manifest corrected it. The
with-Go fixture first omitted libresolv, required by the existing podspec, then
linked correctly. Physical receipt copying initially lacked a local destination
and once preceded the background callback; subsequent copies captured the same
run, not a retry that erased failure. No assertion was weakened.

Exact final host selection, pinned Flutter3.47.2 and Go1.25.0:

```sh
python3 scripts/mknoon_checks.py validate
PATH=/Users/I560101/development/flutter-3.47.2/bin:$PATH GOTOOLCHAIN=go1.25.0 python3 scripts/mknoon_checks.py plan --mode change --base f1761aa17e782283f734200f969a9622f3f837ce --local --output artifacts/testflight-crash-investigation-20260910/remaining-20260911/affected-checks/final-preview
PATH=/Users/I560101/development/flutter-3.47.2/bin:$PATH GOTOOLCHAIN=go1.25.0 python3 scripts/mknoon_checks.py run --mode change --base f1761aa17e782283f734200f969a9622f3f837ce --local --only workflow,notification-lock-diagnostics,affected-push,bridge,ios-build-provenance --output artifacts/testflight-crash-investigation-20260910/remaining-20260911/affected-checks/run-artifacts
```

Selection metadata passes; preview/run exit2 honestly retain incompleteness.
The final wrapper identity is`335991ede7fc466f256ee55abaa3a7ee91758c2dbd65fc5ca2474a2c96ee2f7c`
over4,782 test-selection inputs:4 checks PASS,1 BLOCKED,92 NOT RUN. This hash
has a broader input domain than the build source identity below.
An earlier preview used the default3.41.4 SDK and was BLOCKED before tests;
the corrected pinned preview is separate. HEAD is an explicit change-comparison
base, not an invented previous published revision. Full host/device/release
sweeps were not repeated for this focused native change. The existing mutation
runners were not executed against the primary tree; syntax, named-result
validators and existing batch contracts were checked separately.

Graph impact coverage is complete with zero pending paths; the architecture
graph was refreshed incrementally. The session workflow benchmark retains two
navigation-ordering failures (5/7 categories pass), separate from application
tests. Exact counters are in `N/final-graph-workflow-benchmark.txt` and
`final-document-memory-stats.txt`. Final tracked-diff comparison found only the
seven intended code/test/runner changes and expected generated graph updates;
unrelated tracked changes remain byte-identical to the resumed snapshot.

## Local build and retention

A fresh local **1.0.1(118)** App Store archive/export completed on its first
attempt (568.954s), followed by successful independent artifact validation.
It uses a new isolated checkout and the existing build entry point; nothing was
uploaded or installed:

```sh
scripts/build_ios_appstore_ipa.sh --build-name=1.0.1 --build-number=118 --target=lib/main.dart --no-pub
```

`N/build-candidate/archive-source-freeze.json` records4,159 inputs with identity
`9e50f8242d0e3e4547abef22aa3a8229dd97a9d913dba84b9b09332db51b8556`.
All30 retained Go framework files and current/isolated binding digests match;
Go bindings were not unnecessarily rebuilt. Offline dependency resolution and
configuration preserve the source closure. Actual Release settings identify
ordinary `lib/main.dart`, production VoIP/voice flags and testabilityNO, with
Flutter3.47.2/Go1.25.0. `N/build-candidate/final-local-build.json` records the
completed artifact, matching source closure and preservation checks.

Fresh IPA: `N/build-candidate/source/build/releases/1.0.1+118/ios-20260911T090950Z-3a1010da6401461e9c2c852582e309d9/mknoon.ipa`.
SHA256 `f440128a8b2ae1f534e1d9b6477acd2a5358d5a9b69694566996b409e0284258`,
61,319,107bytes. The same directory retains `Runner.xcarchive` and
`provenance.json`. Runner UUID`80C470C2-2280-3BDF-AD7E-29DE5E20EB2B` and App
UUID`E7BF9CFC-B877-9374-1662-64A2E659248D` match the IPA/archive/dSYMs, arm64.
All23 signatures,3 distribution profiles and24 dSYM images verify. All4,159
captured source files still match primary;75 changed source files reconstruct
from recorded HEAD plus retained patch/untracked archive. The native visibility
change is verified in this local artifact's source capture. **Runtime on this
exact signed IPA remains NOT RUN; distributed inclusion remains unverified.**

The previous local118 IPA is retained unchanged under `F/build/source/`, SHA256
`bc02216235a470006317b1036bd2444de5019d9472a932131b11d5b8b67ec9c2`.
It predates the native visibility correction and must not be substituted for the
fresh candidate. Its AppStore signing was verified, but it has no runtime
receipt. Neither candidate has been uploaded by this task; AppStoreConnect
build-number availability is unqueried. A local source correction is not proof
that testers received it.

The existing build helper now retains unique immutable run directories,
archives/dSYMs, source/configuration/lockfile/toolchain evidence and filtered
working-tree reconstruction. Historical exact binaries are not recreated by
rebuilding commits. Runtime/source snapshots exclude credentials; a required
Firebase configuration is copied privately with hash-only metadata. These are
small retention improvements in the existing build flow, not a CI redesign.

## Missing evidence and release implications

The suspension risk remains open: admission protection cannot safely revoke an
already-running owner, and six incidents lack attribution. Debug executable
faults also lack a confirmed root cause. Absence of newer exports establishes
neither a crash rate nor resolution. No family is declared eliminated by a clean
launch, changed code or passing mocked tests.

Required evidence is precise and independent:

- Same-run acquisition/release, native-expiration, lifecycle and OS held-file/
  SQLite-owner evidence for R2–R4 and unattributed supplemental incidents.
  Existing diagnostics miss the original windows: Sep9 logs start afterR1;
  Sep10 build116 logs cover07:41–07:58UTC, beforeR2–R4. Exact searched locations
  are in `provenance/diagnostic-time-ranges.json`.
- 114 Runner/App dSYMs matching UUIDs in the build table; dirty native source for
 114, complete115 dirty manifest, and117's96 dirty inputs/configuration.
  Supplemental per-build Runner/App UUID requirements are listed individually
  in `N/final-report-dispositions.json`; S09 specifically needs Runner
 `57791507-62B2-3C94-B589-6FFE06086A6B` and App
 `9BC54AC9-3F17-98F5-8663-F61863D4EAC8`, arm64.
- Old release Flutter dSYM`4C4C445B-5555-3144-A163-2D7F68E92244`; debug Runner
  dylib dSYMs`1022964B-74AD-3830-81C6-AC0C3D24C6FE`,
 `108BC2A1-B1AA-37CD-8D72-60A1590846E4`,
 `CCF2C36F-DE47-3A3C-9165-DD5AF7ACA3FB`, all arm64. Native dSYMs alone cannot
  name anonymous JIT functions: same-run generated-code maps, launch/debugger/
  executable-page diagnostics and allocation size/vm_map results are needed.
- WebRTC dSYM`4C4C447E-5555-3144-A121-D213E61611C0` is unavailable but no causal
  verdict depends on it; it is not a prerequisite for the verified fixes.
- Actual signed-candidate notification/AppGroup/NSE, disabled cold/queued VoIP,
  normal debugger-free background/resume, and preserved existing-installation
  upgrade evidence. Current local development profiles authorize only occupied
  production bundle IDs for these capabilities; the disposable wildcard has
  neither APS nor AppGroup access. No isolated provider topic/credentials are
  configured in the existing local conventions. `N/candidate-readiness/` and
 `F/release-readiness-audit.json` record the exact scope. A development/ad-hoc
  export is a different artifact from an AppStore IPA.

No new hardware is required by policy. Signed runtime/provider configuration,
missing historical artifacts and unidentified owners are distinct gaps.
Six pre-existing unmapped paths also remain visible: the retained historical
receipt counterexample, four server deployment utilities and the runtime-root
manifest. They were not hidden or classified as covered by unrelated tests;
no server deployment occurred. Original failure/skip/BLOCKED/NOT RUN verdicts
remain visible after passing controls. The final candidate still requires an
honest release decision against its actual published baseline and runtime
conditions; this investigation does not grant permission to distribute it.
