# App diagnostics validation

The final curated 1:1 gate passed for source stamp `f1899f0d63e1724b`: **3,544 passed, 4 skipped, 0 failed**, across 212 Flutter test paths; exit 0. All 58 production input hashes matched the captured `final-tested-source-manifest.json` both before and after the run. It used Flutter 3.47.2, `GOTOOLCHAIN=go1.25.0` and concurrency 4, and completed before final mobile packaging. The log is `/tmp/call-observability-20260908/curated-1to1-final-admission-cause.log`; `final-curated-result.json` identifies the exact tested source and schema. Six non-failing widget hit-test warnings remained: five backdrop taps and one ListView drag.

The preceding correlation/quota gate on source `181a39528fd16ea2` passed 3,543 tests with 4 skips. Its result remains separately preserved in `curated-correlation-quota-final-result.json`, and its raw log is `/tmp/call-observability-20260908/curated-1to1-final-correlation-quota.log`.

The preceding curated run passed after both Android and iOS builds completed with source stamp `447d22a1e20fb7ae`: **3,539 passed, 4 skipped, 0 failed**, across 212 Flutter test paths. The gate exited 0. It used Flutter 3.47.2, `GOTOOLCHAIN=go1.25.0`, batched execution and concurrency 4. No production or test-harness changes were needed during that run. Its raw log remains `/tmp/call-observability-20260908/curated-1to1-final-envelope.log`.

These are separate test invocations. They overlap and must not be added together as a unique test total.

| Invocation | Result | Evidence |
| --- | --- | --- |
| Final curated 1:1 preservation gate after diagnostic-only admission cause batch | 3,544 passed; 4 skipped; 0 failed; exit 0 | `final-curated-result.json` |
| Correlation/quota curated gate after test completion wait | 3,543 passed; 4 skipped; 0 failed; exit 0 | `curated-correlation-quota-final-result.json` |
| Final headless, runtime, closed-schema and wire-fixture checks | 53 passed | `/tmp/call-observability-20260908/headless-cause-schema-final-green.log` |
| Runtime correlation, native endpoint roles, queue priority and permanent rejection regressions | 23 passed | `/tmp/call-observability-20260908/runtime-correlation-quota-green.log` |
| Prior curated 1:1 preservation gate after consent envelope and status UI fixes | 3,539 passed; 4 skipped; exit 0 | `/tmp/call-observability-20260908/curated-1to1-final-envelope.log` |
| Runtime archive and actual GoBridgeClient contract after the live consent-envelope fix | 138 passed | `/tmp/call-observability-20260908/runtime-native-envelope-green.log` |
| Production composition and authenticated incoming handler, including audio and presentation refusal assertions | 111 passed | `/tmp/call-observability-20260908/refusal-final-preservation.log` |
| App emission cases: preflight, native answer, signaling, TURN, token origin | 147 passed | `/tmp/call-diagnostics-emission-final.log` |
| Exact affected call, native-adapter, bridge, media and settings preservation files | 311 passed | `/tmp/call-diagnostics-preservation-final.log` |
| Terminal classification and conversation call retry sentinels | 9 passed | `/tmp/call-diagnostics-terminal-conversation-final.log` |
| Explicit unavailable-call tap capture widget test | 1 passed | `/tmp/call-diagnostics-conversation-tap-2.log` |
| Reviewed ConversationScreen handoff contract | 1 passed | `/tmp/call-diagnostics-handoff-contract-green.log` |
| Isolated durable-media-preparation test after one contested host run timed out | 1 passed unchanged | `/tmp/call-observability-20260908/media-prep-isolated.log` |
| Exact production-wired media-forwarding test after completion-wait correction | 1 passed | `/tmp/call-observability-20260908/media-forward-completion-green.log` |

The consent regression failed before the fix because no configure call reached the actual native MethodChannel. After the fix, the test verifies configure, upload acknowledgments, trace resolution, disabling and clearing through GoBridgeClient's real `cmd`/`payload` dispatch. Its native transport is mocked; this is host contract evidence, not device or relay proof.

The production audio factory tests use the actual bundle, preparer, audio controller and iOS adapter. Native audio refusal produces `audio_session_failed`; accepted native activation followed by unavailable host WebRTC produces `audio_activation_failed` with `failureStage=create_connection`. The media effect receives an accepted test snapshot. These tests do not replace the separately exercised native Answer authority and device call proofs.

The incoming handler test authenticates its fixture envelope and verifies presentation refusal emits a trace-bound failed presentation without ringing or audio effects. A production graph timeout separately emits `no_answer`. The tests do not claim that an OS presentation was visually observed.

Runtime and runtime-test analysis after the envelope fix reported no issues. Earlier wider app analysis reported no errors and two existing `unawaited_return_in_try_block` warnings in the Android lifecycle adapter and conversation widget.

Four new runtime tests reproduce and verify the final correlation and quota fixes. Delayed Flutter presentation completion and native journal drain retain the resolved shared trace, including across process restart; a stale callback cannot reverse its binding or duplicate its terminal summary. Native records use the known endpoint role while unbound records retain their existing role. Under an upload backlog, the terminal summary and first verified-media record precede routine events. Transient failures preserve queued records; explicit permanent rejections advance the queue, count each drop once, and do not create retry backoff. Both new regression groups failed before their respective fixes. Runtime analysis and diff checks passed; affected query `b77f98c86f944af7` covers the runtime and its test file.

These assertions are host evidence. Earlier live calls exposed provisional-trace orphans and relay quota saturation even when local media records showed progress. That earlier live evidence does not establish complete end-to-end telemetry for the final build; the final runtime and relay changes require their own live verification.

The first final correlation/quota lane completed with 3,542 passed, 4 skipped and one failure in the existing production-wired group media-forwarding test. That test passed unchanged in isolation. Its full-lane assertion followed 80 waits of 25 milliseconds while media snapshotting, encryption and upload used real filesystem IO; the upload cleanup log arrived after the assertion. The test now waits for the durable group message and observed `group:publish`, fails explicitly on a captured Flutter error or an unmet ten-second deadline, and retains every existing payload and attachment assertion. Passing depends on actual completion, not elapsed time. This test-only correction does not change either mobile package. The initial failure remains recorded in `curated-correlation-quota-first-result.json`; affected query `353898cf2f7c40ff` covers the added test path.

The admission vocabulary check uses canonical schema SHA-256 `6ea59e2bf718345f110a3fffc03b8ecbc18bcea7bd3b7e48d6d4ced559f247db`. The generated Dart map equals that schema, the existing advisory wire fixtures remain exact, all six `admissionDisposition` values are accepted, and unknown dispositions or non-boolean readiness fields are rejected. The final focused invocation passed 53 tests: 29 production-headless tests and 24 runtime/schema tests (`headless-cause-schema-final-green.log`). Five-file analysis was clean (`headless-cause-schema-final-analyze.log`). These counts overlap the curated lane where those files are registered. Coherent affected query `c612587c4a8f462a` covers the final 14-path diagnostic batch, including the separately owned native/entrypoint changes.

The diagnostic cause is optional metadata and never authorizes admission. The following mapping applies specifically to **stage `admission`**:

| Cause | Observed source branch |
| --- | --- |
| `authority_invalid` | Missing local account binding, before any remote caller authority is examined. |
| `busy` | This headless backend already has a local session or writable lease. |
| `graph_not_owner` | The single native lease acquisition returned a state other than ACTIVE. |
| `bridge_unavailable` | That lease acquisition threw at the bridge boundary. |
| `transport_failed` | Exact-call mailbox retrieval failed. |
| `unavailable` | The retrieved page has more rows; complete custody cannot yet be judged. |
| `authority_unreachable` | A mailbox row's authentication explicitly deferred. |
| `authority_rejected` | The evaluated page has no admissible invite shape. |
| `adoption_failed` | An unexpected evaluation failure occurred. |
| `canceled` / `expired` / `invalid_request` | The existing stop or lifetime guard prevented completion. |
| `cleanup_failed` | Database closure or lease release was not proven, or teardown failed. |

In particular, `authority_invalid` here does not mean an invalid remote caller, and `busy` here does not mean the remote recipient is already in a call. A generic deferred result with successful closure/release is not itself a persistence failure. Five new headless regressions verify matched source causes, unchanged no-admission/cleanup gates, and one lease acquisition. Two of those regressions first proved that an optional throwing diagnostic getter could downgrade an admitted result or escape a deferred run; a contained accessor now preserves the original disposition and exact cleanup counts. No raw binding, payload or exception text enters the cause.
