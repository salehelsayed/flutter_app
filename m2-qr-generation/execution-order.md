# M2 Execution Order

M2 is complete only when smoke test prints PASS.

---

## Phase 0: Baseline Pre-flight (M1 must already be real)

- [ ] JS bundle pipeline (core-lib builds and copies to assets)
- [ ] WebView assets (index.html, core-lib.js in assets/webview/)
- [ ] Real WebView bridge (JsBridge can send/receive messages)

---

## Dependency Graph (M2 tasks)

```
PHASE 1 ──────────────────────────────────────────────────────────────
  JS Track (sequential)              Flutter Domain (parallel)
  ─────────────────────              ─────────────────────────
  JS_XS_01 → JS_XS_02 → JS_XS_03         FL_XS_01
      │          │           │               │
      ▼          ▼           ▼               ▼
   (types)   (sign fn)   (handler)       (model)

PHASE 2 ──────────────────────────────────────────────────────────────
  Flutter Bridge + Use Case
  ─────────────────────────
  FL_XS_02 (needs JS_XS_03) → FL_XS_03 (needs FL_XS_01, FL_XS_02)
      │                            │
      ▼                            ▼
  (callJsSignPayload)        (buildQRPayloadUseCase)

PHASE 3 ──────────────────────────────────────────────────────────────
  UI Layer
  ────────
  FL_XS_04 → FL_XS_05 (needs FL_XS_03, FL_XS_04)
      │           │
      ▼           ▼
  (layout)    (wiring)

PHASE 4 ──────────────────────────────────────────────────────────────
  QA Gate
  ───────
  QA_XS_01 (needs all above)
      │
      ▼
  (smoke test)
```

---

## Execution Checklist

### Phase 1: Foundation (Parallel Tracks)

**Track A: JavaScript Core-Lib**
- [ ] `JS_XS_01` - QRPayloadJson type definition
- [ ] `JS_XS_02` - signPayload() implementation
- [ ] `JS_XS_03` - Bridge handler for payload.sign

**Track B: Flutter Domain**
- [ ] `FL_XS_01` - QRPayloadModel with JSON mapping

---

### Phase 2: Bridge + Use Case

- [ ] `FL_XS_02` - callJsSignPayload() bridge function
- [ ] `FL_XS_03` - buildQRPayloadUseCase()

---

### Phase 3: UI Layer

- [ ] `FL_XS_04` - QRDisplayScreen layout
- [ ] `FL_XS_05` - Wire QRDisplayScreen

---

### Phase 4: QA Gate

- [ ] `QA_XS_01` - Execute QR generation smoke test

**Gate command:**
```bash
flutter run -t lib/smoke_test_m2_qr_generation.dart
```
