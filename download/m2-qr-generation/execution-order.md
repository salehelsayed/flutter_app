# M2 Execution Order

This document shows the recommended order for executing tasks, including which tasks can run in parallel.

M2 is complete only when the automated smoke test (`QA_XS_01`) prints **PASS** using the real runtime path (WebView JS bridge + SQLite identity repo).

---

## Phase 0: Baseline Pre-flight (M1 must already be real)

These are NOT M2 tasks, but M2 cannot be verified without them.

- [ ] **JS bundle pipeline works:**
  - [ ] `cd core_lib_js && npm install`
  - [ ] `npm run build`
  - [ ] Output file exists: `assets/js/core_lib.js` (generated)

- [ ] **WebView assets are wired in Flutter:**
  - [ ] `assets/js/bridge.html` exists
  - [ ] `assets/js/core_lib.js` exists (from build)
  - [ ] Both are declared in `pubspec.yaml` under `flutter: assets:`

- [ ] **Real WebView bridge exists (no stubs):**
  - [ ] `lib/core/bridge/webview_js_bridge.dart` exists and is used by the app (see `C4_MODEL.md`)

If any pre-flight item fails: fix M1 first. Do NOT add stubs in M2 to "make it pass".

---

## Dependency Graph (M2 tasks)

```
PHASE 1: JS + Flutter Domain (Parallel)
═══════════════════════════════════════════════════════════════════════════════

  JS Track                          Flutter Domain Track
  ────────                          ───────────────────
      │                                     │
      ▼                                     ▼
  ┌─────────┐                         ┌─────────┐
  │JS_XS_01 │                         │FL_XS_01 │
  │Types    │                         │Model    │
  └────┬────┘                         └─────────┘
       │
       ▼
  ┌─────────┐
  │JS_XS_02 │
  │Signing  │
  └────┬────┘
       │
       ▼
  ┌─────────┐   (after this: rebuild bundle)
  │JS_XS_03 │───────────────────────────────▶  `cd core_lib_js && npm run build`
  │Handler  │
  └─────────┘


PHASE 2: Flutter Bridge + Use Case
═══════════════════════════════════════════════════════════════════════════════

  Requires: JS_XS_03 (+ bundle rebuilt), FL_XS_01, M1 IdentityRepository

  ┌─────────┐
  │FL_XS_02 │  (callJsSignPayload)
  └────┬────┘
       │
       ▼
  ┌─────────┐
  │FL_XS_03 │  (buildQRPayload use case + RENDEZVOUS_ADDRESS constant)
  └─────────┘


PHASE 3: UI Layer (can start layout earlier)
═══════════════════════════════════════════════════════════════════════════════

  Layout (no deps)               Wiring (needs use case)
  ────────────────────────       ───────────────────────
  ┌─────────┐                        ┌─────────┐
  │FL_XS_04 │                        │FL_XS_05 │
  │Layout   │                        │Wiring   │
  └─────────┘                        └─────────┘


PHASE 4: QA Gate (automated)
═══════════════════════════════════════════════════════════════════════════════

  Requires: JS bundle rebuilt + FL/JS implementation complete

  ┌─────────┐
  │QA_XS_01 │  (Automated smoke test; MUST print PASS)
  └─────────┘
```

---

## Execution Checklist

### Phase 1: JS + Flutter Domain (parallel)

**JS (core_lib_js):**
- [ ] `JS_XS_01` - QR payload TS types
- [ ] `JS_XS_02` - signPayload() implementation
- [ ] `JS_XS_03` - Bridge handler for `payload.sign`

**IMPORTANT after JS_XS_03: rebuild the WebView JS bundle**
- [ ] `cd core_lib_js && npm install`
- [ ] `npm run build`
- [ ] Confirm: `assets/js/core_lib.js` exists and contains `"payload.sign"`

**Flutter domain:**
- [ ] `FL_XS_01` - QRPayloadModel (canonical JSON)

---

### Phase 2: Flutter bridge + use case

**Prerequisites:** JS bundle rebuilt; JS_XS_03; FL_XS_01; M1 IdentityRepository

- [ ] `FL_XS_02` - `callJsSignPayload()` added to `lib/core/bridge/js_bridge_client.dart`
- [ ] `FL_XS_03` - `buildQRPayload` use case (+ `RENDEZVOUS_ADDRESS` constant if missing)

---

### Phase 3: UI

Layout can be developed in parallel with Phase 1/2, but wiring requires the use case.

- [ ] `FL_XS_04` - QRDisplayScreen layout (`qr_flutter`)
- [ ] `FL_XS_05` - Wire QRDisplayScreen to the real use case and dependencies

---

### Phase 4: QA gate (automated smoke test)

**Prerequisites:** all implementation tasks complete; JS bundle rebuilt.

- [ ] `QA_XS_01` - Add automated smoke test entrypoint and run it on a real device/emulator.

**Gate command (example):**
```bash
flutter run -t lib/smoke_test_m2_qr_generation.dart -d <device-id>
```

PASS criteria:
- App prints `PASS` in logs within a few seconds.
- The test exercised:
  - WebView JS bridge (real, not mocked)
  - SQLite identity repository (real persistence)
  - M2 `payload.sign` command
  - M2 QR payload construction with realness checks
