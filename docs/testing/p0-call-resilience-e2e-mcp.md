# Remaining P0 call journeys: MCP execution packet

Prepared 2026-10-26 against `1154b9d47eb94b0f5e777817113e5ad5f28fb99d`.
Scope, in catalog order: VC-016, VC-017, VC-018, VC-020, VC-022, VC-009 and
VC-010. Other named calls already have reviewed tests and are reused. Execution
belongs to flutter_app; Astra performed no device test. This packet adds no app
fault hook, generic UI driver or boolean-only verdict. The priority Python
receipt checker does not implement these seven cases.

## Setup, ownership and existing evidence

Follow `docs/testing/TESTING.md` and `tool/testing/selection.json` setup/recovery
rules. The execution owner resolves available targets and pins exact artifacts,
packages, source/configuration, actor roles and leases. Shared cases default to
USB Android plus emulator; an available third owned actor is needed only for
the unrelated concurrent-caller leg. VC-009/010 are explicit iOS OS boundaries
on an available physical iPhone, with an available Android peer where needed.
Unavailable hardware is N/A for that leg; missing artifact/access/observations
on an available target remain incomplete. Do not require an absent OS/model.

Actual calls start at or after **08:30 CET**, with the test date's timezone-aware
Europe/Berlin timestamp retained. Host fixtures do not make phone calls. Use
one test process, defer heavy checks above one-minute host load 80, and preserve
first failures and original deadlines. Restore only the run's owned state.

Remote test relay is Hetzner; owned local relay/coturn fixtures are allowed.
Verify the actual binding before traffic, with no AWS default/fallback or remote
service change. If a signed artifact cannot use the permitted test binding,
report that artifact/setup gap. A source/debug substitute does not certify it.
No device credentials, passcode changes or personal account resets belong here.

Reuse `call-privacy-recovery-e2e-mcp.md` for the existing `device-audio` adapter,
its local attested fixture/manual hold, host controls and native cleanup. Its
manual-only mode prepares builds/backend, not ready accounts or a device PASS.
End the owner's Appium MCP session before an instrumented campaign takes its
targets; resume only after campaign cleanup. Use actual Appium MCP tools for
ordinary UI and OS interaction. Use an existing adapter only for its documented
native/process/protocol observation, not as a second generic UI driver.

Bind actual call identities, generations, native owner snapshots, history,
timestamps and raw UI/audio evidence privately. Working-audio claims need real
received content or an attested audible observation with native evidence and
positive controls; RTP progress, a timer and the separate host Pion oracle are
not interchangeable. Mail only paths/redacted facts. A missing observation stays
incomplete, even when supporting host or normal-campaign results pass.

## VC-016: terminal branches, overlaps and the next call

Reuse `test/features/call/application/call_race_convergence_test.dart`,
`call_coordinator_test.dart` and `headless_call_decline_reply_test.dart` in that
directory, plus `test/features/call/integration/call_direct_mailbox_convergence_test.dart`
and `integration_test/call_control_signaling_e2e_test.dart`. These preserve
specific causal/reducer/signaling boundaries, not an actual unattended phone.
VC-002's KX0001 observes encoded timing and scheduling, not actual expiry.

Use a fresh call per row; reverse caller/callee where relevant:

| Actual trigger | Required observation |
| --- | --- |
| Callee declines ringing call | Correct current call terminates at both ends, ring/card/capture ownership retires, supported history is retained. |
| Caller cancels before answer | No later answer or queued invite revives that call; no pre-consent capture, both surfaces retire. |
| Online peer never answers | Let the original scheduled no-answer/expiry fire; no manual cancellation substitutes for it. |
| Eligible peer actually offline | Retain authenticated outgoing admission and actual peer state, then observe the applicable original timeout and cleanup; a local admission refusal is a different branch. |
| Crossed outgoing calls between A/B | Prove actual overlap and use the current deterministic glare contract; neither endpoint owns two live calls or a ghost ring. |
| Third C calls A during an established A/B call | Observe busy/refusal without replacing A/B, stealing its audio or rewriting its current history. |

Current defaults in `lib/features/call/domain/call_state.dart:110-113` are
30 seconds for no-answer and 15 seconds for reconnect. Bind the actual candidate
policy and timer origin; `call_coordinator.dart:681-738` separately anchors
authenticated invite expiry. Do not start every timeout at an arbitrary tap.
For glare, use the source's call-ID ordering and current ownership rules
(`call_race_convergence_test.dart:249`); invent no account-first winner rule.
If taps do not produce an actual overlapping interval, report an unexercised
crossed-call leg rather than infer it from two ordinary calls.

After each terminal row, reopen its history and place an answered fresh call
with positive working audio and normal cleanup. Retain old/new identity fencing.
Late terminal/answer/replay control uses existing exact-call host/native support;
if a real queued order cannot be staged, keep that causal host proof separate
and mark the native injection incomplete. Never fabricate a notification or
database terminal. Use the actual closed `call_end_reason.dart` history grammar,
not one invented UI label per internal reason. A missing third actor makes only
that topology leg N/A, not the whole entry.

## VC-017: selected media-path interruption and bounded recovery

Reuse `test/features/call/integration/call_turn_policy_test.dart`,
`call_readiness_exception_test.dart` and `call_engine_event_delivery_test.dart`
in that directory, plus
`test/features/call/application/call_network_path_binding_test.dart` and
`test/features/call/domain/call_linger_audio_recovery_test.dart`. Their supplied
native readiness/events cannot stand in for actual link loss.

1. Establish actual bidirectional audio and record the current call, selected
   candidate/transport and admission-frozen route policy. Disrupt the **actual
   selected media path** through an existing owned-emulator network operation
   or owned local fixture. Merely stopping libp2p signaling need not stop an
   established WebRTC media path. A network icon or missing log is insufficient.
2. For the recovery row, observe actual native loss and the canonical recovery
   episode, then restore before its original deadline. Prove ready media and
   working audio on that same current call. Bind generation/ownership and show
   an old observation cannot satisfy a new episode. Do not change the privacy
   preference mid-call or claim an inactive future DCUtR feature.
3. On a fresh call, keep the path unavailable through the original recovery
   deadline. Observe terminal cleanup/history and release at both ends. The
   default 15 seconds begins at the actual reconnect episode, not necessarily
   when the network was cut; preserve the observed native detection interval.
   Do not extend/reset the deadline because the UI still says recovering.
4. Restore only owned network state after terminal. Late old media/signaling
   cannot revive the call or release a successor's audio. Place a fresh call,
   prove audio and cleanup. Keep first short/long-outage failures separately.

If an existing profile cannot establish a selected-path cut or its native event,
the corresponding native row is incomplete. Do not add a production loss hook,
stop a shared relay or convert a host-supplied `mediaLost` into a device result.

## VC-018: real OS audio interruption and source-defined recovery

Reuse `test/features/call/application/call_audio_interruption_coordinator_test.dart`,
`call_audio_controller_test.dart` in that directory and
`test/features/call/infrastructure/call_media_conflict_adapter_test.dart`.
The coordinator at
`lib/features/call/application/call_audio_interruption_coordinator.dart:45-124`
invalidates stale readiness and recovers only the current call/phase/generation
when media is ready, under the original episode deadline.

1. Start with positive real audio and record mute state. Use an actually
   available, owned OS interruption/foreground audio-focus challenger and
   observe its real native event. A real cellular interruption is a separate
   leg only if a suitable target/trigger exists. Calling a fake Dart callback
   or simply backgrounding the app does not establish audio-focus loss.
2. Observe the source-supported pause/reconnect or terminal behavior for that
   event, with exclusive capture/route ownership. Restore focus, prove native
   media readiness and actual audio recovery on the same current call, or its
   honest terminal outcome. A focus-return event alone cannot mean connected.
3. Repeat while muted: interruption/return must preserve mute and received-
   content privacy, using VC-019's negative observations and positive controls.
   An active voice-note recording which the source finalizes before call
   capture must not restart automatically afterward; microphone owners remain
   exclusive (`call_media_conflict_adapter.dart:6-8`).
4. End/replace the interrupted call before a delayed recovery completes where
   existing controls can stage it. Old recovery cannot unmute/reacquire/retire
   the new owner. Keep exact asynchronous races covered by the existing causal
   host tests when the OS timing cannot be established; label native scope.

Do not create a new focus harness or stop a foreign audio owner. Unsupported or
unavailable event/topology legs do not erase the applicable observed cases.

## VC-020: ordinary call admission and independent OS permissions

Reuse `test/core/bootstrap/call_signaling_composition_test.dart`,
`test/core/permissions/mic_permission_gateway_test.dart`,
`test/core/permissions/mic_permission_prompt_test.dart`,
`test/features/call/application/call_audio_controller_test.dart`,
`call_redial_controller_test.dart` in that directory and
`test/features/call/integration/call_mic_blocked_end_reason_test.dart`.
KX0008's notification callback is supporting evidence, not the normal entrypoint.

`lib/app/bootstrap/call_signaling_composition.dart:387-420` checks microphone
permission before capability publication and canonical start, then rechecks
graph ownership. Use the actual result/feedback rather than inventing a terminal
row for a preflight which never admitted a call.

1. Through ordinary Calls/conversation entrypoints, exercise unavailable
   identity/graph, ineligible or blocked contact, and busy state using owned
   fixtures. An unavailable entrypoint can be correct refusal. Observe actual
   feedback and no unauthorized new invite, native capture or replacement of
   the live call. Existing host fixtures cover authorities which normal UI
   cannot construct; never delete a personal identity to reach them.
2. Revoke microphone permission for the exact disposable app through the actual
   OS flow. Attempt a normal call, deny its prompt and inspect no new admitted
   call/capture or unauthorized invite. Keep denial and permanently-denied/
   settings behavior distinct when available. A media failure after a granted
   permission is a different branch, not proof of OS denial.
3. Grant through the supported OS/settings path, retry the same normal entrypoint
   and prove a fresh answered call with real audio and cleanup. Retain the
   actual permission-prompt lifecycle; a system dialog's `inactive` state is
   not cancellation by itself. A late grant after explicit cancellation or
   replacement must not start the old request; preserve the host causal race
   when that exact native order is not observable.
4. Independently deny notifications while microphone permission is granted.
   Read actual platform/channel/full-screen-access state and exercise the
   supported foreground call/fallback/feedback. Notification denial is not
   microphone denial, and ordinary iOS notification permission is not the
   PushKit/CallKit contract. Do not demand a suppressed OS card, assume a VoIP
   wake, or infer permission from a saved app boolean. Regrant/restore only
   owned settings and prove the supported call path remains usable.

Keep Android/iOS OS observations separate and preserve actual platform fallback.
Widget feedback and mocked permission adapters do not certify the real prompt.

## VC-022: rejected signaling cannot gain authority or break valid work

Use the existing hermetic negative fixtures, not forged traffic to a shared
remote service or a new app injection channel:

| Boundary | Existing causal source to reuse |
| --- | --- |
| Bad signature, malformed outer/inner shape, mismatched authority, expiry and replay | `test/features/call/infrastructure/secure_call_envelope_codec_test.dart` and `test/features/call/domain/call_signal_schema_test.dart` |
| Sender eligibility and wake/outer/inner mailbox binding before presentation | `test/features/call/application/incoming_call_pre_presentation_admission_test.dart` and `handle_incoming_call_signal_test.dart` in that directory |
| Active call, generation, terminal and valid continuation | `test/features/call/application/call_signaling_service_test.dart`, `call_race_convergence_test.dart`, and `test/features/call/integration/call_direct_mailbox_convergence_test.dart` |
| Authenticated relay control rejection and later valid custody | `go-relay-server/call_control_adversarial_test.go` |

For each exact source-defined adversarial case, retain the real decoder/admission
result, current session/history and native-port call counts. No unauthorized
ring/presentation/capture or live-call replacement may occur. Then process a
valid current signal in the **same** fixture/queue without resetting its owners
and show valid work still completes. Preserve current-call timers and a later
fresh call. Signature/native substitutes remain identified; host rejection
counts do not become physical microphone or native cryptography evidence.

Inventory presence alone does not prove the complete reject-then-valid sequence.
Map each required row to its actual existing assertions; any unasserted combined
order needs a targeted case in that existing fixture before whole-row closure.
Keep invalid expired/stale inputs bound to actual call/authority lifetime rather
than manufacture a new age, deduplication or eligibility policy.

For the additional real-app check, use owned peers and supported contact/call
controls to reach blocked/ineligible admission and a competing current call.
Observe absence of unauthorized native presentation/capture while the entitled
active call stays usable; after ordinary authorized restoration, a valid fresh
call must still work. A bad-signature native leg which no existing approved
adapter can stage remains incomplete. A fabricated push or manually dispatched
`ring` event bypasses the authority under test and cannot fill it.

## VC-009: actual iPhone background and return with working audio

Reuse the iOS lifecycle adapter/CallKit host suites and existing VC-015 signed-
audio procedure. KX0004 is a blocked placeholder, not an executable proof. Use
an available real iPhone and owned Android peer with the exact source/artifact
bindings; a simulator does not certify this physical iPhone row.

1. On fresh calls, let the iPhone initiate and answer in separate cases. Establish
   actual intelligible audio both ways and capture current canonical/native
   ownership before leaving the app.
2. Use actual iOS Home/app switching through MCP and record the background state.
   Keep the process alive. A back arrow inside Flutter, force-quit or process
   kill is a different boundary. While backgrounded, exchange fresh distinct
   cues both ways and retain real received-content/audible plus native evidence.
3. Return through the supported app/system call surface. Require the same current
   call/native owner, ongoing working audio and unchanged mute/route policy,
   with no automatic redial or second call. Structural RTP or duration progress
   alone is insufficient. Repeat the relevant role with its own evidence.
4. End from each endpoint on separate calls and inspect native/audio/card release
   and actual history. Use the current signed-audio artifact procedure for a
   release claim. This connected-call case does not certify the separate
   six-minute idle PushKit wake or every suspended/locked state in VC-014.

## VC-010: actual iOS system contact name and safe fallback

Reuse `ios/RunnerTests/OpaqueCallContactResolverTests.swift`,
`MknoonCallKitLifecycleTests.swift` in that directory and
`test/features/call/infrastructure/call_native_bridge_privacy_contract_test.dart`.
KX0018/19 remain blocked placeholders. The actual resolver is
`ios/Runner/OpaqueCallContactResolver.swift`: only an authenticated stored mapping
provides a display name; a valid unmapped handle resolves to **Mknoon call**.
Do not copy Android's native fallback or Flutter's **Unknown contact** here.
`ios/Runner/MknoonCallKitController.swift:1781-1808` uses a generic per-call handle;
its compliance/absent-handle update can intentionally have an empty display name.

1. With an actual accepted owned contact and current native mapping, deliver a
   real incoming call on the iPhone. Observe actual incoming and ongoing system
   surfaces in the available warm/cold/locked states appropriate to this row.
   Bind the shown name to the authenticated contact, not unsigned push text or
   an underlying Flutter conversation. Caller name/avatar is permitted call
   identity; private history/navigation remains under VC-025's lock protection.
2. Inspect visible text/accessibility and current native update for raw peer IDs,
   contact/transport keys or routing handles. The source-defined opaque per-call
   generic handle is not a peer ID; do not substitute a phone-number identity or
   require the same literal fallback for an empty compliance update.
3. Exercise missing/unreadable mapping through an existing approved owned fixture
   only when it preserves actual authenticated call authority. Observe the
   source-defined safe fallback, then a named-contact positive control. If the
   current signed profile cannot stage that mapping state, keep resolver host
   proof separate and mark the native fallback cell unrun/incomplete. Do not
   edit a personal contact/cache, invent an untrusted admitted caller or inject
   an arbitrary APNs payload to make a name appear.
4. End and inspect owned native/card/history cleanup. Preserve first name/handle
   disclosure witnesses privately and report only paths/redacted facts. A Swift
   string assertion or Android notification name cannot certify this iOS UI.

Each result retains exactly the cases, platform, artifact and observations
actually executed. Preparation, a supporting normal native report or causal
host suite does not certify an unobserved signed candidate or missing OS leg.
