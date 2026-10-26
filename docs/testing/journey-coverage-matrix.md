# Mknoon journey coverage matrix

Ranked-gap progress refreshed: 2026-10-26T14:45:24Z; source `97e66f64adb5287d837b3767a6d82a400f656929`. Original coverage-audit metadata and scoped updates retained: Audited source: `a502c06bc7b2a87c66e01495d4d2285f6731be3e`. Generated: 2026-10-20T14:42:18Z. Scoped Group B update: `f4005fbfa66391500dce2c2b82a6f325cc65934f` (2026-10-21). Scoped Group C host update: base `f14f7d369646b9877bc80c71f517494628f4fe2b`, tests `6ce42d583` (2026-10-22). Scoped Group C device execution: `0ee837d5d` by flutter_app (2026-10-22). Scoped Group D host update: tests `7ebe0608c` / `4365c0ae3` / `063aa72e2` (2026-10-22). The matching [YAML](journey-coverage-matrix.yaml) is the machine-readable source for this document.

295 representative journeys: **45 strong, 245 partial, 4 missing, 1 unknown**. All 103 catalog IDs are retained. The actual camera+caption/full-decode incident is explicit in MEDIA-002 and MEDIA-014. **This matrix does not certify a production release.**


Group C device evidence: source `0ee837d5d6b058977b22c09365fc706b38dfd1d3`, application base `f14f7d369646b9877bc80c71f517494628f4fe2b`, Pixel 6 debug / iPhone 13 release FLOW-log install-over builds. Evidence directory: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022`. Plain host rechecks on that source: contacts 3 PASS, camera 19 PASS / 1 pre-existing skip, calls 6 PASS, all exit 0 (`RESUME.md:50`; `focused.log` completion/rc markers 70/71, 12546/12547, 12562/12563; overall exit 0 at 12564). Astra performed no device work. First failed video download and text-entry harness correction remain visible. Audibility/native RTP and production-signed artifact proof remain unverified.

Lever 1 host joins: source `7572deae51a9acd19f9ff8c4a85724931b0c7f41`, nine shared-logic journeys now strong with actual host_run evidence; 43 distinct final cases PASS, zero skips, including 14 new and two strengthened cases. Separate bootstrap wrapper subset: 22 PASS across three files, child exit0; outer exit3/NOT RUN with28selected checks omitted. Native and signed-release boundaries remain explicit. See [host packet/runbook](astra-lever1-host-quickwins.md) and `header.lever1_host_run` in YAML. Its historical Android energy-proxy allowance is superseded by the owner decisions below.

Current owner decisions (2026-10-22): VC-009/011/014/015/017/018/019 and CALL-007 remain partial: **needs the test-build audio hook (not approved)**. The no-hook energy proxy is not feasible. All 32 Lever2 native oracle routes remain **NOT RUN / SOURCE_CAPTURE_NOT_WIRED**; see [device status](astra-lever2-device-status.md), line 3, and [call decision](lever3-run-a-call-device-evidence.md), line 78. These constraints preserve prior scoped Group C/D device observations and structural call proof.

Group D device evidence: flutter_app reports source `62450cba434f6f718f52472db6807026fed00071`, app base `f14f7d369646b9877bc80c71f517494628f4fe2b`, disposable Android debug package. Saved APK SHA256 `1bb4c9ab0f4141faf6d2d9f9ab5cb0f54a0d1ce5a55d4f5f2ff01f7c6336ac68` was hashed read-only; installation was not inspected by Astra. Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/SUMMARY.md:2`. That packet recorded five scoped device_run rows and the TRANSFER-011 blocked_environment attempt; the later 2026-10-23 TRANSFER-011 row now records scoped iOS-simulator receiver PASS with rating partial. All six ratings remain partial: group3-peer, mid-I/O/video, optical/duplicate-scan, confirmed camera-feedback failure and failed migration limits stay explicit. No new source/receiver oracle or release pass is inferred.

## Interpretation and execution

- Initial source/assertion/fake/registration audit was host-only at the original commit above. Subsequent scoped Group C and D device execution was performed by flutter_app; Astra only inspected saved evidence and changed documentation. No production code or release publication was changed by this update.
- 295 representative journeys in 19 logical families reconcile all 19 lib/features folders and all 103 catalog IDs. Not an exhaustive platform/network/state/format Cartesian product. Every test entry is scoped to its actual assertion and doubles; literal case index was navigation only.
- Ratings describe coverage quality: strong means substantive causal assertions for the stated scoped contract (sometimes several complementary cases), partial means meaningful subset with material remaining seams, missing means no qualifying complete assertion for the defining boundary, unknown means reachability/policy unresolved or inactive future capability. Strong is not passed or end-to-end unless explicitly stated.
- Execution records actual scoped legs: Group C has five device_run rows and CR-009 skipped_waiting_ui_update; Group D retains its initial partial/failure limits; TRANSFER-011 now adds the later scoped iOS-simulator receiver device_run PASS while retaining the earlier block. Nine Lever1 shared contracts have host_run evidence. None is a complete release verdict: per-row native/content/artifact gaps remain and focused host results stay separate.
- Offline enforced-lockfile dependency resolution exited 0. First pubget gate and update-verifier/safety-support test gates held with exit 75 before launch; preserve logs. Held gates are neither assertion failures nor skipped test executions. No analyzer, host-all, native tests or device/manual campaign ran in the initial audit; later scoped device evidence is recorded separately.
- The first static preview reported 34 fallback checks and unmapped YAML; preserve that initial result. Follow-up adds only the exact docs/testing/journey-coverage-matrix.yaml path to existing documentation_only rules; Markdown already matches *.md. Current explicit-base/local wrapper plan and metadata validation are retained with the handoff. No new check was added.
- Initial ordinary change-plan attempts were held before launch (change-plan.log, change-plan-v2.log). Static preview omitted toolchain capture. The final metadata-only wrapper plan captures version information and selection without launching checks or device discovery; selected checks remain unexecuted.
- The initial audit identified source-disabled CONTACT presentation and malformed/future QR cases. Group B now enables and passes the CR-003/005/014/025 host guards; other per-row known gaps remain separate. GIF manual default is overridden true by its registered media runner.
- Registration does not establish CI execution. Host-all discovers test/**/*_test.dart except performance; native/SIMS/legacy dispatch described per entry. CI job condition/trusted-event and actual external vars/runs were not inspected. No registered lane means not_run, never implicit pass.
- Snapshot catalog source SHA256 57f78df40631adcaa1da16eb743bd0f4570c378d6af11be60affb43c4a9ad64c, 103 IDs; read-only live inventory snapshot generated 2026-10-20T11:46:09.388Z head a502c06bc. Linked test files, notes and old PASS labels are not substituted for reviewed assertions or fresh evidence.
- Owner-reported stock iOS 1.0.1 (125) / Android 125 camera Original incident and reported compressed/default nonreproduction are reports, not this audit results. Actual original MIME/encoded bytes remain unknown; do not assume HEIC. New strict-custody cohort proofs cannot certify stock125 legacy behavior.
- Default OFF linked authoring/multi-device/strict-custody/document-send/rotate-on-add cohorts are separate from default production behavior and retained durable authority. Existing PDF receive/open remains supported with send flag off. On-join metadata resync defaults ON. Full phrase-restore group convergence and dormant Posts are separate planned/unreachable scope.
- Available-target project policy applies to all proposed device work: unavailable target/version/accessory/topology is N/A (target unavailable by project policy), not a release blocker. This agent did not discover/control devices; flutter_app owns execution. Actual previous published baseline and exact signed candidate/manual evidence were not supplied.

- Scoped Group B host update at f4005fbfa66391500dce2c2b82a6f325cc65934f (2026-10-21): CR-003/005/014/025 strong; VC-013 partial with capability still planned; NAV-011 remains partial for unproven invite/recovery surfaces. Focused validation: 14 files, 200 passed, 0 skipped; first failures and one resource-aborted run retained under .codex-test-logs/groupB-fixes/. Full journey execution remains not_run; broad affected lanes, native/device, analyzer and full host-all were not run.

- Scoped Group C host update on base f14f7d369646b9877bc80c71f517494628f4fe2b, tests commit 6ce42d583 (2026-10-22): MEDIA-002/003/014, DC-011, VC-015 and CR-009 partial. Three focused files: 28 passed, one pre-existing mixed-relay KNOWN GAP skip; eight new cases passed. First full camera attempt 005 resource-aborted at swapouts +37768 pages with zero completed cases; final 006 passed at unchanged swapouts. Evidence: .codex-test-logs/astra-groupCD. Appium runbook supplied, all actual cross-platform journeys remain not_run; CR-009 native fresh-add route waits for UI-Update. No native build/device/audio/manual proof, broad affected lanes or full host-all run.

- Scoped Group D host update on base f14f7d369, following Group C commit 0ee837d5d, with test commits 7ebe0608c / 4365c0ae3 / 063aa72e2 (2026-10-22): DC-002, GC-005, MEDIA-018, MEDIA-010, CONTACT-001 and TRANSFER-011 partial. Focused direct probes: 9 passed, one new case-scoped ASTRA-D-1 KNOWN GAP skip; 6 new cases passed and one existing migration chain now decodes a real imported photo. Desired camera feedback was causally RED in 011 and routed to Codex after release 126; no app code fixed here. Test setup failures 010/012/015/017 are retained separately. Evidence: .codex-test-logs/astra-groupCD. Actual Android kills, OS grant/deny, live relay/crypto, mobile video/voice/PDF/viewers and signed-candidate evidence remain not_run. Android Appium steps supplied; broader lanes, analyzer and full host-all not run.

## Feature coverage

| Feature | Strong | Partial | Missing | Unknown | Biggest gap |
| --- | ---: | ---: | ---: | ---: | --- |
| IDENTITY — Onboarding, identity and recovery | 1 | 9 | 0 | 0 | Native secure-store/bridge failure and actual offline cold-start continuity are split from route/identity tests; phrase restore is not historical group/media recovery. |
| CONTACT — QR, contact requests, profiles and contact management | 7 | 29 | 0 | 0 | Actual scanner cancellation/permission recovery and iPhone/Android reciprocal contact creation remain unproven; declined-envelope replay is still a separate known gap. |
| CHAT — Direct text and conversation state | 2 | 11 | 0 | 0 | Actual native both-peer process death and deployed relay preservation for 100 messages remain unrun; host SQL/runtime reopen now proves the exact transcript. Full iPhone/Android native text/media interoperability remains separate. |
| MEDIA — Direct/group media, voice, private viewing and libraries | 10 | 34 | 1 | 0 | Actual iPhone store 125 Original camera image plus caption to Android 125 full decode/open remains missing for online relay and offline inbox; real camera bytes/MIME are unknown. |
| GROUP — Group membership, messaging and management | 2 | 22 | 2 | 0 | Accepted-text sender process death, complete cross-platform media/membership parity and eight simultaneous app actors are not supplied by membership-only kills or small fake fanout. |
| CALL — Voice calls, lifecycle, privacy and history | 11 | 24 | 1 | 0 | Actual cross-platform audible call, sustained audio soak, OS suspended/killed incoming delivery, muted-content privacy and hard-kill native cleanup remain distinct gaps. |
| INTRO — Introductions and mutual consent | 2 | 10 | 0 | 0 | Host SQL/consent tests do not establish a complete real network/OS restart journey through both approvals and first reciprocal chat. |
| NOTIFY — Notification ingress, routing, unread and privacy | 3 | 13 | 0 | 0 | Actual signed OS/provider ingress, killed-before-send delivery and iOS extension/lockscreen evidence remain separate from exact local routing/read policy tests. |
| NAV — Feed, Orbit, rings, search and navigation | 0 | 10 | 0 | 1 | Manual Inner-Circle membership/order editor reachability is unresolved; current automatic recency membership and sculpt geometry must not imply that shipped editor. |
| SHARE — External share and received-media forwarding | 0 | 11 | 0 | 0 | Native share URI lifetime/permission/cancel and actual recipient full decode/play across selected targets are not joined by fake ingress/forwarding tests. |
| SETTINGS — Profile, preferences and support | 2 | 10 | 0 | 0 | Preference/profile host boundaries do not prove native picker/clipboard/mail, actual peer avatar convergence or auto-download policy on received full media. |
| TRANSFER — Move Account between phones | 1 | 15 | 0 | 0 | Host loopback transfer now opens a real imported photo through the host codec. Native mobile video/voice/PDF/viewers, secure keychain/SQLCipher and complete candidate cutover remain unverified. |
| LINKED — Flag-gated linked devices and durable linked state | 1 | 12 | 0 | 0 | Default OFF authoring flags, durable authority and actual multi-installation native media delivery must be separated; full phrase-restore group convergence is unfinished. |
| UPDATE — Signed update checks and update-required UI | 3 | 6 | 0 | 0 | Signed verification/cache and shared required-gate recovery have host assertions; actual OS background wake, external store behavior and the exact installed candidate remain separate. |
| TRANSPORT — Cross-cutting discovery, reconnect and local/offline routing | 0 | 8 | 0 | 0 | Real host Go transport checks do not prove actual native local discovery/airplane/radio handover and recipient media continuity under OS lifecycle. |
| DIAG — User-controlled diagnostics and recovery reporting | 0 | 5 | 0 | 0 | Host redaction/export policy lacks joined actual platform export failure/cancel while live communication and microphone ownership remain intact. |
| LOCAL — Local storage, identity secrecy and account erasure | 0 | 5 | 0 | 0 | Native encrypted DB/keychain/first-unlock/erase and actual published-to-candidate upgrade custody are separate from host SQL/files and fake secure storage. |
| ACCESS — Localization, accessibility and usable interaction | 0 | 6 | 0 | 0 | Host semantics/layout/RTL/contrast tests do not establish actual screen-reader/keyboard/native input and cross-platform delivered-content accessibility. |
| RELEASE — Upgrade and whole-app preservation | 0 | 5 | 0 | 0 | No actual previous published revision, exact signed candidate/artifact/configuration and required device/manual evidence supplied for release certification. |

## Source entrypoint reconciliation

These 19 folders cover the implementation inventory. UI callback names are navigation anchors; they do not prove that a dormant/unwired action ships. Application composition/root/lifecycle, native ingress and shared viewers are mapped through the owning journeys.

| Source family | Journey family / representative rows |
| --- | --- |
| [lib/features/account_migration/](../../lib/features/account_migration/) | TRANSFER / DC-019, TRANSFER-001–015; LOCAL-003 erasure |
| [lib/features/call/](../../lib/features/call/) | CALL / VC-001–028, CALL-001–008 |
| [lib/features/contact_profile/](../../lib/features/contact_profile/) | CONTACT / CONTACT-002–010; LINKED-004 trust |
| [lib/features/contact_request/](../../lib/features/contact_request/) | CONTACT / CR-001–026 and CONTACT-001–010; INTRO consent repair |
| [lib/features/contacts/](../../lib/features/contacts/) | CONTACT / management/block/delete/archive; NAV contact projections |
| [lib/features/conversation/](../../lib/features/conversation/) | CHAT / direct text/state; MEDIA / ordinary/private voice/viewers/library; CALL-001 |
| [lib/features/feed/](../../lib/features/feed/) | NAV / Feed/focus/dismiss; CHAT / quick reply; NOTIFY / reveal |
| [lib/features/groups/](../../lib/features/groups/) | GROUP / membership/admin/history; MEDIA / group/private; LINKED / gated groups; NOTIFY |
| [lib/features/home/](../../lib/features/home/) | IDENTITY / first contact/name; CONTACT / my QR and scanner; NAV shell |
| [lib/features/identity/](../../lib/features/identity/) | IDENTITY / creation/phrase restore; LINKED / gated secondary setup; TRANSFER entry |
| [lib/features/introduction/](../../lib/features/introduction/) | INTRO / IN-001–010 and INTRO-001–003 |
| [lib/features/orbit/](../../lib/features/orbit/) | NAV / search/filters/rings; CONTACT / request/management; GROUP / invites/exit; CALL / Calls entry |
| [lib/features/p2p/](../../lib/features/p2p/) | CHAT / direct messaging; TRANSPORT / routing/reconnect; MEDIA custody; CALL signaling |
| [lib/features/posts/](../../lib/features/posts/) | Planned/unreachable Posts UI; reachable post notification is NOTIFY-010 intentional Feed fallback |
| [lib/features/push/](../../lib/features/push/) | NOTIFY / ingress/read/routing/privacy; CALL / wake; UPDATE / check-now |
| [lib/features/qr_code/](../../lib/features/qr_code/) | CONTACT / scan/display/peer binding; LINKED / linked QR; TRANSFER / migration QR |
| [lib/features/settings/](../../lib/features/settings/) | SETTINGS / preferences/profile/support; UPDATE; DIAG; LOCAL; TRANSFER entry |
| [lib/features/share/](../../lib/features/share/) | SHARE / external and received-media forwarding; MEDIA / egress/library |
| [lib/features/update_check/](../../lib/features/update_check/) | UPDATE / signed verifier/cache/gate/background/store |

### Screen callback inventory

| Production screen / wired entry | Owning journey family |
| --- | --- |
| [lib/features/account_migration/presentation/screens/account_migration_blocked_screen.dart](../../lib/features/account_migration/presentation/screens/account_migration_blocked_screen.dart) | TRANSFER / DC-019, TRANSFER-001–015; LOCAL-003 erasure |
| [lib/features/account_migration/presentation/screens/account_migration_journey_screen.dart](../../lib/features/account_migration/presentation/screens/account_migration_journey_screen.dart) | TRANSFER / DC-019, TRANSFER-001–015; LOCAL-003 erasure |
| [lib/features/account_migration/presentation/screens/account_migration_journey_wired.dart](../../lib/features/account_migration/presentation/screens/account_migration_journey_wired.dart) | TRANSFER / DC-019, TRANSFER-001–015; LOCAL-003 erasure |
| [lib/features/call/presentation/screens/incoming_call_screen.dart](../../lib/features/call/presentation/screens/incoming_call_screen.dart) | CALL / VC-001–028, CALL-001–008 |
| [lib/features/call/presentation/screens/outgoing_call_screen.dart](../../lib/features/call/presentation/screens/outgoing_call_screen.dart) | CALL / VC-001–028, CALL-001–008 |
| [lib/features/contact_profile/presentation/screens/contact_profile_screen.dart](../../lib/features/contact_profile/presentation/screens/contact_profile_screen.dart) | CONTACT / CONTACT-002–010; LINKED-004 trust |
| [lib/features/conversation/presentation/screens/conversation_screen.dart](../../lib/features/conversation/presentation/screens/conversation_screen.dart) | CHAT / direct text/state; MEDIA / ordinary/private voice/viewers/library; CALL-001 |
| [lib/features/conversation/presentation/screens/conversation_wired.dart](../../lib/features/conversation/presentation/screens/conversation_wired.dart) | CHAT / direct text/state; MEDIA / ordinary/private voice/viewers/library; CALL-001 |
| [lib/features/conversation/presentation/screens/direct_private_media_viewer.dart](../../lib/features/conversation/presentation/screens/direct_private_media_viewer.dart) | CHAT / direct text/state; MEDIA / ordinary/private voice/viewers/library; CALL-001 |
| [lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart](../../lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart) | CHAT / direct text/state; MEDIA / ordinary/private voice/viewers/library; CALL-001 |
| [lib/features/feed/presentation/screens/feed_screen.dart](../../lib/features/feed/presentation/screens/feed_screen.dart) | NAV / Feed/focus/dismiss; CHAT / quick reply; NOTIFY / reveal |
| [lib/features/feed/presentation/screens/feed_wired.dart](../../lib/features/feed/presentation/screens/feed_wired.dart) | NAV / Feed/focus/dismiss; CHAT / quick reply; NOTIFY / reveal |
| [lib/features/groups/presentation/screens/contact_picker_screen.dart](../../lib/features/groups/presentation/screens/contact_picker_screen.dart) | GROUP / membership/admin/history; MEDIA / group/private; LINKED / gated groups; NOTIFY |
| [lib/features/groups/presentation/screens/create_group_picker_screen.dart](../../lib/features/groups/presentation/screens/create_group_picker_screen.dart) | GROUP / membership/admin/history; MEDIA / group/private; LINKED / gated groups; NOTIFY |
| [lib/features/groups/presentation/screens/group_conversation_screen.dart](../../lib/features/groups/presentation/screens/group_conversation_screen.dart) | GROUP / membership/admin/history; MEDIA / group/private; LINKED / gated groups; NOTIFY |
| [lib/features/groups/presentation/screens/group_conversation_wired.dart](../../lib/features/groups/presentation/screens/group_conversation_wired.dart) | GROUP / membership/admin/history; MEDIA / group/private; LINKED / gated groups; NOTIFY |
| [lib/features/groups/presentation/screens/group_info_screen.dart](../../lib/features/groups/presentation/screens/group_info_screen.dart) | GROUP / membership/admin/history; MEDIA / group/private; LINKED / gated groups; NOTIFY |
| [lib/features/groups/presentation/screens/group_info_wired.dart](../../lib/features/groups/presentation/screens/group_info_wired.dart) | GROUP / membership/admin/history; MEDIA / group/private; LINKED / gated groups; NOTIFY |
| [lib/features/groups/presentation/screens/group_shared_media_library_screen.dart](../../lib/features/groups/presentation/screens/group_shared_media_library_screen.dart) | GROUP / membership/admin/history; MEDIA / group/private; LINKED / gated groups; NOTIFY |
| [lib/features/groups/presentation/screens/linked_group_conversation_wired.dart](../../lib/features/groups/presentation/screens/linked_group_conversation_wired.dart) | GROUP / membership/admin/history; MEDIA / group/private; LINKED / gated groups; NOTIFY |
| [lib/features/home/presentation/screens/first_time_experience_screen.dart](../../lib/features/home/presentation/screens/first_time_experience_screen.dart) | IDENTITY / first contact/name; CONTACT / my QR and scanner; NAV shell |
| [lib/features/home/presentation/screens/first_time_experience_wired.dart](../../lib/features/home/presentation/screens/first_time_experience_wired.dart) | IDENTITY / first contact/name; CONTACT / my QR and scanner; NAV shell |
| [lib/features/identity/presentation/screens/identity_choice_screen.dart](../../lib/features/identity/presentation/screens/identity_choice_screen.dart) | IDENTITY / creation/phrase restore; LINKED / gated secondary setup; TRANSFER entry |
| [lib/features/identity/presentation/screens/identity_choice_wired.dart](../../lib/features/identity/presentation/screens/identity_choice_wired.dart) | IDENTITY / creation/phrase restore; LINKED / gated secondary setup; TRANSFER entry |
| [lib/features/identity/presentation/screens/identity_progress_screen.dart](../../lib/features/identity/presentation/screens/identity_progress_screen.dart) | IDENTITY / creation/phrase restore; LINKED / gated secondary setup; TRANSFER entry |
| [lib/features/identity/presentation/screens/linked_device_setup_wired.dart](../../lib/features/identity/presentation/screens/linked_device_setup_wired.dart) | IDENTITY / creation/phrase restore; LINKED / gated secondary setup; TRANSFER entry |
| [lib/features/identity/presentation/screens/mnemonic_input_screen.dart](../../lib/features/identity/presentation/screens/mnemonic_input_screen.dart) | IDENTITY / creation/phrase restore; LINKED / gated secondary setup; TRANSFER entry |
| [lib/features/identity/presentation/screens/mnemonic_input_wired.dart](../../lib/features/identity/presentation/screens/mnemonic_input_wired.dart) | IDENTITY / creation/phrase restore; LINKED / gated secondary setup; TRANSFER entry |
| [lib/features/introduction/presentation/screens/friend_picker_screen.dart](../../lib/features/introduction/presentation/screens/friend_picker_screen.dart) | INTRO / IN-001–010 and INTRO-001–003 |
| [lib/features/introduction/presentation/screens/friend_picker_wired.dart](../../lib/features/introduction/presentation/screens/friend_picker_wired.dart) | INTRO / IN-001–010 and INTRO-001–003 |
| [lib/features/introduction/presentation/screens/sent_confirmation_screen.dart](../../lib/features/introduction/presentation/screens/sent_confirmation_screen.dart) | INTRO / IN-001–010 and INTRO-001–003 |
| [lib/features/introduction/presentation/screens/sent_confirmation_wired.dart](../../lib/features/introduction/presentation/screens/sent_confirmation_wired.dart) | INTRO / IN-001–010 and INTRO-001–003 |
| [lib/features/orbit/presentation/screens/orbit_screen.dart](../../lib/features/orbit/presentation/screens/orbit_screen.dart) | NAV / search/filters/rings; CONTACT / request/management; GROUP / invites/exit; CALL / Calls entry |
| [lib/features/orbit/presentation/screens/orbit_wired.dart](../../lib/features/orbit/presentation/screens/orbit_wired.dart) | NAV / search/filters/rings; CONTACT / request/management; GROUP / invites/exit; CALL / Calls entry |
| [lib/features/posts/presentation/screens/posts_screen.dart](../../lib/features/posts/presentation/screens/posts_screen.dart) | Planned/unreachable Posts UI; reachable post notification is NOTIFY-010 intentional Feed fallback |
| [lib/features/posts/presentation/screens/posts_wired.dart](../../lib/features/posts/presentation/screens/posts_wired.dart) | Planned/unreachable Posts UI; reachable post notification is NOTIFY-010 intentional Feed fallback |
| [lib/features/qr_code/presentation/screens/qr_display_screen.dart](../../lib/features/qr_code/presentation/screens/qr_display_screen.dart) | CONTACT / scan/display/peer binding; LINKED / linked QR; TRANSFER / migration QR |
| [lib/features/qr_code/presentation/screens/qr_display_wired.dart](../../lib/features/qr_code/presentation/screens/qr_display_wired.dart) | CONTACT / scan/display/peer binding; LINKED / linked QR; TRANSFER / migration QR |
| [lib/features/qr_code/presentation/screens/qr_scanner_screen.dart](../../lib/features/qr_code/presentation/screens/qr_scanner_screen.dart) | CONTACT / scan/display/peer binding; LINKED / linked QR; TRANSFER / migration QR |
| [lib/features/qr_code/presentation/screens/qr_scanner_wired.dart](../../lib/features/qr_code/presentation/screens/qr_scanner_wired.dart) | CONTACT / scan/display/peer binding; LINKED / linked QR; TRANSFER / migration QR |
| [lib/features/settings/presentation/screens/settings_screen.dart](../../lib/features/settings/presentation/screens/settings_screen.dart) | SETTINGS / preferences/profile/support; UPDATE; DIAG; LOCAL; TRANSFER entry |
| [lib/features/settings/presentation/screens/settings_wired.dart](../../lib/features/settings/presentation/screens/settings_wired.dart) | SETTINGS / preferences/profile/support; UPDATE; DIAG; LOCAL; TRANSFER entry |
| [lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart](../../lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart) | SHARE / external and received-media forwarding; MEDIA / egress/library |
| [lib/features/share/presentation/screens/group_media_batch_forward_picker_screen.dart](../../lib/features/share/presentation/screens/group_media_batch_forward_picker_screen.dart) | SHARE / external and received-media forwarding; MEDIA / egress/library |
| [lib/features/share/presentation/screens/share_target_picker_screen.dart](../../lib/features/share/presentation/screens/share_target_picker_screen.dart) | SHARE / external and received-media forwarding; MEDIA / egress/library |
| [lib/features/share/presentation/screens/share_target_picker_wired.dart](../../lib/features/share/presentation/screens/share_target_picker_wired.dart) | SHARE / external and received-media forwarding; MEDIA / egress/library |

## Detailed journeys

### IDENTITY — Onboarding, identity and recovery

#### IDENTITY-001 — Create identity and reach first-time home without duplicate creation

**Coverage:** partial. **Execution:** not_run. **Catalog:** RG-002.

**Steps**

1. Open the new-user choice.
2. Tap create repeatedly while generation is pending.
3. Observe progress and successful handoff.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** One identity creation reaches the first-time app handoff after a visible progress frame.

**Inspected test evidence**

- [test/features/identity/presentation/screens/identity_choice_wired_test.dart](../../test/features/identity/presentation/screens/identity_choice_wired_test.dart) — `successful generation hands off to main from the progress route context` (widget).
  - Real: identity choice/progress widgets; generation use case; Navigator.
  - Faked: identity/ML-KEM bridge callbacks; identity repository; main replaced by first-time setup stand-in.
  - Proves / registration: test/features/identity/presentation/screens/identity_choice_wired_test.dart:251: A successful callback saves the fixture identity and navigates from the progress context; not the real native identity/storage/onboarding chain. Registered: affected-identity, host-all.
- [test/features/identity/presentation/screens/identity_choice_wired_test.dart](../../test/features/identity/presentation/screens/identity_choice_wired_test.dart) — `repeated taps while generation is in flight do not push a second progress route` (widget).
  - Real: real generation guard and progress route.
  - Faked: pending bridge callback; repository.
  - Proves / registration: test/features/identity/presentation/screens/identity_choice_wired_test.dart:360: Repeated taps produce one progress route and one generation operation. Registered: affected-identity, host-all.
- [test/features/identity/presentation/screens/identity_choice_wired_test.dart](../../test/features/identity/presentation/screens/identity_choice_wired_test.dart) — `identity generation waits until after the pushed progress route gets a frame` (widget).
  - Real: real widget frame and progress route.
  - Faked: generation/ML-KEM callbacks; repository.
  - Proves / registration: test/features/identity/presentation/screens/identity_choice_wired_test.dart:103: Generation starts after the progress route has rendered; this is not process-death recovery. Registered: affected-identity, host-all.

**Remaining gaps**

- No single assertion joins actual native entropy/ML-KEM, durable secure storage and the real first-time home.

#### IDENTITY-002 — Cancel or interrupt identity generation; restore a truthful startup state

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Begin identity creation.
2. Interrupt the process while generating or saving.
3. Restart and inspect the recoverable startup state.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: creation interrupted/relaunch; input: as described; recovery: partial generation or save.

**Expected:** An interruption must not expose an inconsistent partially saved account; generation itself has no supported cancel action.

**Inspected test evidence**

- [test/features/identity/presentation/screens/identity_choice_wired_test.dart](../../test/features/identity/presentation/screens/identity_choice_wired_test.dart) — `identity generation waits until after the pushed progress route gets a frame` (widget).
  - Real: real widget frame and progress route.
  - Faked: generation/ML-KEM callbacks; repository.
  - Proves / registration: test/features/identity/presentation/screens/identity_choice_wired_test.dart:103: Generation starts after the progress route has rendered; this is not process-death recovery. Registered: affected-identity, host-all.
- [test/core/bootstrap/application_bootstrap_test.dart](../../test/core/bootstrap/application_bootstrap_test.dart) — `intentional startup cancellation launches no completed app` (unit).
  - Real: bootstrap cancellation control flow.
  - Faked: bootstrap throwing ApplicationBootstrapCancelled; host.
  - Proves / registration: test/core/bootstrap/application_bootstrap_test.dart:182: An explicitly injected bootstrap cancellation launches no completed app; no interrupted identity write/relaunch is asserted. Registered: bootstrap, host-all.

**Remaining gaps**

- lib/features/identity/presentation/screens/identity_progress_screen.dart:36 prevents Back; no user cancel control exists.
- Bootstrap cancellation and first-frame tests do not assert process death between identity/key writes and recovery.

**Open questions**

- What recovery state is required when the OS terminates creation between secure-key and database persistence?

#### IDENTITY-003 — Restore a valid recovery phrase and open existing identity

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Enter a valid twelve-word recovery phrase.
2. Normalize and restore keys, then save the identity.
3. Open the restored account.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: valid phrase, mixed case/whitespace; recovery: n/a.

**Expected:** The phrase restores the same account identity and the app opens a truthful restored state.

**Inspected test evidence**

- [go-mknoon/identity/identity_test.go](../../go-mknoon/identity/identity_test.go) — `TestRestoreIdentity_SameMnemonicProducesIdenticalIdentity` (unit).
  - Real: real BIP39/Ed25519 identity generation and restoration.
  - Faked: none identified.
  - Proves / registration: go-mknoon/identity/identity_test.go:89: A generated phrase restores exactly the same peer/public/private identity. Registered go-core ./...; Flutter FFI and secure storage are outside this process. Registered: see cited native runner/manifest.
- [test/features/identity/application/restore_identity_use_case_test.dart](../../test/features/identity/application/restore_identity_use_case_test.dart) — `success: restores identity with normalized mnemonic` (unit).
  - Real: restore use case and normalization/progress.
  - Faked: core restore and ML-KEM results; repository.
  - Proves / registration: test/features/identity/application/restore_identity_use_case_test.dart:69: Normalizes the words, saves supplied identity/key material and emits generating/saving stages; does not derive real keys. Registered: affected-identity, host-all.
- [test/features/identity/presentation/screens/mnemonic_input_wired_restore_notice_test.dart](../../test/features/identity/presentation/screens/mnemonic_input_wired_restore_notice_test.dart) — `shows the honest notice when restore hydrates zero groups` (widget).
  - Real: MnemonicInputWired submit flow and honest restore notice.
  - Faked: identity restore and ML-KEM callbacks; identity/group repositories.
  - Proves / registration: test/features/identity/presentation/screens/mnemonic_input_wired_restore_notice_test.dart:85: Submitting the phrase with zero restored groups shows the limited-history/group recovery notice then navigates; existing-local-groups case suppresses it. Registered: affected-identity, host-all.

**Remaining gaps**

- Real cryptographic restoration and Flutter navigation/storage are separate tests; native bridge, secure store and relaunch are not joined.

#### IDENTITY-004 — Reject malformed, wrong-length or invalid-checksum recovery phrases

**Coverage:** strong. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Enter too few/many words or a checksum-invalid twelve-word phrase.
2. Submit restoration.
3. Observe validation failure without a successful account save.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: wrong word count or invalid checksum; recovery: n/a.

**Expected:** Malformed phrases are rejected by word-count and real checksum validation, and core rejection maps to the invalid-phrase result.

**Inspected test evidence**

- [test/features/identity/application/restore_identity_use_case_test.dart](../../test/features/identity/application/restore_identity_use_case_test.dart) — `invalidMnemonicFormat: too few words` (unit).
  - Real: Dart word-count validation.
  - Faked: bridge/key generator; repository.
  - Proves / registration: test/features/identity/application/restore_identity_use_case_test.dart:89: Rejects the malformed word count without saving; companion too-many-words case covers thirteen words. Registered: affected-identity, host-all.
- [go-mknoon/identity/identity_test.go](../../go-mknoon/identity/identity_test.go) — `TestRestoreIdentity_FailsForInvalidChecksum` (unit).
  - Real: real mnemonic checksum validation.
  - Faked: none identified.
  - Proves / registration: go-mknoon/identity/identity_test.go:138: Rejects a twelve-word phrase with an invalid checksum; registered go-core ./.... Registered: see cited native runner/manifest.
- [test/features/identity/application/restore_identity_use_case_test.dart](../../test/features/identity/application/restore_identity_use_case_test.dart) — `invalidMnemonicCore: bridge returns INVALID_MNEMONIC` (unit).
  - Real: Dart core-error mapping.
  - Faked: INVALID_MNEMONIC bridge result.
  - Proves / registration: test/features/identity/application/restore_identity_use_case_test.dart:112: Maps a core rejection to invalidMnemonicCore; actual checksum rejection is independently tested in Go. Registered: affected-identity, host-all.

**Remaining gaps**

- Strong is scoped to input validation and failure mapping; a real native UI/FFI round trip is not executed.

#### IDENTITY-005 — Handle secure-store, database and bridge startup failures with retryable UI

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Fail identity generation, key/database persistence or bootstrap preparation.
2. Observe a bounded error/Retry state.
3. Retry preparation and finish once.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: bridge/save/preparation failures; recovery: Retry.

**Expected:** Failure remains visible and retryable without duplicate preparation or a false successful identity handoff.

**Inspected test evidence**

- [test/features/identity/presentation/screens/identity_choice_wired_test.dart](../../test/features/identity/presentation/screens/identity_choice_wired_test.dart) — `core lib failure dismisses progress route and shows failed to generate identity snackbar` (widget).
  - Real: identity UI and failure mapping.
  - Faked: bridge error result; repository.
  - Proves / registration: test/features/identity/presentation/screens/identity_choice_wired_test.dart:295: Core failure returns to the choice screen with the generation error; companion DB failure case asserts save error. Registered: affected-identity, host-all.
- [test/features/identity/presentation/screens/identity_choice_wired_test.dart](../../test/features/identity/presentation/screens/identity_choice_wired_test.dart) — `db save failure dismisses progress route and shows failed to save identity snackbar` (widget).
  - Real: identity UI and save-error mapping.
  - Faked: failing repository; bridge key results.
  - Proves / registration: test/features/identity/presentation/screens/identity_choice_wired_test.dart:328: Injected save failure dismisses progress and shows the save error; secure store/SQLite failure is not induced. Registered: affected-identity, host-all.
- [test/core/bootstrap/application_bootstrap_test.dart](../../test/core/bootstrap/application_bootstrap_test.dart) — `bounded startup failure exposes Retry and resumes one preparation` (widget).
  - Real: real bootstrap orchestration and Retry widget.
  - Faked: recoverable bootstrap preparation; prepared app/root; host.
  - Proves / registration: test/core/bootstrap/application_bootstrap_test.dart:118: Injected preparation failure renders Retry, disables duplicate retry, and completes one preparation/post-launch; not a real native database/keychain fault. Registered: bootstrap, host-all.

**Remaining gaps**

- Injected callbacks/repositories cover error paths; actual secure-store/SQLite/Go initialization faults and durable restart recovery are not joined.

#### IDENTITY-006 — Grant, deny or skip the onboarding microphone permission step

**Coverage:** partial. **Execution:** not_run. **Catalog:** RG-002.

**Steps**

1. Reach microphone onboarding with granted, denied or permanently denied status.
2. Choose Allow, Not now or Back.
3. Finish onboarding after grant/denial/error.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: granted/denied/permanently-denied/error; recovery: skip or denial.

**Expected:** The optional permission step never blocks onboarding and does not repeatedly request permanently denied access.

**Inspected test evidence**

- [test/features/identity/presentation/screens/onboarding_mic_permission_step_test.dart](../../test/features/identity/presentation/screens/onboarding_mic_permission_step_test.dart) — `allow asks once and onboarding completes when granted` (widget).
  - Real: real onboarding permission dialog and completion.
  - Faked: FakeMicPermissionGateway.
  - Proves / registration: test/features/identity/presentation/screens/onboarding_mic_permission_step_test.dart:70: Allow asks once; adjacent denied/permanently-denied/Not now/Back/error cases assert onboarding completes without blocking. No native permission sheet. Registered: affected-identity, host-all.

**Remaining gaps**

- All platform statuses/prompts come from FakeMicPermissionGateway; no native OS permission or later voice-use recovery is asserted.

#### IDENTITY-007 — Restart after onboarding; retain identity and choose the correct home

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Complete onboarding with a local identity and contacts.
2. Close and restart the app.
3. Choose returning-user home from durable local state.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: cold restart; input: as described; recovery: persisted identity/contact state.

**Expected:** A retained identity chooses the correct home without generating another identity.

**Inspected test evidence**

- [test/features/identity/presentation/screens/startup_router_test.dart](../../test/features/identity/presentation/screens/startup_router_test.dart) — `returning cold start after reboot shows persisted conversation history before network warm completion` (unit).
  - Real: decideStartupRoute.
  - Faked: identity/contact repositories; no widget tree or networking.
  - Proves / registration: test/features/identity/presentation/screens/startup_router_test.dart:138: Despite its broad name, only asserts hasIdentityWithContacts from fake local records; does not display persisted history or reboot an app. Registered: affected-identity, host-all.

**Remaining gaps**

- The cited startup contract tests fake repositories and only route decisions; actual durable storage, app restart and rendered home are not asserted together.

#### IDENTITY-008 — First-time user edits their display name and scans first contact

**Coverage:** partial. **Execution:** not_run. **Catalog:** RG-002.

**Steps**

1. Open first-time home.
2. Edit and submit the display name.
3. Use the first-contact scan affordance.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: edited display name and first-contact QR; recovery: n/a.

**Expected:** The edited name is saved and QR regenerated; scanning a valid contact begins the correct contact flow.

**Inspected test evidence**

- [test/features/home/presentation/screens/first_time_experience_wired_test.dart](../../test/features/home/presentation/screens/first_time_experience_wired_test.dart) — `updates username and regenerates QR` (widget).
  - Real: first-time UI, edit/submit action, QR generation orchestration.
  - Faked: identity repository; signing bridge; platform services.
  - Proves / registration: test/features/home/presentation/screens/first_time_experience_wired_test.dart:260: Editing Alice to Bob saves Bob and calls signing again; no real scanner/camera or remote acceptance. Registered: affected-surfaces, host-all.
- [test/features/home/presentation/screens/first_time_experience_wired_test.dart](../../test/features/home/presentation/screens/first_time_experience_wired_test.dart) — `scan button exists and is tappable` (widget).
  - Real: rendered first-time scan affordance.
  - Faked: repositories and signing bridge.
  - Proves / registration: test/features/home/presentation/screens/first_time_experience_wired_test.dart:293: Asserts card and scan icons exist; does not tap/scan an actual contact QR despite the test title. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Edit/save/QR-call assertions exist; the scan case only checks rendered affordances. Actual camera scan and remote contact acceptance are separate evidence.

#### IDENTITY-009 — Restoring a phrase preserves the account identity without promising historical messages or group keys

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Restore a valid phrase into an installation without local groups/history.
2. Read the limited-recovery notice.
3. Continue with the same account identity.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: phrase-only restore; no local groups; recovery: account identity without old message/group state.

**Expected:** The restored account identity is stable and UI does not promise historical messages or missing group keys.

**Inspected test evidence**

- [go-mknoon/identity/identity_test.go](../../go-mknoon/identity/identity_test.go) — `TestRestoreIdentity_SameMnemonicProducesIdenticalIdentity` (unit).
  - Real: real BIP39/Ed25519 identity generation and restoration.
  - Faked: none identified.
  - Proves / registration: go-mknoon/identity/identity_test.go:89: A generated phrase restores exactly the same peer/public/private identity. Registered go-core ./...; Flutter FFI and secure storage are outside this process. Registered: see cited native runner/manifest.
- [test/features/identity/presentation/screens/mnemonic_input_wired_restore_notice_test.dart](../../test/features/identity/presentation/screens/mnemonic_input_wired_restore_notice_test.dart) — `shows the honest notice when restore hydrates zero groups` (widget).
  - Real: MnemonicInputWired submit flow and honest restore notice.
  - Faked: identity restore and ML-KEM callbacks; identity/group repositories.
  - Proves / registration: test/features/identity/presentation/screens/mnemonic_input_wired_restore_notice_test.dart:85: Submitting the phrase with zero restored groups shows the limited-history/group recovery notice then navigates; existing-local-groups case suppresses it. Registered: affected-identity, host-all.

**Remaining gaps**

- Real key derivation and notice UI are independently tested with fake storage/bridge; clean-install signed app restoration is unverified.

#### IDENTITY-010 — Cold start while offline; show local identity/conversations and recover connectivity

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Cold-start offline with an existing identity and conversations.
2. Show usable local state before network recovery.
3. Restore connectivity and settle incoming work.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: offline then reconnect; offline: existing local identity/history; app state: cold start; input: as described; recovery: network warm completion.

**Expected:** Local identity/home/history remain usable while offline and reconnect does not duplicate recovery work.

**Inspected test evidence**

- [test/features/identity/presentation/screens/startup_router_test.dart](../../test/features/identity/presentation/screens/startup_router_test.dart) — `returning cold start after reboot shows persisted conversation history before network warm completion` (unit).
  - Real: decideStartupRoute.
  - Faked: identity/contact repositories; no widget tree or networking.
  - Proves / registration: test/features/identity/presentation/screens/startup_router_test.dart:138: Despite its broad name, only asserts hasIdentityWithContacts from fake local records; does not display persisted history or reboot an app. Registered: affected-identity, host-all.

**Remaining gaps**

- The misleadingly named startup case asserts a decision from fake identity/contact records only; it does not assert rendered SQLite history, actual offline startup or reconnect.

### CONTACT — QR, contact requests, profiles and contact management

#### DC-013 — Deleting a contact wipes the chat

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-013.

**Steps**

1. Confirm deleting one contact.
2. Purge owned direct history/media/trust/notification state.
3. Reopen and preserve other contacts/group/unresolved siblings.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: same-ID direct/group/unresolved siblings; recovery: delete/readd and reopen.

**Expected:** Deleted contact loses owned direct history without crossing another owner.

**Inspected test evidence**

- [test/features/contacts/application/delete_contact_use_case_test.dart](../../test/features/contacts/application/delete_contact_use_case_test.dart) — `contact deletion preserves same id group and unresolved media` (unit).
  - Real: production current SQLite media repositories/owner-scoped cleanup.
  - Faked: contact/message cleanup seams; fixture media/secure store.
  - Proves / registration: test/features/contacts/application/delete_contact_use_case_test.dart:1113: Deletes direct-owned media for colliding message ID, preserves same-ID group and unresolved rows; actual OS file/native notification cleanup is separate. Registered: affected-identity, host-all.
- [test/features/contact_request/integration/contact_repair_two_party_test.dart](../../test/features/contact_request/integration/contact_repair_two_party_test.dart) — `B deletes and re-adds A from A's compact QR twice; each time one signed request earns one reply that repairs B` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; real repair request/reply/outbox orchestration.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/contact_repair_two_party_test.dart:253: Each repeated re-add repairs receiver ML-KEM/grant with one signed request/reply; no reply-to-reply loop. DB/real signatures are meaningful; network/ML-KEM are modeled. Registered: affected-identity, host-all.

**Remaining gaps**

- Real owner-scoped media/SQL cleanup is covered, but full contact delete UI/cancel/confirmation, native file/notification cleanup and restart preservation are separate.

#### DC-016 — Block and unblock preserve ingress privacy

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-016.

**Steps**

1. Block an existing contact and receive text/request/notification.
2. Refuse ingress before decrypt/side effects while preserving history.
3. Unblock and accept only newly valid/current activity.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: block/unblock existing sender; recovery: new activity versus old replay.

**Expected:** Blocked ingress cannot mutate trusted state/leak new previews; unblock does not replay forbidden consent.

**Inspected test evidence**

- [test/features/contact_request/integration/contact_repair_two_party_test.dart](../../test/features/contact_request/integration/contact_repair_two_party_test.dart) — `A blocked B: B's re-add request gets no reply and A stores nothing from it` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; actual blocked-receive policy.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/contact_repair_two_party_test.dart:344: Blocked sender earns zero reply and no stored new state. This is app receive authority, not an OS provider-push blocking proof. Registered: affected-identity, host-all.
- [test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart](../../test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart) — `returns null WITHOUT decrypting for a blocked sender` (unit).
  - Real: actual direct receive blocked check.
  - Faked: bridge and repositories.
  - Proves / registration: test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart:4919: Known blocked sender is refused before decrypt; no public/native push privacy or unblock lifecycle proof by itself. Registered: affected-conversation, host-all, quiet-recovery.
- [test/features/contacts/integration/direct_notification_projection_lifecycle_test.dart](../../test/features/contacts/integration/direct_notification_projection_lifecycle_test.dart) — `direct reaction projection covers contact and authored-target lifecycle` (integration).
  - Real: actual direct notification contact/target projection policy.
  - Faked: memory secure store and fixture contact changes.
  - Proves / registration: test/features/contacts/integration/direct_notification_projection_lifecycle_test.dart:10: Block/archive/unblock/delete update exact projection and exclude private authored text/key values. Native provider/extension state is not exercised. Registered: affected-identity, host-all.

**Remaining gaps**

- Actual receive/projection policy is causal at host seams; native push preview/privacy and unblock/restart/replay across real peers are not one proof.

#### CR-001 — Scan a QR code, the other person accepts, and both can chat

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-001.

**Steps**

1. Scan/paste a signed contact QR.
2. Other person explicitly accepts and reciprocal key exchange settles.
3. Send a first encrypted chat using the exchanged key.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: fresh contact QR and explicit acceptance; recovery: n/a.

**Expected:** Both contacts converge and the actual exchanged key enables first chat only after consent.

**Inspected test evidence**

- [test/features/contacts/contact_request_roundtrip_test.dart](../../test/features/contacts/contact_request_roundtrip_test.dart) — `contact-request roundtrip exchanges ML-KEM key, then a v2 message decrypts` (unit).
  - Real: actual scan/contact request/accept+reciprocal/key hydration/chat send/receive composition.
  - Faked: passthrough message and contact-request crypto; FakeP2PNetwork/in-memory repositories; native camera bypassed.
  - Proves / registration: test/features/contacts/contact_request_roundtrip_test.dart:243: Initial no-key message refuses; accepted reciprocal installs the missing key then an exact v2 chat reaches recipient. Crypto/ML-KEM primitive is explicitly faked, not native authenticated wire. Registered: affected-identity, host-all.
- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `contact QR sends an encrypted request and isolates profile download failure` (widget).
  - Real: actual scanner accepted-result orchestration, contact store/request dispatch.
  - Faked: QRScannerScreen callback instead of camera; bridge/repositories/P2P; profile download failure.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:315: Valid reported QR adds contact and dispatches encrypted request despite avatar failure; actual signature is a bridge seam and recipient acceptance is separate. Registered: affected-identity, host-all.

**Remaining gaps**

- Strong orchestration negative control exists, but native camera/ML-KEM/crypto/network/storage are faked in composed host journey; real peer/candidate end-to-end unverified.

#### CR-002 — Declining a request adds no contact

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-002.

**Steps**

1. Receive a valid signed request.
2. Explicitly Decline.
3. Replay old envelope/restart, then receive a truly fresh request.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: valid request, declined old replay, fresh subsequent request; recovery: real SQLite reopen.

**Expected:** Decline adds no contact/sends no reciprocal; old replay cannot reprompt and fresh request still needs manual consent.

**Inspected test evidence**

- [test/features/contact_request/integration/declining_request_adds_no_contact_test.dart](../../test/features/contact_request/integration/declining_request_adds_no_contact_test.dart) — `decline adds no contact on Alice, sends nothing to Bob, ignores an old replayed envelope, survives restart, and forces a fresh request onto manual consent` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; real listener/decline/replay and file reopen.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/declining_request_adds_no_contact_test.dart:138: Decline retains no contact/outbound reciprocal, old envelope after reopen stays declined and fresh request needs manual consent; fake encryption does not prove native privacy. Registered: affected-identity, host-all.

**Remaining gaps**

- Source-disabled KNOWN GAP CR-002: declining_request_adds_no_contact_test.dart:530-531 skips the sole defining replay/SQL-reopen story. ReplayCache is in-memory only and incoming handling can overwrite declined back to pending without durable message-ID/timestamp ordering. Default gates cannot fail this disabled defining assertion; this is more than not executed in this audit.
- Native transport/ML-KEM encryption and OS presentation remain modeled.

#### CR-003 — A missed request can still be found and answered

**Coverage:** strong. **Execution:** not_run. **Catalog:** CR-003.

**Steps**

1. Store a request while its presentation is missed/suppressed.
2. Attach/reenter Feed/Orbit.
3. Find and answer it exactly once without implicit contact creation.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: persisted or suppressed pending request; recovery: attach/reentry/suppression release.

**Expected:** A valid pending request remains discoverable until an explicit decision.

**Inspected test evidence**

- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-003 stored request replays on first attach and stays until declined` (widget).
  - Real: production Feed/retained Orbit, ContactRequestListener and ContactRequestDialog; current FFI SQLite repositories and real Ed25519 signatures.
  - Faked: P2P/native services and lookup-table request encryption.
  - Proves / registration: Stored pending request is visible on attach and Navigator remount, remains pending until Decline, then leaves no contact or pending row. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/018-shell-persistence.log. Registered: affected-identity, host-all.
- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-003 suppression release reveals a missed request with shell subscribers retained` (widget).
  - Real: production Feed/retained Orbit, ContactRequestListener and ContactRequestDialog; current FFI SQLite repositories and real Ed25519 signatures.
  - Faked: P2P/native services and lookup-table request encryption.
  - Proves / registration: Observable gate release replays the missed durable pending row into one dialog while Feed and Orbit remain subscribed; tab switching grants no contact. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/018-shell-persistence.log. Registered: affected-identity, host-all.
- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-005 live plus inbox duplicate and listener restart retain one consent dialog` (widget).
  - Real: production Feed/retained Orbit, ContactRequestListener and ContactRequestDialog; current FFI SQLite repositories and real Ed25519 signatures.
  - Faked: P2P/native services and lookup-table request encryption.
  - Proves / registration: Repeated live/inbox input and listener restart retain one consent dialog and pending row without implicit contact creation. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/018-shell-persistence.log. Registered: affected-identity, host-all.
- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-005 one event with Feed and embedded Orbit mounted opens one dialog route` (widget).
  - Real: production Feed/retained Orbit, ContactRequestListener and ContactRequestDialog; current FFI SQLite repositories and real Ed25519 signatures.
  - Faked: P2P/native services and lookup-table request encryption.
  - Proves / registration: Both retained shell subscribers receive the broadcast but share one dialog presentation owner. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/018-shell-persistence.log. Registered: affected-identity, host-all.
- [test/features/contact_request/application/contact_request_notification_materializer_test.dart](../../test/features/contact_request/application/contact_request_notification_materializer_test.dart) — `notification decline persists before gate release replays pending rows` (widget).
  - Real: production notification materializer, listener and observable presentation gate.
  - Faked: in-memory request/contact repositories with an explicitly delayed status write; test dialog presenter matching the root await contract; native/network services.
  - Proves / registration: A delayed decision keeps notification suppression until the declined status is persisted; release then reads no pending row. A companion source guard verifies both root callbacks capture and await their decision. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/017-consent-race.log. Registered: affected-identity, host-all.

**Remaining gaps**

- Host replay, remount, retained-subscriber release and decision-before-replay timing pass. Real OS notification delivery and native/network peer behavior remain outside this scoped host proof.

#### CR-004 — Fake or tampered requests are rejected

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-004.

**Steps**

1. Receive tampered/forged/mismatched identity request.
2. Verify signature/binding before state mutation.
3. Retain prior contact/request authority and allow later valid traffic.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: tamper, sender/key mismatch, wrong recipient; recovery: n/a.

**Expected:** Unauthenticated request cannot grant contact/key/consent authority.

**Inspected test evidence**

- [test/features/qr_code/application/parse_qr_identity_binding_test.dart](../../test/features/qr_code/application/parse_qr_identity_binding_test.dart) — `K2 self-signs a QR that claims K1 peer ID: rejected before any contact is built` (unit).
  - Real: real parser/Ed25519 verification/production peer-ID derivation.
  - Faked: test account keys and clock.
  - Proves / registration: test/features/qr_code/application/parse_qr_identity_binding_test.dart:103: Self-signed K2 cannot claim K1 peer ID; valid own-key/derived-ID controls and canonical field ordering are accepted. No scanner camera/native bridge. Registered: affected-identity, host-all.
- [test/features/contact_request/integration/contact_repair_two_party_test.dart](../../test/features/contact_request/integration/contact_repair_two_party_test.dart) — `A blocked B: B's re-add request gets no reply and A stores nothing from it` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; actual blocked-receive policy.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/contact_repair_two_party_test.dart:344: Blocked sender earns zero reply and no stored new state. This is app receive authority, not an OS provider-push blocking proof. Registered: affected-identity, host-all.
- [test/features/contact_request/integration/failed_save_preserves_valid_request_test.dart](../../test/features/contact_request/integration/failed_save_preserves_valid_request_test.dart) — `storage failure on a valid incoming request withholds direct ACK, keeps ProductionCanonicalDirectReplayComposition.replayContactRequest retryable, and surfaces the request once across duplicate replays after storage recovers` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; P2PService/ProductionCanonicalDirectReplayComposition receive completion.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks; SQL upsert throws until repaired.
  - Proves / registration: test/features/contact_request/integration/failed_save_preserves_valid_request_test.dart:420: Failed write withholds positive direct ACK and replay remains retryable; after repair duplicate processing stores one pending row/prompt and no contact, with original current owner. Registered: affected-identity, host-all.

**Remaining gaps**

- Real Ed25519 identity-binding fixtures and storage boundaries exist; request-specific invalid-crypto controller tests often stub bridge rejection. Genuine native request encryption/signature-to-receive mutation boundary is not joined.

#### CR-005 — The same request arriving twice shows once

**Coverage:** strong. **Execution:** not_run. **Catalog:** CR-005.

**Steps**

1. Deliver one request live and through inbox again.
2. Restart listener/reopen pending state.
3. Keep one consent row/dialog even with both retained shell subscribers.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: live/inbox duplicate; Feed+Orbit subscribers; recovery: listener restart.

**Expected:** Duplicate input never creates duplicate consent/contact effects.

**Inspected test evidence**

- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-005 live plus inbox duplicate and listener restart retain one consent dialog` (widget).
  - Real: production Feed/retained Orbit, ContactRequestListener and ContactRequestDialog; current FFI SQLite repositories and real Ed25519 signatures.
  - Faked: P2P/native services and lookup-table request encryption.
  - Proves / registration: Repeated live/inbox input and listener restart retain one consent dialog and pending row without implicit contact creation. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/018-shell-persistence.log. Registered: affected-identity, host-all.
- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-005 one event with Feed and embedded Orbit mounted opens one dialog route` (widget).
  - Real: production Feed/retained Orbit, ContactRequestListener and ContactRequestDialog; current FFI SQLite repositories and real Ed25519 signatures.
  - Faked: P2P/native services and lookup-table request encryption.
  - Proves / registration: Both retained shell subscribers receive the broadcast but share one dialog presentation owner. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/018-shell-persistence.log. Registered: affected-identity, host-all.

**Remaining gaps**

- Single-shell restart and retained Feed/Orbit ownership pass with real pending SQL; actual OS/native transport ingress remains modeled.

#### CR-006 — A request reaches someone who was offline for less than a day

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-006.

**Steps**

1. Keep recipient offline within supported request lifetime.
2. Send encrypted request and retain retry/custody.
3. Reconnect/drain and show one pending consent.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: recipient offline less than24h; app state: foreground; input: as described; recovery: request inbox catch-up.

**Expected:** Retained valid request arrives once without auto-accepting or expiring prematurely.

**Inspected test evidence**

- [test/features/contact_request/integration/key_exchange_retry_flow_test.dart](../../test/features/contact_request/integration/key_exchange_retry_flow_test.dart) — `full offline→online retry sends to contact with null key` (integration).
  - Real: actual retry/send contact-request orchestration.
  - Faked: fake P2P/bridge/in-memory repositories.
  - Proves / registration: test/features/contact_request/integration/key_exchange_retry_flow_test.dart:80: After offline failure, missing-key contact is retried online; key-present/blocked cases are skipped and v2 envelope assertions exist separately. Registered: affected-identity, host-all.
- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-005 live plus inbox duplicate and listener restart retain one consent dialog` (widget).
  - Real: real listener/dialog/retained pending SQL.
  - Faked: fake network/native/lookup encryption.
  - Proves / registration: test/features/contact_request/presentation/screens/pending_request_shell_test.dart:150: Live+inbox duplicate and listener restart keep one dialog/pending row under the tested single-shell setup; two shell subscribers have a separate skipped known-gap test. Registered: affected-identity, host-all.
- [test/features/contacts/contact_request_roundtrip_test.dart](../../test/features/contacts/contact_request_roundtrip_test.dart) — `contact-request roundtrip exchanges ML-KEM key, then a v2 message decrypts` (unit).
  - Real: actual scan/contact request/accept+reciprocal/key hydration/chat send/receive composition.
  - Faked: passthrough message and contact-request crypto; FakeP2PNetwork/in-memory repositories; native camera bypassed.
  - Proves / registration: test/features/contacts/contact_request_roundtrip_test.dart:243: Initial no-key message refuses; accepted reciprocal installs the missing key then an exact v2 chat reaches recipient. Crypto/ML-KEM primitive is explicitly faked, not native authenticated wire. Registered: affected-identity, host-all.

**Remaining gaps**

- Host fake network immediate reconnect covers retry mechanics; actual near24h relay retention/provider wake and full new-user consent path are not joined.

#### CR-007 — Blocked people cannot get a request through

**Coverage:** strong. **Execution:** not_run. **Catalog:** CR-007.

**Steps**

1. Block sender before a new/re-add request arrives.
2. Process signed request through current authority.
3. Check zero reply/key/token/grant/intro/contact mutation.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: blocked requester/re-add and direct chat; recovery: n/a.

**Expected:** Blocking preserves prior trusted state and prevents request side effects.

**Inspected test evidence**

- [test/features/contact_request/integration/contact_repair_two_party_test.dart](../../test/features/contact_request/integration/contact_repair_two_party_test.dart) — `A blocked B: B's re-add request gets no reply and A stores nothing from it` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; actual blocked-receive policy.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/contact_repair_two_party_test.dart:344: Blocked sender earns zero reply and no stored new state. This is app receive authority, not an OS provider-push blocking proof. Registered: affected-identity, host-all.
- [test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart](../../test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart) — `returns null WITHOUT decrypting for a blocked sender` (unit).
  - Real: actual direct receive blocked check.
  - Faked: bridge and repositories.
  - Proves / registration: test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart:4919: Known blocked sender is refused before decrypt; no public/native push privacy or unblock lifecycle proof by itself. Registered: affected-conversation, host-all, quiet-recovery.

**Remaining gaps**

- Strong is scoped to actual app receive policy with real signed fixtures/SQL; OS provider/notification ingress and hardware privacy remain separate.

#### CR-009 — iPhone and Android can add each other

**Coverage:** partial. **Execution:** skipped_waiting_ui_update. **Catalog:** CR-009.

**Steps**

1. Use actual iPhone and Android contact QR/request flows in both directions.
2. Explicitly accept and finish reciprocal keys.
3. Exchange first message without seeding contacts.

**Conditions:** platform: iPhone 13 and Pixel 6 existing identities/pairing preserved; fresh-add skipped; connectivity: n/a; offline: n/a; app state: foreground; input: real QR or supported manual entry; recovery: n/a.

**Expected:** Supported platforms can add each other with genuine native identity/crypto/consent.

**Device execution (2026-10-22; flutter_app)**

- Result: **SKIPPED_WAITING_UI_UPDATE**.
- Fresh native iPhone/Android add was not run: the contact/Orbit route waits for UI-Update. Existing physical identities, pairing and chat survived install-over; this is not fresh-add evidence.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:6`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:30`.

**Inspected test evidence**

- [test/features/contacts/contact_request_roundtrip_test.dart](../../test/features/contacts/contact_request_roundtrip_test.dart) — `CR-009/DC-011 shared protocol scanner A accepts reciprocal keys before exact bidirectional Unicode chat` (integration).
  - Real: production request listener, explicit accept/reciprocate, persisted peer-key lookup and v2 send/receive composition; both logical initiating roles; keyless send refused; exact bidirectional Unicode text and one incoming copy.
  - Faked: QR scan/contact insertion simulated; in-memory repositories and FakeP2PNetwork; passthrough crypto and fake native signatures/ML-KEM, not authenticated native transport.
  - Proves / registration: test/features/contacts/contact_request_roundtrip_test.dart:245: Scanner A begins without the recipient ML-KEM key; receiver remains unlinked before acceptance, reciprocal key unlocks both v2 chat directions. Fresh full file: 3 passed, 0 skipped, exit 0 (003-contact-roundtrip-summary.json/receipt under .codex-test-logs/astra-groupCD). Registered: affected-identity, host-all.
- [test/features/contacts/contact_request_roundtrip_test.dart](../../test/features/contacts/contact_request_roundtrip_test.dart) — `CR-009/DC-011 shared protocol scanner B accepts reciprocal keys before exact bidirectional Unicode chat` (integration).
  - Real: production request listener, explicit accept/reciprocate, persisted peer-key lookup and v2 send/receive composition; both logical initiating roles; keyless send refused; exact bidirectional Unicode text and one incoming copy.
  - Faked: QR scan/contact insertion simulated; in-memory repositories and FakeP2PNetwork; passthrough crypto and fake native signatures/ML-KEM, not authenticated native transport.
  - Proves / registration: test/features/contacts/contact_request_roundtrip_test.dart:245: Scanner B begins without the recipient ML-KEM key; receiver remains unlinked before acceptance, reciprocal key unlocks both v2 chat directions. Fresh full file: 3 passed, 0 skipped, exit 0 (003-contact-roundtrip-summary.json/receipt under .codex-test-logs/astra-groupCD). Registered: affected-identity, host-all.

**Remaining gaps**

- Native fresh add remains SKIPPED waiting for UI-Update. Preserved existing iPhone/Pixel pairing and host simulated QR/crypto cannot prove fresh scan/consent/identity authority.
- Runbook keeps the disposable fresh-add leg separate from preserved physical identities; no iPhone uninstall, erase or identity removal was performed.

**Open questions**

- Runbook: docs/testing/astra-group-c-device-runbook.md. Execution performed by flutter_app, not Astra; existing evidence inspected read-only.
- Result scope, candidate and focused host rechecks are recorded in header.group_c_device_run; remaining manual/content/platform limitations above are not full-journey passes.

#### CR-010 — Encrypted requests never fall back to plain text

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-010.

**Steps**

1. Require encrypted request mode for a known recipient public key.
2. Fail/malformed/empty native encryption result.
3. Verify explicit failure without legacy plaintext fallback.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: required-v2 encryption fail/malformed response; recovery: n/a.

**Expected:** Required-encryption failure never silently downgrades the request to plaintext.

**Inspected test evidence**

- [test/features/contact_request/application/send_contact_request_use_case_test.dart](../../test/features/contact_request/application/send_contact_request_use_case_test.dart) — `v2: returns encryptionError when encryption fails` (unit).
  - Real: actual send-contact-request encryption-error control flow.
  - Faked: bridge failure and fake P2P/repos.
  - Proves / registration: test/features/contact_request/application/send_contact_request_use_case_test.dart:564: Required-encryption error returns encryptionError rather than v1 fallback; malformed/empty crypto output companion cases also reject. Test does not itself assert every outbound counter or genuine native crypto. Registered: affected-identity, host-all.
- [test/features/contacts/contact_request_roundtrip_test.dart](../../test/features/contacts/contact_request_roundtrip_test.dart) — `contact-request roundtrip exchanges ML-KEM key, then a v2 message decrypts` (unit).
  - Real: actual scan/contact request/accept+reciprocal/key hydration/chat send/receive composition.
  - Faked: passthrough message and contact-request crypto; FakeP2PNetwork/in-memory repositories; native camera bypassed.
  - Proves / registration: test/features/contacts/contact_request_roundtrip_test.dart:243: Initial no-key message refuses; accepted reciprocal installs the missing key then an exact v2 chat reaches recipient. Crypto/ML-KEM primitive is explicitly faked, not native authenticated wire. Registered: affected-identity, host-all.

**Remaining gaps**

- Error-result tests use a fake bridge and do not themselves assert every zero-outbound counter; genuine native crypto confidentiality and on-wire absence of plaintext are not jointly established.

#### CR-011 — Scanning someone you already have keeps them intact

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-011.

**Steps**

1. Rescan a saved contact after delete/readd/key repair activity.
2. Recheck trusted identity before permitted request/repair.
3. Preserve current name/archive/block/history while converging eligible keys.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: existing contact QR, same versus conflicting identity key; recovery: n/a.

**Expected:** A rescan cannot duplicate/overwrite existing contact trust or unrelated metadata.

**Inspected test evidence**

- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `scanning an existing contact shows the circle dialog and re-sends our request without touching the stored row` (widget).
  - Real: actual existing-contact scan preservation/hand-off.
  - Faked: bridge/P2P/identity/contact repository.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:375: Rescan shows existing-circle dialog/resends request without profile download, delete, duplicate or overwritten stored row; real SQL repair tested separately. Registered: affected-identity, host-all.
- [test/features/contact_request/integration/contact_repair_two_party_test.dart](../../test/features/contact_request/integration/contact_repair_two_party_test.dart) — `B deletes and re-adds A from A's compact QR twice; each time one signed request earns one reply that repairs B` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; real repair request/reply/outbox orchestration.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/contact_repair_two_party_test.dart:253: Each repeated re-add repairs receiver ML-KEM/grant with one signed request/reply; no reply-to-reply loop. DB/real signatures are meaningful; network/ML-KEM are modeled. Registered: affected-identity, host-all.
- [test/features/contact_request/application/existing_contact_repair_receive_test.dart](../../test/features/contact_request/application/existing_contact_repair_receive_test.dart) — `first key lands, newer rotation lands, older replay and equal-instant different key are ignored` (unit).
  - Real: actual existing-contact receive/instant ordering and authority checks; real Ed25519 request fixtures.
  - Faked: receive harness repositories/grant/token callbacks; encryption lookup model.
  - Proves / registration: test/features/contact_request/application/existing_contact_repair_receive_test.dart:597: Newer ML-KEM public key replaces older; older replay and equal instant with different key do not. Offset timestamp normalizes by instant, not lexicographic order. Registered: affected-identity, host-all.

**Remaining gaps**

- UI and real SQL repair are separately tested with fake network/ML-KEM; complete native scanner-to-real-peer response after restart remains unverified.

#### CR-012 — A request that failed to send is retried later

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-012.

**Steps**

1. Fail initial request/key exchange before/during egress.
2. Retain pending retry intent.
3. Restore connectivity and retry only eligible missing-key contacts.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: missing key and failed send; recovery: later online/restart retry.

**Expected:** Failed request remains recoverable without sending to blocked/already-complete targets.

**Inspected test evidence**

- [test/features/contact_request/integration/key_exchange_retry_flow_test.dart](../../test/features/contact_request/integration/key_exchange_retry_flow_test.dart) — `full offline→online retry sends to contact with null key` (integration).
  - Real: actual retry/send contact-request orchestration.
  - Faked: fake P2P/bridge/in-memory repositories.
  - Proves / registration: test/features/contact_request/integration/key_exchange_retry_flow_test.dart:80: After offline failure, missing-key contact is retried online; key-present/blocked cases are skipped and v2 envelope assertions exist separately. Registered: affected-identity, host-all.
- [test/features/contact_request/integration/acceptance_reaches_peer_after_restart_test.dart](../../test/features/contact_request/integration/acceptance_reaches_peer_after_restart_test.dart) — `pre-egress encryption failure on the reciprocal send after local acceptance is recovered on restart and delivers the accepter ML-KEM key without a second prompt or duplicate contact` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; accept/reciprocate/listener/retry pipeline and SQL file reopen.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks; one bridge encrypt failure.
  - Proves / registration: test/features/contact_request/integration/acceptance_reaches_peer_after_restart_test.dart:174: After local accept and failed reciprocal encryption, reopened sender recovers exact key exchange; one contact and no second prompts while other peer obtains accepter ML-KEM key. No native encrypted transport. Registered: affected-identity, host-all.

**Remaining gaps**

- Real SQL reciprocal restart evidence exists, but generic retry flow uses fake network/store and no OS scheduling/provider execution.

#### CR-013 — Accepting survives a crash halfway through

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-013.

**Steps**

1. Accept a pending request.
2. Inject failure after contact commit but before accepted status.
3. Reopen the file database/listener and retry/read consent.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: mid-accept status-write failure; recovery: real file database close/reopen.

**Expected:** One contact survives partial acceptance and no second prompt or stale key overwrite occurs.

**Inspected test evidence**

- [test/features/contact_request/integration/accepting_survives_crash_halfway_test.dart](../../test/features/contact_request/integration/accepting_survives_crash_halfway_test.dart) — `crash between adding the contact and marking the request accepted leaves one contact and does not re-prompt on restart` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; real SQLite file close/reopen at injected write boundary.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks; status updater deliberately throws to model crash.
  - Proves / registration: test/features/contact_request/integration/accepting_survives_crash_halfway_test.dart:122: Contact add commits before status failure; rebuilding listener from reopened file keeps one contact/no re-prompt. This is a modeled cutpoint, not an OS process kill. Registered: affected-identity, host-all.

**Remaining gaps**

- Source-disabled KNOWN GAP CR-013: accepting_survives_crash_halfway_test.dart:262 and :382 skip both cases. Non-atomic contact/status writes can leave pending consent after a mid-accept crash; repeated accept can overwrite current key/archive/block state. Default gates cannot fail these disabled defining assertions.
- No actual abrupt OS kill, native SQLCipher/keychain or power-loss guarantee was verified.

#### CR-014 — Many requests at once are all kept

**Coverage:** strong. **Execution:** not_run. **Catalog:** CR-014.

**Steps**

1. Receive several distinct valid requests rapidly.
2. Keep every pending row without granting contact consent.
3. Present/answer one at a time while preserving the remaining requests.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: three distinct requests in one burst; recovery: answer one, retain others.

**Expected:** Burst storage and usable sequential consent never lose or implicitly accept a requester.

**Inspected test evidence**

- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-014 burst preserves each distinct pending row without granting consent` (widget).
  - Real: production Feed/retained Orbit, ContactRequestListener and ContactRequestDialog; current FFI SQLite repositories and real Ed25519 signatures.
  - Faked: P2P/native services and lookup-table request encryption.
  - Proves / registration: Three distinct signed requests remain three pending rows with no contact consent. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/018-shell-persistence.log. Registered: affected-identity, host-all.
- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-014 burst presents one request at a time and keeps the others until answered` (widget).
  - Real: production Feed/retained Orbit, ContactRequestListener and ContactRequestDialog; current FFI SQLite repositories and real Ed25519 signatures.
  - Faked: P2P/native services and lookup-table request encryption.
  - Proves / registration: The three-request burst presents one dialog at a time; declining each preserves the remaining rows until their own explicit answer. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/018-shell-persistence.log. Registered: affected-identity, host-all.

**Remaining gaps**

- The bounded three-request host burst passes; production load, native transport and OS lifecycle behavior are not certified by this fixture.

#### CR-015 — A fake or altered QR code adds no contact

**Coverage:** strong. **Execution:** not_run. **Catalog:** CR-015.

**Steps**

1. Scan valid-key controls and forged key/peer combinations.
2. Verify canonical signature and libp2p derivation.
3. Reject forged identity before building a contact.

**Conditions:** platform: shared QR parser boundary; connectivity: n/a; offline: n/a; app state: foreground; input: self-signed wrong peer versus valid key-derived peer; recovery: n/a.

**Expected:** Self-signed mismatched key/peer authority never constructs a contact; valid canonical controls pass.

**Inspected test evidence**

- [test/features/qr_code/application/parse_qr_identity_binding_test.dart](../../test/features/qr_code/application/parse_qr_identity_binding_test.dart) — `K2 self-signs a QR that claims K1 peer ID: rejected before any contact is built` (unit).
  - Real: real parser/Ed25519 verification/production peer-ID derivation.
  - Faked: test account keys and clock.
  - Proves / registration: test/features/qr_code/application/parse_qr_identity_binding_test.dart:103: Self-signed K2 cannot claim K1 peer ID; valid own-key/derived-ID controls and canonical field ordering are accepted. No scanner camera/native bridge. Registered: affected-identity, host-all.

**Remaining gaps**

- Strong is scoped to parser identity binding with real Ed25519; actual camera/native bridge/transport is separate.

#### CR-016 — Requester names display safely

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-016.

**Steps**

1. Render requester username in consent dialog.
2. Use Arabic/English mixed, long and unsafe-control inputs.
3. Keep name legible/direction-correct without hiding Accept/Decline.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: mixed-script/long/control-character requester names; recovery: n/a.

**Expected:** Requester identity displays safely without changing signed content/consent.

**Inspected test evidence**

- [test/features/contact_request/presentation/widgets/contact_request_dialog_test.dart](../../test/features/contact_request/presentation/widgets/contact_request_dialog_test.dart) — `Arabic-first mixed username drives RTL direction` (widget).
  - Real: actual dialog Text/Directionality and consent controls.
  - Faked: fixture request and action callbacks.
  - Proves / registration: test/features/contact_request/presentation/widgets/contact_request_dialog_test.dart:116: Arabic-first mixed name renders RTL while English-first companion renders LTR; unsafe control sanitization/long names are separate. Registered: affected-identity, host-all.

**Remaining gaps**

- Mixed-script direction is asserted; full unsafe bidi, extreme length/emoji and narrow-view action reachability are not all asserted in this dialog journey.

#### CR-017 — Old request actions cannot undo a newer decision

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-017.

**Steps**

1. Retain a stale Accept/Decline action after a newer decision/contact change.
2. Invoke old action or notification.
3. Re-read current authority before connecting, declining or replacing keys.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: stale accept after decline, stale decline after accept, newer blocked key; recovery: n/a.

**Expected:** Old UI action cannot undo decline/accept or overwrite newer blocked/trusted contact.

**Inspected test evidence**

- [test/features/contact_request/integration/old_request_actions_preserve_newer_decision_test.dart](../../test/features/contact_request/integration/old_request_actions_preserve_newer_decision_test.dart) — `stale notification accept after the request was declined does not open a conversation without a current contact` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; actual request state/materializer qualification.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/old_request_actions_preserve_newer_decision_test.dart:125: A stale accept after decline cannot create a conversation without current contact; companion stale-decline and blocked/new-key cases preserve newer decisions. Registered: affected-identity, host-all.
- [test/features/contact_request/integration/old_request_actions_preserve_newer_decision_test.dart](../../test/features/contact_request/integration/old_request_actions_preserve_newer_decision_test.dart) — `stale decline action does not turn an already-accepted request back into declined` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; actual decline current-state qualification.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/old_request_actions_preserve_newer_decision_test.dart:243: Old decline cannot replace accepted status or remove a current contact. Registered: affected-identity, host-all.
- [test/features/contact_request/integration/old_request_actions_preserve_newer_decision_test.dart](../../test/features/contact_request/integration/old_request_actions_preserve_newer_decision_test.dart) — `stale accept action on a leftover pending row does not overwrite a newer blocked contact or its newer ML-KEM key` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; actual accept current-contact qualification.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/old_request_actions_preserve_newer_decision_test.dart:329: Old pending accept preserves the newer blocked contact and newer ML-KEM key. Registered: affected-identity, host-all.

**Remaining gaps**

- Source-disabled KNOWN GAP CR-017: old_request_actions_preserve_newer_decision_test.dart:239, :325 and :414 skip all three stale-action cases. Stale accept may synthesize a contact after decline, stale decline may overwrite accepted state, and stale pending accept may overwrite a newer blocked contact/key. Default gates cannot fail these disabled defining assertions.
- OS native notification actions and real network effects remain modeled.

#### CR-018 — Acceptance still reaches the other person after a restart

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-018.

**Steps**

1. Accept locally and fail reciprocal encryption before egress.
2. Restart with real retained SQL state.
3. Retry key exchange until peer receives current key without second prompt/contact.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: pre-egress reciprocal encryption failure; recovery: same database reopen.

**Expected:** Accepted intent recovers the reciprocal key exchange after restart without duplicate consent.

**Inspected test evidence**

- [test/features/contact_request/integration/acceptance_reaches_peer_after_restart_test.dart](../../test/features/contact_request/integration/acceptance_reaches_peer_after_restart_test.dart) — `pre-egress encryption failure on the reciprocal send after local acceptance is recovered on restart and delivers the accepter ML-KEM key without a second prompt or duplicate contact` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; accept/reciprocate/listener/retry pipeline and SQL file reopen.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks; one bridge encrypt failure.
  - Proves / registration: test/features/contact_request/integration/acceptance_reaches_peer_after_restart_test.dart:174: After local accept and failed reciprocal encryption, reopened sender recovers exact key exchange; one contact and no second prompts while other peer obtains accepter ML-KEM key. No native encrypted transport. Registered: affected-identity, host-all.

**Remaining gaps**

- Real SQL reopen/Ed25519 pipeline is substantive, but encryption lookup/network/store doubles do not prove actual native cryptographic delivery or process termination.

#### CR-019 — Old key updates cannot replace newer contact details

**Coverage:** strong. **Execution:** not_run. **Catalog:** CR-019.

**Steps**

1. Receive an initial trusted key update and newer rotation.
2. Replay older/equal-instant conflicting key/token data.
3. Preserve newest trusted contact details under normalized time ordering.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: newer/older/equal instant timestamp including offset timezone; recovery: n/a.

**Expected:** Older or equal-conflicting updates never overwrite the newer accepted key/authority.

**Inspected test evidence**

- [test/features/contact_request/application/existing_contact_repair_receive_test.dart](../../test/features/contact_request/application/existing_contact_repair_receive_test.dart) — `first key lands, newer rotation lands, older replay and equal-instant different key are ignored` (unit).
  - Real: actual existing-contact receive/instant ordering and authority checks; real Ed25519 request fixtures.
  - Faked: receive harness repositories/grant/token callbacks; encryption lookup model.
  - Proves / registration: test/features/contact_request/application/existing_contact_repair_receive_test.dart:597: Newer ML-KEM public key replaces older; older replay and equal instant with different key do not. Offset timestamp normalizes by instant, not lexicographic order. Registered: affected-identity, host-all.

**Remaining gaps**

- Strong applies to actual receive ordering/relationship policy with real signed inputs; public ML-KEM strings and grant/token storage are fixture seams, not native key validation.

#### CR-020 — A failed save does not lose a valid request

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-020.

**Steps**

1. Fail SQL upsert on a valid incoming request.
2. Attempt direct completion and canonical inbox replay while failure persists.
3. Repair storage and process duplicates.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: valid signed request and injected SQL write failure; recovery: canonical replay after storage repair.

**Expected:** Failure cannot ACK away the request; retry stores/prompts one pending request without auto-contact.

**Inspected test evidence**

- [test/features/contact_request/integration/failed_save_preserves_valid_request_test.dart](../../test/features/contact_request/integration/failed_save_preserves_valid_request_test.dart) — `storage failure on a valid incoming request withholds direct ACK, keeps ProductionCanonicalDirectReplayComposition.replayContactRequest retryable, and surfaces the request once across duplicate replays after storage recovers` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; P2PService/ProductionCanonicalDirectReplayComposition receive completion.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks; SQL upsert throws until repaired.
  - Proves / registration: test/features/contact_request/integration/failed_save_preserves_valid_request_test.dart:420: Failed write withholds positive direct ACK and replay remains retryable; after repair duplicate processing stores one pending row/prompt and no contact, with original current owner. Registered: affected-identity, host-all.

**Remaining gaps**

- Source-disabled KNOWN GAP CR-020: failed_save_preserves_valid_request_test.dart:637-638 skips the defining failed-save/ACK recovery case. Incoming storage failure can become invalidMessage and positive completion/custody commit without a saved request. Default gates cannot fail this disabled defining assertion.
- Native transport ACK wire, device SQLCipher and OS storage failure behavior were not executed.

#### CR-021 — You can add a contact without the camera

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-021.

**Steps**

1. Open Paste QR Data without using camera.
2. Submit valid signed QR and wait for verification.
3. Reach added-contact/request handoff under same validation policy.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: manually pasted QR JSON; recovery: n/a.

**Expected:** Manual entry remains a usable validated contact path without camera access.

**Inspected test evidence**

- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `a scan finishes after the scanner route has already closed` (widget).
  - Real: actual Paste QR Data dialog/Submit and retained host handoff.
  - Faked: gated bridge verification; P2P/repositories/platform camera.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:681: Explicit pasted Submit auto-closes scanner, later verification adds exact contact/request and reaches Feed. This is accepted-scan handoff, not cancellation before submitting. Registered: affected-identity, host-all.
- [test/features/qr_code/application/parse_qr_identity_binding_test.dart](../../test/features/qr_code/application/parse_qr_identity_binding_test.dart) — `K2 self-signs a QR that claims K1 peer ID: rejected before any contact is built` (unit).
  - Real: real parser/Ed25519 verification/production peer-ID derivation.
  - Faked: test account keys and clock.
  - Proves / registration: test/features/qr_code/application/parse_qr_identity_binding_test.dart:103: Self-signed K2 cannot claim K1 peer ID; valid own-key/derived-ID controls and canonical field ordering are accepted. No scanner camera/native bridge. Registered: affected-identity, host-all.

**Remaining gaps**

- Actual pasted Submit/handoff is asserted with fake bridge/network/repositories; real OS clipboard input and native crypto/recipient acceptance are separate.

#### CR-022 — Your own QR code is signed and fails safely

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-022.

**Steps**

1. Build My QR from current identity.
2. Sign canonical payload and render code.
3. Fail signing/malformed response and Retry without exposing bogus successful code.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: valid identity versus absent/malformed/failed signing; recovery: n/a.

**Expected:** Only successfully signed current identity becomes a displayed QR; failure remains explicit/retryable.

**Inspected test evidence**

- [test/features/qr_code/application/build_qr_payload_use_case_test.dart](../../test/features/qr_code/application/build_qr_payload_use_case_test.dart) — `success: builds signed QR payload with sorted keys` (unit).
  - Real: real QR construction/canonical ordering.
  - Faked: signing callback/identity repository.
  - Proves / registration: test/features/qr_code/application/build_qr_payload_use_case_test.dart:49: Sorted payload and signing input are asserted; callback signature is supplied. Real signed build->parse path exists in decline integration, not this unit alone. Registered: affected-identity, host-all.
- [test/features/qr_code/presentation/screens/qr_display_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_display_wired_test.dart) — `retry button rebuilds payload after error` (widget).
  - Real: actual QR display failure/Retry widget.
  - Faked: bridge signing result/repository.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_display_wired_test.dart:125: Error shows Retry; tapping retries signing and displays QR after recovery. Actual native signature/QR decode scan is separate. Registered: affected-identity, host-all.
- [test/features/contact_request/integration/declining_request_adds_no_contact_test.dart](../../test/features/contact_request/integration/declining_request_adds_no_contact_test.dart) — `decline adds no contact on Alice, sends nothing to Bob, ignores an old replayed envelope, survives restart, and forces a fresh request onto manual consent` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; real listener/decline/replay and file reopen.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/declining_request_adds_no_contact_test.dart:138: Decline retains no contact/outbound reciprocal, old envelope after reopen stays declined and fresh request needs manual consent; fake encryption does not prove native privacy. Registered: affected-identity, host-all.

**Remaining gaps**

- QR build/render tests fake signing; decline integration independently uses real Ed25519 build/parse. Native keychain/signing bridge/camera decoding on installed app is not joined.

#### CR-023 — Move Account and linked-device QR codes never add a contact

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-023.

**Steps**

1. Scan Move Account or linked-device document in a contact entry.
2. Dispatch only to its authorized dedicated handler or refuse.
3. Inspect zero ordinary contact/request side effects.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: migration/linked QR with and without authorized handler; recovery: n/a.

**Expected:** Different QR protocols cannot fall through to contact admission.

**Inspected test evidence**

- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `migration QR dispatches to migration handler without contact side effects` (widget).
  - Real: actual QR protocol dispatch before ordinary parser.
  - Faked: camera callback and recording migration handler; bridge/repos.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:255: Migration QR goes to Move Account handler with zero contact/request path effects; dedicated linked QR case similarly avoids contact parser. Registered: affected-identity, host-all.
- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `TC-360-02a dual-signed linked-device QR stages only exact known-contact pending authority` (widget).
  - Real: actual QR scan protocol dispatch and no-contact side-effect boundary.
  - Faked: scanner onScanned callback instead of camera; linked handler; fake bridge/repos.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:777: Linked document goes only to dedicated trust handler; ordinary scan without handler refuses instead of falling through to contact parser/encryption. Registered: affected-identity, host-all.

**Remaining gaps**

- Causal protocol-dispatch guards exist at widget callback seams; actual native camera and full dedicated migration/linked handler are separate.

#### CR-024 — A request from someone you were introduced to finishes the introduction

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-024.

**Steps**

1. Keep one qualifying introduction already accepted by the local user.
2. Receive authenticated request from the introduced peer.
3. Complete only unambiguous eligible intro; preserve declined/deleted/ambiguous cases.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: recipient/introduced, one/two qualifying intro, decline/delete; recovery: n/a.

**Expected:** Recovery can finish prior consent without granting new/ambiguous consent.

**Inspected test evidence**

- [test/features/contact_request/integration/introduced_contact_request_recovery_test.dart](../../test/features/contact_request/integration/introduced_contact_request_recovery_test.dart) — `recipient` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; real request/introduction recovery handlers.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/introduced_contact_request_recovery_test.dart:254: Parameterized recipient/introduced/unique versus ambiguous/declined/deleted cases process real signed incoming request through SQL; only qualifying accepted introduction completes, ambiguous/non-consent cases preserve no connection. Registered: affected-identity, host-all.

**Remaining gaps**

- Real signed request/SQL recovery matrix is meaningful; encryption/transport/secure-store remain fake and actual multi-party UI/native crypto is unverified.

#### CR-025 — Old QR codes are refused

**Coverage:** strong. **Execution:** not_run. **Catalog:** CR-025.

**Steps**

1. Scan signed QR beyond24h, malformed time or far-future time.
2. Check no contact/request/send side effects.
3. Use fresh signed control.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: older-than24h, unreadable, future versus fresh timestamp; recovery: n/a.

**Expected:** Expired or invalid-time QR is refused while fresh valid code works.

**Inspected test evidence**

- [test/features/qr_code/presentation/screens/qr_timestamp_admission_test.dart](../../test/features/qr_code/presentation/screens/qr_timestamp_admission_test.dart) — `is refused without contact or outbound request` (widget).
  - Real: real scanner admission/SQL fixture; real signed QR fixtures.
  - Faked: native scanner callback/network/lookup encryption.
  - Proves / registration: Expired, unreadable and future signed timestamp groups all actively reject before any contact/request/outbound/encryption side effect; the fresh signed control succeeds. All four scanner cases pass. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/006-qr-admission.log. Registered: affected-identity, host-all.
- [test/features/qr_code/application/parse_qr_identity_binding_test.dart](../../test/features/qr_code/application/parse_qr_identity_binding_test.dart) — `K2 self-signs a QR that claims K1 peer ID: rejected before any contact is built` (unit).
  - Real: real parser/Ed25519 verification/production peer-ID derivation.
  - Faked: test account keys and clock.
  - Proves / registration: test/features/qr_code/application/parse_qr_identity_binding_test.dart:103: Self-signed K2 cannot claim K1 peer ID; valid own-key/derived-ID controls and canonical field ordering are accepted. No scanner camera/native bridge. Registered: affected-identity, host-all.

**Remaining gaps**

- All four scanner timestamp cases pass with real signed input and SQL. Native camera acquisition, platform clock correctness and actual remote network delivery remain modeled.

#### CONTACT-001 — Cancel the QR camera or deny camera permission without adding a contact

**Coverage:** partial. **Execution:** device_run. **Catalog:** CR-001, CR-021.

**Steps**

1. Open QR camera then cancel before reporting a code, or deny OS camera access.
2. Return to prior surface without adding/sending contact.
3. Grant access/reopen and scan a fresh code.

**Conditions:** platform: executor-reported Pixel6 physical plus available headless Android emulator; disposable Group D debug package; connectivity: n/a; offline: n/a; app state: foreground; input: cancel before scan result; deny/grant; recovery: reopen scanner.

**Expected:** Native cancel/denial preserves contact/consent and offers truthful camera recovery.

**Group D device execution (2026-10-22; flutter_app)**

- Result: **PASS_PERMISSION_PASTE_PIPELINE_OPTICAL_SCAN_AND_DUPLICATE_NOT_RUN**.
- Scanner close had no effects; OS denial displayed Camera permission denied; grant via Settings recovered the permission path.
- Actual camera scanning could not be exercised. Debug Paste QR was used for fixture entry; one request, one contact and the exact first message passed. Duplicate scan was not exercised.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/SUMMARY.md:4`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/shots/c001_2_after_close.png`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/shots/c001_4_after_deny.png`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/shots/c001_5_after_grant.png`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/shots/c001_6_after_paste.png`.

**Inspected test evidence**

- [test/features/qr_code/presentation/screens/qr_camera_permission_journey_test.dart](../../test/features/qr_code/presentation/screens/qr_camera_permission_journey_test.dart) — `CONTACT-001 cancelled camera admits no code; grant and reopen admits a fresh code once` (widget).
  - Real: real QRScannerScreen route and MobileScannerController; cancel/denial closes without admission callback; grant/reopen accepts one fresh barcode despite duplicate native-stream events.
  - Faked: MobileScannerPlatform permission/camera/view/stream; downstream contact handler replaced by admission recorder; no real QR payload authentication, contact/request repository mutation, OS Settings or full Orbit/root handoff.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_camera_permission_journey_test.dart:15: Fresh file014:2 passed,0 skipped/failed,exit0. Only callback admission is proved; native zero-contact/request and accepted add require device/root journey. Evidence .codex-test-logs/astra-groupCD/014-D-qr-permission-summary.json/receipt. Registered: affected-identity, host-all.
- [test/features/qr_code/presentation/screens/qr_camera_permission_journey_test.dart](../../test/features/qr_code/presentation/screens/qr_camera_permission_journey_test.dart) — `CONTACT-001 denied camera admits no code; grant and reopen admits a fresh code once` (widget).
  - Real: real QRScannerScreen route and MobileScannerController; cancel/denial closes without admission callback; grant/reopen accepts one fresh barcode despite duplicate native-stream events.
  - Faked: MobileScannerPlatform permission/camera/view/stream; downstream contact handler replaced by admission recorder; no real QR payload authentication, contact/request repository mutation, OS Settings or full Orbit/root handoff.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_camera_permission_journey_test.dart:15: Fresh file014:2 passed,0 skipped/failed,exit0. Only callback admission is proved; native zero-contact/request and accepted add require device/root journey. Evidence .codex-test-logs/astra-groupCD/014-D-qr-permission-summary.json/receipt. Registered: affected-identity, host-all.

**Remaining gaps**

- Paste QR entry is not camera recognition. Actual optical scan and duplicate scan remain unproven; permission/UI-to-request/contact/message evidence is narrower. No complete fresh native camera-add journey is inferred.

**Open questions**

- Execution by flutter_app; Astra inspected saved evidence only. See header.group_d_device_run for source/artifact provenance and scope.
- Existing handoff: docs/testing/astra-group-d-device-runbook.md. Actual failures, weaker witnesses and unrun legs above are retained; no rating upgrade.

#### CONTACT-002 — Scan continuously or double-submit one QR without duplicate side effects

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-005.

**Steps**

1. Report the same QR repeatedly or double Submit while verification waits.
2. Complete one accepted scan.
3. Inspect contact/request/repair identities without duplicate side effects.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: continuous duplicate QR callbacks/double submit; recovery: pending verification completion.

**Expected:** Repeated scan intent dispatches only appropriate idempotent work.

**Inspected test evidence**

- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `scanning an existing contact shows the circle dialog and re-sends our request without touching the stored row` (widget).
  - Real: actual existing-contact scan preservation/hand-off.
  - Faked: bridge/P2P/identity/contact repository.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:375: Rescan shows existing-circle dialog/resends request without profile download, delete, duplicate or overwritten stored row; real SQL repair tested separately. Registered: affected-identity, host-all.
- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-005 live plus inbox duplicate and listener restart retain one consent dialog` (widget).
  - Real: real listener/dialog/retained pending SQL.
  - Faked: fake network/native/lookup encryption.
  - Proves / registration: test/features/contact_request/presentation/screens/pending_request_shell_test.dart:150: Live+inbox duplicate and listener restart keep one dialog/pending row under the tested single-shell setup; two shell subscribers have a separate skipped known-gap test. Registered: affected-identity, host-all.
- [test/features/contact_request/integration/contact_repair_two_party_test.dart](../../test/features/contact_request/integration/contact_repair_two_party_test.dart) — `B deletes and re-adds A from A's compact QR twice; each time one signed request earns one reply that repairs B` (integration).
  - Real: production current FFI SQLite schema/repositories; real Ed25519 signatures/peer derivation; real repair request/reply/outbox orchestration.
  - Faked: lookup-table contact-request encryption/ML-KEM fixtures; FakeP2PNetwork; FakeSecureKeyStore/native avatar callbacks.
  - Proves / registration: test/features/contact_request/integration/contact_repair_two_party_test.dart:253: Each repeated re-add repairs receiver ML-KEM/grant with one signed request/reply; no reply-to-reply loop. DB/real signatures are meaningful; network/ML-KEM are modeled. Registered: affected-identity, host-all.

**Remaining gaps**

- Real rescan/receive duplicate mechanisms are covered; continuous camera callbacks/double Submit before first parse and all native egress counts are not one causal test.

#### CONTACT-003 — Share or copy My QR from Orbit/settings and return safely

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-022.

**Steps**

1. Open My QR from Orbit/Settings.
2. Copy QR data through its long-press affordance and return.
3. Keep same Settings/Orbit route and valid current signed data.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: current signed My QR; long-press copy; recovery: close/back to same host.

**Expected:** QR entry/copy/return preserves exact signed account data and route ownership.

**Inspected test evidence**

- [test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart](../../test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart) — `T8: My QR from Settings reaches the display; close returns to the same Settings; ScanFriendCard cross-link opens the scanner` (widget).
  - Real: real Orbit->Settings->QR display/scan routes.
  - Faked: signing bridge; identity/contact/storage/P2P services; scanner capture.
  - Proves / registration: test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart:547: Closing QR returns to the same Settings route; reopening and cross-linking opens one scanner screen. No native camera scan. Registered: affected-identity, affected-surfaces, host-all.
- [test/features/qr_code/presentation/screens/qr_display_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_display_wired_test.dart) — `retry button rebuilds payload after error` (widget).
  - Real: actual QR display failure/Retry widget.
  - Faked: bridge signing result/repository.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_display_wired_test.dart:125: Error shows Retry; tapping retries signing and displays QR after recovery. Actual native signature/QR decode scan is separate. Registered: affected-identity, host-all.

**Remaining gaps**

- Copy is implemented at qr_code_section.dart:139 (Clipboard.setData) but its tests only cover render/loading/error, not long-press copy bytes/failure. Native external QR share is not claimed as an implemented app action.

#### CONTACT-004 — Open contact profile from Orbit/avatar and return to the same conversation

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open profile from current conversation/avatar/Orbit.
2. Read contact metadata and return.
3. Keep intended underlying conversation/scroll/read ownership.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: selected contact profile/avatar; recovery: Back/edge swipe.

**Expected:** Profile is for the selected contact and Back returns without losing the retained conversation.

**Inspected test evidence**

- [test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart](../../test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart) — `the back button pops the screen` (widget).
  - Real: actual ContactProfileScreen open/Back Navigator.
  - Faked: fixture contact/host route.
  - Proves / registration: test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart:236: Profile pop returns to launcher; production avatar routes are source-wired at conversation_wired.dart:8592 and orbit_wired.dart:2863, not exercised by this test. Registered: host-all.
- [test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart](../../test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart) — `peer ID and safety-number copy use the shared quiet pill` (widget).
  - Real: actual profile copy handlers and safety-number computation.
  - Faked: Clipboard.setData MethodChannel handler; fixture contact.
  - Proves / registration: test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart:119: Two taps send exact peer identifier and computed safety number; quiet confirmations show. No trust mutation interface is invoked; failed OS clipboard not tested. Registered: host-all.

**Remaining gaps**

- Profile open/Back is tested with launcher fixture; actual conversation/Orbit avatar source wiring exists but same-conversation/state-return is not asserted in that test.

#### CONTACT-005 — Copy peer identifier and safety number without changing contact trust

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open contact profile identifiers/safety number.
2. Copy each exact value.
3. Preserve contact/key/device trust and display truthful feedback.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: peer identifier and computed safety number; recovery: n/a.

**Expected:** Copy does not mutate trust and transfers the current exact identifier/computed safety number.

**Inspected test evidence**

- [test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart](../../test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart) — `peer ID and safety-number copy use the shared quiet pill` (widget).
  - Real: actual profile copy handlers and safety-number computation.
  - Faked: Clipboard.setData MethodChannel handler; fixture contact.
  - Proves / registration: test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart:119: Two taps send exact peer identifier and computed safety number; quiet confirmations show. No trust mutation interface is invoked; failed OS clipboard not tested. Registered: host-all.

**Remaining gaps**

- Exact clipboard channel bytes/feedback are asserted; platform failure and explicit persisted trust-unchanged query are absent from this widget case.

#### CONTACT-006 — Archive/unarchive a contact while preserving history and ingress policy

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Archive/unarchive a contact.
2. Retain direct history and current block/key authority.
3. Receive new activity and reopen correct filtered surface.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: archive/unarchive with prior history; recovery: incoming activity/remount.

**Expected:** Archive is a presentation preference; it must not erase trusted history or become unintended ingress authorization.

**Inspected test evidence**

- [test/features/contacts/application/archive_contact_use_case_test.dart](../../test/features/contacts/application/archive_contact_use_case_test.dart) — `calls repo.archiveContact with peerId` (unit).
  - Real: actual archive use-case dispatch.
  - Faked: recording contact repository.
  - Proves / registration: test/features/contacts/application/archive_contact_use_case_test.dart:46: Calls archive for exact peer; this tiny delegation case alone proves no history retention or restart. Registered: affected-identity, host-all.
- [test/features/contacts/integration/direct_notification_projection_lifecycle_test.dart](../../test/features/contacts/integration/direct_notification_projection_lifecycle_test.dart) — `direct reaction projection covers contact and authored-target lifecycle` (integration).
  - Real: actual direct notification contact/target projection policy.
  - Faked: memory secure store and fixture contact changes.
  - Proves / registration: test/features/contacts/integration/direct_notification_projection_lifecycle_test.dart:10: Block/archive/unblock/delete update exact projection and exclude private authored text/key values. Native provider/extension state is not exercised. Registered: affected-identity, host-all.
- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `scanning an existing contact shows the circle dialog and re-sends our request without touching the stored row` (widget).
  - Real: actual existing-contact scan preservation/hand-off.
  - Faked: bridge/P2P/identity/contact repository.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:375: Rescan shows existing-circle dialog/resends request without profile download, delete, duplicate or overwritten stored row; real SQL repair tested separately. Registered: affected-identity, host-all.

**Remaining gaps**

- Tiny archive use case only delegates; projection/rescan preservation supports narrower contracts. Real history/restart/unarchive/ingress UI composition not fully established.

#### CONTACT-007 — Delete a contact from Orbit with cancel/confirm and preserve unrelated users

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-013.

**Steps**

1. Request delete from Orbit.
2. Cancel or explicitly confirm intended contact.
3. Purge exact owned state while preserving other contacts/group data.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: delete cancel/confirm; colliding direct/group IDs; recovery: n/a.

**Expected:** Cancel changes nothing; confirmed delete affects only selected contact-owned data.

**Inspected test evidence**

- [test/features/contacts/application/delete_contact_use_case_test.dart](../../test/features/contacts/application/delete_contact_use_case_test.dart) — `contact deletion preserves same id group and unresolved media` (unit).
  - Real: production current SQLite media repositories/owner-scoped cleanup.
  - Faked: contact/message cleanup seams; fixture media/secure store.
  - Proves / registration: test/features/contacts/application/delete_contact_use_case_test.dart:1113: Deletes direct-owned media for colliding message ID, preserves same-ID group and unresolved rows; actual OS file/native notification cleanup is separate. Registered: affected-identity, host-all.
- [test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart](../../test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart) — `the back button pops the screen` (widget).
  - Real: actual ContactProfileScreen open/Back Navigator.
  - Faked: fixture contact/host route.
  - Proves / registration: test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart:236: Profile pop returns to launcher; production avatar routes are source-wired at conversation_wired.dart:8592 and orbit_wired.dart:2863, not exercised by this test. Registered: host-all.

**Remaining gaps**

- Real ownership cleanup exists, but profile Back does not prove Orbit delete cancel/confirm. No single actual Orbit confirmation->full real cleanup->restart journey established.

#### CONTACT-008 — Profile name/avatar updates converge without replacing newer identity keys

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-019.

**Steps**

1. Receive changed peer name/avatar and valid newer key fields.
2. Refresh profile/home projection.
3. Reject stale/conflicting key update while preserving newest trusted identity.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: name/avatar refresh versus newer/older key update; recovery: n/a.

**Expected:** Profile refresh may update current metadata without rolling back identity keys/trust.

**Inspected test evidence**

- [test/features/settings/application/profile_update_listener_test.dart](../../test/features/settings/application/profile_update_listener_test.dart) — `emits updated contact when download succeeds with normalization` (unit).
  - Real: ProfileUpdateListener contact refresh dispatch.
  - Faked: download callback and contact repository.
  - Proves / registration: test/features/settings/application/profile_update_listener_test.dart:232: New avatarVersion/path emitted after injected normalized download; normalizer/native transport/identity-key preservation is outside this callback case. Registered: affected-surfaces, host-all.
- [test/features/contact_request/application/existing_contact_repair_receive_test.dart](../../test/features/contact_request/application/existing_contact_repair_receive_test.dart) — `first key lands, newer rotation lands, older replay and equal-instant different key are ignored` (unit).
  - Real: actual existing-contact receive/instant ordering and authority checks; real Ed25519 request fixtures.
  - Faked: receive harness repositories/grant/token callbacks; encryption lookup model.
  - Proves / registration: test/features/contact_request/application/existing_contact_repair_receive_test.dart:597: Newer ML-KEM public key replaces older; older replay and equal instant with different key do not. Offset timestamp normalizes by instant, not lexicographic order. Registered: affected-identity, host-all.
- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `scanning an existing contact shows the circle dialog and re-sends our request without touching the stored row` (widget).
  - Real: actual existing-contact scan preservation/hand-off.
  - Faked: bridge/P2P/identity/contact repository.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:375: Rescan shows existing-circle dialog/resends request without profile download, delete, duplicate or overwritten stored row; real SQL repair tested separately. Registered: affected-identity, host-all.

**Remaining gaps**

- Listener download callback and widget repositories are fake; actual normalized image bytes/network/UI plus concurrent key-authority update not joined.

#### CONTACT-009 — Scan another user while a call, modal or migration flow is active

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-023.

**Steps**

1. Open scanner while call/modal/migration context is active.
2. Submit or close under the route’s allowed policy.
3. Settle accepted intent without duplicate navigation or bypassing blocked account authority.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: call/modal/migration active; input: QR scan or accepted late completion; recovery: n/a.

**Expected:** Only permitted explicit scan intent completes, under current route/account/call ownership.

**Inspected test evidence**

- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `a scan finishes after the scanner route has already closed` (widget).
  - Real: actual Paste QR Data dialog/Submit and retained host handoff.
  - Faked: gated bridge verification; P2P/repositories/platform camera.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:681: Explicit pasted Submit auto-closes scanner, later verification adds exact contact/request and reaches Feed. This is accepted-scan handoff, not cancellation before submitting. Registered: affected-identity, host-all.
- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `migration QR dispatches to migration handler without contact side effects` (widget).
  - Real: actual QR protocol dispatch before ordinary parser.
  - Faked: camera callback and recording migration handler; bridge/repos.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:255: Migration QR goes to Move Account handler with zero contact/request path effects; dedicated linked QR case similarly avoids contact parser. Registered: affected-identity, host-all.
- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `TC-360-02a dual-signed linked-device QR stages only exact known-contact pending authority` (widget).
  - Real: actual QR scan protocol dispatch and no-contact side-effect boundary.
  - Faked: scanner onScanned callback instead of camera; linked handler; fake bridge/repos.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:777: Linked document goes only to dedicated trust handler; ordinary scan without handler refuses instead of falling through to contact parser/encryption. Registered: affected-identity, host-all.

**Remaining gaps**

- Late accepted-scan handoff and dedicated protocol dispatch are tested; ongoing native call/modal/migration authority interruption is not a joined test.

**Open questions**

- Which scanner entries are intentionally usable during an active call or blocked migration? Existing late-scan test defines completion after accepted Submit, not user cancellation.

#### CONTACT-010 — Receive a request near expiry or after expiry across restart

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-006.

**Steps**

1. Receive request just inside/outside expiry or with future/malformed timestamp.
2. Persist/restart and replay at current effective clock.
3. Keep only eligible pending consent and refuse stale authority changes.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: near/past request lifetime and clock skew; recovery: restart/replay effective clock.

**Expected:** Expiry/replay never creates implicit consent or rolls current trusted keys backward.

**Inspected test evidence**

- [test/features/contact_request/application/handle_incoming_message_use_case_test.dart](../../test/features/contact_request/application/handle_incoming_message_use_case_test.dart) — `v2 ts older than 24h → invalidMessage` (unit).
  - Real: actual v2 request-envelope freshness policy.
  - Faked: crypto bridge/repository inputs.
  - Proves / registration: test/features/contact_request/application/handle_incoming_message_use_case_test.dart:1056: Relative older-than24h outer envelope is invalidMessage with null request; future>5min companion test independently rejects future request timestamp. Different policy from legacy QR timestamp gap. Registered: affected-identity, host-all.
- [test/features/contact_request/application/existing_contact_repair_receive_test.dart](../../test/features/contact_request/application/existing_contact_repair_receive_test.dart) — `first key lands, newer rotation lands, older replay and equal-instant different key are ignored` (unit).
  - Real: actual existing-contact receive/instant ordering and authority checks; real Ed25519 request fixtures.
  - Faked: receive harness repositories/grant/token callbacks; encryption lookup model.
  - Proves / registration: test/features/contact_request/application/existing_contact_repair_receive_test.dart:597: Newer ML-KEM public key replaces older; older replay and equal instant with different key do not. Offset timestamp normalizes by instant, not lexicographic order. Registered: affected-identity, host-all.
- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-003 stored request replays on first attach and stays until declined` (widget).
  - Real: real Feed request/dialog/listener flow; current SQLite and real Ed25519.
  - Faked: fake network/native services/lookup encryption.
  - Proves / registration: test/features/contact_request/presentation/screens/pending_request_shell_test.dart:54: Persisted request replays at attach and stays until Decline; suppression-release case is a separate skipped known gap. Registered: affected-identity, host-all.

**Remaining gaps**

- Actual v2 envelope freshness and key ordering are tested; full near-expiry real SQL restart/provider delivery is not joined.
- Known legacy QR malformed/future skip is a different input boundary and is not generalized to v2 request expiry.

### CHAT — Direct text and conversation state

#### DC-001 — Bidirectional text delivery smoke

**Coverage:** strong. **Execution:** not_run. **Catalog:** DC-001.

**Steps**

1. Prepare two authorized Android contacts.
2. Send five alternating text messages through the production path.
3. Compare every sender/recipient row and exact text/lane/owner.

**Conditions:** platform: registered Android pair campaign; host fake-user companion tests; connectivity: online production routing S5; offline: n/a; app state: foreground; input: three A->B/two B->A texts; recovery: n/a.

**Expected:** Every intended online message reaches its recipient once with matching content and identity.

**Inspected test evidence**

- [tool/sims/production_routing_criteria.dart](../../tool/sims/production_routing_criteria.dart) — `production.routing_smoke / S5` (sims).
  - Real: registered actual Android production send/receive and exact SQL receipt observations when executed; artifact-bound typed criteria.
  - Faked: campaign prepares contacts and controls app/network transitions.
  - Proves / registration: tool/sims/production_routing_criteria.dart:164: S5 requires3 A->B and2 B->A exchanges, every one received with exact message/text/lane/conversation checks at:72. Registered runner run_production_routing.dart. No run/artifact validated here; protocol send bypasses composer gestures. Registered: see cited native runner/manifest.
- [test/features/conversation/integration/two_user_message_exchange_test.dart](../../test/features/conversation/integration/two_user_message_exchange_test.dart) — `Rapid five-round burst preserves delivered state and full order for both users` (integration).
  - Real: actual send/receive listeners/status and conversation ordering.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories.
  - Proves / registration: test/features/conversation/integration/two_user_message_exchange_test.dart:1351: Five alternating rounds produce ten correctly ordered messages on each endpoint and five exact incoming events per user; no100-message burst/restart or real socket. Registered: affected-conversation, direct-chat, host-all.
- [test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart](../../test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart) — `ACK loss after recipient commit then inbox fallback displays one identity` (integration).
  - Real: actual send/receive/inbox-drain dedup orchestration.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories.
  - Proves / registration: test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart:61: Lost live ACK followed by inbox replay yields one exact recipient row/ID/text while sender remains inboxed until receipt; no real deployed relay/SQL durability. Registered: affected-conversation, host-all, quiet-recovery.

**Remaining gaps**

- Strong is scoped to the registered five-message delivery smoke, not100-message/restart, composer UI or signed-store parity. Campaign/artifact was not executed/validated here.

#### DC-002 — 100 messages in order, no duplicates

**Coverage:** partial. **Execution:** device_run. **Catalog:** DC-002.

**Steps**

1. Send100 identified messages in order.
2. Restart both peers and replay retained work.
3. Compare complete ordered transcript and exact one-copy rows on both sides.

**Conditions:** platform: executor-reported Pixel6 physical plus available headless Android emulator; disposable Group D debug package; host evidence only; connectivity: n/a; offline: n/a; app state: both peers restart; input: 100-message burst and duplicate replay; recovery: replay dedup.

**Expected:** All100 messages remain complete/in order/unique after both-peer restart.

**Group D device execution (2026-10-22; flutter_app)**

- Result: **PASS_REPORTED_ANDROID_DEBUG_PAIR**.
- Executor reports 100/100 exact texts with five kill/relaunch checkpoints at25/50/75/100 and final reopen; no loss or duplication. Offline item051 had custody confirmation and caught up.
- Saved JSONL independently inspected as redacted aggregates: both endpoint result maps have rows25/50/75/100/100, exact=true, dups=0, missing=[], order_ok=true and nonexact_rows=0. No application text or device identifiers were copied into this matrix.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/SUMMARY.md:6`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/dc002_run.jsonl:26`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/dc002_run.jsonl:52`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/dc002_run.jsonl:80`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/dc002_run.jsonl:106`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/dc002_run.jsonl:108`.

**Inspected test evidence**

- [test/features/conversation/integration/group_a_text_journeys_test.dart](../../test/features/conversation/integration/group_a_text_journeys_test.dart) — `DC-002 DC-014 one hundred numbered messages survive both SQL/runtime restarts and inbox replay` (integration).
  - Real: production send/receive/loadConversation with two current-schema file databases; both runtime/SQL graphs rebuilt every 25 messages; all 100 IDs, exact text/order/direction and one-copy rows checked on both; offline custody and retained duplicate wire replay.
  - Faked: FakeP2PNetwork/relay, passthrough crypto and memory contact/key boundaries; no OS process kill.
  - Proves / registration: test/features/conversation/integration/group_a_text_journeys_test.dart:54: Fresh exact case 009: 1 passed, 0 skipped/failed, exit 0. Existing Group A case reused unchanged; real SQL/runtime reopen is meaningful but not native kill or actual relay delivery. Evidence .codex-test-logs/astra-groupCD/009-D-numbered-restarts-summary.json/receipt. Registered: affected-conversation, host-all.

**Remaining gaps**

- Rating retained as instructed. Native execution is scoped to the executor-reported Android disposable debug pair and checkpoints; Astra did not operate devices or independently re-audit the kill actions. It is not signed-candidate or whole-app release certification.

**Open questions**

- Execution by flutter_app; Astra inspected saved evidence only. See header.group_d_device_run for source/artifact provenance and scope.
- Existing handoff: docs/testing/astra-group-d-device-runbook.md. Actual failures, weaker witnesses and unrun legs above are retained; no rating upgrade.

#### DC-003 — Recipient offline for a long time, then catches up once

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-003.

**Steps**

1. Keep recipient offline within supported relay retention.
2. Send ordered messages and retain durable custody.
3. Reconnect/catch up across pages and inspect complete exact-once order.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: sender online/recipient offline then reconnect; offline: long dwell within configured retention; app state: foreground; input: as described; recovery: paged catch-up.

**Expected:** Every retained eligible message arrives once in order without losing later pages or claiming expired history.

**Inspected test evidence**

- [test/features/conversation/integration/offline_inbox_roundtrip_test.dart](../../test/features/conversation/integration/offline_inbox_roundtrip_test.dart) — `FDC-03-06 first-ever offline send deposits a concurrent inbox copy that drains on resume` (integration).
  - Real: real send/listener/inbox-drain use-case composition.
  - Faked: FakeP2PNetwork/in-memory relay; PassthroughCryptoBridge; in-memory repositories.
  - Proves / registration: test/features/conversation/integration/offline_inbox_roundtrip_test.dart:234: First offline send records inbox custody, receiver drain yields one exact-text row; no real relay persistence or long retention. Registered: affected-conversation, host-all, offline-recovery.
- [test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart](../../test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart) — `ACK loss after recipient commit then inbox fallback displays one identity` (integration).
  - Real: actual send/receive/inbox-drain dedup orchestration.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories.
  - Proves / registration: test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart:61: Lost live ACK followed by inbox replay yields one exact recipient row/ID/text while sender remains inboxed until receipt; no real deployed relay/SQL durability. Registered: affected-conversation, host-all, quiet-recovery.

**Remaining gaps**

- Host offline roundtrip uses an in-memory relay and immediate reconnect; source cases named large backlog only send10 and do not prove actual pagination/long dwell/TTL. Actual relay-bound complete transcript remains unverified.

#### DC-004 — Sender app killed mid-send, delivered exactly once

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-004.

**Steps**

1. Start a text send and interrupt the sender before settlement.
2. Restart from accepted durable envelope/row.
3. Retry and compare one recipient row under the same message identity.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: sender killed mid-send; host reconstruction/pause model; input: as described; recovery: same-ID custody retry.

**Expected:** A killed sender neither loses accepted work nor remints a duplicate message after restart.

**Inspected test evidence**

- [test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart](../../test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart) — `all paths fail then reconstructed sender drains original custody` (integration).
  - Real: actual outbox custody drain and sender-owner reconstruction.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories; same in-memory repositories retained across reconstruction.
  - Proves / registration: test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart:105: Failed envelope survives recreated TestUser and drains once under same immutable ID/content; not an actual process kill or on-disk reopen. Registered: affected-conversation, host-all, quiet-recovery.
- [test/features/conversation/integration/send_then_lock_delivery_test.dart](../../test/features/conversation/integration/send_then_lock_delivery_test.dart) — `7. app-killed mid-send recovery reuses the original row and still notifies Bob` (integration).
  - Real: production pause/resume/retry path and receive listener.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories; notification recorder; seeded sending row/pause simulates kill.
  - Proves / registration: test/features/conversation/integration/send_then_lock_delivery_test.dart:1383: Seeded sending row becomes failed on simulated pause, resume reuses ID/inbox custody, recipient gets one exact row and notification. Despite name, no process is killed. Registered: affected-conversation, host-all.

**Remaining gaps**

- One case reuses in-memory stores; another only seeds a row and simulates pause/resume despite its app-killed title. No actual text process-death checkpoint and signed-app recipient proof executed/validated.

#### DC-006 — Reply, react, edit and delete stay in sync

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-006.

**Steps**

1. Send a quoted reply and add/remove a reaction.
2. Edit during failure then retry; delete online/offline.
3. Compare final sender/recipient semantic state and replay dedup.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: quote, reaction add/remove, failed edit, delete; recovery: offline replay/retry.

**Expected:** Quote/reaction/edit/delete converge with current authored identity and no stale duplicate rows.

**Inspected test evidence**

- [test/features/conversation/integration/quote_reply_thread_test.dart](../../test/features/conversation/integration/quote_reply_thread_test.dart) — `5a. Alice sends, Bob quotes — reply arrives with quotedMessageId` (integration).
  - Real: actual quote send/receive and payload hydration.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories.
  - Proves / registration: test/features/conversation/integration/quote_reply_thread_test.dart:48: Reply arrives with exact original quotedMessageId and text; both sides retain correct quote relationship. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/emoji_reaction_exchange_test.dart](../../test/features/conversation/integration/emoji_reaction_exchange_test.dart) — `Toggle reaction: add then remove` (integration).
  - Real: actual reaction route/send/remove/listener handling.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories; in-memory reaction repository.
  - Proves / registration: test/features/conversation/integration/emoji_reaction_exchange_test.dart:114: Both users observe one reaction after Add and none after Remove; authenticated crypto/network/persistence are fake. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/edit_retry_round_trip_test.dart](../../test/features/conversation/integration/edit_retry_round_trip_test.dart) — `sender and receiver text converge after a failed-then-retried edit (divergence repair)` (integration).
  - Real: actual edit/retry/action-aware receive path.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories.
  - Proves / registration: test/features/conversation/integration/edit_retry_round_trip_test.dart:50: Transport blackout leaves failed same-ID edit/envelope; healing/retry makes both conversations display edited text with editedAt, without a fresh message. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/message_deletion_roundtrip_test.dart](../../test/features/conversation/integration/message_deletion_roundtrip_test.dart) — `offline inbox ordering leaves the recipient with a tombstoned final row` (integration).
  - Real: actual deletion custody and receive tombstone processing.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories.
  - Proves / registration: test/features/conversation/integration/message_deletion_roundtrip_test.dart:76: Offline delete remains a visible sender tombstone until receiver confirmation; after drain receiver is tombstoned. Real relay/restart remain outside this case. Registered: affected-conversation, host-all.

**Remaining gaps**

- Causal individual roundtrips exist with fake crypto/network/in-memory stores; no full real-peer sequence with durable restart and current UI assertions.

#### DC-007 — In-flight, failure, retry and transport status stay truthful

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-007.

**Steps**

1. Send and observe in-flight/failure/retry.
2. Acquire relay custody, then receive authenticated delivery confirmation.
3. Observe persisted monotonic status and correct transport glyph.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: sending/failed/inboxed/delivered with direct/relay/inbox transport; recovery: retry/duplicate receipt.

**Expected:** Custody remains distinct from receiver delivery and glyph/status cannot downgrade or duplicate rows.

**Inspected test evidence**

- [test/features/conversation/integration/delivery_receipt_roundtrip_test.dart](../../test/features/conversation/integration/delivery_receipt_roundtrip_test.dart) — `relay-inbox arrival mints a delivery receipt that the sender applies, flipping the outgoing row 'inboxed' -> 'delivered'` (integration).
  - Real: actual receipt mint/listener/application.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories.
  - Proves / registration: test/features/conversation/integration/delivery_receipt_roundtrip_test.dart:52: Recipient storage generates receipt; sender changes inboxed to delivered and clears envelope. Duplicate receipt companion case is idempotent. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart) — `sending → inboxed/inbox → delivered/inbox keeps the inbox glyph` (widget).
  - Real: actual conversation stream/widget glyph projection.
  - Faked: fake repository emitted status/transport changes; platform/service dependencies.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart:525: In-flight one tick changes to inbox glyph on custody and remains inbox on receiver-delivered; explicitly no delivered double tick. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart) — `message transitions from sending to failed via messageChanges stream and UI rebuilds with the failed indicator icon` (widget).
  - Real: actual reactive status-to-failed widget update.
  - Faked: fake repository status event and service dependencies.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart:335: Stream transition replaces sending tick with failed affordance; native lifecycle event is not induced. Registered: affected-conversation, host-all.

**Remaining gaps**

- Receipt composition and actual UI are separate fake-network/repository tests. No real remote receipt/native lifecycle-to-persisted-current-widget combined proof. Current UI intentionally retires delivered double-check/read ladder.

#### DC-010 — Relay-only path delivers

**Coverage:** strong. **Execution:** not_run. **Catalog:** DC-010.

**Steps**

1. Let known-peer keepalive miss naturally twice.
2. Send with drop latched and verify direct leg is skipped.
3. Gain relay custody, recover recipient and inspect one exact row/correlated receipt.

**Conditions:** platform: registered Android pair prepared main APK; connectivity: natural keepalive drop -> relay/inbox -> restored peer; offline: n/a; app state: foreground; input: as described; recovery: correlated receipt and peer ping.

**Expected:** A doomed direct attempt is skipped; relay custody recovers exactly one intended message and re-arms peer health.

**Inspected test evidence**

- [integration_test/scripts/android_keepalive_drop_campaign.dart](../../integration_test/scripts/android_keepalive_drop_campaign.dart) — `android.keepalive_drop_skip_direct` (sims).
  - Real: prepared production Android pair/real keepalive/relay/inbox/receipt; exact run-bound recipient message observation.
  - Faked: controlled receiver node stop/recovery and contact setup.
  - Proves / registration: integration_test/scripts/android_keepalive_drop_campaign.dart:34: Waits for two natural keepalive misses, then asserts no direct attempt, subsecond relay custody and exact correlated receipt/rearm; receiver requires exactly one run-bound row at:492. Actual campaign not executed here. Registered: see cited native runner/manifest.
- [test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart](../../test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart) — `ACK loss after recipient commit then inbox fallback displays one identity` (integration).
  - Real: actual send/receive/inbox-drain dedup orchestration.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories.
  - Proves / registration: test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart:61: Lost live ACK followed by inbox replay yields one exact recipient row/ID/text while sender remains inboxed until receipt; no real deployed relay/SQL durability. Registered: affected-conversation, host-all, quiet-recovery.

**Remaining gaps**

- Strong is scoped to the existing registered keepalive-drop proof, which was not executed here. Does not certify iOS, arbitrary relay outages, signed-store artifact or media decoder.

#### DC-011 — iPhone and Android chat with each other

**Coverage:** partial. **Execution:** device_run. **Catalog:** DC-011.

**Steps**

1. Establish authorized iPhone/Android contacts.
2. Exchange text and full image/video/voice media both directions.
3. Verify correct content/native open/play plus recovery on each platform.

**Conditions:** platform: iPhone 13 and Pixel 6; actual owner-run debug/FLOW-log cross-platform candidate; connectivity: n/a; offline: n/a; app state: foreground; input: bidirectional text and real media; recovery: n/a.

**Expected:** Supported cross-platform peers interoperate with correct full usable content in both directions.

**Device execution (2026-10-22; flutter_app)**

- Result: **PASS_CONTENT_PLAYBACK_STRUCTURE_AUDIO_CONTENT_UNVERIFIED**.
- Text passed both directions with exact content/order and one row; camera image evidence is in MEDIA-002/003/014. Voice and video delivered and replayed both directions, with one of each media row per side after both apps relaunched.
- iPhone-to-Pixel voice: about 15 seconds to stored audio/mp4 and about five seconds AudioTrack playback. Reverse voice: direct delivery within 25 seconds and advancing iPhone player. Reverse video: cellular relay within 30 seconds and advancing player.
- First iPhone-to-Pixel video download failed on cellular relay; visible download failure retained. Automatic retry recovered without a tap by 75 seconds after send; full file 255715 bytes, 7.17 seconds, 215 video frames at 320x568 with an audio track. Playback/replay activity was observed.
- Initial text entry was truncated by WDA automation; runner added composer read-back and resent. This harness correction and the video first-attempt failure are retained, not silently counted as first-attempt success.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:13`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:42`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:44`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:46`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:49`.

**Inspected test evidence**

- [test/features/contacts/contact_request_roundtrip_test.dart](../../test/features/contacts/contact_request_roundtrip_test.dart) — `CR-009/DC-011 shared protocol scanner A accepts reciprocal keys before exact bidirectional Unicode chat` (integration).
  - Real: production request listener, explicit accept/reciprocate, persisted peer-key lookup and v2 send/receive composition; both logical initiating roles; keyless send refused; exact bidirectional Unicode text and one incoming copy.
  - Faked: QR scan/contact insertion simulated; in-memory repositories and FakeP2PNetwork; passthrough crypto and fake native signatures/ML-KEM, not authenticated native transport.
  - Proves / registration: test/features/contacts/contact_request_roundtrip_test.dart:245: Scanner A begins without the recipient ML-KEM key; receiver remains unlinked before acceptance, reciprocal key unlocks both v2 chat directions. Fresh full file: 3 passed, 0 skipped, exit 0 (003-contact-roundtrip-summary.json/receipt under .codex-test-logs/astra-groupCD). Registered: affected-identity, host-all.
- [test/features/contacts/contact_request_roundtrip_test.dart](../../test/features/contacts/contact_request_roundtrip_test.dart) — `CR-009/DC-011 shared protocol scanner B accepts reciprocal keys before exact bidirectional Unicode chat` (integration).
  - Real: production request listener, explicit accept/reciprocate, persisted peer-key lookup and v2 send/receive composition; both logical initiating roles; keyless send refused; exact bidirectional Unicode text and one incoming copy.
  - Faked: QR scan/contact insertion simulated; in-memory repositories and FakeP2PNetwork; passthrough crypto and fake native signatures/ML-KEM, not authenticated native transport.
  - Proves / registration: test/features/contacts/contact_request_roundtrip_test.dart:245: Scanner B begins without the recipient ML-KEM key; receiver remains unlinked before acceptance, reciprocal key unlocks both v2 chat directions. Fresh full file: 3 passed, 0 skipped, exit 0 (003-contact-roundtrip-summary.json/receipt under .codex-test-logs/astra-groupCD). Registered: affected-identity, host-all.
- [test/features/conversation/integration/camera_caption_relay_delivery_test.dart](../../test/features/conversation/integration/camera_caption_relay_delivery_test.dart) — `MEDIA-003/DC-011 reverse logical sender preserves compressed full camera image and caption` (integration).
  - Real: ImageProcessor quality/EXIF argument selection; production upload/send/receive and inbox staging/replay; current SQLite repositories and real files; hash equality; grid admission and full received-image decode/caption.
  - Faked: native compressor returns a prepared real JPEG; no camera or platform execution; XOR bridge crypto, fake relay/P2P; endpoint reversal changes identities, not operating systems.
  - Proves / registration: test/features/conversation/integration/camera_caption_relay_delivery_test.dart:141: Reverse sender/recipient identities at compressed quality; correct full prepared image and exact caption; duplicate replay leaves one durable copy. Fresh final file: 19 passed, one pre-existing mixed-relay KNOWN GAP skipped, exit 0; 006-camera-final-summary.json/receipt under .codex-test-logs/astra-groupCD. Registered: media-bytes, affected-conversation, host-all.
- [test/features/conversation/integration/camera_caption_relay_delivery_test.dart](../../test/features/conversation/integration/camera_caption_relay_delivery_test.dart) — `MEDIA-003/DC-011 reverse logical sender preserves original full camera image and caption` (integration).
  - Real: ImageProcessor quality/EXIF argument selection; production upload/send/receive and inbox staging/replay; current SQLite repositories and real files; hash equality; grid admission and full received-image decode/caption.
  - Faked: native compressor returns a prepared real JPEG; no camera or platform execution; XOR bridge crypto, fake relay/P2P; endpoint reversal changes identities, not operating systems.
  - Proves / registration: test/features/conversation/integration/camera_caption_relay_delivery_test.dart:141: Reverse sender/recipient identities at original quality; correct full prepared image and exact caption; duplicate replay leaves one durable copy. Fresh final file: 19 passed, one pre-existing mixed-relay KNOWN GAP skipped, exit 0; 006-camera-final-summary.json/receipt under .codex-test-logs/astra-groupCD. Registered: media-bytes, affected-conversation, host-all.
- [test/features/conversation/integration/camera_caption_relay_delivery_test.dart](../../test/features/conversation/integration/camera_caption_relay_delivery_test.dart) — `MEDIA-002/014 compressed camera JPEG + caption opens full recipient image once over online relay` (integration).
  - Real: ImageProcessor quality/EXIF argument selection; production upload/send/receive and inbox staging/replay; current SQLite repositories and real files; hash equality; grid admission and full received-image decode/caption.
  - Faked: native compressor returns a prepared real JPEG; no camera or platform execution; XOR bridge crypto, fake relay/P2P; endpoint reversal changes identities, not operating systems.
  - Proves / registration: test/features/conversation/integration/camera_caption_relay_delivery_test.dart:120: Compressed quality 85 carries the smaller 1512x2016 prepared image to full viewer/caption; replay retains exactly one message/attachment and no second download. Fresh final file: 19 passed, one pre-existing mixed-relay KNOWN GAP skipped, exit 0; 006-camera-final-summary.json/receipt under .codex-test-logs/astra-groupCD. Registered: media-bytes, affected-conversation, host-all.

**Remaining gaps**

- Voice/video playback structure was observed, but no human/acoustic observer verified audio content or intelligibility; native RTP counters were not captured.
- iPhone image receiver has viewer/Info proof only, without exported full-file hash; controlled high-detail camera/orientation oracle was not available. The 75-second video auto-recovery is a pass with its initial cellular download failure retained.

**Open questions**

- Runbook: docs/testing/astra-group-c-device-runbook.md. Execution performed by flutter_app, not Astra; existing evidence inspected read-only.
- Result scope, candidate and focused host rechecks are recorded in header.group_c_device_run; remaining manual/content/platform limitations above are not full-journey passes.

#### DC-012 — Over a mobile network

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-012.

**Steps**

1. Use an available cellular-capable peer against Wi-Fi.
2. Exchange messages and change active networks.
3. Record actual transport and exact content/owner after handover.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: actual cellular/Wi-Fi; host event model only; offline: n/a; app state: foreground; input: text during network transition; recovery: current-epoch retry.

**Expected:** Mobile-network messages recover without inferring transport from radio type.

**Inspected test evidence**

- [test/core/services/network_path_source_test.dart](../../test/core/services/network_path_source_test.dart) — `a previous-network loss for the ready epoch is delivered once and never replayed` (unit).
  - Real: NetworkPathSource epoch/generation event admission.
  - Faked: StreamController native pushes.
  - Proves / registration: test/core/services/network_path_source_test.dart:40: Previous-loss event is delivered once only for the ready epoch and not replayed to late subscribers; actual Android monitor and mobile handoff are separate. Registered: affected-transport, host-all.
- [test/integration/relay_down_degradation_integration_test.dart](../../test/integration/relay_down_degradation_integration_test.dart) — `1b. active send fails during transport loss, then online transition retrier heals the same row once` (integration).
  - Real: sendChatMessage/PendingMessageRetrier; same-row status/identity handling.
  - Faked: fake ACK/direct/inbox/connectivity; in-memory repositories/passthrough crypto.
  - Proves / registration: test/integration/relay_down_degradation_integration_test.dart:97: Failed initial send stays one failed row, online event retries same ID to inboxed once. Bare inbox store is custody, not remote delivery. Registered: host-all.

**Remaining gaps**

- Native/Dart path classification and fake transport retry are separate; no actual cellular data service/radio/content journey observed. Availability-bounded hardware requirement applies.

#### DC-014 — Arabic, emoji and long text preserve content and direction

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-014.

**Steps**

1. Compose Arabic/mixed-script/emoji/long text.
2. Send and receive through the real encrypted path.
3. Compare exact content and readable first-strong direction.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: Arabic, emoji/ZWJ, long mixed text; recovery: n/a.

**Expected:** Approved text remains intact and readable while unsafe bidi overrides are sanitized by policy.

**Inspected test evidence**

- [integration_test/bidi_text_smoke_test.dart](../../integration_test/bidi_text_smoke_test.dart) — `BiDi display widgets honor first-strong direction and safe markers survive sanitization` (e2e).
  - Real: real sanitizer and displayed quote/body RichText direction.
  - Faked: fixture text/widgets, no message transport.
  - Proves / registration: integration_test/bidi_text_smoke_test.dart:25: Preserves approved safe markers and selects RTL/LTR on local body/quote fixtures; does not send to another endpoint. Registered: registered legacy full inventory (exact dispatch must be inspected).
- [test/features/conversation/integration/two_user_message_exchange_test.dart](../../test/features/conversation/integration/two_user_message_exchange_test.dart) — `Rapid five-round burst preserves delivered state and full order for both users` (integration).
  - Real: actual send/receive listeners/status and conversation ordering.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories.
  - Proves / registration: test/features/conversation/integration/two_user_message_exchange_test.dart:1351: Five alternating rounds produce ten correctly ordered messages on each endpoint and five exact incoming events per user; no100-message burst/restart or real socket. Registered: affected-conversation, direct-chat, host-all.

**Remaining gaps**

- BiDi smoke contains local fixture widgets only; ordinary burst text is different. No exact long/emoji/mixed-script real-peer sender-to-recipient content+render assertion.

#### DC-015 — Message speed

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-015.

**Steps**

1. Send on cold/warm/local/direct/relay/inbox paths.
2. Hold a slow leg beyond its configured budget.
3. Measure completion/receipt latency and verify fallback without false success.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: controlled path budgets versus real campaign; offline: n/a; app state: foreground; input: slow local/direct legs; warm/cold sends; recovery: n/a.

**Expected:** Phase deadlines cap unproductive work and measured recipient delivery meets the stated path-specific budget.

**Inspected test evidence**

- [test/performance/send_path_budget_hard_gate_test.dart](../../test/performance/send_path_budget_hard_gate_test.dart) — `slow LOCAL leg (ack delay ABOVE 1500ms local budget) is abandoned at the budget; the direct leg carries it well under the local delay` (unit).
  - Real: actual race/deadline/budget orchestration; real Stopwatch.
  - Faked: fake five-second local ACK and healthy direct path; in-memory network/repositories.
  - Proves / registration: test/performance/send_path_budget_hard_gate_test.dart:58: Slow local ACK is cut by1500ms budget and healthy path completes under3s; not measured real-device network latency/p95. Registered: performance-host.
- [tool/sims/production_routing_criteria.dart](../../tool/sims/production_routing_criteria.dart) — `production.routing_smoke / S5` (sims).
  - Real: registered actual Android production send/receive and exact SQL receipt observations when executed; artifact-bound typed criteria.
  - Faked: campaign prepares contacts and controls app/network transitions.
  - Proves / registration: tool/sims/production_routing_criteria.dart:164: S5 requires3 A->B and2 B->A exchanges, every one received with exact message/text/lane/conversation checks at:72. Registered runner run_production_routing.dart. No run/artifact validated here; protocol send bypasses composer gestures. Registered: see cited native runner/manifest.

**Remaining gaps**

- Host hard gate proves deadline behavior against fake delays; it does not establish production latency percentiles, real-radio performance or signed-candidate thresholds.

#### DC-017 — Text recovers after relay service outage

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-017.

**Steps**

1. Lose relay while sending accepted text.
2. Retain failed/custody row and original envelope.
3. Recover relay/bridge and deliver the same message once.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: relay unavailable then restored; offline: n/a; app state: foreground; input: as described; recovery: same immutable envelope/custody.

**Expected:** Outage does not discard accepted intent or mint false delivery; retry settles exact owned work.

**Inspected test evidence**

- [test/integration/relay_down_degradation_integration_test.dart](../../test/integration/relay_down_degradation_integration_test.dart) — `1b. active send fails during transport loss, then online transition retrier heals the same row once` (integration).
  - Real: sendChatMessage/PendingMessageRetrier; same-row status/identity handling.
  - Faked: fake ACK/direct/inbox/connectivity; in-memory repositories/passthrough crypto.
  - Proves / registration: test/integration/relay_down_degradation_integration_test.dart:97: Failed initial send stays one failed row, online event retries same ID to inboxed once. Bare inbox store is custody, not remote delivery. Registered: host-all.
- [test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart](../../test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart) — `all paths fail then reconstructed sender drains original custody` (integration).
  - Real: actual outbox custody drain and sender-owner reconstruction.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories; same in-memory repositories retained across reconstruction.
  - Proves / registration: test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart:105: Failed envelope survives recreated TestUser and drains once under same immutable ID/content; not an actual process kill or on-disk reopen. Registered: affected-conversation, host-all, quiet-recovery.
- [test/features/conversation/integration/delivery_receipt_roundtrip_test.dart](../../test/features/conversation/integration/delivery_receipt_roundtrip_test.dart) — `relay-inbox arrival mints a delivery receipt that the sender applies, flipping the outgoing row 'inboxed' -> 'delivered'` (integration).
  - Real: actual receipt mint/listener/application.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories.
  - Proves / registration: test/features/conversation/integration/delivery_receipt_roundtrip_test.dart:52: Recipient storage generates receipt; sender changes inboxed to delivered and clears envelope. Duplicate receipt companion case is idempotent. Registered: affected-conversation, host-all.

**Remaining gaps**

- Transport and relay are simulated in composed application tests; actual service restart/multi-relay routing and recipient durable proof remain separate.

#### DC-022 — Sender offline submission has an honest recoverable outcome

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-022.

**Steps**

1. Submit text while local/direct/relay are unavailable.
2. Observe truthful failure/pending state and retained/restored draft.
3. Retry after connectivity without duplicate user intent.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: sender offline/no usable route then restored; offline: n/a; app state: foreground; input: new text intent; recovery: draft or durable-envelope retry.

**Expected:** Offline submission never silently disappears or claims receiver delivery; recoverable intent remains visible.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `restores draft and removes fresh memory-only optimism when send returns null without custody authority` (widget).
  - Real: real conversation optimistic UI and draft restoration.
  - Faked: held send callback returning nodeNotRunning/null; message/identity/contact repositories.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:6328: Failed fresh send restores exact text, removes memory-only optimistic message and does not persist a false successful row. Registered: affected-conversation, host-all.
- [test/integration/relay_down_degradation_integration_test.dart](../../test/integration/relay_down_degradation_integration_test.dart) — `1b. active send fails during transport loss, then online transition retrier heals the same row once` (integration).
  - Real: sendChatMessage/PendingMessageRetrier; same-row status/identity handling.
  - Faked: fake ACK/direct/inbox/connectivity; in-memory repositories/passthrough crypto.
  - Proves / registration: test/integration/relay_down_degradation_integration_test.dart:97: Failed initial send stays one failed row, online event retries same ID to inboxed once. Bare inbox store is custody, not remote delivery. Registered: host-all.
- [test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart](../../test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart) — `all paths fail then reconstructed sender drains original custody` (integration).
  - Real: actual outbox custody drain and sender-owner reconstruction.
  - Faked: FakeP2PNetwork and in-memory relay; PassthroughCryptoBridge; in-memory contact/message repositories; same in-memory repositories retained across reconstruction.
  - Proves / registration: test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart:105: Failed envelope survives recreated TestUser and drains once under same immutable ID/content; not an actual process kill or on-disk reopen. Registered: affected-conversation, host-all, quiet-recovery.

**Remaining gaps**

- Causal UI and retry storage seams exist but use fake send/network/repositories; exact OS offline-to-native-reconnect full UI/durable recipient path is not one assertion.

### MEDIA — Direct/group media, voice, private viewing and libraries

#### DC-008 — Photo, video and file both ways

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Pick photo/video/file and caption in each direction.
2. Upload/deliver the exact attachment to the other user.
3. Open the received full content and reopen after restart.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: JPEG/PNG/video/PDF and caption; PDF sending flag-gated; recovery: sender/receiver reopen.

**Expected:** Both users receive the intended complete usable media and caption with stable identity after restart.

**Inspected test evidence**

- [test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart](../../test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart) — `sender encrypts, key rides the v2 envelope, receiver decrypts to byte-identical media` (integration).
  - Real: production upload/send/hydrate/download use cases; actual files/byte equality.
  - Faked: prefix/reverse fake crypto; in-memory relay/P2P/repositories; synthetic512-byte JPEG-named data.
  - Proves / registration: test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart:232: Ciphertext differs from input, key metadata rides the v2 envelope and receiver output equals original bytes. Caption is supplied but not asserted; no real image decode/camera. Fresh audit run: all4 cases passed. Registered: affected-conversation, host-all, media-bytes.
- [integration_test/media_message_journey_e2e_test.dart](../../integration_test/media_message_journey_e2e_test.dart) — `real compose journeys render media for sender and receiver in 1:1 and group threads` (e2e).
  - Real: real direct/group compose/send/listener/widget projection; real PNG fixture/grid decode.
  - Faked: fake picker/bridge/network/in-memory repositories; two logical users in one widget graph.
  - Proves / registration: integration_test/media_message_journey_e2e_test.dart:1093: Recipient caption text IS asserted by _expectVisibleMediaMessage:942 and grid has no broken-image icon. Main PNG case does not open full original viewer or establish real camera/cross-OS transport. Registered original runner is run_test_gates.sh:1113/full regression:403. Registered: registered legacy full inventory (exact dispatch must be inspected).
- [test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart](../../test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart) — `library opens cross-message typed viewer at exact attachment identity` (widget).
  - Real: real library/viewer navigation and typed identity.
  - Faked: strict fake library repo; fixture media/file/action seams.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart:111: Opening second tile selects exact attachment/message, including same-path siblings. Does not prove remote original authenticity or zoom/pixel quality. Registered: affected-conversation, host-all.
- [test/core/media/received_media_egress_service_test.dart](../../test/core/media/received_media_egress_service_test.dart) — `open sends one real PDF under its own clean name` (unit).
  - Real: actual canonical file/PDF signature/name checks.
  - Faked: native egress gateway; header-only PDF fixture.
  - Proves / registration: test/core/media/received_media_egress_service_test.dart:359: A signature-valid PDF gets a clean filename and open destination; companion malformed PDF never leaves app. Actual document viewer rendering is separate. Registered: affected-media, host-all.

**Remaining gaps**

- Real local bytes and received caption/grid are covered at separate seams; no real two-way photo/video/file picker-to-native-viewer plus restart journey.
- Synthetic JPEG bytes and fake crypto/network do not prove real image/video/PDF decode.

#### DC-009 — Voice message, record and play

**Coverage:** strong. **Execution:** not_run. **Catalog:** DC-009.

**Steps**

1. Record native voice on physical Android with microphone permission granted.
2. Send through production Go/relay and receive/download on an Android emulator.
3. Compare endpoint bytes and observe native playback start/progress/completion/stop.

**Conditions:** platform: physical Android recorder + available Android emulator receiver; connectivity: real relay in registered full campaign; offline: n/a; app state: running campaign endpoints; input: native>=1.5s AAC/M4A; permission pregranted; recovery: n/a.

**Expected:** The exact recorded nonempty AAC/M4A arrives byte-identically and plays to completion with cleanup.

**Inspected test evidence**

- [integration_test/scripts/android_voice_message_device_campaign.dart](../../integration_test/scripts/android_voice_message_device_campaign.dart) — `android.voice_message_e2e` (sims).
  - Real: production physical Android recorder/Go send; emulator production receive/download/native playback; artifact/hash/identity and cleanup validation.
  - Faked: permission pregranted; campaign setup; UI hold/review gestures bypassed.
  - Proves / registration: integration_test/scripts/android_voice_message_device_campaign.dart:187: lib/core/debug/android_voice_message_e2e.dart:194 records native audio and calls real sendVoiceMessage; :555 awaits actual player start/progress/completion/stop. Evidence validator:128 requires nonempty>=1.5s recording, equal endpoint hashes, real relay/bridge flags and playback. Registered full two-peer campaign; not run here. Registered: see cited native runner/manifest.
- [integration_test/voice_message_e2e_test.dart](../../integration_test/voice_message_e2e_test.dart) — `physical Android records a nonempty AAC/M4A file with valid duration` (e2e).
  - Real: production record plugin and native AAC/M4A file.
  - Faked: microphone permission pregranted.
  - Proves / registration: integration_test/voice_message_e2e_test.dart:26: Native recorder smoke only; file header explicitly excludes send/receive/playback. Distinguish it from full android.voice_message_e2e campaign. Registered: registered legacy full inventory (exact dispatch must be inspected), reliability.full.cleaned_legacy.
- [test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart](../../test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart) — `voice round trip: encrypted m4a decrypts byte-identical` (integration).
  - Real: real upload/download use cases and files.
  - Faked: fake crypto/relay/repos; receiver parent directly seeded; synthetic M4A-named bytes.
  - Proves / registration: test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart:403: Voice bytes/duration/waveform survive the download path; recording, actual send/receive and native playback are bypassed. Included in fresh4-pass file. Registered: affected-conversation, host-all, media-bytes.

**Remaining gaps**

- Strong is scoped to the registered full Android pair campaign under its prepared APK/pregranted permission; it was not executed here.
- The native-recorder smoke alone is narrower and cannot certify send/receive/playback; signed-store artifact, iOS parity and UI hold/review gestures remain separate.

#### DC-018 — Near-limit direct media and interrupted transfer

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-018.

**Steps**

1. Choose valid near-cap direct media and over-cap siblings.
2. Interrupt or stall upload/download and retain owned state.
3. Retry and verify complete received content once.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: per-type exact/over-cap direct files; recovery: stall/interrupted retry.

**Expected:** Near-limit valid media survives interruption; oversize/stalled inputs remain truthful and no incomplete object becomes done.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `oversized 1:1 pick marks the chip invalid at pick time and shows no snackbar` (widget).
  - Real: actual oversized chip/retained draft UI.
  - Faked: budgetBytes set to30MiB on tinyPNG; repositories/send.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10254: Over-cap metadata marks retained chip invalid without snackbar; does not physically transfer a near-limit valid image. Registered: affected-conversation, host-all.
- [test/features/conversation/application/media_download_slow_transfer_simulator_test.dart](../../test/features/conversation/application/media_download_slow_transfer_simulator_test.dart) — `slow steady transfer with progress completes; stalled transfer fails with typed stall code` (unit).
  - Real: download watchdog/deadline/status logic; actual temp output files.
  - Faked: timed writing bridge and synthetic progress events; repositories.
  - Proves / registration: test/features/conversation/application/media_download_slow_transfer_simulator_test.dart:197: Steady progress survives the stall window; no-progress transfer gets typed stall failure. Not real network bandwidth/handover. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/incomplete_upload_recovery_test.dart](../../test/features/conversation/integration/incomplete_upload_recovery_test.dart) — `voice message upload interrupted by lock is re-uploaded and delivered on resume` (integration).
  - Real: actual incomplete-upload retry/send use cases.
  - Faked: fake P2P/bridge/repositories; simulated lock interruption and fixture audio.
  - Proves / registration: test/features/conversation/integration/incomplete_upload_recovery_test.dart:22: Reuploads pending voice attachment and converges delivery state on resume; no actual device lock or native recording/playback. Registered: affected-conversation, host-all.
- [test/features/conversation/application/download_media_use_case_test.dart](../../test/features/conversation/application/download_media_use_case_test.dart) — `content hash mismatch on encrypted direct blob fails before decrypt` (unit).
  - Real: actual SHA256/content admission and file removal.
  - Faked: download/crypto bridge; repositories.
  - Proves / registration: test/features/conversation/application/download_media_use_case_test.dart:4342: Hash mismatch rejects before blob:decrypt, publishes no local path, deletes bad bytes and does not ACK-delete relay data. Registered: affected-conversation, group-media-storage-preservation, host-all, strict-group-media-manifest.

**Remaining gaps**

- Size UI injects budget metadata over tiny fixtures; slow transfer uses a timed fake bridge. No actual near-cap physical-byte end-to-end interruption and recipient decode.

#### GX-003 — Near-limit group media and interrupted transfer

**Coverage:** partial. **Execution:** not_run. **Catalog:** GX-003.

**Steps**

1. Choose valid near-cap group media and an over-cap batch.
2. Interrupt transfer for one member.
3. Retry only missing work while every eligible member receives usable content.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: group per-media and aggregate boundaries; recovery: partial member interruption.

**Expected:** Group caps and failures are per-item/per-recipient; complete authorized content converges once.

**Inspected test evidence**

- [test/features/groups/integration/group_media_fanout_test.dart](../../test/features/groups/integration/group_media_fanout_test.dart) — `discussion members independently download image, video, and voice for every eligible recipient` (integration).
  - Real: actual group send/listener/download fanout and per-member state.
  - Faked: fake network/bridge/in-memory repositories; four-byte image/video/voice fixtures.
  - Proves / registration: test/features/groups/integration/group_media_fanout_test.dart:399: Every eligible recipient independently downloads descriptor/files with expected metadata; four-byte fixtures do not prove image/video/voice decode or audible playback. Registered: affected-groups, host-all.
- [integration_test/scripts/run_group_media_send_reliability.dart](../../integration_test/scripts/run_group_media_send_reliability.dart) — `group_media_foreground_retry_acl_roundtrip` (sims).
  - Real: registered real-relay Android group process-recovery campaign when executed.
  - Faked: controlled setup/three media fixtures/test flags.
  - Proves / registration: integration_test/scripts/run_group_media_send_reliability.dart:1: Manifest assertions require three kinds exactly once, transport ACL, durable claim process-death recovery and second retry zero; role artifact criteria audited at group_media_reliability_criteria_test.dart:9. No execution/artifact validated here; stock125 camera decode/caption not certified. Registered: groups.media_send_reliability, groups.media_send_reliability_ios, reliability.full.cleaned_legacy.
- [test/features/conversation/application/media_download_slow_transfer_simulator_test.dart](../../test/features/conversation/application/media_download_slow_transfer_simulator_test.dart) — `slow steady transfer with progress completes; stalled transfer fails with typed stall code` (unit).
  - Real: download watchdog/deadline/status logic; actual temp output files.
  - Faked: timed writing bridge and synthetic progress events; repositories.
  - Proves / registration: test/features/conversation/application/media_download_slow_transfer_simulator_test.dart:197: Steady progress survives the stall window; no-progress transfer gets typed stall failure. Not real network bandwidth/handover. Registered: affected-conversation, host-all.

**Remaining gaps**

- Fanout uses four-byte fixture media; registered real-relay campaign covers narrower process/ACL assertions, not actual near-cap image/video full decode for every member.

#### DC-021 — Private media retains its policy over the wire

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-021.

**Steps**

1. Select a private media policy with no caption.
2. Send/retry it in encrypted message metadata.
3. Receive and enforce that policy across local open/restart.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: protected/view-once/disappearing policy; recovery: retry/replay/restart.

**Expected:** Private policy stays authenticated inside the encrypted payload and cannot degrade to ordinary media or leak lifecycle internals.

**Inspected test evidence**

- [test/features/conversation/application/send_chat_message_use_case_test.dart](../../test/features/conversation/application/send_chat_message_use_case_test.dart) — `valid private policy is encrypted-inner-only and persists on parent` (unit).
  - Real: actual private-policy serialization/parent persistence and outer-envelope separation.
  - Faked: FakeBridge returns opaque crypto; P2P/repositories.
  - Proves / registration: test/features/conversation/application/send_chat_message_use_case_test.dart:5301: Asserts private policy is in encryption input and persisted parent, absent from public envelope; native encryption/decryption and remote private UI not joined. Registered: affected-conversation, host-all, keepalive-campaign-contract.
- [test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart](../../test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart) — `view once protects before bytes records one first frame and close terminalizes before or after first frame` (unit).
  - Real: actual private-viewer controller/native protection ordering/settlement.
  - Faked: native channel completion; fake lifecycle lane/path authority.
  - Proves / registration: test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart:864: No byte-bearing grant before protection succeeds; first-frame admitted once, close consumes/cleans once even before first frame. Actual native capture prevention is not tested. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/private_media_restart_replay_test.dart](../../test/features/conversation/integration/private_media_restart_replay_test.dart) — `reopen terminalizes opening and preserves monotonic expiry across rollback` (integration).
  - Real: production private engine/adapters/FFI SQLite file reopen.
  - Faked: controlled clock; fixture attachment/key store and app files.
  - Proves / registration: test/features/conversation/integration/private_media_restart_replay_test.dart:32: Reopen consumes interrupted opening, refuses replay and retains expiry high-water despite rollback; deadline then expires/cleans once. Not actual OS process kill/SQLCipher. Registered: affected-conversation, host-all.
- [test/features/conversation/application/direct_private_media_boundary_test.dart](../../test/features/conversation/application/direct_private_media_boundary_test.dart) — `Forward denies every private terminal unsupported hidden or missing parent before side effects` (unit).
  - Real: actual current-parent action authority.
  - Faked: permissive file/token/action seams.
  - Proves / registration: test/features/conversation/application/direct_private_media_boundary_test.dart:368: Current private/terminal/unsupported/deleted source refuses Forward before token/file side effects; other tests guard egress/PiP independently. Registered: affected-conversation, host-all.

**Remaining gaps**

- Wire test inspects real serialization but crypto response is opaque fake. Local state/viewer proofs do not join real encrypted remote receipt and native protection.

#### GC-006 — Authorized members receive usable group media

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-006.

**Steps**

1. Send supported group image/video/voice to active members.
2. Each eligible member independently downloads.
3. Open/play the full content; isolate a failing recipient and retry.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: active group members; image/video/voice; recovery: one-member failure and retry.

**Expected:** Every authorized member gets complete usable content without a failed peer hiding another outcome.

**Inspected test evidence**

- [test/features/groups/integration/group_media_fanout_test.dart](../../test/features/groups/integration/group_media_fanout_test.dart) — `discussion members independently download image, video, and voice for every eligible recipient` (integration).
  - Real: actual group send/listener/download fanout and per-member state.
  - Faked: fake network/bridge/in-memory repositories; four-byte image/video/voice fixtures.
  - Proves / registration: test/features/groups/integration/group_media_fanout_test.dart:399: Every eligible recipient independently downloads descriptor/files with expected metadata; four-byte fixtures do not prove image/video/voice decode or audible playback. Registered: affected-groups, host-all.
- [integration_test/scripts/run_group_media_send_reliability.dart](../../integration_test/scripts/run_group_media_send_reliability.dart) — `group_media_foreground_retry_acl_roundtrip` (sims).
  - Real: registered real-relay Android group process-recovery campaign when executed.
  - Faked: controlled setup/three media fixtures/test flags.
  - Proves / registration: integration_test/scripts/run_group_media_send_reliability.dart:1: Manifest assertions require three kinds exactly once, transport ACL, durable claim process-death recovery and second retry zero; role artifact criteria audited at group_media_reliability_criteria_test.dart:9. No execution/artifact validated here; stock125 camera decode/caption not certified. Registered: groups.media_send_reliability, groups.media_send_reliability_ios, reliability.full.cleaned_legacy.
- [test/features/groups/integration/group_media_fanout_test.dart](../../test/features/groups/integration/group_media_fanout_test.dart) — `tampered fake-network media download fails integrity before done` (integration).
  - Real: actual listener/download/hash status and filesystem cleanup.
  - Faked: fake group network/bridge/repositories; four synthetic bytes.
  - Proves / registration: test/features/groups/integration/group_media_fanout_test.dart:2107: Tampered group attachment reaches integrity_failed, no localPath/file and one download; no native codec or actual cryptographic authentication. Registered: affected-groups, host-all.

**Remaining gaps**

- Host downloaded files have four synthetic bytes, so done/metadata is not decode/playability proof. No actual camera/codec/caption for all group recipients.

#### GC-010 — Group private media preserves each recipient lifecycle

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-010.

**Steps**

1. Deliver private group media to each authorized recipient.
2. Open/consume/expire independently per member.
3. Interrupt/restart/capture and verify no other member lifecycle is consumed or leaked.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: group protected/view-once/disappearing media; recovery: recipient-specific restart/capture.

**Expected:** Each recipient retains independent private lifecycle and exact protected derivatives/cleanup policy.

**Inspected test evidence**

- [test/features/groups/integration/group_private_media_payload_roundtrip_test.dart](../../test/features/groups/integration/group_private_media_payload_roundtrip_test.dart) — `GPL-04 private policy roundtrips send retry live and offline without local lifecycle leakage` (integration).
  - Real: actual group send/retry/live/offline policy hydration.
  - Faked: fake group network/crypto/repositories.
  - Proves / registration: test/features/groups/integration/group_private_media_payload_roundtrip_test.dart:104: Private policy survives each delivery path without local lifecycle fields leaking over wire; no real relay/recipient native decoder. Registered: affected-groups, host-all.
- [test/features/groups/application/group_private_media_expiry_test.dart](../../test/features/groups/application/group_private_media_expiry_test.dart) — `GPL-07 expiry state machine follows approved clock authority across lifecycle` (unit).
  - Real: actual private expiry engine/production SQLite file persistence.
  - Faked: clock and fixture secure keys/files.
  - Proves / registration: test/features/groups/application/group_private_media_expiry_test.dart:62: Clock high-water, receipt-based anchor, lifecycle/reopen and terminal expiry remain monotonic; actual platform scheduling/secure erasure is separate. Registered: affected-groups, host-all.
- [test/features/groups/presentation/group_private_media_viewer_test.dart](../../test/features/groups/presentation/group_private_media_viewer_test.dart) — `GPL-11 capture and background cover immediately then close before native release` (widget).
  - Real: real routed private viewer and cover-before-release ordering.
  - Faked: native event/channel and held settlement; fixture repo/path/media.
  - Proves / registration: test/features/groups/presentation/group_private_media_viewer_test.dart:418: Capture/background covers immediately, waits for settlement, removes viewer then releases native protection; no actual OS screenshot prevention. Registered: affected-groups, host-all.

**Remaining gaps**

- Policy/live/offline and local SQL expiry are substantive but fake transport/native protection remain seams. No multi-member real native lifecycle/crypto journey or signed artifact execution.

#### MEDIA-001 — In-app camera photo plus caption: recipient opens the full correct image and sees the caption

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Use the in-app camera to capture a photo.
2. Add caption and Send to a contact.
3. Recipient opens the full correct image and sees exact caption.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: ordinary direct/relay availability; offline: n/a; app state: foreground; input: actual in-app camera photo+caption; Original/compressed; recovery: n/a.

**Expected:** Actual camera output arrives fully decodable/openable with the exact caption.

**Inspected test evidence**

- [integration_test/media_message_journey_e2e_test.dart](../../integration_test/media_message_journey_e2e_test.dart) — `real compose journeys render media for sender and receiver in 1:1 and group threads` (e2e).
  - Real: real direct/group compose/send/listener/widget projection; real PNG fixture/grid decode.
  - Faked: fake picker/bridge/network/in-memory repositories; two logical users in one widget graph.
  - Proves / registration: integration_test/media_message_journey_e2e_test.dart:1093: Recipient caption text IS asserted by _expectVisibleMediaMessage:942 and grid has no broken-image icon. Main PNG case does not open full original viewer or establish real camera/cross-OS transport. Registered original runner is run_test_gates.sh:1113/full regression:403. Registered: registered legacy full inventory (exact dispatch must be inspected).
- [test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart](../../test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart) — `sender encrypts, key rides the v2 envelope, receiver decrypts to byte-identical media` (integration).
  - Real: production upload/send/hydrate/download use cases; actual files/byte equality.
  - Faked: prefix/reverse fake crypto; in-memory relay/P2P/repositories; synthetic512-byte JPEG-named data.
  - Proves / registration: test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart:232: Ciphertext differs from input, key metadata rides the v2 envelope and receiver output equals original bytes. Caption is supplied but not asserted; no real image decode/camera. Fresh audit run: all4 cases passed. Registered: affected-conversation, host-all, media-bytes.
- [test/core/media/image_processor_test.dart](../../test/core/media/image_processor_test.dart) — `calls compress with quality 100 when preference is original` (unit).
  - Real: actual quality argument selection.
  - Faked: compressor callback.
  - Proves / registration: test/core/media/image_processor_test.dart:83: Original passes quality100; neighboring compressed case passes85 and both strip EXIF. Native output format/codec, real camera MIME/bytes and recipient readability are not established. Registered: affected-media, host-all.

**Remaining gaps**

- Compose test uses a fake gallery picker and generated PNG; byte test uses synthetic non-image data. Neither exercises actual camera output nor recipient original-viewer open.

#### MEDIA-002 — iPhone camera+caption to Android: Original/compressed quality over relay-only online delivery

**Coverage:** partial. **Execution:** device_run. **Catalog:** DC-008, DC-011, DC-010.

**Steps**

1. Capture actual in-app iPhone camera output at Original and compressed quality.
2. Send image+caption to Android over relay-only while both are online.
3. On B, fully decode/open the correct original image and verify exact caption.

**Conditions:** platform: iPhone 13 and Pixel 6; actual owner-run debug/FLOW-log cross-platform candidate; connectivity: relay-only, both online; offline: none; app state: foreground baseline; input: actual in-app camera output+caption; Original/compressed; recovery: ordinary online delivery.

**Expected:** Android B fully decodes/opens the correct camera image and displays the exact caption for each selected quality over relay-only online delivery.

**Device execution (2026-10-22; flutter_app)**

- Result: **PASS_REPORTED_DEVICE_LEGS**.
- Actual iPhone camera plus caption reached online Pixel over per-message witnessed relay transport at both selected qualities; full exported JPEG/native viewer and exact caption checked, one row after reopen.
- Original: 1920x2560, 801930 bytes. Compressed: 1920x2560, 792748 bytes. Both are JPEG; radio state alone was not the route oracle.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:10`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:14`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:15`.

**Inspected test evidence**

- [test/features/conversation/integration/camera_caption_relay_delivery_test.dart](../../test/features/conversation/integration/camera_caption_relay_delivery_test.dart) — `Original camera JPEG + caption opens full recipient image over online relay` (integration).
  - Real: ImageProcessor quality/EXIF argument selection; production upload/send/receive and inbox staging/replay; current SQLite repositories and real files; hash equality; grid admission and full received-image decode/caption.
  - Faked: native compressor returns a prepared real JPEG; no camera or platform execution; XOR bridge crypto, fake relay/P2P; endpoint reversal changes identities, not operating systems.
  - Proves / registration: test/features/conversation/integration/camera_caption_relay_delivery_test.dart:106: Original quality 100 and EXIF removal request reach compression boundary; recipient opens 3024x4032 prepared image with exact bytes and caption. Fresh final file: 19 passed, one pre-existing mixed-relay KNOWN GAP skipped, exit 0; 006-camera-final-summary.json/receipt under .codex-test-logs/astra-groupCD. Registered: media-bytes, affected-conversation, host-all.
- [test/features/conversation/integration/camera_caption_relay_delivery_test.dart](../../test/features/conversation/integration/camera_caption_relay_delivery_test.dart) — `MEDIA-002/014 compressed camera JPEG + caption opens full recipient image once over online relay` (integration).
  - Real: ImageProcessor quality/EXIF argument selection; production upload/send/receive and inbox staging/replay; current SQLite repositories and real files; hash equality; grid admission and full received-image decode/caption.
  - Faked: native compressor returns a prepared real JPEG; no camera or platform execution; XOR bridge crypto, fake relay/P2P; endpoint reversal changes identities, not operating systems.
  - Proves / registration: test/features/conversation/integration/camera_caption_relay_delivery_test.dart:120: Compressed quality 85 carries the smaller 1512x2016 prepared image to full viewer/caption; replay retains exactly one message/attachment and no second download. Fresh final file: 19 passed, one pre-existing mixed-relay KNOWN GAP skipped, exit 0; 006-camera-final-summary.json/receipt under .codex-test-logs/astra-groupCD. Registered: media-bytes, affected-conversation, host-all.

**Remaining gaps**

- Both selected qualities yielded 1920x2560 JPEGs of similar size. This does not establish original sensor-resolution preservation or settle the Original-quality product-copy question; it is not classified as a confirmed app bug.
- No controlled high-detail camera/orientation card was available; desk images, full exported file metadata and viewer decode bound the content oracle. Historical stock125 incident remains separate from this instrumented candidate.

**Open questions**

- Runbook: docs/testing/astra-group-c-device-runbook.md. Execution performed by flutter_app, not Astra; existing evidence inspected read-only.
- Result scope, candidate and focused host rechecks are recorded in header.group_c_device_run; remaining manual/content/platform limitations above are not full-journey passes.

#### MEDIA-003 — Android camera photo plus caption to iPhone receiver

**Coverage:** partial. **Execution:** device_run. **Catalog:** DC-008, DC-011.

**Steps**

1. Capture actual Android camera output and add caption.
2. Send to an iPhone contact.
3. Open/decode full received image and verify caption.

**Conditions:** platform: iPhone 13 and Pixel 6; actual owner-run debug/FLOW-log cross-platform candidate; connectivity: direct/relay supported path; offline: n/a; app state: foreground; input: actual camera image+caption; recovery: n/a.

**Expected:** The cross-platform recipient opens the actual Android camera image with exact caption.

**Device execution (2026-10-22; flutter_app)**

- Result: **PASS_REPORTED_DEVICE_LEGS_IPHONE_FILE_EXPORT_UNVERIFIED**.
- Actual Pixel camera plus caption reached the iPhone at Original and Compressed quality; iPhone full viewer decoded, Info reported JPEG and caption matched. Compressed Info was about 501 KB; Original about 2.9 MB.
- Original upload took 92.8 seconds over cellular and delivered inside the 120-second deadline. Both quality rows were unique after the reboot-forced cold relaunch; the previously pending Original duplicate check passed.
- iPhone receive proof is viewer decode/Info, not exported file/hash inspection; Save was avoided to preserve the owner photo library.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:18`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:19`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:23`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:41`.

**Inspected test evidence**

- [test/features/conversation/integration/camera_caption_relay_delivery_test.dart](../../test/features/conversation/integration/camera_caption_relay_delivery_test.dart) — `MEDIA-003/DC-011 reverse logical sender preserves compressed full camera image and caption` (integration).
  - Real: ImageProcessor quality/EXIF argument selection; production upload/send/receive and inbox staging/replay; current SQLite repositories and real files; hash equality; grid admission and full received-image decode/caption.
  - Faked: native compressor returns a prepared real JPEG; no camera or platform execution; XOR bridge crypto, fake relay/P2P; endpoint reversal changes identities, not operating systems.
  - Proves / registration: test/features/conversation/integration/camera_caption_relay_delivery_test.dart:141: Reverse sender/recipient identities at compressed quality; correct full prepared image and exact caption; duplicate replay leaves one durable copy. Fresh final file: 19 passed, one pre-existing mixed-relay KNOWN GAP skipped, exit 0; 006-camera-final-summary.json/receipt under .codex-test-logs/astra-groupCD. Registered: media-bytes, affected-conversation, host-all.
- [test/features/conversation/integration/camera_caption_relay_delivery_test.dart](../../test/features/conversation/integration/camera_caption_relay_delivery_test.dart) — `MEDIA-003/DC-011 reverse logical sender preserves original full camera image and caption` (integration).
  - Real: ImageProcessor quality/EXIF argument selection; production upload/send/receive and inbox staging/replay; current SQLite repositories and real files; hash equality; grid admission and full received-image decode/caption.
  - Faked: native compressor returns a prepared real JPEG; no camera or platform execution; XOR bridge crypto, fake relay/P2P; endpoint reversal changes identities, not operating systems.
  - Proves / registration: test/features/conversation/integration/camera_caption_relay_delivery_test.dart:141: Reverse sender/recipient identities at original quality; correct full prepared image and exact caption; duplicate replay leaves one durable copy. Fresh final file: 19 passed, one pre-existing mixed-relay KNOWN GAP skipped, exit 0; 006-camera-final-summary.json/receipt under .codex-test-logs/astra-groupCD. Registered: media-bytes, affected-conversation, host-all.

**Remaining gaps**

- No exported received-file/hash proof on iPhone: native viewer/Info and exact caption were observed; Save was intentionally avoided. Controlled high-detail/orientation reference was unavailable.
- The device result is for the stated instrumented source/build and both selected quality legs, not signed production-candidate or original sensor-resolution certification.

**Open questions**

- Runbook: docs/testing/astra-group-c-device-runbook.md. Execution performed by flutter_app, not Astra; existing evidence inspected read-only.
- Result scope, candidate and focused host rechecks are recorded in header.group_c_device_run; remaining manual/content/platform limitations above are not full-journey passes.

#### MEDIA-004 — Gallery JPEG/PNG photo plus caption to the recipient

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Pick real gallery JPEG/PNG and caption.
2. Send to the selected recipient.
3. Observe caption and open the full received image.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: JPEG/PNG gallery photo+caption; recovery: n/a.

**Expected:** Correct gallery image and caption reach the intended recipient and the full image opens.

**Inspected test evidence**

- [integration_test/media_message_journey_e2e_test.dart](../../integration_test/media_message_journey_e2e_test.dart) — `real compose journeys render media for sender and receiver in 1:1 and group threads` (e2e).
  - Real: real direct/group compose/send/listener/widget projection; real PNG fixture/grid decode.
  - Faked: fake picker/bridge/network/in-memory repositories; two logical users in one widget graph.
  - Proves / registration: integration_test/media_message_journey_e2e_test.dart:1093: Recipient caption text IS asserted by _expectVisibleMediaMessage:942 and grid has no broken-image icon. Main PNG case does not open full original viewer or establish real camera/cross-OS transport. Registered original runner is run_test_gates.sh:1113/full regression:403. Registered: registered legacy full inventory (exact dispatch must be inspected).
- [test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart](../../test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart) — `sender encrypts, key rides the v2 envelope, receiver decrypts to byte-identical media` (integration).
  - Real: production upload/send/hydrate/download use cases; actual files/byte equality.
  - Faked: prefix/reverse fake crypto; in-memory relay/P2P/repositories; synthetic512-byte JPEG-named data.
  - Proves / registration: test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart:232: Ciphertext differs from input, key metadata rides the v2 envelope and receiver output equals original bytes. Caption is supplied but not asserted; no real image decode/camera. Fresh audit run: all4 cases passed. Registered: affected-conversation, host-all, media-bytes.
- [test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart](../../test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart) — `library opens cross-message typed viewer at exact attachment identity` (widget).
  - Real: real library/viewer navigation and typed identity.
  - Faked: strict fake library repo; fixture media/file/action seams.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart:111: Opening second tile selects exact attachment/message, including same-path siblings. Does not prove remote original authenticity or zoom/pixel quality. Registered: affected-conversation, host-all.

**Remaining gaps**

- Real PNG/grid+caption UI assertion exists through fake network/picker; main case never opens the received original. Full native gallery/crypto/remote viewer remains unjoined.

#### MEDIA-005 — Gallery HEIC/HEIF or unsupported image: normalize or reject honestly

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008, DC-011.

**Steps**

1. Select gallery HEIC/HEIF or unsupported image bytes.
2. Apply the current quality/normalization policy or reject visibly.
3. Open valid output on recipient; preserve draft/prior content on failure.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: actual HEIC/HEIF or malformed/unsupported image; recovery: honest refusal or supported normalization.

**Expected:** Accepted encoded images remain usable; unsupported/malformed inputs cannot become a false successful image.

**Inspected test evidence**

- [test/features/groups/presentation/group_conversation_wired_test.dart](../../test/features/groups/presentation/group_conversation_wired_test.dart) — `P269 group composer canonicalizes heif to image heic and uploads and publishes once` (widget).
  - Real: real group composer MIME canonicalization/one-send orchestration; HEIF-header fixture file.
  - Faked: injected successful upload; group repositories/bridge/P2P.
  - Proves / registration: test/features/groups/presentation/group_conversation_wired_test.dart:2785: HEIF fixture publishes once with MIME image/heic and sent/done sender state; no camera capture, actual native HEIC decode, received caption or recipient open. Registered: affected-groups, host-all.
- [test/core/media/image_processor_test.dart](../../test/core/media/image_processor_test.dart) — `TC-200-15: undecodable compress output returns compress path byte-identical` (unit).
  - Real: actual normalization fallback and file bytes.
  - Faked: compressor writing junk bytes.
  - Proves / registration: test/core/media/image_processor_test.dart:341: Locks pass-through of undecodable compressor output, not honest invalid-image rejection or a native HEIC conversion proof. Registered: affected-media, host-all.
- [test/core/media/image_processor_test.dart](../../test/core/media/image_processor_test.dart) — `calls compress with quality 100 when preference is original` (unit).
  - Real: actual quality argument selection.
  - Faked: compressor callback.
  - Proves / registration: test/core/media/image_processor_test.dart:83: Original passes quality100; neighboring compressed case passes85 and both strip EXIF. Native output format/codec, real camera MIME/bytes and recipient readability are not established. Registered: affected-media, host-all.

**Remaining gaps**

- HEIF test only canonicalizes MIME and mocks upload; native HEIC decode/normalization is unproved. Existing image fallback deliberately passes undecodable compressor output through unchanged.

#### MEDIA-006 — Capture a video in-app and deliver a playable full video plus caption

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Use Record Video in the in-app attachment sheet.
2. Finish native capture, add caption and Send.
3. Recipient plays the complete correct video and sees caption.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: actual camera video+caption; compressed/original; recovery: n/a.

**Expected:** Actual captured video remains playable and caption-correct after delivery.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `recorded single video keeps single-item processing copy` (widget).
  - Real: actual Record Video UI dispatch/progress tile.
  - Faked: FakeMediaPicker; native compressor completer; mp4 files actually contain tiny PNG bytes; repositories/send.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10773: Selecting Record Video drives injected40% progress and single-item Processing text; no native recording/codec/send/recipient playback. Registered: affected-conversation, host-all.
- [test/shared/widgets/media/media_video_controls_test.dart](../../test/shared/widgets/media/media_video_controls_test.dart) — `seek speed mute and time controls drive one active adapter safely` (widget).
  - Real: actual video controls/seek clamps/speed cycle.
  - Faked: FakeMediaPlaybackAdapter.
  - Proves / registration: test/shared/widgets/media/media_video_controls_test.dart:15: Controls call one active adapter with correct speed/seek/mute/play/pause; no actual decoder or native frames. Registered: affected-media, host-all.
- [test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart](../../test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart) — `sender encrypts, key rides the v2 envelope, receiver decrypts to byte-identical media` (integration).
  - Real: production upload/send/hydrate/download use cases; actual files/byte equality.
  - Faked: prefix/reverse fake crypto; in-memory relay/P2P/repositories; synthetic512-byte JPEG-named data.
  - Proves / registration: test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart:232: Ciphertext differs from input, key metadata rides the v2 envelope and receiver output equals original bytes. Caption is supplied but not asserted; no real image decode/camera. Fresh audit run: all4 cases passed. Registered: affected-conversation, host-all, media-bytes.

**Remaining gaps**

- Record Video case injects FakeMediaPicker and uses PNG bytes in .mp4 files; it only asserts processing copy/progress. No actual capture/encode/orientation/remote playback+caption assertion.

#### MEDIA-007 — Select gallery video and preserve orientation, duration and caption

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Select a gallery video with known orientation/duration.
2. Process at the selected quality and send caption.
3. Play full recipient video with correct orientation/duration/caption.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: gallery video; portrait/landscape metadata and caption; recovery: n/a.

**Expected:** Processed video preserves usable orientation, duration and intended caption.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `gallery multi-video batches keep one processing tile with honest batch context` (widget).
  - Real: gallery batch orchestration/progress UI.
  - Faked: fake picker; compressor completers; synthetic file fixtures and service/repository seams.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10645: Two video jobs with an interleaved image retain one honest batch processing tile with35%/60% progress; not full final recipient ordering/playability. Registered: affected-conversation, host-all.
- [test/shared/widgets/media/media_video_controls_test.dart](../../test/shared/widgets/media/media_video_controls_test.dart) — `seek speed mute and time controls drive one active adapter safely` (widget).
  - Real: actual video controls/seek clamps/speed cycle.
  - Faked: FakeMediaPlaybackAdapter.
  - Proves / registration: test/shared/widgets/media/media_video_controls_test.dart:15: Controls call one active adapter with correct speed/seek/mute/play/pause; no actual decoder or native frames. Registered: affected-media, host-all.
- [test/shared/widgets/media/media_video_lifecycle_test.dart](../../test/shared/widgets/media/media_video_lifecycle_test.dart) — `only current visible video may play across lifecycle transitions` (widget).
  - Real: actual typed viewer page/lifecycle ownership.
  - Faked: FakeMediaPlaybackAdapter; host lifecycle events.
  - Proves / registration: test/shared/widgets/media/media_video_lifecycle_test.dart:40: Only current page plays; pause does not auto-resume, page changes release old owner and disposal is exact; no native codec/radio. Registered: affected-media, host-all.

**Remaining gaps**

- Processing and player controls use fake native adapters/fixtures. No causal native orientation/duration transform-to-recipient playable outcome.

#### MEDIA-008 — Select a mixed multi-item gallery batch; preserve order, identity and per-item outcomes

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Pick mixed photo/video/GIF items.
2. Process each item with progress and partial failure.
3. Send accepted items and inspect stable order, identity, caption and per-item outcomes.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: mixed multi-item gallery batch; recovery: processing/transfer partial failure.

**Expected:** One batch preserves accepted order/identity while refused/stalled siblings remain explicit.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `gallery multi-video batches keep one processing tile with honest batch context` (widget).
  - Real: gallery batch orchestration/progress UI.
  - Faked: fake picker; compressor completers; synthetic file fixtures and service/repository seams.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10645: Two video jobs with an interleaved image retain one honest batch processing tile with35%/60% progress; not full final recipient ordering/playability. Registered: affected-conversation, host-all.
- [integration_test/media_message_journey_e2e_test.dart](../../integration_test/media_message_journey_e2e_test.dart) — `manual GIF acceptance harness records animated proof for picked and received GIF surfaces` (e2e).
  - Real: real GIF widget/full-viewer surfaces and screenshots.
  - Faked: picker/bridge/network/repositories; one widget graph.
  - Proves / registration: integration_test/media_message_journey_e2e_test.dart:1160: Opens picked/received GIF viewers and captures animation evidence. Source defaults skip; registered run_media_message_journey_e2e.dart:103 explicitly enables GIF_MANUAL_ACCEPTANCE=true, so do not call its registered lane disabled. Registered: registered legacy full inventory (exact dispatch must be inspected).
- [test/features/conversation/application/media_download_slow_transfer_simulator_test.dart](../../test/features/conversation/application/media_download_slow_transfer_simulator_test.dart) — `slow steady transfer with progress completes; stalled transfer fails with typed stall code` (unit).
  - Real: download watchdog/deadline/status logic; actual temp output files.
  - Faked: timed writing bridge and synthetic progress events; repositories.
  - Proves / registration: test/features/conversation/application/media_download_slow_transfer_simulator_test.dart:197: Steady progress survives the stall window; no-progress transfer gets typed stall failure. Not real network bandwidth/handover. Registered: affected-conversation, host-all.

**Remaining gaps**

- Host batch only asserts pending processing state; GIF viewer harness uses fake network. Mixed real native input-to-recipient ordering/full decode and per-item caption/outcomes are not joined.

#### MEDIA-009 — Cancel camera/gallery selection or remove a draft attachment before sending

**Coverage:** strong. **Execution:** host_run. **Catalog:** DC-008.

**Steps**

1. Enter caption/draft and open camera/gallery sheet.
2. Cancel selection or remove one staged attachment.
3. Continue composing without an unintended send or lost draft.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: cancelled picker or removed attachment; recovery: continue draft.

**Expected:** Cancellation/removal retains the intended draft and sends no removed item.

**Fresh host join (2026-10-22)**

- test/core/media/media_picker_test.dart:42: Real SystemMediaPicker/ImagePicker adapters handle native-port null/empty cancellation, fresh next results and no cached stale pick. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: ImagePickerPlatform native port.
- test/features/conversation/presentation/screens/conversation_wired_test.dart:10169: Actual conversation keeps draft after null camera and empty gallery/document picks; removed and actual over-cap files never upload; exactly the retained image uploads/sends once. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: native picker/compressor/upload/send/repository ports.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `Signal attachment sheet uses warm semantic roles and Cancel preserves draft` (widget).
  - Real: real attachment-sheet Cancel and composer draft.
  - Faked: service/repository/picker dependencies.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:16037: Cancel dismisses the chooser and retains entered draft; this does not exercise native camera/gallery cancellation. Registered: affected-conversation, host-all.

**Remaining gaps**

- OS camera/gallery dialogs were not operated; strong coverage is the shared cancellation/removal contract at the real system adapter and conversation boundary, not signed-device picker certification.

**Open questions**

- Scoped host proof only. Device handoff and exact remaining boundaries: docs/testing/astra-lever1-host-quickwins.md. No actual device, signed-candidate or whole affected-lane verdict.

#### MEDIA-010 — Deny camera/photo permission and retry after granting permission

**Coverage:** partial. **Execution:** device_run. **Catalog:** DC-008.

**Steps**

1. Deny camera/photo access at its OS boundary.
2. Attempt pick/capture and inspect visible failure without losing draft.
3. Grant access in Settings and retry the same intended action.

**Conditions:** platform: executor-reported Pixel6 physical plus available headless Android emulator; disposable Group D debug package; connectivity: n/a; offline: n/a; app state: foreground; input: denied/permanently denied then granted; recovery: OS Settings permission grant.

**Expected:** Permission failure is honest and recovery allows a fresh capture/pick without duplicate send.

**Group D device execution (2026-10-22; flutter_app)**

- Result: **PASS_DRAFT_SINGLE_SEND_CAMERA_FEEDBACK_FAIL_ASTRA_D_1**.
- Camera denial/retry preserved draft and a valid image sent once, but desired visible camera failure feedback FAILED: ASTRA-D-1 was confirmed on the device; only CONV_FL_PICK_CAMERA_ERROR was observed.
- Photos used a system picker with no permission boundary (N/A); cancellation preserved the draft. This is not photo-permission-denial proof.
- Kayan identifies Codex fix 6f7e11ed55e99bc85e8b00f8936f776979498ef8 for main integration. Its source exists, but the tested device source predates it; this run is not post-fix native validation.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/SUMMARY.md:5`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/shots/m010_cam_after_deny.png`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/shots/m010_gallery_cancel.png`.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `ConversationWired media props MEDIA-010 camera denial then grant keeps draft and sends one staged image once` (widget).
  - Real: real ConversationWired composer and picker-error/retry/admission/send orchestration; draft preserved, no upload/send on denial; grant/retry stages one image and invokes upload/send once.
  - Faked: PlatformException at existing picker seam; image preparation/upload/send and repositories are test boundaries; no OS Settings/native permission dialog, real transport, remote decode or complete file suite run.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10233: Fresh focused 013: both camera/photos controls passed,0 failures,one separate KNOWN GAP feedback case skipped. Evidence .codex-test-logs/astra-groupCD/013-D-media-permission-final-summary.json/receipt. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `ConversationWired media props MEDIA-010 photos denial then grant keeps draft and sends one staged image once` (widget).
  - Real: real ConversationWired composer and picker-error/retry/admission/send orchestration; draft preserved, no upload/send on denial; grant/retry stages one image and invokes upload/send once.
  - Faked: PlatformException at existing picker seam; image preparation/upload/send and repositories are test boundaries; no OS Settings/native permission dialog, real transport, remote decode or complete file suite run.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10233: Fresh focused 013: both camera/photos controls passed,0 failures,one separate KNOWN GAP feedback case skipped. Evidence .codex-test-logs/astra-groupCD/013-D-media-permission-final-summary.json/receipt. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `ConversationWired media props KNOWN GAP ASTRA-D-1: camera permission failure is silent MEDIA-010 denied camera exposes visible failure feedback` (widget).
  - Real: production camera catch/error presentation branch.
  - Faked: denied picker result injected; native OS unrun.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10394: ASTRA-D-1 desired feedback causally RED in 011:0 visible failure notices; _pickFromCamera only logs at lib/features/conversation/presentation/screens/conversation_wired.dart:5850/5862-5867. Final013 retains the exact assertion under a case-scoped KNOWN GAP, not PASS. Routed to Codex for post-126 app fix; no app change here. Evidence .codex-test-logs/astra-groupCD/011-D-media-permission.log and 013 summary.

**Remaining gaps**

- ASTRA-D-1 visible camera error feedback is a confirmed failure on this candidate, not a complete permission-journey PASS. Codex fix6f7e11ed5 is pending main integration/post-fix verification relative to this run; no app fix or test unskip was made by Astra.
- System-picker photo permission boundary was N/A on the exercised target. Preserve that distinction from cancellation and do not require unavailable hardware/OS permission behavior.

**Open questions**

- Execution by flutter_app; Astra inspected saved evidence only. See header.group_d_device_run for source/artifact provenance and scope.
- Existing handoff: docs/testing/astra-group-d-device-runbook.md. Actual failures, weaker witnesses and unrun legs above are retained; no rating upgrade.

#### MEDIA-011 — PDF sending with document flag enabled; recipient receives and opens the document

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Enable document sending and select a genuine supported PDF.
2. Send it through ordinary direct/group media custody.
3. Recipient receives exact bytes and opens the document with its clean filename.

**Conditions:** platform: Android/iOS PDF external-viewer boundary; connectivity: n/a; offline: n/a; app state: foreground; input: PDF with document sending flag enabled; recovery: n/a.

**Expected:** Flag-enabled PDF sending delivers the intended document to a supported external viewer.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `a picked PDF is staged and a fake PDF is refused` (widget).
  - Real: real document-picker result gating/chips; actual header-check files.
  - Faked: FakeMediaPicker; send/repository seams; header-only PDF fixture.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10199: With flag on one signature-valid PDF stages, fake PDF is refused with visible copy. No full document parse, native picker or recipient open. Registered: affected-conversation, host-all.
- [test/core/media/received_media_egress_service_test.dart](../../test/core/media/received_media_egress_service_test.dart) — `open sends one real PDF under its own clean name` (unit).
  - Real: actual canonical file/PDF signature/name checks.
  - Faked: native egress gateway; header-only PDF fixture.
  - Proves / registration: test/core/media/received_media_egress_service_test.dart:359: A signature-valid PDF gets a clean filename and open destination; companion malformed PDF never leaves app. Actual document viewer rendering is separate. Registered: affected-media, host-all.
- [test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart](../../test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart) — `sender encrypts, key rides the v2 envelope, receiver decrypts to byte-identical media` (integration).
  - Real: production upload/send/hydrate/download use cases; actual files/byte equality.
  - Faked: prefix/reverse fake crypto; in-memory relay/P2P/repositories; synthetic512-byte JPEG-named data.
  - Proves / registration: test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart:232: Ciphertext differs from input, key metadata rides the v2 envelope and receiver output equals original bytes. Caption is supplied but not asserted; no real image decode/camera. Fresh audit run: all4 cases passed. Registered: affected-conversation, host-all, media-bytes.

**Remaining gaps**

- Header-only PDF staging/native gateway fake is not a real parsed PDF viewer. No native picker, actual transfer and recipient document-open combined proof.

#### MEDIA-012 — Document sending flag off while receiving/opening an existing PDF remains supported

**Coverage:** strong. **Execution:** host_run. **Catalog:** DC-008.

**Steps**

1. Disable document composition sending.
2. Receive an existing PDF from another supported peer.
3. Open it or handle no installed PDF viewer honestly.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: document flag off; incoming existing PDF; recovery: no installed viewer.

**Expected:** Send flag hides new composition only; qualified received PDFs can still use the supported open action.

**Fresh host join (2026-10-22)**

- test/features/conversation/presentation/screens/conversation_wired_test.dart:17265: Actual received PDF tile with send flag false calls default real egress/path/PDF service and MethodChannel adapter; complete PDF/request path/digest/identity are exact; noViewer then presented retain source, row and unsent draft. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: message/media repositories; PathProvider directory and native egress MethodChannel.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `the Document row is hidden while the switch is off` (widget).
  - Real: actual attachment-sheet feature gating.
  - Faked: repositories/services.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10188: Flag off hides Document while Media Library remains; receiving/opening capability requires separate egress evidence. Registered: affected-conversation, host-all.
- [test/core/media/received_media_egress_service_test.dart](../../test/core/media/received_media_egress_service_test.dart) — `open sends one real PDF under its own clean name` (unit).
  - Real: actual canonical file/PDF signature/name checks.
  - Faked: native egress gateway; header-only PDF fixture.
  - Proves / registration: test/core/media/received_media_egress_service_test.dart:359: A signature-valid PDF gets a clean filename and open destination; companion malformed PDF never leaves app. Actual document viewer rendering is separate. Registered: affected-media, host-all.

**Remaining gaps**

- Actual native PDF page rendering and OS viewer lifetime remain unrun; presented is not a decoder assertion. The shared flag-off receiving/open contract is now joined.

**Open questions**

- Scoped host proof only. Device handoff and exact remaining boundaries: docs/testing/astra-lever1-host-quickwins.md. No actual device, signed-candidate or whole affected-lane verdict.

#### MEDIA-013 — Reject unsupported document types, oversize files and malformed picker results

**Coverage:** strong. **Execution:** host_run. **Catalog:** DC-008, DC-018.

**Steps**

1. Pick unsupported, malformed, mislabeled or oversize documents.
2. Inspect admission and retained draft.
3. Send only supported accepted items and show specific refusal.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: non-PDF/fake PDF/oversize/malformed picker values; recovery: n/a.

**Expected:** Rejected items never enter successful media dispatch or silently erase valid siblings.

**Fresh host join (2026-10-22)**

- test/features/conversation/presentation/screens/conversation_wired_test.dart:10169: Actual >25MiB image file, rather than invented budget metadata, blocks dispatch while keeping draft; removal permits exactly one valid sibling send. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: native compressor/upload/send/repository ports.
- test/features/conversation/presentation/screens/conversation_wired_test.dart:10420: Complete PDF survives mixed non-PDF, empty, short-signature, mislabeled, missing and empty-path inputs; actual >100MiB PDF stays invalid and blocks Send without a message; removing it preserves valid PDF/draft. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: native document picker and repositories.
- test/core/media/media_picker_test.dart:82: Real file-picker MethodChannel and SystemMediaPicker conversion drop pathless entries and return empty after cancellation without stale selection. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: native file-picker channel result.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `a picked PDF is staged and a fake PDF is refused` (widget).
  - Real: real document-picker result gating/chips; actual header-check files.
  - Faked: FakeMediaPicker; send/repository seams; header-only PDF fixture.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10199: With flag on one signature-valid PDF stages, fake PDF is refused with visible copy. No full document parse, native picker or recipient open. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `oversized 1:1 pick marks the chip invalid at pick time and shows no snackbar` (widget).
  - Real: actual oversized chip/retained draft UI.
  - Faked: budgetBytes set to30MiB on tinyPNG; repositories/send.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10254: Over-cap metadata marks retained chip invalid without snackbar; does not physically transfer a near-limit valid image. Registered: affected-conversation, host-all.
- [test/features/conversation/application/download_media_use_case_test.dart](../../test/features/conversation/application/download_media_use_case_test.dart) — `content hash mismatch on encrypted direct blob fails before decrypt` (unit).
  - Real: actual SHA256/content admission and file removal.
  - Faked: download/crypto bridge; repositories.
  - Proves / registration: test/features/conversation/application/download_media_use_case_test.dart:4342: Hash mismatch rejects before blob:decrypt, publishes no local path, deletes bad bytes and does not ACK-delete relay data. Registered: affected-conversation, group-media-storage-preservation, host-all, strict-group-media-manifest.

**Remaining gaps**

- PDF validation is the supported signature/type/size contract; no full PDF parser or native recipient decoder was exercised. A malformed file with a valid PDF header is not declared rejected by these tests.

**Open questions**

- Scoped host proof only. Device handoff and exact remaining boundaries: docs/testing/astra-lever1-host-quickwins.md. No actual device, signed-candidate or whole affected-lane verdict.

#### MEDIA-014 — iPhone camera+caption to offline Android: Original/compressed quality, relay inbox catch-up

**Coverage:** partial. **Execution:** device_run. **Catalog:** DC-003, DC-008, DC-011.

**Steps**

1. Capture actual iPhone camera output at Original/compressed quality and add caption.
2. Keep Android B offline while sending through relay inbox custody.
3. Bring B online/restart, catch up once, then fully decode/open correct image and verify exact caption.

**Conditions:** platform: iPhone 13 and Pixel 6; actual owner-run debug/FLOW-log cross-platform candidate; connectivity: sender online relay; recipient offline then reconnects; offline: Android recipient offline during send; app state: recipient closed/restarted before catch-up; input: actual in-app camera output+caption; Original/compressed; recovery: relay inbox catch-up exactly once.

**Expected:** B receives exactly one complete correct camera image, fully decodes/opens it and shows the exact caption after relay inbox catch-up.

**Device execution (2026-10-22; flutter_app)**

- Result: **PASS_REPORTED_DEVICE_LEGS**.
- Pixel recipient was offline with Wi-Fi/data off and app stopped. Sender relay custody reached inboxed. Both selected qualities caught up automatically about 21 seconds after recipient relaunch, with one row after cold relaunch.
- Full JPEG/native viewer and caption checks passed: Compressed 1920x2560, 734916 bytes; Original 1920x2560, 766032 bytes.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:16`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:17`.

**Inspected test evidence**

- [test/features/conversation/integration/camera_caption_relay_delivery_test.dart](../../test/features/conversation/integration/camera_caption_relay_delivery_test.dart) — `Original camera JPEG + caption opens full recipient image over offline inbox catch-up` (integration).
  - Real: ImageProcessor quality/EXIF argument selection; production upload/send/receive and inbox staging/replay; current SQLite repositories and real files; hash equality; grid admission and full received-image decode/caption.
  - Faked: native compressor returns a prepared real JPEG; no camera or platform execution; XOR bridge crypto, fake relay/P2P; endpoint reversal changes identities, not operating systems.
  - Proves / registration: test/features/conversation/integration/camera_caption_relay_delivery_test.dart:106: Real durable inbox staging/drain at Original quality 100 and EXIF removal request reach compression boundary; recipient opens 3024x4032 prepared image with exact bytes and caption. Fresh final file: 19 passed, one pre-existing mixed-relay KNOWN GAP skipped, exit 0; 006-camera-final-summary.json/receipt under .codex-test-logs/astra-groupCD. Registered: media-bytes, affected-conversation, host-all.
- [test/features/conversation/integration/camera_caption_relay_delivery_test.dart](../../test/features/conversation/integration/camera_caption_relay_delivery_test.dart) — `MEDIA-002/014 compressed camera JPEG + caption opens full recipient image once over offline inbox catch-up` (integration).
  - Real: ImageProcessor quality/EXIF argument selection; production upload/send/receive and inbox staging/replay; current SQLite repositories and real files; hash equality; grid admission and full received-image decode/caption.
  - Faked: native compressor returns a prepared real JPEG; no camera or platform execution; XOR bridge crypto, fake relay/P2P; endpoint reversal changes identities, not operating systems.
  - Proves / registration: test/features/conversation/integration/camera_caption_relay_delivery_test.dart:120: Real durable inbox staging/drain at compressed quality 85 carries the smaller 1512x2016 prepared image to full viewer/caption; replay retains exactly one message/attachment and no second download. Fresh final file: 19 passed, one pre-existing mixed-relay KNOWN GAP skipped, exit 0; 006-camera-final-summary.json/receipt under .codex-test-logs/astra-groupCD. Registered: media-bytes, affected-conversation, host-all.

**Remaining gaps**

- Both selected quality legs ran with real offline recipient/custody/catch-up, but a controlled high-detail/orientation card was unavailable and both encoded outputs were 1920x2560.
- Historical stock125 behavior and exact production-signed candidate remain unverified; current run uses the stated debug/FLOW-log builds.

**Open questions**

- Runbook: docs/testing/astra-group-c-device-runbook.md. Execution performed by flutter_app, not Astra; existing evidence inspected read-only.
- Result scope, candidate and focused host rechecks are recorded in header.group_c_device_run; remaining manual/content/platform limitations above are not full-journey passes.

#### MEDIA-015 — Local Wi-Fi without internet delivers media locally, separately from deferred internet delivery

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Keep two known peers on local Wi-Fi without internet.
2. Send complete media through local transport.
3. Verify recipient bytes/open independently of later internet fallback.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: same Wi-Fi, no internet; loopback host proof; offline: n/a; app state: foreground; input: full local image/video/voice bytes; recovery: n/a.

**Expected:** Local delivery preserves correct content without confusing local write with durable receipt or deferred internet custody.

**Inspected test evidence**

- [test/core/local_discovery/local_ws_integration_i1_i2_test.dart](../../test/core/local_discovery/local_ws_integration_i1_i2_test.dart) — `media production-wiring: PUT -> mediaReadyStream -> persistMedia lands a SHA-256-verified file in the persistent media dir` (unit).
  - Real: real loopback HTTP/WS/media-ready/persist/SHA256/files.
  - Faked: synthetic JPEG-named bytes; loopback rather than Wi-Fi/mDNS.
  - Proves / registration: test/core/local_discovery/local_ws_integration_i1_i2_test.dart:84: Receiver persists full byte-identical8192-byte file outside temporary storage; neither valid image decode nor real LAN discovery is asserted. Registered: affected-transport, host-all.
- [test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart](../../test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart) — `sender encrypts, key rides the v2 envelope, receiver decrypts to byte-identical media` (integration).
  - Real: production upload/send/hydrate/download use cases; actual files/byte equality.
  - Faked: prefix/reverse fake crypto; in-memory relay/P2P/repositories; synthetic512-byte JPEG-named data.
  - Proves / registration: test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart:232: Ciphertext differs from input, key metadata rides the v2 envelope and receiver output equals original bytes. Caption is supplied but not asserted; no real image decode/camera. Fresh audit run: all4 cases passed. Registered: affected-conversation, host-all, media-bytes.

**Remaining gaps**

- Actual loopback HTTP/WS bytes persist, but no physical Wi-Fi/mDNS/permission/recipient decoder joined. Synthetic bytes are not a valid camera image.

#### MEDIA-016 — No usable local or relay path: honest failed/pending media and later retry

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008, DC-022.

**Steps**

1. Start a media send with neither usable local nor relay route.
2. Inspect pending/failed status and retained owned file/draft.
3. Restore a route and retry the same intended media.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: all paths unavailable then restored; offline: n/a; app state: foreground; input: as described; recovery: manual/automatic retry.

**Expected:** Failure remains truthful and retry uses retained authoritative bytes/identity without duplicate success.

**Inspected test evidence**

- [test/features/conversation/integration/media_retry_smoke_test.dart](../../test/features/conversation/integration/media_retry_smoke_test.dart) — `photo message stuck in sending is recovered and retried with media intact` (integration).
  - Real: actual stuck-send/media retry orchestration.
  - Faked: fake network/bridge/repositories and fixture image.
  - Proves / registration: test/features/conversation/integration/media_retry_smoke_test.dart:385: Same retained media row recovers from sending and retries with attachment intact; no native process kill or remote full image decode. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/incomplete_upload_recovery_test.dart](../../test/features/conversation/integration/incomplete_upload_recovery_test.dart) — `voice message upload interrupted by lock is re-uploaded and delivered on resume` (integration).
  - Real: actual incomplete-upload retry/send use cases.
  - Faked: fake P2P/bridge/repositories; simulated lock interruption and fixture audio.
  - Proves / registration: test/features/conversation/integration/incomplete_upload_recovery_test.dart:22: Reuploads pending voice attachment and converges delivery state on resume; no actual device lock or native recording/playback. Registered: affected-conversation, host-all.
- [test/features/share/integration/external_share_media_custody_recovery_test.dart](../../test/features/share/integration/external_share_media_custody_recovery_test.dart) — `TC-348-03 committed external share survives unusable preview and restart` (integration).
  - Real: DefaultShareBatchDeliveryCoordinator; production current FFI SQLite repos; real files/reopen and strict custody/retry owners.
  - Faked: strict bridge crypto/upload and P2P/inbox; image processing and identity/contact repos; strict feature flag enabled.
  - Proves / registration: test/features/share/integration/external_share_media_custody_recovery_test.dart:36: Committed parent/attachment custody survives lost/unusable preview and DB reopen, retries authoritative bytes once, then records one inbox store. Synthetic JPEG bytes/no recipient decoder and default-off cohort limits apply. Registered: affected-media, host-all.

**Remaining gaps**

- Retry state/local strict custody tests use fake networking and explicit cohort flags; actual default-path recipient full decode is absent.

#### MEDIA-017 — Media transfer switches Wi-Fi/mobile or loses connection; correct full content survives retry

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-018.

**Steps**

1. Begin complete media upload/download.
2. Change Wi-Fi/mobile or interrupt connectivity mid-transfer.
3. Recover and verify the full correct content once.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: Wi-Fi/mobile switch or loss mid-transfer; offline: n/a; app state: foreground; input: as described; recovery: resume/retry current transfer.

**Expected:** Current owned work survives handover without thumbnail-only or corrupt success.

**Inspected test evidence**

- [test/features/conversation/application/media_download_slow_transfer_simulator_test.dart](../../test/features/conversation/application/media_download_slow_transfer_simulator_test.dart) — `slow steady transfer with progress completes; stalled transfer fails with typed stall code` (unit).
  - Real: download watchdog/deadline/status logic; actual temp output files.
  - Faked: timed writing bridge and synthetic progress events; repositories.
  - Proves / registration: test/features/conversation/application/media_download_slow_transfer_simulator_test.dart:197: Steady progress survives the stall window; no-progress transfer gets typed stall failure. Not real network bandwidth/handover. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/incomplete_upload_recovery_test.dart](../../test/features/conversation/integration/incomplete_upload_recovery_test.dart) — `voice message upload interrupted by lock is re-uploaded and delivered on resume` (integration).
  - Real: actual incomplete-upload retry/send use cases.
  - Faked: fake P2P/bridge/repositories; simulated lock interruption and fixture audio.
  - Proves / registration: test/features/conversation/integration/incomplete_upload_recovery_test.dart:22: Reuploads pending voice attachment and converges delivery state on resume; no actual device lock or native recording/playback. Registered: affected-conversation, host-all.
- [integration_test/scripts/run_group_media_send_reliability.dart](../../integration_test/scripts/run_group_media_send_reliability.dart) — `group_media_foreground_retry_acl_roundtrip` (sims).
  - Real: registered real-relay Android group process-recovery campaign when executed.
  - Faked: controlled setup/three media fixtures/test flags.
  - Proves / registration: integration_test/scripts/run_group_media_send_reliability.dart:1: Manifest assertions require three kinds exactly once, transport ACL, durable claim process-death recovery and second retry zero; role artifact criteria audited at group_media_reliability_criteria_test.dart:9. No execution/artifact validated here; stock125 camera decode/caption not certified. Registered: groups.media_send_reliability, groups.media_send_reliability_ios, reliability.full.cleaned_legacy.

**Remaining gaps**

- Fake progress/lock and registered group process recovery do not join actual radio handover, full remote bytes and native decoder. No such campaign executed here.

#### MEDIA-018 — Restart sender or receiver during upload/download; no permanent thumbnail-only success

**Coverage:** partial. **Execution:** device_run. **Catalog:** DC-004, DC-018.

**Steps**

1. Begin upload/download then terminate sender or recipient.
2. Reopen accepted durable work before trusting previews.
3. Complete/retry and open the full recipient content.

**Conditions:** platform: executor-reported Pixel6 physical plus available headless Android emulator; disposable Group D debug package; host evidence only; connectivity: n/a; offline: n/a; app state: sender/recipient process interruption represented by database reopen; input: as described; recovery: authoritative custody retry.

**Expected:** Accepted custody survives restart; missing thumbnail/cache cannot manufacture a done original.

**Group D device execution (2026-10-22; flutter_app)**

- Result: **PASS_IMAGE_RECOVERY_WEAK_LOG_CUT_WITNESS_VIDEO_NOT_RUN**.
- Image recovery passed for sender and receiver cuts with log-checkpoint witnesses.
- No byte-progress witness or throttling was available; the logs do not establish a causal mid-I/O interruption. Video repeat was not performed.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/SUMMARY.md:7`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/m018_final_rows.txt:1`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/m018_receiver_cut_recovery.txt:1`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/m018_sender_cut3_recovery.txt:1`.

**Inspected test evidence**

- [test/features/conversation/integration/ordinary_media_receiver_restart_test.dart](../../test/features/conversation/integration/ordinary_media_receiver_restart_test.dart) — `MEDIA-018 interrupted ordinary download survives receiver SQL/runtime reopen and commits one fully decodable image plus caption` (integration).
  - Real: default legacy upload/send/receive/recovery owners, current SQL/files and key references across receiver reopen; partial ciphertext cannot be done; recovered full bytes/hash, host Flutter image frame, exact caption and replay one-copy/no-extra-download.
  - Faked: XOR crypto, controlled native truncated/EOF burst, fake relay/P2P and OS directory lookup; partial prefix reconstructed at a persisted retry checkpoint; no actual process kill, camera, mobile viewer or interrupted in-flight SQL commit.
  - Proves / registration: test/features/conversation/integration/ordinary_media_receiver_restart_test.dart:36: Fresh file 018:1 passed,0 skipped/failed,exit0; final host frame 128x96. Sender source is real JPEG. Evidence .codex-test-logs/astra-groupCD/018-D-receiver-restart-summary.json/receipt. Registered: affected-conversation, host-all.
- [test/features/share/integration/external_share_media_custody_recovery_test.dart](../../test/features/share/integration/external_share_media_custody_recovery_test.dart) — `TC-348-03 committed external share survives unusable preview and restart` (integration).
  - Real: DefaultShareBatchDeliveryCoordinator; production current FFI SQLite repos; real files/reopen and strict custody/retry owners.
  - Faked: strict bridge crypto/upload and P2P/inbox; image processing and identity/contact repos; strict feature flag enabled.
  - Proves / registration: test/features/share/integration/external_share_media_custody_recovery_test.dart:36: Committed parent/attachment custody survives lost/unusable preview and DB reopen, retries authoritative bytes once, then records one inbox store. Synthetic JPEG bytes/no recipient decoder and default-off cohort limits apply. Registered: affected-media, host-all. Fresh exact support case020 passed once,0skips,exit0 (.codex-test-logs/astra-groupCD/020-D-sender-custody-support-summary.json/receipt); strict cohort remains explicit, not legacy sender proof.
- [test/features/conversation/integration/media_retry_smoke_test.dart](../../test/features/conversation/integration/media_retry_smoke_test.dart) — `photo message stuck in sending is recovered and retried with media intact` (integration).
  - Real: actual stuck-send/media retry orchestration.
  - Faked: fake network/bridge/repositories and fixture image.
  - Proves / registration: test/features/conversation/integration/media_retry_smoke_test.dart:385: Same retained media row recovers from sending and retries with attachment intact; no native process kill or remote full image decode. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/private_media_restart_replay_test.dart](../../test/features/conversation/integration/private_media_restart_replay_test.dart) — `reopen terminalizes opening and preserves monotonic expiry across rollback` (integration).
  - Real: production private engine/adapters/FFI SQLite file reopen.
  - Faked: controlled clock; fixture attachment/key store and app files.
  - Proves / registration: test/features/conversation/integration/private_media_restart_replay_test.dart:32: Reopen consumes interrupted opening, refuses replay and retains expiry high-water despite rollback; deadline then expires/cleans once. Not actual OS process kill/SQLCipher. Registered: affected-conversation, host-all.

**Remaining gaps**

- Log-triggered cuts are weaker than byte-progress/owned transfer cutpoints; actual in-flight transfer causality remains unproven. Image-only result; video repeat NOT RUN.
- The processed-sent-source/receiver byte gate and native ledger added after this device source were not executed by this run. No thumbnail-only/full-file or new oracle closure is inferred beyond the executor report.

**Open questions**

- Execution by flutter_app; Astra inspected saved evidence only. See header.group_d_device_run for source/artifact provenance and scope.
- Existing handoff: docs/testing/astra-group-d-device-runbook.md. Actual failures, weaker witnesses and unrun legs above are retained; no rating upgrade.

#### MEDIA-019 — Recipient sees unavailable media; retry restores full content or reports terminal expiry honestly

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008, DC-018.

**Steps**

1. Show unavailable/evicted received media.
2. Tap retry once.
3. Restore full content or settle terminal not-found/expiry without an automatic loop.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: unavailable/evicted/relay-not-found; recovery: explicit retry versus terminal expiry.

**Expected:** Unavailable state remains explicit; retry never claims full content until verified commit.

**Inspected test evidence**

- [test/features/conversation/integration/media_eviction_redownload_test.dart](../../test/features/conversation/integration/media_eviction_redownload_test.dart) — `direct evicted media waits for explicit retry` (integration).
  - Real: real conversation explicit retry/terminal UI.
  - Faked: expired relay bridge; fake network/in-memory repositories.
  - Proves / registration: test/features/conversation/integration/media_eviction_redownload_test.dart:118: Evicted media does not auto-loop and explicit action reaches a truthful terminal download failure; no real provider expiry. Registered: affected-conversation, host-all.
- [test/features/conversation/application/download_media_use_case_test.dart](../../test/features/conversation/application/download_media_use_case_test.dart) — `bounded relay not-found stops after four total attempts` and `bounded relay not-found resumes the remaining budget after real SQLite reopen` (unit).
  - Real: bounded absence classification, independent generic counter, production SQLite interruption/reopen, pending-replay preservation and final recovery exclusion.
  - Faked: bridge responses and retry wait; key-store port and file-manager seam.
  - Proves / registration: The initial not-found plus three further requests use 15/45/120-second declared waits. A real SQL checkpoint after two failures resumes only the remaining two after reopen; replay cannot restart progress or the final unavailable state. This supersedes the immediate first-not-found terminal rule per owner m-ff569538. Actual relay TTL/device timing remains separate. The existing file remains registered in the affected-conversation and media-preservation/strict-manifest selections, and host-all for the later wave. See docs/testing/TESTING.md for verified scope and evidence.
- [test/features/conversation/application/download_media_use_case_test.dart](../../test/features/conversation/application/download_media_use_case_test.dart) — `content hash mismatch on encrypted direct blob fails before decrypt` (unit).
  - Real: actual SHA256/content admission and file removal.
  - Faked: download/crypto bridge; repositories.
  - Proves / registration: test/features/conversation/application/download_media_use_case_test.dart:4342: Hash mismatch rejects before blob:decrypt, publishes no local path, deletes bad bytes and does not ACK-delete relay data. Registered: affected-conversation, group-media-storage-preservation, host-all, strict-group-media-manifest.

**Remaining gaps**

- Terminal retry and hash refusal are causal with fake relay; restoration uses injected download state/bytes rather than a real expired blob/recipient full decoder.

#### MEDIA-020 — Sender preview and recipient original remain distinct when sender cache is deleted

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Send media with a sender preview and a distinct authoritative original.
2. Delete the preview/cache or reopen sender.
3. Receive/download the authoritative original and inspect full content.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: sender preview deleted/corrupt after accepted custody; recovery: retry authoritative source.

**Expected:** Sender cache loss cannot alter/revoke the full accepted original or imply recipient success from a preview.

**Inspected test evidence**

- [test/features/share/integration/external_share_media_custody_recovery_test.dart](../../test/features/share/integration/external_share_media_custody_recovery_test.dart) — `TC-348-03 committed external share survives unusable preview and restart` (integration).
  - Real: DefaultShareBatchDeliveryCoordinator; production current FFI SQLite repos; real files/reopen and strict custody/retry owners.
  - Faked: strict bridge crypto/upload and P2P/inbox; image processing and identity/contact repos; strict feature flag enabled.
  - Proves / registration: test/features/share/integration/external_share_media_custody_recovery_test.dart:36: Committed parent/attachment custody survives lost/unusable preview and DB reopen, retries authoritative bytes once, then records one inbox store. Synthetic JPEG bytes/no recipient decoder and default-off cohort limits apply. Registered: affected-media, host-all.
- [test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart](../../test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart) — `sender encrypts, key rides the v2 envelope, receiver decrypts to byte-identical media` (integration).
  - Real: production upload/send/hydrate/download use cases; actual files/byte equality.
  - Faked: prefix/reverse fake crypto; in-memory relay/P2P/repositories; synthetic512-byte JPEG-named data.
  - Proves / registration: test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart:232: Ciphertext differs from input, key metadata rides the v2 envelope and receiver output equals original bytes. Caption is supplied but not asserted; no real image decode/camera. Fresh audit run: all4 cases passed. Registered: affected-conversation, host-all, media-bytes.

**Remaining gaps**

- Strict local custody test uses a deliberately unusable preview and real authoritative local bytes, but no actual remote recipient/decoder. Default legacy camera path is unverified.

#### MEDIA-021 — Photo/video quality preference is applied while recipient can open the resulting media

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Choose Original/compressed image/video quality.
2. Capture/select media and process with that preference.
3. Send and open the resulting recipient media.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: Original/compressed photo/video quality; recovery: n/a.

**Expected:** Selected quality reaches supported native processing while full received output remains usable.

**Inspected test evidence**

- [test/core/media/image_processor_test.dart](../../test/core/media/image_processor_test.dart) — `calls compress with quality 100 when preference is original` (unit).
  - Real: actual quality argument selection.
  - Faked: compressor callback.
  - Proves / registration: test/core/media/image_processor_test.dart:83: Original passes quality100; neighboring compressed case passes85 and both strip EXIF. Native output format/codec, real camera MIME/bytes and recipient readability are not established. Registered: affected-media, host-all.
- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `recorded single video keeps single-item processing copy` (widget).
  - Real: actual Record Video UI dispatch/progress tile.
  - Faked: FakeMediaPicker; native compressor completer; mp4 files actually contain tiny PNG bytes; repositories/send.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10773: Selecting Record Video drives injected40% progress and single-item Processing text; no native recording/codec/send/recipient playback. Registered: affected-conversation, host-all.
- [integration_test/media_message_journey_e2e_test.dart](../../integration_test/media_message_journey_e2e_test.dart) — `real compose journeys render media for sender and receiver in 1:1 and group threads` (e2e).
  - Real: real direct/group compose/send/listener/widget projection; real PNG fixture/grid decode.
  - Faked: fake picker/bridge/network/in-memory repositories; two logical users in one widget graph.
  - Proves / registration: integration_test/media_message_journey_e2e_test.dart:1093: Recipient caption text IS asserted by _expectVisibleMediaMessage:942 and grid has no broken-image icon. Main PNG case does not open full original viewer or establish real camera/cross-OS transport. Registered original runner is run_test_gates.sh:1113/full regression:403. Registered: registered legacy full inventory (exact dispatch must be inspected).

**Remaining gaps**

- Argument selection100/85 and fake processing UI do not prove actual native format/size/orientation or resulting recipient decode+caption. Original must be audited separately from default compressed.

#### MEDIA-022 — Received image full-screen zoom/swipe/navigation and correct selection across a batch

**Coverage:** strong. **Execution:** host_run. **Catalog:** DC-008.

**Steps**

1. Open an ordinary received image from the exact attachment.
2. Zoom/swipe across multiple items and navigate back.
3. Keep actions tied to the currently visible parent/item.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: multi-item image/GIF pages with same-path siblings; recovery: n/a.

**Expected:** Viewer selection remains exact despite same-path siblings and cross-message paging.

**Fresh host join (2026-10-22)**

- test/shared/widgets/media/full_screen_image_viewer_test.dart:14: Existing real two-pointer pinch, swipes and Back retain exact path/index; host engine decodes 64x32 original and a viewport change preserves selected duplicate-path batch position. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: temporary local receive fixtures; no live transport.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart](../../test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart) — `library opens cross-message typed viewer at exact attachment identity` (widget).
  - Real: real library/viewer navigation and typed identity.
  - Faked: strict fake library repo; fixture media/file/action seams.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart:111: Opening second tile selects exact attachment/message, including same-path siblings. Does not prove remote original authenticity or zoom/pixel quality. Registered: affected-conversation, host-all.
- [test/shared/widgets/media/full_screen_image_viewer_test.dart](../../test/shared/widgets/media/full_screen_image_viewer_test.dart) — `swipes between GIF and JPEG pages` (widget).
  - Real: actual Flutter image viewer/PageView.
  - Faked: fixture media paths; video builder/native dependencies.
  - Proves / registration: test/shared/widgets/media/full_screen_image_viewer_test.dart:92: Swipe changes GIF/JPEG page with correct branches; no real camera-to-recipient content or exhaustive zoom/orientation gestures. Registered: affected-media, host-all.

**Remaining gaps**

- Host viewport resize is not OS rotation. Real transferred full-resolution detail/orientation and device renderer remain separate packet-2 proof. No duplicate gesture test added.

**Open questions**

- Scoped host proof only. Device handoff and exact remaining boundaries: docs/testing/astra-lever1-host-quickwins.md. No actual device, signed-candidate or whole affected-lane verdict.

#### MEDIA-023 — Received video pause/seek/resume/rotate and supported picture-in-picture lifecycle

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Open the selected ordinary received video.
2. Pause/seek/change speed/rotate or background.
3. Enter supported PiP and restore the same owner/position without competing playback.

**Conditions:** platform: shared viewer; supported Android PiP only; connectivity: n/a; offline: n/a; app state: foreground/background/page switch/PiP; input: ordinary authorized video; recovery: n/a.

**Expected:** Only the current authorized video owns playback; controls and PiP preserve its truthful position/lifecycle.

**Inspected test evidence**

- [test/shared/widgets/media/media_video_controls_test.dart](../../test/shared/widgets/media/media_video_controls_test.dart) — `seek speed mute and time controls drive one active adapter safely` (widget).
  - Real: actual video controls/seek clamps/speed cycle.
  - Faked: FakeMediaPlaybackAdapter.
  - Proves / registration: test/shared/widgets/media/media_video_controls_test.dart:15: Controls call one active adapter with correct speed/seek/mute/play/pause; no actual decoder or native frames. Registered: affected-media, host-all.
- [test/shared/widgets/media/media_video_lifecycle_test.dart](../../test/shared/widgets/media/media_video_lifecycle_test.dart) — `only current visible video may play across lifecycle transitions` (widget).
  - Real: actual typed viewer page/lifecycle ownership.
  - Faked: FakeMediaPlaybackAdapter; host lifecycle events.
  - Proves / registration: test/shared/widgets/media/media_video_lifecycle_test.dart:40: Only current page plays; pause does not auto-resume, page changes release old owner and disposal is exact; no native codec/radio. Registered: affected-media, host-all.
- [test/shared/widgets/media/media_picture_in_picture_handoff_test.dart](../../test/shared/widgets/media/media_picture_in_picture_handoff_test.dart) — `PiP handoff has one playback owner and one normalized durable position` (unit).
  - Real: PiP authorization/order/position ownership controller.
  - Faked: native gateway; playback adapter/path authority/resume store.
  - Proves / registration: test/shared/widgets/media/media_picture_in_picture_handoff_test.dart:14: Flutter playback pauses/disposes before native start, stale session ignored and normalized position retained; actual Android PiP/OS controls require separate proof. Registered: affected-media, host-all.

**Remaining gaps**

- Native video decoder and Android PiP gateway are fake in these host tests. Real OS PiP/rotation/audio interruption proof needs its separately registered platform campaign; none executed here.

#### MEDIA-024 — Save/share received ordinary media using platform egress permissions and cancellation

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-008.

**Steps**

1. Choose ordinary received media Save/Share.
2. Qualify exact current owner/path and invoke platform egress.
3. Deny/cancel/busy external handler and inspect unchanged source/truthful outcome.

**Conditions:** platform: Android/iOS Photos/share boundary; connectivity: n/a; offline: n/a; app state: foreground; input: ordinary current image/video; recovery: permission denial/cancel/busy.

**Expected:** Only eligible current media is exported and failed/cancelled platform work preserves source and app.

**Inspected test evidence**

- [test/core/media/received_media_egress_service_test.dart](../../test/core/media/received_media_egress_service_test.dart) — `qualified selection builds one canonical bounded egress request` (unit).
  - Real: actual canonical path/owner/cap/dedup egress qualification; temporary files.
  - Faked: native egress gateway.
  - Proves / registration: test/core/media/received_media_egress_service_test.dart:32: Builds one bounded deduped current-source request; fake gateway returns saved. Real Photos/share permission or actual export not proved. Registered: affected-media, host-all.
- [test/core/media/received_media_egress_service_test.dart](../../test/core/media/received_media_egress_service_test.dart) — `failure busy and late completion preserve source without staging` (unit).
  - Real: actual service/file preservation.
  - Faked: native gateway returning busy.
  - Proves / registration: test/core/media/received_media_egress_service_test.dart:213: Busy leaves source byte-identical and creates no share_staging; source title alone does not prove all late/cancelled native states. Registered: affected-media, host-all.
- [test/features/conversation/application/direct_private_media_boundary_test.dart](../../test/features/conversation/application/direct_private_media_boundary_test.dart) — `Forward denies every private terminal unsupported hidden or missing parent before side effects` (unit).
  - Real: actual current-parent action authority.
  - Faked: permissive file/token/action seams.
  - Proves / registration: test/features/conversation/application/direct_private_media_boundary_test.dart:368: Current private/terminal/unsupported/deleted source refuses Forward before token/file side effects; other tests guard egress/PiP independently. Registered: affected-conversation, host-all.

**Remaining gaps**

- Service/path preservation is causal; native Photos permission, actual share sheet cancellation and destination bytes are mocked/not executed.

#### MEDIA-025 — Open direct/group shared-media library; search/filter, paginate and select the correct parent

**Coverage:** strong. **Execution:** host_run. **Catalog:** source-derived.

**Steps**

1. Open direct/group shared-media library from a conversation.
2. Filter/search/paginate and select an exact attachment.
3. Open its current parent/viewer without crossing owners or stale policy.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: direct/group scope, filters, pages, same-path siblings; recovery: n/a.

**Expected:** Library scope/cursor/parent identity remains exact with truthful unavailable items.

**Fresh host join (2026-10-22)**

- test/features/conversation/integration/media_library_sql_widget_journeys_test.dart:165: Current production SQL file reopen, real canonical group/local direct PNGs, tied 50+2 pages, scope/deleted/sibling isolation, durable bookmark filter, exact typed viewer owner/parent/item and Back join for direct and group libraries. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: synthetic persisted group crypto metadata; no native transfer.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart](../../test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart) — `filters bind direct scope cursor signature and preserve stable paged order` (widget).
  - Real: actual direct library filter/cursor/selection state.
  - Faked: strict library repository and fixture file authority.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart:327: Filters keep direct scope/cursor signature and stable paged ordering; not actual SQL performance or recipient original decode. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart](../../test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart) — `library opens cross-message typed viewer at exact attachment identity` (widget).
  - Real: real library/viewer navigation and typed identity.
  - Faked: strict fake library repo; fixture media/file/action seams.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart:111: Opening second tile selects exact attachment/message, including same-path siblings. Does not prove remote original authenticity or zoom/pixel quality. Registered: affected-conversation, host-all.
- [test/features/conversation/application/direct_private_media_boundary_test.dart](../../test/features/conversation/application/direct_private_media_boundary_test.dart) — `Forward denies every private terminal unsupported hidden or missing parent before side effects` (unit).
  - Real: actual current-parent action authority.
  - Faked: permissive file/token/action seams.
  - Proves / registration: test/features/conversation/application/direct_private_media_boundary_test.dart:368: Current private/terminal/unsupported/deleted source refuses Forward before token/file side effects; other tests guard egress/PiP independently. Registered: affected-conversation, host-all.

**Remaining gaps**

- SQL is host FFI, not native SQLCipher; group encryption metadata is seeded, not authenticated in a live transfer. Mobile original decode/renderer and native delivery remain unrun.

**Open questions**

- Scoped host proof only. Device handoff and exact remaining boundaries: docs/testing/astra-lever1-host-quickwins.md. No actual device, signed-candidate or whole affected-lane verdict.

#### MEDIA-026 — Bookmark, bulk forward, bulk export or bulk local-delete selected library items

**Coverage:** strong. **Execution:** host_run. **Catalog:** source-derived.

**Steps**

1. Select current library items and bookmark/forward/export/delete them.
2. Revalidate each source before side effects.
3. Retry only failed items and retain truthful selection/outcomes.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: up to ten selected items, per-item outcomes; recovery: failed-only retry.

**Expected:** Bulk operations preserve exact owner/parent identities and refuse private/stale sources independently.

**Fresh host join (2026-10-22)**

- test/features/conversation/integration/media_library_sql_widget_journeys_test.dart:412: Actual widget selection -> real current SQL qualification -> batch coordinator -> real owned-file egress service rejects a privacy race before dispatch, hashes exact selected files and retries only failed eligible items. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: native export destination.
- test/features/conversation/integration/media_library_sql_widget_journeys_test.dart:281: SQL reopen preserves independent forward captions/tokens/full-file hashes and guarded bookmark; actual local delete targets exact parent/attachment only; deleted source fails dispatch-time qualification. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: native forward delivery absent; local database delete has no file-manager/export owner.

**Inspected test evidence**

- [test/features/conversation/application/direct_media_library_batch_actions_test.dart](../../test/features/conversation/application/direct_media_library_batch_actions_test.dart) — `batch external share is one qualified native request with failed-only retry state` (unit).
  - Real: actual batch exact-current identity/selection/outcome logic.
  - Faked: native egress gateway/repository seams.
  - Proves / registration: test/features/conversation/application/direct_media_library_batch_actions_test.dart:284: One qualified native request and failed-only retry state; private-state case separately keeps denials item-scoped. Registered: affected-conversation, host-all.
- [test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart](../../test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart) — `failed-cell retry is sparse and preserves each source caption and token` (unit).
  - Real: actual source-target matrix/retry coordinator.
  - Faked: source revalidator; contact repository; strict deliver callback.
  - Proves / registration: test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart:504: Only failed source-target cells retry with original token/latest source caption; settled sent/queued cells remain unchanged. Registered: affected-media, host-all.
- [test/features/conversation/application/private_media_cleanup_race_test.dart](../../test/features/conversation/application/private_media_cleanup_race_test.dart) — `terminal cleanup removes every exact direct artifact and preserves siblings` (unit).
  - Real: production private lifecycle/SQL repositories; real canonical files.
  - Faked: fixture secure key store.
  - Proves / registration: test/features/conversation/application/private_media_cleanup_race_test.dart:131: Deletes exact direct owned artifacts/key references/row, preserves group/unresolved/external siblings; secure-store platform is fake. Registered: affected-conversation, host-all.

**Remaining gaps**

- Existing sparse source-target forward coordinator preservation passed; actual recipient delivery/save/share and native deletion/export lifetime remain separate. Forward-source snapshots are not sent messages.

**Open questions**

- Scoped host proof only. Device handoff and exact remaining boundaries: docs/testing/astra-lever1-host-quickwins.md. No actual device, signed-candidate or whole affected-lane verdict.

#### MEDIA-027 — Voice hold-record/release-send and record-lock review/send preserve playable recipient audio

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-009.

**Steps**

1. Hold/release or lock recording and review it.
2. Explicitly Send the intended recording.
3. Recipient downloads the exact recording and plays it completely.

**Conditions:** platform: Android/iOS UI; native two-peer campaign Android; connectivity: n/a; offline: n/a; app state: foreground; input: hold/release, locked recording/review; recovery: n/a.

**Expected:** Recording UI consent preserves playable exact recipient audio without auto-sending review.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `review send delivers the held recording` (widget).
  - Real: actual voice-review UI/send decision.
  - Faked: FakeAudioRecorderService; sendVoiceMessageFn; repository/P2P.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:13255: Explicit review Send dispatches once and adds outgoing row; recording/playable bytes/receiver are fake. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `review discard drops the recording without sending` (widget).
  - Real: actual review/discard UI and file deletion.
  - Faked: fake recorder; send callback/repositories.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:13273: Discard deletes held fixture file, dispatches zero sends and leaves no outgoing row. Registered: affected-conversation, host-all.
- [integration_test/scripts/android_voice_message_device_campaign.dart](../../integration_test/scripts/android_voice_message_device_campaign.dart) — `android.voice_message_e2e` (sims).
  - Real: production physical Android recorder/Go send; emulator production receive/download/native playback; artifact/hash/identity and cleanup validation.
  - Faked: permission pregranted; campaign setup; UI hold/review gestures bypassed.
  - Proves / registration: integration_test/scripts/android_voice_message_device_campaign.dart:187: lib/core/debug/android_voice_message_e2e.dart:194 records native audio and calls real sendVoiceMessage; :555 awaits actual player start/progress/completion/stop. Evidence validator:128 requires nonempty>=1.5s recording, equal endpoint hashes, real relay/bridge flags and playback. Registered full two-peer campaign; not run here. Registered: see cited native runner/manifest.

**Remaining gaps**

- Full native Android record/send/play campaign exists, but it bypasses hold/lock/review gestures; host review uses a fake recorder/send callback. No single UI-to-recipient native audio journey.

#### MEDIA-028 — Cancel/discard voice recording, deny mic permission or interrupt it with a call

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-009.

**Steps**

1. Start voice recording or deny microphone access.
2. Cancel/discard, reach automatic limit, or acquire a call microphone lease.
3. Retain an unsent review when appropriate and send no unintended recording.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: discard/denied mic/call interruption; recovery: unsent review or idle composer.

**Expected:** Cancellation deletes only owned recording; denial/call interruption never silently sends or loses review intent.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `review discard drops the recording without sending` (widget).
  - Real: actual review/discard UI and file deletion.
  - Faked: fake recorder; send callback/repositories.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:13273: Discard deletes held fixture file, dispatches zero sends and leaves no outgoing row. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `answer stops recording and leaves an unsent review draft` (widget).
  - Real: CallMediaConflictAdapter microphone lease and actual review UI.
  - Faked: fake recorder; call represented by lease acquisition; send/repository/P2P.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:13212: Call acquisition stops recorder once, retains unsent file/review actions and sends nothing. No native call/OS microphone. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `1:1 first plain denied resets to idle with no sheet/snackbar` (widget).
  - Real: real recording-start permission branch/composer state.
  - Faked: FakeMicPermissionGateway/FakeAudioRecorderService.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:15870: Denied request starts no recorder and returns to idle mic with no false recording/send; not an OS permission dialog. Registered: affected-conversation, host-all.

**Remaining gaps**

- Actual UI/lease decisions and file deletion are causal; native microphone permission/call takeover and audio-session release use doubles.

#### MEDIA-029 — Voice playback seek/speed/interruption and competing audio ownership are truthful

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-009.

**Steps**

1. Play a voice note and seek/change speed.
2. Pause/duck/interrupt or start competing call/media.
3. Resume only under current ownership and user intent.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: voice playback, seek/speed and audio interruptions; recovery: one authorized resume.

**Expected:** Playback state and interruption resume ownership stay truthful without duplicate audio.

**Inspected test evidence**

- [test/shared/widgets/media/audio_player_widget_test.dart](../../test/shared/widgets/media/audio_player_widget_test.dart) — `pause interruption pauses active voice and owns exactly one resume` (unit).
  - Real: UserInitiatedVoiceInterruptionHandler.
  - Faked: playing/pause/resume callbacks and injected audio session events.
  - Proves / registration: test/shared/widgets/media/audio_player_widget_test.dart:84: Repeated pause/resume interruption yields one pause and one resume. Actual native session/route and decoded voice are separate. Registered: affected-media, host-all.
- [test/shared/widgets/media/media_video_lifecycle_test.dart](../../test/shared/widgets/media/media_video_lifecycle_test.dart) — `only current visible video may play across lifecycle transitions` (widget).
  - Real: actual typed viewer page/lifecycle ownership.
  - Faked: FakeMediaPlaybackAdapter; host lifecycle events.
  - Proves / registration: test/shared/widgets/media/media_video_lifecycle_test.dart:40: Only current page plays; pause does not auto-resume, page changes release old owner and disposal is exact; no native codec/radio. Registered: affected-media, host-all.
- [integration_test/scripts/android_voice_message_device_campaign.dart](../../integration_test/scripts/android_voice_message_device_campaign.dart) — `android.voice_message_e2e` (sims).
  - Real: production physical Android recorder/Go send; emulator production receive/download/native playback; artifact/hash/identity and cleanup validation.
  - Faked: permission pregranted; campaign setup; UI hold/review gestures bypassed.
  - Proves / registration: integration_test/scripts/android_voice_message_device_campaign.dart:187: lib/core/debug/android_voice_message_e2e.dart:194 records native audio and calls real sendVoiceMessage; :555 awaits actual player start/progress/completion/stop. Evidence validator:128 requires nonempty>=1.5s recording, equal endpoint hashes, real relay/bridge flags and playback. Registered full two-peer campaign; not run here. Registered: see cited native runner/manifest.

**Remaining gaps**

- Native Android voice playback exists in a narrower campaign; interruption handler uses callbacks. Voice seek/speed and actual OS competing call/audio route are not joined with that campaign.

#### MEDIA-030 — Protected media delivery: authorized recipient opens while save/share/forward is refused

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-021.

**Steps**

1. Deliver protected media to an authorized recipient.
2. Open only through the protected route.
3. Attempt save/share/forward/PiP from live or stale ordinary UI.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: protected image/video and stale ordinary route; recovery: n/a.

**Expected:** Private content opens under protection and all unauthorized derivatives remain refused.

**Inspected test evidence**

- [test/features/conversation/application/send_chat_message_use_case_test.dart](../../test/features/conversation/application/send_chat_message_use_case_test.dart) — `valid private policy is encrypted-inner-only and persists on parent` (unit).
  - Real: actual private-policy serialization/parent persistence and outer-envelope separation.
  - Faked: FakeBridge returns opaque crypto; P2P/repositories.
  - Proves / registration: test/features/conversation/application/send_chat_message_use_case_test.dart:5301: Asserts private policy is in encryption input and persisted parent, absent from public envelope; native encryption/decryption and remote private UI not joined. Registered: affected-conversation, host-all, keepalive-campaign-contract.
- [test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart](../../test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart) — `view once protects before bytes records one first frame and close terminalizes before or after first frame` (unit).
  - Real: actual private-viewer controller/native protection ordering/settlement.
  - Faked: native channel completion; fake lifecycle lane/path authority.
  - Proves / registration: test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart:864: No byte-bearing grant before protection succeeds; first-frame admitted once, close consumes/cleans once even before first frame. Actual native capture prevention is not tested. Registered: affected-conversation, host-all.
- [test/features/conversation/application/direct_private_media_boundary_test.dart](../../test/features/conversation/application/direct_private_media_boundary_test.dart) — `Forward denies every private terminal unsupported hidden or missing parent before side effects` (unit).
  - Real: actual current-parent action authority.
  - Faked: permissive file/token/action seams.
  - Proves / registration: test/features/conversation/application/direct_private_media_boundary_test.dart:368: Current private/terminal/unsupported/deleted source refuses Forward before token/file side effects; other tests guard egress/PiP independently. Registered: affected-conversation, host-all.
- [test/features/groups/presentation/group_private_media_viewer_test.dart](../../test/features/groups/presentation/group_private_media_viewer_test.dart) — `GPL-11 capture and background cover immediately then close before native release` (widget).
  - Real: real routed private viewer and cover-before-release ordering.
  - Faked: native event/channel and held settlement; fixture repo/path/media.
  - Proves / registration: test/features/groups/presentation/group_private_media_viewer_test.dart:418: Capture/background covers immediately, waits for settlement, removes viewer then releases native protection; no actual OS screenshot prevention. Registered: affected-groups, host-all.

**Remaining gaps**

- Authorization and cover ordering are causal; actual cryptographic receipt/native protection/OS egress is not a single asserted remote journey.

#### MEDIA-031 — View-once media opens once, survives process interruption and cannot replay after consumption

**Coverage:** strong. **Execution:** not_run. **Catalog:** DC-021.

**Steps**

1. Open one view-once attachment under an exclusive lease.
2. Show first frame or interrupt/close before/after it.
3. Reopen the database/runtime and attempt replay.

**Conditions:** platform: shared local private lifecycle/FFI SQLite boundary; connectivity: n/a; offline: n/a; app state: foreground; input: view-once exact current attachment; recovery: concurrent open, pre-frame close, database reopen/replay.

**Expected:** Only one current lease can expose the item; interrupted/consumed state terminalizes and replay cannot mint a new lease.

**Inspected test evidence**

- [test/features/conversation/application/consume_private_media_use_case_test.dart](../../test/features/conversation/application/consume_private_media_use_case_test.dart) — `two concurrent opens yield exactly one ephemeral lease` (unit).
  - Real: PrivateMediaLifecycleEngine and lifecycle lock.
  - Faked: fake lane adapter and clock.
  - Proves / registration: test/features/conversation/application/consume_private_media_use_case_test.dart:279: Two concurrent opens create exactly one lease; neighboring first-frame/rollback cases reject stale lease and terminalize before cleanup. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart](../../test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart) — `view once protects before bytes records one first frame and close terminalizes before or after first frame` (unit).
  - Real: actual private-viewer controller/native protection ordering/settlement.
  - Faked: native channel completion; fake lifecycle lane/path authority.
  - Proves / registration: test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart:864: No byte-bearing grant before protection succeeds; first-frame admitted once, close consumes/cleans once even before first frame. Actual native capture prevention is not tested. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/private_media_restart_replay_test.dart](../../test/features/conversation/integration/private_media_restart_replay_test.dart) — `reopen terminalizes opening and preserves monotonic expiry across rollback` (integration).
  - Real: production private engine/adapters/FFI SQLite file reopen.
  - Faked: controlled clock; fixture attachment/key store and app files.
  - Proves / registration: test/features/conversation/integration/private_media_restart_replay_test.dart:32: Reopen consumes interrupted opening, refuses replay and retains expiry high-water despite rollback; deadline then expires/cleans once. Not actual OS process kill/SQLCipher. Registered: affected-conversation, host-all.

**Remaining gaps**

- Local state-machine, route-controller and real SQL reopen assertions jointly cover one-use authority; actual OS process kill, native screen protection and signed-store runtime are separate.

#### MEDIA-032 — Disappearing media expires with clock rollback/restart and deletes owned local secrets

**Coverage:** strong. **Execution:** not_run. **Catalog:** DC-021.

**Steps**

1. Receive disappearing media and persist its receipt/deadline/high-water.
2. Roll clock backward, pause/reopen and advance to expiry.
3. Terminalize then delete exact owned local files/key references without touching siblings.

**Conditions:** platform: shared local lifecycle/FFI SQLite/filesystem; connectivity: n/a; offline: n/a; app state: foreground; input: disappearing policy and controlled rollback/deadline; recovery: reopen/expiry cleanup.

**Expected:** Monotonic local expiry cannot be extended by rollback/reopen; terminal cleanup removes only owned artifacts and references.

**Inspected test evidence**

- [test/features/conversation/integration/private_media_restart_replay_test.dart](../../test/features/conversation/integration/private_media_restart_replay_test.dart) — `reopen terminalizes opening and preserves monotonic expiry across rollback` (integration).
  - Real: production private engine/adapters/FFI SQLite file reopen.
  - Faked: controlled clock; fixture attachment/key store and app files.
  - Proves / registration: test/features/conversation/integration/private_media_restart_replay_test.dart:32: Reopen consumes interrupted opening, refuses replay and retains expiry high-water despite rollback; deadline then expires/cleans once. Not actual OS process kill/SQLCipher. Registered: affected-conversation, host-all.
- [test/features/conversation/application/private_media_cleanup_race_test.dart](../../test/features/conversation/application/private_media_cleanup_race_test.dart) — `terminal cleanup removes every exact direct artifact and preserves siblings` (unit).
  - Real: production private lifecycle/SQL repositories; real canonical files.
  - Faked: fixture secure key store.
  - Proves / registration: test/features/conversation/application/private_media_cleanup_race_test.dart:131: Deletes exact direct owned artifacts/key references/row, preserves group/unresolved/external siblings; secure-store platform is fake. Registered: affected-conversation, host-all.
- [test/features/groups/application/group_private_media_expiry_test.dart](../../test/features/groups/application/group_private_media_expiry_test.dart) — `GPL-07 expiry state machine follows approved clock authority across lifecycle` (unit).
  - Real: actual private expiry engine/production SQLite file persistence.
  - Faked: clock and fixture secure keys/files.
  - Proves / registration: test/features/groups/application/group_private_media_expiry_test.dart:62: Clock high-water, receipt-based anchor, lifecycle/reopen and terminal expiry remain monotonic; actual platform scheduling/secure erasure is separate. Registered: affected-groups, host-all.

**Remaining gaps**

- Strong covers local clock/state/file/reference cleanup under host SQL fixtures; real keychain/keystore erasure, wall-clock OS scheduling and device-level secure deletion are unverified.

#### MEDIA-033 — Protected/view-once viewer handles screenshot/capture/background/platform protection failures

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-021.

**Steps**

1. Open private media after platform protection succeeds.
2. Inject screenshot/capture/background or protection failure.
3. Cover immediately, settle exact lifecycle and remove route before releasing protection.

**Conditions:** platform: Android/iOS private protection channel; connectivity: n/a; offline: n/a; app state: background/capture/private route; input: as described; recovery: protection refusal or event.

**Expected:** Private route fails closed and makes only truthful platform capture claims.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart](../../test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart) — `capture removes the exact route and overlays before release despite persistence failures` (widget).
  - Real: real private route cover/dismiss/settlement ordering.
  - Faked: native capture event/channel; persistence-failure fixture.
  - Proves / registration: test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart:1296: Capture covers/removes exact route before protection release even on settlement failure. Actual platform screenshot prevention or OS capture signal remains unexecuted. Registered: affected-conversation, host-all.
- [test/features/groups/presentation/group_private_media_viewer_test.dart](../../test/features/groups/presentation/group_private_media_viewer_test.dart) — `GPL-11 capture and background cover immediately then close before native release` (widget).
  - Real: real routed private viewer and cover-before-release ordering.
  - Faked: native event/channel and held settlement; fixture repo/path/media.
  - Proves / registration: test/features/groups/presentation/group_private_media_viewer_test.dart:418: Capture/background covers immediately, waits for settlement, removes viewer then releases native protection; no actual OS screenshot prevention. Registered: affected-groups, host-all.
- [test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart](../../test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart) — `view once protects before bytes records one first frame and close terminalizes before or after first frame` (unit).
  - Real: actual private-viewer controller/native protection ordering/settlement.
  - Faked: native channel completion; fake lifecycle lane/path authority.
  - Proves / registration: test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart:864: No byte-bearing grant before protection succeeds; first-frame admitted once, close consumes/cleans once even before first frame. Actual native capture prevention is not tested. Registered: affected-conversation, host-all.

**Remaining gaps**

- Native events/channel are mocked in host tests. Actual Android/iOS capture safeguards have separate integration proof sources but were not executed or independently artifact-verified here.

#### MEDIA-034 — Private-media cancel-before-open, unavailable-download retry and delete/read races preserve policy

**Coverage:** strong. **Execution:** host_run. **Catalog:** DC-021.

**Steps**

1. Start a private unavailable-media open then double-tap/cancel/cover.
2. Race a download completion against delete/read/route/lifecycle change.
3. Requalify before any bytes/lease and retain only current owned state.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: private unavailable item and changed parent/lease; recovery: cancel/pause/download completion/delete race.

**Expected:** Late download/open cannot bypass private policy or reopen consumed/deleted content.

**Fresh host join (2026-10-22)**

- test/features/conversation/integration/private_media_sql_open_races_test.dart:29: Four actual SQL/files/lifecycle/viewer cases hold native protection admission then race consume, delete or owner change; no stale byte-bearing grant/re-entry, one valid first frame/close control and sibling file preserved. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: native protection port only.
- test/features/conversation/application/download_media_use_case_test.dart:6241: Existing current-SQL private expiry, relay-failure/hide and timeout late-write cleanup cases freshly pass; existing card single-flight/route/pause guards also freshly pass. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: native bridge/crypto transfer; controlled clock/path adapter.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart](../../test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart) — `rapid double tap downloads then auto-continues under one single-flight` (widget).
  - Real: real private card single-flight/lifecycle guard.
  - Faked: download/open callbacks; repository/clock/native services.
  - Proves / registration: test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart:103: Double tap downloads once and opens once only after completion; companion pause/route cover prevents stale auto-open. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart](../../test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart) — `view once protects before bytes records one first frame and close terminalizes before or after first frame` (unit).
  - Real: actual private-viewer controller/native protection ordering/settlement.
  - Faked: native channel completion; fake lifecycle lane/path authority.
  - Proves / registration: test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart:864: No byte-bearing grant before protection succeeds; first-frame admitted once, close consumes/cleans once even before first frame. Actual native capture prevention is not tested. Registered: affected-conversation, host-all.
- [test/features/conversation/application/direct_private_media_boundary_test.dart](../../test/features/conversation/application/direct_private_media_boundary_test.dart) — `Forward denies every private terminal unsupported hidden or missing parent before side effects` (unit).
  - Real: actual current-parent action authority.
  - Faked: permissive file/token/action seams.
  - Proves / registration: test/features/conversation/application/direct_private_media_boundary_test.dart:368: Current private/terminal/unsupported/deleted source refuses Forward before token/file side effects; other tests guard egress/PiP independently. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/private_media_restart_replay_test.dart](../../test/features/conversation/integration/private_media_restart_replay_test.dart) — `reopen terminalizes opening and preserves monotonic expiry across rollback` (integration).
  - Real: production private engine/adapters/FFI SQLite file reopen.
  - Faked: controlled clock; fixture attachment/key store and app files.
  - Proves / registration: test/features/conversation/integration/private_media_restart_replay_test.dart:32: Reopen consumes interrupted opening, refuses replay and retains expiry high-water despite rollback; deadline then expires/cleans once. Not actual OS process kill/SQLCipher. Registered: affected-conversation, host-all.

**Remaining gaps**

- Native secure-window/capture behavior and actual transfer process death remain unrun. New open-race cases start with a completed file; separate existing SQL download races establish no late commit/resurrection.

**Open questions**

- Scoped host proof only. Device handoff and exact remaining boundaries: docs/testing/astra-lever1-host-quickwins.md. No actual device, signed-candidate or whole affected-lane verdict.

#### MEDIA-035 — Group camera photo/caption reaches every authorized member as a usable full image

**Coverage:** missing. **Execution:** not_run. **Catalog:** GC-006.

**Steps**

1. Capture actual camera photo in a group and add caption.
2. Deliver to every authorized current member.
3. Each member opens/decodes the full correct image and sees exact caption.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: group live/offline fanout; offline: n/a; app state: foreground; input: actual group camera image+caption; Original/compressed; recovery: per-member catch-up.

**Expected:** Every authorized member receives usable actual camera output and exact caption independently.

**Inspected test evidence**

- [integration_test/media_message_journey_e2e_test.dart](../../integration_test/media_message_journey_e2e_test.dart) — `real compose journeys render media for sender and receiver in 1:1 and group threads` (e2e).
  - Real: real direct/group compose/send/listener/widget projection; real PNG fixture/grid decode.
  - Faked: fake picker/bridge/network/in-memory repositories; two logical users in one widget graph.
  - Proves / registration: integration_test/media_message_journey_e2e_test.dart:1093: Recipient caption text IS asserted by _expectVisibleMediaMessage:942 and grid has no broken-image icon. Main PNG case does not open full original viewer or establish real camera/cross-OS transport. Registered original runner is run_test_gates.sh:1113/full regression:403. Registered: registered legacy full inventory (exact dispatch must be inspected).
- [test/features/groups/presentation/group_conversation_wired_test.dart](../../test/features/groups/presentation/group_conversation_wired_test.dart) — `P269 group composer canonicalizes heif to image heic and uploads and publishes once` (widget).
  - Real: real group composer MIME canonicalization/one-send orchestration; HEIF-header fixture file.
  - Faked: injected successful upload; group repositories/bridge/P2P.
  - Proves / registration: test/features/groups/presentation/group_conversation_wired_test.dart:2785: HEIF fixture publishes once with MIME image/heic and sent/done sender state; no camera capture, actual native HEIC decode, received caption or recipient open. Registered: affected-groups, host-all.
- [test/features/groups/integration/group_media_fanout_test.dart](../../test/features/groups/integration/group_media_fanout_test.dart) — `discussion members independently download image, video, and voice for every eligible recipient` (integration).
  - Real: actual group send/listener/download fanout and per-member state.
  - Faked: fake network/bridge/in-memory repositories; four-byte image/video/voice fixtures.
  - Proves / registration: test/features/groups/integration/group_media_fanout_test.dart:399: Every eligible recipient independently downloads descriptor/files with expected metadata; four-byte fixtures do not prove image/video/voice decode or audible playback. Registered: affected-groups, host-all.
- [integration_test/scripts/run_group_media_send_reliability.dart](../../integration_test/scripts/run_group_media_send_reliability.dart) — `group_media_foreground_retry_acl_roundtrip` (sims).
  - Real: registered real-relay Android group process-recovery campaign when executed.
  - Faked: controlled setup/three media fixtures/test flags.
  - Proves / registration: integration_test/scripts/run_group_media_send_reliability.dart:1: Manifest assertions require three kinds exactly once, transport ACL, durable claim process-death recovery and second retry zero; role artifact criteria audited at group_media_reliability_criteria_test.dart:9. No execution/artifact validated here; stock125 camera decode/caption not certified. Registered: groups.media_send_reliability, groups.media_send_reliability_ios, reliability.full.cleaned_legacy.

**Remaining gaps**

- No qualifying actual group camera-output-to-every-member full correct decode/open+caption assertion found. Fake PNG compose checks one logical recipient/grid/caption; HEIF sender test mocks upload; fanout uses four synthetic bytes.

#### MEDIA-036 — Group gallery/video/PDF/voice delivery respects recipient authorization and per-item failures

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-006.

**Steps**

1. Pick group gallery/video/PDF/voice media and caption where allowed.
2. Send only to current authorized members.
3. Verify per-member full content and independent failure/retry.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: group mixed gallery/video/PDF/voice; PDF send flag enabled; recovery: independent recipient failures.

**Expected:** Each eligible member gets usable media; one failure neither authorizes others incorrectly nor hides partial outcomes.

**Inspected test evidence**

- [test/features/groups/integration/group_media_fanout_test.dart](../../test/features/groups/integration/group_media_fanout_test.dart) — `discussion members independently download image, video, and voice for every eligible recipient` (integration).
  - Real: actual group send/listener/download fanout and per-member state.
  - Faked: fake network/bridge/in-memory repositories; four-byte image/video/voice fixtures.
  - Proves / registration: test/features/groups/integration/group_media_fanout_test.dart:399: Every eligible recipient independently downloads descriptor/files with expected metadata; four-byte fixtures do not prove image/video/voice decode or audible playback. Registered: affected-groups, host-all.
- [integration_test/scripts/run_group_media_send_reliability.dart](../../integration_test/scripts/run_group_media_send_reliability.dart) — `group_media_foreground_retry_acl_roundtrip` (sims).
  - Real: registered real-relay Android group process-recovery campaign when executed.
  - Faked: controlled setup/three media fixtures/test flags.
  - Proves / registration: integration_test/scripts/run_group_media_send_reliability.dart:1: Manifest assertions require three kinds exactly once, transport ACL, durable claim process-death recovery and second retry zero; role artifact criteria audited at group_media_reliability_criteria_test.dart:9. No execution/artifact validated here; stock125 camera decode/caption not certified. Registered: groups.media_send_reliability, groups.media_send_reliability_ios, reliability.full.cleaned_legacy.
- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `a picked PDF is staged and a fake PDF is refused` (widget).
  - Real: real document-picker result gating/chips; actual header-check files.
  - Faked: FakeMediaPicker; send/repository seams; header-only PDF fixture.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:10199: With flag on one signature-valid PDF stages, fake PDF is refused with visible copy. No full document parse, native picker or recipient open. Registered: affected-conversation, host-all.
- [integration_test/scripts/android_voice_message_device_campaign.dart](../../integration_test/scripts/android_voice_message_device_campaign.dart) — `android.voice_message_e2e` (sims).
  - Real: production physical Android recorder/Go send; emulator production receive/download/native playback; artifact/hash/identity and cleanup validation.
  - Faked: permission pregranted; campaign setup; UI hold/review gestures bypassed.
  - Proves / registration: integration_test/scripts/android_voice_message_device_campaign.dart:187: lib/core/debug/android_voice_message_e2e.dart:194 records native audio and calls real sendVoiceMessage; :555 awaits actual player start/progress/completion/stop. Evidence validator:128 requires nonempty>=1.5s recording, equal endpoint hashes, real relay/bridge flags and playback. Registered full two-peer campaign; not run here. Registered: see cited native runner/manifest.

**Remaining gaps**

- Full group gallery/native video/PDF/voice output and per-member decode/playback are not joined. Direct Android voice campaign is supporting native/transport evidence, not proof of group delivery.

#### MEDIA-037 — New group member receives only policy-permitted historical media; removed member cannot fetch

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-004, GC-006.

**Steps**

1. Add/remove/readd a group member across retained media.
2. Request permitted history/current descriptors/blobs.
3. Verify new member gets only permitted usable content and removed member cannot fetch future objects.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: new/removed/readded member; historical/current media; recovery: membership epoch changes.

**Expected:** Membership/history/key/blob authorization agrees; old or removed membership cannot expose unauthorized media.

**Inspected test evidence**

- [test/features/groups/integration/group_media_fanout_test.dart](../../test/features/groups/integration/group_media_fanout_test.dart) — `PL-006 MD-011 removed member is excluded from future media descriptors and downloads` (integration).
  - Real: actual membership-based media descriptor/download filtering.
  - Faked: fake group network/relay/bridge/repos.
  - Proves / registration: test/features/groups/integration/group_media_fanout_test.dart:1662: Removed member is omitted from future media descriptors/downloads; not a real deployed relay blob ACL penetration test. Registered: affected-groups, host-all.
- [test/features/groups/integration/group_media_fanout_test.dart](../../test/features/groups/integration/group_media_fanout_test.dart) — `discussion members independently download image, video, and voice for every eligible recipient` (integration).
  - Real: actual group send/listener/download fanout and per-member state.
  - Faked: fake network/bridge/in-memory repositories; four-byte image/video/voice fixtures.
  - Proves / registration: test/features/groups/integration/group_media_fanout_test.dart:399: Every eligible recipient independently downloads descriptor/files with expected metadata; four-byte fixtures do not prove image/video/voice decode or audible playback. Registered: affected-groups, host-all.
- [integration_test/scripts/run_group_media_send_reliability.dart](../../integration_test/scripts/run_group_media_send_reliability.dart) — `group_media_foreground_retry_acl_roundtrip` (sims).
  - Real: registered real-relay Android group process-recovery campaign when executed.
  - Faked: controlled setup/three media fixtures/test flags.
  - Proves / registration: integration_test/scripts/run_group_media_send_reliability.dart:1: Manifest assertions require three kinds exactly once, transport ACL, durable claim process-death recovery and second retry zero; role artifact criteria audited at group_media_reliability_criteria_test.dart:9. No execution/artifact validated here; stock125 camera decode/caption not certified. Registered: groups.media_send_reliability, groups.media_send_reliability_ios, reliability.full.cleaned_legacy.

**Remaining gaps**

- Fake-network membership filters and registered real-relay ACL checks are narrower; actual historical media/key-window admission plus removed-peer real blob fetch attempts and full decoder are not joined.

#### MEDIA-038 — Expired relay blob, corrupt ciphertext/hash or missing key never becomes a valid visible attachment

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-018, GX-003.

**Steps**

1. Download expired/corrupted/wrong-key/missing-key media.
2. Verify hash/crypto/owner before publishing a canonical original.
3. Keep terminal/integrity failure truthful and permit only policy-valid retries.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: expired blob, corrupt bytes/hash, wrong/missing key; recovery: terminal failure or operational retry.

**Expected:** Bad or unavailable bytes never become a valid visible attachment/done original.

**Inspected test evidence**

- [test/features/conversation/application/download_media_use_case_test.dart](../../test/features/conversation/application/download_media_use_case_test.dart) — `content hash mismatch on encrypted direct blob fails before decrypt` (unit).
  - Real: actual SHA256/content admission and file removal.
  - Faked: download/crypto bridge; repositories.
  - Proves / registration: test/features/conversation/application/download_media_use_case_test.dart:4342: Hash mismatch rejects before blob:decrypt, publishes no local path, deletes bad bytes and does not ACK-delete relay data. Registered: affected-conversation, group-media-storage-preservation, host-all, strict-group-media-manifest.
- [test/features/groups/integration/group_media_fanout_test.dart](../../test/features/groups/integration/group_media_fanout_test.dart) — `tampered fake-network media download fails integrity before done` (integration).
  - Real: actual listener/download/hash status and filesystem cleanup.
  - Faked: fake group network/bridge/repositories; four synthetic bytes.
  - Proves / registration: test/features/groups/integration/group_media_fanout_test.dart:2107: Tampered group attachment reaches integrity_failed, no localPath/file and one download; no native codec or actual cryptographic authentication. Registered: affected-groups, host-all.
- [test/features/conversation/application/download_media_use_case_test.dart](../../test/features/conversation/application/download_media_use_case_test.dart) — `bounded relay not-found stops after four total attempts` and `bounded relay not-found resumes the remaining budget after real SQLite reopen` (unit).
  - Real: bounded absence classification, independent generic counter, production SQLite interruption/reopen, pending-replay preservation and final recovery exclusion.
  - Faked: bridge responses and retry wait; key-store port and file-manager seam.
  - Proves / registration: The initial not-found plus three further requests use 15/45/120-second declared waits. A real SQL checkpoint after two failures resumes only the remaining two after reopen; replay cannot restart progress or the final unavailable state. This supersedes the immediate first-not-found terminal rule per owner m-ff569538. Actual relay TTL/device timing remains separate. The existing file remains registered in the affected-conversation and media-preservation/strict-manifest selections, and host-all for the later wave. See docs/testing/TESTING.md for verified scope and evidence.
- [test/features/conversation/application/direct_private_media_boundary_test.dart](../../test/features/conversation/application/direct_private_media_boundary_test.dart) — `Forward denies every private terminal unsupported hidden or missing parent before side effects` (unit).
  - Real: actual current-parent action authority.
  - Faked: permissive file/token/action seams.
  - Proves / registration: test/features/conversation/application/direct_private_media_boundary_test.dart:368: Current private/terminal/unsupported/deleted source refuses Forward before token/file side effects; other tests guard egress/PiP independently. Registered: affected-conversation, host-all.

**Remaining gaps**

- Actual SHA256/refusal is causal; crypto provider is fake here and deployed relay expiry/native decoder integration is separate. Real Go AEAD tests cannot alone certify a displayed attachment.

### GROUP — Group membership, messaging and management

#### GX-001 — Larger group (8 members)

**Coverage:** missing. **Execution:** not_run. **Catalog:** GX-001.

**Steps**

1. Create eight-member group.
2. Have every member send and verify each other member receives once.

**Conditions:** platform: available target matrix only; not discovered in this host-only audit; connectivity: n/a; offline: n/a; app state: foreground; input: 8 concurrent app actors; recovery: n/a.

**Expected:** Every member of an 8-member group sends and every member receives exactly once.

**Inspected test evidence**

- [test/features/groups/integration/group_edge_cases_smoke_test.dart](../../test/features/groups/integration/group_edge_cases_smoke_test.dart) — `5 users simultaneous messaging — high fan-out` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_edge_cases_smoke_test.dart:158: Five modeled app peers each send; every peer has1 outgoing+4 incoming and20 deliveries total. Five fake peers do not prove eight native app endpoints. Registered: affected-groups, host-all.

**Remaining gaps**

- Closest inspected host fanout uses5 modeled peers; registered production full-mesh uses3, shared journey wiring up to4. No eight-actor send/receive journey found. Run only if eight targets actually available; unavailable topology is N/A by policy.

#### GX-002 — Mixed iPhone and Android group

**Coverage:** missing. **Execution:** not_run. **Catalog:** GX-002.

**Steps**

1. Join actual iPhone and Android in same group.
2. Exchange text, full media and membership changes in both directions.

**Conditions:** platform: iOS/Android parity; only available targets; connectivity: n/a; offline: n/a; app state: foreground; input: mixed group, actual media and member changes; recovery: n/a.

**Expected:** A group with iPhones and Android phones delivers messages, media and member changes to everyone.

**Inspected test evidence**

- [integration_test/scripts/run_production_group_create.dart](../../integration_test/scripts/run_production_group_create.dart) — `production.group_catalog.private_abc_create` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_create.dart:11: main:11 creates through UI, observes both pending invites before supported accept, checks readable joins, initial epoch and exact message; validator tool/sims/production_group_create_criteria.dart. Role identity/bootstrap uses the shared production journey fixture. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_catalog.private_abc_create.
- [test/features/groups/integration/group_membership_smoke_test.dart](../../test/features/groups/integration/group_membership_smoke_test.dart) — `GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_membership_smoke_test.dart:5212: Production membership/send/listener policies reject removed-window traffic and admit post-readd current epoch in fake network. restartWithPersistedState at test/shared/fakes/group_test_user.dart:979 reuses in-memory repositories; not a disk/process restart. Registered: affected-groups, host-all.

**Remaining gaps**

- No full mixed-platform group assertion found. Android catalog campaigns and fake shared policy cannot certify iOS/Android parity; signed-chat-group-media is an adjacent release lane, not this complete journey.

#### GC-001 — Create, invite, join and add a member

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-001.

**Steps**

1. Create group from picker.
2. Accept/decline invitations and add another member.
3. Verify future-only admitted history and new live traffic.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Create a group through the shipped UI, accept or decline invites, then add a member to an existing group; entitled history and future messages converge without exposing pre-admission content outside policy.

**Inspected test evidence**

- [integration_test/scripts/run_production_group_create.dart](../../integration_test/scripts/run_production_group_create.dart) — `production.group_catalog.private_abc_create` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_create.dart:11: main:11 creates through UI, observes both pending invites before supported accept, checks readable joins, initial epoch and exact message; validator tool/sims/production_group_create_criteria.dart. Role identity/bootstrap uses the shared production journey fixture. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_catalog.private_abc_create.
- [integration_test/scripts/run_production_group_invite_reliability.dart](../../integration_test/scripts/run_production_group_invite_reliability.dart) — `production.group_invite_reliability` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_invite_reliability.dart:11: main:11 drives decline, exact revoke/delayed old invite rejection and stale-to-fresh metadata. tool/sims/production_group_invite_criteria.dart:158 checks exact consumed invite; :176 checks real metadata convergence. Polling explicitly drains inbox, so this is not autonomous push recovery. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_invite_reliability.
- [test/features/groups/integration/group_new_member_onboarding_test.dart](../../test/features/groups/integration/group_new_member_onboarding_test.dart) — `quoted reply to pre-join parent keeps missing-parent fallback for new member` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_new_member_onboarding_test.dart:1148: New member retains quote identity but receives unavailable-parent fallback, with no pre-join row disclosure; fake byte/transport harness. Registered: affected-groups, host-all.
- [test/features/groups/presentation/create_group_picker_wired_test.dart](../../test/features/groups/presentation/create_group_picker_wired_test.dart) — `tapping Start group chat creates group and navigates to conversation` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: fake identity/bridge/P2P and in-memory stores.
  - Proves / registration: test/features/groups/presentation/create_group_picker_wired_test.dart:326: Actual picker route creates group and navigates with fake identity/bridge/P2P and in-memory stores; this is not native transport. Registered: affected-groups, host-all.

**Remaining gaps**

- Real create/invite campaigns exist; accepted history/media and existing-group add are separate cases, not one complete UI/native joined journey. No campaign executed here.

#### GC-002 — Every member receives ordered text exactly once

**Coverage:** strong. **Execution:** not_run. **Catalog:** GC-002.

**Steps**

1. Join three authorized members.
2. Each member sends to others.
3. Send100 ordered texts and replay same identity.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: 3 actors;100 same-sender sequence plus each-member round robin; recovery: explicit receiver replay drain.

**Expected:** Available authorized members each send and receive; a 100-message sequence is complete and ordered, and replay preserves logical identities without duplicate rows.

**Inspected test evidence**

- [integration_test/scripts/run_production_group_full_mesh.dart](../../integration_test/scripts/run_production_group_full_mesh.dart) — `production.group_catalog.private_full_mesh_online` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_full_mesh.dart:5: main:5 sends from each of three actors and waits for each other actor; validator production_group_full_mesh_criteria.dart binds exact rows. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_catalog.private_full_mesh_online.
- [integration_test/scripts/run_production_group_de002.dart](../../integration_test/scripts/run_production_group_de002.dart) — `production.group_catalog.de002` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_de002.dart:6: main:6 sends100 numbered texts through composer, each receiver holds every exact row once; tool/sims/production_group_de002_criteria.dart:60 also checks sender identity and strict timestamp order. This is one sender and two receivers, not eight actors. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_catalog.de002.
- [integration_test/scripts/run_production_group_de003.dart](../../integration_test/scripts/run_production_group_de003.dart) — `production.group_catalog.de003` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_de003.dart:4: main:4 sends through production composition then explicitly drains both receivers and counts the same logical message; production_group_send_cases_criteria.dart owns exact verdict. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_catalog.de003.

**Remaining gaps**

- Coverage combines registered exact production full-mesh, ordered100 and replay cases. No runs in this audit; it does not generalize to eight members or every signed candidate.

#### GC-003 — Offline and background members recover naturally

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-003.

**Steps**

1. Disconnect/background recipient.
2. Send while unavailable and restart/resume recipient.
3. Observe natural catch-up followed by fresh live traffic.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: recipient unavailable; app state: background/process restart; input: as described; recovery: natural foreground/push recovery.

**Expected:** Relay custody preserves entitled messages through disconnection and process restart; the normal foreground or push trigger catches up once in order, followed by fresh live delivery.

**Inspected test evidence**

- [test/features/groups/integration/group_resume_recovery_test.dart](../../test/features/groups/integration/group_resume_recovery_test.dart) — `member backgrounded during send receives missed group messages after resume` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_resume_recovery_test.dart:1921: Unsubscribes a fake network member, manually seeds signed replay into cursor bridge and invokes drain; missed message appears once. Background label does not represent real OS lifecycle/push. Registered: affected-groups, host-all.
- [test/features/groups/integration/group_resume_recovery_test.dart](../../test/features/groups/integration/group_resume_recovery_test.dart) — `PREREQ-HISTORY-GAP-REPAIR fake-network repair rejects bad source then restores range before live delivery` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_resume_recovery_test.dart:1754: Bad source rejected then range repair precedes live delivery; source/key/hash and source identity assertions are real policy with fake wire and stores. Registered: affected-groups, host-all.
- [integration_test/scripts/run_production_group_de003.dart](../../integration_test/scripts/run_production_group_de003.dart) — `production.group_catalog.de003` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_de003.dart:4: main:4 sends through production composition then explicitly drains both receivers and counts the same logical message; production_group_send_cases_criteria.dart owns exact verdict. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_catalog.de003.

**Remaining gaps**

- Host background is fake unsubscribe plus manually seeded inbox. Registered replay campaigns may explicitly drain; natural push/foreground recovery, process restart and ordered backlog are not proven together.

#### GC-004 — Removed members lose content and mutation access

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-004.

**Steps**

1. Remove member online or offline.
2. Attempt removed-window text/media/reaction access.
3. Re-add and verify only entitled history/current epoch and safe notifications.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Online or offline removal and later re-add enforce the actual history and epoch boundary; removed-window text/media remain inaccessible, stale reactions are rejected, and notification previews do not disclose excluded content.

**Inspected test evidence**

- [integration_test/scripts/run_production_group_gm007.dart](../../integration_test/scripts/run_production_group_gm007.dart) — `production.group_catalog.gm007` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_gm007.dart:6: main:6 observes pre-removal text, excluded-window texts, removal rotation, re-add and allowed new text. Explicit catch-up drain:57 means this is not purely natural recovery. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_catalog.gm007.
- [test/features/groups/integration/group_reaction_roundtrip_test.dart](../../test/features/groups/integration/group_reaction_roundtrip_test.dart) — `PL-010 removed member reaction is ignored by Alice and Bob without visible mutation` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_reaction_roundtrip_test.dart:214: Removed member reaction is ignored by both current peers without visible mutation; fake wire/bridge, not OS delivery. Registered: affected-groups, host-all.
- [integration_test/scripts/run_production_group_up012.dart](../../integration_test/scripts/run_production_group_up012.dart) — `production.group_catalog.private_removed_notification_privacy` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_up012.dart:5: main:5 removes Charlie, rotates, sends A/B messages away from chat, asserts positive notification controls and waits5s before absence counting; validator production_group_up012_criteria.dart. Actual provider/native lockscreen preview parity is separate. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_catalog.private_removed_notification_privacy.

**Remaining gaps**

- Substantive production text-window and notification-observation campaigns exist; media entitlement/native preview across offline removal/re-add are separate boundaries. Full exact signed-candidate conjunction unexecuted.

#### GC-005 — Accepted text and membership survive process death

**Coverage:** partial. **Execution:** device_run. **Catalog:** GC-005.

**Steps**

1. Kill owned process after verified accepted text.
2. Reopen and verify same-ID delivery once.
3. Repeat around add/removal/re-add without restoring revoked access.

**Conditions:** platform: executor-reported Pixel6 physical plus available headless Android emulator; disposable Group D debug package; host evidence only; connectivity: n/a; offline: n/a; app state: owned-process termination; input: as described; recovery: text custody and membership reopen.

**Expected:** Owned-process termination at a verified accepted-text checkpoint preserves same-ID delivery exactly once; membership add, removal and re-add recover without restoring revoked access.

**Group D device execution (2026-10-22; flutter_app)**

- Result: **PASS_MANUAL_TWO_PEER_UI_THREE_PEER_HARNESS_NOT_RUN**.
- Manual two-peer UI run passed accepted-text sender cut after inboxStored=true, remove/re-add with kill/reopen, and removed-window exclusion.
- The SIMS three-peer process-death harness was not run; manual two-peer evidence does not stand in for it.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/SUMMARY.md:8`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/gc005_cut.txt:1`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/gc005_recovery.txt:1`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/gc005_remove.txt:1`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/gc005_readd.txt:1`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/gc005_replay_check.txt:1`.

**Inspected test evidence**

- [test/features/groups/integration/group_text_custody_restart_test.dart](../../test/features/groups/integration/group_text_custody_restart_test.dart) — `GC-005 accepted text and membership survive both SQL/runtime restarts; replayed custody keeps one identity` (integration).
  - Real: production sendGroupMessage accepts fake inbox custody before receiver delivery; both current-schema SQL/repository/listener graphs recreated; production signed-envelope decoder and GroupMessageListener replay into SQL once; member roles/key epoch and removal/re-add persist.
  - Faked: ZeroPeerPublishBridge/FakeBridge native relay and signatures/encryption; fake secure keychain survives outside recreated graphs; clean SQL close/reopen models a checkpoint, not abrupt OS termination; full revoked-key isolation not claimed.
  - Proves / registration: test/features/groups/integration/group_text_custody_restart_test.dart:30: Fresh file 016:1 passed,0 skipped/failed,exit0. Same accepted message ID/text survives sender reopen and reaches recreated receiver once after duplicate replay; roster removal is not resurrected and fresh re-add retains writer role. Evidence .codex-test-logs/astra-groupCD/016-D-group-custody-summary.json/receipt. Registered: affected-groups, host-all.
- [integration_test/scripts/run_production_group_process_death.dart](../../integration_test/scripts/run_production_group_process_death.dart) — `production.group_catalog.private_process_death_matrix` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_process_death.dart:11: run_production_group_process_death.dart:253 verifies owned-process kill evidence after persisted add/removal/re-add and reopens. tool/sims/production_group_process_death_criteria.dart:74 checks those three cuts and current membership; no accepted-text sender kill. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_catalog.private_process_death_matrix.
- [test/features/groups/integration/group_resume_recovery_test.dart](../../test/features/groups/integration/group_resume_recovery_test.dart) — `member backgrounded during send receives missed group messages after resume` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_resume_recovery_test.dart:1921: Unsubscribes a fake network member, manually seeds signed replay into cursor bridge and invokes drain; missed message appears once. Background label does not represent real OS lifecycle/push. Registered: affected-groups, host-all.

**Remaining gaps**

- Three-peer process-death harness remains NOT RUN. Recorded manual two-peer actions are a narrower native witness; no broad group topology, historical revoked-key isolation or signed-release pass is inferred.

**Open questions**

- Execution by flutter_app; Astra inspected saved evidence only. See header.group_d_device_run for source/artifact provenance and scope.
- Existing handoff: docs/testing/astra-group-d-device-runbook.md. Actual failures, weaker witnesses and unrun legs above are retained; no rating upgrade.

#### GC-008 — Leave, delete and supported admin changes preserve access rules

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-008.

**Steps**

1. Leave or delete group; cancel once before confirming.
2. Try sole-admin leave and supported role transfer.
3. Check remaining group and unrelated direct chats.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Leaving or deleting a group stops future access and preserves unrelated direct chats; last-admin safeguards and exposed role-transfer actions leave the remaining group usable.

**Inspected test evidence**

- [test/features/groups/application/group_exit_intent_runner_test.dart](../../test/features/groups/application/group_exit_intent_runner_test.dart) — `PB264-09 real SQLite prepare and completion faults roll back atomically and restart reuses the durable signature` (unit).
  - Real: production exit runner and real FFI SQLite transactions.
  - Faked: controlled signing/native leave/network callbacks; injected SQL faults.
  - Proves / registration: test/features/groups/application/group_exit_intent_runner_test.dart:1528: Real SQL transactions roll back prepare/completion faults and recreate runner reusing durable signature. Native leave, signing and network injected; no actual OS process/radio loss. Registered: affected-groups, host-all.
- [test/features/groups/application/update_group_member_role_use_case_test.dart](../../test/features/groups/application/update_group_member_role_use_case_test.dart) — `blocks removing the last admin from the group` (unit).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: in-memory groups; FakeBridge signing/config/network.
  - Proves / registration: test/features/groups/application/update_group_member_role_use_case_test.dart:640: Last-admin demotion rejected at use-case boundary. Promotion and manage-role override cases nearby test authorization with recording/fake bridge. Registered: affected-groups, host-all.
- [test/features/groups/presentation/group_info_wired_test.dart](../../test/features/groups/presentation/group_info_wired_test.dart) — `Group Info asks before leaving and Cancel keeps the group` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: in-memory repositories and fake native/network bridge.
  - Proves / registration: test/features/groups/presentation/group_info_wired_test.dart:6045: Cancel preserves group/route; confirms pre-action behavior through actual Info route with fake backend. Registered: affected-groups, host-all.
- [test/features/groups/presentation/group_info_wired_test.dart](../../test/features/groups/presentation/group_info_wired_test.dart) — `canceling dissolved local delete keeps the group state and route intact` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: in-memory repositories and fake bridge.
  - Proves / registration: test/features/groups/presentation/group_info_wired_test.dart:7393: Cancelled local delete preserves dissolved group and route; no delete side effect. Registered: affected-groups, host-all.

**Remaining gaps**

- Real SQL exit fault/recreation and UI cancellation guards exist. Native leave, end-to-end remaining-member convergence and direct-chat preservation are separate registered/host cases, unexecuted here.

#### GC-009 — Supported group replies, reactions and local deletion behave correctly

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-009.

**Steps**

1. Reply with existing or unavailable parent.
2. Add/remove reaction.
3. Delete received media locally and reopen/replay.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Quotes preserve parent identity and entitlement-safe unavailable-parent rendering; reaction add/remove converges; received-media delete-for-me remains local, persists across reopen and preserves unrelated content.

**Inspected test evidence**

- [test/features/groups/integration/group_new_member_onboarding_test.dart](../../test/features/groups/integration/group_new_member_onboarding_test.dart) — `quoted reply to pre-join parent keeps missing-parent fallback for new member` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_new_member_onboarding_test.dart:1148: New member retains quote identity but receives unavailable-parent fallback, with no pre-join row disclosure; fake byte/transport harness. Registered: affected-groups, host-all.
- [test/features/groups/integration/group_reaction_roundtrip_test.dart](../../test/features/groups/integration/group_reaction_roundtrip_test.dart) — `PL-010 removed member reaction is ignored by Alice and Bob without visible mutation` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_reaction_roundtrip_test.dart:214: Removed member reaction is ignored by both current peers without visible mutation; fake wire/bridge, not OS delivery. Registered: affected-groups, host-all.
- [test/features/groups/integration/group_received_media_delete_replay_test.dart](../../test/features/groups/integration/group_received_media_delete_replay_test.dart) — `GMA-08 self contained journal saga converges per item across every restart boundary` (integration).
  - Real: current FFI SQLite media-deletion journal/helpers; real files and production reconciler.
  - Faked: fake secure key store; injected file/key deletion failures and recreated objects.
  - Proves / registration: test/features/groups/integration/group_received_media_delete_replay_test.dart:197: Real SQL journal and actual temporary files preserve per-item cleanup state through injected file/key failures and fresh reconciler instances; preserves unrelated orphan and eventually finishes. Secure key store is fake; recreation is not a real OS kill. Registered: affected-groups, host-all.

**Remaining gaps**

- Quote entitlement, reaction authorization and real local deletion journal are causal but split across fake transport and secure-store seams; no complete actual-app combined reply/reaction/delete-for-me journey run.

#### GROUP-001 — Cancel group creation or submit empty/invalid names and selections

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open create picker, search/select contacts.
2. Cancel before create.
3. Submit empty/whitespace name or invalid selection and inspect supported naming policy.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Cancel group creation or submit empty/invalid names and selections

**Inspected test evidence**

- [test/features/groups/presentation/create_group_picker_wired_test.dart](../../test/features/groups/presentation/create_group_picker_wired_test.dart) — `back button pops screen` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: fake repositories/bridge/P2P.
  - Proves / registration: test/features/groups/presentation/create_group_picker_wired_test.dart:516: Back pops route. Test asserts navigation, not a complete zero-write/zero-egress counter proof. Registered: affected-groups, host-all.
- [test/features/groups/presentation/create_group_picker_wired_test.dart](../../test/features/groups/presentation/create_group_picker_wired_test.dart) — `tapping Start group chat creates group and navigates to conversation` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: fake identity/bridge/P2P and in-memory stores.
  - Proves / registration: test/features/groups/presentation/create_group_picker_wired_test.dart:326: Actual picker route creates group and navigates with fake identity/bridge/P2P and in-memory stores; this is not native transport. Registered: affected-groups, host-all.

**Remaining gaps**

- Back-only assertion lacks all zero-write/egress counters. Empty name is an optional naming input passed to createGroupWithMembers (create_group_picker_wired.dart:204); do not invent mandatory-name validation. Invalid selection and no-ghost rollback need joined assertions.

**Open questions**

- Confirm desired optional/empty group-name fallback; source accepts optional name rather than exposing a required-name error contract.

#### GROUP-002 — Rename group or update/remove avatar with admin authorization and recipient convergence

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Admin renames and replaces/removes avatar.
2. Existing and late members converge exact metadata/avatar.
3. Revoke authority during edit and reject stale completion.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Rename group or update/remove avatar with admin authorization and recipient convergence

**Inspected test evidence**

- [test/features/groups/integration/group_admin_metadata_convergence_test.dart](../../test/features/groups/integration/group_admin_metadata_convergence_test.dart) — `scenario7_late_invitee_acceptance_closes_stale_metadata_invite_and_four_user_fanout` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_admin_metadata_convergence_test.dart:2948: Four logical users, stale invite plus later metadata/avatar, real host avatar files/hash/decode helper and each-sender fanout converge. Group bridge/network/cryptography remain test doubles. Registered: affected-groups, host-all.
- [test/features/groups/presentation/group_info_wired_test.dart](../../test/features/groups/presentation/group_info_wired_test.dart) — `demote admin shows confirmation, updates badge, and emits success feedback` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: in-memory groups/contacts and fake bridge/P2P.
  - Proves / registration: test/features/groups/presentation/group_info_wired_test.dart:5498: Confirmation, role badge and success feedback update after actual wired action using fake bridge/stores; no cross-device native convergence. Registered: affected-groups, host-all.

**Remaining gaps**

- Real host files/avatar decoding and four-user metadata fanout exist with fake crypto/transport. Native picker/crop/upload, removal variant and signed recipient convergence are separate.

#### GROUP-003 — Invite offline member; accept/decline, retry, resend or revoke a pending invite

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Invite offline member.
2. Accept/decline, fail/resend delivery or revoke exact pending invite.
3. Replay old copies and check truthful status.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Invite offline member; accept/decline, retry, resend or revoke a pending invite

**Inspected test evidence**

- [integration_test/scripts/run_production_group_invite_reliability.dart](../../integration_test/scripts/run_production_group_invite_reliability.dart) — `production.group_invite_reliability` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_invite_reliability.dart:11: main:11 drives decline, exact revoke/delayed old invite rejection and stale-to-fresh metadata. tool/sims/production_group_invite_criteria.dart:158 checks exact consumed invite; :176 checks real metadata convergence. Polling explicitly drains inbox, so this is not autonomous push recovery. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_invite_reliability.
- [test/features/groups/presentation/contact_picker_wired_test.dart](../../test/features/groups/presentation/contact_picker_wired_test.dart) — `shows contacts excluding existing group members` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: in-memory groups/contacts and fake bridge/P2P.
  - Proves / registration: test/features/groups/presentation/contact_picker_wired_test.dart:561: Existing member and self exclusion covered in wired picker; fake repositories/contact loading. Blocked/invalid-key eligibility not comprehensively demonstrated here. Registered: affected-groups, host-all.

**Remaining gaps**

- Actual decline/revoke/stale campaign explicitly drains inbox. Offline receiver restart and all resend/failure/status UI conditions are distributed across tests rather than one full journey.

#### GROUP-004 — Accept a stale invite and converge current signed group metadata

**Coverage:** strong. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Receive invite snapshot.
2. Admin changes metadata before acceptance.
3. Accept stale snapshot then obtain current authenticated config.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Accepted stale invite converges current signed name/avatar/config without downgrading metadata.

**Inspected test evidence**

- [integration_test/scripts/run_production_group_invite_reliability.dart](../../integration_test/scripts/run_production_group_invite_reliability.dart) — `production.group_invite_reliability` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_invite_reliability.dart:11: main:11 drives decline, exact revoke/delayed old invite rejection and stale-to-fresh metadata. tool/sims/production_group_invite_criteria.dart:158 checks exact consumed invite; :176 checks real metadata convergence. Polling explicitly drains inbox, so this is not autonomous push recovery. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_invite_reliability.
- [test/features/groups/integration/group_admin_metadata_convergence_test.dart](../../test/features/groups/integration/group_admin_metadata_convergence_test.dart) — `scenario7_late_invitee_acceptance_closes_stale_metadata_invite_and_four_user_fanout` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_admin_metadata_convergence_test.dart:2948: Four logical users, stale invite plus later metadata/avatar, real host avatar files/hash/decode helper and each-sender fanout converge. Group bridge/network/cryptography remain test doubles. Registered: affected-groups, host-all.

**Remaining gaps**

- Registered actual-app stale-to-fresh metadata assertions plus four-user host/avatar checks. Campaign polling explicitly drains inbox; autonomous notification timing and every native image codec are outside this scoped journey.

#### GROUP-005 — Search/select contacts to add while excluding existing, blocked or invalid members

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Search contacts to add.
2. Exclude self/existing and disallowed contacts.
3. Select batch, reject stale authority and add valid members.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Search/select contacts to add while excluding existing, blocked or invalid members

**Inspected test evidence**

- [test/features/groups/presentation/create_group_picker_screen_test.dart](../../test/features/groups/presentation/create_group_picker_screen_test.dart) — `search filters contacts by username` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: provided contact rows/callbacks.
  - Proves / registration: test/features/groups/presentation/create_group_picker_screen_test.dart:126: Actual search widget filters provided contacts by username; callbacks/contact list supplied. Registered: affected-groups, host-all, ui-tap-gestures.
- [test/features/groups/presentation/contact_picker_wired_test.dart](../../test/features/groups/presentation/contact_picker_wired_test.dart) — `shows contacts excluding existing group members` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: in-memory groups/contacts and fake bridge/P2P.
  - Proves / registration: test/features/groups/presentation/contact_picker_wired_test.dart:561: Existing member and self exclusion covered in wired picker; fake repositories/contact loading. Blocked/invalid-key eligibility not comprehensively demonstrated here. Registered: affected-groups, host-all.

**Remaining gaps**

- Widget filtering and existing/self exclusion proven with supplied/fake stores; blocked/invalid-key contact eligibility and refreshed selection-to-zero-side-effects are not comprehensively joined.

#### GROUP-006 — Promote/demote an administrator and enforce permissions on every member

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Promote/demote eligible member.
2. Attempt non-admin or revoked-permission role update and last-admin demotion.
3. Observe role and permissions at every member.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Promote/demote an administrator and enforce permissions on every member

**Inspected test evidence**

- [test/features/groups/application/update_group_member_role_use_case_test.dart](../../test/features/groups/application/update_group_member_role_use_case_test.dart) — `blocks removing the last admin from the group` (unit).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: in-memory groups; FakeBridge signing/config/network.
  - Proves / registration: test/features/groups/application/update_group_member_role_use_case_test.dart:640: Last-admin demotion rejected at use-case boundary. Promotion and manage-role override cases nearby test authorization with recording/fake bridge. Registered: affected-groups, host-all.
- [test/features/groups/presentation/group_info_wired_test.dart](../../test/features/groups/presentation/group_info_wired_test.dart) — `demote admin shows confirmation, updates badge, and emits success feedback` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: in-memory groups/contacts and fake bridge/P2P.
  - Proves / registration: test/features/groups/presentation/group_info_wired_test.dart:5498: Confirmation, role badge and success feedback update after actual wired action using fake bridge/stores; no cross-device native convergence. Registered: affected-groups, host-all.

**Remaining gaps**

- Local use-case and actual UI confirmation tests use fake signing/config/network; real concurrent actor/recipient permission convergence not executed.

#### GROUP-007 — Remove and rapidly re-add a member; stale keys, messages and actions stay fenced

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Remove and rapidly re-add same member.
2. Deliver delayed old key/config/content/reaction.
3. Allow only current entitlement and preserve unrelated members.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Remove and rapidly re-add a member; stale keys, messages and actions stay fenced

**Inspected test evidence**

- [test/features/groups/integration/group_membership_smoke_test.dart](../../test/features/groups/integration/group_membership_smoke_test.dart) — `GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_membership_smoke_test.dart:5212: Production membership/send/listener policies reject removed-window traffic and admit post-readd current epoch in fake network. restartWithPersistedState at test/shared/fakes/group_test_user.dart:979 reuses in-memory repositories; not a disk/process restart. Registered: affected-groups, host-all.
- [integration_test/scripts/run_production_group_gm007.dart](../../integration_test/scripts/run_production_group_gm007.dart) — `production.group_catalog.gm007` (sims).
  - Real: production app UI flows and real transport/database observations; exact run/role/message membership criteria.
  - Faked: disposable test identities and catalog fixture/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_group_gm007.dart:6: main:6 observes pre-removal text, excluded-window texts, removal rotation, re-add and allowed new text. Explicit catch-up drain:57 means this is not purely natural recovery. Capability is registered in tool/sims/critical_features.json; source audited, no campaign executed. Registered: production.group_catalog.gm007.
- [test/features/groups/integration/group_reaction_roundtrip_test.dart](../../test/features/groups/integration/group_reaction_roundtrip_test.dart) — `PL-010 removed member reaction is ignored by Alice and Bob without visible mutation` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_reaction_roundtrip_test.dart:214: Removed member reaction is ignored by both current peers without visible mutation; fake wire/bridge, not OS delivery. Registered: affected-groups, host-all.

**Remaining gaps**

- Broad fake-network stale-event tests and real production text-window campaign are substantive; actual delayed key/media/reaction composition across all native peers remains separate/unrun.

#### GROUP-008 — Leave a group offline; retry a stuck leave without reappearing as an active member

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Leave while offline/native leave ambiguous.
2. Recreate app, inspect durable read-only intent and retry.
3. Ensure no repeated notice/rotation or active membership resurrection.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: leave egress unavailable; app state: foreground; input: as described; recovery: durable exact-intent retry.

**Expected:** Leave a group offline; retry a stuck leave without reappearing as an active member

**Inspected test evidence**

- [test/features/groups/application/group_exit_intent_runner_test.dart](../../test/features/groups/application/group_exit_intent_runner_test.dart) — `PB264-09 real SQLite prepare and completion faults roll back atomically and restart reuses the durable signature` (unit).
  - Real: production exit runner and real FFI SQLite transactions.
  - Faked: controlled signing/native leave/network callbacks; injected SQL faults.
  - Proves / registration: test/features/groups/application/group_exit_intent_runner_test.dart:1528: Real SQL transactions roll back prepare/completion faults and recreate runner reusing durable signature. Native leave, signing and network injected; no actual OS process/radio loss. Registered: affected-groups, host-all.
- [test/features/groups/application/group_exit_intent_runner_test.dart](../../test/features/groups/application/group_exit_intent_runner_test.dart) — `PB264-10 native ambiguity retries only native after process recreation` (unit).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/application/group_exit_intent_runner_test.dart:1902: Recreated runner at native-leave-pending retries native only; never prepares/rebroadcasts/rotates again. Repositories are modeled; no native leave executed. Registered: affected-groups, host-all.

**Remaining gaps**

- SQL transaction faults/recreated runner and native-only retry proven separately. Actual offline/native bridge/process-loss composition and UI recovery are not run.

#### GROUP-009 — Dissolve a group versus delete locally; cancellation and unrelated contacts remain intact

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Cancel then confirm dissolve or local delete.
2. Keep terminal distinction and delete only owned group data.
3. Preserve direct contacts/threads and remaining membership rules.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Dissolve a group versus delete locally; cancellation and unrelated contacts remain intact

**Inspected test evidence**

- [test/features/groups/presentation/group_info_wired_test.dart](../../test/features/groups/presentation/group_info_wired_test.dart) — `Group Info asks before leaving and Cancel keeps the group` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: in-memory repositories and fake native/network bridge.
  - Proves / registration: test/features/groups/presentation/group_info_wired_test.dart:6045: Cancel preserves group/route; confirms pre-action behavior through actual Info route with fake backend. Registered: affected-groups, host-all.
- [test/features/groups/presentation/group_info_wired_test.dart](../../test/features/groups/presentation/group_info_wired_test.dart) — `canceling dissolved local delete keeps the group state and route intact` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: in-memory repositories and fake bridge.
  - Proves / registration: test/features/groups/presentation/group_info_wired_test.dart:7393: Cancelled local delete preserves dissolved group and route; no delete side effect. Registered: affected-groups, host-all.
- [test/features/groups/application/group_exit_intent_runner_test.dart](../../test/features/groups/application/group_exit_intent_runner_test.dart) — `PB264-09 real SQLite prepare and completion faults roll back atomically and restart reuses the durable signature` (unit).
  - Real: production exit runner and real FFI SQLite transactions.
  - Faked: controlled signing/native leave/network callbacks; injected SQL faults.
  - Proves / registration: test/features/groups/application/group_exit_intent_runner_test.dart:1528: Real SQL transactions roll back prepare/completion faults and recreate runner reusing durable signature. Native leave, signing and network injected; no actual OS process/radio loss. Registered: affected-groups, host-all.

**Remaining gaps**

- Cancellation and durable exit policy covered with fake native/network. Full production delete-preserves-friends campaign is registered; this audit has not run it or joined dissolve, local delete and device history checks.

#### GROUP-010 — Archive/unarchive a group without changing membership or message custody

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Archive group.
2. Receive allowed message while archived.
3. Unarchive/reopen and inspect history/custody/membership.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Archive/unarchive a group without changing membership or message custody

**Inspected test evidence**

- [test/features/groups/application/archive_group_use_case_test.dart](../../test/features/groups/application/archive_group_use_case_test.dart) — `calls groupRepo.archiveGroup(groupId) successfully` (unit).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: recording group repository.
  - Proves / registration: test/features/groups/application/archive_group_use_case_test.dart:15: Only delegates archive to recording repository; no history/custody/membership reopen assertion. Registered: affected-groups, host-all.

**Remaining gaps**

- Selected archive unit only verifies repository delegation; no joined archive-to-message-to-unarchive/reopen membership/custody assertion found.

**Open questions**

- Confirm which current home surface exposes group archive/unarchive and how new incoming messages affect archived state.

#### GROUP-011 — Mute/unmute a group; preserve unread and obey settings across restart

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Mute group, restart and receive text/reaction.
2. Keep delivery/unread while suppressing permitted notification/badge.
3. Unmute and verify later eligible notification.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Mute/unmute a group; preserve unread and obey settings across restart

**Inspected test evidence**

- [test/features/groups/integration/group_membership_smoke_test.dart](../../test/features/groups/integration/group_membership_smoke_test.dart) — `UP-011 muted group keeps delivery unread and suppresses notifications through churn` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_membership_smoke_test.dart:10410: Mute survives modeled churn while incoming rows/unread remain and fake notifications are suppressed; actual SQL reopen/native provider card not proved. Registered: affected-groups, host-all.

**Remaining gaps**

- Model keeps rows/unread through churn but restart shares in-memory stores; actual SQL reopen, OS card/badge and unmute control are separate registered notification campaigns, not run.

#### GROUP-012 — Group voice recording cancellation, permissions and recipient playback

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Record voice, cancel or lose membership during recording.
2. Deny/grant microphone and send allowed voice.
3. Every authorized recipient opens and plays received voice.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Group voice recording cancellation, permissions and recipient playback

**Inspected test evidence**

- [test/features/groups/presentation/group_conversation_wired_test.dart](../../test/features/groups/presentation/group_conversation_wired_test.dart) — `losing write access cancels an active recording` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeVoiceRecorderService; fake group bridge and in-memory repositories.
  - Proves / registration: test/features/groups/presentation/group_conversation_wired_test.dart:19281: Dissolve while recording cancels recorder exactly once and returns idle. Fake recorder; no microphone/permission/native capture. Registered: affected-groups, host-all.
- [test/features/groups/presentation/group_conversation_wired_test.dart](../../test/features/groups/presentation/group_conversation_wired_test.dart) — `group recorder auto-stop preserves the capture file sends nothing and exposes no review controls` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: fake recorder output/duration and fake bridge; in-memory repositories.
  - Proves / registration: test/features/groups/presentation/group_conversation_wired_test.dart:19577: At modeled five-minute auto-stop, real4-byte temporary capture remains, no publish/parent and no review controls. Synthetic file is not playable voice. Registered: affected-groups, host-all.

**Remaining gaps**

- Actual recorder/microphone/permission and recipient playback absent from these wired fake-recorder cases; auto-stop file is4 synthetic bytes. Group media fanout alone is not native playback.

#### GROUP-013 — Group send fails terminally: retry/delete actions reflect actual stored state

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Persist terminal or retryable failed text/media.
2. Reopen bubble and inspect Retry/Delete.
3. Retry original identity only where stored retry authority exists.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Group send fails terminally: retry/delete actions reflect actual stored state

**Inspected test evidence**

- [test/features/groups/presentation/group_conversation_wired_test.dart](../../test/features/groups/presentation/group_conversation_wired_test.dart) — `retry-exhausted send_failed WITH a retry payload still shows Retry in a writable group (payload-gate non-regression)` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: fake bridge and in-memory group/message repositories.
  - Proves / registration: test/features/groups/presentation/group_conversation_wired_test.dart:6831: Persisted retry payload keeps Retry on failed bubble in writable group; terminal/no-payload cases nearby discriminate truthful controls. No actual network retry. Registered: affected-groups, host-all.
- [test/features/groups/presentation/group_conversation_wired_test.dart](../../test/features/groups/presentation/group_conversation_wired_test.dart) — `message load failure shows retryable error instead of empty conversation` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FailingInitialPageGroupMessageRepository; fake bridge/identity.
  - Proves / registration: test/features/groups/presentation/group_conversation_wired_test.dart:9434: Actual load-failure UI differs from empty state, retry invokes repository again and recovered row renders; failure-injecting in-memory repository. Registered: affected-groups, host-all.

**Remaining gaps**

- Real wired UI checks stored retry payload distinction using fake stores/bridge; actual persisted reopen/network recovery and delete isolation are separate.

#### GROUP-014 — Load group message history with pagination, older content expiry and retry after load failure

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open older paged history.
2. Fail initial/next page and retry.
3. Show retention-expired versus recoverable gap distinctly and preserve scroll.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Load group message history with pagination, older content expiry and retry after load failure

**Inspected test evidence**

- [test/features/groups/presentation/group_conversation_wired_test.dart](../../test/features/groups/presentation/group_conversation_wired_test.dart) — `message load failure shows retryable error instead of empty conversation` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FailingInitialPageGroupMessageRepository; fake bridge/identity.
  - Proves / registration: test/features/groups/presentation/group_conversation_wired_test.dart:9434: Actual load-failure UI differs from empty state, retry invokes repository again and recovered row renders; failure-injecting in-memory repository. Registered: affected-groups, host-all.
- [test/features/groups/integration/group_resume_recovery_test.dart](../../test/features/groups/integration/group_resume_recovery_test.dart) — `PREREQ-HISTORY-GAP-REPAIR fake-network repair rejects bad source then restores range before live delivery` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_resume_recovery_test.dart:1754: Bad source rejected then range repair precedes live delivery; source/key/hash and source identity assertions are real policy with fake wire and stores. Registered: affected-groups, host-all.

**Remaining gaps**

- Initial retry UI and fake-network gap repair causal; next-page failure/retention/actual long history scroll plus SQL reopen not joined in one journey.

#### GROUP-015 — Group reply/reaction overlay, copy and message-sender navigation use the correct target

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Long press exact message.
2. Reply/react/copy and open exact sender context.
3. Dismiss and retain correct quote/identity and scroll target.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Group reply/reaction overlay, copy and message-sender navigation use the correct target

**Inspected test evidence**

- [test/features/groups/presentation/group_conversation_screen_test.dart](../../test/features/groups/presentation/group_conversation_screen_test.dart) — `long-press copy action copies exact text and dismisses once` (widget).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: supplied messages/callbacks; mock SystemChannels.platform clipboard/haptics.
  - Proves / registration: test/features/groups/presentation/group_conversation_screen_test.dart:1103: Long press copies exact multiline/emoji text once, dismisses overlay and shows quiet confirmation; platform clipboard mocked. Registered: affected-groups, host-all, ui-tap-gestures.
- [test/features/groups/integration/group_new_member_onboarding_test.dart](../../test/features/groups/integration/group_new_member_onboarding_test.dart) — `quoted reply to pre-join parent keeps missing-parent fallback for new member` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_new_member_onboarding_test.dart:1148: New member retains quote identity but receives unavailable-parent fallback, with no pre-join row disclosure; fake byte/transport harness. Registered: affected-groups, host-all.
- [test/features/groups/integration/group_reaction_roundtrip_test.dart](../../test/features/groups/integration/group_reaction_roundtrip_test.dart) — `PL-010 removed member reaction is ignored by Alice and Bob without visible mutation` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_reaction_roundtrip_test.dart:214: Removed member reaction is ignored by both current peers without visible mutation; fake wire/bridge, not OS delivery. Registered: affected-groups, host-all.

**Remaining gaps**

- Exact copy and overlay dismissal plus quote/reaction boundaries exist; clipboard/platform mocked and sender-navigation target not included in the cited joined flow.

#### GROUP-016 — Reject forged membership/admin/config/reaction events without wedging subsequent valid input

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Inject forged/invalid/stale membership/admin/config/reaction.
2. Verify no authority/content mutation.
3. Deliver legitimate subsequent event and remain usable.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Reject forged membership/admin/config/reaction events without wedging subsequent valid input

**Inspected test evidence**

- [test/features/groups/integration/group_membership_smoke_test.dart](../../test/features/groups/integration/group_membership_smoke_test.dart) — `SV-009 malformed member keys never activate and later valid add still syncs` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_membership_smoke_test.dart:2021: Malformed member keys cannot activate, then valid add syncs. Adjacent non-admin/config forgery cases use fake signature bridge; no genuine cryptographic unforgeability proof. Registered: affected-groups, host-all.
- [test/features/groups/integration/group_reaction_roundtrip_test.dart](../../test/features/groups/integration/group_reaction_roundtrip_test.dart) — `PL-010 removed member reaction is ignored by Alice and Bob without visible mutation` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_reaction_roundtrip_test.dart:214: Removed member reaction is ignored by both current peers without visible mutation; fake wire/bridge, not OS delivery. Registered: affected-groups, host-all.
- [test/features/groups/integration/group_membership_smoke_test.dart](../../test/features/groups/integration/group_membership_smoke_test.dart) — `GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic` (integration).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/integration/group_membership_smoke_test.dart:5212: Production membership/send/listener policies reject removed-window traffic and admit post-readd current epoch in fake network. restartWithPersistedState at test/shared/fakes/group_test_user.dart:979 reuses in-memory repositories; not a disk/process restart. Registered: affected-groups, host-all.

**Remaining gaps**

- Actual validation/entitlement and recovery policy tested; FakeBridge signature/crypto accepts fixtures, so genuine signed network unforgeability needs native/Go boundaries and production integration.

#### GROUP-017 — Optional rotate-on-add cohort separates new-member access from prior epochs

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Build optional rotate-on-add cohort.
2. Add member and advance/distribute key.
3. Reject prior-epoch content for joiner while preserving current members.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: MKNOON_ENABLE_FORWARD_ROTATE_ON_ADD=true; defaultOFF comparison; recovery: n/a.

**Expected:** Opted-in rotation changes epoch and key authority; default cohort retains established behavior.

**Inspected test evidence**

- [test/features/groups/application/add_group_member_use_case_test.dart](../../test/features/groups/application/add_group_member_use_case_test.dart) — `B5: forward rotation fires on add when opted in by the creator` (unit).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeBridge keygen/signing/config/network; in-memory groups.
  - Proves / registration: test/features/groups/application/add_group_member_use_case_test.dart:182: Opted-in add calls generateNextKey and stores new member; does not assert real key secrecy or an old ciphertext fails decryption at recipient. Registered: affected-groups, host-all.
- [test/features/groups/application/add_group_member_use_case_test.dart](../../test/features/groups/application/add_group_member_use_case_test.dart) — `B5: default add does NOT rotate (non-breaking)` (unit).
  - Real: production group use cases/listeners and entitlement/replay policy.
  - Faked: FakeGroupPubSubNetwork/in-memory repositories; FakeBridge signatures, encryption, keys and native transport.
  - Proves / registration: test/features/groups/application/add_group_member_use_case_test.dart:209: Default add creates member without key rotation; lib/core/config/forward_rotate_on_add_flag.dart:6 defaultOFF build flag. No default-on forward-secrecy claim. Registered: affected-groups, host-all.

**Remaining gaps**

- DefaultOFF flag at lib/core/config/forward_rotate_on_add_flag.dart:6; unit proves keygen command only. Actual prior ciphertext inaccessible/current members readable and signed cohort rollback are not asserted.

### CALL — Voice calls, lifecycle, privacy and history

#### VC-001 — Android calls connect, exchange audio and end cleanly

**Coverage:** strong. **Execution:** not_run. **Catalog:** VC-001.

**Steps**

1. Start production call.
2. Answer native surface, observe both RTP directions and exercise mute/speaker.
3. Emulator hangs up; verify both surfaces/native ownership clear.

**Conditions:** platform: available Android physical+emulator; campaign source only; connectivity: disposable local relay/coturn; offline: n/a; app state: foreground; input: fresh mutual contacts/audio call; recovery: n/a.

**Expected:** Real app call start and native answer establish bidirectional RTP; mute and speaker controls are exercised, and emulator-initiated hangup releases both endpoints.

**Inspected test evidence**

- [integration_test/scripts/android_production_audio_call_campaign.dart](../../integration_test/scripts/android_production_audio_call_campaign.dart) — `android.production_1to1_audio_call` (sims).
  - Real: production app semantic start/native answer and real Android WebRTC RTP; same APK; physical Android+emulator; exact call-bound observers; actual native cleanup and bounded evidence validation.
  - Faked: disposable local relay/coturn and fresh contacts; separate host Pion known-Opus oracle; this does not substitute for app RTP.
  - Proves / registration: integration_test/scripts/android_production_audio_call_campaign.dart:539: executeAndroidProductionAudioCallCampaign exercises mute/speaker/emulator hangup and verifies both native calls released. integration_test/support/android_production_audio_call_evidence.dart:448 requires all controls, :465 cleanup, :487 both app RTP directions plus independent Pion fixture. Registered android.production_1to1_audio_call; no human audibility/content fidelity claim or run here. Registered: see cited native runner/manifest.

**Remaining gaps**

- Campaign source establishes the requested Android/RTP/control/cleanup boundary. Not run here; independent Pion audio oracle is host-side and app RTP is not human audibility or content fidelity.

#### VC-002 — Calls use the expected ringing time limits

**Coverage:** strong. **Execution:** not_run. **Catalog:** VC-002.

**Steps**

1. Establish authenticated call.
2. Capture actual signed invite and scheduled canonical timers.
3. Compare exact TTL/origins and measured wire-versus-delivery gap.

**Conditions:** platform: available Android physical+emulator; campaign source only; connectivity: disposable local relay/coturn; offline: n/a; app state: foreground; input: fresh mutual contacts/audio call; recovery: n/a.

**Expected:** On an established call, encoded signed invites and scheduled timers satisfy the configured TTL, invite-expiry and no-answer timing contract.

**Inspected test evidence**

- [integration_test/scripts/run_production_call_regression.dart](../../integration_test/scripts/run_production_call_regression.dart) — `kx0001` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_regression.dart:8: production_call_surface_regressions.dart:557 reads actual post-sign wire/timer observations. production_call_regression_criteria.dart:202 checks40s signedTTL,45s invite-expiry origin,30s no-answer timer and measured wire/deadline gap. Does not wait for an actual unanswered/offline call. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0001, kx0002, kx0003, kx0015, kx0016, kx0017, kx0029, kx0030.
- [test/features/call/application/call_coordinator_test.dart](../../test/features/call/application/call_coordinator_test.dart) — `injected 30 second no-answer timer terminates the call` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_coordinator_test.dart:695: Fake-time30s no-answer dispatch yields terminal state; expired/cancelled timer tests fence stale callback. Not actual offline/push scheduling. Registered: affected-calls, host-all.

**Remaining gaps**

- Actual runtime deadline campaign plus causal host timer; no run here and no delayed/offline incoming-admission claim.

#### VC-003 — A call keeps going when either person leaves the app and comes back

**Coverage:** strong. **Execution:** not_run. **Catalog:** VC-003.

**Steps**

1. Connect call.
2. Minimize caller and callee separately.
3. Check quiet ongoing replaces ringing and native tap returns same connected call.

**Conditions:** platform: available Android physical+emulator; campaign source only; connectivity: disposable local relay/coturn; offline: n/a; app state: foreground; input: fresh mutual contacts/audio call; recovery: n/a.

**Expected:** Caller and callee each keep the same active call after minimization; the quiet ongoing card replaces ringing in the correct order and opens that same call.

**Inspected test evidence**

- [integration_test/scripts/run_production_call_regression.dart](../../integration_test/scripts/run_production_call_regression.dart) — `kx0002` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_regression.dart:8: production_call_surface_regressions.dart:291 minimizes/returns via ongoing-card tap; production_call_regression_criteria.dart:398 checks same connected pair/card at all stages, quiet channel and native key. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0001, kx0002, kx0003, kx0015, kx0016, kx0017, kx0029, kx0030.
- [integration_test/scripts/run_production_call_regression.dart](../../integration_test/scripts/run_production_call_regression.dart) — `kx0003` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_regression.dart:8: Same production minimize/return for callee; additionally actual notification publication/event order ensures ongoing foreground before ringing removal. Criteria production_call_regression_criteria.dart:398+; no iOS parity claim. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0001, kx0002, kx0003, kx0015, kx0016, kx0017, kx0029, kx0030.
- [android/app/src/test/kotlin/com/mknoon/app/call/MknoonCallOngoingNotificationHandoverTest.kt](../../android/app/src/test/kotlin/com/mknoon/app/call/MknoonCallOngoingNotificationHandoverTest.kt) — `ongoing notification takes the foreground before the ringing heads-up is cancelled` (unit).
  - Real: actual Kotlin handOverToOngoingCallNotification helper.
  - Faked: recording startForeground/cancel callbacks.
  - Proves / registration: android/app/src/test/kotlin/com/mknoon/app/call/MknoonCallOngoingNotificationHandoverTest.kt:10: Exact startForeground505 then cancel504 ordering; companion refusal keeps ringing card. Third case:46 is source-text wiring assertion only. Registered android-call-native / native.android.unit; no actual OS card by this unit. Registered: see cited native runner/manifest.

**Remaining gaps**

- Registered Android campaign checks current-call/native notification handover with positive observations. Not run; iOS lifecycle is VC-009.

#### VC-004 — Call screens show contact names, never hidden IDs

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-004.

**Steps**

1. Show incoming/active/native call surfaces.
2. Resolve current contact name or safe fallback.
3. Reject raw transport/account identifiers in displayed names.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Incoming and active in-app call surfaces and native notifications show the contact name or safe fallback without exposing a raw peer identifier.

**Inspected test evidence**

- [integration_test/scripts/run_production_call_regression.dart](../../integration_test/scripts/run_production_call_regression.dart) — `kx0016` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_regression.dart:8: production_call_regression_criteria.dart:362 checks authenticated incoming and ongoing name hashes, no peer ID and exact current contact binding; companion kx0015 incoming and kx0017 raw-ID-name safe fallback cases registered. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0001, kx0002, kx0003, kx0015, kx0016, kx0017, kx0029, kx0030.
- [test/features/call/presentation/foreground_call_overlay_test.dart](../../test/features/call/presentation/foreground_call_overlay_test.dart) — `unresolved UI fallback never becomes native caller metadata` (widget).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/presentation/foreground_call_overlay_test.dart:163: Unresolved UI fallback cannot enter authenticated native name projection; fake contact lookup/capability, real overlay policy. Registered: affected-calls, host-all, ui-approved-recovery-readability.
- [ios/RunnerTests/OpaqueCallContactResolverTests.swift](../../ios/RunnerTests/OpaqueCallContactResolverTests.swift) — `testOnlyVerifiedOpaqueMappingCanSupplyDisplayName` (unit).
  - Real: actual Swift opaque-contact resolver and canonical handle/name validation.
  - Faked: MemoryOpaqueContactBackend/clock.
  - Proves / registration: ios/RunnerTests/OpaqueCallContactResolverTests.swift:17: Verified mapping supplies trimmed readable name; malformed/multiline name update rejected. Companion unknown mapping generic fallback:9 and revoke:48. Registered native.ios.runner_tests complete RunnerTests target; does not display real system CallKit UI. Registered: see cited native runner/manifest.

**Remaining gaps**

- Substantive Android native card/name campaigns plus host overlay/Swift resolver; actual iOS system CallKit display and all platform surfaces remain unexecuted/separate.

#### VC-005 — Calling back from a missed call reaches the right person

**Coverage:** strong. **Execution:** not_run. **Catalog:** VC-005.

**Steps**

1. Create two missed-call callbacks and kill owned process.
2. Submit A then B while readiness/lock holds.
3. Release readiness/unlock and admit only newest B.

**Conditions:** platform: available Android physical+emulator; campaign source only; connectivity: disposable local relay/coturn; offline: n/a; app state: foreground; input: fresh mutual contacts/audio call; recovery: n/a.

**Expected:** After process death or while locked, successive missed-call callback requests coalesce to the latest selected contact; no dialing occurs while locked and only that contact starts dialing after unlock.

**Inspected test evidence**

- [integration_test/scripts/run_production_call_back.dart](../../integration_test/scripts/run_production_call_back.dart) — `kx0005` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_back.dart:8: production_call_back_criteria.dart:277 requires verified owned-process death, actual A then B callback submissions before readiness release, one fresh outgoing call to B only. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0005, kx0006, kx0007, kx0008.
- [integration_test/scripts/run_production_call_back.dart](../../integration_test/scripts/run_production_call_back.dart) — `kx0006` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_back.dart:8: production_call_back_criteria.dart:308 checks actual credential-free emulator keyguard remains locked without dialing, then real unlock admits latest B; keyguard restored. Not a credentialed physical lock-screen bypass proof. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0005, kx0006, kx0007, kx0008.
- [test/features/call/application/call_redial_controller_test.dart](../../test/features/call/application/call_redial_controller_test.dart) — `new callback supersedes A at $stage before canonical admission` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_redial_controller_test.dart:288: Seven async stages parameterize cancellation/supersession; latest history/contact/preflight bound before canonical admission. Controlled readiness/history/endpoint/gateway ports. Registered: affected-calls, call-signaling, host-all.

**Remaining gaps**

- Real Android callback/keyguard campaigns cover current source contract on credential-free emulator; not run, no credentialed physical unlock claim.

#### VC-006 — Calling back when busy or without microphone access fails clearly

**Coverage:** strong. **Execution:** not_run. **Catalog:** VC-006.

**Steps**

1. Callback while active call busy.
2. Callback with microphone denied.
3. Observe feedback, preserved original call or zero new native capture.

**Conditions:** platform: available Android physical+emulator; campaign source only; connectivity: disposable local relay/coturn; offline: n/a; app state: foreground; input: fresh mutual contacts/audio call; recovery: n/a.

**Expected:** A busy callback shows feedback while preserving the existing call and audio; a microphone-denied callback shows feedback without creating a call or owning recorder clients.

**Inspected test evidence**

- [integration_test/scripts/run_production_call_back.dart](../../integration_test/scripts/run_production_call_back.dart) — `kx0007` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_back.dart:8: production_call_back_criteria.dart:321 requires actual busy callback result/visible unavailable feedback while original call, connection and enabled audio survive. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0005, kx0006, kx0007, kx0008.
- [integration_test/scripts/run_production_call_back.dart](../../integration_test/scripts/run_production_call_back.dart) — `kx0008` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_back.dart:8: production_call_back_criteria.dart:335 requires microphoneDenied, no connection/current call and real positive-to-zero owned AudioRecord client control from bounded OS dump, plus feedback. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0005, kx0006, kx0007, kx0008.

**Remaining gaps**

- Actual Android current-call and positive-to-zero capture evidence required by registered campaigns. No campaign run here.

#### VC-007 — Speaker turns on and switches back to an available audio output

**Coverage:** strong. **Execution:** not_run. **Catalog:** VC-007.

**Steps**

1. Open route picker during active call.
2. Compare native inventory; select speaker.
3. Return to source-defined available fallback and retain same call.

**Conditions:** platform: available Android physical+emulator; campaign source only; connectivity: disposable local relay/coturn; offline: n/a; app state: foreground; input: fresh mutual contacts/audio call; recovery: n/a.

**Expected:** The route picker matches the actual output inventory, selects speaker and returns to one supported source-defined fallback while retaining the call.

**Inspected test evidence**

- [integration_test/scripts/run_production_call_regression.dart](../../integration_test/scripts/run_production_call_regression.dart) — `kx0029` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_regression.dart:8: production_call_surface_regressions.dart:339 compares actual coarse inventory/UI, selects speaker then source-defined available fallback; production_call_regression_criteria.dart:265 validates actual provider equality and same active call. Absent wired/Bluetooth explicitly unavailable; no acoustic/accessory attach proof. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0001, kx0002, kx0003, kx0015, kx0016, kx0017, kx0029, kx0030.
- [test/features/call/presentation/call_audio_output_picker_test.dart](../../test/features/call/presentation/call_audio_output_picker_test.dart) — `hot-plug refresh observes fallback and disposal discards a late inventory` (widget).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/presentation/call_audio_output_picker_test.dart:86: Injected output inventory hot-plug refresh observes fallback and ignores late disposed inventory; native hot-plug event/accessory acoustic outcome absent. Registered: affected-calls, call-signaling, host-all.

**Remaining gaps**

- Campaign only claims actually available outputs. Acoustic correctness and attaching absent hardware are outside this bounded route-inventory journey; not run.

#### VC-008 — The always-relay setting turns on and off and is remembered

**Coverage:** strong. **Execution:** not_run. **Catalog:** VC-008.

**Steps**

1. Toggle always-relay setting on/off.
2. Read saved value and privacy copy.
3. Relaunch, restore original choice.

**Conditions:** platform: available Android physical+emulator; campaign source only; connectivity: disposable local relay/coturn; offline: n/a; app state: foreground; input: fresh mutual contacts/audio call; recovery: n/a.

**Expected:** The always-relay call setting can be enabled and disabled, reads back correctly and presents the expected privacy copy.

**Inspected test evidence**

- [integration_test/scripts/run_production_call_regression.dart](../../integration_test/scripts/run_production_call_regression.dart) — `kx0030` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_regression.dart:8: production_call_surface_regressions.dart:482 explicitly scopes saved preference/copy only; reads saved boolean, toggles, relaunches/restores. Forced-relay campaign build cannot prove causal network change from this toggle. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0001, kx0002, kx0003, kx0015, kx0016, kx0017, kx0029, kx0030.

**Remaining gaps**

- Saved choice/copy/relaunch campaign is a sufficient scoped test, unexecuted here. Network causality is tracked separately in VC-023.

#### VC-009 — An iPhone call keeps going when you leave the app

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-009.

**Steps**

1. Connect actual iPhone call.
2. Minimize and return.
3. Retain same call and working audio.

**Conditions:** platform: available actual iPhone for OS-specific boundary; connectivity: n/a; offline: n/a; app state: background/resume; input: as described; recovery: n/a.

**Expected:** On a real iPhone, minimizing an active call and returning preserves the same call and working audio.

**Inspected test evidence**

- [ios/RunnerTests/MknoonCallKitLifecycleTests.swift](../../ios/RunnerTests/MknoonCallKitLifecycleTests.swift) — `testAnswerBeforeFlutterPersistsAndReplaysOnceInOrder` (unit).
  - Real: actual Swift native event/journal/controller ordering.
  - Faked: makeRig fake CallKit provider/audio and pending-call backend.
  - Proves / registration: ios/RunnerTests/MknoonCallKitLifecycleTests.swift:569: Answer before Flutter records replay once/in order; adjacent decline/end/reset/terminal races exercise ownership through fake provider. Registered native.ios.runner_tests, not actual system surface/audio. Registered: see cited native runner/manifest.
- [ios/RunnerTests/MknoonCallKitLifecycleTests.swift](../../ios/RunnerTests/MknoonCallKitLifecycleTests.swift) — `testRetiredTerminalReceiptDoesNotReleaseSuccessorAudio` (unit).
  - Real: actual Swift lifecycle/store receipt ownership rules.
  - Faked: makeRig MemoryPendingCallBackend; FakeCallProvider/FakeCallAudio and controlled clock.
  - Proves / registration: ios/RunnerTests/MknoonCallKitLifecycleTests.swift:1255: After old receipt retention and successor answer/adoption/activation, two old ACKs leave successor descriptor/audio intact. Registered native.ios.runner_tests; no actual delayed OS callback or audible successor call. Registered: see cited native runner/manifest.

**Remaining gaps**

- Swift lifecycle unit ownership does not establish actual iOS suspension/CallKit/WebRTC audible continuity. kx0009 physical campaign is registered inactive/automationReady=false; it is not passing coverage.

#### VC-010 — iPhone call screens show the caller's name safely

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-010.

**Steps**

1. Receive actual iPhone call.
2. Inspect system incoming name/handle privacy.
3. Use safe fallback for unknown or untrusted mapping.

**Conditions:** platform: iOS system CallKit UI; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** The iPhone system incoming-call surface shows the contact name or the source-defined safe fallback, without a raw peer identifier or inappropriate system handle disclosure.

**Inspected test evidence**

- [ios/RunnerTests/OpaqueCallContactResolverTests.swift](../../ios/RunnerTests/OpaqueCallContactResolverTests.swift) — `testOnlyVerifiedOpaqueMappingCanSupplyDisplayName` (unit).
  - Real: actual Swift opaque-contact resolver and canonical handle/name validation.
  - Faked: MemoryOpaqueContactBackend/clock.
  - Proves / registration: ios/RunnerTests/OpaqueCallContactResolverTests.swift:17: Verified mapping supplies trimmed readable name; malformed/multiline name update rejected. Companion unknown mapping generic fallback:9 and revoke:48. Registered native.ios.runner_tests complete RunnerTests target; does not display real system CallKit UI. Registered: see cited native runner/manifest.
- [test/features/call/presentation/foreground_call_overlay_test.dart](../../test/features/call/presentation/foreground_call_overlay_test.dart) — `unresolved UI fallback never becomes native caller metadata` (widget).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/presentation/foreground_call_overlay_test.dart:163: Unresolved UI fallback cannot enter authenticated native name projection; fake contact lookup/capability, real overlay policy. Registered: affected-calls, host-all, ui-approved-recovery-readability.

**Remaining gaps**

- Resolver/native bridge tests do not inspect real iOS system call UI/provider display. kx0004 physical fixture is inactive, not proof.

#### VC-011 — An old call on the iPhone cannot disturb a new one

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-011.

**Steps**

1. Terminate old call and retain terminal receipt.
2. Answer/adopt new call after retention.
3. Deliver old ACK/event twice and preserve current owner/audio.

**Conditions:** platform: iOS lifecycle; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: old terminal receipt against current successor.

**Expected:** Delayed events and retained terminal receipts from an earlier call cannot take audio, release resources or change ownership of the current call.

**Inspected test evidence**

- [ios/RunnerTests/MknoonCallKitLifecycleTests.swift](../../ios/RunnerTests/MknoonCallKitLifecycleTests.swift) — `testRetiredTerminalReceiptDoesNotReleaseSuccessorAudio` (unit).
  - Real: actual Swift lifecycle/store receipt ownership rules.
  - Faked: makeRig MemoryPendingCallBackend; FakeCallProvider/FakeCallAudio and controlled clock.
  - Proves / registration: ios/RunnerTests/MknoonCallKitLifecycleTests.swift:1255: After old receipt retention and successor answer/adoption/activation, two old ACKs leave successor descriptor/audio intact. Registered native.ios.runner_tests; no actual delayed OS callback or audible successor call. Registered: see cited native runner/manifest.

**Remaining gaps**

- Swift fake-provider ownership test is exact and causal; actual late OS event/current audible call and Dart/native joined presentation remain separate/unrun.

#### VC-012 — A muted call stays connected and keeps exchanging audio

**Coverage:** strong. **Execution:** not_run. **Catalog:** VC-012.

**Steps**

1. Accept foreground call with permission.
2. Mute both endpoints and reach structural readiness.
3. Observe both RTP directions and canonical cleanup.

**Conditions:** platform: Android available pair; connectivity: n/a; offline: n/a; app state: foreground; permission granted; input: as described; recovery: n/a.

**Expected:** A foreground accepted Android call with granted permission reaches structural media readiness and carries RTP in both directions while both endpoints are muted, using canonical signaling and cleanup.

**Inspected test evidence**

- [integration_test/scripts/android_foreground_webrtc_audio_campaign.dart](../../integration_test/scripts/android_foreground_webrtc_audio_campaign.dart) — `android.foreground_webrtc_audio` (sims).
  - Real: native Android WebRTC engines and canonical secure signaling/cleanup; bidirectional RTP/readiness observations under both-muted controls.
  - Faked: dedicated foreground harness/permission-pregranted fixture; host rendezvous forwards secure envelope and fixed barriers.
  - Proves / registration: integration_test/scripts/android_foreground_webrtc_audio_campaign.dart:206: Registered foreground media campaign; :24 enumerates both-muted barriers, evidence android_foreground_webrtc_audio_evidence.dart:1522 validates directional RTP. This is canonical foreground harness, not every production UI/OS lifecycle nor semantic microphone-content leakage proof. Not executed. Registered: see cited native runner/manifest.
- [test/features/call/integration/muted_call_connection_decisions_test.dart](../../test/features/call/integration/muted_call_connection_decisions_test.dart) — `VC-012 host two-peer mute preserves connected receive ownership (mute before ready=$muteBeforeReady)` (integration).
  - Real: production two-endpoint signaling/controller/engine composition; FFI SQLite history.
  - Faked: native WebRTC/permission/audio session; deterministic crypto/transport/roster fixtures.
  - Proves / registration: test/features/call/integration/muted_call_connection_decisions_test.dart:66: Two host endpoints retain receive/connected ownership when muted before/after ready; actual RTP is expressly separate. Registered: affected-calls, host-all.

**Remaining gaps**

- Registered actual foreground WebRTC campaign supplies RTP separate from host decisions, but no run here. Muted RTP does not establish microphone-content suppression.

#### VC-013 — A relayed call can later switch to a direct connection safely

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-013.

**Steps**

1. Only if relay-to-direct upgrade becomes active, establish relayed call.
2. Attempt supported upgrade and negative symmetric-NAT case.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** If the future upgrade capability ships, a relayed call moves to direct transport when supported and stays relayed when the attempted upgrade cannot succeed.

**Inspected test evidence**

- [test/features/call/integration/call_turn_policy_test.dart](../../test/features/call/integration/call_turn_policy_test.dart) — `VC-013 selected relay-to-direct media path preserves both call owners` (integration).
  - Real: CallCoordinator, CallNegotiationEffectExecutor and CallAudioNegotiationPreparer; FlutterWebRtcCallEngine and both call owners.
  - Faked: accepted control/signaling fixtures and native selected-transport/readiness observations; peer connection/media platform seam; no real NAT, RTP or DCUtR initiation.
  - Proves / registration: Both connected call owners preserve identity, session, connectedAt, readiness and state when the selected media path changes; no ICE restart, new connection or premature terminal history. Explicit hangup creates one history row per owner. Fresh host PASS: .codex-test-logs/groupB-fixes/011-vc013-turn.log (33 passed, 0 skipped). Registered broad lanes remain unrun.
- [test/features/call/integration/call_turn_policy_test.dart](../../test/features/call/integration/call_turn_policy_test.dart) — `VC-013 upgrade hint without selected direct media retains both relay calls` (integration).
  - Real: CallCoordinator, CallNegotiationEffectExecutor and CallAudioNegotiationPreparer; FlutterWebRtcCallEngine and both call owners.
  - Faked: accepted control/signaling fixtures and native selected-transport/readiness observations; peer connection/media platform seam; no real NAT, RTP or DCUtR initiation.
  - Proves / registration: A direct-upgrade hint alone cannot relabel native TURN-selected media or end either connected call. Fresh host PASS: .codex-test-logs/groupB-fixes/011-vc013-turn.log. This does not implement or enable the planned upgrade capability.

**Remaining gaps**

- Host owner continuity and advisory-hint negative control pass; actual upgrade initiation, NAT/symmetric-CGNAT behavior, SDP, RTP and native DCUtR remain unproven.
- vc02.dcutr_upgrade and vc02.dcutr_symmetric_cgnat_negative retain automationReady=false. Capability/catalog remain planned and are not current unconditional release gates.

**Open questions**

- When this capability is enabled, define current supported upgrade policy and available transport/topology proof.

#### VC-014 — Incoming calls ring in supported background and locked states

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-014.

**Steps**

1. Suspend/terminate/lock supported app.
2. Deliver incoming call to native system surface.
3. Answer and establish audio once without stale duplicate.

**Conditions:** platform: Android/iOS supported OS states; available targets only; connectivity: n/a; offline: n/a; app state: suspended/process-terminated/locked; input: as described; recovery: n/a.

**Expected:** An incoming call reaches the system call surface in supported suspended, process-terminated and locked states on each shipped platform, and answering establishes audio without stale or duplicate calls.

**Inspected test evidence**

- [test/features/call/application/incoming_call_pre_presentation_admission_test.dart](../../test/features/call/application/incoming_call_pre_presentation_admission_test.dart) — `blocked and unknown authenticated transports reject permanently` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/incoming_call_pre_presentation_admission_test.dart:58: Blocked or unknown authenticated transport permanently rejects before presentation; fixture crypto/roster/network. Does not prove OS PushKit/FCM reception. Registered: affected-calls, host-all.
- [ios/RunnerTests/MknoonCallKitLifecycleTests.swift](../../ios/RunnerTests/MknoonCallKitLifecycleTests.swift) — `testAnswerBeforeFlutterPersistsAndReplaysOnceInOrder` (unit).
  - Real: actual Swift native event/journal/controller ordering.
  - Faked: makeRig fake CallKit provider/audio and pending-call backend.
  - Proves / registration: ios/RunnerTests/MknoonCallKitLifecycleTests.swift:569: Answer before Flutter records replay once/in order; adjacent decline/end/reset/terminal races exercise ownership through fake provider. Registered native.ios.runner_tests, not actual system surface/audio. Registered: see cited native runner/manifest.
- [test/features/call/integration/presentation_refusal_round_trip_test.dart](../../test/features/call/integration/presentation_refusal_round_trip_test.dart) — `a callee whose call surface refuses to ring leaves one missed call and the caller reads "No answer"` (integration).
  - Real: two production coordinators/codec/control executor; actual overlay end-reason rendering.
  - Faked: crypto/roster/transport/history/notification posting and native refusal.
  - Proves / registration: test/features/call/integration/presentation_refusal_round_trip_test.dart:43: Two real coordinators/codec/control executor propagate no_answer, one missed notification/history and caller No answer UI. Header:30 explicitly substitutes crypto, roster, transport write and notification post. Registered: affected-calls, host-all.

**Remaining gaps**

- Headless/presentation admission and native journal tests do not prove actual FCM/PushKit/APNs transport through OS suspended/process-killed states. Required artifact-bound provider/device evidence remains incomplete.

#### VC-015 — iPhone and Android can call each other both ways

**Coverage:** partial. **Execution:** device_run. **Catalog:** VC-015.

**Steps**

1. iPhone calls Android and answers reverse call.
2. Verify intelligible bidirectional audio.
3. End both directions and release resources.

**Conditions:** platform: iPhone 13 and Pixel 6; actual owner-run debug/FLOW-log cross-platform candidate; connectivity: n/a; offline: n/a; app state: foreground; input: actual audio in both call directions; recovery: n/a.

**Expected:** The shipped iPhone and Android candidates each initiate and answer a call with the other platform, exchange audible audio and terminate cleanly.

**Device execution (2026-10-22; flutter_app)**

- Result: **PASS_STRUCTURAL_AUDIO_AND_RTP_UNVERIFIED**.
- Both initiation/answer roles passed structurally on iPhone 13 and Pixel 6. iPhone-to-Pixel incoming was about two seconds, both Connected within eight seconds; reverse incoming about five seconds. Pixel Telecom ACTIVE, playback and mic activity were observed.
- Each answering side ended its call; both UIs ended within five seconds, Pixel Telecom/playback/mic cleaned up, one history row on each side. This is structural call/cleanup evidence, not audibility or native RTP proof.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:47`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:48`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:49`.

**Inspected test evidence**

- [test/features/call/integration/muted_call_connection_decisions_test.dart](../../test/features/call/integration/muted_call_connection_decisions_test.dart) — `VC-015 shared protocol caller A negotiates both owners and callee hangup releases both` (integration).
  - Real: two production CallCoordinators, real envelope codec/router/control/negotiation adapters and FlutterWebRtcCallEngine; SQLite history; both offer/answer directions; callee terminal releases both call/session owners once.
  - Faked: native WebRTC snapshots/SDP/RTP flags, audio-session ownership and crypto primitive; in-process transport queue and trusted endpoint/roster authority; no actual platform or audio.
  - Proves / registration: test/features/call/integration/muted_call_connection_decisions_test.dart:66: Caller A negotiates through reciprocal signaling to two structurally ready connected owners; answerer hangup crosses the envelope path and leaves one native close and correct local/remote terminal history each. Fresh full file: 6 passed, 0 skipped, exit 0 (004-call-roles-summary.json/receipt under .codex-test-logs/astra-groupCD). Registered: affected-calls, host-all.
- [test/features/call/integration/muted_call_connection_decisions_test.dart](../../test/features/call/integration/muted_call_connection_decisions_test.dart) — `VC-015 shared protocol caller B negotiates both owners and callee hangup releases both` (integration).
  - Real: two production CallCoordinators, real envelope codec/router/control/negotiation adapters and FlutterWebRtcCallEngine; SQLite history; both offer/answer directions; callee terminal releases both call/session owners once.
  - Faked: native WebRTC snapshots/SDP/RTP flags, audio-session ownership and crypto primitive; in-process transport queue and trusted endpoint/roster authority; no actual platform or audio.
  - Proves / registration: test/features/call/integration/muted_call_connection_decisions_test.dart:66: Caller B negotiates through reciprocal signaling to two structurally ready connected owners; answerer hangup crosses the envelope path and leaves one native close and correct local/remote terminal history each. Fresh full file: 6 passed, 0 skipped, exit 0 (004-call-roles-summary.json/receipt under .codex-test-logs/astra-groupCD). Registered: affected-calls, host-all.

**Remaining gaps**

- Call setup/answer/end, native activity and cleanup passed structurally; bidirectional audio content/audibility remains unverified without a human or acoustic observer.
- Native call-bound RTP counters were not captured. Connected state and native playback/mic activity do not prove audible media delivery.

**Open questions**

- Runbook: docs/testing/astra-group-c-device-runbook.md. Execution performed by flutter_app, not Astra; existing evidence inspected read-only.
- Result scope, candidate and focused host rechecks are recorded in header.group_c_device_run; remaining manual/content/platform limitations above are not full-journey passes.

#### VC-016 — Declined, cancelled, unanswered and overlapping calls end cleanly

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-016.

**Steps**

1. Decline, cancel before answer and allow actual unanswered/offline timeout.
2. Cross calls or inject unrelated busy invite.
3. Deliver delayed terminal signals, clean and start another call.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Decline, pre-answer cancellation and actual unanswered or offline-peer timeout end cleanly; concurrent or crossed incoming calls cannot replace an active call; delayed terminal signals cannot revive it, and a subsequent call can start.

**Inspected test evidence**

- [test/features/call/application/call_race_convergence_test.dart](../../test/features/call/application/call_race_convergence_test.dart) — `paired glare converges with lower caller $lowerSide and reversed delivery $reverse, terminal replay cleans once` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_race_convergence_test.dart:109: Two actual coordinators under both caller-order and delivery-order variants converge canonical glare leg; terminal replay cleans each once. Fake effects/history, no native ringing/audio. Registered: affected-calls, host-all.
- [test/features/call/application/call_race_convergence_test.dart](../../test/features/call/application/call_race_convergence_test.dart) — `unrelated second call is busy and cannot replace active call` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_race_convergence_test.dart:272: Unrelated incoming call cannot replace canonical active owner; modeled effects/native media. Registered: affected-calls, host-all.
- [test/features/call/application/call_coordinator_test.dart](../../test/features/call/application/call_coordinator_test.dart) — `injected 30 second no-answer timer terminates the call` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_coordinator_test.dart:695: Fake-time30s no-answer dispatch yields terminal state; expired/cancelled timer tests fence stale callback. Not actual offline/push scheduling. Registered: affected-calls, host-all.
- [test/features/call/integration/presentation_refusal_round_trip_test.dart](../../test/features/call/integration/presentation_refusal_round_trip_test.dart) — `a callee whose call surface refuses to ring leaves one missed call and the caller reads "No answer"` (integration).
  - Real: two production coordinators/codec/control executor; actual overlay end-reason rendering.
  - Faked: crypto/roster/transport/history/notification posting and native refusal.
  - Proves / registration: test/features/call/integration/presentation_refusal_round_trip_test.dart:43: Two real coordinators/codec/control executor propagate no_answer, one missed notification/history and caller No answer UI. Header:30 explicitly substitutes crypto, roster, transport write and notification post. Registered: affected-calls, host-all.

**Remaining gaps**

- Real coordinator two-party race/no-answer/refusal policies covered using fake wire/native media. Actual native cancellation disappearance/offline timeout and all cleanup outcomes are not one full campaign.

#### VC-017 — A dropped connection recovers the call or ends it honestly

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-017.

**Steps**

1. Interrupt established network.
2. Show same-call recovery and retain original deadline.
3. Recover ready media or end, ignoring late readiness after terminal.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** A bounded network interruption shows recovery; media resumes only for the same current call, or the original recovery deadline terminates cleanly; late recovery cannot revive a terminal call.

**Inspected test evidence**

- [test/features/call/application/call_network_path_binding_test.dart](../../test/features/call/application/call_network_path_binding_test.dart) — `readiness after the original expiry cannot revive the call` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_network_path_binding_test.dart:306: Network readiness arriving after original recovery deadline cannot revive call; exact active generation and hangup tests use fake source/media readiness. Registered: affected-calls, host-all.
- [test/features/call/integration/call_turn_policy_test.dart](../../test/features/call/integration/call_turn_policy_test.dart) — `valid TURN preserves $policy and approved STUN` (integration).
  - Real: actual controller/coordinator/negotiation/FlutterWebRtc engine policy; deterministic fake-time recovery/deadline.
  - Faked: scripted Bridge TURN credentials; fake native PeerConnection selected transport.
  - Proves / registration: test/features/call/integration/call_turn_policy_test.dart:133: Wrapper _testClock:423 registers each CallTransportPolicy enum expansion under host-all; :133 verifies native configuration relayOnly/all, then simulates selected TURN UDP. :157 parameterized outage/timeout rejects relayOnly before connection and permits approved STUN for all; actual native route not established. Registered: affected-calls, call-signaling, host-all.
- [test/features/call/integration/process_loss_recovery_decisions_test.dart](../../test/features/call/integration/process_loss_recovery_decisions_test.dart) — `surviving peer given media loss ends at its original 15-second deadline and can place a fresh call` (integration).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/integration/process_loss_recovery_decisions_test.dart:336: Given simulated media loss, original15s deadline ends peer and next call can start. Fake-time/native engine loss, not killing other actual phone process. Registered: affected-calls, host-all.

**Remaining gaps**

- Causal fake-time/network/native readiness model; no actual radio handover/packet interruption and restored bidirectional media run.

#### VC-018 — Audio interruptions let the call recover or end safely

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-018.

**Steps**

1. Interrupt OS audio focus/session.
2. Pause/recover only when media ready and current generation.
3. Keep explicit mute and protect replacement call.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Available OS audio-focus interruptions follow the supported pause or terminal policy; recovery requires ready media and cannot affect a replacement call or silently override mute.

**Inspected test evidence**

- [test/features/call/application/call_audio_interruption_coordinator_test.dart](../../test/features/call/application/call_audio_interruption_coordinator_test.dart) — `recovery never connects from UI intent without media readiness` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_audio_interruption_coordinator_test.dart:154: UI recovery cannot reconnect unless actual sampled structural readiness; async old-generation recovery case fences replacement. Injected readiness/session events, no actual OS interruption. Registered: affected-calls, call-signaling, host-all.
- [test/features/call/integration/microphone_command_privacy_test.dart](../../test/features/call/integration/microphone_command_privacy_test.dart) — `${direction.name}: mute remains applied through interruption and is restored after an unmute is reversed` (integration).
  - Real: production coordinator/audio/engine and real FFI SQLite.
  - Faked: scripted native WebRTC/session and permission ports.
  - Proves / registration: test/features/call/integration/microphone_command_privacy_test.dart:480: Both direction variants keep enabled=false across interruption and reversed unmute; actual native RTP/audio content not sampled. Registered: affected-calls, host-all.
- [test/features/call/infrastructure/call_media_conflict_adapter_test.dart](../../test/features/call/infrastructure/call_media_conflict_adapter_test.dart) — `refuses call capture while voice-note recording owns microphone` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/infrastructure/call_media_conflict_adapter_test.dart:12: Real shared microphone conflict adapter refuses while fake voice-note recorder owns lease; protected-media viewer and OS audio focus not represented. Registered: affected-calls, host-all.

**Remaining gaps**

- Injected interruption and microphone leases test policy. Actual OS audio-focus/phone interruption/native route recovery/audio are separate.

#### VC-019 — The microphone is never sent before answering or while muted

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-019.

**Steps**

1. Before answer inspect zero capture/content.
2. Mute/unmute either peer and check received content.
3. Hang up/lifecycle change; stale unmute must not capture.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** No microphone content reaches the other peer before acceptance or after hangup; muting either endpoint suppresses its microphone content, unmuting restores it and lifecycle transitions do not silently unmute.

**Inspected test evidence**

- [test/features/call/integration/microphone_command_privacy_test.dart](../../test/features/call/integration/microphone_command_privacy_test.dart) — `${direction.name}: ringing issues no capture command; answer enables it; hangup fences later unmute` (integration).
  - Real: production coordinator/audio/control/FlutterWebRtc engine composition; production FFI SQLite schema/history.
  - Faked: counting native WebRTC/session/permission/route ports; scripted signaling.
  - Proves / registration: test/features/call/integration/microphone_command_privacy_test.dart:431: For both direction enum values, real coordinator/engine ownership/control/terminal/history composition with real FFI SQLite. Ringing has zero native create/enabled writes, answer starts at accepted, hangup closes/disables and late unmute does nothing. Actual native backend is counted fake. Registered: affected-calls, host-all.
- [test/features/call/integration/microphone_command_privacy_test.dart](../../test/features/call/integration/microphone_command_privacy_test.dart) — `${direction.name}: mute remains applied through interruption and is restored after an unmute is reversed` (integration).
  - Real: production coordinator/audio/engine and real FFI SQLite.
  - Faked: scripted native WebRTC/session and permission ports.
  - Proves / registration: test/features/call/integration/microphone_command_privacy_test.dart:480: Both direction variants keep enabled=false across interruption and reversed unmute; actual native RTP/audio content not sampled. Registered: affected-calls, host-all.
- [integration_test/scripts/android_foreground_webrtc_audio_campaign.dart](../../integration_test/scripts/android_foreground_webrtc_audio_campaign.dart) — `android.foreground_webrtc_audio` (sims).
  - Real: native Android WebRTC engines and canonical secure signaling/cleanup; bidirectional RTP/readiness observations under both-muted controls.
  - Faked: dedicated foreground harness/permission-pregranted fixture; host rendezvous forwards secure envelope and fixed barriers.
  - Proves / registration: integration_test/scripts/android_foreground_webrtc_audio_campaign.dart:206: Registered foreground media campaign; :24 enumerates both-muted barriers, evidence android_foreground_webrtc_audio_evidence.dart:1522 validates directional RTP. This is canonical foreground harness, not every production UI/OS lifecycle nor semantic microphone-content leakage proof. Not executed. Registered: see cited native runner/manifest.

**Remaining gaps**

- Host verifies command/capture ownership with fake native port; actual muted RTP progress can contain silence or content. No qualifying recipient semantic/acoustic no-microphone-content proof before answer/while muted found.

#### VC-020 — Calls handle microphone and notification permissions safely

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-020.

**Steps**

1. Try missing identity/ineligible contact/busy/microphone denial.
2. Verify zero unauthorized signaling/capture.
3. Grant permission and retry; exercise notification-denial fallback.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Normal call entrypoints reject unavailable identity, ineligible contact, busy state or microphone denial without unauthorized signaling or capture; later permission grant allows calling and notification denial has the supported platform fallback.

**Inspected test evidence**

- [test/features/call/application/call_audio_controller_test.dart](../../test/features/call/application/call_audio_controller_test.dart) — `permission denial creates no connection, track, or SDP` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_audio_controller_test.dart:35: Permanent denial creates no connection/track/SDP/session; grants-on-next-call companion uses fake permission gateway, not actual OS prompt. Registered: affected-calls, host-all.
- [test/features/call/application/call_audio_controller_test.dart](../../test/features/call/application/call_audio_controller_test.dart) — `a mic turned on in Settings lets the next call start without a restart` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_audio_controller_test.dart:366: Fake gateway changes permission between attempts; next accepted call starts without controller restart. Does not operate native Settings. Registered: affected-calls, host-all.
- [test/features/call/application/incoming_call_pre_presentation_admission_test.dart](../../test/features/call/application/incoming_call_pre_presentation_admission_test.dart) — `blocked and unknown authenticated transports reject permanently` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/incoming_call_pre_presentation_admission_test.dart:58: Blocked or unknown authenticated transport permanently rejects before presentation; fixture crypto/roster/network. Does not prove OS PushKit/FCM reception. Registered: affected-calls, host-all.
- [integration_test/scripts/run_production_call_back.dart](../../integration_test/scripts/run_production_call_back.dart) — `kx0008` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_back.dart:8: production_call_back_criteria.dart:335 requires microphoneDenied, no connection/current call and real positive-to-zero owned AudioRecord client control from bounded OS dump, plus feedback. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0005, kx0006, kx0007, kx0008.

**Remaining gaps**

- Real Android denied-callback capture campaign exists; other eligibility/permission grant/native notification fallback branches remain split host/native fake boundaries. All requested entrypoints not joined.

#### VC-021 — Call history is kept after a restart and calls back the right person

**Coverage:** strong. **Execution:** host_run. **Catalog:** VC-021.

**Steps**

1. Complete/decline/miss call and persist one terminal status/duration.
2. Reopen SQL/app and browse/search history.
3. Callback current correct contact.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Call outcomes produce the supported privacy-safe status and duration without duplicate terminal rows; history survives restart and its callback reaches the correct contact.

**Fresh host join (2026-10-22)**

- test/features/call/data/call_history_repository_test.dart:104: Terminal projector -> real current SQL file reopen/replay -> actual CallsPage -> real redial controller admits exact current account once, retaining one privacy-safe row with original duration/reason. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: constructed terminal snapshot; outgoing call-start capability port.

**Inspected test evidence**

- [test/features/call/data/call_history_repository_test.dart](../../test/features/call/data/call_history_repository_test.dart) — `fresh projector preserves one terminal row after SQLite reopen` (unit).
  - Real: current FFI SQLite/file reopen/CallHistoryRepositoryImpl/projector.
  - Faked: constructed terminal snapshots/clock; no actual call hardware.
  - Proves / registration: test/features/call/data/call_history_repository_test.dart:115: Actual current production SQL schema/file close+reopen and new projector preserve one terminal row, original duration/reason and no second announcement even conflicting replay. Registered: affected-calls, host-all.
- [test/features/call/data/call_history_repository_test.dart](../../test/features/call/data/call_history_repository_test.dart) — `global history pages have one row per call, stable equal-time order, local search and current names` (unit).
  - Real: FFI SQLite history/contact data and production history consumers.
  - Faked: constructed rows and callback owner.
  - Proves / registration: test/features/call/data/call_history_repository_test.dart:178: Actual SQL paging/order/search joins current contact names; real callback capability is replaced with recording starts. Registered: affected-calls, host-all.
- [test/features/call/presentation/calls_page_test.dart](../../test/features/call/presentation/calls_page_test.dart) — `paging renders each call once; refresh reflects rename/removal without clearing unread elsewhere` (widget).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/presentation/calls_page_test.dart:146: Actual Calls widget paging/refresh reflects renamed/removed fixture contact while unrelated unread retained; repository/callback fake, no native call. Registered: affected-calls, call-signaling, host-all.
- [test/features/call/application/call_redial_controller_test.dart](../../test/features/call/application/call_redial_controller_test.dart) — `new callback supersedes A at $stage before canonical admission` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_redial_controller_test.dart:288: Seven async stages parameterize cancellation/supersession; latest history/contact/preflight bound before canonical admission. Controlled readiness/history/endpoint/gateway ports. Registered: affected-calls, call-signaling, host-all.

**Remaining gaps**

- Native call completion/audio and OS process death were not exercised. Strong is the shared durable-history/page/callback identity contract, not remote ringing or signed-call certification.

**Open questions**

- Scoped host proof only. Device handoff and exact remaining boundaries: docs/testing/astra-lever1-host-quickwins.md. No actual device, signed-candidate or whole affected-lane verdict.

#### VC-022 — Fake or old call signals cannot take over a call

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-022.

**Steps**

1. Inject forged/malformed/replayed/out-of-authority signals.
2. Preserve current call/no unauthorized ring or capture.
3. Accept subsequent legitimate input.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Invalid sender or key authority, malformed or replayed signals, ineligible contacts and stale call ownership cannot cause an unauthorized ring, capture or change to a live call; valid signaling remains usable.

**Inspected test evidence**

- [test/features/call/infrastructure/secure_call_envelope_codec_test.dart](../../test/features/call/infrastructure/secure_call_envelope_codec_test.dart) — `rejects invalid signature before decryption with privacy-safe error` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/infrastructure/secure_call_envelope_codec_test.dart:281: Codec rejects invalid signature before decrypt and returns privacy-safe error; _DeterministicCrypto:12 uses reversible base64/text signature model, not real ML-KEM/Ed25519. Registered: affected-calls, host-all.
- [test/features/call/infrastructure/secure_call_envelope_codec_test.dart](../../test/features/call/infrastructure/secure_call_envelope_codec_test.dart) — `rejects duplicate message IDs and non-monotonic sender sequence` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/infrastructure/secure_call_envelope_codec_test.dart:362: Replay/sequence admission, separate out-of-order accepted negotiation and exact changed-bytes-same-ID cases. Deterministic base64/signature model, no native crypto. Registered: affected-calls, host-all.
- [test/features/call/application/incoming_call_pre_presentation_admission_test.dart](../../test/features/call/application/incoming_call_pre_presentation_admission_test.dart) — `blocked and unknown authenticated transports reject permanently` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/incoming_call_pre_presentation_admission_test.dart:58: Blocked or unknown authenticated transport permanently rejects before presentation; fixture crypto/roster/network. Does not prove OS PushKit/FCM reception. Registered: affected-calls, host-all.
- [test/features/call/application/call_race_convergence_test.dart](../../test/features/call/application/call_race_convergence_test.dart) — `paired glare converges with lower caller $lowerSide and reversed delivery $reverse, terminal replay cleans once` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_race_convergence_test.dart:109: Two actual coordinators under both caller-order and delivery-order variants converge canonical glare leg; terminal replay cleans each once. Fake effects/history, no native ringing/audio. Registered: affected-calls, host-all.

**Remaining gaps**

- Actual codec/admission/ownership policies tested using deterministic reversible crypto/signatures and fake roster/transport. Genuine Go/native crypto plus OS-presentation joined adversarial proof not established by these host tests.

#### VC-023 — With always-relay on, calls really go through the relay

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-023.

**Steps**

1. Enable user always-relay choice.
2. Observe actual selected relay-only media route.
3. Remove TURN, refuse direct fallback, restore TURN and call again.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** The enabled privacy setting propagates into actual relay-only media selection; unavailable relay service produces an honest failure without direct fallback, and restored service permits a call.

**Inspected test evidence**

- [integration_test/scripts/run_production_call_regression.dart](../../integration_test/scripts/run_production_call_regression.dart) — `kx0030` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_regression.dart:8: production_call_surface_regressions.dart:482 explicitly scopes saved preference/copy only; reads saved boolean, toggles, relaunches/restores. Forced-relay campaign build cannot prove causal network change from this toggle. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0001, kx0002, kx0003, kx0015, kx0016, kx0017, kx0029, kx0030.
- [test/features/call/integration/call_turn_policy_test.dart](../../test/features/call/integration/call_turn_policy_test.dart) — `valid TURN preserves $policy and approved STUN` (integration).
  - Real: actual controller/coordinator/negotiation/FlutterWebRtc engine policy; deterministic fake-time recovery/deadline.
  - Faked: scripted Bridge TURN credentials; fake native PeerConnection selected transport.
  - Proves / registration: test/features/call/integration/call_turn_policy_test.dart:133: Wrapper _testClock:423 registers each CallTransportPolicy enum expansion under host-all; :133 verifies native configuration relayOnly/all, then simulates selected TURN UDP. :157 parameterized outage/timeout rejects relayOnly before connection and permits approved STUN for all; actual native route not established. Registered: affected-calls, call-signaling, host-all.
- [test/features/call/infrastructure/flutter_webrtc_call_engine_test.dart](../../test/features/call/infrastructure/flutter_webrtc_call_engine_test.dart) — `relay-only selected direct transport fails closed` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/infrastructure/flutter_webrtc_call_engine_test.dart:2019: Relay-only config with native snapshot reporting selected direct transport fails closed. Fake adapter reports classification, no packet route evidence. Registered: affected-calls, call-signaling, host-all.
- [integration_test/scripts/android_production_audio_call_campaign.dart](../../integration_test/scripts/android_production_audio_call_campaign.dart) — `android.production_1to1_audio_call` (sims).
  - Real: production app semantic start/native answer and real Android WebRTC RTP; same APK; physical Android+emulator; exact call-bound observers; actual native cleanup and bounded evidence validation.
  - Faked: disposable local relay/coturn and fresh contacts; separate host Pion known-Opus oracle; this does not substitute for app RTP.
  - Proves / registration: integration_test/scripts/android_production_audio_call_campaign.dart:539: executeAndroidProductionAudioCallCampaign exercises mute/speaker/emulator hangup and verifies both native calls released. integration_test/support/android_production_audio_call_evidence.dart:448 requires all controls, :465 cleanup, :487 both app RTP directions plus independent Pion fixture. Registered android.production_1to1_audio_call; no human audibility/content fidelity claim or run here. Registered: see cited native runner/manifest.

**Remaining gaps**

- Saved preference and relayOnly/outage policy tested separately; actual audio campaign uses forced-relay build. No joined user-toggle-to-real-route/outage/no-direct-fallback/restored-service campaign found.

#### VC-024 — Long calls stay clear on available audio outputs

**Coverage:** missing. **Execution:** not_run. **Catalog:** VC-024.

**Steps**

1. Hold sustained real bidirectional call.
2. Monitor usable audio/resources over duration.
3. Connect/disconnect available accessories and recover output.

**Conditions:** platform: only actually available audio outputs; connectivity: n/a; offline: n/a; app state: foreground; input: sustained real audio; duration to be specified; recovery: n/a.

**Expected:** A sustained call retains intelligible bidirectional audio without progressive silence or unbounded resource growth; available accessory connection, removal and route switching preserve usable audio or the supported fallback.

**Inspected test evidence**

- [test/features/call/presentation/call_audio_output_picker_test.dart](../../test/features/call/presentation/call_audio_output_picker_test.dart) — `hot-plug refresh observes fallback and disposal discards a late inventory` (widget).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/presentation/call_audio_output_picker_test.dart:86: Injected output inventory hot-plug refresh observes fallback and ignores late disposed inventory; native hot-plug event/accessory acoustic outcome absent. Registered: affected-calls, call-signaling, host-all.
- [integration_test/scripts/android_production_audio_call_campaign.dart](../../integration_test/scripts/android_production_audio_call_campaign.dart) — `android.production_1to1_audio_call` (sims).
  - Real: production app semantic start/native answer and real Android WebRTC RTP; same APK; physical Android+emulator; exact call-bound observers; actual native cleanup and bounded evidence validation.
  - Faked: disposable local relay/coturn and fresh contacts; separate host Pion known-Opus oracle; this does not substitute for app RTP.
  - Proves / registration: integration_test/scripts/android_production_audio_call_campaign.dart:539: executeAndroidProductionAudioCallCampaign exercises mute/speaker/emulator hangup and verifies both native calls released. integration_test/support/android_production_audio_call_evidence.dart:448 requires all controls, :465 cleanup, :487 both app RTP directions plus independent Pion fixture. Registered android.production_1to1_audio_call; no human audibility/content fidelity claim or run here. Registered: see cited native runner/manifest.

**Remaining gaps**

- Short call RTP/control campaign and sampler/route fakes do not establish sustained intelligible audio or bounded long-duration growth/accessory transitions. No qualifying soak found.

**Open questions**

- Specify supported sustained-call acceptance duration/resource thresholds; do not require unavailable accessories.

#### VC-025 — Answering on a locked phone does not reveal private chats

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-025.

**Steps**

1. Answer from locked native surface.
2. Attempt conversation/contact/navigation access without unlock.
3. Expose only allowed controls until real unlock.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Answering from the locked system surface shows only permitted call controls until real unlock; conversation history, contact lists and navigation remain inaccessible behind the call.

**Inspected test evidence**

- [test/features/call/presentation/foreground_call_overlay_test.dart](../../test/features/call/presentation/foreground_call_overlay_test.dart) — `modal call semantics hide background actions until terminal dismissal` (widget).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/presentation/foreground_call_overlay_test.dart:1148: Actual overlay semantics exclude background actions/history until dismissal; supplied fake capability/session/lock projection. Not physical keyguard visual/touch/navigation confidentiality proof. Registered: affected-calls, host-all, ui-approved-recovery-readability.
- [integration_test/scripts/run_production_call_back.dart](../../integration_test/scripts/run_production_call_back.dart) — `kx0006` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_back.dart:8: production_call_back_criteria.dart:308 checks actual credential-free emulator keyguard remains locked without dialing, then real unlock admits latest B; keyguard restored. Not a credentialed physical lock-screen bypass proof. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0005, kx0006, kx0007, kx0008.

**Remaining gaps**

- Semantics modal policy and locked callback no-dial are different assertions. Neither proves real locked-answer physical visual/touch/history confidentiality; native JVM tests remain separate.

#### VC-026 — If the app is killed during a call, both sides recover correctly

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-026.

**Steps**

1. Lose app process while ringing/active.
2. Inspect native capture/resource reconciliation and remote deadline.
3. Restart and place fresh call.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** When the app process is lost during ringing or an active call, owned capture and native call resources release or reconcile according to the supported OS lifecycle contract; the remote peer settles within its deadline and restart can place a fresh call.

**Inspected test evidence**

- [test/features/call/integration/process_loss_recovery_decisions_test.dart](../../test/features/call/integration/process_loss_recovery_decisions_test.dart) — `fresh Dart owner reconciles supplied native terminal replay without re-ringing; SQL survives reopen` (integration).
  - Real: production lifecycle adapter/coordinator/real FFI SQLite reopen.
  - Faked: supplied native terminal/journal port and native media.
  - Proves / registration: test/features/call/integration/process_loss_recovery_decisions_test.dart:230: Fresh owner reconciles supplied native terminal with real SQL reopen, no re-ring; native journal/replay is supplied. Not actual OS process kill/capture release. Registered: affected-calls, host-all.
- [test/features/call/integration/process_loss_recovery_decisions_test.dart](../../test/features/call/integration/process_loss_recovery_decisions_test.dart) — `surviving peer given media loss ends at its original 15-second deadline and can place a fresh call` (integration).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/integration/process_loss_recovery_decisions_test.dart:336: Given simulated media loss, original15s deadline ends peer and next call can start. Fake-time/native engine loss, not killing other actual phone process. Registered: affected-calls, host-all.
- [test/features/call/application/call_coordinator_shutdown_terminate_test.dart](../../test/features/call/application/call_coordinator_shutdown_terminate_test.dart) — `engine teardown during a connected call delivers the appShutdown terminate before call signaling closes` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_coordinator_shutdown_terminate_test.dart:37: Orderly engine teardown sends appShutdown terminate before signaling closes, bounded hung-write companion. Graceful dispose is not uncatchable OS process death. Registered: affected-calls, host-all.

**Remaining gaps**

- Actual SQL reopen/supplied journal and given media-loss deadline proven. Graceful shutdown sends terminate but cannot stand for hard OS kill; native capture cleanup and surviving remote under actual kill missing.

#### VC-027 — Every way a call ends frees the microphone and audio

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-027.

**Steps**

1. End through every supported terminal reason.
2. Retry bounded failed cleanup and persist terminal once.
3. Protect newer call and release native capture/card/resources.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Normal and remote hangup, decline, cancellation, timeout, busy rejection and media failure release owned capture, native call and notification resources and persist the supported terminal state without affecting a newer call.

**Inspected test evidence**

- [test/features/call/application/call_cleanup_coordinator_test.dart](../../test/features/call/application/call_cleanup_coordinator_test.dart) — `critical failure blocks terminal ACK and retry runs only that step` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_cleanup_coordinator_test.dart:127: Critical cleanup failure gates terminal ACK; retry reruns only failed step, bounded/throwing-step companion preserves remaining cleanup. Callback counters, not native mic ownership. Registered: affected-calls, host-all.
- [test/features/call/integration/microphone_command_privacy_test.dart](../../test/features/call/integration/microphone_command_privacy_test.dart) — `${direction.name}: ringing issues no capture command; answer enables it; hangup fences later unmute` (integration).
  - Real: production coordinator/audio/control/FlutterWebRtc engine composition; production FFI SQLite schema/history.
  - Faked: counting native WebRTC/session/permission/route ports; scripted signaling.
  - Proves / registration: test/features/call/integration/microphone_command_privacy_test.dart:431: For both direction enum values, real coordinator/engine ownership/control/terminal/history composition with real FFI SQLite. Ringing has zero native create/enabled writes, answer starts at accepted, hangup closes/disables and late unmute does nothing. Actual native backend is counted fake. Registered: affected-calls, host-all.
- [integration_test/scripts/android_production_audio_call_campaign.dart](../../integration_test/scripts/android_production_audio_call_campaign.dart) — `android.production_1to1_audio_call` (sims).
  - Real: production app semantic start/native answer and real Android WebRTC RTP; same APK; physical Android+emulator; exact call-bound observers; actual native cleanup and bounded evidence validation.
  - Faked: disposable local relay/coturn and fresh contacts; separate host Pion known-Opus oracle; this does not substitute for app RTP.
  - Proves / registration: integration_test/scripts/android_production_audio_call_campaign.dart:539: executeAndroidProductionAudioCallCampaign exercises mute/speaker/emulator hangup and verifies both native calls released. integration_test/support/android_production_audio_call_evidence.dart:448 requires all controls, :465 cleanup, :487 both app RTP directions plus independent Pion fixture. Registered android.production_1to1_audio_call; no human audibility/content fidelity claim or run here. Registered: see cited native runner/manifest.
- [ios/RunnerTests/MknoonCallKitLifecycleTests.swift](../../ios/RunnerTests/MknoonCallKitLifecycleTests.swift) — `testRetiredTerminalReceiptDoesNotReleaseSuccessorAudio` (unit).
  - Real: actual Swift lifecycle/store receipt ownership rules.
  - Faked: makeRig MemoryPendingCallBackend; FakeCallProvider/FakeCallAudio and controlled clock.
  - Proves / registration: ios/RunnerTests/MknoonCallKitLifecycleTests.swift:1255: After old receipt retention and successor answer/adoption/activation, two old ACKs leave successor descriptor/audio intact. Registered native.ios.runner_tests; no actual delayed OS callback or audible successor call. Registered: see cited native runner/manifest.

**Remaining gaps**

- Real normal Android hangup/native cleanup campaign exists and host critical retry/ownership cases cover policy. Actual native failure/decline/cancel/timeout/busy matrix not fully joined or run.

#### VC-028 — Calls work both over a direct connection and through the relay

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-028.

**Steps**

1. Establish available direct and TURN UDP/TCP calls.
2. Observe selected transport classification and bidirectional media.
3. Exercise supported fallback and clean termination.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Available direct, TURN UDP and supported TURN TCP profiles establish bidirectional media and cleanly terminate, with selected transport classifications and the tested fallback conditions recorded.

**Inspected test evidence**

- [test/features/call/integration/call_turn_policy_test.dart](../../test/features/call/integration/call_turn_policy_test.dart) — `valid TURN preserves $policy and approved STUN` (integration).
  - Real: actual controller/coordinator/negotiation/FlutterWebRtc engine policy; deterministic fake-time recovery/deadline.
  - Faked: scripted Bridge TURN credentials; fake native PeerConnection selected transport.
  - Proves / registration: test/features/call/integration/call_turn_policy_test.dart:133: Wrapper _testClock:423 registers each CallTransportPolicy enum expansion under host-all; :133 verifies native configuration relayOnly/all, then simulates selected TURN UDP. :157 parameterized outage/timeout rejects relayOnly before connection and permits approved STUN for all; actual native route not established. Registered: affected-calls, call-signaling, host-all.
- [test/features/call/infrastructure/flutter_webrtc_call_engine_test.dart](../../test/features/call/infrastructure/flutter_webrtc_call_engine_test.dart) — `relay-only selected direct transport fails closed` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/infrastructure/flutter_webrtc_call_engine_test.dart:2019: Relay-only config with native snapshot reporting selected direct transport fails closed. Fake adapter reports classification, no packet route evidence. Registered: affected-calls, call-signaling, host-all.
- [integration_test/scripts/android_production_audio_call_campaign.dart](../../integration_test/scripts/android_production_audio_call_campaign.dart) — `android.production_1to1_audio_call` (sims).
  - Real: production app semantic start/native answer and real Android WebRTC RTP; same APK; physical Android+emulator; exact call-bound observers; actual native cleanup and bounded evidence validation.
  - Faked: disposable local relay/coturn and fresh contacts; separate host Pion known-Opus oracle; this does not substitute for app RTP.
  - Proves / registration: integration_test/scripts/android_production_audio_call_campaign.dart:539: executeAndroidProductionAudioCallCampaign exercises mute/speaker/emulator hangup and verifies both native calls released. integration_test/support/android_production_audio_call_evidence.dart:448 requires all controls, :465 cleanup, :487 both app RTP directions plus independent Pion fixture. Registered android.production_1to1_audio_call; no human audibility/content fidelity claim or run here. Registered: see cited native runner/manifest.
- [integration_test/scripts/android_foreground_webrtc_audio_campaign.dart](../../integration_test/scripts/android_foreground_webrtc_audio_campaign.dart) — `android.foreground_webrtc_audio` (sims).
  - Real: native Android WebRTC engines and canonical secure signaling/cleanup; bidirectional RTP/readiness observations under both-muted controls.
  - Faked: dedicated foreground harness/permission-pregranted fixture; host rendezvous forwards secure envelope and fixed barriers.
  - Proves / registration: integration_test/scripts/android_foreground_webrtc_audio_campaign.dart:206: Registered foreground media campaign; :24 enumerates both-muted barriers, evidence android_foreground_webrtc_audio_evidence.dart:1522 validates directional RTP. This is canonical foreground harness, not every production UI/OS lifecycle nor semantic microphone-content leakage proof. Not executed. Registered: see cited native runner/manifest.

**Remaining gaps**

- Host native adapter simulates classifications. Actual local production audio proves scoped relay/RTP, not complete direct/TURN TCP failure/fallback and platform transport matrix.

#### CALL-001 — Start a call from chat header, call-history row and missed-call notification

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-005, VC-021.

**Steps**

1. Start from chat header.
2. Use history row and missed-call native callback.
3. Resolve exact current account and preflight each path.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Start a call from chat header, call-history row and missed-call notification

**Inspected test evidence**

- [test/features/call/presentation/calls_page_test.dart](../../test/features/call/presentation/calls_page_test.dart) — `paging renders each call once; refresh reflects rename/removal without clearing unread elsewhere` (widget).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/presentation/calls_page_test.dart:146: Actual Calls widget paging/refresh reflects renamed/removed fixture contact while unrelated unread retained; repository/callback fake, no native call. Registered: affected-calls, call-signaling, host-all.
- [test/features/call/application/call_redial_controller_test.dart](../../test/features/call/application/call_redial_controller_test.dart) — `new callback supersedes A at $stage before canonical admission` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_redial_controller_test.dart:288: Seven async stages parameterize cancellation/supersession; latest history/contact/preflight bound before canonical admission. Controlled readiness/history/endpoint/gateway ports. Registered: affected-calls, call-signaling, host-all.
- [integration_test/scripts/run_production_call_back.dart](../../integration_test/scripts/run_production_call_back.dart) — `kx0005` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_back.dart:8: production_call_back_criteria.dart:277 requires verified owned-process death, actual A then B callback submissions before readiness release, one fresh outgoing call to B only. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0005, kx0006, kx0007, kx0008.

**Remaining gaps**

- Native callback campaign and current-history guards substantive; actual chat-header/history-row-to-audible-call joins are not all covered by same production flow.

#### CALL-002 — Cancel outgoing call before answer; callee stops ringing without stale ongoing UI

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-016.

**Steps**

1. Start outgoing then cancel before answer.
2. Ensure callee ringing and native ongoing UI stop.
3. Ignore late answer and allow next call.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Cancel outgoing call before answer; callee stops ringing without stale ongoing UI

**Inspected test evidence**

- [test/features/call/application/call_coordinator_test.dart](../../test/features/call/application/call_coordinator_test.dart) — `canceling a queued preflight prevents admission and preserves retry` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_coordinator_test.dart:297: Queued outgoing preflight cancellation preserves retry and prevents admission. Does not observe callee native ringing disappearance. Registered: affected-calls, host-all.
- [test/features/call/application/call_race_convergence_test.dart](../../test/features/call/application/call_race_convergence_test.dart) — `paired glare converges with lower caller $lowerSide and reversed delivery $reverse, terminal replay cleans once` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_race_convergence_test.dart:109: Two actual coordinators under both caller-order and delivery-order variants converge canonical glare leg; terminal replay cleans each once. Fake effects/history, no native ringing/audio. Registered: affected-calls, host-all.
- [test/features/call/integration/presentation_refusal_round_trip_test.dart](../../test/features/call/integration/presentation_refusal_round_trip_test.dart) — `a callee whose call surface refuses to ring leaves one missed call and the caller reads "No answer"` (integration).
  - Real: two production coordinators/codec/control executor; actual overlay end-reason rendering.
  - Faked: crypto/roster/transport/history/notification posting and native refusal.
  - Proves / registration: test/features/call/integration/presentation_refusal_round_trip_test.dart:43: Two real coordinators/codec/control executor propagate no_answer, one missed notification/history and caller No answer UI. Header:30 explicitly substitutes crypto, roster, transport write and notification post. Registered: affected-calls, host-all.

**Remaining gaps**

- Host admission and terminal/race policies do not inspect actual callee ringing dismissal and late native answer across both devices.

#### CALL-003 — Caller offline or callee unreachable: no false connected or permanently ringing state

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-017.

**Steps**

1. Call with offline/unreachable peer.
2. Wait actual source-defined timeout.
3. Show honest terminal result without false connected/stuck ring, then retry.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Caller offline or callee unreachable: no false connected or permanently ringing state

**Inspected test evidence**

- [test/features/call/application/call_coordinator_test.dart](../../test/features/call/application/call_coordinator_test.dart) — `injected 30 second no-answer timer terminates the call` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_coordinator_test.dart:695: Fake-time30s no-answer dispatch yields terminal state; expired/cancelled timer tests fence stale callback. Not actual offline/push scheduling. Registered: affected-calls, host-all.
- [test/features/call/integration/call_turn_policy_test.dart](../../test/features/call/integration/call_turn_policy_test.dart) — `valid TURN preserves $policy and approved STUN` (integration).
  - Real: actual controller/coordinator/negotiation/FlutterWebRtc engine policy; deterministic fake-time recovery/deadline.
  - Faked: scripted Bridge TURN credentials; fake native PeerConnection selected transport.
  - Proves / registration: test/features/call/integration/call_turn_policy_test.dart:133: Wrapper _testClock:423 registers each CallTransportPolicy enum expansion under host-all; :133 verifies native configuration relayOnly/all, then simulates selected TURN UDP. :157 parameterized outage/timeout rejects relayOnly before connection and permits approved STUN for all; actual native route not established. Registered: affected-calls, call-signaling, host-all.
- [test/features/call/integration/presentation_refusal_round_trip_test.dart](../../test/features/call/integration/presentation_refusal_round_trip_test.dart) — `a callee whose call surface refuses to ring leaves one missed call and the caller reads "No answer"` (integration).
  - Real: two production coordinators/codec/control executor; actual overlay end-reason rendering.
  - Faked: crypto/roster/transport/history/notification posting and native refusal.
  - Proves / registration: test/features/call/integration/presentation_refusal_round_trip_test.dart:43: Two real coordinators/codec/control executor propagate no_answer, one missed notification/history and caller No answer UI. Header:30 explicitly substitutes crypto, roster, transport write and notification post. Registered: affected-calls, host-all.

**Remaining gaps**

- Fake-time no-answer and connection/credential failure covered, but actual unreachable peer/native ring and successful later retry not a complete device assertion.

#### CALL-004 — Incoming call while another call or protected-media viewer is active

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-016, VC-018.

**Steps**

1. Receive second call during current call or protected viewer.
2. Preserve active call/lease and reject unauthorized capture.
3. Allow subsequent eligible call after cleanup.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Incoming call while another call or protected-media viewer is active

**Inspected test evidence**

- [test/features/call/application/call_race_convergence_test.dart](../../test/features/call/application/call_race_convergence_test.dart) — `unrelated second call is busy and cannot replace active call` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_race_convergence_test.dart:272: Unrelated incoming call cannot replace canonical active owner; modeled effects/native media. Registered: affected-calls, host-all.
- [test/features/call/infrastructure/call_media_conflict_adapter_test.dart](../../test/features/call/infrastructure/call_media_conflict_adapter_test.dart) — `refuses call capture while voice-note recording owns microphone` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/infrastructure/call_media_conflict_adapter_test.dart:12: Real shared microphone conflict adapter refuses while fake voice-note recorder owns lease; protected-media viewer and OS audio focus not represented. Registered: affected-calls, host-all.

**Remaining gaps**

- Canonical busy and voice-recorder shared lease covered. Protected-media viewer, native incoming presentation during it and no content/privacy leak are not a joined assertion.

#### CALL-005 — Bluetooth/wired headset attach/detach and route selection during a call

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-007, VC-024.

**Steps**

1. Connect/disconnect available wired/Bluetooth accessory.
2. Refresh current actual output inventory and select exact route.
3. Handle hot-unplug without stale replacement or lost audio.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Bluetooth/wired headset attach/detach and route selection during a call

**Inspected test evidence**

- [integration_test/scripts/run_production_call_regression.dart](../../integration_test/scripts/run_production_call_regression.dart) — `kx0029` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_regression.dart:8: production_call_surface_regressions.dart:339 compares actual coarse inventory/UI, selects speaker then source-defined available fallback; production_call_regression_criteria.dart:265 validates actual provider equality and same active call. Absent wired/Bluetooth explicitly unavailable; no acoustic/accessory attach proof. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0001, kx0002, kx0003, kx0015, kx0016, kx0017, kx0029, kx0030.
- [test/features/call/presentation/call_audio_output_picker_test.dart](../../test/features/call/presentation/call_audio_output_picker_test.dart) — `hot-plug refresh observes fallback and disposal discards a late inventory` (widget).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/presentation/call_audio_output_picker_test.dart:86: Injected output inventory hot-plug refresh observes fallback and ignores late disposed inventory; native hot-plug event/accessory acoustic outcome absent. Registered: affected-calls, call-signaling, host-all.

**Remaining gaps**

- Campaign proves existing inventory/speaker fallback only. Widget hot-plug is injected; actual accessory attach/detach and audible recovery require available hardware.

#### CALL-006 — Android connected notification handover, tap-return and terminal cleanup preserve audio

**Coverage:** strong. **Execution:** not_run. **Catalog:** VC-003, VC-027.

**Steps**

1. Connect Android call and replace ringing with quiet ongoing.
2. Minimize, native tap back to same call.
3. Hang up and verify exact card/native/audio cleanup.

**Conditions:** platform: available Android physical+emulator; campaign source only; connectivity: disposable local relay/coturn; offline: n/a; app state: foreground; input: fresh mutual contacts/audio call; recovery: n/a.

**Expected:** Android connected notification handover, tap-return and terminal cleanup preserve audio

**Inspected test evidence**

- [integration_test/scripts/run_production_call_regression.dart](../../integration_test/scripts/run_production_call_regression.dart) — `kx0002` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_regression.dart:8: production_call_surface_regressions.dart:291 minimizes/returns via ongoing-card tap; production_call_regression_criteria.dart:398 checks same connected pair/card at all stages, quiet channel and native key. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0001, kx0002, kx0003, kx0015, kx0016, kx0017, kx0029, kx0030.
- [integration_test/scripts/run_production_call_regression.dart](../../integration_test/scripts/run_production_call_regression.dart) — `kx0003` (sims).
  - Real: actual production Android APK call/notification/settings entrypoints; native app-handler/session/OS observations bound to current call.
  - Faked: disposable local relay/coturn fixture and fresh account/contact fixtures; private scenario/control/observation adapter.
  - Proves / registration: integration_test/scripts/run_production_call_regression.dart:8: Same production minimize/return for callee; additionally actual notification publication/event order ensures ongoing foreground before ringing removal. Criteria production_call_regression_criteria.dart:398+; no iOS parity claim. Dispatches android_production_audio_call_campaign.dart with regressionScenario; registered in critical_features.json. No device campaign executed here. Registered: kx0001, kx0002, kx0003, kx0015, kx0016, kx0017, kx0029, kx0030.
- [integration_test/scripts/android_production_audio_call_campaign.dart](../../integration_test/scripts/android_production_audio_call_campaign.dart) — `android.production_1to1_audio_call` (sims).
  - Real: production app semantic start/native answer and real Android WebRTC RTP; same APK; physical Android+emulator; exact call-bound observers; actual native cleanup and bounded evidence validation.
  - Faked: disposable local relay/coturn and fresh contacts; separate host Pion known-Opus oracle; this does not substitute for app RTP.
  - Proves / registration: integration_test/scripts/android_production_audio_call_campaign.dart:539: executeAndroidProductionAudioCallCampaign exercises mute/speaker/emulator hangup and verifies both native calls released. integration_test/support/android_production_audio_call_evidence.dart:448 requires all controls, :465 cleanup, :487 both app RTP directions plus independent Pion fixture. Registered android.production_1to1_audio_call; no human audibility/content fidelity claim or run here. Registered: see cited native runner/manifest.
- [android/app/src/test/kotlin/com/mknoon/app/call/MknoonCallOngoingNotificationHandoverTest.kt](../../android/app/src/test/kotlin/com/mknoon/app/call/MknoonCallOngoingNotificationHandoverTest.kt) — `ongoing notification takes the foreground before the ringing heads-up is cancelled` (unit).
  - Real: actual Kotlin handOverToOngoingCallNotification helper.
  - Faked: recording startForeground/cancel callbacks.
  - Proves / registration: android/app/src/test/kotlin/com/mknoon/app/call/MknoonCallOngoingNotificationHandoverTest.kt:10: Exact startForeground505 then cancel504 ordering; companion refusal keeps ringing card. Third case:46 is source-text wiring assertion only. Registered android-call-native / native.android.unit; no actual OS card by this unit. Registered: see cited native runner/manifest.

**Remaining gaps**

- Registered real Android state/card/order/return/cleanup campaigns cover boundary; all unexecuted in this audit.

#### CALL-007 — iOS system call UI answer/decline/end/mute agrees with in-app ownership

**Coverage:** partial. **Execution:** not_run. **Catalog:** VC-009, VC-014.

**Steps**

1. Use iOS system answer/decline/end/mute.
2. Replay pending native events into Dart.
3. Keep one correct owner, retained mute and terminal cleanup.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** iOS system call UI answer/decline/end/mute agrees with in-app ownership

**Inspected test evidence**

- [ios/RunnerTests/MknoonCallKitLifecycleTests.swift](../../ios/RunnerTests/MknoonCallKitLifecycleTests.swift) — `testAnswerBeforeFlutterPersistsAndReplaysOnceInOrder` (unit).
  - Real: actual Swift native event/journal/controller ordering.
  - Faked: makeRig fake CallKit provider/audio and pending-call backend.
  - Proves / registration: ios/RunnerTests/MknoonCallKitLifecycleTests.swift:569: Answer before Flutter records replay once/in order; adjacent decline/end/reset/terminal races exercise ownership through fake provider. Registered native.ios.runner_tests, not actual system surface/audio. Registered: see cited native runner/manifest.
- [ios/RunnerTests/MknoonCallKitLifecycleTests.swift](../../ios/RunnerTests/MknoonCallKitLifecycleTests.swift) — `testRetiredTerminalReceiptDoesNotReleaseSuccessorAudio` (unit).
  - Real: actual Swift lifecycle/store receipt ownership rules.
  - Faked: makeRig MemoryPendingCallBackend; FakeCallProvider/FakeCallAudio and controlled clock.
  - Proves / registration: ios/RunnerTests/MknoonCallKitLifecycleTests.swift:1255: After old receipt retention and successor answer/adoption/activation, two old ACKs leave successor descriptor/audio intact. Registered native.ios.runner_tests; no actual delayed OS callback or audible successor call. Registered: see cited native runner/manifest.
- [test/features/call/integration/microphone_command_privacy_test.dart](../../test/features/call/integration/microphone_command_privacy_test.dart) — `${direction.name}: mute remains applied through interruption and is restored after an unmute is reversed` (integration).
  - Real: production coordinator/audio/engine and real FFI SQLite.
  - Faked: scripted native WebRTC/session and permission ports.
  - Proves / registration: test/features/call/integration/microphone_command_privacy_test.dart:480: Both direction variants keep enabled=false across interruption and reversed unmute; actual native RTP/audio content not sampled. Registered: affected-calls, host-all.

**Remaining gaps**

- Swift fake-provider journal and Dart command policies do not prove real system CallKit action-to-WebRTC behavior; physical fixtures inactive, not pass.

#### CALL-008 — Peer renaming/contact deletion during call history and callback keeps exact account identity

**Coverage:** strong. **Execution:** host_run. **Catalog:** VC-004, VC-021.

**Steps**

1. Rename/remove contact while history loads or callback awaits.
2. Refresh names and reject stale completion.
3. Dial only current exact account or refuse by policy.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Peer renaming/contact deletion during call history and callback keeps exact account identity

**Fresh host join (2026-10-22)**

- test/features/call/data/call_history_repository_test.dart:103: Real SQL rename preserves stale-page callback account; deletion while callback contact preflight awaits refuses before call-start port; refresh shows Unknown contact, terminal row remains unique. Source 7572deae51a9acd19f9ff8c4a85724931b0c7f41; actual focused completions in header.lever1_host_run. Registered under owning affected lane and host-all. Replaced: outgoing call-start capability port; contact preflight timing gate.

**Inspected test evidence**

- [test/features/call/data/call_history_repository_test.dart](../../test/features/call/data/call_history_repository_test.dart) — `global history pages have one row per call, stable equal-time order, local search and current names` (unit).
  - Real: FFI SQLite history/contact data and production history consumers.
  - Faked: constructed rows and callback owner.
  - Proves / registration: test/features/call/data/call_history_repository_test.dart:178: Actual SQL paging/order/search joins current contact names; real callback capability is replaced with recording starts. Registered: affected-calls, host-all.
- [test/features/call/presentation/calls_page_test.dart](../../test/features/call/presentation/calls_page_test.dart) — `paging renders each call once; refresh reflects rename/removal without clearing unread elsewhere` (widget).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/presentation/calls_page_test.dart:146: Actual Calls widget paging/refresh reflects renamed/removed fixture contact while unrelated unread retained; repository/callback fake, no native call. Registered: affected-calls, call-signaling, host-all.
- [test/features/call/application/call_redial_controller_test.dart](../../test/features/call/application/call_redial_controller_test.dart) — `new callback supersedes A at $stage before canonical admission` (unit).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/application/call_redial_controller_test.dart:288: Seven async stages parameterize cancellation/supersession; latest history/contact/preflight bound before canonical admission. Controlled readiness/history/endpoint/gateway ports. Registered: affected-calls, call-signaling, host-all.
- [test/features/call/presentation/foreground_call_overlay_test.dart](../../test/features/call/presentation/foreground_call_overlay_test.dart) — `unresolved UI fallback never becomes native caller metadata` (widget).
  - Real: production call coordinator/controller/adapter policy.
  - Faked: scripted native WebRTC/audio/permission/route ports; controlled clock and modeled signaling/history seams.
  - Proves / registration: test/features/call/presentation/foreground_call_overlay_test.dart:163: Unresolved UI fallback cannot enter authenticated native name projection; fake contact lookup/capability, real overlay policy. Registered: affected-calls, host-all, ui-approved-recovery-readability.

**Remaining gaps**

- Native provider display-name rendering remains a separate VC-004/VC-010 boundary; no native call/audio proof is inferred from exact logical admission.

**Open questions**

- Scoped host proof only. Device handoff and exact remaining boundaries: docs/testing/astra-lever1-host-quickwins.md. No actual device, signed-candidate or whole affected-lane verdict.

#### IN-001 — The introducer is notified when an introduction is accepted

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-001.

**Steps**

1. Introduce two contacts.
2. Accept one/both sides and deliver response to introducer.
3. Present the correct notification and route on explicit open.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground/background/cold notification open; input: one-side versus mutual accept; recovery: n/a.

**Expected:** Introducer receives role-correct progress/connection notice and opens the intended existing conversation.

**Inspected test evidence**

- [test/features/introduction/application/introduction_listener_test.dart](../../test/features/introduction/application/introduction_listener_test.dart) — `introducer-side mutual acceptance writes a recipient-thread connection message and a role-correct notification` (unit).
  - Real: actual intro processing/system-message/notification role selection.
  - Faked: notification service; in-memory repositories; injected acceptance payload.
  - Proves / registration: test/features/introduction/application/introduction_listener_test.dart:553: Mutual acceptance creates one canonical recipient-thread message and role-correct notification/payload; actual OS presentation/tap is outside the host seam. Registered: affected-surfaces, host-all.
- [integration_test/intro_accept_notification_android_proof_test.dart](../../integration_test/intro_accept_notification_android_proof_test.dart) — `physical_introducer` (e2e).
  - Real: typed captured-artifact validator.
  - Faked: no device actions occur in this validator; relies on externally captured campaign artifact.
  - Proves / registration: integration_test/intro_accept_notification_android_proof_test.dart:17: Validates TC12 physical-introducer artifact captured by run_intro_accept_notification_android.dart; file itself is not a live device journey. No capture or validation executed here. Registered: no automated lane found.
- [test/features/introduction/integration/introduction_multi_node_test.dart](../../test/features/introduction/integration/introduction_multi_node_test.dart) — `introducer heals after partitioned accept deliveries and converges with B and C` (integration).
  - Real: real three-party introduction listeners/state convergence.
  - Faked: FakeP2PNetwork/relay inbox; PassthroughCryptoBridge; in-memory identity/contact/introduction/message repositories.
  - Proves / registration: test/features/introduction/integration/introduction_multi_node_test.dart:1107: Partitioned introducer retains pending until two inbox accept responses drain, then all three participants converge; no real process death or relay durability. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Host notification is a fake service; registered capture validator depends on an external artifact not produced/validated here. Actual OS notice/tap route remains unverified.

#### IN-002 — When both people accept, they become contacts and can chat

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-002.

**Steps**

1. A introduces B and C.
2. Both participants explicitly accept in either order.
3. Create reciprocal contacts and exchange first message.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: fake online/offline; offline: n/a; app state: foreground; input: both accept, either order; recovery: n/a.

**Expected:** Only mutual acceptance creates the B/C contact edge and supports correct chat delivery.

**Inspected test evidence**

- [test/features/introduction/integration/introduction_multi_node_test.dart](../../test/features/introduction/integration/introduction_multi_node_test.dart) — `offline relay intro delivery converges to mutual acceptance and first encrypted chat` (integration).
  - Real: real introduction send/listener/accept/mutual-contact/chat use cases.
  - Faked: FakeP2PNetwork/relay inbox; PassthroughCryptoBridge; in-memory identity/contact/introduction/message repositories.
  - Proves / registration: test/features/introduction/integration/introduction_multi_node_test.dart:790: Both offline participants drain one offer, mutually accept, become contacts and exchange first exact chat text; crypto calls are passthrough and relay is in-memory. Registered: affected-surfaces, host-all.
- [test/features/introduction/integration/introduction_multi_node_test.dart](../../test/features/introduction/integration/introduction_multi_node_test.dart) — `introducer heals after partitioned accept deliveries and converges with B and C` (integration).
  - Real: real three-party introduction listeners/state convergence.
  - Faked: FakeP2PNetwork/relay inbox; PassthroughCryptoBridge; in-memory identity/contact/introduction/message repositories.
  - Proves / registration: test/features/introduction/integration/introduction_multi_node_test.dart:1107: Partitioned introducer retains pending until two inbox accept responses drain, then all three participants converge; no real process death or relay durability. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Real consent orchestration is composed across fake network/in-memory storage/passthrough crypto; native authenticated transport/durable restart and actual users are not established.

#### IN-003 — Either person can decline, and nothing connects

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-003.

**Steps**

1. Receive an introduction offer.
2. Have either participant Pass while the other accepts or remains pending.
3. Ensure no unwanted mutual contact connection appears.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: accept/pass order permutations; recovery: n/a.

**Expected:** Passing prevents mutual connection without changing unrelated existing contacts.

**Inspected test evidence**

- [test/features/introduction/integration/introduction_multi_node_test.dart](../../test/features/introduction/integration/introduction_multi_node_test.dart) — `B accepts, C passes → no mutualAccepted` (integration).
  - Real: real accept/pass state handling.
  - Faked: FakeP2PNetwork/relay inbox; PassthroughCryptoBridge; in-memory identity/contact/introduction/message repositories; missing received intro may be manually seeded.
  - Proves / registration: test/features/introduction/integration/introduction_multi_node_test.dart:211: Asserts C passed after B accepts and C passes; it manually repairs absent input fixtures and does not itself assert both contact repositories are empty. Registered: affected-surfaces, host-all.
- [test/features/introduction/integration/fake_introductions_rejected_test.dart](../../test/features/introduction/integration/fake_introductions_rejected_test.dart) — `blocked senders cannot create new offers while existing responses still reconcile and forged deferred responses are dropped` (integration).
  - Real: actual listener/blocked-contact/deferred-response policy; production FFI SQLite repositories.
  - Faked: PassthroughCryptoBridge; fake P2P and transport identity inputs.
  - Proves / registration: test/features/introduction/integration/fake_introductions_rejected_test.dart:630: New offers from blocked introducer are rejected, existing consent responses still reconcile, and forged deferred responses are discarded; not a secure transport end-to-end proof. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Multi-node pass case asserts passed state and may seed missing offers; it does not independently assert both contact edges absent. Whole three-party durable UI outcome is not joined.

#### IN-004 — Unanswered introductions expire

**Coverage:** strong. **Execution:** not_run. **Catalog:** IN-004.

**Steps**

1. Retain an unanswered introduction beyond its configured lifetime.
2. Invoke expiry/startup repair.
3. Inspect status and verify no contact/message creation.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: pending31-day-old timestamp; recovery: explicit expiry/startup repair invocation.

**Expected:** Stale pending consent becomes expired and never grants an implicit connection.

**Inspected test evidence**

- [test/features/introduction/application/expire_old_introductions_use_case_test.dart](../../test/features/introduction/application/expire_old_introductions_use_case_test.dart) — `repairs stale pending expired rows without creating a contact` (unit).
  - Real: actual expiry/repair policy and status derivation.
  - Faked: in-memory intro/contact/message repositories; constructed31-day-old timestamp.
  - Proves / registration: test/features/introduction/application/expire_old_introductions_use_case_test.dart:102: A stale pending record becomes expired with no other-party contact or messages. Strong only for expiry policy when invoked, not actual background scheduling. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Strong is scoped to expiry policy invoked with a timestamp; real elapsed days, OS wake scheduling and multi-peer expiry synchronization are outside that claim.

#### IN-005 — Repeated or out-of-order messages do not break consent

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-005.

**Steps**

1. Deliver accept/pass before the offer or replay older/duplicate offers.
2. Replay deferred responses when the offer arrives.
3. Inspect each party’s consent/contact state and duplicates.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: late/duplicate/deferred/out-of-order events; recovery: same-intro replay.

**Expected:** Order/replay cannot bypass consent or duplicate contact/system effects.

**Inspected test evidence**

- [test/features/introduction/integration/introduction_multi_node_test.dart](../../test/features/introduction/integration/introduction_multi_node_test.dart) — `late delivery on the same intro replays an earlier accept and converges on A, B, and C without duplicates` (integration).
  - Real: real deferred-response replay/dedup and three-party state.
  - Faked: FakeP2PNetwork/relay inbox; PassthroughCryptoBridge; in-memory identity/contact/introduction/message repositories.
  - Proves / registration: test/features/introduction/integration/introduction_multi_node_test.dart:1198: Late duplicate offer replays prior acceptance and converges all participants without duplicate contact/system rows under the fake network. Registered: affected-surfaces, host-all.
- [test/features/introduction/integration/introduction_multi_node_test.dart](../../test/features/introduction/integration/introduction_multi_node_test.dart) — `introducer heals after partitioned accept deliveries and converges with B and C` (integration).
  - Real: real three-party introduction listeners/state convergence.
  - Faked: FakeP2PNetwork/relay inbox; PassthroughCryptoBridge; in-memory identity/contact/introduction/message repositories.
  - Proves / registration: test/features/introduction/integration/introduction_multi_node_test.dart:1107: Partitioned introducer retains pending until two inbox accept responses drain, then all three participants converge; no real process death or relay durability. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Causal three-party fake-network proofs exist; actual signed malicious/replayed ciphertext and durable process restart are not joined.

#### IN-006 — Fake introductions are rejected

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-006.

**Steps**

1. Submit wrong-recipient/non-party/mismatched-sender offers or responses.
2. Try conflicting trusted key material.
3. Inspect rejected outcome and unchanged contact/introduction state.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: wrong recipient, forged sender, conflicting key material; recovery: n/a.

**Expected:** Forged party/key authority does not create a connection or overwrite trusted keys.

**Inspected test evidence**

- [test/features/introduction/integration/fake_introductions_rejected_test.dart](../../test/features/introduction/integration/fake_introductions_rejected_test.dart) — `wrong-recipient offer and mismatched-sender offer or response are rejected without creating introductions or contacts` (integration).
  - Real: IntroductionListener/handler real identity/party validation; production FFI SQLite repositories and unchanged-state assertions.
  - Faked: PassthroughCryptoBridge; fake P2P/transport sender inputs; secure store.
  - Proves / registration: test/features/introduction/integration/fake_introductions_rejected_test.dart:354: Wrong recipient/forged sender/non-party responses are rejected before SQL side effects; a legitimate offer continues. Actual cryptographic signatures/AEAD are not verified by the passthrough bridge. Registered: affected-surfaces, host-all.
- [test/features/introduction/integration/fake_introductions_rejected_test.dart](../../test/features/introduction/integration/fake_introductions_rejected_test.dart) — `conflicting key authority blocks acceptance and preserves existing trusted contact keys` (integration).
  - Real: real key-authority and consent checks; production SQLite repositories.
  - Faked: PassthroughCryptoBridge; P2P/secure store.
  - Proves / registration: test/features/introduction/integration/fake_introductions_rejected_test.dart:546: Conflicting offered keys prevent acceptance and preserve existing trusted contact keys; actual native crypto is separate. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Real listener/SQL authorization guards are substantive, but PassthroughCryptoBridge does not establish genuine signature/AEAD rejection or authenticated socket identity.

#### IN-007 — Introductions keep existing contacts and conversations intact

**Coverage:** strong. **Execution:** not_run. **Catalog:** IN-007.

**Steps**

1. Keep an existing contact/conversation, including a contact created while consent was pending.
2. Receive an offer or complete mutual acceptance.
3. Compare all retained contact/history fields after processing.

**Conditions:** platform: shared local receiving/preservation boundary; connectivity: n/a; offline: n/a; app state: foreground; input: existing contact before offer or before mutual acceptance; recovery: n/a.

**Expected:** Existing trusted contact identity, preferences/provenance and conversation remain byte/field-equivalent without duplicate connection effects.

**Inspected test evidence**

- [test/features/introduction/integration/existing_contacts_and_conversations_preserved_test.dart](../../test/features/introduction/integration/existing_contacts_and_conversations_preserved_test.dart) — `recipient: mutual acceptance preserves contact created meanwhile` (integration).
  - Real: real production FFI SQLite schema/repositories; handleIncomingIntroduction/handleMutualAcceptance.
  - Faked: FakeSecureKeyStore; direct handler invocation/constructed accepted status.
  - Proves / registration: test/features/introduction/integration/existing_contacts_and_conversations_preserved_test.dart:233: Parameterized test expands recipient/introduced x offer/mutual cases; checks exact incumbent contact map, key/ML-KEM/archive/provenance and one unchanged conversation. No actual network/crypto is needed for this local preservation boundary. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Strong applies to the real local SQL preservation boundary; OS/network delivery and signed-app upgrade are separate.

#### IN-009 — Introductions sent while offline arrive once

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-009.

**Steps**

1. Send an introduction while participants/introducer are offline.
2. Persist fallback work and restore connectivity.
3. Drain once, complete consent and exchange first chat.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: offline then restored; offline: fake relay inbox retention; app state: foreground; input: as described; recovery: outbox/inbox retry.

**Expected:** Intended participants recover retained offers/responses once and all parties converge.

**Inspected test evidence**

- [test/features/introduction/integration/introduction_multi_node_test.dart](../../test/features/introduction/integration/introduction_multi_node_test.dart) — `offline relay intro delivery converges to mutual acceptance and first encrypted chat` (integration).
  - Real: real introduction send/listener/accept/mutual-contact/chat use cases.
  - Faked: FakeP2PNetwork/relay inbox; PassthroughCryptoBridge; in-memory identity/contact/introduction/message repositories.
  - Proves / registration: test/features/introduction/integration/introduction_multi_node_test.dart:790: Both offline participants drain one offer, mutually accept, become contacts and exchange first exact chat text; crypto calls are passthrough and relay is in-memory. Registered: affected-surfaces, host-all.
- [test/features/introduction/integration/introduction_multi_node_test.dart](../../test/features/introduction/integration/introduction_multi_node_test.dart) — `introducer heals after partitioned accept deliveries and converges with B and C` (integration).
  - Real: real three-party introduction listeners/state convergence.
  - Faked: FakeP2PNetwork/relay inbox; PassthroughCryptoBridge; in-memory identity/contact/introduction/message repositories.
  - Proves / registration: test/features/introduction/integration/introduction_multi_node_test.dart:1107: Partitioned introducer retains pending until two inbox accept responses drain, then all three participants converge; no real process death or relay durability. Registered: affected-surfaces, host-all.
- [test/features/introduction/application/introduction_outbound_delivery_test.dart](../../test/features/introduction/application/introduction_outbound_delivery_test.dart) — `failed live send and inbox fallback keeps a failed outbox delivery` (unit).
  - Real: actual durable-delivery/outbox state logic.
  - Faked: fake direct/inbox failures; in-memory introduction repository.
  - Proves / registration: test/features/introduction/application/introduction_outbound_delivery_test.dart:229: Both transport failures leave one failed envelope row with retry payload. Registered: affected-surfaces, host-all.
- [test/features/introduction/application/introduction_outbound_delivery_test.dart](../../test/features/introduction/application/introduction_outbound_delivery_test.dart) — `retryPendingIntroductionDeliveries replays a sent row through inbox` (unit).
  - Real: actual retry selection/cleanup logic.
  - Faked: in-memory outbox; P2P inbox callback.
  - Proves / registration: test/features/introduction/application/introduction_outbound_delivery_test.dart:257: Replays one retained envelope through inbox then removes settled row; no multi-target picker retry UI is asserted. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Relay and repository durability are in-memory in the composed journey; real relay expiry, sender process death and actual peer full flow remain unverified.

#### IN-010 — The introduction picker sends only the chosen contacts

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-010.

**Steps**

1. Open introduction picker for a recipient.
2. Search/select only intended eligible friends.
3. Confirm and inspect exact introduced IDs/progress/result callback.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: two selected friends among filtered candidates; recovery: n/a.

**Expected:** Only chosen eligible friends are introduced to the intended recipient.

**Inspected test evidence**

- [test/features/introduction/presentation/screens/friend_picker_wired_test.dart](../../test/features/introduction/presentation/screens/friend_picker_wired_test.dart) — `loads, searches, selects, sends with progress, and returns introductions to the parent callback` (widget).
  - Real: actual picker search/select/send/progress/callback; real sendIntroductions use case.
  - Faked: fake delayed P2P network; in-memory repositories; bridge crypto.
  - Proves / registration: test/features/introduction/presentation/screens/friend_picker_wired_test.dart:270: Searching then selecting two named friends sends exactly those introduced IDs to the intended recipient and shows1-of2 progress; no real peer outcomes. Registered: affected-surfaces, host-all.
- [test/features/introduction/presentation/screens/friend_picker_wired_test.dart](../../test/features/introduction/presentation/screens/friend_picker_wired_test.dart) — `filters recipient, self, blocked, and archived contacts while keeping eligible friends selectable` (widget).
  - Real: actual picker eligible-contact filtering.
  - Faked: in-memory contacts/identity; P2P.
  - Proves / registration: test/features/introduction/presentation/screens/friend_picker_wired_test.dart:122: Recipient/self/blocked/archived rows are absent while the eligible friend is visible; selection-time predicate only. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Exact chooser dispatch is causal; crypto/network/storage are fake and send-time changed eligibility plus actual receiving participants are not joined.

#### INTRO-001 — Cancel the introduction picker, search/select/deselect and enforce eligible recipients

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-010.

**Steps**

1. Search and select/deselect candidate friends.
2. Inspect self/recipient/blocked/archived eligibility.
3. Close without confirming.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: query/selection/cancel; recovery: n/a.

**Expected:** Eligible selection remains under user control and closing cannot authorize an introduction.

**Inspected test evidence**

- [test/features/introduction/presentation/screens/friend_picker_wired_test.dart](../../test/features/introduction/presentation/screens/friend_picker_wired_test.dart) — `filters recipient, self, blocked, and archived contacts while keeping eligible friends selectable` (widget).
  - Real: actual picker eligible-contact filtering.
  - Faked: in-memory contacts/identity; P2P.
  - Proves / registration: test/features/introduction/presentation/screens/friend_picker_wired_test.dart:122: Recipient/self/blocked/archived rows are absent while the eligible friend is visible; selection-time predicate only. Registered: affected-surfaces, host-all.
- [test/features/introduction/presentation/screens/friend_picker_test.dart](../../test/features/introduction/presentation/screens/friend_picker_test.dart) — `close button triggers onClose` (widget).
  - Real: actual close action.
  - Faked: recording onClose callback and friend fixtures.
  - Proves / registration: test/features/introduction/presentation/screens/friend_picker_test.dart:215: Close invokes its callback; no wired repository/zero-outbound assertion in this screen-only case. Registered: affected-surfaces, host-all, ui-tap-gestures.
- [test/features/introduction/presentation/screens/friend_picker_wired_test.dart](../../test/features/introduction/presentation/screens/friend_picker_wired_test.dart) — `loads, searches, selects, sends with progress, and returns introductions to the parent callback` (widget).
  - Real: actual picker search/select/send/progress/callback; real sendIntroductions use case.
  - Faked: fake delayed P2P network; in-memory repositories; bridge crypto.
  - Proves / registration: test/features/introduction/presentation/screens/friend_picker_wired_test.dart:270: Searching then selecting two named friends sends exactly those introduced IDs to the intended recipient and shows1-of2 progress; no real peer outcomes. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Close screen test only records callback; no wired Cancel-plus-zero-outbox/send assertion found in cited picker tests.

#### INTRO-002 — Select multiple introductions with partial send failure; retry only failed intended targets

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-009.

**Steps**

1. Choose multiple intended introductions.
2. Fail one direct/inbox delivery while another settles.
3. Retry only retained failed work with original intended participants.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: multi-friend send with partial transport failure; recovery: failed-only durable retry.

**Expected:** Partial delivery retains truthful per-envelope work and retry does not repeat settled intended introductions.

**Inspected test evidence**

- [test/features/introduction/presentation/screens/friend_picker_wired_test.dart](../../test/features/introduction/presentation/screens/friend_picker_wired_test.dart) — `loads, searches, selects, sends with progress, and returns introductions to the parent callback` (widget).
  - Real: actual picker search/select/send/progress/callback; real sendIntroductions use case.
  - Faked: fake delayed P2P network; in-memory repositories; bridge crypto.
  - Proves / registration: test/features/introduction/presentation/screens/friend_picker_wired_test.dart:270: Searching then selecting two named friends sends exactly those introduced IDs to the intended recipient and shows1-of2 progress; no real peer outcomes. Registered: affected-surfaces, host-all.
- [test/features/introduction/application/introduction_outbound_delivery_test.dart](../../test/features/introduction/application/introduction_outbound_delivery_test.dart) — `failed live send and inbox fallback keeps a failed outbox delivery` (unit).
  - Real: actual durable-delivery/outbox state logic.
  - Faked: fake direct/inbox failures; in-memory introduction repository.
  - Proves / registration: test/features/introduction/application/introduction_outbound_delivery_test.dart:229: Both transport failures leave one failed envelope row with retry payload. Registered: affected-surfaces, host-all.
- [test/features/introduction/application/introduction_outbound_delivery_test.dart](../../test/features/introduction/application/introduction_outbound_delivery_test.dart) — `retryPendingIntroductionDeliveries replays a sent row through inbox` (unit).
  - Real: actual retry selection/cleanup logic.
  - Faked: in-memory outbox; P2P inbox callback.
  - Proves / registration: test/features/introduction/application/introduction_outbound_delivery_test.dart:257: Replays one retained envelope through inbox then removes settled row; no multi-target picker retry UI is asserted. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Multi-send UI and one-envelope failure/retry are separate tests; no single picker partial-result/failed-only multi-target retry assertion found.

#### INTRO-003 — Restart/expiry/blocked-user changes while consent is pending preserve all participants

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-003, IN-004, IN-007.

**Steps**

1. Leave consent pending then restart/expire/block a participant.
2. Deliver old/new offer and consent responses.
3. Preserve each party’s valid preexisting state without implicit connection.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: restart represented by replay seams; input: pending consent with block/expiry change; recovery: deferred response processing.

**Expected:** Durable consent/expiry/block rules remain truthful across recovery and stale responses.

**Inspected test evidence**

- [test/features/introduction/integration/fake_introductions_rejected_test.dart](../../test/features/introduction/integration/fake_introductions_rejected_test.dart) — `blocked senders cannot create new offers while existing responses still reconcile and forged deferred responses are dropped` (integration).
  - Real: actual listener/blocked-contact/deferred-response policy; production FFI SQLite repositories.
  - Faked: PassthroughCryptoBridge; fake P2P and transport identity inputs.
  - Proves / registration: test/features/introduction/integration/fake_introductions_rejected_test.dart:630: New offers from blocked introducer are rejected, existing consent responses still reconcile, and forged deferred responses are discarded; not a secure transport end-to-end proof. Registered: affected-surfaces, host-all.
- [test/features/introduction/application/expire_old_introductions_use_case_test.dart](../../test/features/introduction/application/expire_old_introductions_use_case_test.dart) — `repairs stale pending expired rows without creating a contact` (unit).
  - Real: actual expiry/repair policy and status derivation.
  - Faked: in-memory intro/contact/message repositories; constructed31-day-old timestamp.
  - Proves / registration: test/features/introduction/application/expire_old_introductions_use_case_test.dart:102: A stale pending record becomes expired with no other-party contact or messages. Strong only for expiry policy when invoked, not actual background scheduling. Registered: affected-surfaces, host-all.
- [test/features/introduction/integration/introduction_multi_node_test.dart](../../test/features/introduction/integration/introduction_multi_node_test.dart) — `late delivery on the same intro replays an earlier accept and converges on A, B, and C without duplicates` (integration).
  - Real: real deferred-response replay/dedup and three-party state.
  - Faked: FakeP2PNetwork/relay inbox; PassthroughCryptoBridge; in-memory identity/contact/introduction/message repositories.
  - Proves / registration: test/features/introduction/integration/introduction_multi_node_test.dart:1198: Late duplicate offer replays prior acceptance and converges all participants without duplicate contact/system rows under the fake network. Registered: affected-surfaces, host-all.
- [test/features/introduction/integration/existing_contacts_and_conversations_preserved_test.dart](../../test/features/introduction/integration/existing_contacts_and_conversations_preserved_test.dart) — `recipient: mutual acceptance preserves contact created meanwhile` (integration).
  - Real: real production FFI SQLite schema/repositories; handleIncomingIntroduction/handleMutualAcceptance.
  - Faked: FakeSecureKeyStore; direct handler invocation/constructed accepted status.
  - Proves / registration: test/features/introduction/integration/existing_contacts_and_conversations_preserved_test.dart:233: Parameterized test expands recipient/introduced x offer/mutual cases; checks exact incumbent contact map, key/ML-KEM/archive/provenance and one unchanged conversation. No actual network/crypto is needed for this local preservation boundary. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Real SQL rejection/preservation and pure expiry are covered separately; no all-three-participants durable cold restart with changed block/expiry and real transport.

### NOTIFY — Notification ingress, routing, unread and privacy

#### DC-005 — Killed recipient gets a notification that opens the right chat

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-005.

**Steps**

1. Kill recipient before sending.
2. Deliver through real provider/background recovery and show one card.
3. Tap and show the triggering message in the exact chat.

**Conditions:** platform: Android provider campaign; iOS proof separate; connectivity: n/a; offline: n/a; app state: killed before delivery versus killed after delivery/before tap; input: as described; recovery: n/a.

**Expected:** Closed recipient receives one intended notice and explicit tap opens correct visible content without implicit loss/read of another chat.

**Inspected test evidence**

- [integration_test/scripts/notification_android_payload_campaign.dart](../../integration_test/scripts/notification_android_payload_campaign.dart) — `notifications.android_payload_campaign` (sims).
  - Real: registered real relay/FCM Android payload custody/permission/channel/cold-open campaign when executed.
  - Faked: campaign setup and controlled OS/network state.
  - Proves / registration: integration_test/scripts/notification_android_payload_campaign.dart:157: Owning full campaign includes staged payload, permission/channel block/recovery and live/provider races. Registered by notifications.android_payload_campaign; no campaign or capture artifact validated here. Source audit does not itself prove killed-before-send presentation. Registered: see cited native runner/manifest.
- [integration_test/notification_tap_message_visible_proof_test.dart](../../integration_test/notification_tap_message_visible_proof_test.dart) — `payload_fast_path_cold_kill` (e2e).
  - Real: captured-artifact validator with required check set.
  - Faked: relies on external capture; performs no device actions.
  - Proves / registration: integration_test/notification_tap_message_visible_proof_test.dart:45: Requires terminated-before-tap/cold-launch/staged-message-visible/no-previsibility-relay-drain flags. Validator alone is not a fresh OS execution. Registered: no automated lane found.
- [integration_test/scripts/run_production_notification_open.dart](../../integration_test/scripts/run_production_notification_open.dart) — `production.notification_open` (sims).
  - Real: real production FCM acceptance/native ingress/card/system tap; warm/cold/same-peer app routes and SQL messages; exact typed artifact criteria.
  - Faked: campaign prepares contacts and another chat; controlled background/kill actions.
  - Proves / registration: integration_test/scripts/run_production_notification_open.dart:20: Criteria production_notification_open_criteria.dart:54 requires all3 cases, one exact native card, correct incoming row before/after, unread->read and actual lifecycle; cold kill:159 precedes real tap and requires fresh invocation. Existing main-app campaign, not run here; candidate store signing remains separate. Registered: production.notification_open, production.notification_tap_latency.

**Remaining gaps**

- Registered provider campaign and artifact validator exist, but no fresh exact killed-before-send provider-to-visible-content artifact audited/executed. Production warm/cold runner kills after receiving the card, so it alone cannot establish killed-before-send.

#### DC-023 — Direct notifications respect routing, unread and privacy controls

**Coverage:** strong. **Execution:** not_run. **Catalog:** DC-023.

**Steps**

1. Receive two peers’ messages/duplicates and open one exact chat.
2. Read/suppress only viewed conversation while preserving other card/unread.
3. Leave/reopen SQL and receive private media with generic preview.

**Conditions:** platform: shared Dart policy with Android host widget/native-channel double; connectivity: n/a; offline: n/a; app state: foreground; input: two peers, duplicate, private media; recovery: screen and real SQLite reopen.

**Expected:** Local routing/read/privacy policy is exact and survives reopen without cross-peer suppression or duplicates.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart](../../test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart) — `DC-023 exact route, unread, card generation and duplicate state survive screen and SQL reopen` (widget).
  - Real: real ConversationWired routing/view tracker; production FFI SQLite repos/reopen; real local notification policy/registry.
  - Faked: native notification channel/card map; P2P/bridge crypto and OS tap.
  - Proves / registration: test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart:48: Two peers notify separately; exact Bob route clears only Bob/read state, Cara card/unread survives, viewed Bob is suppressed, leaving restores posting, reopen/replay creates no duplicate. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart](../../test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart) — `DC-023 encrypted private media persists but notification preview is generic` (widget).
  - Real: real private-policy receive/hydration/SQL and notification copy.
  - Faked: bridge returns controlled decrypted private payload; native card channel.
  - Proves / registration: test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart:203: Private policy is persisted and native request uses generic preview; real ciphertext/native extension/lock-screen is not exercised. Registered: affected-conversation, host-all.
- [test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart](../../test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart) — `DC-023 forced-silent recovery cannot bypass a blocked Messages channel` (widget).
  - Real: real direct notification channel selection and SQL receive.
  - Faked: mock native channel/card implementation; bridge/network.
  - Proves / registration: test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart:174: Blocked primary flag does not reroute forced-silent recovery to another channel; message stays unread. Test explicitly excludes actual OS channel blocking. Registered: affected-conversation, host-all.

**Remaining gaps**

- Strong covers real local Dart/SQL/UI policy; native card map/crypto/provider/channel blocking are mocked and OS presentation remains unverified.

#### GC-007 — Group notifications preserve routing, unread and privacy

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-007.

**Steps**

1. Receive group message/reaction under current membership/mute/privacy.
2. Publish only allowed preview and open exact group.
3. Preserve message unread and cross-group state correctly.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: group chat/announcement message/reaction; mute/current roster; recovery: n/a.

**Expected:** Current group authority controls notification and route, without privacy leak or unrelated unread mutation.

**Inspected test evidence**

- [test/integration/notification_deeplink_integration_test.dart](../../test/integration/notification_deeplink_integration_test.dart) — `UP-010 group push routes only after current local membership is resolved` (integration).
  - Real: actual remote-open preparation/resolver and routing order.
  - Faked: in-memory groups/invites; injected drain installs current member; route callback.
  - Proves / registration: test/integration/notification_deeplink_integration_test.dart:96: Group route waits for drain/current membership before selecting exact group; not actual OS tap/real incoming content. Registered: host-all.
- [test/features/groups/integration/group_notification_projection_lifecycle_test.dart](../../test/features/groups/integration/group_notification_projection_lifecycle_test.dart) — `projection tracks group member mute dissolve key and target lifecycle` (integration).
  - Real: real group notification projection/public fact codec.
  - Faked: in-memory secure store; constructed group/member/key/target changes.
  - Proves / registration: test/features/groups/integration/group_notification_projection_lifecycle_test.dart:138: Projection tracks mute/dissolve/key/roster and excludes private text/key/emoji fields. No native NSE/Android worker or device persistence. Registered: affected-groups, host-all.
- [test/features/groups/integration/group_reaction_notification_pipeline_test.dart](../../test/features/groups/integration/group_reaction_notification_pipeline_test.dart) — `chat and announcement reactions leave message unread state unchanged` (integration).
  - Real: actual group reaction notification listener/gate; durable tone lease files.
  - Faked: tracking group message/in-memory group/reaction repos; notification service/event source.
  - Proves / registration: test/features/groups/integration/group_reaction_notification_pipeline_test.dart:313: Chat and announcement reactions leave message unread/read events unchanged; notification is a recording service, not native provider delivery. Registered: affected-groups, host-all.

**Remaining gaps**

- Projection/routing/unread logic is tested at separate fake native/repository seams; no complete provider-to-native-card-to-current-group visible content journey audited/executed.

#### IN-008 — Tapping the notification opens the introduction without accepting it

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-008.

**Steps**

1. Tap an introduction notification.
2. Resolve role-specific existing conversation or Intros fallback.
3. Keep pending consent until explicit Accept/Pass.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: intro offer/accept notification and unresolved fallback; recovery: n/a.

**Expected:** Notification navigation never automatically grants consent or connects users.

**Inspected test evidence**

- [test/features/push/application/intro_notification_orbit_route_test.dart](../../test/features/push/application/intro_notification_orbit_route_test.dart) — `intro notification route shows persistent nav with orbit active and feed return restores shell` (widget).
  - Real: real Orbit/Feed route/shell transition.
  - Faked: repositories/services and explicit Open intro action.
  - Proves / registration: test/features/push/application/intro_notification_orbit_route_test.dart:80: Intro route activates Orbit and Feed returns to original shell; test does not assert pending consent unchanged/no accept side effect. Registered: affected-push, host-all.

**Remaining gaps**

- Route/shell proof exists but cited route test does not assert unchanged pending consent/zero acceptance; actual OS tap/cold setup is separate.

#### CR-008 — Tapping a request notification opens it without accepting

**Coverage:** partial. **Execution:** not_run. **Catalog:** CR-008.

**Steps**

1. Tap request notification for a pending sender.
2. Materialize the request dialog.
3. Require explicit Accept/Decline before connection.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: pending request notification; recovery: n/a.

**Expected:** Tap reveals consent without creating contact/accepting automatically.

**Inspected test evidence**

- [test/features/contact_request/application/contact_request_notification_materializer_test.dart](../../test/features/contact_request/application/contact_request_notification_materializer_test.dart) — `pending request materializes as a dialog` (widget).
  - Real: actual materializer/Navigator/request dialog.
  - Faked: in-memory request/contact repositories; fake services.
  - Proves / registration: test/features/contact_request/application/contact_request_notification_materializer_test.dart:87: Pending request opens Accept/Decline dialog; companion case requires explicit Accept before contact/conversation. No native notification tap or cold launch. Registered: affected-identity, host-all.

**Remaining gaps**

- Materializer dialog and explicit accept companion are tested with in-memory repos; no full native notification tap and a single zero-autoaccept assertion through cold launch.

#### NOTIFY-001 — Warm and cold notification opens exact direct chat with the triggering content visible

**Coverage:** strong. **Execution:** not_run. **Catalog:** DC-005, DC-023.

**Steps**

1. Receive exact real notification while another chat is open, cold-starting or same-peer.
2. Use actual system tap.
3. Observe one exact sender route, triggering text and unread-before/read-after.

**Conditions:** platform: registered Android production-FCM journey; connectivity: n/a; offline: n/a; app state: warm other-chat, cold-start, same-peer; input: exact run-bound text/card; recovery: n/a.

**Expected:** All three open states show the triggering content in the correct single conversation and preserve underlying other-chat route where appropriate.

**Inspected test evidence**

- [integration_test/scripts/run_production_notification_open.dart](../../integration_test/scripts/run_production_notification_open.dart) — `production.notification_open` (sims).
  - Real: real production FCM acceptance/native ingress/card/system tap; warm/cold/same-peer app routes and SQL messages; exact typed artifact criteria.
  - Faked: campaign prepares contacts and another chat; controlled background/kill actions.
  - Proves / registration: integration_test/scripts/run_production_notification_open.dart:20: Criteria production_notification_open_criteria.dart:54 requires all3 cases, one exact native card, correct incoming row before/after, unread->read and actual lifecycle; cold kill:159 precedes real tap and requires fresh invocation. Existing main-app campaign, not run here; candidate store signing remains separate. Registered: production.notification_open, production.notification_tap_latency.
- [test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart](../../test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart) — `DC-023 exact route, unread, card generation and duplicate state survive screen and SQL reopen` (widget).
  - Real: real ConversationWired routing/view tracker; production FFI SQLite repos/reopen; real local notification policy/registry.
  - Faked: native notification channel/card map; P2P/bridge crypto and OS tap.
  - Proves / registration: test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart:48: Two peers notify separately; exact Bob route clears only Bob/read state, Cara card/unread survives, viewed Bob is suppressed, leaving restores posting, reopen/replay creates no duplicate. Registered: affected-conversation, host-all.

**Remaining gaps**

- Strong denotes meaningful existing campaign assertions, not a passing run. No artifact validated/executed here; iOS and signed-store candidate parity separate.

#### NOTIFY-002 — Foreground exact-chat suppression preserves another peer notification and unread count

**Coverage:** strong. **Execution:** not_run. **Catalog:** DC-023.

**Steps**

1. View peer A while B has unread notification.
2. Receive A/B events and open/leave A.
3. Inspect A-only suppression/read and B preserved card/count.

**Conditions:** platform: local Dart/SQLite/widget boundary; connectivity: n/a; offline: n/a; app state: foreground; input: two peers and duplicate events; recovery: n/a.

**Expected:** Exact viewed chat is suppressed/read without suppressing or clearing another peer.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart](../../test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart) — `DC-023 exact route, unread, card generation and duplicate state survive screen and SQL reopen` (widget).
  - Real: real ConversationWired routing/view tracker; production FFI SQLite repos/reopen; real local notification policy/registry.
  - Faked: native notification channel/card map; P2P/bridge crypto and OS tap.
  - Proves / registration: test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart:48: Two peers notify separately; exact Bob route clears only Bob/read state, Cara card/unread survives, viewed Bob is suppressed, leaving restores posting, reopen/replay creates no duplicate. Registered: affected-conversation, host-all.

**Remaining gaps**

- Strong local policy boundary uses mock native cards/provider; actual system notification replacement and foreground classification are separate.

#### NOTIFY-003 — Tap an older notification generation without cancelling a newer replacement

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-023.

**Steps**

1. Receive a newer replacement while older notification open work is pending.
2. Complete old tap/preparation/cancellation after new generation.
3. Keep newest route/card authority intact.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: older/newer content generation and reversed async completion; recovery: stale exact cancellation.

**Expected:** Stale ordinals/CAS cannot replace newest route or cancel a newer content generation.

**Inspected test evidence**

- [test/core/notifications/local_notification_projection_convergence_test.dart](../../test/core/notifications/local_notification_projection_convergence_test.dart) — `TC-372-04 final canonical facts and revision CAS prevent resurrection and stale cancellation` (unit).
  - Real: actual ledger/registry final-effect CAS; real temp files and production SQL facts.
  - Faked: native publication/cancellation callbacks; controlled late canonical read mutation.
  - Proves / registration: test/core/notifications/local_notification_projection_convergence_test.dart:59: Helper:786 installs newer metadata during final read, refuses stale publication/retirement and preserves newer generation. Other helpers cover read/delete/membership barriers. No real older OS tap/notification replacement. Registered: affected-push, host-all.
- [test/core/notifications/app_root_notification_open_test.dart](../../test/core/notifications/app_root_notification_open_test.dart) — `reverse preparation completion cannot let an older tap replace newer` (unit).
  - Real: NotificationOpenRouteCoordinator ordinal/deferred ownership.
  - Faked: held asynchronous preparation callbacks.
  - Proves / registration: test/core/notifications/app_root_notification_open_test.dart:283: Newer direct context remains deferred when older group preparation completes late; old dispatch settles superseded rather than navigating. Registered: affected-push, host-all, notifications.

**Remaining gaps**

- Real file/SQL CAS and route ordinal proofs are separate; no actual older OS notification tap racing a native newer replacement in one journey.

#### NOTIFY-004 — Deny notification permission or block Messages channel; preserve message delivery and truthful UI

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-023.

**Steps**

1. Deny notification permission or block Messages channel.
2. Receive messages and inspect retained custody/unread without bypass posting.
3. Grant/re-enable and retry eligible notification recovery.

**Conditions:** platform: Android permission/channel; iOS authorization mapping; connectivity: n/a; offline: n/a; app state: foreground; input: denied/authorized-but-OS-disabled or Messages blocked; recovery: grant/re-enable.

**Expected:** Permission/channel denial cannot stop message storage or route around user notification choices; UI reports effective state.

**Inspected test evidence**

- [test/features/push/application/request_push_permission_use_case_test.dart](../../test/features/push/application/request_push_permission_use_case_test.dart) — `returns false when authorizationStatus is denied` (unit).
  - Real: actual permission result mapping.
  - Faked: Firebase request result/native OS status channel.
  - Proves / registration: test/features/push/application/request_push_permission_use_case_test.dart:90: Denied result is false; other cases check effective OS disabled overrides authorized request. No real system prompt/channel mutation here. Registered: affected-push, host-all.
- [test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart](../../test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart) — `DC-023 forced-silent recovery cannot bypass a blocked Messages channel` (widget).
  - Real: real direct notification channel selection and SQL receive.
  - Faked: mock native channel/card implementation; bridge/network.
  - Proves / registration: test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart:174: Blocked primary flag does not reroute forced-silent recovery to another channel; message stays unread. Test explicitly excludes actual OS channel blocking. Registered: affected-conversation, host-all.
- [integration_test/scripts/notification_android_payload_campaign.dart](../../integration_test/scripts/notification_android_payload_campaign.dart) — `notifications.android_payload_campaign` (sims).
  - Real: registered real relay/FCM Android payload custody/permission/channel/cold-open campaign when executed.
  - Faked: campaign setup and controlled OS/network state.
  - Proves / registration: integration_test/scripts/notification_android_payload_campaign.dart:157: Owning full campaign includes staged payload, permission/channel block/recovery and live/provider races. Registered by notifications.android_payload_campaign; no campaign or capture artifact validated here. Source audit does not itself prove killed-before-send presentation. Registered: see cited native runner/manifest.

**Remaining gaps**

- Host seams prove mapping/channel choice and message storage; registered real OS campaign was not executed or artifact-verified.

#### NOTIFY-005 — Direct media/private-media previews do not expose protected content

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-023.

**Steps**

1. Receive direct protected/unsupported media with sensitive text/name fields.
2. Resolve app/NSE/native preview.
3. Inspect only allowed generic preview and retained private policy.

**Conditions:** platform: Dart and Swift NSE resolver; connectivity: n/a; offline: n/a; app state: foreground; input: protected/future/malformed policy, secret caption/file fields; recovery: n/a.

**Expected:** Protected media/caption/filename cannot appear in private preview outputs.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart](../../test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart) — `DC-023 encrypted private media persists but notification preview is generic` (widget).
  - Real: real private-policy receive/hydration/SQL and notification copy.
  - Faked: bridge returns controlled decrypted private payload; native card channel.
  - Proves / registration: test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart:203: Private policy is persisted and native request uses generic preview; real ciphertext/native extension/lock-screen is not exercised. Registered: affected-conversation, host-all.
- [test/features/push/application/show_notification_use_case_test.dart](../../test/features/push/application/show_notification_use_case_test.dart) — `private and unsupported local preview bodies are always generic` (unit).
  - Real: actual preview copy/policy selection.
  - Faked: private/unsupported policy inputs.
  - Proves / registration: test/features/push/application/show_notification_use_case_test.dart:137: Caption canary is replaced by generic Private media for supported/future policy; localized companion cases cover en/de/ar. Registered: affected-push, host-all, notifications.
- [ios/RunnerTests/NotificationPreviewResolverTests.swift](../../ios/RunnerTests/NotificationPreviewResolverTests.swift) — `testPrivateMediaPreviewIsGenericForSupportedLocalesAndMalformedPolicy` (unit).
  - Real: actual Swift NotificationPreviewResolver policy/copy.
  - Faked: MemoryPushKeyReader/MemoryPushDecryptor/MemoryPushDedupeStore; fixture plaintext/native extension lifecycle.
  - Proves / registration: ios/RunnerTests/NotificationPreviewResolverTests.swift:345: Submits secret text/caption/filename plus supported/malformed policy; resolved preview is localized generic without secret/Photo. Not real AEAD, APNs, Keychain or running NSE. Registered: see cited native runner/manifest.

**Remaining gaps**

- Actual copy/resolver assertions exist, but decrypted plaintext/key/native channels use doubles; actual APNs/NSE/lock-screen/signing/privacy settings are not joined.

#### NOTIFY-006 — Group message/reaction notification opens the correct group and exact unread state

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-007.

**Steps**

1. Receive group message or reaction.
2. Tap exact group card after membership preparation.
3. Inspect message read state and reaction-specific unread behavior.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: group message versus reaction; current/removed member; recovery: n/a.

**Expected:** Group identity/current membership routes correctly; reactions do not mutate message unread counts.

**Inspected test evidence**

- [test/integration/notification_deeplink_integration_test.dart](../../test/integration/notification_deeplink_integration_test.dart) — `UP-010 group push routes only after current local membership is resolved` (integration).
  - Real: actual remote-open preparation/resolver and routing order.
  - Faked: in-memory groups/invites; injected drain installs current member; route callback.
  - Proves / registration: test/integration/notification_deeplink_integration_test.dart:96: Group route waits for drain/current membership before selecting exact group; not actual OS tap/real incoming content. Registered: host-all.
- [test/features/groups/integration/group_reaction_notification_pipeline_test.dart](../../test/features/groups/integration/group_reaction_notification_pipeline_test.dart) — `chat and announcement reactions leave message unread state unchanged` (integration).
  - Real: actual group reaction notification listener/gate; durable tone lease files.
  - Faked: tracking group message/in-memory group/reaction repos; notification service/event source.
  - Proves / registration: test/features/groups/integration/group_reaction_notification_pipeline_test.dart:313: Chat and announcement reactions leave message unread/read events unchanged; notification is a recording service, not native provider delivery. Registered: affected-groups, host-all.
- [test/features/groups/integration/group_notification_projection_lifecycle_test.dart](../../test/features/groups/integration/group_notification_projection_lifecycle_test.dart) — `projection tracks group member mute dissolve key and target lifecycle` (integration).
  - Real: real group notification projection/public fact codec.
  - Faked: in-memory secure store; constructed group/member/key/target changes.
  - Proves / registration: test/features/groups/integration/group_notification_projection_lifecycle_test.dart:138: Projection tracks mute/dissolve/key/roster and excludes private text/key/emoji fields. No native NSE/Android worker or device persistence. Registered: affected-groups, host-all.

**Remaining gaps**

- Host route/reaction/projection tests use in-memory repos/native doubles; full real provider/card/tap/SQL exact group read journey not audited/executed.

#### NOTIFY-007 — Group invite notification opens consent without accepting automatically

**Coverage:** partial. **Execution:** not_run. **Catalog:** GC-001, GC-007.

**Steps**

1. Receive a group invite while backgrounded.
2. Tap exact invite identity and recover pending invite.
3. Show consent without silently joining; accept/decline only explicitly.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: single/multi-use invite notification; recovery: n/a.

**Expected:** Notification route retains pending invite authority and cannot itself accept membership.

**Inspected test evidence**

- [test/features/groups/application/group_invite_notification_presenter_test.dart](../../test/features/groups/application/group_invite_notification_presenter_test.dart) — `background invite uses exact copy, route, and provider-compatible identity` (unit).
  - Real: real invite presenter/provider-compatible identity.
  - Faked: notification service; fixed app visibility.
  - Proves / registration: test/features/groups/application/group_invite_notification_presenter_test.dart:27: Invite copy/payload/tag identify exact group+invite and repeated presentations reevaluate visibility; does not accept membership. Registered: affected-groups, host-all.
- [test/features/push/application/resolve_group_notification_route_target_use_case_test.dart](../../test/features/push/application/resolve_group_notification_route_target_use_case_test.dart) — `returns the existing pending invite without draining inbox` (unit).
  - Real: actual group-notification pending-invite resolution.
  - Faked: in-memory group/invite repos; drain callback.
  - Proves / registration: test/features/push/application/resolve_group_notification_route_target_use_case_test.dart:113: Resolves exact existing pending invite without draining or constructing an accepted group; actual consent dialog and real OS open are separate. Registered: affected-push, host-all.

**Remaining gaps**

- Presenter/resolver have exact payload and pending selection proofs; no single native tap->actual dialog->zero-autoaccept assertion or real provider execution.

#### NOTIFY-008 — Introduction/request notification interrupted by onboarding, migration or another route is deferred safely

**Coverage:** partial. **Execution:** not_run. **Catalog:** IN-008, CR-008.

**Steps**

1. Tap request/intro notification while startup/onboarding/migration/another route blocks readiness.
2. Retain the newest exact deferred target.
3. Flush once when permitted; preserve consent and retry limits.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: startup/onboarding/migration/covered route; input: newer versus older deferred target; recovery: readiness flush.

**Expected:** Deferred navigation neither loses target nor bypasses migration/consent or lets old work win.

**Inspected test evidence**

- [test/core/notifications/app_root_notification_open_test.dart](../../test/core/notifications/app_root_notification_open_test.dart) — `concurrent deferred flushes join one handler invocation and consume one attempt` (unit).
  - Real: actual deferred-route one-attempt/coalescing state machine.
  - Faked: route handler/completion gates.
  - Proves / registration: test/core/notifications/app_root_notification_open_test.dart:179: Two flushes join one handler and consume one attempt; no onboarding/migration native UI or real socket readiness. Registered: affected-push, host-all, notifications.
- [test/core/notifications/app_root_notification_open_test.dart](../../test/core/notifications/app_root_notification_open_test.dart) — `reverse preparation completion cannot let an older tap replace newer` (unit).
  - Real: NotificationOpenRouteCoordinator ordinal/deferred ownership.
  - Faked: held asynchronous preparation callbacks.
  - Proves / registration: test/core/notifications/app_root_notification_open_test.dart:283: Newer direct context remains deferred when older group preparation completes late; old dispatch settles superseded rather than navigating. Registered: affected-push, host-all, notifications.
- [test/features/contact_request/application/contact_request_notification_materializer_test.dart](../../test/features/contact_request/application/contact_request_notification_materializer_test.dart) — `pending request materializes as a dialog` (widget).
  - Real: actual materializer/Navigator/request dialog.
  - Faked: in-memory request/contact repositories; fake services.
  - Proves / registration: test/features/contact_request/application/contact_request_notification_materializer_test.dart:87: Pending request opens Accept/Decline dialog; companion case requires explicit Accept before contact/conversation. No native notification tap or cold launch. Registered: affected-identity, host-all.
- [test/features/push/application/intro_notification_orbit_route_test.dart](../../test/features/push/application/intro_notification_orbit_route_test.dart) — `intro notification route shows persistent nav with orbit active and feed return restores shell` (widget).
  - Real: real Orbit/Feed route/shell transition.
  - Faked: repositories/services and explicit Open intro action.
  - Proves / registration: test/features/push/application/intro_notification_orbit_route_test.dart:80: Intro route activates Orbit and Feed returns to original shell; test does not assert pending consent unchanged/no accept side effect. Registered: affected-push, host-all.

**Remaining gaps**

- Coordinator coalescing/ordinal and materializers are separate unit/widget seams; whole interrupted setup/migration native-tap consent journey not joined.

#### NOTIFY-009 — iOS notification extension/app-group handoff and Android headless recovery converge once

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-005, GC-007.

**Steps**

1. Receive APNs/NSE or Android headless payload while main runtime is absent.
2. Stage under exact account/owner and hand off to foreground.
3. Ingest once and display/read exact content without duplicate writer/card.

**Conditions:** platform: iOS APNs/NSE/app-group and Android FCM/headless; connectivity: n/a; offline: n/a; app state: background/terminated -> cold foreground; input: as described; recovery: staged exact-owner handoff.

**Expected:** App-group/headless custody and foreground runtime converge exactly once with current authority.

**Inspected test evidence**

- [integration_test/notification_tap_message_visible_proof_test.dart](../../integration_test/notification_tap_message_visible_proof_test.dart) — `payload_fast_path_cold_kill` (e2e).
  - Real: captured-artifact validator with required check set.
  - Faked: relies on external capture; performs no device actions.
  - Proves / registration: integration_test/notification_tap_message_visible_proof_test.dart:45: Requires terminated-before-tap/cold-launch/staged-message-visible/no-previsibility-relay-drain flags. Validator alone is not a fresh OS execution. Registered: no automated lane found.
- [integration_test/scripts/run_ios_notification_payload_sims.dart](../../integration_test/scripts/run_ios_notification_payload_sims.dart) — `notifications.ios_payload_fast_path` (sims).
  - Real: registered iOS APNs/NSE/app-group staged-payload tap campaign when executed.
  - Faked: controlled campaign state and provider setup.
  - Proves / registration: integration_test/scripts/run_ios_notification_payload_sims.dart:1: Registered APNs/NSE exact-recovery boundary exists; no target/artifact inspected or execution performed here. Swift unit fixtures use memory decryptors, not APNs. Registered: notifications.ios_payload_fast_path.
- [integration_test/scripts/notification_android_payload_campaign.dart](../../integration_test/scripts/notification_android_payload_campaign.dart) — `notifications.android_payload_campaign` (sims).
  - Real: registered real relay/FCM Android payload custody/permission/channel/cold-open campaign when executed.
  - Faked: campaign setup and controlled OS/network state.
  - Proves / registration: integration_test/scripts/notification_android_payload_campaign.dart:157: Owning full campaign includes staged payload, permission/channel block/recovery and live/provider races. Registered by notifications.android_payload_campaign; no campaign or capture artifact validated here. Source audit does not itself prove killed-before-send presentation. Registered: see cited native runner/manifest.
- [test/core/notifications/local_notification_projection_convergence_test.dart](../../test/core/notifications/local_notification_projection_convergence_test.dart) — `TC-372-04 final canonical facts and revision CAS prevent resurrection and stale cancellation` (unit).
  - Real: actual ledger/registry final-effect CAS; real temp files and production SQL facts.
  - Faked: native publication/cancellation callbacks; controlled late canonical read mutation.
  - Proves / registration: test/core/notifications/local_notification_projection_convergence_test.dart:59: Helper:786 installs newer metadata during final read, refuses stale publication/retirement and preserves newer generation. Other helpers cover read/delete/membership barriers. No real older OS tap/notification replacement. Registered: affected-push, host-all.

**Remaining gaps**

- Native campaign machinery/host ledger proofs exist; no current artifact-bound provider/NSE/headless execution audited or performed. Source/validator cannot certify signed artifact or OS delivery.

#### NOTIFY-010 — Post/comment notification retains target and uses existing Feed fallback (Posts UI dormant)

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open a post/comment notification target.
2. Wait for local post observation or bounded fallback timeout.
3. Reveal existing root/Feed and expire unresolved target as defined.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: post/comment target, missing/delayed content; recovery: bounded fallback/expiry.

**Expected:** Coordinator retains exact post/comment target, falls back to Feed intentionally and expires unresolved state; no active Posts-tab claim.

**Inspected test evidence**

- [test/features/posts/phase1/post_notification_open_flow_test.dart](../../test/features/posts/phase1/post_notification_open_flow_test.dart) — `timeout opens Posts with the approved fallback message` (unit).
  - Real: PostNotificationOpenCoordinator/pending target deadlines/AppShellController.
  - Faked: post repository; revealPostsSurface callback; 20ms timeout.
  - Proves / registration: test/features/posts/phase1/post_notification_open_flow_test.dart:138: Despite historical test name, asserts Feed active, stored fallback message and reveal callback. Production application_root.dart:2230 only pops to root; no active Posts-tab/UI claim. Registered: affected-surfaces, host-all.
- [test/features/posts/phase1/post_notification_open_flow_test.dart](../../test/features/posts/phase1/post_notification_open_flow_test.dart) — `pending target expires after the approved budget if the post never arrives` (unit).
  - Real: real pending-target expiry logic.
  - Faked: post repository and shortened60ms budget.
  - Proves / registration: test/features/posts/phase1/post_notification_open_flow_test.dart:160: Unresolved post target and status clear after expiry; no visible active Posts surface exists to certify. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Tests use fake post repository and reveal callback. Production application_root.dart:2230 pops to root; dormant Posts UI is excluded. No rendered post/comment or visible fallback-message claim established.

#### NOTIFY-011 — Notification sound/vibration debounce, silent recovery and duplicate delivery remain correct

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-023, GC-007.

**Steps**

1. Deliver live/remote duplicate and rapid same-conversation events.
2. Recover historical inbox silently while retaining live event tone policy.
3. Inspect exact native first-card sound/vibration flags and later silent updates.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: live/recovered/provider duplicate;10s tone window; recovery: background/inbox reconciliation.

**Expected:** Only eligible unique live events alert within debounce policy; historical recovery/duplicates remain silent without dropping content.

**Inspected test evidence**

- [test/integration/live_direct_notification_integration_test.dart](../../test/integration/live_direct_notification_integration_test.dart) — `a live direct message notifies once with a tone AND confirms the sender` (integration).
  - Real: real P2PService/live staged-message commit/notification policy/confirm path.
  - Faked: bridge callback/crypto; in-memory repositories; notification service.
  - Proves / registration: test/integration/live_direct_notification_integration_test.dart:200: One live event stores/commits one row, emits one audible-policy notification and one ok confirm; actual OS sound/provider absent. Registered: host-all.
- [test/integration/live_direct_notification_integration_test.dart](../../test/integration/live_direct_notification_integration_test.dart) — `a burst from one conversation within the window coalesces to one tone` (integration).
  - Real: actual per-conversation notification tone debounce.
  - Faked: clock advanced5s; bridge/in-memory repos/notification service.
  - Proves / registration: test/integration/live_direct_notification_integration_test.dart:233: Two distinct messages update the card but second is silent, both acknowledged; no actual audible waveform/vibration. Registered: host-all.
- [test/integration/live_direct_notification_integration_test.dart](../../test/integration/live_direct_notification_integration_test.dart) — `a genuine relay-recovered (non-prefixed) sweep entry stays silent` (integration).
  - Real: real staged-inbox recovery callback/policy.
  - Faked: seeded staging/in-memory message repo; bridge/notification service.
  - Proves / registration: test/integration/live_direct_notification_integration_test.dart:265: Recovered non-live entry persists message with zero notification while live-retried path companion remains notifiable. Registered: host-all.
- [integration_test/scripts/run_production_notification_sound.dart](../../integration_test/scripts/run_production_notification_sound.dart) — `production.notification_sound` (sims).
  - Real: registered production S1–S16/native notification flag/card/decision evidence when executed.
  - Faked: controlled fixtures/state; external OS verifier.
  - Proves / registration: integration_test/scripts/run_production_notification_sound.dart:1: production_notification_sound_criteria_test.dart:223,262,284 binds first exact card and distinguishes later silent update; descriptor media fixtures are not playable byte-transfer proof. No live run/audio/vibration observation here. Registered: production.notification_sound.

**Remaining gaps**

- Dart tone policy and native OS-flag campaign assertions are meaningful but no run here. Actual audible output/vibration and iOS signed provider behavior are not established by fake service or descriptor media.

### NAV — Feed, Orbit, rings, search and navigation

#### NAV-001 — Feed/Orbit tab taps and horizontal swipe preserve selected conversation and scroll state

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Switch Feed/Orbit by tab or horizontal swipe.
2. Open/search/focus a surface, then leave and reenter.
3. Observe the defined retained/reset state and usable scroll.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: tab tap versus host horizontal swipe; recovery: reentry.

**Expected:** One retained shell switches correctly; Orbit reentry resets its transient view/search and Feed focus clears according to current behavior.

**Inspected test evidence**

- [test/features/feed/presentation/screens/feed_wired_test.dart](../../test/features/feed/presentation/screens/feed_wired_test.dart) — `orbit re-entry resets to the Inner-Circle view (search state does not survive)` (widget).
  - Real: real retained Feed/Orbit shell, Navigator and search state.
  - Faked: identity/contact/message repositories; P2P/platform services.
  - Proves / registration: test/features/feed/presentation/screens/feed_wired_test.dart:1266: After searching all-chats, leaving and reentering Orbit resets to Inner-Circle and removes search; preservation of search is explicitly not the current contract. Registered: affected-feed, host-all.

**Remaining gaps**

- Current contract intentionally resets transient search/focus; exact scroll/selected-conversation preservation across all navigation paths is not established.

#### NAV-002 — Feed card focus, inline reply, open full chat and back use the correct peer/group

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Focus the intended Feed card and compose an inline reply.
2. Open the full conversation or leave through Back.
3. Observe the correct peer/group, read transition and sibling cards.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: direct/group Feed cards, replied versus no-reply Back; recovery: n/a.

**Expected:** Focus/reply/navigation targets the intended conversation; a replied thread marks read only at the defined leave boundary.

**Inspected test evidence**

- [test/features/feed/presentation/screens/feed_focus_test.dart](../../test/features/feed/presentation/screens/feed_focus_test.dart) — `B2/B4/B5/TC-11: leaving a replied thread via the back affordance commits, removes the card, and marks it read (read deferred to leave)` (widget).
  - Real: actual Feed focus/composer/send/leave UI.
  - Faked: in-memory cleared/message/contact repositories; fake live connection/send transport.
  - Proves / registration: test/features/feed/presentation/screens/feed_focus_test.dart:1162: A reply does not mark unread until leaving; Back then removes only its card and marks that conversation read. Registered: affected-feed, host-all.

**Remaining gaps**

- Causal direct Feed UI proof uses fake transport/repositories; full direct+group open-chat/remote outcome chain remains separate.

#### NAV-003 — Feed silent dismiss, read/commit and resumed unread projection (no Undo UI)

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Dismiss a resting card without replying.
2. Leave a replied focused card.
3. Refresh/resume unread state and admit a later incoming message.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: resting dismiss versus replied commit; recovery: read refresh/resume.

**Expected:** Dismiss hides without marking read; replied leave commits/read-marks. Current UI intentionally has no Undo; later incoming activity may resurface the thread.

**Inspected test evidence**

- [test/features/feed/presentation/screens/feed_swipe_test.dart](../../test/features/feed/presentation/screens/feed_swipe_test.dart) — `TC-24: swipe-left on a RESTING card dismisses — removed, red indicator, NO SnackBar (silent), markCleared(read=false), FEED_CLEAR_DISMISS (NOT COMMIT)` (widget).
  - Real: real swipe arena/card removal and event choice.
  - Faked: in-memory cleared/identity/contact/message repositories.
  - Proves / registration: test/features/feed/presentation/screens/feed_swipe_test.dart:529: Silent dismiss removes the card, records markRead=false and emits dismiss rather than commit; explicitly asserts no SnackBar or Undo affordance. Registered: affected-feed, host-all.
- [test/features/feed/presentation/screens/feed_focus_test.dart](../../test/features/feed/presentation/screens/feed_focus_test.dart) — `B2/B4/B5/TC-11: leaving a replied thread via the back affordance commits, removes the card, and marks it read (read deferred to leave)` (widget).
  - Real: actual Feed focus/composer/send/leave UI.
  - Faked: in-memory cleared/message/contact repositories; fake live connection/send transport.
  - Proves / registration: test/features/feed/presentation/screens/feed_focus_test.dart:1162: A reply does not mark unread until leaving; Back then removes only its card and marks that conversation read. Registered: affected-feed, host-all.
- [test/features/orbit/presentation/screens/orbit_refresh_ordering_test.dart](../../test/features/orbit/presentation/screens/orbit_refresh_ordering_test.dart) — `an older unread snapshot cannot overwrite a read-clear` (widget).
  - Real: actual refresh/read-event arbitration.
  - Faked: held call lookup; fake repositories/listener.
  - Proves / registration: test/features/orbit/presentation/screens/orbit_refresh_ordering_test.dart:256: Delayed old unread result cannot overwrite zero after a read event. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Store-level watermark removal exists separately; there is no current Undo UI to certify. Native resume, durable watermark and live remote arrival are not joined.

#### NAV-004 — Orbit search names/Unicode/group names and clear/close without stale results

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Search active names/groups including mixed scripts.
2. Receive an unrelated row update.
3. Clear/close search and select the intended result.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: friend/group name and Unicode query; recovery: refresh during search and close.

**Expected:** Results and selection remain truthful without stale unrelated rows; closing releases find state as defined.

**Inspected test evidence**

- [test/features/orbit/presentation/screens/orbit_wired_test.dart](../../test/features/orbit/presentation/screens/orbit_wired_test.dart) — `search context is preserved while unrelated friend updates arrive` (widget).
  - Real: real Orbit search field/filter and refresh.
  - Faked: spy contact/message repos; fake listener.
  - Proves / registration: test/features/orbit/presentation/screens/orbit_wired_test.dart:2477: Filtering Bob stays stable through an unrelated Cara arrival; field text and hidden result remain correct. Registered: affected-surfaces, host-all.
- [test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart](../../test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart) — `TC-198-44 group match chips + opens the group conversation` (widget).
  - Real: actual find/chip UI and exact selected group callback.
  - Faked: fixture friends/groups and route callback.
  - Proves / registration: test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart:620: A group-name match yields the group chip and opens that group; not a real group repository/Unicode normalization oracle. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Ordinary name/group causal tests exist; full Unicode normalization/long-name input and real remote update route are not joined.

#### NAV-005 — Orbit filters friends/groups/archived/blocked rows without exposing forbidden actions

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Toggle active/archived/list/ring views.
2. Inspect blocked contacts and archived groups.
3. Activate only permitted chat actions.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: active, archived and blocked contact/group states; recovery: n/a.

**Expected:** Each view contains the right permitted rows and cannot expose an active chat action for forbidden entries.

**Inspected test evidence**

- [test/features/orbit/presentation/screens/orbit_wired_test.dart](../../test/features/orbit/presentation/screens/orbit_wired_test.dart) — `blocked and archived contacts do not expose orbital chat actions` (widget).
  - Real: real Orbit action projection/semantics.
  - Faked: seeded contact repository/platform services.
  - Proves / registration: test/features/orbit/presentation/screens/orbit_wired_test.dart:5641: Only the allowed active contact exposes the Open chat semantics action; blocked/archived fixtures do not. Registered: affected-surfaces, host-all.
- [test/features/orbit/application/inner_circle_items_test.dart](../../test/features/orbit/application/inner_circle_items_test.dart) — `interleaves friends and groups by recency (most-recent first)` (unit).
  - Real: actual mergeInnerCircleItems ordering.
  - Faked: timestamped friend/group inputs.
  - Proves / registration: test/features/orbit/application/inner_circle_items_test.dart:57: All five items interleave in descending activity; no manual membership/order editor is involved. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Representative fake repository fixtures cover action projection; no persisted privacy-state change/restart and all filter combinations joined.

#### NAV-006 — Inner-Circle automatic membership/order; manual editor reachability unresolved

**Coverage:** unknown. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Inspect the implemented Inner-Circle population and ordering.
2. Distinguish spatial sculpt knobs from manual contact membership/order.
3. Confirm any intended cancel/commit/restart editor entry before claiming coverage.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: active friend/group recency; proposed manual edit; recovery: n/a.

**Expected:** Current source derives active friends/groups by recency; manual membership/order editing requires a confirmed product entry.

**Inspected test evidence**

- [test/features/orbit/application/inner_circle_items_test.dart](../../test/features/orbit/application/inner_circle_items_test.dart) — `interleaves friends and groups by recency (most-recent first)` (unit).
  - Real: actual mergeInnerCircleItems ordering.
  - Faked: timestamped friend/group inputs.
  - Proves / registration: test/features/orbit/application/inner_circle_items_test.dart:57: All five items interleave in descending activity; no manual membership/order editor is involved. Registered: affected-surfaces, host-all.

**Remaining gaps**

- lib/features/orbit/application/inner_circle_items.dart:5 derives membership/order. Inspected Orbit callbacks expose geometry editing, not a manual membership/reorder editor.

**Open questions**

- Is manual Inner-Circle membership/order editing implemented anywhere? No entry discovered; do not treat it as a shipped missing test or a planned commitment without an owner decision.

#### NAV-007 — Orbit radial/list presentation and geometry preferences preserve selected people

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Switch radial/list presentation and edit geometry.
2. Close/reopen or reset the surface.
3. Inspect retained people/groups and persisted geometry.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: ring/arc/list and geometry knobs; recovery: remount/reset.

**Expected:** Spatial preferences survive remount/reset as defined and do not change account/contact ownership.

**Inspected test evidence**

- [test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart](../../test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart) — `TC-198-33 sculpt persists across a remount` (widget).
  - Real: actual sculpt control and surface remount.
  - Faked: spy/fake secure store; fixture nodes.
  - Proves / registration: test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart:500: A knob edit survives dispose/remount from stored geometry; actual keychain/process restart and manual membership are not tested. Registered: affected-surfaces, host-all.
- [test/features/orbit/application/inner_circle_items_test.dart](../../test/features/orbit/application/inner_circle_items_test.dart) — `interleaves friends and groups by recency (most-recent first)` (unit).
  - Real: actual mergeInnerCircleItems ordering.
  - Faked: timestamped friend/group inputs.
  - Proves / registration: test/features/orbit/application/inner_circle_items_test.dart:57: All five items interleave in descending activity; no manual membership/order editor is involved. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Geometry remount uses a fake store; actual process restart plus all contact/group selection identities across layouts is not joined.

#### NAV-008 — Open Calls/settings/My QR/Scan from Orbit and return without duplicate retained shells

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open Settings, Calls, My QR or Scan from Orbit.
2. Try repeated taps while a route is opening.
3. Return and enter again from the retained shell.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: Orbit auxiliary entries and rapid taps; recovery: Back/reopen.

**Expected:** The intended single route opens and returns to the existing shell without duplicate retained routes.

**Inspected test evidence**

- [test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart](../../test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart) — `T8: My QR from Settings reaches the display; close returns to the same Settings; ScanFriendCard cross-link opens the scanner` (widget).
  - Real: real Orbit->Settings->QR display/scan routes.
  - Faked: signing bridge; identity/contact/storage/P2P services; scanner capture.
  - Proves / registration: test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart:547: Closing QR returns to the same Settings route; reopening and cross-linking opens one scanner screen. No native camera scan. Registered: affected-identity, affected-surfaces, host-all.
- [test/features/orbit/presentation/screens/orbit_settings_entry_test.dart](../../test/features/orbit/presentation/screens/orbit_settings_entry_test.dart) — `TC-206-06 rapid taps push exactly one settings route` (widget).
  - Real: actual Settings entry/navigation latch.
  - Faked: repository/platform dependencies.
  - Proves / registration: test/features/orbit/presentation/screens/orbit_settings_entry_test.dart:353: Rapid entry taps push a single Settings route; companion Back/reopen cases retain Orbit. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Settings/QR routing is causally asserted with fake services; native scan and full Calls/settings/QR lifecycle matrix are separate.

#### NAV-009 — Conversation drafts, quoted reply and edit state survive navigation with correct account ownership

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Compose an unsent draft/quote/edit in a conversation surface.
2. Navigate away, switch focused peer and return.
3. Finish/retry only under the correct account and conversation owner.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: unsent text, quote/edit and peer/account switch; recovery: close/reopen.

**Expected:** Draft state survives its supported navigation boundary without crossing peers/accounts or duplicating sends.

**Inspected test evidence**

- [test/features/feed/presentation/screens/feed_async_state_regression_test.dart](../../test/features/feed/presentation/screens/feed_async_state_regression_test.dart) — `feed draft survives closing and reopening its reply card` (widget).
  - Real: actual Feed card focus and draft state.
  - Faked: fixture repositories/services.
  - Proves / registration: test/features/feed/presentation/screens/feed_async_state_regression_test.dart:271: Closing/reopening the same focused card retains exact unsent text; companion case isolates drafts across cards. Quote/edit/account-rebind is outside this case. Registered: affected-feed, host-all.

**Remaining gaps**

- Exact Feed text draft restore is asserted; quotes/edits/account rebind across full navigation are not all established by the cited test.

#### NAV-010 — Resume/restart Feed/Orbit refreshes messages, avatars, groups and unread without duplicates

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Keep a delayed refresh while rows/read/avatar/group metadata change.
2. Resume or reopen Feed/Orbit.
3. Apply only current owned state without duplicate/stale rows.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: retained shell/resume/restart; input: overlapping old/new snapshots; recovery: latest authoritative refresh.

**Expected:** Old async completion cannot resurrect deleted rows or overwrite newer unread state.

**Inspected test evidence**

- [test/features/orbit/presentation/screens/orbit_refresh_ordering_test.dart](../../test/features/orbit/presentation/screens/orbit_refresh_ordering_test.dart) — `FIFO completion cannot resurrect a deleted contact` (widget).
  - Real: actual Orbit async refresh projection.
  - Faked: stepped FIFO repository queries; fake listener/services.
  - Proves / registration: test/features/orbit/presentation/screens/orbit_refresh_ordering_test.dart:226: A stale in-flight refresh completes after contact deletion and cannot resurrect the row. Registered: affected-surfaces, host-all.
- [test/features/orbit/presentation/screens/orbit_refresh_ordering_test.dart](../../test/features/orbit/presentation/screens/orbit_refresh_ordering_test.dart) — `an older unread snapshot cannot overwrite a read-clear` (widget).
  - Real: actual refresh/read-event arbitration.
  - Faked: held call lookup; fake repositories/listener.
  - Proves / registration: test/features/orbit/presentation/screens/orbit_refresh_ordering_test.dart:256: Delayed old unread result cannot overwrite zero after a read event. Registered: affected-surfaces, host-all.
- [test/features/orbit/presentation/screens/orbit_wired_test.dart](../../test/features/orbit/presentation/screens/orbit_wired_test.dart) — `search context is preserved while unrelated friend updates arrive` (widget).
  - Real: real Orbit search field/filter and refresh.
  - Faked: spy contact/message repos; fake listener.
  - Proves / registration: test/features/orbit/presentation/screens/orbit_wired_test.dart:2477: Filtering Bob stays stable through an unrelated Cara arrival; field text and hidden result remain correct. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Causal host race proofs exist with stepped/fake repositories; native process restart and all avatar/group projections are not one end-to-end assertion.

#### NAV-011 — Navigation during pending request/invite/recovery does not stack duplicate dialogs

**Coverage:** partial. **Execution:** not_run. **Catalog:** none.

**Steps**

1. Receive a pending request/invite while Feed and Orbit are retained.
2. Navigate/toggle/suppress and release presentation.
3. Present each consent dialog once without granting implicit acceptance.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: one broadcast with two shell subscribers; suppressed pending request; recovery: tab reentry/suppression release.

**Expected:** One presentation owner shows a single pending dialog and correctly replays suppressed work.

**Inspected test evidence**

- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-005 one event with Feed and embedded Orbit mounted opens one dialog route` (widget).
  - Real: production Feed/retained Orbit, ContactRequestListener and ContactRequestDialog; current FFI SQLite repositories and real Ed25519 signatures.
  - Faked: P2P/native services and lookup-table request encryption.
  - Proves / registration: Both retained shell subscribers receive the broadcast but share one dialog presentation owner. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/018-shell-persistence.log. Registered: affected-identity, host-all.
- [test/features/contact_request/presentation/screens/pending_request_shell_test.dart](../../test/features/contact_request/presentation/screens/pending_request_shell_test.dart) — `CR-003 suppression release reveals a missed request with shell subscribers retained` (widget).
  - Real: production Feed/retained Orbit, ContactRequestListener and ContactRequestDialog; current FFI SQLite repositories and real Ed25519 signatures.
  - Faked: P2P/native services and lookup-table request encryption.
  - Proves / registration: Observable gate release replays the missed durable pending row into one dialog while Feed and Orbit remain subscribed; tab switching grants no contact. Fresh host PASS, 0 skips: .codex-test-logs/groupB-fixes/018-shell-persistence.log. Registered: affected-identity, host-all.

**Remaining gaps**

- Request-shell deduplication and suppression-release navigation are active passing guards. Other pending group invite/recovery surfaces still need their own assertions, so this broader journey remains Partial.
- Host SQL/signatures and real retained shell do not establish OS/native multi-peer behavior.

### SHARE — External share and received-media forwarding

#### SHARE-001 — Cold external text share: choose direct recipient, send and verify recipient content

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Cold-launch from external text/URL share.
2. Choose a direct recipient and confirm Send.
3. Verify the selected recipient receives exact content once.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: cold external launch; input: text or URL; recovery: n/a.

**Expected:** The retained share reaches only the selected recipient with exact text.

**Inspected test evidence**

- [test/core/services/share_intent_service_test.dart](../../test/core/services/share_intent_service_test.dart) — `1e: getInitialIntent handles cold-start text shares` (unit).
  - Real: ShareIntentService parsing.
  - Faked: plugin initial-media callback/cache/reset.
  - Proves / registration: test/core/services/share_intent_service_test.dart:205: Controlled plugin URL input becomes a text share; actual native cold launch is not exercised. Registered: affected-transport, host-all.
- [test/features/share/integration/share_to_contact_smoke_test.dart](../../test/features/share/integration/share_to_contact_smoke_test.dart) — `6a: share text can target multiple selected recipients from the picker` (integration).
  - Real: real picker selection/action/Navigator.
  - Faked: recording fail-all delivery coordinator; identity/contact/group repositories.
  - Proves / registration: test/features/share/integration/share_to_contact_smoke_test.dart:242: Exactly selected contact/group targets and text reach the coordinator once. The coordinator deliberately fails all targets, so this is not delivered-recipient evidence. Registered: affected-identity, affected-media, host-all.

**Remaining gaps**

- Plugin input and coordinator are substituted; selection/text dispatch is proven, final remote recipient content and native launch are not.

#### SHARE-002 — Warm external image/video share with caption reaches the selected direct recipient

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Share image/video into the warm app.
2. Edit caption and select a direct recipient.
3. Upload/send and open received media with caption.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: warm app/open conversation; input: image/video and caption; recovery: n/a.

**Expected:** The selected recipient gets full correct media and exact edited caption.

**Inspected test evidence**

- [test/core/services/share_intent_service_test.dart](../../test/core/services/share_intent_service_test.dart) — `1f: getInitialIntent handles warm-start style mixed shares` (unit).
  - Real: ShareIntentService text/file grouping.
  - Faked: plugin initial-media callback.
  - Proves / registration: test/core/services/share_intent_service_test.dart:224: Caption and image path survive parsing, without opening/uploading/decoding the file. Registered: affected-transport, host-all.
- [test/features/share/presentation/share_target_picker_wired_test.dart](../../test/features/share/presentation/share_target_picker_wired_test.dart) — `edited caption is sent from the recipient picker` (widget).
  - Real: real editable picker caption/action.
  - Faked: recording coordinator and repositories.
  - Proves / registration: test/features/share/presentation/share_target_picker_wired_test.dart:583: Edited caption reaches the coordinator; no remote recipient content assertion. Registered: affected-media, host-all.
- [test/features/share/application/share_batch_delivery_coordinator_test.dart](../../test/features/share/application/share_batch_delivery_coordinator_test.dart) — `stalled shared video is skipped without sending its raw source` (unit).
  - Real: ImageProcessor deadline/coordinator sibling selection.
  - Faked: never-finishing native compressor; send callback and repositories; synthetic source bytes.
  - Proves / registration: test/features/share/application/share_batch_delivery_coordinator_test.dart:2341: A30ms processing stall skips video and only sibling photo is passed to send; raw stalled video is not sent. Registered: affected-media, host-all, strict-group-media-manifest.

**Remaining gaps**

- Parsing/editing/processing refusal are real at their seams; native source URI/codec and actual recipient full decode+caption are not joined.

#### SHARE-003 — External share to selected groups and direct contacts preserves only selected targets

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Select a subset of contacts and writable groups.
2. Confirm once and revalidate targets at dispatch.
3. Observe per-target outcomes without sending to unselected targets.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: multiple direct/group selections and changed authority; recovery: n/a.

**Expected:** Only selected currently authorized targets receive a share and outcomes remain target-specific.

**Inspected test evidence**

- [test/features/share/integration/share_to_contact_smoke_test.dart](../../test/features/share/integration/share_to_contact_smoke_test.dart) — `6a: share text can target multiple selected recipients from the picker` (integration).
  - Real: real picker selection/action/Navigator.
  - Faked: recording fail-all delivery coordinator; identity/contact/group repositories.
  - Proves / registration: test/features/share/integration/share_to_contact_smoke_test.dart:242: Exactly selected contact/group targets and text reach the coordinator once. The coordinator deliberately fails all targets, so this is not delivered-recipient evidence. Registered: affected-identity, affected-media, host-all.
- [test/features/groups/application/group_media_batch_forward_authorization_test.dart](../../test/features/groups/application/group_media_batch_forward_authorization_test.dart) — `GBF-04 own-member removal in final snapshot prevents upload` (unit).
  - Real: actual group forwarding authorization/final reload.
  - Faked: harness repositories with injected membership mutation; bridge/process/send counters.
  - Proves / registration: test/features/groups/application/group_media_batch_forward_authorization_test.dart:68: Removing the local member at final snapshot denies before every upload/delivery side effect; adjacent role/key drift cases cover demotion/key changes. Registered: affected-groups, host-all.

**Remaining gaps**

- Picker dispatch uses a fail-all recording coordinator; actual network/recipient fanout is not asserted by this test. Group final-authority evidence is separate.

#### SHARE-004 — Cancel share sheet, deselect targets and back out without sending

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Select/deselect recipients then cancel or Back before delivery.
2. Return to the previous route.
3. Verify no empty/cancelled batch sends.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: cancel/empty selection; recovery: route dismissal.

**Expected:** Cancelling before send dismisses safely and unselected targets receive no operation.

**Inspected test evidence**

- [test/features/share/presentation/share_target_picker_wired_test.dart](../../test/features/share/presentation/share_target_picker_wired_test.dart) — `2p: cancel pops back to the previous screen` (widget).
  - Real: real routed picker and Cancel action.
  - Faked: repositories/P2P/bridge/processors.
  - Proves / registration: test/features/share/presentation/share_target_picker_wired_test.dart:1441: Cancel returns to launcher and removes picker; this particular case does not assert a zero-send counter. Registered: affected-media, host-all.
- [test/features/share/application/share_batch_delivery_coordinator_test.dart](../../test/features/share/application/share_batch_delivery_coordinator_test.dart) — `does nothing when no targets are selected` (unit).
  - Real: actual coordinator target admission.
  - Faked: repository/bridge/send seams.
  - Proves / registration: test/features/share/application/share_batch_delivery_coordinator_test.dart:202: An empty selection performs no delivery; complements UI cancel but does not model native external-share cancellation. Registered: affected-media, host-all, strict-group-media-manifest.
- [test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart](../../test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart) — `batch forward action is nullable reentry guarded and cancel preserves exact selection` (widget).
  - Real: actual library selection/route reentry guard.
  - Faked: strict fake library repository; held launch callback.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart:516: Without callback no Forward action; with callback double tap launches once and cancelled route retains exactly two selected identities. Production callback wiring exists at conversation_wired.dart:7391. Registered: affected-conversation, host-all.

**Remaining gaps**

- Zero targets and library-cancel selection are causally asserted; external Cancel widget case only checks navigation and lacks a send counter/native incoming-share cancellation assertion.

#### SHARE-005 — External share before identity setup resumes after onboarding with consent intact

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Receive an external share before identity exists.
2. Complete setup and explicitly accept the first contact.
3. Resume the original picker and require Send consent.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: unsettled/fresh onboarding; input: buffered external text; recovery: identity/contact setup completion.

**Expected:** The buffered share waits through setup and never sends automatically or loses original content.

**Inspected test evidence**

- [test/features/share/integration/share_to_contact_smoke_test.dart](../../test/features/share/integration/share_to_contact_smoke_test.dart) — `6g2: cold start with needsIdentity shows picker only after onboarding and first contact` (integration).
  - Real: StartupRouter/identity/first-time UI and share settlement.
  - Faked: native identity/ML-KEM and microphone gateway; repositories/P2P/signing; injected contact request.
  - Proves / registration: test/features/share/integration/share_to_contact_smoke_test.dart:497: Buffered text remains hidden until identity setup and explicit request acceptance; then picker shows the original share text. No native extension/secure-store/remote send. Registered: affected-identity, affected-media, host-all.

**Remaining gaps**

- Real app UI orchestration is exercised, but identity/permissions/repositories/native share and transport are fake; no real extension-to-recipient journey.

#### SHARE-006 — Multiple shared items preserve order, captions and correct MIME; unsupported input fails safely

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Import multiple supported/mixed files.
2. Preserve order and caption while identifying MIME/size/processing refusals.
3. Send only accepted items and report refused siblings.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: multiple images/video/GIF/PDF and unsupported files; recovery: partial preprocessing failure.

**Expected:** Accepted items retain correct identity/order/caption; unsupported or unprocessed sources do not become false successful sends.

**Inspected test evidence**

- [test/features/share/integration/share_to_contact_smoke_test.dart](../../test/features/share/integration/share_to_contact_smoke_test.dart) — `6f: share multiple images preserves all file paths` (integration).
  - Real: picker file-intent dispatch.
  - Faked: recording fail-all delivery coordinator; file fixtures and repositories.
  - Proves / registration: test/features/share/integration/share_to_contact_smoke_test.dart:379: All selected source paths reach the coordinator; neither native MIME/bytes nor final recipient ordering is established. Registered: affected-identity, affected-media, host-all.
- [test/features/share/application/share_batch_delivery_coordinator_test.dart](../../test/features/share/application/share_batch_delivery_coordinator_test.dart) — `414: a shared non-PDF document is skipped and a real PDF is kept` (unit).
  - Real: coordinator document signature/extension gating; actual temporary files.
  - Faked: send callback and repositories; PDF is header-only test file.
  - Proves / registration: test/features/share/application/share_batch_delivery_coordinator_test.dart:2011: With document-send flag on, non-PDF/fake-PDF are skipped and only signature-valid PDF reaches send; flag-off case rejects even that PDF. Does not render a valid full document. Registered: affected-media, host-all, strict-group-media-manifest.
- [test/features/share/application/share_batch_delivery_coordinator_test.dart](../../test/features/share/application/share_batch_delivery_coordinator_test.dart) — `stalled shared video is skipped without sending its raw source` (unit).
  - Real: ImageProcessor deadline/coordinator sibling selection.
  - Faked: never-finishing native compressor; send callback and repositories; synthetic source bytes.
  - Proves / registration: test/features/share/application/share_batch_delivery_coordinator_test.dart:2341: A30ms processing stall skips video and only sibling photo is passed to send; raw stalled video is not sent. Registered: affected-media, host-all, strict-group-media-manifest.

**Remaining gaps**

- Path ordering and input gating are tested independently; actual multi-item native grants, codecs and recipient MIME/order/full-open outcome remain unjoined. PDF send is flag-gated default off.

#### SHARE-007 — External file URI access expires or permission is denied: truthful recovery and no dropped success

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Receive a shared file URI.
2. Expire/deny access or fail cache copying before send.
3. Observe safe content handling and truthful retry/failure.

**Conditions:** platform: Android URI guard; shared Dart buffer; connectivity: n/a; offline: n/a; app state: foreground; input: unreadable/expired provider grant; recovery: copy/access failure.

**Expected:** Unreadable input cannot be sent as successful media and any retained readable content/fallback remains honest.

**Inspected test evidence**

- [android/app/src/test/kotlin/com/mknoon/app/ShareIntentReadabilityGuardTest.kt](../../android/app/src/test/kotlin/com/mknoon/app/ShareIntentReadabilityGuardTest.kt) — `414 an unreadable single share becomes a plain launch` (unit).
  - Real: Android Intent sanitizer and Robolectric runtime.
  - Faked: injected canRead URI predicate; provider/files unavailable fixture.
  - Proves / registration: android/app/src/test/kotlin/com/mknoon/app/ShareIntentReadabilityGuardTest.kt:35: Unreadable stream becomes plain ACTION_MAIN with no MIME/stream; adjacent case preserves text-only share. No real expiring URI grant or app-visible recovery notification. Registered: see cited native runner/manifest.
- [test/core/services/share_intent_service_test.dart](../../test/core/services/share_intent_service_test.dart) — `1i4: bufferIntent falls back to original path if copy fails` (unit).
  - Real: real buffering/cache copy fallback.
  - Faked: nonexistent original file path.
  - Proves / registration: test/core/services/share_intent_service_test.dart:135: Failed copy leaves the original nonexistent path buffered. This is current behavior, not proof of truthful visible error or durable readability. Registered: affected-transport, host-all.

**Remaining gaps**

- Robolectric sanitization uses a predicate and missing provider. Buffer fallback deliberately retains an inaccessible original path; no actual expired grant plus visible recovery/no-false-success assertion. iOS grant lifetime is not verified.

#### SHARE-008 — Forward one received ordinary image/video to another contact without forwarding private content

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open ordinary received image/video Forward.
2. Edit the copied caption and select another contact.
3. Revalidate source privacy/deletion before dispatch.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: ordinary image/video versus private/deleted transition; recovery: dispatch revalidation.

**Expected:** Eligible ordinary content forwards under fresh ownership; private/deleted drift releases no source bytes.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart](../../test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart) — `forward action launches existing picker with editable source caption` (widget).
  - Real: real received-media forward action and picker route.
  - Faked: repositories/P2P/bridge; native media services.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart:565: A qualified ordinary received source opens the existing picker with editable caption; not real remote byte transfer/decode. Registered: affected-conversation, host-all.
- [test/features/share/application/share_batch_delivery_coordinator_test.dart](../../test/features/share/application/share_batch_delivery_coordinator_test.dart) — `direct picker authority fails all targets before preprocessing or send after parent delete/private transition` (unit).
  - Real: actual coordinator final source-authority check.
  - Faked: in-memory source/message/media/contact/group repos; processing/send recording seams.
  - Proves / registration: test/features/share/application/share_batch_delivery_coordinator_test.dart:249: Deleted/private source drift refuses all targets before preprocessing or any direct/group send; no private bytes are released by this tested boundary. Registered: affected-media, host-all, strict-group-media-manifest.

**Remaining gaps**

- UI and authority boundary have causal tests; actual native video/image decode, network crypto and destination full-open/caption are not one asserted journey.

#### SHARE-009 — Batch-forward selected direct-library items with partial failure and retry failed targets only

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Select direct-library items and launch batch forward.
2. Edit independent captions and choose recipients.
3. Retry failed cells only; cancel without losing source selection.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: multiple sources/targets and sparse failures; recovery: failed-only retry/cancel.

**Expected:** Each selected source-target cell has stable identity and truthful sent/queued/failed status; retry does not replay settled cells.

**Inspected test evidence**

- [test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart](../../test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart) — `failed-cell retry is sparse and preserves each source caption and token` (unit).
  - Real: actual source-target matrix/retry coordinator.
  - Faked: source revalidator; contact repository; strict deliver callback.
  - Proves / registration: test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart:504: Only failed source-target cells retry with original token/latest source caption; settled sent/queued cells remain unchanged. Registered: affected-media, host-all.
- [test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart](../../test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart) — `picker retries the exact sparse failed cells without replaying settled cells` (widget).
  - Real: real picker progress/selection/retry UI.
  - Faked: scripted delivery coordinator and contact repository.
  - Proves / registration: test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart:408: Four-cell initial matrix retries two failed cells and preserves settled/queued cells; transport results are supplied. Registered: affected-media, host-all.
- [test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart](../../test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart) — `batch forward action is nullable reentry guarded and cancel preserves exact selection` (widget).
  - Real: actual library selection/route reentry guard.
  - Faked: strict fake library repository; held launch callback.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart:516: Without callback no Forward action; with callback double tap launches once and cancelled route retains exactly two selected identities. Production callback wiring exists at conversation_wired.dart:7391. Registered: affected-conversation, host-all.

**Remaining gaps**

- Production launch is wired, but matrix send results/source qualification are substituted at coordinator seams; no real multi-recipient full-media convergence/decoder assertion.

#### SHARE-010 — Forward selected group-library items to groups/contacts without leaking removed or private content

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Select eligible group/announcement-library items.
2. Choose current writable groups/contacts and edit captions.
3. Recheck source/destination authority and retry failed cells.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: discussion/announcement sources and target role/membership drift; recovery: dispatch revalidation and sparse retry.

**Expected:** Forwarded copies preserve per-target ownership while removed/private/unauthorized content cannot escape.

**Inspected test evidence**

- [test/features/groups/application/group_media_batch_forward_delivery_test.dart](../../test/features/groups/application/group_media_batch_forward_delivery_test.dart) — `GBF-07 partial retry is idempotent at the source-target cell` (unit).
  - Real: actual group batch matrix and dedup-key handling.
  - Faked: revalidate source callback; single-delivery callback.
  - Proves / registration: test/features/groups/application/group_media_batch_forward_delivery_test.dart:13: Source-target failure retries once with same operation identity while sent/queued cells are preserved. Registered: affected-groups, host-all.
- [test/features/groups/application/group_media_batch_forward_authorization_test.dart](../../test/features/groups/application/group_media_batch_forward_authorization_test.dart) — `GBF-04 own-member removal in final snapshot prevents upload` (unit).
  - Real: actual group forwarding authorization/final reload.
  - Faked: harness repositories with injected membership mutation; bridge/process/send counters.
  - Proves / registration: test/features/groups/application/group_media_batch_forward_authorization_test.dart:68: Removing the local member at final snapshot denies before every upload/delivery side effect; adjacent role/key drift cases cover demotion/key changes. Registered: affected-groups, host-all.
- [test/features/share/presentation/announcement_batch_forward_target_policy_test.dart](../../test/features/share/presentation/announcement_batch_forward_target_policy_test.dart) — `real route sends edited draft to selected target through coordinator once` (widget).
  - Real: actual group batch route, edited captions, selection and wake-lock cleanup.
  - Faked: recording delivery coordinator; fake wake-lock driver and repositories.
  - Proves / registration: test/features/share/presentation/announcement_batch_forward_target_policy_test.dart:156: One selected target and both source captions reach the coordinator once; result closes route and releases lock. Not a recipient/codec proof. Registered: affected-media, host-all.

**Remaining gaps**

- Actual authorization and route/matrix logic are tested with harness repositories/delivery callbacks; native files/network and recipient full decode are separate.

#### SHARE-011 — Offline forwarding/external sharing persists custody and delivers correctly after reconnection

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Confirm external share/forward while transport is unavailable.
2. Persist custody before closing/reopening the sender.
3. Restore connectivity and settle the same owned operation once.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: offline then restored/inbox fallback; offline: n/a; app state: database reopen models restart; input: external media or internal forward; recovery: durable strict custody retry.

**Expected:** Accepted work survives restart and retries authoritative bytes/identity without duplicate custody or false success.

**Inspected test evidence**

- [test/features/share/integration/external_share_media_custody_recovery_test.dart](../../test/features/share/integration/external_share_media_custody_recovery_test.dart) — `TC-348-03 committed external share survives unusable preview and restart` (integration).
  - Real: DefaultShareBatchDeliveryCoordinator; production current FFI SQLite repos; real files/reopen and strict custody/retry owners.
  - Faked: strict bridge crypto/upload and P2P/inbox; image processing and identity/contact repos; strict feature flag enabled.
  - Proves / registration: test/features/share/integration/external_share_media_custody_recovery_test.dart:36: Committed parent/attachment custody survives lost/unusable preview and DB reopen, retries authoritative bytes once, then records one inbox store. Synthetic JPEG bytes/no recipient decoder and default-off cohort limits apply. Registered: affected-media, host-all.
- [test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart](../../test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart) — `failed-cell retry is sparse and preserves each source caption and token` (unit).
  - Real: actual source-target matrix/retry coordinator.
  - Faked: source revalidator; contact repository; strict deliver callback.
  - Proves / registration: test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart:504: Only failed source-target cells retry with original token/latest source caption; settled sent/queued cells remain unchanged. Registered: affected-media, host-all.

**Remaining gaps**

- Real local files/SQLite custody/reopen is meaningful, but strict feature is explicitly enabled, crypto/network fake, and remote recipient is absent. Cannot generalize to default legacy store125 behavior.

### SETTINGS — Profile, preferences and support

#### SETTINGS-001 — Edit display name with validation and preserve the update across restart and peer refresh

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Edit the display name and submit.
2. Reopen/restart Settings.
3. Observe the changed name locally and after a peer profile refresh.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: new display name; recovery: restart and peer refresh.

**Expected:** A valid submitted name persists and peers converge without showing a false saved value.

**Inspected test evidence**

- [test/features/settings/presentation/screens/settings_wired_test.dart](../../test/features/settings/presentation/screens/settings_wired_test.dart) — `editing username saves to repository and updates display` (widget).
  - Real: real Settings edit/submit/display.
  - Faked: identity repository; bridge/P2P/platform services.
  - Proves / registration: test/features/settings/presentation/screens/settings_wired_test.dart:522: Submitting a changed name updates the fake repository and rendered username; no peer refresh or disk restart. Registered: affected-surfaces, host-all, ui-approved-recovery-readability.

**Remaining gaps**

- The wired case uses a fake repository and only a normal name; boundary validation, durable restart and peer convergence are not joined.

#### SETTINGS-002 — Choose/cancel a profile avatar and converge valid normalized avatar to contacts

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Choose a profile image or cancel the picker.
2. Normalize and save/upload the selected avatar.
3. Deliver the new version to contacts and render it.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: non-square real JPEG after fake compression; picker cancel; recovery: n/a.

**Expected:** Cancellation preserves the prior avatar; selected valid images normalize and converge to active contacts.

**Inspected test evidence**

- [test/features/settings/application/helpers/avatar_normalization_helper_test.dart](../../test/features/settings/application/helpers/avatar_normalization_helper_test.dart) — `TC-200-08: non-square input commits a 512x512 square jpeg in a NEW file` (unit).
  - Real: AvatarNormalizationHelper; Dart image crop/decode; temporary files.
  - Faked: native compressor supplies a real generated JPEG.
  - Proves / registration: test/features/settings/application/helpers/avatar_normalization_helper_test.dart:78: Actual crop result decodes at512x512 in a new file; native picker/compression is substituted. Registered: affected-surfaces, host-all.
- [test/features/settings/integration/profile_picture_flow_test.dart](../../test/features/settings/integration/profile_picture_flow_test.dart) — `4e. ProfileUpdateListener detects new avatarVersion and downloads a normalized avatar` (integration).
  - Real: IncomingMessageRouter; ProfileUpdateListener; download use case and canonical file write.
  - Faked: fake P2P network/bridge/repositories; normalizer returns four non-image bytes.
  - Proves / registration: test/features/settings/integration/profile_picture_flow_test.dart:342: A new avatar version routes through download to canonical bytes; the fixture is not a decodable image, so this proves propagation/state rather than valid recipient rendering. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Picker/compressor/network are fake; propagation integration uses non-image output bytes and does not assert recipient decode/render or actual picker cancellation.

#### SETTINGS-003 — Avatar picker/upload/download failure or malformed image preserves the prior valid profile

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Keep a valid prior avatar.
2. Fail pick/compress/upload/download or supply malformed image bytes.
3. Inspect the retained valid profile.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: null compression, malformed output, transport failure; recovery: retain prior canonical avatar.

**Expected:** Unsuccessful avatar work does not replace a prior valid profile with missing/corrupt content.

**Inspected test evidence**

- [test/features/settings/application/download_profile_picture_use_case_test.dart](../../test/features/settings/application/download_profile_picture_use_case_test.dart) — `keeps the canonical avatar untouched when processing fails` (unit).
  - Real: download use case and real prior canonical file.
  - Faked: bridge download; compressor returning null; contact repository.
  - Proves / registration: test/features/settings/application/download_profile_picture_use_case_test.dart:235: Processing failure returns null and preserves the exact prior canonical bytes. Registered: affected-surfaces, host-all.
- [test/features/settings/application/helpers/avatar_normalization_helper_test.dart](../../test/features/settings/application/helpers/avatar_normalization_helper_test.dart) — `TC-200-15: undecodable compress output passes through byte-identical (crop skipped)` (unit).
  - Real: normalization fallback and actual file bytes.
  - Faked: compressor writing invalid bytes.
  - Proves / registration: test/features/settings/application/helpers/avatar_normalization_helper_test.dart:135: Locks the current pass-through of undecodable compressor output. This is not a valid-image rejection oracle; malformed-image preservation remains incomplete. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Null processing preserves prior bytes, but the existing undecodable-output test intentionally passes junk through. No assertion guarantees every malformed image leaves the prior valid avatar intact.

#### SETTINGS-004 — Reveal/copy/hide recovery phrase; hide automatically on navigation/background

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open the recovery sheet and explicitly reveal the phrase.
2. Copy or hide it.
3. Navigate away or background and return.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: recovery sheet then navigation/background; input: valid twelve-word phrase; recovery: n/a.

**Expected:** The phrase is hidden at rest and after explicit Hide; sensitive visibility after lifecycle changes must follow the intended privacy policy.

**Inspected test evidence**

- [test/features/settings/presentation/screens/settings_sub_sheets_test.dart](../../test/features/settings/presentation/screens/settings_sub_sheets_test.dart) — `T6 recovery sheet: warning, blur, reveal, copy, hide re-blurs; phrase never on the main page` (widget).
  - Real: real recovery modal/reveal/hide/copy feedback.
  - Faked: identity repository; secure store/clipboard platform handler.
  - Proves / registration: test/features/settings/presentation/screens/settings_sub_sheets_test.dart:330: Phrase is absent from the main page, reveal exposes it and Hide restores blur; no lifecycle-background assertion. Registered: affected-surfaces, call-signaling, host-all, ui-approved-recovery-readability.

**Remaining gaps**

- Explicit reveal/hide is asserted; auto-hide on background and clipboard failure are not asserted.

**Open questions**

- Is automatic concealment on app background required? The inspected SettingsWired has explicit reveal/hide but no lifecycle observer; scope expectation needs an explicit product decision.

#### SETTINGS-005 — Copy account identifier with truthful clipboard feedback

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Tap copy on the account identifier.
2. Inspect full copied value and temporary feedback.
3. Try a platform clipboard failure.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: full identifier; successful or failed clipboard write; recovery: n/a.

**Expected:** Copy targets the full account identifier; feedback must reflect the actual clipboard outcome.

**Inspected test evidence**

- [test/features/settings/presentation/screens/settings_wired_test.dart](../../test/features/settings/presentation/screens/settings_wired_test.dart) — `copy peer ID: full ID on clipboard, shows check for 2s then reverts` (widget).
  - Real: real Settings copy action and feedback timer.
  - Faked: clipboard MethodChannel handler; identity repository.
  - Proves / registration: test/features/settings/presentation/screens/settings_wired_test.dart:430: The full fixture identifier is sent to Clipboard.setData; success icon reverts after2s. A failed clipboard write is not tested here. Registered: affected-surfaces, host-all, ui-approved-recovery-readability.

**Remaining gaps**

- Success bytes/timer are asserted; Settings account-copy failure is not. lib/features/settings/presentation/screens/settings_wired.dart:207 invokes Clipboard.setData without awaiting it before success state.

#### SETTINGS-006 — Change background/theme with live contrast and restart persistence

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open background choices and select or dismiss.
2. Observe shell/contrast and a save failure rollback.
3. Reopen using the persisted selection.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: Default/Cosmic/Aurora/Signal and failed save; recovery: remount from stored token.

**Expected:** Choice updates the live app and remounts truthfully; dismissal changes nothing and failed saves restore the prior value.

**Inspected test evidence**

- [test/features/settings/presentation/screens/settings_one_screen_layout_test.dart](../../test/features/settings/presentation/screens/settings_one_screen_layout_test.dart) — `T9 reopen reconstructs values from storage` (widget).
  - Real: real Settings choice/mount/remount.
  - Faked: same FakeSecureKeyStore reused; identity/P2P dependencies.
  - Proves / registration: test/features/settings/presentation/screens/settings_one_screen_layout_test.dart:316: Cosmic is reconstructed after disposing/remounting the tree; not an OS process restart or real keychain read. Registered: affected-surfaces, host-all.
- [test/features/settings/presentation/screens/settings_sub_sheets_test.dart](../../test/features/settings/presentation/screens/settings_sub_sheets_test.dart) — `T3 background save failure reverts and surfaces the error` (widget).
  - Real: real preference sheet and rollback/error UI.
  - Faked: failing secure store.
  - Proves / registration: test/features/settings/presentation/screens/settings_sub_sheets_test.dart:258: Rejected save restores the prior selection and shows an error; other cases cover dismissal and a late save after sheet pop. Registered: affected-surfaces, call-signaling, host-all, ui-approved-recovery-readability.

**Remaining gaps**

- Remount uses a reused fake store; real process/keychain persistence and contrast across every app surface are outside this proof.

#### SETTINGS-007 — Change photo/video quality and restore the persisted selected value

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Select photo Original/compressed and independent video quality.
2. Close and reconstruct Settings.
3. Use the retained quality in the next media operation.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: Original versus compressed image/video; recovery: n/a.

**Expected:** Photo/video choices persist independently and the selected quality reaches processing.

**Inspected test evidence**

- [test/features/settings/presentation/screens/settings_sub_sheets_test.dart](../../test/features/settings/presentation/screens/settings_sub_sheets_test.dart) — `T4 photo sheet parity: options present, Original fires mediaQuality once` (widget).
  - Real: actual quality sheet and shell notification.
  - Faked: FakeSecureKeyStore; identity/P2P.
  - Proves / registration: test/features/settings/presentation/screens/settings_sub_sheets_test.dart:279: Original selection persists and fires one mediaQuality change; separate video case asserts independent preference. Registered: affected-surfaces, call-signaling, host-all, ui-approved-recovery-readability.
- [test/features/settings/presentation/screens/settings_wired_test.dart](../../test/features/settings/presentation/screens/settings_wired_test.dart) — `loads video quality preference on init from SecureKeyStore` (widget).
  - Real: Settings preference hydration.
  - Faked: preseeded FakeSecureKeyStore; identity/P2P.
  - Proves / registration: test/features/settings/presentation/screens/settings_wired_test.dart:677: Original video choice is reconstructed from the stored token. Registered: affected-surfaces, host-all, ui-approved-recovery-readability.

**Remaining gaps**

- UI/storage tokens are tested with fake secure store; selected preference to actual native camera/codec/recipient outcome is not joined.

#### SETTINGS-008 — Configure per-network/per-media auto-download and apply it to actual incoming attachments

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Configure media auto-download per lane/type/network.
2. Remount and receive pending/failed/evicted attachments.
3. Apply the current preference before automatic transfers; retain explicit retry.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: Wi-Fi/cellular/unknown input classes; offline: n/a; app state: foreground; input: direct, discussion, announcement and media types; recovery: mount/resume/older-page retry.

**Expected:** The correct matrix cell gates automatic work without erasing other preferences or preventing an eligible explicit action.

**Inspected test evidence**

- [test/features/settings/presentation/screens/settings_wired_test.dart](../../test/features/settings/presentation/screens/settings_wired_test.dart) — `media download settings persist and rollback failed saves` (widget).
  - Real: real media settings UI/full-matrix codec/rollback.
  - Faked: FakeSecureKeyStore and failing store; network/file transfers absent.
  - Proves / registration: test/features/settings/presentation/screens/settings_wired_test.dart:1169: Edits one lane, preserves other cells, remounts both and rolls back a failed save. Registered: affected-surfaces, host-all, ui-approved-recovery-readability.
- [test/features/settings/application/media_download_policy_test.dart](../../test/features/settings/application/media_download_policy_test.dart) — `policy decides all lane type and network combinations without transport side effects` (unit).
  - Real: actual pure MediaDownloadPolicy.
  - Faked: network/lane/type inputs.
  - Proves / registration: test/features/settings/application/media_download_policy_test.dart:18: Every disabled matrix cell denies exactly its lane/type/network; distinct announcement/discussion owner contexts remain distinct. No actual transfer. Registered: affected-surfaces, host-all, ui-approved-recovery-readability.
- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `denied policy makes zero transfers across mount, drain reload and older page` (widget).
  - Real: real conversation mount/resume/page recovery triggers.
  - Faked: recording denying decider; download callback; repositories/P2P/files.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:16351: All triggers consult direct context and make zero download calls; preferences/network classification are not real in this widget case. Registered: affected-conversation, host-all.

**Remaining gaps**

- Pure matrix and actual route triggers are tested separately; fake decider/download callbacks do not join real network classification, saved preferences and full incoming byte transfer.

#### SETTINGS-009 — Observe media storage usage, unavailable categories and refresh after deletion

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open Media & storage and request a scope measurement.
2. Inspect owned local counts/bytes and unavailable categories.
3. Clear a media type and refresh totals.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: paged owned files, descriptor-only/missing/noncanonical rows; recovery: refresh after deletion.

**Expected:** Only owned eligible local bytes count; clearing refreshes totals without affecting sibling scopes.

**Inspected test evidence**

- [test/core/media/media_storage_manager_test.dart](../../test/core/media/media_storage_manager_test.dart) — `all media inventory exhausts owner scoped pages for exact totals` (unit).
  - Real: MediaStorageManager; production FFI SQLite schema/repositories; actual files/owner-scoped pagination.
  - Faked: none identified.
  - Proves / registration: test/core/media/media_storage_manager_test.dart:887: Counts actual eligible local bytes across200 rows and exclusions; descriptor-only/noncanonical/wrong-owner rows do not become local usage. No Settings usage widget is mounted. Registered: affected-media, host-all.

**Remaining gaps**

- Strong manager inventory evidence exists, but no reference to MediaStorageUsageSection was found in tests; Settings measure/clear/refresh UI and failure usability are not asserted.

#### SETTINGS-010 — Toggle nearby-sharing consent, deny location and stop fresh presence when disabled/backgrounded

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Enable nearby sharing or deny location.
2. Disable sharing/background the app.
3. Verify fresh presence stops and stored coarse state clears appropriately.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground/background; input: sharing toggle and denied location; recovery: n/a.

**Expected:** Only explicitly permitted coarse presence is shared; disabled/background state does not keep publishing fresh presence.

**Inspected test evidence**

- [test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart](../../test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart) — `disabling nearby sharing publishes inactive before clearing` (widget).
  - Real: real Settings consent control.
  - Faked: InMemoryPostsPrivacySettingsRepository; fake nearby service.
  - Proves / registration: test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart:376: Off clears the saved local snapshot and calls the disable service once; publishing inactive is represented by that fake service callback. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Settings uses fake nearby service and in-memory privacy state; no real location permission, native lifecycle or recipient-observed presence cessation. Dormant Posts UI is excluded separately; Settings nearby control is reachable.

#### SETTINGS-011 — Open/copy safety report contact without auto-sending conversation data; handle missing mail/browser

**Coverage:** strong. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open the safety support sheet.
2. Explicitly launch mail/browser or use copy fallback.
3. Fail the external handler/clipboard and retry.

**Conditions:** platform: shared UI external-handler boundary; connectivity: n/a; offline: n/a; app state: foreground; input: launch false/throw and clipboard failure; recovery: copy/selectable fallback.

**Expected:** No conversation data is automatically sent; handler failures retain a usable selectable contact and truthful feedback.

**Inspected test evidence**

- [test/features/settings/presentation/widgets/safety_support_sheet_test.dart](../../test/features/settings/presentation/widgets/safety_support_sheet_test.dart) — `email action opens only the developer address and a subject` (widget).
  - Real: SafetySupportSheet exact URI composition and tap action.
  - Faked: recording URL launcher.
  - Proves / registration: test/features/settings/presentation/widgets/safety_support_sheet_test.dart:40: No automatic launch; explicit tap passes only the fixed mail address and subject, with no conversation body/attachment. Registered: affected-surfaces, host-all.
- [test/features/settings/presentation/widgets/safety_support_sheet_test.dart](../../test/features/settings/presentation/widgets/safety_support_sheet_test.dart) — `unavailable mail app (throws=$throws) keeps a copy fallback` (widget).
  - Real: real failure feedback and copy fallback.
  - Faked: URL launch false/PlatformException; copy callback.
  - Proves / registration: test/features/settings/presentation/widgets/safety_support_sheet_test.dart:63: Both false and exception launch failures retain a selectable/copyable address and show truthful failure feedback. Registered: affected-surfaces, host-all.
- [test/features/settings/presentation/widgets/safety_support_sheet_test.dart](../../test/features/settings/presentation/widgets/safety_support_sheet_test.dart) — `failed clipboard write keeps the selectable contact` (widget).
  - Real: real clipboard failure UI.
  - Faked: copy callback throwing PlatformException.
  - Proves / registration: test/features/settings/presentation/widgets/safety_support_sheet_test.dart:90: Shows failure, retains selectable contact and never shows a false copied confirmation. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Strong covers URI/data minimization, explicit user action and fallback states. Real mail/browser application availability and sending are outside the claimed controller behavior.

#### SETTINGS-012 — QR tiles appear as an authorized pair and prevent double navigation

**Coverage:** strong. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Supply both authorized QR host entries or an incomplete pair.
2. Tap/double-tap one entry then its sibling while navigation is pending.
3. Complete the route and enter again.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: both/neither/half callback pair; recovery: pending navigation completion.

**Expected:** Tiles appear together only when both callbacks exist; one route runs at a time and completion releases the latch.

**Inspected test evidence**

- [test/features/settings/presentation/widgets/settings_qr_tiles_test.dart](../../test/features/settings/presentation/widgets/settings_qr_tiles_test.dart) — `T5 rapid double-tap fires the host entry once (latch)` (widget).
  - Real: SettingsWired QR route latch; real tile actions.
  - Faked: host QR route represented by held Future; identity/bridge/P2P/storage.
  - Proves / registration: test/features/settings/presentation/widgets/settings_qr_tiles_test.dart:124: Double-tap starts one host entry, blocks sibling entry while pending, and releases the latch after completion. Registered: affected-surfaces, host-all.
- [test/features/settings/presentation/widgets/settings_qr_tiles_test.dart](../../test/features/settings/presentation/widgets/settings_qr_tiles_test.dart) — `T6 tiles absent when host callbacks are null (pair gating)` (widget).
  - Real: actual paired tile gating.
  - Faked: host callback availability.
  - Proves / registration: test/features/settings/presentation/widgets/settings_qr_tiles_test.dart:183: Neither tile is shown for no callbacks or either half-supplied callback pair. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Strong is scoped to tile gating/navigation dispatch; actual camera scan/contact acceptance is in CONTACT.

### TRANSFER — Move Account between phones

#### DC-019 — Account transfer preserves direct and group chat continuity

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Pair and authorize old/new phones for Move Account.
2. Transfer/verify/import account and exchange cutover proofs.
3. Reopen direct/group history and media, then exchange new messages.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: populated direct/group account; recovery: transfer/cutover and resumed messaging.

**Expected:** One active receiver preserves usable direct/group account continuity and old sender retires.

**Inspected test evidence**

- [test/features/account_migration/application/account_migration_end_to_end_test.dart](../../test/features/account_migration/application/account_migration_end_to_end_test.dart) — `TC-347-07 moves the full account and exact blob custody row file binding` (unit).
  - Real: real production bundle-source/local-transfer/receiver/import/cutover composition; actual loopback HTTP/WS; real FFI SQLite snapshot/import and files/hash checks.
  - Faked: SQLCipher adapter replaced by plain FFI SQLite using constructed schema; deterministic reversible ML-KEM crypto model; fake secure stores/discovery/authority repositories.
  - Proves / registration: test/features/account_migration/application/account_migration_end_to_end_test.dart:151: Source-to-wire-to-import moves rows, group key/media references and exact retained blob custody file binding. Not a signed binary upgrade, actual SQLCipher encryption/native keychain or recipient media decoder. Registered: affected-storage, host-all.
- [test/features/account_migration/application/account_migration_bundle_transfer_test.dart](../../test/features/account_migration/application/account_migration_bundle_transfer_test.dart) — `receiver finalizes cutover into active DB without replacing the new DB key` (unit).
  - Real: actual active import/key-selection/cutover logic and row checks.
  - Faked: snapshot/cipher/crypto adapters; secure-store/authority repositories.
  - Proves / registration: test/features/account_migration/application/account_migration_bundle_transfer_test.dart:1095: Finalized receiver retains its new database encryption key rather than importing old DB key; native encrypted database reopen and network identity are separate. Registered: affected-storage, host-all.
- [test/features/account_migration/application/migration_cutover_coordinator_test.dart](../../test/features/account_migration/application/migration_cutover_coordinator_test.dart) — `recovers interrupted cutover branches without two active devices` (unit).
  - Real: actual cutover state/proof prerequisite machine.
  - Faked: fake authority/cutover repositories and clock.
  - Proves / registration: test/features/account_migration/application/migration_cutover_coordinator_test.dart:168: No block proof/no active proof branches remain blocked; after exact old proof new active is permitted and recovery chooses correct side. No power-loss/native durable proof exchange. Registered: affected-storage, host-all.

**Remaining gaps**

- Real loopback/files/FFI SQL composition is substantive, but crypto/SQLCipher/native stores/discovery are fake or constructed. No actual signed phones plus new direct/group message/media-open post-transfer journey audited/executed.

#### TRANSFER-001 — Old phone opens Move Account; new phone displays/scans the correct migration QR

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Old phone opens Move Account.
2. New phone generates migration QR and advertises receiver.
3. Old phone scans exact migration QR and shows confirmation code.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: old/new phone roles and migration QR; recovery: n/a.

**Expected:** Correct old/new flow is reachable and unrelated QR cannot enter transfer authority.

**Inspected test evidence**

- [test/features/account_migration/presentation/account_migration_journey_screen_test.dart](../../test/features/account_migration/presentation/account_migration_journey_screen_test.dart) — `old-phone scan authorizes migration QR and shows matching pairing code` (widget).
  - Real: actual Move Account old-phone scan->confirmation UI; real pairing-code derivation.
  - Faked: QR scanner callback; export authorizer supplies transcript; identity/secure store.
  - Proves / registration: test/features/account_migration/presentation/account_migration_journey_screen_test.dart:486: Scanned migration QR is authorized and exact expected code displayed; native scan/channel authentication and remote matching-code consent absent. Registered: affected-storage, host-all.
- [test/features/account_migration/presentation/account_migration_journey_screen_test.dart](../../test/features/account_migration/presentation/account_migration_journey_screen_test.dart) — `new-phone QR shows loading then success without raw secrets` (widget).
  - Real: actual new-phone QR loading/success UI.
  - Faked: buildQrPayload/startReceiver/keygen/storage callbacks.
  - Proves / registration: test/features/account_migration/presentation/account_migration_journey_screen_test.dart:213: Pending payload produces loading then QR; raw key material is not exposed by the intended view. Native key generation/persistence/advertisement not joined. Registered: affected-storage, host-all.

**Remaining gaps**

- Real route/UI with injected keygen/scan/authorizer/receiver proves handoff; native camera, local discovery and two real displays/code match not joined.

#### TRANSFER-002 — Reject malformed, expired, future, reused, wrong-kind or untrusted transfer QR

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Scan malformed/expired/future/wrong-kind/untrusted QR.
2. Try reused consumed session or crossed key/session.
3. Verify no transfer/export authority and preserve retryable legitimate session.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: invalid QR/time/version, consumed session, crossed key; recovery: n/a.

**Expected:** Only fresh matching migration protocol/session authority may export account.

**Inspected test evidence**

- [test/features/account_migration/application/migration_qr_payload_use_case_test.dart](../../test/features/account_migration/application/migration_qr_payload_use_case_test.dart) — `parser fails closed for malformed and incompatible payloads` (unit).
  - Real: actual QR parser/version/time policy.
  - Faked: controlled clock and literal QR fields.
  - Proves / registration: test/features/account_migration/application/migration_qr_payload_use_case_test.dart:63: Rejects malformed/expired/future timestamp, missing key, wrong kind/version; cannot prove cryptographic peer authentication. Registered: affected-storage, host-all.
- [test/features/account_migration/application/migration_export_authorization_test.dart](../../test/features/account_migration/application/migration_export_authorization_test.dart) — `reused consumed session cannot authorize export again` (unit).
  - Real: actual export authorization/single-use session policy.
  - Faked: in-memory session repository/clock.
  - Proves / registration: test/features/account_migration/application/migration_export_authorization_test.dart:80: Consumed session refuses reauthorization; mismatched session/key case prevents using another transfer. No native authenticated channel. Registered: affected-storage, host-all.
- [test/features/account_migration/application/migration_export_authorization_test.dart](../../test/features/account_migration/application/migration_export_authorization_test.dart) — `confirmation code requires authenticated channel transcript material` (unit).
  - Real: typed transcript constraints/hash-derived confirmation.
  - Faked: constructed channel-binding input.
  - Proves / registration: test/features/account_migration/application/migration_export_authorization_test.dart:97: Empty authenticated binding throws; different transcript material changes the code. A nonempty test string is not real channel authentication. Registered: affected-storage, host-all.

**Remaining gaps**

- Parser/session/type/confirmation boundaries are causal; real authenticated peer/channel and native QR capture are substituted.

#### TRANSFER-003 — Confirm matching codes; cancel or reject mismatched confirmation without cutover

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Compare matching confirmation on both roles.
2. Confirm only intended authenticated session, or cancel on mismatch.
3. Inspect that cancellation/mismatch does not cut over account.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: matching/mismatched code and cancellation; recovery: no cutover on refusal.

**Expected:** User consent is bound to the exact authenticated transfer and refusal leaves source authority intact.

**Inspected test evidence**

- [test/features/account_migration/presentation/account_migration_journey_screen_test.dart](../../test/features/account_migration/presentation/account_migration_journey_screen_test.dart) — `old-phone scan authorizes migration QR and shows matching pairing code` (widget).
  - Real: actual Move Account old-phone scan->confirmation UI; real pairing-code derivation.
  - Faked: QR scanner callback; export authorizer supplies transcript; identity/secure store.
  - Proves / registration: test/features/account_migration/presentation/account_migration_journey_screen_test.dart:486: Scanned migration QR is authorized and exact expected code displayed; native scan/channel authentication and remote matching-code consent absent. Registered: affected-storage, host-all.
- [test/features/account_migration/application/migration_export_authorization_test.dart](../../test/features/account_migration/application/migration_export_authorization_test.dart) — `confirmation code requires authenticated channel transcript material` (unit).
  - Real: typed transcript constraints/hash-derived confirmation.
  - Faked: constructed channel-binding input.
  - Proves / registration: test/features/account_migration/application/migration_export_authorization_test.dart:97: Empty authenticated binding throws; different transcript material changes the code. A nonempty test string is not real channel authentication. Registered: affected-storage, host-all.
- [test/features/account_migration/presentation/account_migration_journey_screen_test.dart](../../test/features/account_migration/presentation/account_migration_journey_screen_test.dart) — `old-phone cancellation is not overwritten by runner completion` (widget).
  - Real: actual old-phone route/cancel/progress result arbitration.
  - Faked: held runTransfer returns later success; scan/authorizer/storage/identity callbacks.
  - Proves / registration: test/features/account_migration/presentation/account_migration_journey_screen_test.dart:1030: Cancelled UI remains cancelled when old runner completes; does not perform database/authority cutover. Registered: affected-storage, host-all.
- [test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart](../../test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart) — `restores active authority when the transfer is cancelled` (unit).
  - Real: actual transfer cancellation/result and authority coordinator.
  - Faked: recording bundle receiver; discovery/authority repositories and prepared bundle.
  - Proves / registration: test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart:2797: Pre-cutover cancellation returns cancelled and source migrationFailedActiveRestored; real transport/durable secure authority not asserted here. Registered: affected-storage, host-all.

**Remaining gaps**

- Code derivation, UI and cancellation are separate tests with constructed transcript/fake runner; no actual two-phone mismatched confirmation-to-zero-cutover proof.

#### TRANSFER-004 — Establish local transfer on Wi-Fi without internet, separately from internet recovery

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Keep old/new on local Wi-Fi without internet.
2. Discover/pair and transfer full account locally.
3. Verify local completion independently of later relay reconnect.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: same Wi-Fi/no internet; host loopback substitute; offline: n/a; app state: foreground; input: as described; recovery: n/a.

**Expected:** Local transfer works without public internet and does not infer internet messaging recovery.

**Inspected test evidence**

- [test/features/account_migration/application/account_migration_end_to_end_test.dart](../../test/features/account_migration/application/account_migration_end_to_end_test.dart) — `TC-347-07 moves the full account and exact blob custody row file binding` (unit).
  - Real: real production bundle-source/local-transfer/receiver/import/cutover composition; actual loopback HTTP/WS; real FFI SQLite snapshot/import and files/hash checks.
  - Faked: SQLCipher adapter replaced by plain FFI SQLite using constructed schema; deterministic reversible ML-KEM crypto model; fake secure stores/discovery/authority repositories.
  - Proves / registration: test/features/account_migration/application/account_migration_end_to_end_test.dart:151: Source-to-wire-to-import moves rows, group key/media references and exact retained blob custody file binding. Not a signed binary upgrade, actual SQLCipher encryption/native keychain or recipient media decoder. Registered: affected-storage, host-all.
- [test/features/account_migration/application/account_migration_end_to_end_test.dart](../../test/features/account_migration/application/account_migration_end_to_end_test.dart) — `moves a realistic ~12 MB media account across many segments` (unit).
  - Real: same real bundle/wire/FFI SQLite/files composition; six actual2MiB deterministic files.
  - Faked: fake segment crypto/secure stores/discovery/authority; media bytes are generated .bin data.
  - Proves / registration: test/features/account_migration/application/account_migration_end_to_end_test.dart:675: Many verified segments retain all generated files/content hashes and account data; volume tests are not native photo/video/audio open tests. Registered: affected-storage, host-all.

**Remaining gaps**

- Real HTTP/WS wire and files run on loopback with shared fake discovery, not actual native mDNS/Wi-Fi permission/airplane state.

#### TRANSFER-005 — Preflight insufficient space or oversized account and recover without corrupting either phone

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Estimate account/receiver staging footprint.
2. Reject over-cap/insufficient/unreadable capacity before transfer.
3. Free space/reduce account and retry without mutating either account.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: account cap/free-space/headroom/unknown capacity; recovery: retry after capacity repair.

**Expected:** Preflight refusal is specific, truthful and non-destructive with usable recovery.

**Inspected test evidence**

- [test/features/account_migration/application/migration_storage_preflight_test.dart](../../test/features/account_migration/application/migration_storage_preflight_test.dart) — `fails closed when storage is insufficient` (unit).
  - Real: actual size/headroom arithmetic/decision.
  - Faked: available bytes provider.
  - Proves / registration: test/features/account_migration/application/migration_storage_preflight_test.dart:38: Required750 versus available700 rejects as storageInsufficient; unknown/unreadable provider rejects in companion case. No real ENOSPC fault. Registered: affected-storage, host-all.
- [test/features/account_migration/presentation/account_migration_journey_screen_test.dart](../../test/features/account_migration/presentation/account_migration_journey_screen_test.dart) — `P0-2: over-cap account blocks Start transfer at the confirm stage` (widget).
  - Real: actual confirmation size gate/disabled action/telemetry.
  - Faked: size estimate/authorizer; recording transfer runner and secure store.
  - Proves / registration: test/features/account_migration/presentation/account_migration_journey_screen_test.dart:833: 250MiB estimate exceeds200MiB test policy so Start is blocked and runner unused; real account scan/free-space pressure not induced. Registered: affected-storage, host-all.

**Remaining gaps**

- Arithmetic/UI use injected estimates/providers. Actual disk-full during write, realistic free-space scan and both-phone cleanup/retry are not joined.

#### TRANSFER-006 — Transfer encrypted database, media files, secure references, groups and pending work completely

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Build typed encrypted transfer manifest from all owned account data.
2. Move database/files/secure references/groups/pending work over segments.
3. Verify hashes/schema/references before import and activation.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: full account DB/media/group keys/secure references/pending work; recovery: n/a.

**Expected:** All required owned data arrives consistently; missing critical media/secrets blocks completion.

**Inspected test evidence**

- [test/features/account_migration/application/account_migration_end_to_end_test.dart](../../test/features/account_migration/application/account_migration_end_to_end_test.dart) — `TC-347-07 moves the full account and exact blob custody row file binding` (unit).
  - Real: real production bundle-source/local-transfer/receiver/import/cutover composition; actual loopback HTTP/WS; real FFI SQLite snapshot/import and files/hash checks.
  - Faked: SQLCipher adapter replaced by plain FFI SQLite using constructed schema; deterministic reversible ML-KEM crypto model; fake secure stores/discovery/authority repositories.
  - Proves / registration: test/features/account_migration/application/account_migration_end_to_end_test.dart:151: Source-to-wire-to-import moves rows, group key/media references and exact retained blob custody file binding. Not a signed binary upgrade, actual SQLCipher encryption/native keychain or recipient media decoder. Registered: affected-storage, host-all.
- [test/features/account_migration/application/account_migration_end_to_end_test.dart](../../test/features/account_migration/application/account_migration_end_to_end_test.dart) — `moves a realistic ~12 MB media account across many segments` (unit).
  - Real: same real bundle/wire/FFI SQLite/files composition; six actual2MiB deterministic files.
  - Faked: fake segment crypto/secure stores/discovery/authority; media bytes are generated .bin data.
  - Proves / registration: test/features/account_migration/application/account_migration_end_to_end_test.dart:675: Many verified segments retain all generated files/content hashes and account data; volume tests are not native photo/video/audio open tests. Registered: affected-storage, host-all.
- [test/features/account_migration/application/account_migration_bundle_transfer_test.dart](../../test/features/account_migration/application/account_migration_bundle_transfer_test.dart) — `receiver finalizes cutover into active DB without replacing the new DB key` (unit).
  - Real: actual active import/key-selection/cutover logic and row checks.
  - Faked: snapshot/cipher/crypto adapters; secure-store/authority repositories.
  - Proves / registration: test/features/account_migration/application/account_migration_bundle_transfer_test.dart:1095: Finalized receiver retains its new database encryption key rather than importing old DB key; native encrypted database reopen and network identity are separate. Registered: affected-storage, host-all.
- [test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart](../../test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart) — `classifies valid pending work to resume only on the new phone after commit` (unit).
  - Real: actual pending-work classification/ownership manifest.
  - Faked: constructed database rows/known payload references.
  - Proves / registration: test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart:10: Eligible pending work is classified for new-phone resume only after commit, excluding terminal/unsupported state. Does not perform actual pending sends/read/draft UI after migration. Registered: affected-storage, host-all.

**Remaining gaps**

- Chained host uses constructed schema/plain FFI SQL and deterministic reversible crypto/fake secure stores. Genuine ML-KEM/SQLCipher/native keychain and all current schema coverage are separate.

#### TRANSFER-007 — Interrupt/cancel transfer before cutover; source remains usable and receiver staging is cleaned

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Interrupt/cancel before account cutover.
2. Clean receiver session staging and restore source active state only from export pause.
3. Retry without deleting active data or accepting late success.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: cancel/transport failure before cutover; recovery: owned staging cleanup/source restoration.

**Expected:** Pre-cutover cancellation preserves source usability and cleans only session-owned receiver artifacts.

**Inspected test evidence**

- [test/features/account_migration/presentation/account_migration_journey_screen_test.dart](../../test/features/account_migration/presentation/account_migration_journey_screen_test.dart) — `old-phone cancellation is not overwritten by runner completion` (widget).
  - Real: actual old-phone route/cancel/progress result arbitration.
  - Faked: held runTransfer returns later success; scan/authorizer/storage/identity callbacks.
  - Proves / registration: test/features/account_migration/presentation/account_migration_journey_screen_test.dart:1030: Cancelled UI remains cancelled when old runner completes; does not perform database/authority cutover. Registered: affected-storage, host-all.
- [test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart](../../test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart) — `restores active authority when the transfer is cancelled` (unit).
  - Real: actual transfer cancellation/result and authority coordinator.
  - Faked: recording bundle receiver; discovery/authority repositories and prepared bundle.
  - Proves / registration: test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart:2797: Pre-cutover cancellation returns cancelled and source migrationFailedActiveRestored; real transport/durable secure authority not asserted here. Registered: affected-storage, host-all.
- [test/features/account_migration/application/migration_database_import_cleanup_test.dart](../../test/features/account_migration/application/migration_database_import_cleanup_test.dart) — `failed import deletes DB sidecars and invokes MIG-003 cleanup only for session` (unit).
  - Real: real filesystem session DB/WAL/SHM/journal cleanup; actual secure-staging cleanup owner.
  - Faked: fake secure stores.
  - Proves / registration: test/features/account_migration/application/migration_database_import_cleanup_test.dart:31: Failed import deletes session-owned staged DB/sidecars/manifest/temp and cleans corresponding staged secrets while preserving active DB/keys; not OS keychain deletion. Registered: affected-storage, host-all.

**Remaining gaps**

- File cleanup is real and state/route guards causal, but actual secure-store/disconnect/OS cancellation and source runtime are fake.

#### TRANSFER-008 — Retry/resume interrupted segments without duplicate import or lost files

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Transfer and verify some segments/entry offsets.
2. Interrupt/recreate receiver and reload checkpoint ledger.
3. Send only missing bytes and finish one import.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: partial verified4MiB transfer and file-backed offsets; recovery: interruption/recreated receiver.

**Expected:** Resume retains verified data and exact offsets without duplicate import or lost files.

**Inspected test evidence**

- [test/features/account_migration/application/account_migration_end_to_end_test.dart](../../test/features/account_migration/application/account_migration_end_to_end_test.dart) — `an interrupted transfer resumes from the receiver ledger instead of restarting` (unit).
  - Real: actual production local transport/receiver checkpoint/resume; real files/SQLite.
  - Faked: deterministic crypto; fake discovery/secure store/authority; controlled transport interruption.
  - Proves / registration: test/features/account_migration/application/account_migration_end_to_end_test.dart:1008: FourMiB fixture interrupts mid-stream then resumes verified chunks without restarting; no real Wi-Fi disconnect/OS process death. Registered: affected-storage, host-all.
- [test/features/account_migration/application/account_migration_bundle_transfer_test.dart](../../test/features/account_migration/application/account_migration_bundle_transfer_test.dart) — `receiver restart resumes from the file-backed ledger without resending verified entries` (unit).
  - Real: production receiver/checkpoint file reload/offset/hash logic.
  - Faked: recreated receiver object; crypto/import/native-store seams.
  - Proves / registration: test/features/account_migration/application/account_migration_bundle_transfer_test.dart:2417: A recreated receiver loads verified24-byte file offset, sends remaining chunks only and completes import; actual process and native SQLCipher remain separate. Registered: affected-storage, host-all.

**Remaining gaps**

- Real host wire/files/checkpoint reload exist; crypto/secure stores/SQLCipher/discovery are seams and no actual process/radio interruption executed.

#### TRANSFER-009 — Crash or lose network at authorization/cutover/finalization; exactly one account authority survives

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Lose process/network at export authorization, old block, new activation or final acknowledgment.
2. Recover exact cutover proof/state.
3. Ensure at most one account runtime can act; retry only unresolved branch.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: crash/cutover/finalization checkpoint; input: as described; recovery: proof exchange and monotonic authority.

**Expected:** Missing/crossed proofs cannot yield two active account authorities or restore a cutover-blocked source.

**Inspected test evidence**

- [test/features/account_migration/application/migration_cutover_coordinator_test.dart](../../test/features/account_migration/application/migration_cutover_coordinator_test.dart) — `recovers interrupted cutover branches without two active devices` (unit).
  - Real: actual cutover state/proof prerequisite machine.
  - Faked: fake authority/cutover repositories and clock.
  - Proves / registration: test/features/account_migration/application/migration_cutover_coordinator_test.dart:168: No block proof/no active proof branches remain blocked; after exact old proof new active is permitted and recovery chooses correct side. No power-loss/native durable proof exchange. Registered: affected-storage, host-all.
- [test/features/account_migration/application/migration_cutover_coordinator_test.dart](../../test/features/account_migration/application/migration_cutover_coordinator_test.dart) — `old network block is durable before new active commit` (unit).
  - Real: actual old-block-before-new-active operation order.
  - Faked: fake persistence repositories.
  - Proves / registration: test/features/account_migration/application/migration_cutover_coordinator_test.dart:131: Asserts saved old blocking state precedes new active record; durable wording is modeled at repository seam, not actual fsync/secure-store crash test. Registered: affected-storage, host-all.
- [test/features/account_migration/application/account_migration_end_to_end_test.dart](../../test/features/account_migration/application/account_migration_end_to_end_test.dart) — `TC-347-07 moves the full account and exact blob custody row file binding` (unit).
  - Real: real production bundle-source/local-transfer/receiver/import/cutover composition; actual loopback HTTP/WS; real FFI SQLite snapshot/import and files/hash checks.
  - Faked: SQLCipher adapter replaced by plain FFI SQLite using constructed schema; deterministic reversible ML-KEM crypto model; fake secure stores/discovery/authority repositories.
  - Proves / registration: test/features/account_migration/application/account_migration_end_to_end_test.dart:151: Source-to-wire-to-import moves rows, group key/media references and exact retained blob custody file binding. Not a signed binary upgrade, actual SQLCipher encryption/native keychain or recipient media decoder. Registered: affected-storage, host-all.

**Remaining gaps**

- Proof/state machine and operation order use fake persistence; no actual power loss/native secure-store fsync/process race across two devices.

#### TRANSFER-010 — Finalize receiver, retire old sender authority and reconnect using correct transport identity

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Verify receiver import and commit its new active state.
2. Block/retire source and clean old push/runtime leases.
3. Reconnect under imported account with correct current installation transport.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: verified import, exact old/new proofs; recovery: runtime/push lease cleanup and reconnect.

**Expected:** Receiver retains its own database key/current runtime identity while source cannot continue account operations.

**Inspected test evidence**

- [test/features/account_migration/application/account_migration_bundle_transfer_test.dart](../../test/features/account_migration/application/account_migration_bundle_transfer_test.dart) — `receiver finalizes cutover into active DB without replacing the new DB key` (unit).
  - Real: actual active import/key-selection/cutover logic and row checks.
  - Faked: snapshot/cipher/crypto adapters; secure-store/authority repositories.
  - Proves / registration: test/features/account_migration/application/account_migration_bundle_transfer_test.dart:1095: Finalized receiver retains its new database encryption key rather than importing old DB key; native encrypted database reopen and network identity are separate. Registered: affected-storage, host-all.
- [test/features/account_migration/application/migration_cutover_coordinator_test.dart](../../test/features/account_migration/application/migration_cutover_coordinator_test.dart) — `old network block is durable before new active commit` (unit).
  - Real: actual old-block-before-new-active operation order.
  - Faked: fake persistence repositories.
  - Proves / registration: test/features/account_migration/application/migration_cutover_coordinator_test.dart:131: Asserts saved old blocking state precedes new active record; durable wording is modeled at repository seam, not actual fsync/secure-store crash test. Registered: affected-storage, host-all.
- [test/features/account_migration/application/migration_export_authorization_test.dart](../../test/features/account_migration/application/migration_export_authorization_test.dart) — `TC-360-01b v112 remote roster migrates while linked installation authority cannot move` (unit).
  - Real: LinkedInstallationAuthority and export qualification.
  - Faked: FakeSecureKeyStore/session repository.
  - Proves / registration: test/features/account_migration/application/migration_export_authorization_test.dart:136: Linked-role source is refused without consuming session; ordinary primary remains allowed. No linked identity can authorize account export under this local guard. Registered: affected-storage, host-all.

**Remaining gaps**

- Native runtime shutdown, push provider unregistration and actual transported identity/reconnect are not joined with host import/proof checks.

#### TRANSFER-011 — Open migrated photos/videos/voice/documents on the receiver, not only message metadata

**Coverage:** partial. **Execution:** device_run. **Catalog:** DC-019.

**Steps**

1. Transfer representative real photos/videos/voice/PDFs.
2. Open each migrated attachment on receiver using native decoder/player/document viewer.
3. Compare full content/orientation/duration/caption and retry missing original honestly.

**Conditions:** platform: executor-reported Android source to iOS simulator receiver; physical-iPhone receiver leg NOT RUN; connectivity: local network, completed transfer/cutover; offline: n/a; app state: foreground; input: actual migrated image/video/voice/PDF bytes; recovery: receiver terminate/relaunch and all four items reopened.

**Expected:** Migrated full media is usable on receiver, beyond preserved metadata/path/hash.

**Device execution (2026-10-23; flutter_app)**

- Result: **PASS**, scoped to the **iOS simulator receiver**, source `cb02da5e9`. Rating stays **partial**.
- Migrated JPEG, MP4, M4A and PDF hashes matched the Android source. Full photo, video, voice player and PDF opened; after terminate/relaunch the same four rows, captions/times and hashes persisted, and every item reopened. The old source showed its moved-account block.
- **Physical-iPhone receiver leg NOT RUN** after its automation prerequisite blocked. QR used screenshot decoding and **debug paste (not camera)**. First simulator build network-lookup failure and IME-altered paste rejection remain recorded; the corrected build/paste completed.
- Silent voice fixture proves player progression/duration and file preservation, not intelligible audio. Astra inspected saved executor evidence and performed no device work.
- Evidence: `/Volumes/CrucialX9/flutter_app/.codex-test-logs/transfer011-20261023T0941Z/SUMMARY.md:10` (scope), lines 11-12 (first attempts and QR), 14-16 (hashes, opens and relaunch), 17 (source cutover).

**Prior Group D device execution (2026-10-22; flutter_app)**

- Result: **BLOCKED_ENVIRONMENT_LOCAL_PEER_UNAVAILABLE**.
- The launched Move Account attempt stopped at connecting with failureCode localPeerUnavailable between two emulators. Executor attributes the block to separate netsim NATs.
- This is an actual attempted-run environment block, not migrated receiver/media preservation proof. Astra did not diagnose networking or control either emulator.
- Use only a currently available, mutually reachable disposable migration pair for any follow-up. An unavailable alternate hardware/topology leg is N/A by project policy; two absent physical LAN devices must not become a mandatory closure condition.
- Evidence: `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/SUMMARY.md:9`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/t011_move_fail_log.txt:10`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/t011_move_fail_log.txt:11`; `/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-d-20261022/t011_source_media_hashes.txt:1`.

**Inspected test evidence**

- [test/features/account_migration/application/account_migration_end_to_end_test.dart](../../test/features/account_migration/application/account_migration_end_to_end_test.dart) — `TC-347-07 moves the full account and exact blob custody row file binding` (integration).
  - Real: production bundle source/local transfer/receiver/import/cutover, actual loopback HTTP/WS and file/hash preservation; real portrait JPEG opens from imported authoritative row/path through host Flutter codec;192x256 frame, red/blue pixel content and exact caption.
  - Faked: constructed matching schema and plain FFI SQLite in place of SQLCipher; deterministic reversible crypto; fake secure stores/discovery/authority; host image engine only; no actual mobile app viewer, native keychain/crypto or video/voice/PDF open.
  - Proves / registration: test/features/account_migration/application/account_migration_end_to_end_test.dart:154: Fresh focused019:1 passed,0 skipped/failed,exit0. Existing full-chain preservation assertions remain, source fixture is now a decodable JPEG rather than opaque image-named bytes. Evidence .codex-test-logs/astra-groupCD/019-D-migrated-photo-summary.json/receipt. Registered: affected-storage, host-all.
- [test/features/account_migration/application/account_migration_end_to_end_test.dart](../../test/features/account_migration/application/account_migration_end_to_end_test.dart) — `moves a realistic ~12 MB media account across many segments` (unit).
  - Real: same real bundle/wire/FFI SQLite/files composition; six actual2MiB deterministic files.
  - Faked: fake segment crypto/secure stores/discovery/authority; media bytes are generated .bin data.
  - Proves / registration: test/features/account_migration/application/account_migration_end_to_end_test.dart:739: Many verified segments retain all generated files/content hashes and account data; volume tests are not native photo/video/audio open tests. Registered: affected-storage, host-all. This volume case was not rerun in the scoped Group D packet.

**Remaining gaps**

- Receiver PASS is scoped to iOS simulator; physical-iPhone receiver leg NOT RUN and optical QR camera scanning were not verified. Unavailable alternate targets are N/A by project policy, not mandatory hardware waits.
- Silent voice playback does not establish intelligible audio; missing-original recovery and a signed release candidate were not verified. Rating remains partial.

**Open questions**

- Execution by flutter_app; Astra inspected saved evidence only. The 2026-10-23 summary lines 10-18 defines the scoped simulator receiver PASS; the earlier Group D block remains historical evidence.
- Existing handoff: docs/testing/astra-group-d-device-runbook.md. Actual failures, weaker witnesses and unrun legs above are retained; no rating upgrade.

#### TRANSFER-012 — Migrated direct/group unread, drafts, history and pending outgoing retries remain coherent

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Migrate unread/history/drafts/accepted pending outgoing work.
2. Activate receiver and project correct direct/group home state.
3. Drain pending work only on receiver with original identity/semantic state.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: direct/group history/unread/draft/pending retries; recovery: post-activation retry.

**Expected:** Retained history/read/draft and pending custody remain coherent without replay by retired source.

**Inspected test evidence**

- [test/features/account_migration/application/account_migration_end_to_end_test.dart](../../test/features/account_migration/application/account_migration_end_to_end_test.dart) — `TC-347-07 moves the full account and exact blob custody row file binding` (unit).
  - Real: real production bundle-source/local-transfer/receiver/import/cutover composition; actual loopback HTTP/WS; real FFI SQLite snapshot/import and files/hash checks.
  - Faked: SQLCipher adapter replaced by plain FFI SQLite using constructed schema; deterministic reversible ML-KEM crypto model; fake secure stores/discovery/authority repositories.
  - Proves / registration: test/features/account_migration/application/account_migration_end_to_end_test.dart:151: Source-to-wire-to-import moves rows, group key/media references and exact retained blob custody file binding. Not a signed binary upgrade, actual SQLCipher encryption/native keychain or recipient media decoder. Registered: affected-storage, host-all.
- [test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart](../../test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart) — `classifies valid pending work to resume only on the new phone after commit` (unit).
  - Real: actual pending-work classification/ownership manifest.
  - Faked: constructed database rows/known payload references.
  - Proves / registration: test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart:10: Eligible pending work is classified for new-phone resume only after commit, excluding terminal/unsupported state. Does not perform actual pending sends/read/draft UI after migration. Registered: affected-storage, host-all.
- [test/features/account_migration/application/account_migration_bundle_transfer_test.dart](../../test/features/account_migration/application/account_migration_bundle_transfer_test.dart) — `receiver restart resumes from the file-backed ledger without resending verified entries` (unit).
  - Real: production receiver/checkpoint file reload/offset/hash logic.
  - Faked: recreated receiver object; crypto/import/native-store seams.
  - Proves / registration: test/features/account_migration/application/account_migration_bundle_transfer_test.dart:2417: A recreated receiver loads verified24-byte file offset, sends remaining chunks only and completes import; actual process and native SQLCipher remain separate. Registered: affected-storage, host-all.

**Remaining gaps**

- Manifest/local row/file preservation is meaningful; actual application draft/unread rendering and resumed pending direct/group sends after full transfer are not one assertion.

#### TRANSFER-013 — Reject transfer from a linked-secondary installation and honor transfer-time feature restrictions

**Coverage:** strong. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Attempt export from a linked-secondary or otherwise blocked installation role.
2. Evaluate exact local authority before consuming pairing session.
3. Preserve valid primary transfer and exclude device-local installation authority from migration.

**Conditions:** platform: local authority/export admission boundary; connectivity: n/a; offline: n/a; app state: foreground; input: linked role versus ordinary primary; recovery: n/a.

**Expected:** Restricted linked installation cannot export account authority or consume the retry session; primary semantics remain valid.

**Inspected test evidence**

- [test/features/account_migration/application/migration_export_authorization_test.dart](../../test/features/account_migration/application/migration_export_authorization_test.dart) — `TC-360-01b v112 remote roster migrates while linked installation authority cannot move` (unit).
  - Real: LinkedInstallationAuthority and export qualification.
  - Faked: FakeSecureKeyStore/session repository.
  - Proves / registration: test/features/account_migration/application/migration_export_authorization_test.dart:136: Linked-role source is refused without consuming session; ordinary primary remains allowed. No linked identity can authorize account export under this local guard. Registered: affected-storage, host-all.

**Remaining gaps**

- Strong is scoped to the explicit local export refusal; real secure-store tamper resistance and signed artifact migration enforcement were not executed.

#### TRANSFER-014 — Close/back/app-background while receiver finalization is locked; restore a truthful progress state

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-019.

**Steps**

1. Begin receiver import/verified finalization.
2. Try Close/Back/background while cutover is locked.
3. Activate or report failure and restore truthful progress/close behavior.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: receiver importing/waiting activation; Close/Back/background; input: as described; recovery: activation/failure.

**Expected:** Non-poppable finalization cannot be abandoned into conflicting UI and progress ownership remains truthful.

**Inspected test evidence**

- [test/features/account_migration/presentation/account_migration_journey_screen_test.dart](../../test/features/account_migration/presentation/account_migration_journey_screen_test.dart) — `verified new-phone finalization disables close and system back` (widget).
  - Real: actual new-phone route/PopScope/finalization controls.
  - Faked: receiver progress/activation event stream; build/startReceiver/bridge/store callbacks.
  - Proves / registration: test/features/account_migration/presentation/account_migration_journey_screen_test.dart:322: Importing/verified waiting locks Close and Back until activation; source events are injected, not a real receiver finalize/native process restart. Registered: affected-storage, host-all.
- [test/features/account_migration/presentation/account_migration_journey_screen_test.dart](../../test/features/account_migration/presentation/account_migration_journey_screen_test.dart) — `old-phone cancellation is not overwritten by runner completion` (widget).
  - Real: actual old-phone route/cancel/progress result arbitration.
  - Faked: held runTransfer returns later success; scan/authorizer/storage/identity callbacks.
  - Proves / registration: test/features/account_migration/presentation/account_migration_journey_screen_test.dart:1030: Cancelled UI remains cancelled when old runner completes; does not perform database/authority cutover. Registered: affected-storage, host-all.

**Remaining gaps**

- Actual route guards use injected receiver events; background/native keep-alive/OS process restart and durable finalization state restoration are separate.

#### TRANSFER-015 — Erase a blocked/retired account with explicit confirmation and preserve unrelated OS data

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open retired/blocked source erase action.
2. Explicitly confirm local erasure.
3. Retire exact owned recovery/data/keys and preserve unrelated OS notifications/state on failure.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: retired/migrated-out account and explicit erase confirmation; recovery: database erase failure preserves keys/authority.

**Expected:** Erasure requires valid blocked authority/consent and touches only owned local state with truthful failure handling.

**Inspected test evidence**

- [test/features/identity/presentation/screens/startup_router_recovery_test.dart](../../test/features/identity/presentation/screens/startup_router_recovery_test.dart) — `migrated-out erase clears iOS recovery without clearing all delivered notifications` (widget).
  - Real: real blocked-account consent UI; erase ordering and authority repository.
  - Faked: identity/secure store; database erasure/native notification hooks; P2P.
  - Proves / registration: test/features/identity/presentation/screens/startup_router_recovery_test.dart:631: Explicit confirmation invalidates visibility, retires binding and clears exact recovery before database erase and key removal; broad delivered-notification clearing is deliberately not called. Registered: affected-identity, host-all, startup.
- [test/features/identity/presentation/screens/startup_router_recovery_test.dart](../../test/features/identity/presentation/screens/startup_router_recovery_test.dart) — `database erase failure preserves the key and migrated-out authority` (widget).
  - Real: real blocked-account failure UI/authority policy.
  - Faked: throwing database erase; secure store/P2P.
  - Proves / registration: test/features/identity/presentation/screens/startup_router_recovery_test.dart:717: Database erase failure retains encryption key and migrated-out authority, starts no P2P and keeps blocked UI. Registered: affected-identity, host-all, startup.
- [test/features/account_migration/application/migration_secure_storage_cleanup_test.dart](../../test/features/account_migration/application/migration_secure_storage_cleanup_test.dart) — `explicit account erase/reset deletes registry-owned active keys` (unit).
  - Real: actual registry resolution/cleanup across primary/shared scopes.
  - Faked: in-memory primary/shared secure stores.
  - Proves / registration: test/features/account_migration/application/migration_secure_storage_cleanup_test.dart:27: Explicit reset deletes every fixed and discovered group/media reference; non-explicit cleanup separately preserves device-local authority. Registered: affected-storage, host-all.

**Remaining gaps**

- Combined widget/registry proof fakes actual DB deletion/native notifications/secure store. Real filesystem/platform erasure and unrelated OS state were not exercised.

### LINKED — Flag-gated linked devices and durable linked state

#### DC-020 — Linked direct installations converge under the enabled feature

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-020.

**Steps**

1. Enable only the intended direct linked selectors.
2. Admit exact installations and send blob-free/media events under current roster.
3. Compare each installation’s logical conversation and per-target custody.

**Conditions:** platform: shared source/host SQL; multi-installation run unverified; connectivity: n/a; offline: n/a; app state: foreground; input: admitted initialized linked roster; controlled selectors; recovery: n/a.

**Expected:** Controlled linked installations converge only authorized supported events with stable identity and no conflicting legacy fallback.

**Inspected test evidence**

- [test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart](../../test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart) — `TC-361-02a linked blob-free event authoring stages the exact target batch before transport` (integration).
  - Real: actual event fanout authoring/SQL atomic all-target stage.
  - Faked: crypto/encryption and physical transport callbacks.
  - Proves / registration: test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart:1044: Commits exact per-target blob-free batch before egress and isolates partial outcomes; no real multi-installation delivery or native keys. Registered: affected-identity, host-all.
- [test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart](../../test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart) — `TC-361-03a linked physical transport maps to one logical event authority` (integration).
  - Real: actual reverse transport->logical authority and receiving/database application.
  - Faked: signature/crypto transport inputs; fake bridge.
  - Proves / registration: test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart:1312: Maps exact active physical sender to logical event authority and rejects contradictory/revoked origins before effect; no real network-authenticated session proof. Registered: affected-identity, host-all.
- [test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart](../../test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart) — `TC-362-02a linked fanout generation stages N×M rows once with secure-key discipline` (unit).
  - Real: production real FFI SQLite media/fanout repository and transaction; per-target custody markers.
  - Faked: fixture prepared artifacts; fake secure store/crypto/relay receipts.
  - Proves / registration: test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart:9629: Stages2attachments x2targets all at once, stores key references, makes exact replay idempotent; does not upload/decode real image/voice/private media. Registered: affected-conversation, group-media-storage-preservation, host-all, strict-group-media-manifest.
- [test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart](../../test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart) — `TC-362-02b crash after upload reopens the complete persisted generation and binds the full v108 batch atomically` (unit).
  - Real: actual file-backed SQLite reopen/full-generation binding and CAS.
  - Faked: fabricated per-target upload receipts/ciphertext; fixture secure store.
  - Proves / registration: test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart:9876: Fabricates crash-after-upload stored state, reopens and binds complete v108 batches atomically; not a real process killed after real relay upload. Registered: affected-conversation, group-media-storage-preservation, host-all, strict-group-media-manifest.

**Remaining gaps**

- Real transactions/identity mapping exist; crypto/transport/receipts are seams and no complete actual multi-installation text/media convergence evidence audited/executed.

#### LINKED-001 — Default-off build hides new linked-device authoring but preserves durable installed authority

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-020.

**Steps**

1. Use default-off linked authoring build/policy.
2. Inspect new onboarding/QR entries.
3. Load a previously active durable linked credential and choose its restricted runtime.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: default-off authoring versus persisted active credential; recovery: flag rollback/restart.

**Expected:** New linked authoring remains hidden/refused while retained installed authority never becomes a different primary/legacy identity.

**Inspected test evidence**

- [test/features/identity/presentation/screens/identity_choice_wired_test.dart](../../test/features/identity/presentation/screens/identity_choice_wired_test.dart) — `TC-360-01a linked-secondary transport identity is distinct stable and fail-closed` (widget).
  - Real: actual onboarding entry gating/navigation.
  - Faked: identity/ML-KEM/repository callbacks; linked setup replaced by route stand-in; injected selector.
  - Proves / registration: test/features/identity/presentation/screens/identity_choice_wired_test.dart:441: Default-off selector or absent builder hides Link this device; enabled+builder dispatches exactly the supplied restricted route. Actual setup widget/storage/native crypto is not run. Registered: affected-identity, host-all.
- [test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart](../../test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart) — `TC-360-01a linked-secondary transport identity is distinct stable and fail-closed` (unit).
  - Real: RoleAwareDeferredRuntimeStart exact role selection.
  - Faked: authority snapshots/start callbacks; source-string wiring assertions.
  - Proves / registration: test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart:1517: Active linked authority starts restricted foundation only; preparing/partial/unreadable states start neither runtime. Generic primary fallback is forbidden; no actual native transport or signed-build rollback. Registered: group-media-storage-preservation, host-all.

**Remaining gaps**

- Host selectors/snapshots and source default constants prove policy seams, not an installed flag-on->flag-off signed-binary upgrade with actual native secure credential.

#### LINKED-002 — Flag-enabled phrase-based linked-secondary setup and dual-signed device QR

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-020.

**Steps**

1. Enter the account recovery phrase through Link this device on the secondary.
2. Create a distinct local transport credential under linked authority.
3. Present its dual-signed device QR to the dedicated trust/bootstrap entry and confirm exact device explicitly.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: linked selector enabled; account phrase and new transport identity; recovery: n/a.

**Expected:** Secondary transport is distinct/stable and QR can only stage exact pending authority for explicit trust; scanning cannot become ordinary contact admission.

**Inspected test evidence**

- [test/features/identity/presentation/screens/identity_choice_wired_test.dart](../../test/features/identity/presentation/screens/identity_choice_wired_test.dart) — `TC-360-01a linked-secondary transport identity is distinct stable and fail-closed` (widget).
  - Real: actual onboarding entry gating/navigation.
  - Faked: identity/ML-KEM/repository callbacks; linked setup replaced by route stand-in; injected selector.
  - Proves / registration: test/features/identity/presentation/screens/identity_choice_wired_test.dart:441: Default-off selector or absent builder hides Link this device; enabled+builder dispatches exactly the supplied restricted route. Actual setup widget/storage/native crypto is not run. Registered: affected-identity, host-all.
- [test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart](../../test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart) — `TC-360-01a linked-secondary transport identity is distinct stable and fail-closed` (unit).
  - Real: RoleAwareDeferredRuntimeStart exact role selection.
  - Faked: authority snapshots/start callbacks; source-string wiring assertions.
  - Proves / registration: test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart:1517: Active linked authority starts restricted foundation only; preparing/partial/unreadable states start neither runtime. Generic primary fallback is forbidden; no actual native transport or signed-build rollback. Registered: group-media-storage-preservation, host-all.
- [test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart](../../test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart) — `TC-360-02a dual-signed linked-device QR stages only exact known-contact pending authority` (integration).
  - Real: real versioned QR parser/body hashing/peer derivation; production FFI SQLite direct-binding repository.
  - Faked: _FakeSigner SHA256-based signature-semantic model; injected clock/identity fixtures.
  - Proves / registration: test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart:318: Dual-body/signature/time/purpose/key-derivation/refusal matrix stages only pending exact known contact, changes no ordinary contact and reissued QR is idempotent. This is NOT genuine Ed25519 signature verification. Registered: affected-identity, host-all.
- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `TC-360-02a dual-signed linked-device QR stages only exact known-contact pending authority` (widget).
  - Real: actual QR scan protocol dispatch and no-contact side-effect boundary.
  - Faked: scanner onScanned callback instead of camera; linked handler; fake bridge/repos.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:777: Linked document goes only to dedicated trust handler; ordinary scan without handler refuses instead of falling through to contact parser/encryption. Registered: affected-identity, host-all.

**Remaining gaps**

- Corrected source flow: linked_device_setup_wired.dart:106 takes phrase and calls secondary setup; it is not a primary-issued pairing QR.
- Onboarding test substitutes setup route; no behavior test of full LinkedDeviceSetupWired submit/native key creation/secure persistence/QR display and remote trust in one journey.

#### LINKED-003 — Reject forged, expired, replayed or wrong-protocol linked QR without adding an ordinary contact

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-020.

**Steps**

1. Scan forged/single-signed/wrong-purpose/version/expired/future linked QR.
2. Replay an already staged immutable binding.
3. Inspect unchanged contact/ML-KEM and no active device admission.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: tampered/expired/replayed/wrong protocol QR; recovery: reissued valid timestamp.

**Expected:** Invalid protocol/authority is refused; valid reissue is idempotent pending only and never an ordinary contact.

**Inspected test evidence**

- [test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart](../../test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart) — `TC-360-02a dual-signed linked-device QR stages only exact known-contact pending authority` (integration).
  - Real: real versioned QR parser/body hashing/peer derivation; production FFI SQLite direct-binding repository.
  - Faked: _FakeSigner SHA256-based signature-semantic model; injected clock/identity fixtures.
  - Proves / registration: test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart:318: Dual-body/signature/time/purpose/key-derivation/refusal matrix stages only pending exact known contact, changes no ordinary contact and reissued QR is idempotent. This is NOT genuine Ed25519 signature verification. Registered: affected-identity, host-all.
- [test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart](../../test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart) — `TC-360-02a dual-signed linked-device QR stages only exact known-contact pending authority` (widget).
  - Real: actual QR scan protocol dispatch and no-contact side-effect boundary.
  - Faked: scanner onScanned callback instead of camera; linked handler; fake bridge/repos.
  - Proves / registration: test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart:777: Linked document goes only to dedicated trust handler; ordinary scan without handler refuses instead of falling through to contact parser/encryption. Registered: affected-identity, host-all.

**Remaining gaps**

- Actual parser/SQL and no-legacy dispatch are tested, but signature model is SHA256 over public key/data rather than genuine Ed25519; native camera/bridge authentication not joined.

#### LINKED-004 — Observe pending sibling device in contact profile; verify/reject/revoke the exact installation

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-020.

**Steps**

1. Open contact profile pending-device safety card.
2. Verify/Reject/Revoke one exact rendered installation.
3. Reload roster/safety authority and preserve siblings/trusted contact.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: pending/active/revoked bindings and stale UI belief; recovery: n/a.

**Expected:** Only exact current fingerprint/account belief changes trust and target resolution; staging alone never admits.

**Inspected test evidence**

- [test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart](../../test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart) — `TC-360-03a direct-device trust owns exact admission revocation and legacy resolution` (integration).
  - Real: DatabaseDirectContactDeviceTrust; actual FFI SQLite roster/fingerprint CAS/target resolution.
  - Faked: clock; fixture account/device material.
  - Proves / registration: test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart:688: Exact fingerprint/account key gates Verify/Reject/Revoke; pending never authorizes, active/revoked target sets and initialized legacy resolution remain exact. Signature setup uses fake signer. Registered: affected-identity, host-all.
- [test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart](../../test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart) — `TC-360-03b direct-device trust UI changes only the reviewed contact safety authority` (widget).
  - Real: actual profile device cards and safety-number view/actions.
  - Faked: _FakeDirectContactDeviceTrust; fixture contact/device fields.
  - Proves / registration: test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart:347: Pending displays exact account/device fingerprint, Verify passes rendered belief fields; active roster changes safety authority and exposes revoke. Does not persist via the real DB trust callback in this widget test. Registered: host-all.

**Remaining gaps**

- Real DB CAS and profile callback arguments are substantive but separately tested; no actual remote device status convergence or profile wired to real DB/native proof in one journey.

#### LINKED-005 — Read restricted linked status/group list, retry load failures and prevent unavailable modalities

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-020.

**Steps**

1. Open restricted linked status/group list.
2. Refresh while identity/group authority is pending or loading fails.
3. Keep unsupported modalities unavailable and retry current supported content only.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: settled/unsettled authority and failed group-list read; recovery: explicit status refresh.

**Expected:** Status remains truthful; unavailable authority/modality cannot become a working composer or implicit legacy fallback.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `TC-361-03b linked runtime starts only direct blob-free event owners — the restricted conversation surface refuses media and voice authoring while the default gate keeps the incumbent full surface` (widget).
  - Real: actual restricted conversation UI/media and mic guards.
  - Faked: fake recorder/repositories/bridge; injected modality gate.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:17047: Restricted blob-free mode refuses voice before recorder and media before picker, showing specific copy; default gate retains full surface. Later strict-media enabled cohort is separate. Registered: affected-conversation, host-all.
- [test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart](../../test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart) — `TC-363-03a linked startup defers without identity and orders protected recovery before read-only refresh` (unit).
  - Real: RoleAwareDeferredRuntimeStart no-identity deferral.
  - Faked: authority/start callbacks; source-order string assertions.
  - Proves / registration: test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart:2773: No identity loads/starts linked authority; after identity exists starts once. Source assertions require inbox/bootstrap/authority recovery before read-only refresh, not a real widget/OS start. Registered: group-media-storage-preservation, host-all.
- [test/features/groups/presentation/group_conversation_wired_test.dart](../../test/features/groups/presentation/group_conversation_wired_test.dart) — `TC-365-04a linked group exposes only ordinary media and voice` (widget).
  - Real: actual LinkedGroupConversationWired media/voice projection and guards.
  - Faked: load group/protected rows/media/settled-authority callbacks; attach/record/open/retry callbacks.
  - Proves / registration: test/features/groups/presentation/group_conversation_wired_test.dart:10642: Current strict cohort exposes bound ordinary image/voice, refuses unbound/private/unsettled state, and dispatches exact current operations; no native capture/playback or full group replica convergence. Registered: affected-groups, host-all.

**Remaining gaps**

- Restricted modality and startup ordering have causal tests, but no behavior test of LinkedGroupReadOnlyStatus loading/error/refresh failure. Source _load at linked_device_setup_wired.dart:249 awaits repository without visible error handling.

**Open questions**

- What status/retry UI is required after group-list/authority load failure? Current source-string checks do not define it.

#### LINKED-006 — Flag-enabled text/edit/delete/reaction fanout converges across admitted installations

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-020.

**Steps**

1. Enable blob-free linked event authoring and admit exact current devices.
2. Send text/edit/delete/reaction Add/Remove.
3. Receive as one logical contact and retry surviving target rows independently.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: text/edit/DFE/reaction Add/Remove; event selector ON; recovery: partial target retry.

**Expected:** All-target batches commit atomically and each supported semantic event converges under exact physical-to-logical authority.

**Inspected test evidence**

- [test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart](../../test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart) — `TC-361-02a linked blob-free event authoring stages the exact target batch before transport` (integration).
  - Real: actual event fanout authoring/SQL atomic all-target stage.
  - Faked: crypto/encryption and physical transport callbacks.
  - Proves / registration: test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart:1044: Commits exact per-target blob-free batch before egress and isolates partial outcomes; no real multi-installation delivery or native keys. Registered: affected-identity, host-all.
- [test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart](../../test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart) — `TC-361-03a linked physical transport maps to one logical event authority` (integration).
  - Real: actual reverse transport->logical authority and receiving/database application.
  - Faked: signature/crypto transport inputs; fake bridge.
  - Proves / registration: test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart:1312: Maps exact active physical sender to logical event authority and rejects contradictory/revoked origins before effect; no real network-authenticated session proof. Registered: affected-identity, host-all.
- [test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart](../../test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart) — `TC-361-03b linked runtime starts only direct blob-free event owners — the exact v113 drain completes only nonnull blob-free rows and leaves historical, media and unclassifiable rows byte-untouched with the authoring selector OFF` (unit).
  - Real: actual restricted durable-row drain/classification with authoring selector OFF.
  - Faked: custody repositories/store callback; loader deliberately returns wrong rows.
  - Proves / registration: test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart:510: Selector default off still drains only qualifying nonnull blob-free rows; historical/media/unclassifiable rows remain untouched. No real relay transfer. Registered: affected-transport, host-all.

**Remaining gaps**

- Real SQL staging/authority exists; native crypto/network and all event types across actual installations after restart are not a single proof.

#### LINKED-007 — Flag-enabled media/voice/private fanout reaches each intended installation with correct custody

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-020.

**Steps**

1. Enable explicit media/event/strict selectors for initialized linked roster.
2. Prepare one shared artifact and exact per-target envelopes/custody.
3. Deliver/retry each ordinary/voice/private target and open full correct content.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: explicitly enabled linked media/voice/private cohort; recovery: partial target failure and SQLite reopen.

**Expected:** Every intended installation receives correct policy-preserving media under independent immutable custody without duplicated shared artifacts.

**Inspected test evidence**

- [test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart](../../test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart) — `TC-362-02a linked fanout generation stages N×M rows once with secure-key discipline` (unit).
  - Real: production real FFI SQLite media/fanout repository and transaction; per-target custody markers.
  - Faked: fixture prepared artifacts; fake secure store/crypto/relay receipts.
  - Proves / registration: test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart:9629: Stages2attachments x2targets all at once, stores key references, makes exact replay idempotent; does not upload/decode real image/voice/private media. Registered: affected-conversation, group-media-storage-preservation, host-all, strict-group-media-manifest.
- [test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart](../../test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart) — `TC-362-02b crash after upload reopens the complete persisted generation and binds the full v108 batch atomically` (unit).
  - Real: actual file-backed SQLite reopen/full-generation binding and CAS.
  - Faked: fabricated per-target upload receipts/ciphertext; fixture secure store.
  - Proves / registration: test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart:9876: Fabricates crash-after-upload stored state, reopens and binds complete v108 batches atomically; not a real process killed after real relay upload. Registered: affected-conversation, group-media-storage-preservation, host-all, strict-group-media-manifest.
- [test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart](../../test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart) — `TC-362-04a linked resume drains only the exact strict-media convergers` (unit).
  - Real: actual linked resume owner selection/order.
  - Faked: strict-media converger callbacks and lifecycle/service seams.
  - Proves / registration: test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart:590: Linked resume calls only exact strict-media convergers, preserving generic media owners at zero; current accepted rows are independent of new-authoring selector. Registered: affected-transport, host-all.

**Remaining gaps**

- 2x2/large-generation transactional custody is tested with fake keys/receipts; no actual native media/private decoder/playback at all linked targets. Cannot infer default/store125 behavior.

#### LINKED-008 — Flag rollback refuses new fanout while draining already-committed durable rows

**Coverage:** strong. **Execution:** not_run. **Catalog:** DC-020.

**Steps**

1. Persist linked event/media custody under an enabled authoring cohort.
2. Disable new authoring selectors.
3. Drain only accepted exact durable owners while preserving historical/unclassifiable siblings.

**Conditions:** platform: shared local authoring/drain policy and SQL boundary; connectivity: n/a; offline: n/a; app state: foreground; input: selector OFF with previously committed marked rows; recovery: durable exact-owner drain.

**Expected:** Rollback refuses new fanout without stranding or reinterpreting already committed exact linked work.

**Inspected test evidence**

- [test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart](../../test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart) — `TC-361-03b linked runtime starts only direct blob-free event owners — the exact v113 drain completes only nonnull blob-free rows and leaves historical, media and unclassifiable rows byte-untouched with the authoring selector OFF` (unit).
  - Real: actual restricted durable-row drain/classification with authoring selector OFF.
  - Faked: custody repositories/store callback; loader deliberately returns wrong rows.
  - Proves / registration: test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart:510: Selector default off still drains only qualifying nonnull blob-free rows; historical/media/unclassifiable rows remain untouched. No real relay transfer. Registered: affected-transport, host-all.
- [test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart](../../test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart) — `TC-362-04a linked resume drains only the exact strict-media convergers` (unit).
  - Real: actual linked resume owner selection/order.
  - Faked: strict-media converger callbacks and lifecycle/service seams.
  - Proves / registration: test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart:590: Linked resume calls only exact strict-media convergers, preserving generic media owners at zero; current accepted rows are independent of new-authoring selector. Registered: affected-transport, host-all.
- [test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart](../../test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart) — `TC-362-02a linked fanout generation stages N×M rows once with secure-key discipline` (unit).
  - Real: production real FFI SQLite media/fanout repository and transaction; per-target custody markers.
  - Faked: fixture prepared artifacts; fake secure store/crypto/relay receipts.
  - Proves / registration: test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart:9629: Stages2attachments x2targets all at once, stores key references, makes exact replay idempotent; does not upload/decode real image/voice/private media. Registered: affected-conversation, group-media-storage-preservation, host-all, strict-group-media-manifest.

**Remaining gaps**

- Strong is scoped to local selection/ownership/transaction invariants; actual rebuilt signed APK rollback/native credentials and successful relay delivery were not executed.

#### LINKED-009 — Restart/quarantine/revoke a linked authority without falling back to a conflicting legacy transport

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-020.

**Steps**

1. Restart with active/partial/quarantined/revoked linked credentials.
2. Resolve exact current transport/roster before routing content.
3. Refuse inconsistent authority rather than falling back to conflicting legacy target.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: active/partial/revoked authority and initialized roster; recovery: restart/quarantine.

**Expected:** Retained authority and explicit revocation fail closed without identity substitution or unauthorized event application.

**Inspected test evidence**

- [test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart](../../test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart) — `TC-360-01a linked-secondary transport identity is distinct stable and fail-closed` (unit).
  - Real: RoleAwareDeferredRuntimeStart exact role selection.
  - Faked: authority snapshots/start callbacks; source-string wiring assertions.
  - Proves / registration: test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart:1517: Active linked authority starts restricted foundation only; preparing/partial/unreadable states start neither runtime. Generic primary fallback is forbidden; no actual native transport or signed-build rollback. Registered: group-media-storage-preservation, host-all.
- [test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart](../../test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart) — `TC-360-03a direct-device trust owns exact admission revocation and legacy resolution` (integration).
  - Real: DatabaseDirectContactDeviceTrust; actual FFI SQLite roster/fingerprint CAS/target resolution.
  - Faked: clock; fixture account/device material.
  - Proves / registration: test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart:688: Exact fingerprint/account key gates Verify/Reject/Revoke; pending never authorizes, active/revoked target sets and initialized legacy resolution remain exact. Signature setup uses fake signer. Registered: affected-identity, host-all.
- [test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart](../../test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart) — `TC-361-03a linked physical transport maps to one logical event authority` (integration).
  - Real: actual reverse transport->logical authority and receiving/database application.
  - Faked: signature/crypto transport inputs; fake bridge.
  - Proves / registration: test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart:1312: Maps exact active physical sender to logical event authority and rejects contradictory/revoked origins before effect; no real network-authenticated session proof. Registered: affected-identity, host-all.

**Remaining gaps**

- Role/canonical trust checks are causal at host seams; real secure-store corruption/OS restart and authenticated transport revoke race remain unverified.

#### LINKED-010 — Linked group enrollment/bootstrap/key epochs gate content before authority settles

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Use group-scoped same-account linked QR/bootstrap entry.
2. Persist roster/key/genesis and required protected authority receipts.
3. Enable content only after prerequisites settle and ACK exact durable apply.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: linked group bootstrap, key epochs and unsettled prerequisites; recovery: bootstrap/authority replay before content.

**Expected:** Unsettled roster/key epochs cannot authorize linked group content or premature relay ACK.

**Inspected test evidence**

- [test/features/groups/domain/repositories/group_repository_impl_test.dart](../../test/features/groups/domain/repositories/group_repository_impl_test.dart) — `TC-363-01b protected self bootstrap commits atomically before exact relay ACK` (unit).
  - Real: production group/bootstrap repository and current FFI SQLite transactions.
  - Faked: FakeSecureKeyStore; authenticated genesis supplied as fixture.
  - Proves / registration: test/features/groups/domain/repositories/group_repository_impl_test.dart:609: Commits group/roster/key-reference/genesis atomically before exact ACK authorization; fixture signature/key bytes do not prove remote verification. Registered: affected-groups, host-all.
- [test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart](../../test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart) — `TC-363-03a linked startup defers without identity and orders protected recovery before read-only refresh` (unit).
  - Real: RoleAwareDeferredRuntimeStart no-identity deferral.
  - Faked: authority/start callbacks; source-order string assertions.
  - Proves / registration: test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart:2773: No identity loads/starts linked authority; after identity exists starts once. Source assertions require inbox/bootstrap/authority recovery before read-only refresh, not a real widget/OS start. Registered: group-media-storage-preservation, host-all.
- [test/core/services/p2p_service_inbox_ack_ordering_test.dart](../../test/core/services/p2p_service_inbox_ack_ordering_test.dart) — `TC-364-03a protected content applies in authenticated authority order before exact ACK` (unit).
  - Real: P2PServiceImpl protected-lane discriminator/order/ACK logic.
  - Faked: fake bridge/in-memory staging; replay prerequisite callback and failed ACK.
  - Proves / registration: test/core/services/p2p_service_inbox_ack_ordering_test.dart:3127: Signed inner discriminator selects lane; missing prerequisites defer and accepted apply precedes exact ACK/retry. Actual signature verification/native relay is outside this fixture. Registered: affected-transport, group-media-storage-preservation, host-all, strict-group-media-manifest.

**Remaining gaps**

- Production SQLite atomic materialization and orchestrator order are tested; real signatures/key wrapping/native secure-store/three-party bootstrap transport are seams. Full phrase-restore group convergence stays explicitly planned.

#### LINKED-011 — Linked group send/receive/retry/media and notification state respect retained membership

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open a settled protected linked group with retained membership.
2. Send/receive/retry supported content/media/voice and update notification/read state.
3. Remove/demote membership and refuse stale content/actions.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: flag-gated protected group content and strict ordinary media/voice; recovery: receipt/authority replay and membership drift.

**Expected:** Only current settled membership authorizes supported protected content and exact retry/notification ownership.

**Inspected test evidence**

- [test/features/groups/application/send_group_message_use_case_test.dart](../../test/features/groups/application/send_group_message_use_case_test.dart) — `TC-364-01a protected blob-free group authoring freezes physical custody with zero pubsub` (unit).
  - Real: actual protected group authoring target/receipt state machine.
  - Faked: strict repository/inbox store/crypto callbacks; in-memory roster.
  - Proves / registration: test/features/groups/application/send_group_message_use_case_test.dart:1063: Freezes current physical-device targets, excludes revoked device and persists before strict custody with zero pubsub; remote real content/decode is not tested. Registered: affected-groups, group-harness-contract, host-all, strict-group-media-manifest.
- [test/core/services/p2p_service_inbox_ack_ordering_test.dart](../../test/core/services/p2p_service_inbox_ack_ordering_test.dart) — `TC-364-03a protected content applies in authenticated authority order before exact ACK` (unit).
  - Real: P2PServiceImpl protected-lane discriminator/order/ACK logic.
  - Faked: fake bridge/in-memory staging; replay prerequisite callback and failed ACK.
  - Proves / registration: test/core/services/p2p_service_inbox_ack_ordering_test.dart:3127: Signed inner discriminator selects lane; missing prerequisites defer and accepted apply precedes exact ACK/retry. Actual signature verification/native relay is outside this fixture. Registered: affected-transport, group-media-storage-preservation, host-all, strict-group-media-manifest.
- [test/features/groups/presentation/group_conversation_wired_test.dart](../../test/features/groups/presentation/group_conversation_wired_test.dart) — `TC-365-04a linked group exposes only ordinary media and voice` (widget).
  - Real: actual LinkedGroupConversationWired media/voice projection and guards.
  - Faked: load group/protected rows/media/settled-authority callbacks; attach/record/open/retry callbacks.
  - Proves / registration: test/features/groups/presentation/group_conversation_wired_test.dart:10642: Current strict cohort exposes bound ordinary image/voice, refuses unbound/private/unsettled state, and dispatches exact current operations; no native capture/playback or full group replica convergence. Registered: affected-groups, host-all.

**Remaining gaps**

- Current linked group UI includes later strict media/voice cohort; do not generalize old blob-free test title to all current capabilities.
- Load/send/native/crypto/notification seams are separate; no whole real multi-installation group+media+OS notification evidence audited/executed.

#### LINKED-012 — Group pending sibling verification/rejection and invitation revoke preserve trust

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Hold an account-signed announced sibling as pending.
2. Explicitly Verify or Reject exact pending device; revoke invitation/device authority as applicable.
3. Preserve trusted roster/siblings and forbid implicit admission.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: pending group sibling; Verify/Reject/revoke; recovery: stale/repeated decision.

**Expected:** Pending announcement never auto-admits; explicit decisions affect only authorized exact trust state.

**Inspected test evidence**

- [test/features/groups/application/manage_pending_sibling_device_test.dart](../../test/features/groups/application/manage_pending_sibling_device_test.dart) — `verify admits the device and clears the pending entry` (unit).
  - Real: real verify/admit trust transition.
  - Faked: InMemoryGroupRepository; fixture verified account key/announced device.
  - Proves / registration: test/features/groups/application/manage_pending_sibling_device_test.dart:119: Explicit Verify admits exact pending device and clears pending; signed announcement authenticity is supplied by caller. Registered: affected-groups, host-all.
- [test/features/groups/application/manage_pending_sibling_device_test.dart](../../test/features/groups/application/manage_pending_sibling_device_test.dart) — `reject drops the pending entry and never admits` (unit).
  - Real: real pending-device reject transition.
  - Faked: in-memory group repository.
  - Proves / registration: test/features/groups/application/manage_pending_sibling_device_test.dart:174: Reject clears pending with no admitted roster device; flag-off hold and marked-shell cases preserve refusal semantics. Registered: affected-groups, host-all.
- [test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart](../../test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart) — `TC-360-03a direct-device trust owns exact admission revocation and legacy resolution` (integration).
  - Real: DatabaseDirectContactDeviceTrust; actual FFI SQLite roster/fingerprint CAS/target resolution.
  - Faked: clock; fixture account/device material.
  - Proves / registration: test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart:688: Exact fingerprint/account key gates Verify/Reject/Revoke; pending never authorizes, active/revoked target sets and initialized legacy resolution remain exact. Signature setup uses fake signer. Registered: affected-identity, host-all.

**Remaining gaps**

- Group transitions use in-memory repo and assumed verified signing authority; direct revoke uses real SQL separately. No single real group invitation-revoke/pending-device native trust journey.

### UPDATE — Signed update checks and update-required UI

#### UPDATE-001 — After-first-frame signed version check returns no update, soft update or required update

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Start the app and allow its first frame.
2. Check an older/current/newer installed build against a signed policy.
3. Observe no notice, optional banner or required gate as appropriate.

**Conditions:** platform: shared Dart; Android emulator/iOS simulator scenarios; connectivity: controlled signed version source; production HTTPS unverified; offline: n/a; app state: foreground; input: installed build below minimum, between minimum/latest, current; recovery: failed download may use valid cached policy.

**Expected:** A completed authenticated check selects the correct decision without delaying the first usable frame.

**Inspected test evidence**

- [test/features/update_check/application/update_check_service_test.dart](../../test/features/update_check/application/update_check_service_test.dart) — `none, soft and hard` (unit).
  - Real: UpdateCheckService; Ed25519 verifier and policy/ratchet; atomic temporary-file state store.
  - Faked: version-file server responses and test signing keys; installed build/platform/clock inputs.
  - Proves / registration: test/features/update_check/application/update_check_service_test.dart:66: Real signed envelopes select none/soft/hard for installed builds; no real production version host or app bootstrap. Registered: host-all, update-check.
- [test/features/update_check/presentation/update_required_gate_test.dart](../../test/features/update_check/presentation/update_required_gate_test.dart) — `a pushed route, and Back does not pop it` (widget).
  - Real: UpdateRequiredGate; back guard; Flutter navigator/focus/semantics.
  - Faked: update service; call capability; store launcher; host platform-back stimulus.
  - Proves / registration: test/features/update_check/presentation/update_required_gate_test.dart:199: Hard decision overlays a pushed route; handled Back leaves route and gate in place. Registered: host-all, update-check.
- [integration_test/scripts/run_production_update_check.dart](../../integration_test/scripts/run_production_update_check.dart) — `kx0020` (sims).
  - Real: production update verifier/controller; registered Android/iOS app UI and Android native posting when executed; typed artifact validator.
  - Faked: test version source/signing key; clock advancement; controlled runner triggers; OS scheduling not exercised.
  - Proves / registration: integration_test/scripts/run_production_update_check.dart:62: tool/sims/production_update_check_criteria.dart:36 requires exact signed-envelope hashes, new checks, unique successful UI receipts and native card/target evidence. Stock published artifact/version-host and real elapsed scheduling are separate. Registered: kx0020, kx0021, kx0022, kx0023, kx0024, kx0025, kx0026, kx0027, kx0028. Exact registered scenario kx0020; see production_update_check_criteria.dart:12 phase map (0025/0027 native controlled runner).
- [integration_test/scripts/run_production_update_check.dart](../../integration_test/scripts/run_production_update_check.dart) — `kx0021` (sims).
  - Real: production update verifier/controller; registered Android/iOS app UI and Android native posting when executed; typed artifact validator.
  - Faked: test version source/signing key; clock advancement; controlled runner triggers; OS scheduling not exercised.
  - Proves / registration: integration_test/scripts/run_production_update_check.dart:62: tool/sims/production_update_check_criteria.dart:36 requires exact signed-envelope hashes, new checks, unique successful UI receipts and native card/target evidence. Stock published artifact/version-host and real elapsed scheduling are separate. Registered: kx0020, kx0021, kx0022, kx0023, kx0024, kx0025, kx0026, kx0027, kx0028. Exact registered scenario kx0021; see production_update_check_criteria.dart:12 phase map (0025/0027 native controlled runner).

**Remaining gaps**

- Service and widget proofs are composed through fakes in host tests; live scenarios use TEST sources and were not run here.
- No audited signed-store launch/production-host first-frame trace.

#### UPDATE-002 — Dismiss optional update for one build; higher build shows a fresh banner

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Receive an optional update banner.
2. Dismiss it and resume while the same latest build remains.
3. Provide a higher signed build and resume again.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground and explicit resume; input: same versus higher latestBuild; recovery: persisted dismissal.

**Expected:** Dismissal persists for the same latest build, a higher build reappears, and underlying home state survives.

**Inspected test evidence**

- [test/features/update_check/application/update_check_service_test.dart](../../test/features/update_check/application/update_check_service_test.dart) — `dismissal holds for the same latestBuild; a higher one returns` (unit).
  - Real: UpdateCheckService; Ed25519 verifier and policy/ratchet; atomic temporary-file state store.
  - Faked: version-file server responses and test signing keys; installed build/platform/clock inputs.
  - Proves / registration: test/features/update_check/application/update_check_service_test.dart:103: Persists dismissal and accepts a higher signed build; this service case has no OS banner. Registered: host-all, update-check.
- [test/features/update_check/presentation/update_available_banner_test.dart](../../test/features/update_check/presentation/update_available_banner_test.dart) — `a dismissal holds for the same latestBuild and the banner returns for a higher one` (widget).
  - Real: UpdateCheckController; actual banner/widget state/navigation stand-in.
  - Faked: FakeUpdateCheckService; store launcher and lifecycle stimulus.
  - Proves / registration: test/features/update_check/presentation/update_available_banner_test.dart:131: Tap Not now records build120, resume keeps it hidden, higher build121 reappears and underlying UI state survives. Registered: host-all, update-check.

**Remaining gaps**

- Widget service is fake; process relaunch and a real server-to-home UI path are not joined in one proof.

#### UPDATE-003 — Required update blocks touch/back/accessibility behind the gate and launches correct store

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Receive a required-update decision while a route is open.
2. Try touch/focus/semantics and system Back behind the gate.
3. Tap Update and observe the platform store target.

**Conditions:** platform: Android/iOS widget cases; registered mobile scenarios; connectivity: n/a; offline: n/a; app state: root, pushed/deep-linked routes; input: valid hard policy; recovery: n/a.

**Expected:** Private content is blocked, Back does not dismiss the gate, and the action chooses the built-in correct platform store target.

**Inspected test evidence**

- [test/features/update_check/presentation/update_required_gate_test.dart](../../test/features/update_check/presentation/update_required_gate_test.dart) — `a pushed route, and Back does not pop it` (widget).
  - Real: UpdateRequiredGate; back guard; Flutter navigator/focus/semantics.
  - Faked: update service; call capability; store launcher; host platform-back stimulus.
  - Proves / registration: test/features/update_check/presentation/update_required_gate_test.dart:199: Hard decision overlays a pushed route; handled Back leaves route and gate in place. Registered: host-all, update-check.
- [test/features/update_check/presentation/update_required_gate_test.dart](../../test/features/update_check/presentation/update_required_gate_test.dart) — `Android opens the Play page` (widget).
  - Real: actual UpdateRequiredGate action; platform URL selection.
  - Faked: update service; successful URL launcher.
  - Proves / registration: test/features/update_check/presentation/update_required_gate_test.dart:181: Tapping Update selects the exact built-in Android store URI; it does not prove an installed store app opens. Registered: host-all, update-check.
- [integration_test/scripts/run_production_update_check.dart](../../integration_test/scripts/run_production_update_check.dart) — `kx0021` (sims).
  - Real: production update verifier/controller; registered Android/iOS app UI and Android native posting when executed; typed artifact validator.
  - Faked: test version source/signing key; clock advancement; controlled runner triggers; OS scheduling not exercised.
  - Proves / registration: integration_test/scripts/run_production_update_check.dart:62: tool/sims/production_update_check_criteria.dart:36 requires exact signed-envelope hashes, new checks, unique successful UI receipts and native card/target evidence. Stock published artifact/version-host and real elapsed scheduling are separate. Registered: kx0020, kx0021, kx0022, kx0023, kx0024, kx0025, kx0026, kx0027, kx0028. Exact registered scenario kx0021; see production_update_check_criteria.dart:12 phase map (0025/0027 native controlled runner).
- [integration_test/scripts/run_production_update_check.dart](../../integration_test/scripts/run_production_update_check.dart) — `kx0028` (sims).
  - Real: production update verifier/controller; registered Android/iOS app UI and Android native posting when executed; typed artifact validator.
  - Faked: test version source/signing key; clock advancement; controlled runner triggers; OS scheduling not exercised.
  - Proves / registration: integration_test/scripts/run_production_update_check.dart:62: tool/sims/production_update_check_criteria.dart:36 requires exact signed-envelope hashes, new checks, unique successful UI receipts and native card/target evidence. Stock published artifact/version-host and real elapsed scheduling are separate. Registered: kx0020, kx0021, kx0022, kx0023, kx0024, kx0025, kx0026, kx0027, kx0028. Exact registered scenario kx0028; see production_update_check_criteria.dart:12 phase map (0025/0027 native controlled runner).

**Remaining gaps**

- Host launcher is a recording callback; exact store target is tested but actual store opening/install/back flow is not certified.
- Mobile scenarios are registered, not executed in this audit.

#### UPDATE-004 — An incoming/outgoing/active call defers required-update blocking until safe

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Show the hard-update gate.
2. Receive/start a call and progress to connected.
3. End the call and observe the gate again.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: active call versus terminal call; input: incoming, outgoing, connected and ended projections; recovery: n/a.

**Expected:** Incoming/outgoing/active call controls remain reachable; after the call ends, the required gate returns.

**Inspected test evidence**

- [test/features/update_check/presentation/update_required_gate_test.dart](../../test/features/update_check/presentation/update_required_gate_test.dart) — `not shown during an incoming or active call; back after it ends; the call surface is never covered` (widget).
  - Real: real update/call overlay widgets; UpdateCheckController.
  - Faked: call state source/audio graph; update service; store launcher.
  - Proves / registration: test/features/update_check/presentation/update_required_gate_test.dart:301: Incoming/connected projections expose hit-testable call surfaces; ended projection restores the hard overlay. No actual call audio or native CallKit/Telecom boundary. Registered: host-all, update-check.

**Remaining gaps**

- Call capability/audio/native system call UI is simulated; no real incoming call overlaps the update gate in these assertions.

#### UPDATE-005 — Offline/HTTP/signature/schema/replay failure never trusts an invalid update file

**Coverage:** strong. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Submit an invalid/tampered/unknown-key, stale or malformed policy, or fail its download.
2. Verify the rejection and stored ratchet/cached decision.
3. Ensure invalid input never promotes a new trusted update decision.

**Conditions:** platform: shared Dart trust boundary; Android UI tamper scenario registered; connectivity: local TLS errors and controlled signed inputs; offline: download failure with/without valid cache; app state: foreground; input: tamper, rogue key, stale sequence, bad schema/URL/oversize; recovery: n/a.

**Expected:** Real signature/schema/rank/sequence and URL/size/deadline checks reject invalid inputs; a failed check may retain an already-authenticated cached policy.

**Inspected test evidence**

- [test/features/update_check/domain/version_file_verifier_test.dart](../../test/features/update_check/domain/version_file_verifier_test.dart) — `changing one payload byte fails the signature` (unit).
  - Real: pinenacl Ed25519; VersionFileVerifier parsing/signature checks.
  - Faked: public test signing-key fixtures.
  - Proves / registration: test/features/update_check/domain/version_file_verifier_test.dart:100: A payload mutation is rejected by real cryptographic verification; not a stubbed accept/reject callback. Registered: host-all, update-check.
- [test/features/update_check/application/update_check_service_test.dart](../../test/features/update_check/application/update_check_service_test.dart) — `a lower sequence is ignored` (unit).
  - Real: UpdateCheckService; Ed25519 verifier and policy/ratchet; atomic temporary-file state store.
  - Faked: version-file server responses and test signing keys; installed build/platform/clock inputs.
  - Proves / registration: test/features/update_check/application/update_check_service_test.dart:138: A signed lower-sequence hard policy cannot replace the stored newer accepted policy. Registered: host-all, update-check.
- [test/features/update_check/infrastructure/version_file_fetcher_test.dart](../../test/features/update_check/infrastructure/version_file_fetcher_test.dart) — `non-https URLs and identifying URLs are rejected before connecting` (unit).
  - Real: VersionFileFetcher; real local TLS server/HttpClient; size/URL/deadline policy.
  - Faked: self-signed test certificate and controlled server; production version host.
  - Proves / registration: test/features/update_check/infrastructure/version_file_fetcher_test.dart:167: Invalid schemes/identifying URL parts are refused before client creation; neighboring cases enforce no redirects, byte limits and actual socket deadlines. Registered: host-all, update-check.
- [integration_test/scripts/run_production_update_check.dart](../../integration_test/scripts/run_production_update_check.dart) — `kx0022` (sims).
  - Real: production update verifier/controller; registered Android/iOS app UI and Android native posting when executed; typed artifact validator.
  - Faked: test version source/signing key; clock advancement; controlled runner triggers; OS scheduling not exercised.
  - Proves / registration: integration_test/scripts/run_production_update_check.dart:62: tool/sims/production_update_check_criteria.dart:36 requires exact signed-envelope hashes, new checks, unique successful UI receipts and native card/target evidence. Stock published artifact/version-host and real elapsed scheduling are separate. Registered: kx0020, kx0021, kx0022, kx0023, kx0024, kx0025, kx0026, kx0027, kx0028. Exact registered scenario kx0022; see production_update_check_criteria.dart:12 phase map (0025/0027 native controlled runner).
- [integration_test/scripts/run_production_update_check.dart](../../integration_test/scripts/run_production_update_check.dart) — `kx0023` (sims).
  - Real: production update verifier/controller; registered Android/iOS app UI and Android native posting when executed; typed artifact validator.
  - Faked: test version source/signing key; clock advancement; controlled runner triggers; OS scheduling not exercised.
  - Proves / registration: integration_test/scripts/run_production_update_check.dart:62: tool/sims/production_update_check_criteria.dart:36 requires exact signed-envelope hashes, new checks, unique successful UI receipts and native card/target evidence. Stock published artifact/version-host and real elapsed scheduling are separate. Registered: kx0020, kx0021, kx0022, kx0023, kx0024, kx0025, kx0026, kx0027, kx0028. Exact registered scenario kx0023; see production_update_check_criteria.dart:12 phase map (0025/0027 native controlled runner).
- [integration_test/scripts/run_production_update_check.dart](../../integration_test/scripts/run_production_update_check.dart) — `kx0024` (sims).
  - Real: production update verifier/controller; registered Android/iOS app UI and Android native posting when executed; typed artifact validator.
  - Faked: test version source/signing key; clock advancement; controlled runner triggers; OS scheduling not exercised.
  - Proves / registration: integration_test/scripts/run_production_update_check.dart:62: tool/sims/production_update_check_criteria.dart:36 requires exact signed-envelope hashes, new checks, unique successful UI receipts and native card/target evidence. Stock published artifact/version-host and real elapsed scheduling are separate. Registered: kx0020, kx0021, kx0022, kx0023, kx0024, kx0025, kx0026, kx0027, kx0028. Exact registered scenario kx0024; see production_update_check_criteria.dart:12 phase map (0025/0027 native controlled runner).

**Remaining gaps**

- Production version-host TLS/key provisioning and signed distribution artifact remain unverified; Strong is scoped to the implemented trust/rejection assertions.

#### UPDATE-006 — Resume/background checks obey due-time, cache, concurrency and timeout budgets

**Coverage:** strong. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Invoke/resume checks inside and outside their due interval.
2. Issue overlapping requests and a never-finishing download.
3. Observe cache, coalescing, timeout and post-deadline state writes.

**Conditions:** platform: shared Dart checker and host filesystem; connectivity: fake/hanging fetcher; offline: n/a; app state: explicit foreground/background checker invocation; input: controlled clock and concurrent calls; recovery: six-hour gate, clock rollback, timeout and crash-temp state.

**Expected:** One coalesced due check preserves the monotonic state/cache and a budget abort performs no late notification/state commit.

**Inspected test evidence**

- [test/features/update_check/application/update_check_service_test.dart](../../test/features/update_check/application/update_check_service_test.dart) — `concurrent calls share one run` (unit).
  - Real: UpdateCheckService; Ed25519 verifier and policy/ratchet; atomic temporary-file state store.
  - Faked: version-file server responses and test signing keys; installed build/platform/clock inputs.
  - Proves / registration: test/features/update_check/application/update_check_service_test.dart:433: Concurrent checks coalesce; suite also checks real file atomic writes, cached policy, six-hour gating and crash-temp recovery. Registered: host-all, update-check.
- [test/features/update_check/background/update_check_background_runner_test.dart](../../test/features/update_check/background/update_check_background_runner_test.dart) — `the budget abort writes nothing after the deadline` (unit).
  - Real: background Dart runner; real timer/deadline; atomic filesystem state; real verifier.
  - Faked: hanging fetcher; recording notification poster; clock/platform/call inputs.
  - Proves / registration: test/features/update_check/background/update_check_background_runner_test.dart:239: A150ms budget abort posts nothing and creates no partial state file; no genuine OS task scheduling is exercised. Registered: host-all, update-check.

**Remaining gaps**

- Strong covers the checker once invoked; actual WorkManager/BGTaskScheduler wake timing and real hours are a different row.

#### UPDATE-007 — Android/iOS background or check-now push produces one permitted localized update notification

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Make a signed update eligible while the app is backgrounded.
2. Trigger a supported scheduled/check-now entry.
3. Observe one localized native notification with the correct store action.

**Conditions:** platform: Android and iOS background implementations; connectivity: check-now or scheduled check; offline: n/a; app state: background/minimal engine; input: signed soft/hard update and repeated triggers; recovery: n/a.

**Expected:** Each eligible build/reminder emits one permitted localized notice; duplicates and unrelated cards are preserved correctly.

**Inspected test evidence**

- [test/features/update_check/background/update_check_background_runner_test.dart](../../test/features/update_check/background/update_check_background_runner_test.dart) — `once per latestBuild; a higher latestBuild notifies again` (unit).
  - Real: Dart background runner; real signed-file verification; persistent state.
  - Faked: network response; clock/foreground/call probes; native notification poster.
  - Proves / registration: test/features/update_check/background/update_check_background_runner_test.dart:110: Repeated eligible checks post once per latest build and update the durable reminder state; actual native publication is replaced. Registered: host-all, update-check.
- [integration_test/scripts/run_production_update_check.dart](../../integration_test/scripts/run_production_update_check.dart) — `kx0025` (sims).
  - Real: production update verifier/controller; registered Android/iOS app UI and Android native posting when executed; typed artifact validator.
  - Faked: test version source/signing key; clock advancement; controlled runner triggers; OS scheduling not exercised.
  - Proves / registration: integration_test/scripts/run_production_update_check.dart:62: tool/sims/production_update_check_criteria.dart:36 requires exact signed-envelope hashes, new checks, unique successful UI receipts and native card/target evidence. Stock published artifact/version-host and real elapsed scheduling are separate. Registered: kx0020, kx0021, kx0022, kx0023, kx0024, kx0025, kx0026, kx0027, kx0028. Exact registered scenario kx0025; see production_update_check_criteria.dart:12 phase map (0025/0027 native controlled runner).
- [integration_test/scripts/run_production_update_check.dart](../../integration_test/scripts/run_production_update_check.dart) — `kx0027` (sims).
  - Real: production update verifier/controller; registered Android/iOS app UI and Android native posting when executed; typed artifact validator.
  - Faked: test version source/signing key; clock advancement; controlled runner triggers; OS scheduling not exercised.
  - Proves / registration: integration_test/scripts/run_production_update_check.dart:62: tool/sims/production_update_check_criteria.dart:36 requires exact signed-envelope hashes, new checks, unique successful UI receipts and native card/target evidence. Stock published artifact/version-host and real elapsed scheduling are separate. Registered: kx0020, kx0021, kx0022, kx0023, kx0024, kx0025, kx0026, kx0027, kx0028. Exact registered scenario kx0027; see production_update_check_criteria.dart:12 phase map (0025/0027 native controlled runner).

**Remaining gaps**

- Dart poster is fake; native unit tests use OS doubles and device scenarios use controlled invocation.
- Genuine OS scheduling, provider push delivery, real elapsed reminder intervals and signed-store background execution remain unverified.

#### UPDATE-008 — Disabled switch, denied notification permission, active call or locked state avoids unwanted notices

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Disable update checks or deny notifications; alternatively hold a call or protected unreadable state.
2. Trigger/resume the background checker.
3. Verify no unwanted notice or destructive state reset, then retry only when eligible.

**Conditions:** platform: shared Android/iOS Dart policy; connectivity: n/a; offline: n/a; app state: foreground, in-call, background and pre-unlock represented; input: disabled switch or denied/unreadable state; recovery: later eligible run.

**Expected:** Kill switch, denied posting, active-call/foreground deferral and unreadable state do not create unwanted notices or erase trusted state.

**Inspected test evidence**

- [test/features/update_check/background/update_check_background_runner_test.dart](../../test/features/update_check/background/update_check_background_runner_test.dart) — `$name: disabled, no download, no notification` (unit).
  - Real: real UpdateCheckSwitch and background runner.
  - Faked: build-mode inputs; fetcher/poster.
  - Proves / registration: test/features/update_check/background/update_check_background_runner_test.dart:378: For explicit off, debug default and unapproved E2E/SIMS modes, returns disabled with zero fetches/posts; source template expands to the four named modes. Registered: host-all, update-check.
- [test/features/update_check/background/update_check_background_runner_test.dart](../../test/features/update_check/background/update_check_background_runner_test.dart) — `notifications not allowed: skipped silently, nothing recorded` (unit).
  - Real: Dart notification eligibility; persistent state.
  - Faked: poster permission result; clock/call/foreground probes.
  - Proves / registration: test/features/update_check/background/update_check_background_runner_test.dart:230: Denied posting leaves no recorded successful notification; native permission dialog/OS scheduling remains outside this case. Registered: host-all, update-check.
- [test/features/update_check/background/update_check_background_runner_test.dart](../../test/features/update_check/background/update_check_background_runner_test.dart) — `state unreadable (before the first unlock): skip, never reset` (unit).
  - Real: real state file and permission denial; background runner.
  - Faked: first-unlock represented by chmod; fetcher/poster/platform probes.
  - Proves / registration: test/features/update_check/background/update_check_background_runner_test.dart:260: Unreadable state performs no fetch/post and preserves file bytes; does not reproduce a real pre-unlock phone. Registered: host-all, update-check.
- [test/features/update_check/background/update_check_background_runner_test.dart](../../test/features/update_check/background/update_check_background_runner_test.dart) — `never during a call; posted on a later run` (unit).
  - Real: background runner and reminder state.
  - Faked: call-state boolean; fetcher/clock/poster.
  - Proves / registration: test/features/update_check/background/update_check_background_runner_test.dart:221: In-call run defers; clearing the call condition allows the later notification. Registered: host-all, update-check.

**Remaining gaps**

- Permission/call/lock boundaries are simulated or host file modes; real OS denial and first-unlock behavior were not exercised here.

#### UPDATE-009 — Store launch failure/cancel leaves a usable truthful update-required state

**Coverage:** strong. **Execution:** host_run. **Catalog:** source-derived.

**Steps**

1. Show the required-update gate.
2. Have the platform store launcher reject, throw, or return without an install.
3. Retry or resume while the installed build is still old.

**Conditions:** platform: shared Android/iOS root-gate logic; injected host store boundary; connectivity: n/a; offline: n/a; app state: foreground; input: false/throw handoff; successful handoff followed by return without installing; recovery: retry and return without installing.

**Expected:** The required state remains truthful and retryable; a failed/cancelled store action must not imply the installed app was updated.

**Inspected test evidence**

- [test/features/update_check/presentation/update_required_gate_test.dart](../../test/features/update_check/presentation/update_required_gate_test.dart) — `UPDATE-009 store handoff cannot clear the required root gate` (widget).
  - Real: UpdateRequiredGate in MaterialApp.builder inside ForegroundCallOverlay; update controller and Back guard; Flutter navigator, focus and semantics.
  - Faked: update service and installed-build/platform inputs; call capability; external store handoff result.
  - Proves / registration: existing EN/DE/AR false/throw/return cases retain the hard decision, localized recovery on refused or thrown handoff, retry and the exact store target. The successful-retry case at line 156 clears stale feedback, resumes without an install or a false error, and uses the build-126 session X. Existing Android target and session-X tests remain unchanged. Registered: host-all, update-check.

**Verified host execution (2026-10-23)**

- `flutter test --no-pub --machine --concurrency=1 --timeout=2m test/features/update_check/presentation/update_required_gate_test.dart`: **31 PASS, 0 skipped/failed**, runner `done.success=true`, exit 0. The new successful-retry/no-false-error case passed; existing cases stayed unchanged.
- Focused `flutter analyze --no-pub test/features/update_check/presentation/update_required_gate_test.dart`: **No issues found**, exit 0.
- Evidence in the Astra worktree: `.codex-test-logs/astra-update-relay-sims/item1/009-gate-summary.json`, `009-gate-receipt.json`, `010-analyze.log`, `010-analyze-receipt.json`. Earlier resource-aborted/held attempts are retained. These are injected host-boundary results; real external store, installation and signed-candidate behavior were not exercised.

**Remaining gaps**

- Host launchers prove the shared UI contract; no real external store, native cancellation, installation or signed candidate was exercised. A successful external handoff followed by user cancellation is modeled as return without an install, not a false platform-launch failure.

### TRANSPORT — Cross-cutting discovery, reconnect and local/offline routing

#### TRANSPORT-001 — Known-contact discovery on same local Wi-Fi without public internet

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Discover a known contact on local Wi-Fi with public internet unavailable.
2. Send text/media over LAN.
3. Confirm exact received content and durable ACK before success.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: local Wi-Fi, no public internet; host loopback fixture; offline: n/a; app state: foreground; input: known contact text/media; recovery: n/a.

**Expected:** Known peers can exchange correct owned content locally without treating discovery alone as authority.

**Inspected test evidence**

- [test/core/local_discovery/local_ws_integration_i1_i2_test.dart](../../test/core/local_discovery/local_ws_integration_i1_i2_test.dart) — `text: A -> B delivers, B acks, content intact` (unit).
  - Real: actual loopback WebSocket servers/client; message stream/ACK parsing.
  - Faked: opaque encrypted-envelope fixture; no cryptography; loopback instead of Wi-Fi/mDNS/OS permission.
  - Proves / registration: test/core/local_discovery/local_ws_integration_i1_i2_test.dart:44: Exact opaque envelope/from/to reaches one receiver; unconfigured receiver ACK is explicitly legacy parse-time, not durable delivery. Registered: affected-transport, host-all.
- [test/core/local_discovery/local_ws_integration_i1_i2_test.dart](../../test/core/local_discovery/local_ws_integration_i1_i2_test.dart) — `media production-wiring: PUT -> mediaReadyStream -> persistMedia lands a SHA-256-verified file in the persistent media dir` (unit).
  - Real: actual loopback WS/HTTP transfer,mediaReadyStream/persistMedia; actual filesystem/SHA256.
  - Faked: synthetic8192-byte JPEG-named file; loopback rather than real discovery.
  - Proves / registration: test/core/local_discovery/local_ws_integration_i1_i2_test.dart:84: Full persisted receiver bytes match sender SHA256 and move out of temporary path; synthetic bytes do not prove valid image decode/open. Registered: affected-transport, host-all.
- [test/core/local_discovery/local_ws_durable_ack_integration_test.dart](../../test/core/local_discovery/local_ws_durable_ack_integration_test.dart) — `receiver killed after committed ack does not lose the message: staged row replays on restart` (unit).
  - Real: actual loopback WS committed ACK; production staging repository/SQLite file reopen.
  - Faked: receiver shutdown and DB reopen model kill; replay consumer helper/injected envelope.
  - Proves / registration: test/core/local_discovery/local_ws_durable_ack_integration_test.dart:31: ACK follows durable staging; after reopen two recovery passes replay once and delete exact staging row. No OS process kill/native lifecycle. Registered: affected-transport, host-all.

**Remaining gaps**

- Real loopback wire/files are tested, but actual native mDNS/permission/Wi-Fi reachability and signed-app known-contact authorization/full media decode are not joined.

#### TRANSPORT-002 — Direct connection failure falls back to durable relay delivery without duplicate rows

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-010.

**Steps**

1. Attempt a local/direct send and lose or delay its authenticated proof.
2. Fall back to relay/inbox custody under the same identity.
3. Receive/replay without duplicate conversation rows.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: direct/LAN failure then relay/inbox; offline: n/a; app state: foreground; input: as described; recovery: late competing result/replay.

**Expected:** A mere local write never suppresses durable proof; fallback retains one owned send and one received message.

**Inspected test evidence**

- [test/features/conversation/integration/ranked_race_relay_penalty_test.dart](../../test/features/conversation/integration/ranked_race_relay_penalty_test.dart) — `FDC-02 e2e R2: sender LAN write cannot suppress relay proof, receiver persists one row` (integration).
  - Real: real sender sendChatMessage race and ACK authority.
  - Faked: DurableLanFakeP2PService/repositories; receiver is a hand-written dedup list, not production receiver.
  - Proves / registration: test/features/conversation/integration/ranked_race_relay_penalty_test.dart:77: LAN write cannot suppress authenticated-relay result; sender invokes one local and one relay-live leg. Receiver dedup list only models the expected property. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/offline_inbox_roundtrip_test.dart](../../test/features/conversation/integration/offline_inbox_roundtrip_test.dart) — `FDC-03-06 first-ever offline send deposits a concurrent inbox copy that drains on resume` (integration).
  - Real: real send/listener/inbox-drain use-case composition.
  - Faked: FakeP2PNetwork/in-memory relay; PassthroughCryptoBridge; in-memory repositories.
  - Proves / registration: test/features/conversation/integration/offline_inbox_roundtrip_test.dart:234: First offline send records inbox custody, receiver drain yields one exact-text row; no real relay persistence or long retention. Registered: affected-conversation, host-all, offline-recovery.

**Remaining gaps**

- Sender race is causal, but ranked race receiver is a manually deduping list. Actual relay wire plus production receiver dedup across simultaneous legs is not established by that file.

#### TRANSPORT-003 — Mixed Wi-Fi/mobile peers deliver direct text and full media with sender/recipient agreement

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-011, DC-012.

**Steps**

1. Place peers on mixed Wi-Fi/mobile paths.
2. Send text and complete media in both directions.
3. Compare recorded actual transport and full recipient content.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: Wi-Fi/mobile mixed; actual radio untested; offline: n/a; app state: foreground; input: text and full media; recovery: n/a.

**Expected:** Network type does not imply transport; sender and recipient agree on exact delivered content.

**Inspected test evidence**

- [test/core/local_discovery/local_ws_integration_i1_i2_test.dart](../../test/core/local_discovery/local_ws_integration_i1_i2_test.dart) — `media production-wiring: PUT -> mediaReadyStream -> persistMedia lands a SHA-256-verified file in the persistent media dir` (unit).
  - Real: actual loopback WS/HTTP transfer,mediaReadyStream/persistMedia; actual filesystem/SHA256.
  - Faked: synthetic8192-byte JPEG-named file; loopback rather than real discovery.
  - Proves / registration: test/core/local_discovery/local_ws_integration_i1_i2_test.dart:84: Full persisted receiver bytes match sender SHA256 and move out of temporary path; synthetic bytes do not prove valid image decode/open. Registered: affected-transport, host-all.
- [test/core/services/network_path_source_test.dart](../../test/core/services/network_path_source_test.dart) — `a previous-network loss for the ready epoch is delivered once and never replayed` (unit).
  - Real: NetworkPathSource epoch/generation event admission.
  - Faked: StreamController native pushes.
  - Proves / registration: test/core/services/network_path_source_test.dart:40: Previous-loss event is delivered once only for the ready epoch and not replayed to late subscribers; actual Android monitor and mobile handoff are separate. Registered: affected-transport, host-all.
- [go-mknoon/node/network_handoff_test.go](../../go-mknoon/node/network_handoff_test.go) — `TestDefaultNetworkChange_ReplacesStalledRelayBeforeIdleTimeout` (integration).
  - Real: real Go/libp2p relay+QUIC node/proxy; blackholed old socket/fresh relay reservation; third-host circuit dial and unrelated-connection preservation.
  - Faked: controlled loopback network-path epoch event/proxy; actual mobile default-network change absent.
  - Proves / registration: go-mknoon/node/network_handoff_test.go:248: A real stalled connection is blackholed, three epoch requests coalesce to one fresh socket, new reservation accepts a third host, original identity/host/unrelated peer survive. Skipped only under go -short; registered go-core ./... full mode. Registered: see cited native runner/manifest.

**Remaining gaps**

- Loopback byte transfer and network-event/native transport recovery are separate. No actual mixed-radio full-media+caption/decode journey or recorded cellular service observed here.

#### TRANSPORT-004 — Wi-Fi/mobile handover during queued sends or media transfer recovers exact owned work

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-017, DC-018.

**Steps**

1. Begin queued sends/media transfer.
2. Handover Wi-Fi/mobile while an old connection stalls.
3. Recover only current-epoch work without duplicate/lost accepted content.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: old socket blackhole/default-network change; offline: n/a; app state: foreground; input: current/superseded epochs and queued content; recovery: fresh relay reservation and retry.

**Expected:** One current network owner recovers fresh routing and retains accepted work/identity while stale completions cannot win.

**Inspected test evidence**

- [go-mknoon/node/network_handoff_test.go](../../go-mknoon/node/network_handoff_test.go) — `TestDefaultNetworkChange_ReplacesStalledRelayBeforeIdleTimeout` (integration).
  - Real: real Go/libp2p relay+QUIC node/proxy; blackholed old socket/fresh relay reservation; third-host circuit dial and unrelated-connection preservation.
  - Faked: controlled loopback network-path epoch event/proxy; actual mobile default-network change absent.
  - Proves / registration: go-mknoon/node/network_handoff_test.go:248: A real stalled connection is blackholed, three epoch requests coalesce to one fresh socket, new reservation accepts a third host, original identity/host/unrelated peer survive. Skipped only under go -short; registered go-core ./... full mode. Registered: see cited native runner/manifest.
- [test/core/services/network_path_source_test.dart](../../test/core/services/network_path_source_test.dart) — `a previous-network loss for the ready epoch is delivered once and never replayed` (unit).
  - Real: NetworkPathSource epoch/generation event admission.
  - Faked: StreamController native pushes.
  - Proves / registration: test/core/services/network_path_source_test.dart:40: Previous-loss event is delivered once only for the ready epoch and not replayed to late subscribers; actual Android monitor and mobile handoff are separate. Registered: affected-transport, host-all.
- [test/integration/relay_down_degradation_integration_test.dart](../../test/integration/relay_down_degradation_integration_test.dart) — `1b. active send fails during transport loss, then online transition retrier heals the same row once` (integration).
  - Real: sendChatMessage/PendingMessageRetrier; same-row status/identity handling.
  - Faked: fake ACK/direct/inbox/connectivity; in-memory repositories/passthrough crypto.
  - Proves / registration: test/integration/relay_down_degradation_integration_test.dart:97: Failed initial send stays one failed row, online event retries same ID to inboxed once. Bare inbox store is custody, not remote delivery. Registered: host-all.
- [integration_test/scripts/run_connectivity_restore_sims.dart](../../integration_test/scripts/run_connectivity_restore_sims.dart) — `android.connectivity_restore_inbox_drain` (sims).
  - Real: registered Android OS-network disconnect/restore campaign when executed; receiver inbox-drain observations and typed artifacts.
  - Faked: campaign setup/contact provisioning; controlled network toggle.
  - Proves / registration: integration_test/scripts/run_connectivity_restore_sims.dart:70: Scenario deliberately disconnects receiver and checks natural recovery after restore using pinned available targets. Registered capability is real execution machinery, but no run/artifact was produced or validated in this host audit. Registered: android.connectivity_restore_inbox_drain.

**Remaining gaps**

- Substantive real Go relay/socket preservation exists; mobile OS handover plus actual in-flight media/recipient completion are not joined or executed.

#### TRANSPORT-005 — Airplane/no-network startup and resume preserve local reading and pending send intent

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-022.

**Steps**

1. Start/resume with no network and retained local history.
2. Read local content and compose/send without silently discarding intent.
3. Restore connectivity and settle retained work.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: airplane/no network then reconnect; offline: n/a; app state: cold/resumed; input: as described; recovery: pending retry.

**Expected:** Offline UI remains usable and retains truthful pending/failed intent for later recovery.

**Inspected test evidence**

- [test/features/conversation/integration/offline_inbox_roundtrip_test.dart](../../test/features/conversation/integration/offline_inbox_roundtrip_test.dart) — `FDC-03-06 first-ever offline send deposits a concurrent inbox copy that drains on resume` (integration).
  - Real: real send/listener/inbox-drain use-case composition.
  - Faked: FakeP2PNetwork/in-memory relay; PassthroughCryptoBridge; in-memory repositories.
  - Proves / registration: test/features/conversation/integration/offline_inbox_roundtrip_test.dart:234: First offline send records inbox custody, receiver drain yields one exact-text row; no real relay persistence or long retention. Registered: affected-conversation, host-all, offline-recovery.
- [test/integration/relay_down_degradation_integration_test.dart](../../test/integration/relay_down_degradation_integration_test.dart) — `1b. active send fails during transport loss, then online transition retrier heals the same row once` (integration).
  - Real: sendChatMessage/PendingMessageRetrier; same-row status/identity handling.
  - Faked: fake ACK/direct/inbox/connectivity; in-memory repositories/passthrough crypto.
  - Proves / registration: test/integration/relay_down_degradation_integration_test.dart:97: Failed initial send stays one failed row, online event retries same ID to inboxed once. Bare inbox store is custody, not remote delivery. Registered: host-all.

**Remaining gaps**

- Use-case fake network recovery is covered; full offline cold-start rendered local history plus saved draft and real OS connectivity is not one asserted journey.

#### TRANSPORT-006 — Local peer discovery disabled/permission denied or stale endpoint never authorizes an unknown peer

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Disable/deny local discovery or receive a stale/unknown endpoint.
2. Attempt discovery/send and apply independent contact authority.
3. Recover browsing safely without authorizing unknown senders.

**Conditions:** platform: Android/iOS discovery implementations; connectivity: n/a; offline: n/a; app state: foreground; input: suspected permission denial, stale endpoint, unknown sender; recovery: n/a.

**Expected:** Discovery availability never grants messaging authority; stale endpoints fail promptly and known-contact checks still apply.

**Inspected test evidence**

- [test/core/local_discovery/bonsoir_discovery_service_contract_test.dart](../../test/core/local_discovery/bonsoir_discovery_service_contract_test.dart) — `iOS suspected-denied skips the broadcast but KEEPS the browse running` (unit).
  - Real: Bonjour-discovery policy/restart orchestration.
  - Faked: fake discovery/broadcast objects; host target-platform override.
  - Proves / registration: test/core/local_discovery/bonsoir_discovery_service_contract_test.dart:725: Suspected-denied gate prevents broadcast while browsing continues; not an actual iOS Local Network prompt or physical LAN. Registered: affected-transport, host-all.
- [test/core/local_discovery/local_ws_integration_i1_i2_test.dart](../../test/core/local_discovery/local_ws_integration_i1_i2_test.dart) — `stale host:port -> connect fails fast within _connectTimeout (800ms), not the full local budget` (unit).
  - Real: actual socket connect/deadline handling.
  - Faked: reserved non-listening endpoint; fixedpeer/envelope fixtures.
  - Proves / registration: test/core/local_discovery/local_ws_integration_i1_i2_test.dart:223: Stale endpoint cannot consume full1.5s budget; returns false within1.4s. Does not authenticate a discovered identity. Registered: affected-transport, host-all.
- [test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart](../../test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart) — `returns unknownSender when sender is not a contact` (unit).
  - Real: actual receive contact admission.
  - Faked: message/contact repositories and bridge.
  - Proves / registration: test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart:1926: Unknown sender returns unknownSender before any accepted chat; no claim that mDNS discovery authorizes contacts. Registered: affected-conversation, host-all, quiet-recovery.

**Remaining gaps**

- Policy, actual socket timeout and receive contact admission are separate. No native permission-denial plus forged discovery identity to authenticated receive pipeline is joined.

#### TRANSPORT-007 — Relay outage or bridge restart recovers inbox delivery and accepted durable work exactly once

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-017.

**Steps**

1. Lose the relay/bridge while accepted work is queued.
2. Restart/recover routing and inbox owner.
3. Replay exact retained work once and retain truthful custody/delivery distinction.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: relay outage/bridge restart; offline: n/a; app state: foreground; input: as described; recovery: inbox drain/retained retry.

**Expected:** Outage recovery preserves one owned row/byte source and cannot invent receiver delivery from relay acceptance.

**Inspected test evidence**

- [test/integration/relay_down_degradation_integration_test.dart](../../test/integration/relay_down_degradation_integration_test.dart) — `1b. active send fails during transport loss, then online transition retrier heals the same row once` (integration).
  - Real: sendChatMessage/PendingMessageRetrier; same-row status/identity handling.
  - Faked: fake ACK/direct/inbox/connectivity; in-memory repositories/passthrough crypto.
  - Proves / registration: test/integration/relay_down_degradation_integration_test.dart:97: Failed initial send stays one failed row, online event retries same ID to inboxed once. Bare inbox store is custody, not remote delivery. Registered: host-all.
- [test/features/conversation/integration/offline_inbox_roundtrip_test.dart](../../test/features/conversation/integration/offline_inbox_roundtrip_test.dart) — `FDC-03-06 first-ever offline send deposits a concurrent inbox copy that drains on resume` (integration).
  - Real: real send/listener/inbox-drain use-case composition.
  - Faked: FakeP2PNetwork/in-memory relay; PassthroughCryptoBridge; in-memory repositories.
  - Proves / registration: test/features/conversation/integration/offline_inbox_roundtrip_test.dart:234: First offline send records inbox custody, receiver drain yields one exact-text row; no real relay persistence or long retention. Registered: affected-conversation, host-all, offline-recovery.
- [test/core/local_discovery/local_ws_durable_ack_integration_test.dart](../../test/core/local_discovery/local_ws_durable_ack_integration_test.dart) — `receiver killed after committed ack does not lose the message: staged row replays on restart` (unit).
  - Real: actual loopback WS committed ACK; production staging repository/SQLite file reopen.
  - Faked: receiver shutdown and DB reopen model kill; replay consumer helper/injected envelope.
  - Proves / registration: test/core/local_discovery/local_ws_durable_ack_integration_test.dart:31: ACK follows durable staging; after reopen two recovery passes replay once and delete exact staging row. No OS process kill/native lifecycle. Registered: affected-transport, host-all.
- [go-mknoon/node/network_handoff_test.go](../../go-mknoon/node/network_handoff_test.go) — `TestDefaultNetworkChange_ReplacesStalledRelayBeforeIdleTimeout` (integration).
  - Real: real Go/libp2p relay+QUIC node/proxy; blackholed old socket/fresh relay reservation; third-host circuit dial and unrelated-connection preservation.
  - Faked: controlled loopback network-path epoch event/proxy; actual mobile default-network change absent.
  - Proves / registration: go-mknoon/node/network_handoff_test.go:248: A real stalled connection is blackholed, three epoch requests coalesce to one fresh socket, new reservation accepts a third host, original identity/host/unrelated peer survive. Skipped only under go -short; registered go-core ./... full mode. Registered: see cited native runner/manifest.

**Remaining gaps**

- Real loopback staging reopen and fake relay send retry are meaningful; actual deployed relay persistence/bridge restart-to-recipient completion remains unverified.

#### TRANSPORT-008 — Background/closed-process recovery respects single-runtime ownership and foreground handoff

**Coverage:** partial. **Execution:** not_run. **Catalog:** DC-005, GC-003.

**Steps**

1. Receive background/closed-process recovery while foreground may acquire ownership.
2. Drain runtime, quiesce Go and close database before handoff.
3. Retain ownership on failed close/quiescence and attach once after success.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground/background/closed-process competing recovery; input: lease handoff and failed teardown; recovery: quiesce/close/reacquire.

**Expected:** Only the authorized writable runtime owns durable work; failed teardown never transfers a live database/runtime to another owner.

**Inspected test evidence**

- [test/core/notifications/canonical_runtime_lease_test.dart](../../test/core/notifications/canonical_runtime_lease_test.dart) — `database close failure retains draining ownership` (unit).
  - Real: CanonicalWritableRuntimeSession lifecycle/lease state.
  - Faked: native lease gateway; database close throwing callback.
  - Proves / registration: test/core/notifications/canonical_runtime_lease_test.dart:60: Failed close retains draining lease and reports release:false; does not run actual cross-process native lock. Registered: affected-push, host-all.
- [test/core/notifications/canonical_runtime_lease_test.dart](../../test/core/notifications/canonical_runtime_lease_test.dart) — `Go quiescence failure skips database close and never transfers` (unit).
  - Real: real shutdown ordering and transfer refusal.
  - Faked: native gateway quiescence rejection; runtime/database callbacks.
  - Proves / registration: test/core/notifications/canonical_runtime_lease_test.dart:91: Refused Go quiescence prevents database close/lease transfer; native concurrency primitive and actual SQLCipher are not exercised. Registered: affected-push, host-all.
- [integration_test/scripts/run_connectivity_restore_sims.dart](../../integration_test/scripts/run_connectivity_restore_sims.dart) — `android.connectivity_restore_inbox_drain` (sims).
  - Real: registered Android OS-network disconnect/restore campaign when executed; receiver inbox-drain observations and typed artifacts.
  - Faked: campaign setup/contact provisioning; controlled network toggle.
  - Proves / registration: integration_test/scripts/run_connectivity_restore_sims.dart:70: Scenario deliberately disconnects receiver and checks natural recovery after restore using pinned available targets. Registered capability is real execution machinery, but no run/artifact was produced or validated in this host audit. Registered: android.connectivity_restore_inbox_drain.

**Remaining gaps**

- Dart lifecycle tests use a fake native gateway and database callbacks; actual native cross-process locking, SQLCipher ownership and OS recovery are not executed here.

### DIAG — User-controlled diagnostics and recovery reporting

#### DIAG-001 — Enable/disable app diagnostics, preview/export redacted evidence and clear only owned records

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open app diagnostics disclosure and inspect its support code.
2. Change sharing preference and preview/copy a report.
3. Clear retained evidence while old upload completion is pending.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: default-on disclosure, opt-out, pending upload; recovery: clear during upload.

**Expected:** Disclosure matches default-on sharing, explicit disable stops collection, and clear cannot be undone by a stale upload.

**Inspected test evidence**

- [test/features/settings/presentation/widgets/app_diagnostics_settings_section_test.dart](../../test/features/settings/presentation/widgets/app_diagnostics_settings_section_test.dart) — `support code is copyable and opting out disables collection` (widget).
  - Real: Settings diagnostics controls; AppDiagnostics; temporary-file persistence.
  - Faked: platform clipboard channel.
  - Proves / registration: test/features/settings/presentation/widgets/app_diagnostics_settings_section_test.dart:24: Copies a valid support code, turns sharing off, flushes and refuses a later attempt. Diagnostics are on by default; this is not an opt-in-only product claim. Registered: affected-surfaces, diagnostics, host-all.
- [test/features/settings/presentation/widgets/call_diagnostics_settings_section_test.dart](../../test/features/settings/presentation/widgets/call_diagnostics_settings_section_test.dart) — `large report preview stays bounded and copies the full report` (widget).
  - Real: actual report-preview/copy widgets.
  - Faked: report callback; clipboard channel.
  - Proves / registration: test/features/settings/presentation/widgets/call_diagnostics_settings_section_test.dart:10: Preview is bounded to8194 characters while explicit Copy includes the full report; closing the preview preserves Settings. Registered: affected-surfaces, diagnostics, host-all.
- [test/core/diagnostics/app_diagnostics_test.dart](../../test/core/diagnostics/app_diagnostics_test.dart) — `clear does not wait for old upload or accept its late completion` (unit).
  - Real: AppDiagnostics clear/epoch/persistence.
  - Faked: held upload acknowledgements.
  - Proves / registration: test/core/diagnostics/app_diagnostics_test.dart:1216: Clear completes while upload is held; late acknowledgement cannot restore rows or last-upload state. Registered: diagnostics, host-all, notification-lock-diagnostics.
- [test/features/call/diagnostics/call_diagnostics_test.dart](../../test/features/call/diagnostics/call_diagnostics_test.dart) — `protocol identities and arbitrary payloads cannot enter persisted or exported events` (unit).
  - Real: CallDiagnostics schema admission/export; real state.json I/O.
  - Faked: native collector/relay and test install inputs.
  - Proves / registration: test/features/call/diagnostics/call_diagnostics_test.dart:1476: Hostile call/peer/SDP/error/address values are submitted and absent from actual persisted/exported bytes; allowed counters remain. Registered: affected-calls, diagnostics, host-all.

**Remaining gaps**

- App settings preview/export and native/relay consent are tested at separate seams; clipboard/OS export is mocked. No full signed-app export or opt-out/restart journey executed.

#### DIAG-002 — Call diagnostics opt-in, status/export/clear preserve ongoing call and microphone ownership

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Inspect call diagnostics sharing status and report.
2. Turn off and clear while a call operation is active.
3. Continue the call even if diagnostic storage fails.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: active call represented by operation closure; input: held clear or failed diagnostic storage; recovery: n/a.

**Expected:** Consent/clear/report work remains independent of call ownership and microphone operation.

**Inspected test evidence**

- [test/features/settings/presentation/widgets/call_diagnostics_settings_section_test.dart](../../test/features/settings/presentation/widgets/call_diagnostics_settings_section_test.dart) — `clear revokes sharing before clearing and blocks duplicate actions` (widget).
  - Real: actual diagnostics clear controls.
  - Faked: consent/clear callbacks; held clear completer.
  - Proves / registration: test/features/settings/presentation/widgets/call_diagnostics_settings_section_test.dart:203: Turns sharing off before clear and disables duplicate actions; no live call/microphone is mounted. Registered: affected-surfaces, diagnostics, host-all.
- [test/features/call/diagnostics/call_diagnostics_test.dart](../../test/features/call/diagnostics/call_diagnostics_test.dart) — `storage failure preserves the call result and recovers after restoring the sink` (unit).
  - Real: CallDiagnostics; actual directory removal/recreation and state write.
  - Faked: call represented by synchronous closure returning42; native collector/relay.
  - Proves / registration: test/features/call/diagnostics/call_diagnostics_test.dart:2435: A real filesystem failure does not change the closure result; storage health recovers after the directory is restored. No actual media call ownership is asserted. Registered: affected-calls, diagnostics, host-all.
- [test/features/call/diagnostics/call_diagnostics_test.dart](../../test/features/call/diagnostics/call_diagnostics_test.dart) — `protocol identities and arbitrary payloads cannot enter persisted or exported events` (unit).
  - Real: CallDiagnostics schema admission/export; real state.json I/O.
  - Faked: native collector/relay and test install inputs.
  - Proves / registration: test/features/call/diagnostics/call_diagnostics_test.dart:1476: Hostile call/peer/SDP/error/address values are submitted and absent from actual persisted/exported bytes; allowed counters remain. Registered: affected-calls, diagnostics, host-all.

**Remaining gaps**

- Call preservation is a closure result; no real call audio graph, native microphone owner or in-call OS control is exercised.

#### DIAG-003 — Group-exit diagnostics and recovery sheet explain stuck leave/rejoin without destructive cross-group action

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open saved group-exit diagnostic history.
2. Reload or clear; fail then recover the repository.
3. Read only typed opaque codes for the affected operation.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: saved exit outcomes and reload/clear failure; recovery: explicit diagnostic reload.

**Expected:** Diagnostic history explains typed outcomes without leaking identifiers or retrying/destructively changing membership.

**Inspected test evidence**

- [test/features/settings/presentation/widgets/group_exit_diagnostics_sheet_test.dart](../../test/features/settings/presentation/widgets/group_exit_diagnostics_sheet_test.dart) — `PB266-13 reload and clear are explicit retain data on failure and requery after clear` (widget).
  - Real: actual group-exit diagnostics sheet/localized errors.
  - Faked: diagnostic repository.
  - Proves / registration: test/features/settings/presentation/widgets/group_exit_diagnostics_sheet_test.dart:208: Reload/clear failure preserves visible rows, hides raw error details; success requeries and replaces only diagnostic history. No leave/rejoin side effect is invoked. Registered: affected-surfaces, host-all.
- [test/features/groups/domain/repositories/group_exit_diagnostic_repository_impl_test.dart](../../test/features/groups/domain/repositories/group_exit_diagnostic_repository_impl_test.dart) — `PB266-08 hostile cause identifiers paths and secrets never cross storage or rendering` (unit).
  - Real: production group diagnostic repository; actual FFI SQLite production schema; hash references.
  - Faked: none identified.
  - Proves / registration: test/features/groups/domain/repositories/group_exit_diagnostic_repository_impl_test.dart:271: Submits hostile raw group/intent inputs and asserts database row bytes exclude them while retaining the intended opaque references. Registered: affected-groups, host-all.

**Remaining gaps**

- Real SQLite redaction and sheet behavior are separate proofs; the sheet repository is fake. No single stuck-leave/rejoin-to-Settings journey is asserted.

#### DIAG-004 — Transport diagnostics report truthful readiness and do not change delivery/routing policy

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Record transport readiness/session observations.
2. Open and refresh transport diagnostics.
3. Read aggregate readiness and latency without initiating transport changes.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: direct/relay/Wi-Fi/inbox/unknown synthetic metrics; recovery: n/a.

**Expected:** The card truthfully renders aggregate observations and refresh remains observational.

**Inspected test evidence**

- [test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart](../../test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart) — `refreshes rendered aggregate transport diagnostics` (widget).
  - Real: TransportMetrics aggregation; actual refresh/report widget.
  - Faked: synthetically recorded transport/LAN/latency counters.
  - Proves / registration: test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart:24: Recorded counts render exact mix/median/p95/readiness values. Secret constants in this widget test are not supplied to metrics, so their absence alone is not a redaction proof; no real transport policy is executed. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Metrics are injected, so production observation accuracy and invariance of real routing/delivery policy are not established by this widget case.

#### DIAG-005 — Export/share failure or cancellation preserves app functionality and does not expose secrets

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Preview/copy diagnostic evidence.
2. Cancel the preview or encounter export/storage failure.
3. Keep Settings and application operations usable; inspect emitted bytes for secrets.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: large report, cancellation, unavailable diagnostic storage; recovery: retry after storage repair.

**Expected:** Closing/failing diagnostic work preserves the application and only allowlisted redacted evidence leaves diagnostics.

**Inspected test evidence**

- [test/features/settings/presentation/widgets/call_diagnostics_settings_section_test.dart](../../test/features/settings/presentation/widgets/call_diagnostics_settings_section_test.dart) — `large report preview stays bounded and copies the full report` (widget).
  - Real: actual report-preview/copy widgets.
  - Faked: report callback; clipboard channel.
  - Proves / registration: test/features/settings/presentation/widgets/call_diagnostics_settings_section_test.dart:10: Preview is bounded to8194 characters while explicit Copy includes the full report; closing the preview preserves Settings. Registered: affected-surfaces, diagnostics, host-all.
- [test/features/call/diagnostics/call_diagnostics_test.dart](../../test/features/call/diagnostics/call_diagnostics_test.dart) — `storage failure preserves the call result and recovers after restoring the sink` (unit).
  - Real: CallDiagnostics; actual directory removal/recreation and state write.
  - Faked: call represented by synchronous closure returning42; native collector/relay.
  - Proves / registration: test/features/call/diagnostics/call_diagnostics_test.dart:2435: A real filesystem failure does not change the closure result; storage health recovers after the directory is restored. No actual media call ownership is asserted. Registered: affected-calls, diagnostics, host-all.
- [test/features/call/diagnostics/call_diagnostics_test.dart](../../test/features/call/diagnostics/call_diagnostics_test.dart) — `protocol identities and arbitrary payloads cannot enter persisted or exported events` (unit).
  - Real: CallDiagnostics schema admission/export; real state.json I/O.
  - Faked: native collector/relay and test install inputs.
  - Proves / registration: test/features/call/diagnostics/call_diagnostics_test.dart:1476: Hostile call/peer/SDP/error/address values are submitted and absent from actual persisted/exported bytes; allowed counters remain. Registered: affected-calls, diagnostics, host-all.

**Remaining gaps**

- Preview dismissal and storage failure are covered independently; no failing platform Clipboard/export callback assertion found. Native external share cancellation is not this product flow, which currently provides Copy.

### LOCAL — Local storage, identity secrecy and account erasure

#### LOCAL-001 — Upgrade database/secure-store versions without losing identity, messages, media or trust

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open a populated supported older database and secure-store state.
2. Apply production upgrade/secret migrations.
3. Reopen and verify identity/messages/media/trust remain usable.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: constructed legacy schemas and partial secret migration; recovery: upgrade/reopen/rerun.

**Expected:** Supported schema upgrades preserve valid data and move secrets without losing the usable account.

**Inspected test evidence**

- [test/core/database/integration/full_migration_chain_test.dart](../../test/core/database/integration/full_migration_chain_test.dart) — `1b. Step-by-step upgrade preserves seeded data` (integration).
  - Real: real migrations001–026; FFI SQLite and seeded identity/contact/request/group rows.
  - Faked: FakeSecureKeyStore; old schema constructed by current source.
  - Proves / registration: test/core/database/integration/full_migration_chain_test.dart:762: Preserves seeded public identity/contact/request fields, migrates secrets out of SQL and preserves a pre-v26 group quote default. Not an actual previous published app/database or current complete upgrade proof. Registered: affected-storage, host-all, migration.
- [test/core/database/migrations/120_media_attachment_file_name_test.dart](../../test/core/database/migrations/120_media_attachment_file_name_test.dart) — `a document row stores and restores its name after reopen` (unit).
  - Real: real migration/SQLite file reopen.
  - Faked: none identified.
  - Proves / registration: test/core/database/migrations/120_media_attachment_file_name_test.dart:57: A document filename survives database reopen; neighboring registry test requires v120 thenv121. This alone cannot certify all current schema data. Registered: affected-storage, host-all.
- [test/core/secure_storage/migrate_secrets_to_secure_storage_test.dart](../../test/core/secure_storage/migrate_secrets_to_secure_storage_test.dart) — `Partial migration — re-runs safely` (unit).
  - Real: real secret migration and FFI SQLite.
  - Faked: FakeSecureKeyStore.
  - Proves / registration: test/core/secure_storage/migrate_secrets_to_secure_storage_test.dart:102: Missing-sentinel partial migration overwrites keys from legacy DB and nulls secret columns; actual keychain/SQLCipher protection is outside this test. Registered: affected-storage, host-all.

**Remaining gaps**

- Migration fixtures use current code/FFI SQLite and fake secure storage; old published SQLCipher database plus signed-candidate keychain/artifact upgrade is not certified.
- The broad-named step-by-step case ends at v26; later migration tests provide separate evidence, not one complete historical app upgrade.

#### LOCAL-002 — Before first unlock or when secure storage is unavailable, defer protected work without unsafe fallback

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Invoke protected background/startup work before first unlock or with storage unavailable.
2. Observe deferral/failure without replacing trusted state.
3. Unlock/repair storage and retry only eligible owned work.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: background/startup; first unlock represented; input: unreadable file or secure-store exception; recovery: later readable state.

**Expected:** Protected work fails closed or defers; unavailable secrets never become an unsafe new authority or destructive reset.

**Inspected test evidence**

- [test/features/update_check/background/update_check_background_runner_test.dart](../../test/features/update_check/background/update_check_background_runner_test.dart) — `state unreadable (before the first unlock): skip, never reset` (unit).
  - Real: real background update state file and runner.
  - Faked: chmod models protected data; fetcher/poster/clock.
  - Proves / registration: test/features/update_check/background/update_check_background_runner_test.dart:260: Unreadable state performs no fetch/post and preserves bytes; no genuine first-unlock OS boundary. Registered: host-all, update-check.
- [test/core/secure_storage/flutter_secure_key_store_test.dart](../../test/core/secure_storage/flutter_secure_key_store_test.dart) — `storage failure still finishes the fence and preserves the primary error` (unit).
  - Real: FlutterSecureKeyStore authority-mutation orchestration.
  - Faked: secure-storage MethodChannel failure; native mutation publisher.
  - Proves / registration: test/core/secure_storage/flutter_secure_key_store_test.dart:160: A storage exception remains the primary error and the authority fence still finishes; actual OS keychain/keystore is mocked. Registered: affected-storage, host-all.
- [test/features/identity/domain/repositories/identity_repository_impl_test.dart](../../test/features/identity/domain/repositories/identity_repository_impl_test.dart) — `returns null when privateKey is missing from both stores` (unit).
  - Real: identity load qualification.
  - Faked: DB row and secure-store callbacks.
  - Proves / registration: test/features/identity/domain/repositories/identity_repository_impl_test.dart:210: Incomplete key material yields no usable identity; does not invent one from partial data. Registered: affected-identity, host-all.

**Remaining gaps**

- Host chmod and mocked platform exceptions do not establish Android/iOS first-unlock protection across notification, call and account owners.

#### LOCAL-003 — Account erase/reset removes owned database, files, notifications and secure references with consent

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open the supported blocked-account erase/reset flow.
2. Confirm the destructive action.
3. Remove owned database/files/secure references and exact notification recovery; handle erase failure.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: migrated-out blocked account; input: explicit confirmation versus erase failure; recovery: retain authority on incomplete database erase.

**Expected:** Explicit erase retires account authority and owned local data in order; database failure retains required keys and unrelated delivered notifications are preserved.

**Inspected test evidence**

- [test/features/identity/presentation/screens/startup_router_recovery_test.dart](../../test/features/identity/presentation/screens/startup_router_recovery_test.dart) — `migrated-out erase clears iOS recovery without clearing all delivered notifications` (widget).
  - Real: real blocked-account consent UI; erase ordering and authority repository.
  - Faked: identity/secure store; database erasure/native notification hooks; P2P.
  - Proves / registration: test/features/identity/presentation/screens/startup_router_recovery_test.dart:631: Explicit confirmation invalidates visibility, retires binding and clears exact recovery before database erase and key removal; broad delivered-notification clearing is deliberately not called. Registered: affected-identity, host-all, startup.
- [test/features/identity/presentation/screens/startup_router_recovery_test.dart](../../test/features/identity/presentation/screens/startup_router_recovery_test.dart) — `database erase failure preserves the key and migrated-out authority` (widget).
  - Real: real blocked-account failure UI/authority policy.
  - Faked: throwing database erase; secure store/P2P.
  - Proves / registration: test/features/identity/presentation/screens/startup_router_recovery_test.dart:717: Database erase failure retains encryption key and migrated-out authority, starts no P2P and keeps blocked UI. Registered: affected-identity, host-all, startup.
- [test/features/account_migration/application/migration_secure_storage_cleanup_test.dart](../../test/features/account_migration/application/migration_secure_storage_cleanup_test.dart) — `explicit account erase/reset deletes registry-owned active keys` (unit).
  - Real: actual registry resolution/cleanup across primary/shared scopes.
  - Faked: in-memory primary/shared secure stores.
  - Proves / registration: test/features/account_migration/application/migration_secure_storage_cleanup_test.dart:27: Explicit reset deletes every fixed and discovered group/media reference; non-explicit cleanup separately preserves device-local authority. Registered: affected-storage, host-all.

**Remaining gaps**

- UI, registry and cleanup order are meaningful, but database/files/native recovery hooks and secure store are fake in the combined widget journey; actual on-disk/native erasure is unverified.

#### LOCAL-004 — Corrupt/partial local data reports failure and recovers without inventing sent/connected state

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Load incomplete/corrupt local account data or fail a local write.
2. Observe error/blocked state and retain previous valid state.
3. Repair/restart and retry without inventing sent/connected success.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: missing keys, failed DB upsert/erase; recovery: repair and retry.

**Expected:** Partial data cannot qualify an unusable identity; failed writes preserve known valid state and expose failure.

**Inspected test evidence**

- [test/features/identity/domain/repositories/identity_repository_impl_test.dart](../../test/features/identity/domain/repositories/identity_repository_impl_test.dart) — `failed saveIdentity does not poison a warm cache` (unit).
  - Real: IdentityRepositoryImpl error/cache handling.
  - Faked: failing DB upsert callback; secure store.
  - Proves / registration: test/features/identity/domain/repositories/identity_repository_impl_test.dart:430: Failed save rethrows and preserves the previous cached identity; no power-loss or corrupt encrypted database is induced. Registered: affected-identity, host-all.
- [test/features/identity/domain/repositories/identity_repository_impl_test.dart](../../test/features/identity/domain/repositories/identity_repository_impl_test.dart) — `returns null when privateKey is missing from both stores` (unit).
  - Real: identity load qualification.
  - Faked: DB row and secure-store callbacks.
  - Proves / registration: test/features/identity/domain/repositories/identity_repository_impl_test.dart:210: Incomplete key material yields no usable identity; does not invent one from partial data. Registered: affected-identity, host-all.
- [test/features/identity/presentation/screens/startup_router_recovery_test.dart](../../test/features/identity/presentation/screens/startup_router_recovery_test.dart) — `database erase failure preserves the key and migrated-out authority` (widget).
  - Real: real blocked-account failure UI/authority policy.
  - Faked: throwing database erase; secure store/P2P.
  - Proves / registration: test/features/identity/presentation/screens/startup_router_recovery_test.dart:717: Database erase failure retains encryption key and migrated-out authority, starts no P2P and keeps blocked UI. Registered: affected-identity, host-all, startup.

**Remaining gaps**

- Assertions cover representative identity/erase seams, not every message/call/media corruption path or actual interrupted SQLCipher write.

#### LOCAL-005 — Logging, diagnostics and notification outputs redact keys, protected media and hidden peer identifiers

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Submit sensitive identities, errors and media-related values to logging/diagnostics/notification paths.
2. Persist/export or display the resulting output.
3. Inspect that only the allowed redacted fields escape.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: diagnostic collection/export and notification display; input: hostile private payload/path/key-like values; recovery: n/a.

**Expected:** Outputs follow their privacy policy and do not expose keys, protected media or hidden identifiers.

**Inspected test evidence**

- [test/core/diagnostics/app_diagnostics_test.dart](../../test/core/diagnostics/app_diagnostics_test.dart) — `private keys and exception text cannot enter the archive` (unit).
  - Real: actual diagnostic admission/export/fingerprint.
  - Faked: test-install native/relay seams.
  - Proves / registration: test/core/diagnostics/app_diagnostics_test.dart:1243: Submits hostile operation/media/error/path/stack strings and asserts they are absent from exported bytes; keeps only typed error class/source fingerprint. Registered: diagnostics, host-all, notification-lock-diagnostics.
- [test/features/call/diagnostics/call_diagnostics_test.dart](../../test/features/call/diagnostics/call_diagnostics_test.dart) — `protocol identities and arbitrary payloads cannot enter persisted or exported events` (unit).
  - Real: real call diagnostic schema and state file/export.
  - Faked: native collector/relay.
  - Proves / registration: test/features/call/diagnostics/call_diagnostics_test.dart:1476: Submitted peer/call/SDP/address/error strings never persist/export; allowlisted counters remain. Registered: affected-calls, diagnostics, host-all.

**Remaining gaps**

- Diagnostic byte-level rejection is substantive; it does not prove every production log sink/native notification lock-screen or private-media surface. Those require separate NOTIFY/MEDIA assertions and exact artifact observations.

### ACCESS — Localization, accessibility and usable interaction

#### ACCESS-001 — Arabic/RTL names, emoji and long text remain readable through composition, delivery and recipient render

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Compose Arabic/RTL, emoji and long mixed-script content.
2. Send to another user.
3. Read the received body, name and quote in the intended direction.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: Arabic-first/English-first mixed scripts, emoji and long content; recovery: n/a.

**Expected:** Text remains intact/readable through sender composition, delivery and recipient rendering.

**Inspected test evidence**

- [test/features/conversation/presentation/widgets/compose_area_test.dart](../../test/features/conversation/presentation/widgets/compose_area_test.dart) — `TextField switches to RTL for Arabic-first mixed text` (widget).
  - Real: real composer TextField and input direction policy.
  - Faked: composer callbacks.
  - Proves / registration: test/features/conversation/presentation/widgets/compose_area_test.dart:272: Typing Arabic-first mixed text selects RTL; no send/network/recipient is present. Registered: affected-conversation, host-all, ui-action-discoverability, ui-tap-gestures.
- [test/features/conversation/presentation/widgets/letter_card_test.dart](../../test/features/conversation/presentation/widgets/letter_card_test.dart) — `Arabic-first mixed text drives RTL on body RichText` (widget).
  - Real: LetterCard/LinkableText actual rich-text direction.
  - Faked: fixture message and callbacks.
  - Proves / registration: test/features/conversation/presentation/widgets/letter_card_test.dart:658: Arabic-first received-body fixture renders RTL; separate English-first case renders LTR. Does not join sender delivery or long/emoji text transport. Registered: affected-conversation, host-all.

**Remaining gaps**

- Direction is asserted independently at composer and rendered fixture; no single mixed-script/emoji/long-text send-to-recipient assertion or full bidirectional visual proof is established.

#### ACCESS-002 — Screen-reader labels, disabled actions and minimum interaction targets preserve correct outcomes

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Navigate actions by accessibility semantics.
2. Activate the intended enabled control; inspect disabled state.
3. Verify exact target and usable hit dimensions.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: semantics navigation; enabled/disabled actions; recovery: n/a.

**Expected:** Controls have meaningful labels/actions, adequate targets and cannot invoke the wrong/disabled operation.

**Inspected test evidence**

- [test/features/groups/presentation/widgets/group_member_remove_accessibility_test.dart](../../test/features/groups/presentation/widgets/group_member_remove_accessibility_test.dart) — `accessible removal selects the exact member` (widget).
  - Real: actual group member row semantics and tap.
  - Faked: onRemove callback.
  - Proves / registration: test/features/groups/presentation/widgets/group_member_remove_accessibility_test.dart:10: Semantics identifier has a tap action and selects exactly the intended member, leaving sibling control present. Registered: affected-groups, host-all, production-journey-contracts.
- [test/features/settings/presentation/widgets/settings_qr_tiles_test.dart](../../test/features/settings/presentation/widgets/settings_qr_tiles_test.dart) — `T7 tile hit targets are at least 44x44` (widget).
  - Real: actual QR tile layout.
  - Faked: host callbacks.
  - Proves / registration: test/features/settings/presentation/widgets/settings_qr_tiles_test.dart:201: Both tile targets measure at least44x44; this is not an app-wide target-size audit. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Representative group and QR controls have causal assertions; no complete TalkBack/VoiceOver traversal or app-wide semantics/minimum-target audit.

#### ACCESS-003 — Keyboard, large text, orientation and narrow viewports keep composer/dialog/call actions reachable

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Open composer/dialog/call controls with keyboard.
2. Use landscape/narrow viewports and enlarged text.
3. Reach and invoke the required visible actions.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: conversation/call/Settings; input: landscape/narrow viewport, keyboard inset,1.5x text; recovery: n/a.

**Expected:** Input and essential actions remain reachable without overflow or loss of draft.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_screen_test.dart](../../test/features/conversation/presentation/screens/conversation_screen_test.dart) — `chat keeps message space above a landscape Android keyboard` (widget).
  - Real: real conversation layout, focus/draft text.
  - Faked: host physical size/density/viewInsets/padding; fixture messages/callbacks.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_screen_test.dart:2341: A simulated landscape keyboard leaves over40px message space, shows input, restores header after hiding, and retains unsent text. Registered: affected-conversation, host-all, ui-tap-gestures.
- [test/features/call/presentation/foreground_call_overlay_test.dart](../../test/features/call/presentation/foreground_call_overlay_test.dart) — `call controls stay above the keyboard inset` (widget).
  - Real: real foreground call controls/layout.
  - Faked: call capability projections; MediaQuery keyboard inset.
  - Proves / registration: test/features/call/presentation/foreground_call_overlay_test.dart:1476: Cancel/Mute/Speaker/End remain above the injected keyboard edge; no native IME, screen reader or audio session. Registered: affected-calls, host-all, ui-approved-recovery-readability.
- [test/features/settings/presentation/screens/settings_one_screen_layout_test.dart](../../test/features/settings/presentation/screens/settings_one_screen_layout_test.dart) — `T5 textScale 1.5 lays out without overflow` (widget).
  - Real: real Settings layout/scrolling.
  - Faked: host viewport/text scale; fixture settings.
  - Proves / registration: test/features/settings/presentation/screens/settings_one_screen_layout_test.dart:223: At1.5x text the page has no observed layout exception and scrolls to Move Account. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Host-injected geometry covers real layouts, but not every dialog/screen or native keyboard/rotation/screen-reader operation.

#### ACCESS-004 — Background/theme choices preserve text and action contrast across app surfaces

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Switch supported backgrounds/themes.
2. Read message/settings/dialog/call content and actions.
3. Keep selected/disabled states distinguishable.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: Default/Cosmic/Aurora/Signal representative light/dark backgrounds; recovery: n/a.

**Expected:** Content and actions retain readable contrast on the supported backgrounds.

**Inspected test evidence**

- [test/features/settings/presentation/screens/settings_one_screen_layout_test.dart](../../test/features/settings/presentation/screens/settings_one_screen_layout_test.dart) — `T6 daylight tone renders light readable roles on rows` (widget).
  - Real: actual Settings text styles and semantic palette.
  - Faked: representative background selection.
  - Proves / registration: test/features/settings/presentation/screens/settings_one_screen_layout_test.dart:249: Checks label/title colors match representative-light tokens; token equality is not measured contrast on every background/surface. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Palette-role equality and selected Settings layouts are asserted; no exhaustive computed/pixel contrast and actual-device background matrix across app surfaces.

#### ACCESS-005 — Loading/empty/error/retry states remain usable without silently dropping entered data

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Enter data and start an operation.
2. Hold loading or force an empty/error result.
3. Retry/dismiss and inspect preserved input and truthful state.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: pending/failed send and long accessible layouts; recovery: retry with retained draft.

**Expected:** Loading/error/retry remains usable and does not silently discard entered data or invent completion.

**Inspected test evidence**

- [test/features/conversation/presentation/screens/conversation_wired_test.dart](../../test/features/conversation/presentation/screens/conversation_wired_test.dart) — `restores draft and removes fresh memory-only optimism when send returns null without custody authority` (widget).
  - Real: real conversation optimistic UI and draft restoration.
  - Faked: held send callback returning nodeNotRunning/null; message/identity/contact repositories.
  - Proves / registration: test/features/conversation/presentation/screens/conversation_wired_test.dart:6328: Failed fresh send restores exact text, removes memory-only optimistic message and does not persist a false successful row. Registered: affected-conversation, host-all.
- [test/features/settings/presentation/screens/settings_one_screen_layout_test.dart](../../test/features/settings/presentation/screens/settings_one_screen_layout_test.dart) — `T5 textScale 1.5 lays out without overflow` (widget).
  - Real: real Settings layout/scrolling.
  - Faked: host viewport/text scale; fixture settings.
  - Proves / registration: test/features/settings/presentation/screens/settings_one_screen_layout_test.dart:223: At1.5x text the page has no observed layout exception and scrolls to Move Account. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Direct draft failure has causal widget coverage, but not all forms/permission sheets/call loading and error states in one app-wide sweep.

#### ACCESS-006 — Rapid repeated taps, swipe-back and route interruptions do not duplicate sends/consent

**Coverage:** partial. **Execution:** not_run. **Catalog:** source-derived.

**Steps**

1. Repeat taps/gestures while a send/consent/navigation action is pending.
2. Interrupt with a route/sheet.
3. Complete or retry the owned action.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: rapid taps/swipe while pending; recovery: route completion/interruption.

**Expected:** Repeated input dispatches one owned operation and interruption cannot duplicate consent/send/navigation.

**Inspected test evidence**

- [test/features/settings/presentation/screens/settings_swipe_back_test.dart](../../test/features/settings/presentation/screens/settings_swipe_back_test.dart) — `TC-226-15 one qualifying gesture fires exactly one pop` (widget).
  - Real: real Settings gesture/Navigator/AppShell state.
  - Faked: repositories and service dependencies.
  - Proves / registration: test/features/settings/presentation/screens/settings_swipe_back_test.dart:232: Repeated qualifying gesture activity pops exactly once to Orbit; adjacent topmost-sheet case keeps underlying route inert. Registered: affected-surfaces, host-all.
- [test/features/settings/presentation/widgets/settings_qr_tiles_test.dart](../../test/features/settings/presentation/widgets/settings_qr_tiles_test.dart) — `T5 rapid double-tap fires the host entry once (latch)` (widget).
  - Real: actual QR route latch/actions.
  - Faked: held host-route Future; repositories/platform services.
  - Proves / registration: test/features/settings/presentation/widgets/settings_qr_tiles_test.dart:124: Double-tap and sibling tap during one route dispatch only once; completion releases the latch. Registered: affected-surfaces, host-all.

**Remaining gaps**

- Settings navigation guards are causal; this does not certify every send, permission consent and native Back/lifecycle path. Feature-specific duplicate-send/consent assertions remain necessary.

### RELEASE — Upgrade and whole-app preservation

#### RG-001 — Published-to-candidate signed upgrade preserves messaging

**Coverage:** partial. **Execution:** not_run. **Catalog:** RG-001.

**Steps**

1. Identify the actual previous published binary and exact signed candidate/configuration.
2. Populate identity, contacts, groups, messages, media and unread state.
3. Upgrade in place, reopen retained content and exchange old/new peer messages.

**Conditions:** platform: supported available Android/iOS signed artifacts; connectivity: n/a; offline: n/a; app state: foreground; input: actual published baseline and exact candidate; recovery: in-place upgrade.

**Expected:** The signed upgrade preserves usable account/history/media/trust and old/new interoperability.

**Inspected test evidence**

- [test/core/database/integration/full_migration_chain_test.dart](../../test/core/database/integration/full_migration_chain_test.dart) — `1b. Step-by-step upgrade preserves seeded data` (integration).
  - Real: real001–026 migrations and FFI SQLite rows.
  - Faked: constructed old schema; FakeSecureKeyStore.
  - Proves / registration: test/core/database/integration/full_migration_chain_test.dart:762: Seeded identity/contact/request fields and a group row survive migration. This broad case ends atv26 and is not the actual previous published database/signed app. Registered: affected-storage, host-all, migration.
- [tool/testing/selection.json](../../tool/testing/selection.json) — `signed-upgrade-compat` (release).
  - Real: required actual published-to-candidate upgrade when performed.
  - Faked: none identified.
  - Proves / registration: tool/testing/selection.json:1018: Mandatory manual selector requires verified previous published revision, retained identity/contacts/groups/history/keys and old/new messaging including quiet compatibility. A registered requirement is not executed evidence; no matching artifact-bound result audited here. Registered: see cited native runner/manifest.

**Remaining gaps**

- Mandatory manual contract exists; no exact baseline/candidate/artifact-bound execution supplied or performed in this audit. Host migration source tests cannot certify signed upgrade.

#### RG-002 — Fresh onboarding reaches the first direct and group message

**Coverage:** partial. **Execution:** not_run. **Catalog:** RG-002.

**Steps**

1. Launch as an unseeded user and complete onboarding.
2. Scan/accept a real contact QR and exchange a first direct message.
3. Create/join a real group and exchange its first message.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: fresh installation; input: unseeded identity/contact/group; recovery: n/a.

**Expected:** A new user reaches real direct and group conversation without seeded contacts or bypassed consent.

**Inspected test evidence**

- [test/integration/onboarding_golden_path_test.dart](../../test/integration/onboarding_golden_path_test.dart) — `fresh identity creation, accepted contact request, and first message succeed in one flow` (integration).
  - Real: identity/contact accept/send/receive use cases; real fixture Ed25519 identity material.
  - Faked: identity/ML-KEM creation; signature validation callback; PassthroughCryptoBridge; FakeP2PNetwork and repositories.
  - Proves / registration: test/integration/onboarding_golden_path_test.dart:83: Composes generated fixture identity, accepted contact request/reciprocity and first direct message; no real UI QR scan, native secure storage, network or first group message. Registered: affected-identity, host-all.

**Remaining gaps**

- Host golden path fakes native identity/network/storage and omits real UI scan plus first group message. Existing production journeys prepare contacts, so their later sends alone cannot close this onboarding journey.

#### RG-003 — Retained backlog, expiry and pagination follow policy

**Coverage:** partial. **Execution:** not_run. **Catalog:** RG-003.

**Steps**

1. Bind actual relay/history/key-retention configuration.
2. Accumulate retained and expired backlog across pages/epochs while offline.
3. Catch up completely in order, report supported expiry honestly and resume live traffic.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: long offline then reconnect; offline: controlled clock retained/expired boundaries; app state: foreground; input: paged backlog and historical key epochs; recovery: catch-up then new live delivery.

**Expected:** Every retained eligible event converges once; expired history does not wedge later retained/live work.

**Inspected test evidence**

- [test/features/groups/application/drain_group_offline_inbox_use_case_test.dart](../../test/features/groups/application/drain_group_offline_inbox_use_case_test.dart) — `mixed old and new cursor pages keep retained backlog and record both boundaries` (unit).
  - Real: actual group offline drain and retention boundary policy.
  - Faked: cursor pages/clock; group/message repositories and bridge crypto.
  - Proves / registration: test/features/groups/application/drain_group_offline_inbox_use_case_test.dart:8989: An expired first page does not stop a later retained page; stores one retained message and exact expired/retained boundaries over two retrievals. Registered: affected-groups, host-all.

**Remaining gaps**

- Controlled host drain demonstrates a narrower boundary; no complete direct/group actual relay TTL plus key-retention/epoch/page signed-app catch-up. Seven-day history policy is not by itself proof of relay TTL.

#### RG-004 — Rejected incoming events do not wedge valid delivery

**Coverage:** partial. **Execution:** not_run. **Catalog:** RG-004.

**Steps**

1. Process malformed or undecryptable input at the real receiving completion boundary.
2. Check no rejected event/state mutation escaped.
3. Process a valid event through the same owner and replay it.

**Conditions:** platform: shared Android/iOS logic; host evidence only; connectivity: n/a; offline: n/a; app state: foreground; input: malformed JSON and injected decrypt failure followed by valid/replay event; recovery: same listener without restart.

**Expected:** Rejected input preserves existing state and cannot wedge the next valid delivery or deduplication.

**Inspected test evidence**

- [test/features/conversation/integration/rejected_events_preserve_valid_delivery_test.dart](../../test/features/conversation/integration/rejected_events_preserve_valid_delivery_test.dart) — `malformed JSON then valid message` (integration).
  - Real: ChatMessageListener/process completion; production current SQLite schema and repositories; DatabaseDirectTransportAuthority.
  - Faked: single decrypt-failure seam and passthrough valid crypto; FakeSecureKeyStore; injected messages without actual router/socket.
  - Proves / registration: test/features/conversation/integration/rejected_events_preserve_valid_delivery_test.dart:178: Conditional declaration expands to this exact name; awaits rejection, proves unchanged prior history/contact, processes a valid event through the same listener, and proves replay duplicate with exactly two rows. Real AEAD rejection and group/native receiving loop are outside this test. Registered: affected-conversation, host-all.
- [test/features/conversation/integration/rejected_events_preserve_valid_delivery_test.dart](../../test/features/conversation/integration/rejected_events_preserve_valid_delivery_test.dart) — `failed decryption then valid message` (integration).
  - Real: ChatMessageListener/process completion; production current SQLite schema and repositories; DatabaseDirectTransportAuthority.
  - Faked: single decrypt-failure seam and passthrough valid crypto; FakeSecureKeyStore; injected messages without actual router/socket.
  - Proves / registration: test/features/conversation/integration/rejected_events_preserve_valid_delivery_test.dart:178: Conditional declaration expands to this exact name; awaits rejection, proves unchanged prior history/contact, processes a valid event through the same listener, and proves replay duplicate with exactly two rows. Real AEAD rejection and group/native receiving loop are outside this test. Registered: affected-conversation, host-all.

**Remaining gaps**

- Direct listener/real SQL subsequent-delivery proof exists. Decryption is a controlled failure seam; it does not cover genuine cryptographic malformed inputs, all group events or native production transport loops.

#### RELEASE-004 — Candidate permissions/platform configuration and first-unlock behavior match supported release claims

**Coverage:** partial. **Execution:** not_run. **Catalog:** RG-001, RG-002.

**Steps**

1. Inspect exact signed candidate platform permissions/entitlements/configuration.
2. Grant/deny/recover relevant OS permissions on supported available targets.
3. Exercise protected work before first unlock and after unlocking.

**Conditions:** platform: available Android/iOS targets; none accessed in this host audit; connectivity: n/a; offline: n/a; app state: foreground; input: candidate platform config and granted/denied/protected states; recovery: Settings permission change and first unlock.

**Expected:** The shipped artifact matches declared platform/privacy behavior and permission/protected-state failure remains truthful and recoverable.

**Inspected test evidence**

- [test/core/notifications/ios_app_visibility_privacy_manifest_contract_test.dart](../../test/core/notifications/ios_app_visibility_privacy_manifest_contract_test.dart) — `TC-371-06 iOS visibility targets declare exact required-reason APIs` (unit).
  - Real: actual checked-in privacy manifests/project source.
  - Faked: none identified.
  - Proves / registration: test/core/notifications/ios_app_visibility_privacy_manifest_contract_test.dart:6: Source contract verifies required-reason API declarations; does not inspect entitlements/configuration of a signed distributed candidate. Registered: affected-push, host-all.
- [test/core/permissions/mic_permission_prompt_test.dart](../../test/core/permissions/mic_permission_prompt_test.dart) — `tapping Open Settings invokes gateway.openAppSettings exactly once and dismisses` (widget).
  - Real: real permission-recovery dialog and action.
  - Faked: permission gateway/openAppSettings.
  - Proves / registration: test/core/permissions/mic_permission_prompt_test.dart:83: Open Settings action dispatches once and dismisses; actual system settings/permissions remain unverified. Registered: host-all.

**Remaining gaps**

- Checked-in source contracts and fake gateway UI do not establish merged signed manifest/entitlements, real platform prompts, first-unlock behavior or distribution configuration. No candidate artifact was built/inspected here.

## Prioritized test plan

Ranks order the next useful proofs; run only applicable available-target legs. Missing/partial coverage is not an instruction for this host-only agent to execute device work.

<!-- ranked-gap-status:start -->
Progress as of 2026-10-26T14:45:24Z. `ready` means reviewed preparation waiting for execution; `covered` means the stated existing evidence/runner scope. No status below is a fresh device or signed-candidate PASS. Group B is in preparation. Original requirements and reasons remain below unchanged. Remote test traffic uses Hetzner; owned local fixtures are permitted; AWS is reserved for owner pre-publish lanes.

| Rank | Journey | Status | Date | Evidence / remaining scope |
| --- | --- | --- | --- | --- |
| 1 | MEDIA-002 | covered | 2026-10-26 | 10-22 Original/Compressed camera+caption/full image, source 0ee837d5d; build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:14; not signed-127 proof. |
| 2 | MEDIA-014 | covered | 2026-10-26 | 10-22 offline camera/caption and automatic full-image catch-up, 0ee837d5d; build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:16; no new device run. |
| 3 | RG-001 | ready | 2026-10-26 | Reviewed 5a769d256/7354d2942; docs/testing/rg001-store-126-to-127-mcp.md; actual signed store-upgrade proof pending. |
| 4 | VC-014 | ready | 2026-10-26 | Reviewed c3767b491:docs/testing/priority-e2e-mcp-execution.md; answered OS-state/audio observations pending; unanswered timing runs do not complete it. |
| 5 | VC-019 | preparing | 2026-10-26 | Group B in preparation; test/features/call/integration/microphone_command_privacy_test.dart is host command proof, not received content. |
| 6 | VC-025 | preparing | 2026-10-26 | Group B in preparation; test/features/call/presentation/locked_call_projection_test.dart is rendering proof, not actual locked navigation. |
| 7 | DC-002 | covered | 2026-10-26 | Existing 100-text/restart runner: integration_test/scripts/run_production_direct_ordered_replay.dart; no new native execution. |
| 8 | GC-005 | covered | 2026-10-26 | Existing ordered/process-death runners documented in 0107badee:docs/testing/priority-e2e-codex-mcp-execution.md; no new native execution. |
| 9 | TRANSFER-011 | not_started | 2026-10-26 | Scoped 10-23 simulator PASS retained; audible voice and missing-original recovery remain open; .codex-test-logs/transfer011-20261023T0941Z/SUMMARY.md:10. |
| 10 | VC-026 | preparing | 2026-10-26 | Group B in preparation; test/features/call/integration/process_loss_recovery_decisions_test.dart supplies observations, not actual process death. |
| 11 | CONTACT-001 | ready | 2026-10-26 | Reviewed 0107badee:docs/testing/priority-e2e-codex-mcp-execution.md (CONTACT-001); native scanner/permission execution pending. |
| 12 | MEDIA-010 | ready | 2026-10-26 | Reviewed 0107badee:docs/testing/priority-e2e-codex-mcp-execution.md (MEDIA-010); native permission/draft/retry execution pending. |
| 13 | MEDIA-003 | covered | 2026-10-26 | 10-22 reverse camera/caption/full iPhone viewer, source 0ee837d5d; build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:18; not signed-127 proof. |
| 14 | MEDIA-035 | ready | 2026-10-26 | Reviewed 0107badee:docs/testing/priority-e2e-codex-mcp-execution.md (MEDIA-035); actual every-recipient full-image execution pending. |
| 15 | VC-015 | ready | 2026-10-26 | Reviewed c3767b491:docs/testing/priority-e2e-mcp-execution.md; 10-22 structural calls do not establish intelligible bidirectional audio. |
| 16 | DC-011 | ready | 2026-10-26 | Reviewed c3767b491:docs/testing/priority-e2e-mcp-execution.md; historical media component evidence is not exact signed-candidate parity proof. |
| 17 | CR-009 | ready | 2026-10-26 | Reviewed c3767b491:docs/testing/priority-e2e-mcp-execution.md; fresh native cross-platform scan/consent/key exchange pending. |
| 18 | GX-002 | ready | 2026-10-26 | Reviewed c3767b491:docs/testing/priority-e2e-mcp-execution.md; actual mixed-platform full-media/membership execution pending. |
| 19 | VC-023 | ready | 2026-10-26 | Reviewed 0107badee:docs/testing/priority-e2e-codex-mcp-execution.md (VC-023); actual selected route/TURN outage/privacy execution pending. |
| 20 | MEDIA-018 | ready | 2026-10-26 | Reviewed 0107badee:docs/testing/priority-e2e-codex-mcp-execution.md (MEDIA-018), including cut-actor binding; native partial-transfer recovery pending. |
| 21 | VC-024 | not_started | 2026-10-26 | Not started: sustained bidirectional audio/resource proof; only unavailable wired/Bluetooth accessory legs are N/A per owner; /Volumes/CrucialX9/Kayan/testplan.yaml (VC-024). |
| 22 | GX-001 | n_a | 2026-10-26 | Owner reports eight concurrent targets unavailable; /Volumes/CrucialX9/Kayan/testplan.yaml (GX-001); N/A by available-target policy. |
| 23 | NAV-006 | blocked | 2026-10-26 | Owner decision on supported Inner-Circle membership/order entry remains pending; docs/testing/journey-coverage-matrix.md (NAV-006). |

DC-013 is outside this rank list; reuse `run_production_contact_delete.dart` (`kx0010`/`kx0011`) per `0d7e4f1f7:docs/testing/privacy-e2e-mcp.md`. No rank or journey rating is added.
<!-- ranked-gap-status:end -->

1. **MEDIA-002** (e2e): Reproduce actual iPhone camera Original and compressed image+caption to Android over relay-only online path; recipient opens full correct image and exact caption. Record actual MIME/encoded fixture privately, never assume HEIC. Owner-reported stock125 incident is not covered by synthetic-byte or caption-only widget tests.
2. **MEDIA-014** (e2e): Repeat same camera/quality/caption assertion with Android offline then supported foreground/inbox catch-up, preserving accepted identity and full decode after restart. Offline relay custody/hydration can fail independently from online rendition.
3. **RG-001** (release): Bind actual previous published revision and exact candidate source/configuration/signed artifact; execute mandatory-plus-affected preservation and required available-target manual/device legs. Host/source or a later/debug artifact cannot certify the signed upgrade released to users.
4. **VC-014** (e2e): Correlate provider acceptance, actual OS wake/system presentation and answered audio in supported suspended/process-terminated/locked states on available platforms. Host admission/journal tests cannot prove platform courier/OS delivery and first-attempt missed ring remains evidence.
5. **VC-019** (e2e): Use causal received audio/content oracle before answer, while either peer muted and after hangup, with positive unmuted controls and lifecycle changes. Command counters and continuing RTP do not prove microphone content is absent.
6. **VC-025** (e2e): Answer through actual locked system surface, attempt allowed/forbidden navigation and inspect visual/touch/accessibility history exposure until real unlock. Semantics-only modal tests and locked no-dial callback prove different boundaries.
7. **DC-002** (e2e): Send100 numbered texts, kill/restart both sides at verified checkpoints, then assert every exact logical row/content/order once and later live delivery. Smaller bursts and unrelated routing criteria cannot prove this100-message restart contract.
8. **GC-005** (e2e): Kill actual owned sender at verified accepted-text custody checkpoint, reopen and verify same-ID delivery once while preserving membership-window authority. Current verified process-death campaign covers membership add/removal/re-add only.
9. **TRANSFER-011** (e2e): Preserve scoped simulator receiver media-open/relaunch PASS; verify intelligible migrated voice and missing-original recovery on available targets. Silent playback/file preservation does not prove those remaining boundaries. Physical-iPhone receiver leg NOT RUN; unavailable alternate targets are N/A by project policy.
10. **VC-026** (e2e): Kill actual ringing/active app; inspect owned native capture/call/card release or reconciliation, remote deadline and fresh call after restart. Graceful teardown and supplied native replay cannot stand for hard process loss.
11. **CONTACT-001** (e2e): Cancel native scanner before code/result and deny/grant camera permission; assert zero contact/request/egress on refusal and one valid request after retry. Accepted paste/late callback tests do not exercise camera cancellation before result.
12. **MEDIA-010** (e2e): Deny camera/photo access, grant via supported OS flow and retry without losing draft, duplicate sends or false success. Picker/permission callbacks in host tests bypass OS permission state.
13. **MEDIA-003** (e2e): Actual Android camera plus caption reaches available iPhone and full image decodes with correct content/caption in supported rendition. Reverse-direction native camera/codec boundary remains untested.
14. **MEDIA-035** (e2e): Actual group camera image/caption opens as full correct image on every authorized available member; exclude removed member and retain partial failures honestly. Synthetic fanout and rows/status are not each-recipient decode evidence.
15. **VC-015** (e2e): Available iPhone/Android each initiate and answer, exchange intelligible audio and clean both native owners. Android-only RTP does not establish mixed-platform audible interoperability.
16. **DC-011** (e2e): Use actual available iOS/Android signed candidates for bidirectional text and full representative media with exact identity/caption/restart assertions. Shared host logic and single-platform campaigns do not certify parity.
17. **CR-009** (e2e): Scan/add each platform in both directions, accept/decline and complete reciprocal key exchange then first real chat. Host lookup encryption/bridge substitutes do not establish native cross-platform contact protocol.
18. **GX-002** (e2e): With available mixed-platform group topology, exchange full text/media and apply add/remove/re-add with every entitled receiver checked. Small single-platform production cases and fake group policies leave full parity incomplete.
19. **VC-023** (e2e): Enable user always-relay preference, observe actual selected route, remove TURN and prove no direct fallback, restore TURN and call again. Forced-relay build, saved boolean and fake outage policy are separate assertions.
20. **MEDIA-018** (e2e): Kill sender/receiver at durable upload/download cuts and recover full native usable content once, preserving original failed attempt. Fake bridges/object reconstruction and thumbnail visibility are insufficient for native full-content recovery.
21. **VC-024** (e2e): Specify duration/resource thresholds, hold real bidirectional audio and test only actually available output accessories with positive audio continuity. Short RTP/control runs and sampler unit tests cannot prove sustained audio/resource behavior.
22. **GX-001** (e2e): When eight concurrent app targets are actually available, expand role binding and exact every-sender/every-receiver dedupe assertions. Five fake peers and three/four actual actors do not prove eight-member scale; unavailable topology N/A.
23. **NAV-006** (manual): Owner identifies concrete supported manual Inner-Circle membership/order entry, or confirms automatic recency/sculpt-only policy. Unknown reachability should be resolved before inventing a shipped missing editor or planned commitment.

## Exclusions

- **Video calling and custom app-password/biometric unlock flows:** No supported implementation/entry discovered; do not invent planned product commitments. Voice calls and actual OS/private-media protection are included.
- **Debug/E2E-only entrypoints under lib/debug and lib/core/debug:** Harness controls are test infrastructure, not shipped user entrypoints; actual production adapters/scenarios remain evidence when inspecting tests.
- **Exhaustive platform/network/state/format Cartesian product:** Not claimed. Separate rows cover changed outcome/risk; other combinations are representative and explicitly unproven in per-row gaps.
- **Unattached render-only subwidgets and low-level DB/crypto/transport helpers:** Map through their owning user journeys; avoid counting implementation functions as extra user journeys.

## Planned / unreachable scope

- **Full Posts authoring/feed/comments/pass-along/pin UI:** Implementation and tests exist, but rg PostsWired( lib finds only its declaration; AppShellTab supports Feed/Orbit only. Root post notification reveal only popUntil(first). Treat retained dormant UI as planned/unreachable until owner clarifies supported entry; audit the reachable post-notification route separately.
- **Unqualified group same-user convergence after phrase restore:** kMultiDeviceSyncEnabled defaults off; source explicitly describes full convergence as unfinished. Do not equate phrase restore with historical group/key hydration. Implemented flag-gated linked-group pieces remain in LINKED rows.
- **Relay-to-direct call upgrade (VC-013):** Inactive vc02.dcutr_upgrade and negative symmetric-NAT capability have automationReady=false; future/conditional, not a current unconditional release gate.

## Commands and evidence

Commands below identify audit/validation work and the one fresh behavioral subset; the ignored handoff retains stdout and gate logs. Source navigation used targeted `rg`/bounded reads and actual assertion/fake/runner inspection. No workflow/SIMS inventory declaration is treated as a passing run.

- `git rev-parse HEAD`
- `git branch --show-current`
- `rg --files test`
- `python3 .codex-test-logs/astra-matrix/index_tests.py`
- `python3 .codex-test-logs/astra-matrix/audit_update.py`
- `python3 .codex-test-logs/astra-matrix/audit_identity.py`
- `python3 .codex-test-logs/astra-matrix/audit_diag.py`
- `python3 .codex-test-logs/astra-matrix/audit_settings.py`
- `python3 .codex-test-logs/astra-matrix/audit_local.py`
- `python3 .codex-test-logs/astra-matrix/audit_access.py`
- `python3 .codex-test-logs/astra-matrix/audit_release.py`
- `python3 .codex-test-logs/astra-matrix/audit_nav.py`
- `python3 .codex-test-logs/astra-matrix/audit_share.py`
- `python3 .codex-test-logs/astra-matrix/audit_intro.py`
- `python3 .codex-test-logs/astra-matrix/audit_transport.py`
- `python3 .codex-test-logs/astra-matrix/audit_media.py`
- `python3 .codex-test-logs/astra-matrix/audit_chat.py`
- `python3 .codex-test-logs/astra-matrix/audit_notify.py`
- `python3 .codex-test-logs/astra-matrix/audit_linked.py`
- `python3 .codex-test-logs/astra-matrix/audit_transfer.py`
- `python3 .codex-test-logs/astra-matrix/audit_contact.py`
- `python3 .codex-test-logs/astra-matrix/audit_group.py`
- `python3 .codex-test-logs/astra-matrix/audit_call.py`
- `python3 .codex-test-logs/astra-matrix/host_gate_run.py .codex-test-logs/astra-matrix/pubget-attempt2.log flutter pub get --offline --enforce-lockfile`
- `python3 .codex-test-logs/astra-matrix/host_gate_run.py .codex-test-logs/astra-matrix/media-bytes.log flutter test --no-pub --concurrency=1 --reporter expanded test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart`
- `python3 .codex-test-logs/astra-matrix/render_matrix.py`
- `python3 .codex-test-logs/astra-matrix/validate_matrix.py`
- `python3 scripts/mknoon_checks.py validate`
- `python3 scripts/mknoon_checks.py plan --mode change --base a502c06bc7b2a87c66e01495d4d2285f6731be3e --local --output .codex-test-logs/astra-matrix/change-plan`
- `python3 .codex-test-logs/astra-matrix/static_change_plan.py`
- `python3 scripts/mknoon_checks.py plan --mode change --base a502c06bc7b2a87c66e01495d4d2285f6731be3e --local --output .codex-test-logs/astra-matrix/change-plan-v3`
- `git diff --check`

Fresh behavioral stdout: `build/kayan-safe/astra-matrix/media-bytes.log` (4 passed, 0 skipped, exit 0). Dependency stdout: `pubget-attempt2.log` (exit 0). Held-before-launch evidence: `pubget.log`, `update-verifier.log`, `safety-support.log`. Static validation/change-plan and patch identity are retained separately in that handoff.
