# VC-024 long-call verification

Threshold proposal approved by Kayan in m-0772a038 on 2026-11-01, following
m-2b7002a1. This is an execution packet, not a device PASS or release approval.
The earlier phone campaign's owner-N/A soak result remains historical.

Kayan approved the in-call CPU growth criterion and scoped audio evidence on
2026-11-10 in `m-6af4d197`. That decision adds the matched-route CPU check below.
Physical speaker/earpiece output remains **NOT PROVEN**, without blocking this
scoped VC-024 verdict. The owner does no hands-on or listening steps.

## Ownership and prerequisites

flutter_app owns all device execution. Use the project's available-target policy
and existing Appium MCP/call campaign setup; discover and pin targets at execution.
Use available Android physical + emulator by default, with a separate available
iOS leg for AVAudioSession route/activity and CallKit/native cleanup claims.
Exercise earpiece and speaker on each available phone; Bluetooth is required
only when actually available. Do not require absent hardware. Keep iPhone 11 on
Wi-Fi, use the Pixel for cellular legs, and install over iPhone builds without
erasing their retained data.
Record exact source, signed/debug artifact and flags, endpoint roles, observer
clock and measurement method. Do not export identities, tokens or message/audio
content. Store redacted evidence in ignored run artifacts. Reuse existing tools;
do not build a new UI harness or telemetry service.

Use three eligible contacts/endpoints only for the second-different-contact leg.
If no third endpoint is available, preserve the two-peer soak result and mark
that distinct leg N/A under target policy. Never relabel a same-contact redial
as different-contact proof. Keep each first failure and do not silently rerun.

## Execution and acceptance

1. Observe five idle minutes. Record process RSS and CPU with the existing
   platform tooling, its units and sampling interval. Record thermal/battery
   where accessible. Stabilize unrelated workload and note charging state.
2. Start one audio call. Run for 30 minutes from canonical connected time.
   At start, 5, 15 and 30 minutes, assert the same call identity on both sides
   and displayed duration within two seconds of elapsed observer time.
3. At each checkpoint, use fresh Android two-way sampled decoded-content PCM
   probes plus advancing inbound/outbound RTP. Reuse the existing debug probe;
   retain exact call/engine ownership and processor-removal receipts from both
   endpoints. A prior successful probe, initial nonzero counter, stale/reset
   counter, local playback or RTP alone is insufficient. On iOS, record the
   adopted call's AVAudioSession route and active-session evidence. That proves
   OS session/route state, not received content or physical output; no equivalent
   iOS PCM producer is established by this packet. Report those limits rather
   than substituting owner listening. Physical speaker/earpiece output stays
   NOT PROVEN and is nonblocking under the November 10 decision. Deliberately
   muted intervals cannot satisfy a positive Android content check.
4. Exercise mute/unmute and available output routes mid-call. Verify the chosen
   route and resumed two-way audio. Only available accessories are required.
   Preserve the same call and connected timestamp. Do not inject an outage
   longer than the existing reconnect deadline into this duration soak.
5. At minute 30, RSS must be <= max(1.20 * minute-5 RSS, minute-5 RSS + 30 MiB).
   This is an approved investigation threshold, not a universal leak detector.
   Keep intermediate samples to diagnose monotonic growth and unrelated work.

   For each earpiece/speaker route, the 60-second late CPU median must be
   <= max(1.20 * its matched warm median, warm median + 5 percentage points).
   This is the additional November 10 investigation bound. Use the same PID,
   process-start identity, route, screen/workload and CPU scale. Derive
   `100 * delta(process CPU seconds) / delta(monotonic seconds)`: 100% is one
   core, not the whole device. Declare windows before the run; do not choose
   whichever later window passes. One usable schedule is earpiece at minutes
   4–5 and 29–30, speaker at 6–7 and 31–32, extending the call to 32 minutes.
   RSS comparison remains at minutes 5 and 30. Save raw samples and units;
   missing windows, process replacement, PSS substituted for RSS, or mismatched
   CPU scales leave resource proof incomplete.
6. End the call. Within 60 seconds assert no owned native call, microphone/media
   track, foreground call service, proximity lock or ongoing call-stat sampling.
   Both sides must have one truthful terminal history row. Waiting for the
   Android six-hour proximity safety timeout does not establish cleanup.
7. Immediately place a fresh call to a different eligible contact. Require
   admission, connection, two-way audio and clean end. Preserve the first
   attempt if it reports unavailable; attach only redacted preflight/authority
   and native-cleanup diagnostics to the report.
8. Observe five post-call minutes. CPU recovery: a 60-second median after end
   within five percentage points of idle baseline on the same measurement
   scale. Use the final 60 seconds of the five idle baseline minutes and the
   final 60 seconds of the five post-call idle minutes, selected before the run.
   Start the post interval after owned cleanup and any different-contact recovery
   call; retain its actual monotonic start. Mark inconclusive if unrelated
   workload dominates. Record battery and thermal changes; no universal battery
   budget or absolute in-call CPU ceiling has been established. The matched-route
   growth bound above is a separate gate. Thermal escalation requires diagnosis,
   not automatic attribution to Mknoon.

## Host proof and its limits

The VC-024 cases in `call_coordinator_test.dart` use a real coordinator/reducer,
injected clock/timers, fake effects and in-memory history. They check a virtual
30-minute call with recovery episodes, bounded active timers, terminal cleanup
acknowledgement, history duration and a new contact's call surviving stale old
callbacks. They do not exercise endpoint resolution, native resources or real
elapsed load. In particular they cannot close the owner-reported contact-B
availability incident by themselves.

The VC-024 case in `call_screens_test.dart` verifies duration across remount and
reconnecting presentation. Widget disposal assertions and Flutter's pending-timer
checks are host UI checks, not native timer or wake-lock measurements.
`call_rtp_progress_sampler_test.dart` preserves the negative oracles for stagnant,
one-way, reset, missing and video-only counters. It is not received-audio proof.

Report each host and device leg separately with command, result, evidence path
and exact remaining step. The approved RSS/CPU thresholds are not measured by
these host tests. Do not claim a signed production soak from virtual time.

## Saved resource measurements

`run_call_audio_soak.dart` can evaluate retained resource files without operating
a device. Collect actual measurements with existing platform tools; the command
does not supply a collector, attest that cleanup happened, or authenticate the
device origin of submitted data. Its host fixtures are synthetic.

```sh
dart run integration_test/scripts/run_call_audio_soak.dart \
  --assert-resource-evidence "$VC_RESOURCE_RECEIPT" \
  --source "$CANDIDATE_SHA" --run-id "$VC_RUN_ID"
```

Use the existing `mknoon.production-journey-gap.v1` envelope with `journeyId`
`VC-024`, `executionStatus` `complete`, a full `candidateSource`, `runId`, and
distinct pinned `targets` with device and artifact identities. List each raw
resource file in `evidence` with its relative path, SHA-256 and kind
`call-resource-samples`. Set `observations.canonicalCallId` and map every target
role to its file in `observations.resourceFiles`. The resource test's `_receipt`
and `_samples` fixtures show the format; their fake identities and measurements
must never be submitted as device evidence.

Each raw JSON file uses these fields:

| Fields | Required observation |
| --- | --- |
| `schema`, `candidateSource`, `runId`, `role`, `deviceId`, `artifactSha256` | Schema `mknoon.call-resource-samples.v1` and exact envelope bindings. |
| `executionKind`, `clockType`, `clockId` | `device-monotonic`, `monotonic`, and the actual observer clock identity. |
| `pid`, `processStartId`, `canonicalCallId`, `connectedAtMs`, `endedAtMs` | One process and canonical call, with monotonic millisecond timestamps. |
| `memoryMetric`, `memoryUnit`, `cpuCounterUnit` | `rss`, `bytes`, and cumulative process CPU `seconds`. |
| `windowPlanDeclaredAtMs`, `postObservationPolicy`, `postObservationStartMs` | Declare before connection; use `first-five-idle-minutes-after-owned-recovery` and retain the actual post-cleanup/recovery idle start. |
| `inCallCpuWindows` | One entry per `earpiece`/`speaker`, with absolute monotonic `warmStartMs` and `lateStartMs`. Each window lasts 60 seconds. |
| `samples` | Each row contains `atMs`, `pid`, `processStartId`, `processCpuSeconds`, `rssBytes`, `canonicalCallId`, `connectedAtMs` and observed `route`; idle rows have no active call. |

Sample nominally every 10 seconds. The checker rejects gaps above 15 seconds,
counter resets, process changes and incomplete idle/post periods. It uses the
first RSS observation at or after minute 5/30 within 15 seconds and reports the
actual sample times. CPU medians are weighted by observed interval duration;
route windows require confirming route observations at both ends of every
interval. Warm windows must fit within minutes 4–8 and late windows begin no
earlier than minute 29. The schedule above satisfies both routes.

Passing saved resources produce `resourceCriteria: PASS_RECORDED` while overall
`status` and `fullSoakStatus` remain `NOT RUN`, with expected exit code **78**.
Invalid or failing resources produce `FAIL_RECORDED` and exit **1**. No arguments
still report `BLOCKED`/78; `--list-scenarios` remains discovery only. Keep the
separate Android PCM, iOS OS-session/route, cleanup, history and recovery evidence
beside this resource result. Physical output remains `NOT PROVEN`.
