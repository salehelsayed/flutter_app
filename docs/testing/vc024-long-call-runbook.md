# VC-024 long-call verification

Threshold proposal approved by Kayan in m-0772a038 on 2026-11-01, following
m-2b7002a1. This is an execution packet, not a device PASS or release approval.
The earlier phone campaign's owner-N/A soak result remains historical.

## Ownership and prerequisites

flutter_app owns all device execution. Use the project's available-target policy
and existing Appium MCP/call campaign setup; discover and pin targets at execution.
Use available Android physical + emulator by default, with a separate available
iOS leg for CallKit/native cleanup claims. Do not require absent hardware.
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
3. At each checkpoint, exchange controlled unmuted speech in both directions.
   Observe advancing inbound/outbound RTP with the existing sampler, plus an
   actual received-audio oracle or authorized human listening. An initial
   nonzero counter, stale/reset counters, local playback or RTP alone is not
   audible-content proof. If the received-content oracle is unavailable, mark
   it incomplete explicitly. Do not manufacture a PASS from a mute/silence gap.
4. Exercise mute/unmute and available output routes mid-call. Verify the chosen
   route and resumed two-way audio. Only available accessories are required.
   Preserve the same call and connected timestamp. Do not inject an outage
   longer than the existing reconnect deadline into this duration soak.
5. At minute 30, RSS must be <= max(1.20 * minute-5 RSS, minute-5 RSS + 30 MiB).
   This is an approved investigation threshold, not a universal leak detector.
   Keep intermediate samples to diagnose monotonic growth and unrelated work.
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
   scale. Mark inconclusive if unrelated workload dominates. Record battery
   and thermal changes; no universal battery percentage or in-call CPU cutoff
   has been established. Thermal escalation requires diagnosis, not automatic
   attribution to Mknoon.

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
