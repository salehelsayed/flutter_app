workspace "Mknoon 1-to-1 Voice Calling - PRD v2" "Implementation-ready architecture contract for private 1-to-1 audio calling. The call feature is planned, not implemented; existing foundations, proposed components, and unproven infrastructure are marked explicitly." {

    model {
        caller = person "[01] Caller" "Accepted Mknoon contact who starts and controls a private audio call."
        callee = person "[08] Callee" "Accepted Mknoon contact who receives and answers or declines the call."
        mknoon = softwareSystem "Mknoon" "Private Flutter/libp2p messaging application. PRD v2 makes Dart canonical after runtime attachment, permits only a bounded native pre-start handoff before attachment, keeps libp2p as signaling transport, and uses WebRTC as the media plane." {
            mobileApp = container "[02] Flutter Call Application" "PLANNED under SE-12 and SE-13. Adds deterministic call control, encrypted signaling, foreground call UI, WebRTC audio, cleanup, and local history to the existing app." "Flutter / Dart" "Planned" {
                callEntry = component "[02A] Call Entry + Policy Gate" "PLANNED: exposes the phone action only when one device survives the accepted contact's trusted device roster and current signed relay-capability intersection." "Flutter / Dart" "Planned"
                callCoordinator = component "[02B] CallCoordinator" "PLANNED in SE-12 / VC2-02: canonical serialized product-state owner after Dart attaches; owns call_id, timers, transitions, WebRTC lifecycle, terminal dominance, native-record adoption, and cleanup." "Dart" "Planned"
                callSignaling = component "[02C] CallSignalingService" "PLANNED in SE-12 / VC2-02: signs and encrypts versioned call_signal envelopes, races direct delivery with ephemeral mailbox custody, and deduplicates every path." "Dart + existing ML-KEM/AES-GCM bridge" "Planned"
                callEngine = component "[02D] WebRTC CallEngine" "PLANNED in SE-13 / VC2-03 after SE-11 feasibility proof: audio-only PeerConnection, fingerprint-bound SDP, bounded trickle ICE, Opus, route control, and teardown. Connected uses ICE/DTLS/native-audio/sender/receiver-track readiness, never observed audio bytes or energy." "flutter_webrtc behind a fakeable Dart boundary" "Planned"
                callUi = component "[02E] Foreground Call UI" "PLANNED in SE-13 / VC2-03: Calling, Ringing, Connecting, Connected, Reconnecting, mute, speaker/route, and end. Foreground only at this milestone." "Flutter" "Planned"
                cleanupHistory = component "[02F] Cleanup + Local Call History" "PLANNED across SE-12 and SE-16: one idempotent cleanup path and one local history projection per call_id; never stores SDP, ICE addresses, credentials, or audio." "Dart / local database" "Planned"
                nativePrestart = component "[L0] Native Pre-Start Handoff" "LATER PHASE in SE-14 / SE-15: one protected bounded record, monotonic native events, terminal precedence, ordered exactly-once Dart adoption, acknowledgement, and cleanup. It is not a second call state machine." "Kotlin / Swift / protected local store" "LaterPhase"
                micGateway = component "[02G] Microphone + Audio Session Foundation" "EXISTING reusable permission and audio-session plumbing. It is not yet integrated with WebRTC calling." "permission_handler / audio_session" "Existing"
                androidAdapter = component "[L1] Android Telecom Adapter" "LATER PHASE: SE-14 / VC2-04 adds Telecom/Core-Telecom, CallStyle, foreground service, durable pre-Dart action capture, and background/terminated/locked lifecycle proof." "Kotlin / Android Telecom" "LaterPhase"
                iosAdapter = component "[L2] iOS CallKit Adapter" "LATER PHASE: SE-15 / VC2-05 adds a distinct durable VoIP token, prompt CallKit report, PushKit callback completion without waiting for Flutter/network/mailbox, parallel validation, pre-Dart action capture, native audio activation, and physical-iPhone proof." "Swift / PushKit / CallKit" "LaterPhase"
            }
            goRuntime = container "[03] Go/libp2p Signaling Transport" "EXISTING reusable transport. Carries bounded authenticated call_signal frames directly or through Circuit Relay; owns no product call state and never carries WebRTC audio." "Go / libp2p" "Existing" {
                p2pTransport = component "[03A] Existing Message Stream" "EXISTING framed authenticated peer stream, direct connections, Circuit Relay fallback, transport ACKs, and bridge events. Transport ACK never means Ringing." "libp2p" "Existing"
            }
        }
        calleeDevice = softwareSystem "[07] Callee Mknoon Device" "The selected call-capable recipient device. MVP resolves exactly one device from the trusted contact-device roster intersected with current signed relay capability; a relay record alone is not authority and no fanout occurs." "Planned" {
            calleeApp = container "Callee Call Runtime" "PLANNED mirror of the deterministic Dart CallCoordinator, signaling, foreground UI, and WebRTC engine on the recipient device." "Flutter / Dart / Go" "Planned"
        }
        relayInfra = softwareSystem "Mknoon Relay Services" "Separates libp2p signaling custody from WebRTC media relay. Existing relay and coturn processes are useful foundations, not proof that calling is ready." {
            relayControl = container "[04] libp2p Circuit Relay" "EXISTING signaling fallback only. It may carry call-control bytes but is never an ICE/TURN media relay." "Go / libp2p Circuit Relay v2" "Existing"
            callMailbox = container "[05] Ephemeral Call Mailbox" "PLANNED in SE-12 / VC2-02: separate durable Redis custody with a hard 45-second invite TTL, bounded events/bytes, sender attribution, replay tombstones, atomic cancel/ack, and opaque wake authority. Redis failure never becomes in-memory success and chat mailbox rules are not reused." "Go / Redis" "Planned"
            turnCredentials = container "[06] TURN Credential Authority" "PLANNED in SE-11 / VC2-01: authenticated turn_credentials_v1 mints rate-limited 10-minute coturn REST credentials; that TTL is not maximum call duration. It stages replacements for long calls/restarts. Minting outage, allocation refresh/recreation, expiry, coordinated secret rotation, and rollback are explicit gates; the app ships no static secret." "Go" "Planned"
            coturn = container "[07] coturn Media Relay" "ACTIVE INFRASTRUCTURE, PROOF PENDING. coturn 4.6.3, UDP STUN, and static-credential service on 3478 are live; REST-secret minting/rotation, authenticated allocation, real relay candidates, TCP/TLS and TLS/443 media, long-call/restart behavior, forced-relay privacy, quotas, and cleanup remain implementation gates." "coturn / STUN / TURN" "ProofPending"
        }
        pushProvider = softwareSystem "FCM / APNs Native Call Delivery" "LATER PHASE for SE-14 and SE-15. Push is an opaque wake/presentation hint only; the authenticated mailbox invitation remains signaling truth. iOS uses a distinct durable PushKit VoIP token and APNs VoIP topic, never ordinary notifications or the Notification Service Extension." "LaterPhase,External"

        caller -> mobileApp "01 · Intersect trusted device roster with signed relay capability; create one CallSession and show Calling"
        mobileApp -> callMailbox "02A · Store signed encrypted invite with a hard 45-second TTL" "call_store_v1" "Signaling"
        mobileApp -> goRuntime "02B · Race direct call_signal delivery; transport ACK is not Ringing" "Native bridge + authenticated libp2p" "Signaling"
        goRuntime -> calleeApp "03A · Preferred: deliver signaling directly" "libp2p direct" "Signaling"
        goRuntime -> relayControl "03B · Fallback: use Circuit Relay for signaling only" "Circuit Relay v2" "Fallback"
        relayControl -> calleeApp "03C · Deliver relayed signaling; never carry WebRTC audio" "libp2p circuit" "Fallback"
        calleeApp -> callMailbox "03D · Retrieve current encrypted invite when the direct race loses" "call_retrieve_v1" "Signaling"
        calleeApp -> callee "04 · After roster/capability, identity, policy, expiry, and replay checks, present foreground UI"
        callee -> calleeApp "05 · Accept or decline"
        calleeApp -> goRuntime "06 · Return application Ringing, then accept or generic reject" "Authenticated libp2p" "Signaling"
        goRuntime -> mobileApp "07 · Deliver one authenticated idempotent event to Dart CallCoordinator" "Bridge event" "Signaling"
        mobileApp -> turnCredentials "08 · After accept, fetch/stage short-lived ICE credentials for allocation or restart; no static app secret" "turn_credentials_v1" "Fallback"
        turnCredentials -> coturn "09 · Authorize bounded allocation with tested expiry, long-call, outage, and secret-rotation behavior" "coturn REST authentication" "Fallback"
        mobileApp -> calleeApp "10 · Exchange fingerprint-bound offer/answer and bounded trickle ICE after accept" "Signed encrypted call_signal" "Signaling"
        mobileApp -> calleeApp "11A · Preferred media: direct DTLS-SRTP Opus; Connected uses ICE/DTLS/track/audio-session readiness, never byte or energy growth" "WebRTC" "Media"
        mobileApp -> coturn "11B · Fallback media: TURN UDP, then TCP/TLS when required" "WebRTC over TURN" "Fallback"
        coturn -> calleeApp "11C · Relay encrypted WebRTC packets without media keys" "TURN" "Fallback"
        mobileApp -> calleeApp "12 · Send idempotent terminate; terminal state dominates late events" "Signed encrypted call_signal" "Signaling"
        caller -> callEntry "Starts a voice call"
        callEntry -> callCoordinator "Submits an authorized target"
        callCoordinator -> callUi "Projects deterministic call state"
        callUi -> callCoordinator "Submits user actions"
        callCoordinator -> callSignaling "Requests signed encrypted call-control messages"
        callCoordinator -> callEngine "Owns media lifecycle after acceptance"
        callCoordinator -> micGateway "Requests microphone and audio-session access"
        callCoordinator -> cleanupHistory "Runs terminal cleanup and history projection"
        nativePrestart -> callCoordinator "Hands off ordered native events once; terminal state dominates; Dart acknowledges adoption/cleanup"
        callCoordinator -> androidAdapter "Submits and receives Android native lifecycle events"
        callCoordinator -> iosAdapter "Submits and receives iOS native lifecycle events"
        androidAdapter -> nativePrestart "Persists bounded pre-Dart Telecom actions; never SDP, ICE, credentials, or media"
        iosAdapter -> nativePrestart "Reports CallKit and completes PushKit promptly; persists bounded actions while validation/runtime continue"
        androidAdapter -> callCoordinator "Reports idempotent native actions after attachment"
        iosAdapter -> callCoordinator "Reports idempotent native actions after attachment"
        callEngine -> callCoordinator "Reports selected pair, ICE, DTLS, native-audio, sender/receiver-track readiness, route, and failure; audio bytes never gate Connected"
        callEngine -> callSignaling "Produces fingerprint-bound offer, answer, ICE, and restart signals"
        callSignaling -> p2pTransport "Sends and receives call_signal frames" "Authenticated libp2p stream" "Signaling"
        p2pTransport -> calleeApp "Delivers direct signaling" "libp2p direct" "Signaling"
        p2pTransport -> relayControl "Falls back when no direct signaling route exists" "Circuit Relay v2" "Fallback"
        callSignaling -> callMailbox "Stores short-lived encrypted call events before racing direct delivery" "call_store_v1" "Signaling"
        calleeApp -> p2pTransport "Returns ringing, accept/reject, SDP/ICE, and terminate events" "Authenticated libp2p stream" "Signaling"
        p2pTransport -> callCoordinator "Reports one validated incoming event; ACK is transport-only" "Bridge event" "Signaling"
        callEngine -> turnCredentials "Requests and stages short-lived ICE credentials for new allocation/restart; healthy media is not migrated solely for age" "turn_credentials_v1" "Fallback"
        callEngine -> calleeApp "Preferred direct two-way audio" "WebRTC DTLS-SRTP / Opus" "Media"
        callEngine -> coturn "Fallback encrypted media when direct ICE cannot connect" "TURN UDP or TCP/TLS" "Fallback"
        callMailbox -> pushProvider "Requests an opaque wake only for a committed current invite" "" "Later"
        pushProvider -> androidAdapter "Wakes Android call presentation and mailbox retrieval" "" "Later"
        pushProvider -> iosAdapter "Delivers APNs VoIP wake only; CallKit report completes PushKit while authenticated retrieval continues in parallel" "" "Later"
    }

    views {
        systemContext mknoon "01_ProductView" {
            title "Mknoon private voice calling - PRD v2 contract"
            description "PROPOSED, NOT IMPLEMENTED. Existing encrypted messaging, relay, push, permissions, and coturn are foundations. Delivery proceeds through SE-11 to SE-16; external beta requires native lifecycle and hardening, not only a foreground demo."
            include caller
            include callee
            include mknoon
            include calleeDevice
            include relayInfra
            include pushProvider
            autoLayout lr
        }

        container mknoon "02_ForegroundCallFlow" {
            title "Foreground one-to-one audio call - planned implementation flow"
            description "PLANNED INTERNAL MILESTONE - SE-13 / VC2-03. Depends on SE-11 / VC2-01 feasibility, authenticated TURN plus long-call/restart/outage/rotation proof, and SE-12 / VC2-02 deterministic signaling with separate fail-closed 45-second Redis custody and roster/capability endpoint intersection. No production call stack exists yet. Dart CallCoordinator is canonical after attachment; native later holds only a bounded pre-start handoff. Audio starts only after accept and permission. Connected requires selected pair, ICE, DTLS, native audio, sender track, and remote receiver/track—not audio bytes or energy. Android lifecycle is SE-14; Apple-aligned PushKit/CallKit is SE-15; hardening and beta rollout are SE-16."
            include caller
            include mobileApp
            include goRuntime
            include relayControl
            include callMailbox
            include turnCredentials
            include coturn
            include calleeApp
            include callee
            autoLayout
        }

        component mobileApp "03_FlutterCallFeature" {
            title "Dart-canonical call control, bounded native handoff, and WebRTC boundary"
            description "SE-12 and SE-13 introduce these planned components around existing permission/audio and libp2p seams. Native adapters remain later phases: before Dart attaches they may hold only one bounded pre-start record; after attachment no component other than CallCoordinator advances product call state."
            include caller
            include callEntry
            include callCoordinator
            include callSignaling
            include callEngine
            include callUi
            include cleanupHistory
            include nativePrestart
            include micGateway
            include androidAdapter
            include iosAdapter
            include p2pTransport
            include callMailbox
            include turnCredentials
            include coturn
            include calleeApp
            include callee
            autoLayout lr
        }

        component goRuntime "04_ControlPlaneUpgrade" {
            title "Call signaling reuses transport, not chat semantics"
            description "The existing libp2p stream and Circuit Relay carry encrypted versioned call_signal bytes. SE-12 adds a separate fail-closed Redis 45-second mailbox and roster/capability endpoint intersection; call events never enter the durable chat retrier or an in-memory wake/token fallback, and Circuit Relay never carries WebRTC audio."
            include callSignaling
            include p2pTransport
            include relayControl
            include callMailbox
            include calleeApp
            include callCoordinator
            autoLayout lr
        }

        styles {
            element "Person" {
                background #0f3d5e
                color #f0f9ff
                shape person
                stroke #7dd3fc
            }

            element "Software System" {
                background #123a5a
                color #f8fafc
                stroke #93c5fd
            }

            element "Container" {
                background #174d70
                color #f8fafc
                stroke #bae6fd
            }

            element "Component" {
                background #1e5f87
                color #ffffff
                stroke #dbeafe
            }

            element "Existing" {
                background #0f766e
                color #ecfeff
                stroke #5eead4
            }

            element "Planned" {
                background #1d4ed8
                color #eff6ff
                stroke #93c5fd
            }

            element "ProofPending" {
                background #92400e
                color #fffbeb
                stroke #fbbf24
            }

            element "LaterPhase" {
                background #475569
                color #f8fafc
                stroke #cbd5e1
            }

            relationship "Relationship" {
                color #dbeafe
                thickness 2
                fontSize 14
            }

            relationship "Signaling" {
                color #60a5fa
                thickness 3
            }

            relationship "Media" {
                color #34d399
                thickness 4
            }

            relationship "Fallback" {
                color #fbbf24
                thickness 3
                dashed true
            }

            relationship "Later" {
                color #94a3b8
                thickness 2
                dashed true
                opacity 70
            }
        }
    }

}
