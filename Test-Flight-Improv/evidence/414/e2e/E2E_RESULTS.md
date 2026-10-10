# Plan 414 device E2E (2026-10-10)

Builds (worktree commit 44d01720b, data and identity kept, user approved):
- Pixel 6 `21071FDF600CSC`: `1.0.0-44d01720b.d11.pdf414.t261010154455` (debug APK, `MKNOON_ENABLE_DOCUMENT_ATTACHMENTS=true`), verified.
- iPhone 13 `00008110-00184D622289801E`: `1.0.04401720.13.414.261010154746`, bundleVersion 261010154746 (release flowlog, same define), verified. This build compiles the new Swift Quick Look code.

| # | Case | Result | Evidence |
|---|---|---|---|
| E0 | Attach sheet shows "Document" with the switch on | PASS | `ui/e02_sheet.xml` |
| E2 | Pixel picks `fake-414.pdf` (HTML bytes) in the system picker | PASS: "Only PDF files can be sent.", nothing staged | `ui/e05_after_fake.xml` |
| E1 | Pixel sends `Invoice-414.pdf` 1:1 to iphone-13 | PASS: tile "Invoice-414.pdf · PDF · 599 B · Sent via cellular relay", `MEDIA_UPLOAD_SUCCESS` | `ui/e07_sent.xml`, `logs/e1_pixel.txt` |
| E1b | Pixel taps its sent PDF | PASS: Android "Open with" (Drive, Drive PDF Viewer, Files); Drive PDF Viewer shows page "Plan 414 Pixel to iPhone" | `ui/e08_open.xml`, `ui/e09_viewer.xml` |
| E3 | Pixel sends `Minutes-414.pdf` to group "test" (iphone-11, iphone-13) | PASS on send: strict group upload `MEDIA_UPLOAD_SUCCESS`, status sent | `ui/e13_group_sent.xml`, `logs/e3_pixel.txt` |
| R1 | iPhone 13 holds both PDFs | PASS: `Documents/media/<pixel peer>/53d26568….pdf` (599 B, 15:49) and `Documents/media/<group>/9134ab54….pdf` (594 B, 16:00); SHA-256 equal to the originals | `iphone13_pull/` |
| E4 | Share sheet into Mknoon | NOT RUN on device: shell-started shares cannot grant read access (plugin crash, see F2), and the chooser lists five "MKnoon" test builds in a changing order | `logs/e4_pixel.txt` |
| I1 | iPhone: tile shows, tap opens Quick Look, Save to Files, send a PDF back | BLOCKED: XCUITest "Timed out while enabling automation mode" (iOS 26 per-boot authorization) on three attempts, 14:00-14:52Z. Needs the phone owner (or a reboot plus one authorization) before WDA can drive it. | Appium log `docker-ws/beta/r34_appium_server.log` 14:00-14:31Z |

Notes:
- R1's 1:1 file arrived at 15:49, before the new iPhone build was installed: the 10-09 build downloaded the PDF (old 1:1 clients store it). Its row has no file name, so the new build shows that tile as "PDF".
- The iPhone 11 in group "test" still runs an older build. By design (R1 in the plan) it drops the group PDF message.

Findings:
- F1 (minor UX): Android viewer title shows the stored name (`53d26568-….pdf`), not "Invoice-414.pdf". The provider's DISPLAY_NAME is the file name on disk. Fix: pass the display name through the open request.
- F2 (pre-existing, not PDF-specific): `receive_sharing_intent` crashes the app (SecurityException in `FileDirectory.getDataColumn`) when a shared content URI is not readable. A PNG shared the same way fails the same way. Real shares grant access, so normal users should not hit it.
- F3 (UX): share-sheet feedback for a refused document is "Failed for 1 target." (all files refused) or "Skipped N oversized attachments" (mixed). It should say only PDF documents can be shared.

## Findings fixed (2026-10-10, Pixel build `1.0.0-f0de1f5d2.d35.pdf414.t261010170103`)

- F1 FIXED: the read-only provider now reports the document's clean name (`displayName` query parameter, accepted only when it keeps the stored file's extension and has no path, control or bidi characters). Device: Drive PDF Viewer title is "Invoice-414.pdf" (`ui/f1_viewer2.xml`). Android share uses the same name.
- F2 FIXED: `ShareIntentReadabilityGuard` drops shared files the app cannot read before `receive_sharing_intent` sees the intent (onCreate and onNewIntent). An unreadable share becomes a plain launch, or a text share when it carries text. Device: the share that crashed before now opens the app normally, no FATAL in logcat (`logs/f2_pixel.txt`).
- F3 FIXED (unit and widget tests; no device route): refused documents have their own count (`skippedUnsupportedDocumentCount`) and text "Skipped 1 file. Only photos, videos, audio and PDF files can be shared." When every file is refused and there is no text, no target is attempted, so nothing reads "Failed".
- Tests: Dart 357/357 (`findings_dart_names.txt`), Android JVM 22/22 (egress 15, guard 5, MainActivity onNewIntent 2).
- Not changed: iOS Save to Files and Share still export the stored file name; only Quick Look uses the document name. The iPhone UI steps stay blocked (automation mode).

