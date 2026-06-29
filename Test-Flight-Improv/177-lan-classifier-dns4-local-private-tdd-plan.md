# 177 - FDC-S6 LAN classifier: `/dns4/<host>.local` counted as private/LAN  (Bug)

Status: awaiting-review
Spec: free-text intent (no formal spec) — found during plan 176 (CV-09) FDC-S6 pilot collection (2026-06-29)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-29 | Evidence Collector | lan_address_classifier.dart, lan_address_classifier_test.dart, bonsoir_discovery_service.dart:115-147, p2p_bridge_client.dart:618-629 | root cause confirmed in source + device-confirmed | hand to Planner |
| 2026-06-29 | Planner | (above) | `.local`-gated fix; existing `example.com→false` test already guards over-broadening | emit plan |
| 2026-06-29 | Reviewer (sufficiency) | this plan | see Reviewer Findings | — |
| 2026-06-29 | Arbiter | this plan | host RED→GREEN gating; device re-run = closure | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | lan_address_classifier_test.dart | (cmd proving FAIL) | RED for documented reason | |
| | implementation | lan_address_classifier.dart | | scoped 1 file | |
| | direct GREEN | | | reds now green | |
| | preservation GREEN | | core-host-all | sentinels green | |
| | device-proof (closure) | FDC-S6 pilot re-run | lanPrivateIp:true + certified win-rate | win-rate certifiable | |

## Source Of Truth
- Bug: `lib/core/local_discovery/lan_address_classifier.dart:23-34`.
- Fix-C `/dns4` builder: `lib/core/local_discovery/bonsoir_discovery_service.dart:129-146` (proto `dns4` for a hostname; trailing dot stripped at :129).
- Sole consumer (emit): `lib/core/bridge/p2p_bridge_client.dart:629` `'lanPrivateIp': multiaddrsContainPrivateIp(addresses)`.
- FDC-S6 win-criterion that consumes it: `Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/fdc-s6-measurement/` (RESULTS + parser).

## Session Classification
implementation-ready (host RED→GREEN is the gating deliverable; a device re-run of the FDC-S6 pilot is the real-world closure).

## Exact Problem Statement
The FDC-S6 private-IP discriminator `multiaddrIsPrivateIp` (`lan_address_classifier.dart`) only credits `/ip4`/`/ip6` IP literals; a multiaddr whose host is a DNS name (`/dns4/<host>...`) falls through to `return false`. But **Fix C (plan 175)** builds `/dns4/<host>.local` multiaddrs for **iOS-resolved** bonsoir peers — iOS bonsoir resolves a same-WiFi peer to its `.local` mDNS **hostname**, not a numeric IP (`bonsoir_discovery_service.dart:119-136`; `/ip4/<hostname>` fails to parse, so `/dns4` is correct for dialing). The per-peer `lanPrivateIp` boolean is computed from these addresses via the classifier (`p2p_bridge_client.dart:629`) **before emit** (the raw multiaddr is redacted from logs), so it is **`false` for every iOS-discovered peer**.

FDC-S6's "clean libp2p-LAN win" criterion = `direct` leg AND bonsoir-fed AND `lanPrivateIp:true`. Because iOS-discovered peers always get `lanPrivateIp:false`, that criterion **can never be satisfied when iOS is the discoverer** → the soak systematically **under-counts** real LAN wins (mislabels them "ambiguous WAN/DCUtR") for cross-platform iOS↔Android AND iOS↔iOS pairs. The retire-WS verdict would be computed on corrupted data.

**Device-confirmed (2026-06-29, plan 176 pilot):** real iPhone 11 emitted `P2P_LAN_PEER_FOUND_REQUEST{addrCount:2, peer:<Pixel>, lanPrivateIp:false}` for a genuinely LAN-direct conn (`transport:"direct"`, both on 192.168.0.x, `EnableDcutrUpgrade=false` ⇒ no DCUtR fold). The parser scored 0% clean-LAN-wins purely from this gap.

**What must improve:** a `/dns4|/dns6|/dnsaddr/<host>.local` multiaddr must classify as private/LAN (`lanPrivateIp:true`).
**What must stay unchanged (preserved-green sentinels):** all existing `/ip4`/`/ip6` literal classifications; `/dns4/example.com` (non-`.local`) STAYS false; `/p2p-circuit`/empty STAY false.

## Root Cause (verify → refute confirmed)
`lan_address_classifier.dart:23-34` `multiaddrIsPrivateIp` matches only `proto == 'ip4'` / `'ip6'` segments. A `/dns4/Android_X.local/udp/45000/quic-v1` has proto `dns4` → no match → `return false`. An mDNS `.local` hostname is **link-local by definition (RFC 6762)** — it resolves only on the local link via multicast DNS, so it can NOT be a WAN address and IS valid LAN evidence.

**Refuted / do-NOT-re-introduce:**
- ❌ "Any `/dns4` host should be private." REFUTED — a `/dns4/example.com` could be a WAN domain; the existing test `lan_address_classifier_test.dart:72` pins it `false`. The fix must be **`.local`-gated**, not "any dns4".
- ❌ "Already fixed on HEAD." REFUTED — the classifier returns false for all non-ip4/ip6 (read :23-34).
- ❌ "Wrong root cause (the false came from elsewhere)." REFUTED — Fix C emits `/dns4` for hostnames (:136), the emit computes lanPrivateIp via the classifier (:629), and the device showed `lanPrivateIp:false` for `addrCount:2` genuine-LAN. DCUtR off + same-subnet rules out a real WAN/DCUtR `direct`.
- ❌ "Change the win-criterion to bonsoir-fed-only (drop lanPrivateIp)." OUT OF SCOPE — fixing the classifier makes lanPrivateIp correct; the WAN/DCUtR guard stays meaningful for non-bonsoir `direct` legs.

## Real Scope
**In scope (1 prod file + its test):**
1. `lib/core/local_discovery/lan_address_classifier.dart` — extend `multiaddrIsPrivateIp`: for `proto == 'dns4' | 'dns6' | 'dnsaddr'`, return true iff the host (next segment) is an mDNS `.local` name (case-insensitive; tolerate a trailing dot defensively). Keep all `/ip4`/`/ip6` logic unchanged. Update the file/function doc comment (lines 19-22) to record the `.local` case.
2. `test/core/local_discovery/lan_address_classifier_test.dart` — add the RED cases below.

**Out of scope (owned elsewhere / correct as-is):**
- The FDC-S6 win-criterion (bonsoir-fed AND lanPrivateIp) — unchanged.
- Fix C / the `/dns4` multiaddr build (`bonsoir_discovery_service.dart`) — correct for dialing.
- `p2p_bridge_client.dart:629` emit wiring — already routes through the classifier; no change beyond what the classifier returns.
- No Go change. No parser change (it consumes the boolean; it will simply see `true` now).

## Files To Inspect Next
Production (edit): `lan_address_classifier.dart:23-34`.
Test (edit): `lan_address_classifier_test.dart` (new cases in the existing "non-IP host components" + aggregate groups).
Dependency-only context (DO NOT edit): `bonsoir_discovery_service.dart:129-146`, `p2p_bridge_client.dart:618-629`.

## Existing Tests Covering This Area
- `lan_address_classifier_test.dart` — covers /ip4, /ip6, IPv4-mapped, and (line 71-78) `/dns4/example.com → false` + `/p2p-circuit → false` + empty. EXISTS, all pass. **Gap:** no `.local` case (the production shape Fix C emits) → MISSING.
**Already in curated family arrays?:** No — `test/core/**` AUTO-glob (`core-host-all`). Not in any `run_test_gates.sh` family.

## RED Test Catalog  (add BEFORE the production edit — INV-RED-FIRST)
1. `lan_address_classifier_test.dart::'mDNS .local hostnames (Fix C /dns4) are LAN evidence'`
   - Tier: unit (pure function host).
   - Shape/setup: assert each → `isTrue`:
     - `/dns4/Android_9DNYWLJG.local/udp/45000/quic-v1/p2p/12D3KooFoo` (exact Fix-C QUIC shape)
     - `/dns4/Android_X.local/tcp/45001` (exact Fix-C TCP shape)
     - `/dns6/iphone-host.local/udp/45000/quic-v1`
     - `/dnsaddr/host.local/tcp/4001`
     - `/dns4/HOST.LOCAL/tcp/4001` (case-insensitive)
     - `/dns4/host.local./tcp/4001` (defensive: unstripped trailing dot)
   - RED on HEAD because: classifier returns false for all non-ip4/ip6 protos.
   - GREEN after fix asserts: each `.local` dns multiaddr → true.
   - Mutation that re-reds: remove the `dns4|dns6|dnsaddr` arm in `multiaddrIsPrivateIp` → this test red.
2. `lan_address_classifier_test.dart::'non-.local dns hosts stay ambiguous (not LAN) — .local is the discriminator'`
   - Tier: unit.
   - Shape/setup: in ONE test assert BOTH `multiaddrIsPrivateIp('/dns4/Android_X.local/tcp/45001')` `isTrue` AND `multiaddrIsPrivateIp('/dns4/example.com/tcp/4001')` `isFalse` AND `multiaddrIsPrivateIp('/dns4/notlocal/tcp/4001')` `isFalse` AND `multiaddrIsPrivateIp('/dnsaddr/relay.example.org/tcp/4001')` `isFalse`.
   - RED on HEAD because: the `.local` half asserts true but HEAD returns false.
   - GREEN after fix asserts: `.local` → true while every non-`.local` dns host → false (the over-broadening guard).
   - Mutation that re-reds: make the fix match ANY dns4 (drop the `.local` check) → the `example.com → false` assertion red. **This is the anti-over-broaden lock.**
3. `lan_address_classifier_test.dart::'multiaddrsContainPrivateIp true for a .local-only advert set'`
   - Tier: unit.
   - Shape/setup: `multiaddrsContainPrivateIp(['/dns4/Android_X.local/udp/45000/quic-v1', '/dns4/Android_X.local/tcp/45001'])` → `isTrue` (the exact per-peer set Fix C builds for an iOS-discovered Android peer).
   - RED on HEAD because: both are `/dns4` → both false → aggregate false.
   - GREEN after fix asserts: aggregate true (this is the value `p2p_bridge_client.dart:629` emits as `lanPrivateIp`).
   - Mutation that re-reds: revert the classifier change → red.

## Test Coverage Matrix  (zero empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-77-01 `.local` dns → private | pure logic | unit | `lan_address_classifier_test.dart::mDNS .local…LAN evidence` | non-ip4/ip6 → false on HEAD | remove `dns4|dns6|dnsaddr` arm → red | `flutter test test/core/local_discovery/lan_address_classifier_test.dart` | AUTO (`test/core/**`) |
| TC-77-02 non-`.local` dns stays false (over-broaden guard) | pure logic | unit | `lan_address_classifier_test.dart::non-.local dns…discriminator` | `.local` half asserts true; HEAD false | drop `.local` gate (match any dns4) → `example.com→false` red | `flutter test test/core/local_discovery/lan_address_classifier_test.dart` | AUTO (`test/core/**`) |
| TC-77-03 aggregate `.local` set → true | pure logic | unit | `lan_address_classifier_test.dart::multiaddrsContainPrivateIp…local-only` | both `/dns4` → false → aggregate false | revert classifier → red | `flutter test test/core/local_discovery/lan_address_classifier_test.dart` | AUTO (`test/core/**`) |
| TC-77-04 iOS-discovered peer certifies on device | OS-boundary / multi-device | device-proof | FDC-S6 pilot re-run (`fdc_s6_capture.sh` + `fdc_s6_parse.py`) | n/a (closure) | revert classifier → `lanPrivateIp:false` again, parser 0% clean | manual two-phone, NO dart-define (reuse the CV-09 ON-arm build) | reuses FDC-S6 harness; capture must span discovery (start capture → cold-start the pair) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** N/A — `multiaddrIsPrivateIp` is a pure stateless function; no persisted/derived state.
- **Sibling-surface consistency:** the classifier has **one** production consumer — the `lanPrivateIp` emit at `p2p_bridge_client.dart:629` (confirmed by grep). The FDC-S6 parser consumes the emitted boolean downstream (no code change — it sees `true` now). No parallel capability gate to update. Covered.
- **Destructive-action side-effects:** N/A — no delete/cleanup/cancel.
- **Invariant re-verification under new transitions:** N/A — no new state transition; the change is a wider classification of a pure input.

## Invariants (locked by tests)
- INV-1: any `/dns4|/dns6|/dnsaddr/<host>.local` (case-insensitive, trailing-dot tolerant) → private/LAN → TC-77-01.
- INV-2: a non-`.local` dns host (potential WAN domain) → NOT private → TC-77-02 (over-broaden lock).
- INV-3: all `/ip4`/`/ip6`/circuit/empty classifications unchanged → the existing test groups stay green.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (pre-existing dirty: `info.plist`, `project.pbxproj`, FDC-S6 pilot logs — do NOT revert).
2. Add the 3 RED tests (TC-77-01/02/03). Run the focused cmd → confirm they FAIL for the documented reasons.
3. Edit `lan_address_classifier.dart`: add the `dns4|dns6|dnsaddr` + `.local` arm to `multiaddrIsPrivateIp` (a small private `_isMdnsLocalHost` helper: lowercase, strip one trailing dot, accept `local` or `*.local`). Update the doc comment 19-22. **Stop-if** TC-77-02's `example.com→false` goes red after the edit → the fix over-broadened; re-gate on `.local`.
4. Rerun direct GREEN → preservation (`core-host-all`) → `flutter analyze`.
5. Device closure: re-run the FDC-S6 pilot (capture-then-cold-start so discovery is in-window), confirm `lanPrivateIp:true` for the iOS-discovered peer and a non-zero certified win-rate. After landing: `graphify update .` + `./graphify-arch/refresh_arch_graph.sh`.

## Risks And Edge Cases
- **Over-broadening to any `/dns4`** (most likely error) → pinned by TC-77-02 (`example.com → false`).
- **Trailing-dot / case variance** — Fix C strips the trailing dot (`bonsoir_discovery_service.dart:129`) and the host is device-name-cased; the helper lowercases + strips defensively, locked by the case/trailing-dot cases in TC-77-01.
- **`/dnsaddr` host without `.local`** (a real relay dnsaddr, e.g. `mknoun.xyz`) must NOT become LAN → TC-77-02 covers a `/dnsaddr/relay.example.org`.

## Device/Relay Proof Profile
Host RED→GREEN is the gating deliverable. **Device re-run is the real-world closure** (not a fake): re-run the FDC-S6 pilot on Pixel 6 + iPhone 11, NO LAN-dial dart-define (reuse the CV-09 ON-arm build), **start the captures THEN cold-start the pair** so `P2P_LAN_PEER_FOUND_REQUEST{lanPrivateIp}` lands in-window; confirm `lanPrivateIp:true` for the iOS-discovered peer and a non-zero `fdc_s6_parse.py` clean-LAN win-rate. (iPhone must be foregrounded by TAPPING the app icon, not `devicectl --terminate-existing` — that leaves it GPU-render-denied/black.)

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before the edit) — must FAIL for the documented reason
flutter test test/core/local_discovery/lan_address_classifier_test.dart   # expect: the 3 new .local cases FAIL

# Direct GREEN (after the edit)
flutter test test/core/local_discovery/lan_address_classifier_test.dart    # expect: all pass

# Preservation sentinels (must stay green)
./scripts/run_host_test_gates.sh core-host-all                             # classifier + p2p host suite green

# Hygiene
flutter analyze            # 0 new issues
git diff --check

# Device closure (manual two-phone) — NO LAN-dial dart-define, capture-then-cold-start:
# bash fdc-s6-measurement/scripts/fdc_s6_capture.sh android <udid> logs/v_i2a pixel   (start FIRST)
# bash fdc-s6-measurement/scripts/fdc_s6_capture.sh ios <udid> logs/v_a2i iphone       (start FIRST)
# then cold-start both apps; send a batch; Ctrl-C; then:
# python3 fdc-s6-measurement/scripts/fdc_s6_parse.py --label "A->i" logs/v_a2i/*.log   # clean LAN wins > 0
```

## Known-Failure Interpretation
- Expected RED: TC-77-01/02/03 before the edit.
- Pre-existing dirty (do NOT revert): `info.plist`, `ios/Runner.xcodeproj/project.pbxproj`, the FDC-S6 `logs/pilot*` files.
- Environment blocker (NOT product): a black iPhone app screen after `devicectl --terminate-existing` = GPU-render denial (launch the app by tapping it); a multi-AP-WiFi mDNS failure = rig, not code.
- Scope drift (BLOCKING): any change to the win-criterion, Fix C, the emit wiring, or Go.

## Done Criteria
- [ ] RED added first (TC-77-01/02/03), failed for the documented reason.
- [ ] Mutation-verified: remove the dns/.local arm → TC-77-01/03 red; drop the `.local` gate → TC-77-02 red.
- [ ] Direct GREEN + `core-host-all` + existing classifier groups green; `flutter analyze` 0-new; `git diff --check` clean.
- [ ] Device re-run: `lanPrivateIp:true` for the iOS-discovered peer + non-zero certified win-rate.
- [ ] Post-land: `graphify update .` + `./graphify-arch/refresh_arch_graph.sh`.

## Scope Guard (hard "Do not")
- Do NOT make any non-`.local` `/dns4|/dns6|/dnsaddr` host private (WAN-domain false positive).
- Do NOT change the FDC-S6 win-criterion, Fix C `/dns4` build, the emit wiring, or any Go code.

## Accepted Differences / Intentionally Out Of Scope
- A `direct` win to a non-bonsoir-fed peer still requires an IP-literal private addr (or a `.local` dns) to count — the bonsoir-fed AND lanPrivateIp belt-and-suspenders is preserved; we only made `.local` correctly satisfy the IP half.

## Dependency Impact
- FDC-S6 win-rate verdict (plan 176 / CV-09 follow-on) depends on this: without it, every iOS-discoverer direction reads 0% clean-LAN-wins, corrupting the retire-WS decision.

## Reviewer Findings
Sufficiency: 3 host RED rows (each tier+mutation+literal-gate+AUTO-registration) + 1 device-proof closure row; the over-broaden risk is mutation-locked by TC-77-02 (the single most important guard — a `.local`→true + `example.com`→false in one test). The existing `example.com→false` test means NO current test breaks (the fix is purely additive for `.local`). Refuted hypotheses recorded. Blind-spot sweep: 4 justified N/A (pure function, single consumer). Thin evidence: none — full chain read in source + device-confirmed.

## Arbiter Decision
Structural blockers: none. Deferred details: device re-run is manual two-phone (reuses FDC-S6 harness). **implementation-ready.**

## Final Execution Verdict
Verdict: (pending execution) | Files changed: 1 prod + 1 test | Tests run (+counts): (pending) | Blocking: (pending) | QA verdict: (pending) | Non-blocking follow-ups: FDC-S6 pilot re-run + graphify refresh.
