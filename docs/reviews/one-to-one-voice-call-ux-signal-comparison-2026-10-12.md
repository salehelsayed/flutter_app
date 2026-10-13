# One-to-one voice calls: Signal versus Mknoon from the user's perspective

Reviewed 12 October 2026. This covers one-to-one voice-call use, not group calls, video-call functionality or protocol design. Source-backed behavior is distinguished from real-device evidence. No device campaign was run.

## What is actually missing or different?

The strongest differences are delayed missed-call recovery, in-app multitasking, linked-device ringing, call browsing/redial, audio-device selection, low-data controls and optional system-call-log integration. Mknoon already implements many essentials: ringing feedback, incoming/cancel/decline/busy flows, missed-call cards and chat history, background native actions, mute/speaker, duration, reconnection, privacy preferences and accessibility semantics. These should not be placed on a missing-feature backlog just because Signal also has them.

**Evidence labels:** **Confirmed** means source directly establishes the UI/policy; **inference** means the user consequence follows under stated conditions; **not found** means the inspected call/UI/settings owners contain no equivalent, not proof of absence in an installed binary; **runtime** means hardware/OS/network behavior must be tested. This report is broad across the call journey, not an assertion that every OS version, accessory or failure permutation has been exercised.

## Your offline-recipient example

**Scenario:** Alice calls Bob. Bob's phone has no network for several minutes. Alice gives up. Bob then reconnects.

- **Signal:** a delayed offer can be processed as a **missed voice call**, rather than ringing an old call. Both pinned clients explicitly turn an expired offer into missed-call history. Signal's support also lists being offline as a reason for seeing a missed call. Delivery/retention, registration and notification permissions still matter; this is not a promise that every offline call will be reported forever. [Android expired offer][signal-a-expired], [iOS expired offer][signal-i-expired], [Signal calling support](https://support.signal.org/hc/en-us/articles/360007060672-Troubleshooting-Calling).
- **Mknoon:** the recipient can get a missed-call row/card **if an authenticated invite or terminal event reaches local call handling**. Its killed-app recorder can even construct the history from the terminal alone. However, the relay filters expired events and the codec rejects stale envelopes; there is no long-lived missed-call catch-up event in the traced call path. If Bob stays offline until all those events expire, the normal recovery path has nothing left to turn into a missed-call entry. **Inference: Bob may reconnect and have no record that Alice tried.** This does not mean Mknoon never shows missed calls. [expired event filtering][expiry], [decode rejection][decode], [headless history][headless-history], [missed notifier][missed].

The default invitation lifetime and maximum pre-connect mailbox window are 45 seconds; ringing/no-answer timeout defaults to 30 seconds. A later terminal signal has its own expiry, so **45 seconds after the first tap is not a universal deadline for every call artifact**. [call policy][life], [relay maximum][max-expiry]. Reconnecting while the invitation remains valid and the caller is still calling is a separate live-call scenario.

**Product improvement:** preserve the short lifetime of an actionable invitation, and add a separately authenticated, deduplicated, non-ringing missed-call outcome to an existing durable encrypted delivery owner. An hours-old missed-call entry must never be treated as permission to ring or answer an old call. Retention and metadata/notification privacy need explicit product decisions.

## Confirmed and strongly supported gaps

| ID | User scenario | Signal experience | Mknoon experience | Verdict |
|---|---|---|---|---|
| G1 | Recipient returns after being offline for minutes/hours | Can see a missed-call entry from a delayed/expired offer. | A call received before expiry can be recorded, including in headless handling; an entirely offline recipient can miss all expiring call events. | **Strong inferred gap:** no equivalent durable catch-up outcome found. Sources above. |
| G2 | While talking, open chat to read a message or send an address | Call view can minimize, leaving a return-to-call control. [minimize][signal-minimize], [return][signal-return] | Active call is a full-screen modal overlay, blocks underlying interaction and does not expose an in-app minimize control. Android Back backgrounds the whole app; it does not open the chat underneath. [overlay][overlay], [Back behavior][back] | **Confirmed gap:** in-app multitasking. Calling can still continue while using another app. |
| G3 | Phone is offline but another linked device is online | Ring multiple linked devices; answer on a reachable device. [multi-device design](https://signal.org/blog/ice-forking/) | Resolves one authorized endpoint rather than a broadcast-to-every-device call. [endpoint][endpoint] | **Confirmed design difference:** no equivalent simultaneous ringing flow. Desktop delivery was not audited in Mknoon. |
| G4 | Answer on one device and stop the others ringing | Other devices receive answered/declined-elsewhere outcomes. [Signal call states][signal-i-expired], [sync handling][signal-sync] | No multi-device ringing/answered-elsewhere experience in the traced single-endpoint flow. | **Consequence of G3**, not a second independent implementation project. |
| G5 | Find all recent or missed calls without remembering the contact | Dedicated searchable Calls list; Android has All/Missed filters. [Android list][signal-a-log], [iOS list][signal-i-log] | Call entries live in each chat and feed Orbit activity/unread information. No dedicated global Calls page was found. [history][history], [Orbit activity][orbit] | **UI gap found:** history exists, but centralized browsing is absent in inspected surfaces. |
| G6 | Tap a previous call to call back | Call-list actions can start another call. [Android list][signal-a-log] | Chat call row is display-only, with no tap/callback handler. The user can use the conversation's normal call control instead. [row][call-row], [row placement][chat-row] | **Confirmed gap:** direct redial from that row. |
| G7 | Call back straight from the missed-call notification | Platform-specific missed-call actions vary; not certified here. | Notification carries a contact route, but no dedicated Call back action is configured. [notification][notification], [details][notification-details] | **Confirmed Mknoon omission; Signal parity needs a platform check.** Do not present this as a proven all-platform Signal advantage. |
| G8 | Pick between speaker, phone and named Bluetooth devices | Android supplies an explicit audio-output picker, including device choices on supported APIs. [picker][signal-picker] | Own call screen shows current output and Mute/Speaker/End; it has no device-choice list. OS routing and automatic Bluetooth/wired routing can still work. [controls][controls] | **Confirmed Android own-screen UX gap.** Do not claim Bluetooth itself is unsupported. |
| G9 | Save mobile data or improve a congested connection | User can select less-data calling for cellular only or all networks. [data settings](https://support.signal.org/hc/en-us/articles/360056044831-Data-Usage-Options-Wi-Fi-Cellular) | No equivalent low-data call setting or explicit user-selectable mode was found in call/settings owners. | **Feature gap found**, not a claim that Mknoon lacks WebRTC adaptation. |
| G10 | Find a Signal call in iPhone Phone → Recents, or redial there | Can opt into system call-log integration. [CallKit configuration][signal-recents] | Production CallKit configuration sets `includesCallsInRecents = false`; history stays in Mknoon. Android self-managed calling similarly does not create a normal system call log. [iOS configuration][ios-recents], [native-log explanation][missed] | **Confirmed difference**, potentially intentional for privacy. Offer an explicit opt-in only if requirements allow it. |
| G11 | Recognize a caller by a custom ringtone/vibration | Android has per-recipient call sound and vibration controls; iOS CallKit can inherit a system contact's ringtone. [Android settings][signal-sound], [iOS configuration][signal-recents] | No equivalent per-contact call customization UI was found. Android system channel preferences are separate and may permit app-level customization. | **Customization gap found**, platform-qualified. |
| G12 | Turn on Always relay calls to hide the IP address from the other participant | Signal's relay option obscures peer IPs; signaling goes through its service. [relay explanation](https://signal.org/blog/signal-is-expensive/) | Preference forces relayed **audio**. Direct call signaling still races the mailbox and can expose an address; the setting description explicitly says so. [preference][privacy], [direct transport][direct], [user copy][copy] | **Confirmed limitation:** the setting is not a complete peer-IP-hiding mode. Actual exposure depends on the selected signaling route. |
| G13 | Browse identical call outcomes on linked devices | Dedicated linked-device call-event synchronization exists. [sync handling][signal-sync] | Local history/projector plus single-endpoint calling; equivalent account-wide call-history convergence was not established. [history][history], [endpoint][endpoint] | **No equivalent proven.** Requires a product decision and device evidence before promising sync. |

## Already present: do not call these missing

| ID | User scenario | What Mknoon already provides | Comparison/qualification |
|---|---|---|---|
| P1 | Start a call | Contact/capability checks and outgoing Connecting state, with Cancel. [endpoint][endpoint], [state copy][states-copy] | Signal also has calling/connecting states. Neither app can complete a call while the required parties remain unreachable. |
| P2 | Know whether the recipient is actually ringing | Authenticated remote ringing changes the caller state and starts ringback. Provider acceptance alone does not. Headless/native presentation has a wired ringing reply. [state owner][life], [ringback][ringback], [headless reply][headless-ring], [wiring][headless-wiring] | Similar intended UX. Native ring/silent mode and network-return timing need measurement. A stale comment claiming headless never signals must not override the implemented reply. |
| P3 | Let a call ring without answering | Default no-answer timeout; caller history says no answer, incoming history can say missed. [policy][life], [history mapping][history] | Exists. Exact timing differs and defaults may be overridden. No arbitrary Signal timeout number is claimed. |
| P4 | Caller cancels before answer | Cancel/terminate handling and incoming cancelled history mapped to a missed-call notification. [headless terminal][headless-history], [notifier][missed] | Exists if terminal handling reaches the recipient. It does not solve G1's extended-offline retention gap. |
| P5 | Decline a call | Decline signaling and distinct history. Deliberately declined incoming calls do not create a missed-call notification. [history][history], [notifier][missed] | Exists; missed and declined are different outcomes. |
| P6 | Another person calls while already in a call | Busy response/handling exists. [busy handling][busy] | Signal also handles active-call offers as busy/missed. [Signal active-call case][signal-busy] Neither source review proves a two-call hold/switch experience. |
| P7 | Miss a call while the app is closed | Native/headless terminal recorder writes local history and awaits the missed-call card; ordinary foreground composition also posts cards after durable history. [headless recorder][headless-history], [notifier][missed] | Exists. Actual killed/locked/OEM behavior must be tested; OS notification permissions can still suppress presentation. |
| P8 | Phone locked or app backgrounded | iOS PushKit/CallKit, Android incoming notification actions and locked-call presentation. [iOS wake][ios-wake], [Android actions][android-ui], [locked controls][android-locked] | Exists, not necessarily identical on every OS/OEM. Full-screen permission is a separate Android prerequisite. |
| P9 | Lock-screen call did not light the screen | Android full-screen-access explanation and settings action exist. [access surface][full-screen] | Both apps depend on OS permission/settings; no guarantee that an app can bypass them. |
| P10 | Mute, use speaker, see duration, hang up | Explicit controls; duration begins at connection and remains anchored through reconnecting. [controls][controls], [active UI][active] | Exists. Truthful control availability is exposed rather than optimistic UI toggles. |
| P11 | Move to another app while talking | Android Back backgrounds the task and keeps the call running. Native audio lifecycle exists on both platforms. [Back guard][back] | Distinguish this from G2: remaining in another Mknoon screen is blocked by the overlay. |
| P12 | Wi-Fi/mobile network change or a temporary drop | Reconnecting state, ICE restart machinery, bounded reconnect window defaulting to 15 seconds; failure has a distinct message. [state policy][life], [messages][states-copy] | Exists. Which app recovers faster or more reliably needs live controlled tests. |
| P13 | Microphone permission denied | Call permission adapter and explicit microphone-needed failure message. [permission adapter][permission], [messages][states-copy] | Exists. A dedicated settings deep link/retry experience was not certified. |
| P14 | Receive a phone call or lose audio focus | Interruption coordinator handles paused/reconnect and recovery intents. [interruption][interruption] | Exists at code level. Carrier-call/CallKit/Telecom interactions require real devices; cannot infer a full hold-and-resume UX. |
| P15 | Be recording a voice note when a call starts | Existing microphone owner is coordinated before call capture; recording is not silently resumed. [media conflict adapter][mic-conflict] | Exists. This is not equivalent to pausing attachment network downloads. |
| P16 | See call outcome inside the conversation/contact list | Durable history produces chat timeline rows and Orbit call/unread activity. [chat row][chat-row], [Orbit][orbit] | Exists. G5/G6 concern browsing and shortcuts, not absence of history. |
| P17 | Use screen reader or local language | Call screens expose individual names/status/control semantics and localized strings. [controls][controls], [overlay][overlay] | Exists in source; VoiceOver/TalkBack order, large-text fit and actual usability need runtime accessibility review. |
| P18 | Prevent blocked/unaccepted people from ringing | Endpoint resolution refuses blocked/nonaccepted contacts. [endpoint][endpoint] | Exists. Signal's message-request/trust terminology differs; “always rings unknown people” is not an established advantage. |

## Additional differences or unknowns that must not become invented gaps

| ID | Scenario | Signal evidence | Mknoon finding / next proof |
|---|---|---|---|
| U1 | A large attachment downloads while talking | Signal documents pausing attachment downloads during calls; Android download jobs carry a not-in-call constraint. [support](https://support.signal.org/hc/en-us/articles/360056044831-Data-Usage-Options-Wi-Fi-Cellular), [constraint][signal-download] | No equivalent explicit pause guard was found in inspected download/call owners. Verify concurrent transfer behavior; it may compete for bandwidth, but worse audio is an **inference**, not measured. |
| U2 | Hold phone to ear; avoid accidental touches | Signal has explicit proximity handling. [Android][signal-a-proximity], [iOS][signal-i-proximity] | No explicit app proximity owner found in the searched call/native paths. Native frameworks/plugin behavior may still provide it. Test before declaring absent. |
| U3 | Do Not Disturb, silent mode, low power or Android force-stop | Signal documents missed-call/permission/battery limitations. [support](https://support.signal.org/hc/en-us/articles/360007060672-Troubleshooting-Calling) | Native code exists, but not a fresh platform verdict. “Killed app”, “backgrounded”, “force-stopped” and “offline” are distinct cases. Do not promise either app overrides OS restrictions. |
| U4 | Two people call each other simultaneously | Signal has glare-handling outcomes. [iOS service][signal-i-expired] | Mknoon has a busy/session state owner; exact simultaneous-call UX was not established. Controlled two-peer test needed. |
| U5 | Poor network, noisy room, echo, Bluetooth microphone quality | Signal has purpose-built tuning and low-data UX. | Need comparative packet-loss/jitter/audio-route tests. Engine/library names cannot establish that Signal sounds better. |
| U6 | Hear both parties immediately after answering | Both have negotiation/media-readiness machinery. | Measure tap-to-two-way-audio, one-way audio, stale native Answer actions and locked/unlocked handoff on available devices. |
| U7 | Get a missed-call banner while already using the app | Platform/UI policy varies in Signal. | Mknoon's production foreground notifier deliberately suppresses missed-call cards when the app is foreground-active. It still retains history. [composition policy][foreground-missed] This is an observed product choice, not established Signal parity/absence. |
| U8 | Calls survive process crashes or manual app termination mid-conversation | Not certified by this review. | Native journals and cleanup are not proof of uninterrupted media. Test separately from ordinary background continuation. |

**Video upgrade, screen sharing, group calling, call links and voicemail are not included in the voice-only missing list.** Video/group capabilities in Signal are broader product scope; they do not prove a defect in Mknoon's chosen one-to-one voice feature. Neither app is claimed here to supply voicemail, cellular fallback, guaranteed automatic redial, or transfer of an already-connected call between devices.

## Suggested implementation order

1. **Delayed missed-call recovery (highest user impact):** make “someone tried to reach me while offline” durable without prolonging ringing permission. Reuse encrypted delivery and local dedupe/history owners. Tradeoff: retention/storage and extra notification/metadata handling.
2. **Minimize and return to call:** keep the current call alive while allowing chat/Orbit navigation. Preserve native Back behavior, accessibility isolation when expanded and recording/audio conflict rules. Tradeoff: more navigation/UI state; microphone conflicts must stay controlled.
3. **Call-back shortcut and Calls list:** add an explicit call action to history rows or detail view, then centralized All/Missed/search. Reuse existing history; do not duplicate it. Tradeoff: clutter and clear confirmation/preflight handling.
4. **Audio-output chooser and data-saving controls:** build on the current native route owner; expose named routes where available. Define and measure a low-data mode before advertising it. Tradeoff: platform variation and audio-quality/bandwidth balance.
5. **Full peer-IP privacy option:** decide whether Always relay must also disable direct signaling. Tradeoff: losing direct setup acceleration and increasing dependence on relay availability.
6. **Linked-device ringing/history convergence:** larger design with first-answer winner, cancellation of other rings and synchronized history. Tradeoff: multiple wake-ups, battery/network work and privacy/state complexity.
7. **System Recents and ringtone customization:** lower priority, explicit platform opt-in. Excluding system logs can be intentional privacy behavior; defaulting them on would change the app's disclosure boundary.

Before implementation, resolve whether flagged “not found” behavior exists through OS/plugin UI. Use available pinned targets and Appium MCP for UX; exact deterministic tests for relay expiry/durable history. Unavailable hardware is N/A by project policy. No live measurements or new test passes are claimed here.

## Version and evidence scope

Mknoon: the working tree reviewed on 12 October 2026, with HEAD recorded in the adjacent manifest; the checkout advanced during review from `ec1da2cc…` to `6a5bcc50…`. The manifest pins hashes of cited files at report creation. Existing user changes were not edited. Declared app version was `1.0.1+123`.

Signal Android: `v8.30.3`, commit `9a8f9ba79a3218ba2bddab1dabe7d23bae4cbc66`. Signal iOS: `8.32.0.1910`, commit `4046e74fe7b52f7790337ede04bde76fc173f23f`. Public support pages were consulted on 12 October 2026 and are not immutable release specifications. Source/UI presence does not bind installed binaries, deployed services, remote configuration or successful notification delivery.

[life]: /Volumes/CrucialX9/flutter_app/lib/features/call/domain/call_state.dart:105

[expiry]: /Volumes/CrucialX9/flutter_app/go-relay-server/call_control_redis.go:395

[max-expiry]: /Volumes/CrucialX9/flutter_app/go-relay-server/call_control.go:32

[decode]: /Volumes/CrucialX9/flutter_app/lib/features/call/infrastructure/secure_call_envelope_codec.dart:529

[missed]: /Volumes/CrucialX9/flutter_app/lib/features/call/application/missed_call_notifier.dart:44

[history]: /Volumes/CrucialX9/flutter_app/lib/features/call/application/call_history_projector.dart:27

[headless-history]: /Volumes/CrucialX9/flutter_app/lib/features/call/application/headless_terminal_call_record.dart:10

[headless-ring]: /Volumes/CrucialX9/flutter_app/lib/features/call/application/headless_call_ringing_reply.dart:8

[headless-wiring]: /Volumes/CrucialX9/flutter_app/lib/app/bootstrap/production_headless_call_admission.dart:970

[overlay]: /Volumes/CrucialX9/flutter_app/lib/features/call/presentation/foreground_call_overlay.dart:335

[back]: /Volumes/CrucialX9/flutter_app/lib/features/call/presentation/foreground_call_back_guard.dart:17

[controls]: /Volumes/CrucialX9/flutter_app/lib/features/call/presentation/widgets/call_controls.dart:87

[call-row]: /Volumes/CrucialX9/flutter_app/lib/features/conversation/presentation/widgets/call_timeline_row.dart:76

[chat-row]: /Volumes/CrucialX9/flutter_app/lib/features/conversation/presentation/screens/conversation_screen.dart:1071

[orbit]: /Volumes/CrucialX9/flutter_app/lib/features/call/data/call_history_orbit_activity_source.dart:1

[ios-recents]: /Volumes/CrucialX9/flutter_app/ios/Runner/MknoonCallKitController.swift:469

[notification]: /Volumes/CrucialX9/flutter_app/lib/core/notifications/flutter_notification_service.dart:600

[notification-details]: /Volumes/CrucialX9/flutter_app/lib/core/notifications/local_notification_support.dart:41

[endpoint]: /Volumes/CrucialX9/flutter_app/lib/features/call/application/call_endpoint_resolver.dart:76

[busy]: /Volumes/CrucialX9/flutter_app/lib/features/call/application/call_coordinator.dart:379

[privacy]: /Volumes/CrucialX9/flutter_app/lib/features/settings/application/call_privacy_preference_use_cases.dart:27

[copy]: /Volumes/CrucialX9/flutter_app/lib/l10n/app_en.arb:2045

[signal-race]: /Volumes/CrucialX9/flutter_app/lib/features/call/application/call_signaling_service.dart:86

[direct]: /Volumes/CrucialX9/flutter_app/lib/features/call/infrastructure/p2p_call_transport.dart:36

[video]: /Volumes/CrucialX9/flutter_app/lib/features/call/infrastructure/flutter_webrtc_call_engine.dart:1601

[interruption]: /Volumes/CrucialX9/flutter_app/lib/features/call/application/call_audio_interruption_coordinator.dart:59

[mic-conflict]: /Volumes/CrucialX9/flutter_app/lib/features/call/infrastructure/call_media_conflict_adapter.dart:8

[android-ui]: /Volumes/CrucialX9/flutter_app/android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallNotificationFactory.kt:110

[android-locked]: /Volumes/CrucialX9/flutter_app/android/app/src/main/kotlin/com/mknoon/app/call/MknoonLockedCallView.kt:32

[ios-wake]: /Volumes/CrucialX9/flutter_app/ios/Runner/MknoonVoipPushRegistry.swift:741

[full-screen]: /Volumes/CrucialX9/flutter_app/lib/features/call/presentation/full_screen_call_access_surface.dart:1

[ringback]: /Volumes/CrucialX9/flutter_app/lib/features/call/application/call_ringback_coordinator.dart:25

[states-copy]: /Volumes/CrucialX9/flutter_app/lib/features/call/presentation/foreground_call_overlay.dart:530

[active]: /Volumes/CrucialX9/flutter_app/lib/features/call/presentation/screens/active_call_screen.dart:36

[permission]: /Volumes/CrucialX9/flutter_app/lib/features/call/infrastructure/call_microphone_permission_adapter.dart:4

[foreground-missed]: /Volumes/CrucialX9/flutter_app/lib/app/bootstrap/production_application_bootstrap.dart:6254

[signal-a-expired]: https://github.com/signalapp/Signal-Android/blob/9a8f9ba79a3218ba2bddab1dabe7d23bae4cbc66/app/src/main/java/org/thoughtcrime/securesms/service/webrtc/WebRtcActionProcessor.java#L267

[signal-i-expired]: https://github.com/signalapp/Signal-iOS/blob/4046e74fe7b52f7790337ede04bde76fc173f23f/Signal/Calls/IndividualCallService.swift#L811

[signal-a-log]: https://github.com/signalapp/Signal-Android/blob/9a8f9ba79a3218ba2bddab1dabe7d23bae4cbc66/app/src/main/java/org/thoughtcrime/securesms/calls/log/CallLogFragment.kt#L248

[signal-i-log]: https://github.com/signalapp/Signal-iOS/blob/4046e74fe7b52f7790337ede04bde76fc173f23f/Signal/Calls/UserInterface/CallsListViewController.swift#L2275

[signal-minimize]: https://github.com/signalapp/Signal-iOS/blob/4046e74fe7b52f7790337ede04bde76fc173f23f/Signal/Calls/UserInterface/IndividualCallViewController.swift#L1097

[signal-return]: https://github.com/signalapp/Signal-iOS/blob/4046e74fe7b52f7790337ede04bde76fc173f23f/Signal/Calls/UserInterface/ReturnToCallViewController.swift#L258

[signal-picker]: https://github.com/signalapp/Signal-Android/blob/9a8f9ba79a3218ba2bddab1dabe7d23bae4cbc66/app/src/main/java/org/thoughtcrime/securesms/components/webrtc/WebRtcAudioOutputBottomSheet.kt#L42

[signal-recents]: https://github.com/signalapp/Signal-iOS/blob/4046e74fe7b52f7790337ede04bde76fc173f23f/Signal/Calls/UserInterface/CallKitCallUIAdaptee.swift#L70

[signal-sound]: https://github.com/signalapp/Signal-Android/blob/9a8f9ba79a3218ba2bddab1dabe7d23bae4cbc66/app/src/main/java/org/thoughtcrime/securesms/components/settings/conversation/sounds/custom/CustomNotificationsSettingsScreen.kt#L172

[signal-download]: https://github.com/signalapp/Signal-Android/blob/9a8f9ba79a3218ba2bddab1dabe7d23bae4cbc66/app/src/main/java/org/thoughtcrime/securesms/jobs/AttachmentDownloadJob.kt#L560

[signal-a-proximity]: https://github.com/signalapp/Signal-Android/blob/9a8f9ba79a3218ba2bddab1dabe7d23bae4cbc66/app/src/main/java/org/thoughtcrime/securesms/webrtc/locks/ProximityLock.java#L19

[signal-i-proximity]: https://github.com/signalapp/Signal-iOS/blob/4046e74fe7b52f7790337ede04bde76fc173f23f/Signal/Calls/CallAudioService.swift#L263

[signal-busy]: https://github.com/signalapp/Signal-iOS/blob/4046e74fe7b52f7790337ede04bde76fc173f23f/Signal/Calls/IndividualCallService.swift#L821

[signal-sync]: https://github.com/signalapp/Signal-iOS/blob/4046e74fe7b52f7790337ede04bde76fc173f23f/SignalServiceKit/Calls/CallRecord/IncomingCallEventSyncMessageManager.swift#L1
