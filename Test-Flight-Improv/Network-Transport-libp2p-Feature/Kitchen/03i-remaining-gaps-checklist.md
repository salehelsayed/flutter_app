# 03i — Remaining Gaps

> **Source:** Cross-reference of `03b-timing-improvement-plan.md` against `03f-benchmark-test-inventory.md`
> **Fact-checked:** 2026-04-15 against actual codebase

---

## 1. Run Existing Harnesses — DONE

- [x] **Inbox E2E Delivery** — D-Sim ran, inbox store=**122ms** on iPhone 17 Pro
- [x] **Group Publish with 0 peers** — GP-Sim-2 harness exists. G8 measured `successNoPeers` (1218ms) as closest approximation.

## 2. Small Code Additions — DONE

- [x] **5MB media transfer** — Added to S12. **1MB=467ms (2193KB/s), 5MB=1323ms (3870KB/s)**
- [x] **Group Discovery join→connected timing** — G6 now reports **5255ms** (5s settle + ~255ms actual)
- [x] **Media stream open timing** — Captured via `_captureFlowEvents` + `_filter('media:stream_open_timing')` in S12

## 3. Timeout Accuracy — KNOWN LIMITATION

- [ ] **Force remaining timeouts to fire** — H-Sim gets instant errors. Needs network simulation to force real timeouts. Documented as known limitation.

## 4. Document in 03f — DONE

- [x] **Hazard fix status** — All 5 fixes documented in "Hazard Fixes Implemented (03b §4)" section
- [x] **Instrumentation status** — Both items documented in "Additional Instrumentation Implemented (03b §3)" section
