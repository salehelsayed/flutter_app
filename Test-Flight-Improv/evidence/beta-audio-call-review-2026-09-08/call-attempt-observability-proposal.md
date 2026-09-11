# Proposed app and relay call diagnostics

Status: reviewed design, not implemented or deployed. This is an observability proposal following the twelve-call investigation, not a claim that the current beta builds already record this information.

## Objective

For every attempted call, produce a bounded diagnostic timeline showing the first failed or incomplete stage, the reported reason and originating action, what each endpoint observed, what the relay committed, and whether audio packets progressed. Include attempts that never create a call session or reach the relay. Support successful calls, deliberate declines/cancellations, technical failures, and incomplete evidence as distinct outcomes.

## Verified gaps today

| Area | Existing implementation | Gap |
| --- | --- | --- |
| Flutter events | `flow_event_emitter.dart:245` sanitizes and timestamps events; default emission is controlled by `kDebugMode` at line 6. | Normally off in profile/release. The `FDC_FLOW_LOG` override in `production_application_bootstrap.dart:525` enables printing, not persistence or upload. |
| Outgoing preflight | `call_signaling_composition.dart:238` checks microphone, graph, advertisement and wake authority. | Failures can collapse to generic failed/unavailable without an attempt record or detailed stage result. |
| Call state/media | Existing graph observers report transitions, audio-start stages and cleanup; `call_engine.dart` provides allowlisted connection/media fields. | Console/memory observations do not survive process death. Structural readiness does not prove RTP progress; existing RTP booleans mean ever observed, not sustained flow. |
| Native lifecycle | Durable CallKit/Android replay journals already record presentation, answer and terminal work. | ACK removes records; journals are bounded authority/replay state, not incident archives. Android events lack individual occurrence timestamps. |
| iPhone withdrawal | Explicit capability disable and PushKit token invalidation both emit the same invalidation event; Dart exposes `Stream<void>`. | The original trigger is lost before token/endpoint rollback. |
| Relay | Fixed-cardinality action/outcome/wake counters and selected failure/cancel/revoke logs are live. | No per-attempt join; successful actions and endpoint-not-found results can be indistinguishable in the log history. Response-write failure is separate from backend success. |
| TURN | Credential issuance counters and client connection fields exist. | Minted credentials do not prove the response arrived, an allocation succeeded, or media flowed. Coturn has no shared attempt reference today. |

Existing terminal history includes contact/call identifiers and is not an acceptable raw diagnostic export. Reuse safe projections and typed observers; do not enable all debug logging or repurpose the replaceable E2E sink.

## 1. Start a diagnostic attempt before preflight

Create a fresh cryptographically random diagnostic trace reference at the first Call action, before permission, availability or authority checks. It is separate from protocol call/message handles, account/device identifiers, and native call UUIDs. Each deliberate retry gets a new attempt reference; internal retries retain the original attempt and increment a retry ordinal. Suppressed duplicate taps get an event linked to the active attempt rather than starting another call.

Propagate that reference to both apps and the relay through explicitly supported diagnostic fields. The receiver's native push path must be able to persist its reference before Flutter runs. Strict current v1 call-control and TURN decoders reject unknown fields. Use a capability-negotiated v2 diagnostic envelope while preserving existing v1 request/response bodies and fallback; receiver signaling/push codecs need equally explicit compatibility handling. Verify mixed-version behavior. Never append a field to existing strict messages and assume compatibility.

Diagnostics must never be an admission requirement. Older peers continue calling; their trace is labeled partial/legacy rather than failed. A reference never authorizes a call or access to another user's diagnostics. The relay validates format, size and ownership bindings, and treats client-provided reasons as reported annotations, separate from server-observed outcomes.

## 2. Record explicit milestones on both phones

| Stage | Required events and bounded results |
| --- | --- |
| Call action | Attempt started; source UI/native action; foreground/background; app/build and schema versions. |
| Preflight | Microphone/platform capability/graph checks; endpoint lookup result; token/grant/receipt validation result; exact fixed failure code and elapsed time. |
| Signaling | Direct send started/result; mailbox request/result; receipt parsing; incoming validation accepted/rejected with fixed reason. Direct and mailbox legs stay distinct. |
| Native incoming UI | Push received; parser result; platform presentation requested/result; action timeout or provider reset. API success is labeled presentation accepted, not proof of audible ringing or that the user saw it. |
| Answer | Action origin; native answer requested; native journal commit/refusal; Dart adoption; native audio activation result. |
| Media | TURN request/result; selected transport class; ICE/DTLS/structural readiness; first inbound/outbound RTP; bounded progress/stall observations. No addresses, candidates, SDP or raw statistics. |
| End | Terminal origin/reason; last completed stage; media evidence; requested and completed cleanup steps; surviving-resource counts. |

Cancellation must identify its origin: user action, remote terminal signal, timeout, authority invalidation, graph replacement/shutdown, audio failure, or another fixed reason. A server Cancel alone must not be presented as a human action.

Use existing typed state, engine, history-diagnostic and route projections. Add dedicated attempt outcomes for preflight; do not require a canonical session to exist before recording a failure.

## 3. Preserve the cause of every registration change

Give each publish/refresh/revoke action its own random operation reference and parent-operation reference. Preserve a closed origin enum from the native callback through Dart and the relay request. Examples include `pushkit_token_invalidated`, `calls_disabled`, `permission_revoked`, `native_token_updated`, `resume_refresh`, `logout`, `account_changed`, `graph_replaced`, `native_snapshot_invalid`, `authority_rejected`, and `token_rotation_cleanup`.

Record each requested/committed/failed native, token and endpoint operation, plus current call-state class and whether graph ownership matched. `graph_shutdown` is an intermediate step, not a sufficient originating reason.

Link an operation to an attempt only when the application actually knows that relationship. Do not attach withdrawals to the nearest call by timestamp. For a failed endpoint lookup, the relay can internally connect the lookup trace to its last recorded registration-change reference using its existing private authority keys. Those keys/identities must not appear in diagnostic output or be exposed as a new lookup capability. Keep diagnostic references advisory and outside authorization decisions.

This would answer the missing question from calls 099–101: what initiated the iPhone withdrawal, which operation reached the relay, and which attempts were affected.

## 4. Separate relay phases and outcomes

Emit structured records for request received/validated, authority lookup found/not-found/rejected, backend commit, response write, and terminal cleanup. Carry the diagnostic trace and a request/span reference in restricted records. Store, retrieve, ACK, cancel and expire remain separate operations; a successful Store or ACK is never labeled a successful call.

This phase separation is essential: `CallControlService.Store` can commit the mailbox and then return an error from wake claim/authorization/completion. A generic request error would otherwise falsely suggest that nothing was stored. Record the commit before wake processing and report request completion separately. Likewise, report `not_found_or_expired` when retained authority evidence cannot distinguish those cases. Successful empty polling stays silent.

For push, record reservation/authorization, actual provider entry, provider result, retry/cross-environment ordinal, and suppression/skip reason. `wake completed` remains bookkeeping. For TURN credentials, record request, mint result and response-write result separately; the existing issued/write-error counters can describe two phases of one request rather than two attempts.

Record relay build/deployment revision at trace start. Keep aggregate metrics limited to bounded stage, reason, platform, direction and outcome labels; never put trace references into Prometheus labels.

Initially, correlate TURN credential requests and the clients' selected transport/ICE/RTP observations. Coturn allocation outcomes remain aggregate unless a separate, verified adapter maps an allocation to a dedicated non-secret diagnostic reference. Any such adapter must redact raw usernames/credentials and addresses before storage. Do not promise per-call coturn attribution by merely enabling verbose logs.

## 5. Keep durable records and deliver them without blocking calls

Add a separate protected diagnostic spool in Flutter and each native platform. The native spool must initialize before Flutter. Do not expand or reuse the canonical 32-event/8-KiB replay journal as a diagnostic archive.

Proposed beta defaults:

- Opt-in beta diagnostics: record and upload 100% of bounded attempt milestones and summaries, including successful attempts and preflight failures. Upload automatically while connectivity and OS execution permit; retain an offline queue otherwise.
- Local bounds: seven days, the latest 100 attempts, or 5 MiB, whichever limit is reached first. Cap a single attempt at 256 diagnostic events / 64 KiB, aggregate repeated stages, and preserve the terminal summary separately. Record truncation/drop counts rather than silently implying completeness.
- Server retention: fourteen days in a dedicated durable diagnostic store with a total quota and restricted access. Do not rely on expiring call mailboxes or Redis AOF history as the archive.
- Upload acknowledgements, deduplication and bounded exponential retry. Upload/storage errors cannot change call admission, delay PushKit completion, prevent cleanup, or block the user interface.
- Persist start and terminal markers. On restart, an unfinished attempt becomes `interrupted_before_final_record`; do not guess crash versus force quit without OS evidence.

Store per-source sequence, UTC time, monotonic elapsed time, and server receipt time. Align cross-phone events using causal references and request bounds; do not assume phone clocks agree. Preserve both original occurrence and later upload times.

Real-time visibility is best effort while online; offline or OS-suspended devices can report later. Missing telemetry must remain visible as missing rather than being silently counted as success or failure.

## 6. Define success and failure honestly

Maintain separate dimensions for setup result, media evidence, terminal reason and trace completeness.

- `media_flow_verified`: accepted session, native audio active, structural connection ready, and inbound/outbound RTP counters increasing across bounded observations. Record whether one or both endpoints confirm this. It proves packet flow, not subjective sound quality.
- `answered_without_verified_media`: acceptance occurred, but the evidence never established media flow. Distinguish an intentional very short call from a timeout or technical failure.
- `completed_after_media` versus `dropped_after_media`: use explicit terminal origin/reason after media evidence.
- `declined`, `busy`, `caller_canceled`, and `no_answer`: intentional or unanswered outcomes reported separately from technical failures.
- `preflight_failed`, `signaling_failed`, `native_answer_failed`, `media_failed`: include the failed stage and fixed code.
- `interrupted_unknown`, `partial_legacy`, or `missing_endpoint_report`: incomplete evidence, not invented media verdicts.

Do not treat silence or mute as evidence of a broken call. Sample media counters sparsely and retain only approved progress/stall summaries, not audio or arbitrary WebRTC stats.

## 7. Make the records usable

Provide one support trace code and an operator lookup that combines caller, relay and callee events into an ordered timeline. Show the first failed/incomplete stage, underlying reason, registration-operation chain, native presentation/answer evidence, media evidence, cleanup, and telemetry completeness. Preserve source labels so a client-reported outcome cannot be confused with a server-observed fact.

Add aggregate views and alerts for preflight rejection, technical setup failure, answered-without-media, drops after media, native registration withdrawals by origin, provider failures, credential failures, telemetry loss, and cleanup failures. Keep deliberate declines/cancellations separate from the technical failure rate. Show counts/denominators and minimum sample thresholds so a small beta cohort does not create misleading percentage alerts.

## Privacy and compatibility contract

Existing proposed diagnostic policy forbids raw peer/contact/device identifiers, call/message/opaque handles, SDP/candidates/IPs, tokens/credentials/ciphertext, and audio. Keep those forbidden. Do not print arbitrary exception strings or export user call-history rows.

A dedicated random diagnostic reference is a new, explicitly allowlisted correlation field in a restricted, opt-in trace. It must not reuse or hash a protocol handle as a shortcut. Update the diagnostic privacy contract and tests to define its scope, access and expiry. Public operational logs and aggregate metrics remain identifier-free. Support export remains bounded, previewable and redacted; automatic beta telemetry needs a clear opt-in with the data categories and retention shown.

## Acceptance checks before relying on this

Use deterministic failures plus available lab devices to establish that the trace alone distinguishes:

1. Permission denial and unavailable authority before any relay call exists.
2. Store committed but wake processing or response delivery failed; direct success with mailbox failure.
3. Provider accepted push versus native presentation refusal versus user no-answer.
4. Native answer persistence/refusal versus Dart acceptance versus audio activation failure.
5. TURN credential error, ICE failure, and connected-without-RTP.
6. PushKit invalidation versus explicit calls-disabled withdrawal, with the complete native-to-relay operation chain.
7. User cancellation versus automatic cleanup, including late work from a replaced graph.
8. Success, decline, retry, and clean termination in both supported directions.
9. App restart/offline upload, reordered/duplicate batches, quota exhaustion and missing endpoint telemetry.
10. Mixed old/new protocol peers, disabled diagnostics, redaction, and failure of every diagnostic sink without affecting call behavior.

Implement server compatibility and durable ingestion first, then app/native instrumentation and the beta build. Validate the joined traces on the available lab matrix before relying on telemetry from consenting beta testers. This adds evidence for future incidents; it cannot reconstruct encrypted reasons already lost from the earlier twelve calls.
