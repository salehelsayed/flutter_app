# M2 File Structure

This document shows the project structure for M2 and maps tasks to their output files.

---

## Project Structure Overview (M2 touches only)

```
flutter_app/
├── lib/
│   ├── core/
│   │   ├── bridge/
│   │   │   └── js_bridge_client.dart              # (M1) + GLUE_01 adds callJsSignPayload()
│   │   └── constants/
│   │       └── network_constants.dart             # (M2) IMPLEMENT_01 adds RENDEZVOUS_ADDRESS
│   ├── features/
│   │   └── qr_code/
│   │       ├── domain/models/
│   │       │   └── qr_payload_model.dart          # (M2) IMPLEMENT_01
│   │       ├── application/
│   │       │   └── build_qr_payload_use_case.dart # (M2) IMPLEMENT_01
│   │       └── presentation/screens/
│   │           ├── qr_display_screen.dart         # (M2) IMPLEMENT_02
│   │           └── qr_display_wired.dart          # (M2) IMPLEMENT_02
│   ├── integration_test_m2_js_signing.dart        # (M2) INT_01
│   └── smoke_test_m2_qr_generation.dart           # (M2) SMOKE_01
│
├── core_lib_js/
│   └── src/
│       ├── types/
│       │   └── qr_payload.ts                      # (M2) GLUE_01
│       ├── signing/
│       │   └── sign_payload.ts                    # (M2) GLUE_01
│       └── bridge/
│           └── handlers.ts                        # (M1) + GLUE_01 adds payload.sign handler
│
├── assets/js/
│   ├── bridge.html                                # (M1) WebView wrapper
│   └── core_lib.js                                # (generated) BUILD_01 rebuilds
│
└── pubspec.yaml                                   # (M1) + BUILD_01 adds qr_flutter
```

---

## Task → File Mapping

| Task | File(s) Created/Modified | Purpose |
|------|--------------------------|---------|
| GLUE_01 | `core_lib_js/src/types/qr_payload.ts` | QR payload TypeScript types |
| GLUE_01 | `core_lib_js/src/signing/sign_payload.ts` | signPayload() implementation |
| GLUE_01 | `core_lib_js/src/bridge/handlers.ts` | Add `payload.sign` handler |
| GLUE_01 | `lib/core/bridge/js_bridge_client.dart` | Add `callJsSignPayload()` method |
| BUILD_01 | `pubspec.yaml` | Add `qr_flutter` dependency |
| BUILD_01 | `assets/js/core_lib.js` | Rebuilt JS bundle (generated) |
| IMPLEMENT_01 | `lib/core/constants/network_constants.dart` | RENDEZVOUS_ADDRESS constant |
| IMPLEMENT_01 | `lib/features/qr_code/domain/models/qr_payload_model.dart` | QRPayloadModel |
| IMPLEMENT_01 | `lib/features/qr_code/application/build_qr_payload_use_case.dart` | BuildQRPayloadUseCase |
| IMPLEMENT_02 | `lib/features/qr_code/presentation/screens/qr_display_screen.dart` | QR display UI layout |
| IMPLEMENT_02 | `lib/features/qr_code/presentation/screens/qr_display_wired.dart` | Wired screen with state |
| INT_01 | `lib/integration_test_m2_js_signing.dart` | Real runtime handshake test |
| SMOKE_01 | `lib/smoke_test_m2_qr_generation.dart` | E2E smoke test (milestone gate) |

---

## Notes on Generated Assets

**CRITICAL:** `assets/js/core_lib.js` is a **generated file**.

- **DO NOT** edit this file directly.
- It is built from `core_lib_js/` sources via `npm run build`.
- After any changes to `core_lib_js/src/**/*.ts`, you MUST rebuild:

```bash
cd core_lib_js && npm install && npm run build
```

- Verify the bundle contains `"payload.sign"`:

```bash
grep -q '"payload.sign"' assets/js/core_lib.js && echo "OK" || echo "MISSING"
```
