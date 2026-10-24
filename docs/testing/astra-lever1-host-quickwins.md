# Lever 1: MEDIA/CALL host journey joins

Owner assignment: Kayan `m-7fe1a390`; source baseline
`5e1821e231185ca35a25873124fda16eff291fd5`. The closure analysis is committed
separately as `5b5c4d433074acd5a67f8fa50ff3e17019cec256`. These changes add tests
and this handoff only. Application behavior is unchanged.

The defining host contracts now join previously separate layers. Native picker,
protection, call-start and export ports remain explicitly replaced where a host
cannot execute them. SQL tests use the current production migrations and
repositories; close/reopen means a real file database reopen, not OS process death.
The complete PDF fixture has a page, font, content stream and byte-correct xref;
signature-only fixtures remain appropriate only for signature checks.

| Journey | Added or extended proof | Exact host source | Remaining platform boundary / flutter_app handoff |
| --- | --- | --- | --- |
| MEDIA-009 | Real `SystemMediaPicker`/`ImagePicker` adaptation of null camera/video and empty gallery results; document MethodChannel cancel/pathless result conversion; actual conversation retains draft, removes an image, uploads/sends only the retained sibling once. | `test/core/media/media_picker_test.dart`; `conversation_wired_test.dart`, case starting `MEDIA-009/MEDIA-013` | In the existing Group C/D conversation, cancel the real camera/gallery picker, keep caption, pick two images, remove one and send. Prove the removed item has no receiver row and the retained one has exactly one row. This host join does not operate an OS picker. |
| MEDIA-012 | Document composition remains off while a complete received PDF traverses the actual conversation tile, default egress service, owned-path/PDF checks and native MethodChannel adapter. `noViewer` then `presented` requests retain source bytes, row and unsent draft. | `conversation_wired_test.dart`, case starting `MEDIA-012` | Keep the actual send flag off. Receive the complete PDF through the existing ordinary-media driver, confirm Document is absent, then open it in the real native viewer. Record an actual rendered page; presentation alone is not decoding. On a supported target with no viewer, preserve truthful failure and the original. Do not manufacture an unavailable platform condition. |
| MEDIA-013 | Actual sparse image file over 25 MiB is budgeted from file length; Send produces zero upload/message effects until removal, then the valid sibling sends once. Mixed complete PDF, non-PDF bytes, empty file, short signature, wrong extension, missing file and empty path preserve only the accepted PDF and visible refusal. | `conversation_wired_test.dart`, `MEDIA-009/MEDIA-013` and `MEDIA-013 complete PDF...`; platform-result adapter case in `media_picker_test.dart` | Malicious platform values are host fault inputs, not a claim about an OS dialog. A native valid-PDF control still belongs to MEDIA-012/packet 2. The app checks a PDF signature; these tests do not claim a complete parser rejects every malformed PDF with a valid header. |
| MEDIA-022 | Extends the existing real two-pointer pinch/swipe/Back case with host engine decode dimensions and viewport change while retaining the exact selected path/index. No duplicate gesture test. | `test/shared/widgets/media/full_screen_image_viewer_test.dart:14` | Reuse the received-image leg in Group C/D. Full-resolution detail/orientation and processed-sender/receiver equality are separate packet-2 evidence. Host viewport resizing is not an OS rotation or native camera proof. |
| MEDIA-025 | Current SQL, real files and direct/group library widgets join in one journey: reopen, 50+2 tied-order pages, foreign/deleted/sibling-lane exclusion, durable bookmark filter, exact typed-viewer owner/parent/attachment and Back. | `test/features/conversation/integration/media_library_sql_widget_journeys_test.dart`, two `MEDIA-025` cases | Reuse the current direct/group library routes and receive fixtures. Verify the selected visible item opens its correct current parent/file. Group persisted encryption metadata is synthetic fixture data; native transfer/authentication is not exercised here. No unsupported library search UI is invented. |
| MEDIA-026 | Real SQL selection feeds the actual batch coordinator and actual egress service; a parent becoming private is refused before native dispatch; only failed eligible items retry, settled items do not. Actual file hashes are checked at the replaced destination. A SQL reopen also joins forward-source captions/tokens/files, guarded bookmark state and exact parent-local deletion. | `media_library_sql_widget_journeys_test.dart`, two `MEDIA-026` cases | Reuse Group D and `received_media_native_egress_proof_test.dart` plus its receiver ledger for real save/share bytes and per-item outcomes. Keep ordinary forward's existing sparse source-target coordinator test. SQL forward snapshots are not delivered messages. The local database-delete leg deliberately has no file manager/export owner; native file deletion is not claimed. |
| MEDIA-034 | Current SQL and exact private-file authority feed the actual lifecycle engine/viewer controller. Hold only native protection admission, race durable consume/delete/owner change, then assert no stale byte-bearing grant or native re-entry. Valid control admits one first frame, closes and refuses reopen. | `test/features/conversation/integration/private_media_sql_open_races_test.dart`, four `MEDIA-034` cases | Existing `direct_private_media_continuity_test.dart` still owns download single-flight and route/pause guards. Reuse the private protection campaign for actual secure-window/capture behavior. This join races open admission after a completed download; it does not claim a real transfer kill or an OS screenshot was blocked. |
| VC-021 | Terminal projector → current SQL file reopen → actual Calls page → actual redial controller → exact callback admission port. Duplicate terminal replay keeps one row, duration/reason and privacy-safe route metadata. | `test/features/call/data/call_history_repository_test.dart`, `VC-021 terminal projection...` | Optional existing-call smoke confirms the expected peer rings; history identity is a logical contract and does not require a new semantic audio hook. Constructed terminal snapshot and replaced outgoing capability do not prove native call completion. |
| CALL-008 | Current SQL rename does not retarget a stale visible history row. Deletion while its callback contact preflight is held refuses before the replaced call-start port, then refresh shows Unknown contact. | `call_history_repository_test.dart`, `CALL-008 SQL rename...` | Native provider display-name rendering remains with VC-004/VC-010. Reuse that executor's call, rather than adding another device campaign for shared account routing. |

## Host execution and limits

Final source: `7572deae51a9acd19f9ff8c4a85724931b0c7f41`. Final focused runs
009–015 completed **43 distinct cases, all PASS, zero skips**: private SQL 4,
library SQL 4, picker adapter 2, full call-history file 13, selected composer/PDF
and size-preservation cases 6, unchanged download/continuity/forward preservation
8, full image-viewer file 6. This comprises 14 new cases, two strengthened cases
and 27 unchanged cases. Earlier subset runs are not added to these totals.
The matrix marks only the nine named shared-logic contracts strong/host_run;
the other 286 journeys are unchanged. Strong is coverage of the stated host
contract, not native execution or production release certification.

Run one focused Flutter process at a time with `--concurrency=1`, `nice -n 10`
and resource guards. Before every shared-host lease acquire, run the approved
read-only `scripts/lease_status.py` from the main checkout; known HELD means no
acquire. The ignored runner in `.codex-test-logs/astra-levers12/run_host.py`
locks only `mknoon.shared-native-build` using the wrapper's existing lock helper.
Importing that helper does not discover or control devices.

Final focused commands and receipts are recorded in the packet's validation
summary; the matrix audit is `016-lever1-matrix-audit.json`. First fixture
failures and the stopped incomplete precache attempt stay
in the same ignored evidence directory. Exit zero without test completion is
not PASS. An explicit baseline/local selection preview and metadata validation
do not execute their selected checks; omitted affected lanes remain NOT RUN.
No full host-all or release/signed-artifact verdict is implied by these joins.

The final explicit `5e1821e23 --local` preview selected 29 checks over 12 changed
rows, with zero unmapped changes. Metadata validation passed. A diagnostic
`mknoon_checks.py run --only bootstrap --jobs 1 --flutter-workers 1` completed
the three selected bootstrap files with **22 PASS, zero skips**; its child exit
was 0. The wrapper's overall exit was 3 / NOT RUN because the other 28 selected
checks, including contacts/workflow and broader affected lanes, were omitted.
Receipt: `.codex-test-logs/astra-levers12/bootstrap-wrapper/results.json`;
source head `7572deae5`, recorded working-tree identity
`b3a40b0a6af6803ef25bc9babc789e781b4b1f93f96e9c6bdeb8439b873317d5`.
This separate baseline result is not added to the 43 journey/preservation cases.

## Device executor rules

Only flutter_app runs the device legs. Reuse the
[Group C](astra-group-c-device-runbook.md) and
[Group D](astra-group-d-device-runbook.md) drivers and their owned cleanup.
Use the available Android pair for shared two-peer behavior; add iOS only for an
actual iOS boundary or explicitly requested parity. Unavailable hardware is N/A
under project policy. Preserve the existing physical-iPhone install, identity
and pairing; do not follow an older proof's uninstall/reset precondition there.

Keep exact source/build/configuration, first attempts, file-comparison receipts
and causal native observations in ignored artifacts. Mail only paths and
redacted conclusions. Per Kayan `m-17c52b26`, Android-receiver call directions may
use the approved no-hook energy proxy only; iPhone-receiver/content-proof rows
stay **needs a test-build audio hook (not approved now)**. Neither that proxy nor
this host packet certifies semantic bidirectional speech.
