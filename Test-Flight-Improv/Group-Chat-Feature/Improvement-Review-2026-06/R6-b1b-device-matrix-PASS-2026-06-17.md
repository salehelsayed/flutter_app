# R6 — `b1b_sibling_device_convergence` device-matrix proof: **PASSED** (2026-06-17)

Closes the final external gate of `12-P2-PartB-REMAINING-TDD-plan.md` (R6), which blocks the
R7 `kMultiDeviceSyncEnabled` flag-flip. Proves **per-device ML-KEM key separation** on real
crypto: a restored sibling device obtains the group key ONLY via the live
announce → admit → redistribute path (a 1:1 key-update ML-KEM-sealed to its FRESH device key),
never via a fixture.

## How it was run

Two booted iOS simulators, real Go bridge (real ML-KEM/ed25519), prod relay:

```
dart run integration_test/scripts/run_b1b_sibling_device_convergence.dart
# defaults: primary = iPhone Air (347FB118-…), sibling = iPhone 17 (5BA69F1C-…)
# builds both with --dart-define=MKNOON_ENABLE_MULTI_DEVICE_SYNC=true
```

Implemented in the **2-role** multi-device harness (`group_multi_device_real_harness.dart`),
scenario `b1b_sibling_device_convergence`: `primary` = admin/creator, `sibling` = the primary's
restored second device. (Deviation from the plan's 3-role multi-party framing — chosen because
the multi-party harness has no live key-redistribution receive pipeline, while the 2-role harness
already wires `GroupKeyUpdateListener`; the per-device proof is identical. The primary admits its
own restored sibling.)

## Verdict (run 1781715513029) — the cryptographic proof

| Field | primary | sibling |
|---|---|---|
| logical peerId | `12D3KooWG26LG8…ACLW` | `12D3KooWG26LG8…ACLW`  (SAME account — restore) |
| transport peerId | `12D3KooWG26LG8…ACLW` | `12D3KooWHNYQL1…26io`  (**DISTINCT** — fresh on restore) |
| ML-KEM public key | `gSlHfIE655…` | `zdloMiGGH7…`  (**DISTINCT** — fresh per-device key) |
| admit outcome | `admitted` | — |
| keyEpochReceived | 1 (current) | 1  (via live redistribution) |
| decryptedPostAdmitText | sent | `B1b post-admit from primary …`  (decrypted) |

`[ORCH] B1b per-device ML-KEM convergence proof PASSED` · both harnesses `All tests passed.`

## Why it's airtight (not vacuous)

- The sibling **starts keyless**: `expect(getLatestKey(groupId), isNull)` immediately after the
  shell import (which calls `callGroupJoinWithConfig` for topic subscription but deliberately does
  **NOT** `saveKey`) — this assertion passed, so the join did not seed the key.
- The sibling then `waitForCondition(getLatestKey != null)` passed (no timeout) → the key arrived,
  and the only path that persists a key from null is `GroupKeyUpdateListener` decrypting the 1:1
  ML-KEM-sealed redistribution **with the sibling's fresh ML-KEM secret**.
- Flow markers observed: `GROUP_SIBLING_DEVICE_ADMITTED`, `GROUP_KEY_DISTRIBUTION_DISTRIBUTED`
  (deviceCount 2 = primary's own device + sibling).
- The sibling then decrypted the primary's post-admit group message.

## Debug iterations (for the record)

1. **DatabaseException** — harness test-DB `onCreate` was missing migration 078
   (`group_pending_key_distributions`); the send-side reopen/drain sinks threw. Fixed: added
   `runGroupPendingKeyDistributionsMigration` to `onCreate` + import.
2. **`RECIPIENT_DEVICE_MISMATCH`** — decryption succeeded but `_isBoundToLocalRecipient` could not
   find the sibling device in the sibling's **own** local roster (the shell fixture predates the
   admin's admit). Fixed: a restored device registers its own announced device on its local member
   roster (it knows its own identity; this does not introduce the key).

## What changed

- `integration_test/group_multi_device_real_harness.dart`: `b1b_sibling_device_convergence`
  dispatch + `_runB1bConvergencePrimary`/`_runB1bConvergenceSibling` + `_importGroupShellForB1b`
  (shell import without key) + send-side redistribution wiring (distribution repo + runner +
  drain/reopen sinks, scoped to the b1b primary) + migration 078 in `onCreate`.
- `integration_test/scripts/run_b1b_sibling_device_convergence.dart`: dedicated 2-sim orchestrator
  (flag ON, no CLI peer).

## Remaining for R7

R6 is now green. R7 (flip `MKNOON_ENABLE_MULTI_DEVICE_SYNC` on for prod) still also requires R2
(trust-prompt UX) per the plan, then `group_multi_device_policy_contract_test.dart` + UX-013
re-closure.
