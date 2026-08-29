workspace "Mknoon One-to-One Calls" "Source-backed architecture proposal for foreground one-to-one audio calling. Existing components are distinguished from proposed call and TURN components in their descriptions." {

    model {
        caller = person "[01] Caller" "Starts a private audio call from an existing one-to-one conversation."
        callee = person "[05] Callee" "Receives and answers the call while Mknoon is in the foreground for the MVP."
        mknoon = softwareSystem "[02] Mknoon" "Private Flutter/libp2p messaging application." {
            mobileApp = container "Flutter Application" "Existing mobile app plus proposed one-to-one calling feature." "Flutter / Dart" {
                conversationHeader = component "Call Entry Button" "PROPOSED: phone action in the existing one-to-one conversation header." "Flutter Widget"
                callController = component "Call Controller" "PROPOSED: coordinates outgoing, incoming, accept, decline, busy, timeout, and hangup actions." "Dart"
                callSession = component "Call Session State Machine" "PROPOSED: callId, TTL, glare resolution, idempotency, and idle/dialing/ringing/connecting/active/ended states." "Dart"
                signalingAdapter = component "Encrypted Call Signaling" "PROPOSED: call_* envelopes sent fast-path-only through the existing P2PService.sendMessageWithReply path." "Dart"
                callEngine = component "WebRTC Call Engine" "PROPOSED: RTCPeerConnection, ICE, DTLS-SRTP audio, mute, speaker, stats, and teardown using flutter_webrtc." "flutter_webrtc"
                micGateway = component "Microphone Permission Gateway" "EXISTING: reusable permission_handler abstraction currently used by voice messages." "Dart"
                callScreens = component "Incoming / Active Call UI" "PROPOSED MVP: foreground incoming screen and active call controls." "Flutter"
                incomingRouter = component "Incoming Message Router" "EXISTING: content-type router; currently has no call_* cases." "Dart"
                p2pService = component "P2P Service" "EXISTING: account-gated fast-path send and relay health/session management." "Dart"
                bridgeClient = component "Go Bridge Client" "EXISTING: JSON command bridge into the native Go runtime." "Dart / MethodChannel"
            }
            goRuntime = container "Go/libp2p Runtime" "Existing peer identity, encrypted chat stream, relay reservation, peer sessions, LAN-direct dial, and gated DCUtR support." "Go / libp2p" {
                chatProtocol = component "Encrypted Chat Stream" "EXISTING: /mknoon/chat/1.0.0 carries content-agnostic envelopes and immediate transport acknowledgements." "libp2p stream"
                peerSession = component "Peer Session Manager" "EXISTING: selects direct connections over circuit-relay connections and falls back when direct transport is lost." "Go / libp2p"
                dcutr = component "DCUtR Upgrade" "IMPLEMENTED BUT DISABLED BY DEFAULT: opportunistic libp2p circuit-to-direct upgrade, pending device campaign." "go-libp2p hole punching"
            }
        }
        peerDevice = softwareSystem "[04] Callee Mknoon Device" "The other participant's Flutter app and Go/libp2p node."
        relayInfra = softwareSystem "[03] Mknoon Relay Infrastructure" "Optional signaling relay plus proposed WebRTC NAT traversal services. Direct paths may bypass it." {
            relayControl = container "libp2p Relay + Rendezvous" "EXISTING CONTROL PATH ONLY: reservations, rendezvous, inbox, presence, and push-token services. Current circuit defaults are 2 minutes and 128 KiB per direction, so this relay cannot carry sustained call audio." "Go / libp2p"
            turnCredentials = container "TURN Credential Service" "PROPOSED: authenticated short-lived HMAC credentials returned to the requesting Mknoon peer." "Go"
            stunTurn = container "STUN / TURN Service" "PROPOSED: STUN discovery and TURN UDP media relay, colocated operationally with the relay but separate from libp2p circuits." "Pion TURN"
        }
        pushProvider = softwareSystem "[F1] FCM / APNs" "FUTURE: call-specific wake/ringing for background or terminated apps; not part of the foreground MVP." "External"

        caller -> mobileApp "01 · Start the call"
        callee -> mknoon "04 · Receive the incoming call"
        callee -> peerDevice "05 · Accept or decline"
        conversationHeader -> callController "A01 · Start outgoing call"
        callController -> micGateway "A02 · Request microphone permission"
        callController -> callSession "A03 · Create and advance call state"
        callSession -> signalingAdapter "A04 · Build call_* messages"
        signalingAdapter -> p2pService "A05 · Send fast-path encrypted signal"
        p2pService -> bridgeClient "A06 · Cross the native bridge"
        bridgeClient -> incomingRouter "A07 · Forward incoming envelope"
        incomingRouter -> callSession "A08 · Apply validated call signal"
        callController -> callEngine "A09 · Start or stop WebRTC"
        callController -> callScreens "A10 · Show ringing and active states"
        callEngine -> turnCredentials "06 · Fetch short-lived ICE credentials"
        mobileApp -> goRuntime "02 · Exchange encrypted call signaling" "Native bridge + events"
        mobileApp -> turnCredentials "06 · Fetch short-lived ICE credentials" "Authenticated relay API"
        goRuntime -> peerDevice "03A · Preferred: exchange signaling directly" "libp2p direct"
        goRuntime -> relayControl "03B · If direct fails, use circuit relay" "Circuit Relay v2"
        relayControl -> peerDevice "03C · Deliver relayed signaling" "libp2p circuit"
        peerSession -> dcutr "N04 · Attempt optional direct upgrade"
        dcutr -> peerDevice "N05 · Use direct QUIC/TCP control path" "Disabled by default"
        mobileApp -> peerDevice "08A · Preferred: direct encrypted audio" "WebRTC DTLS-SRTP"
        mobileApp -> stunTurn "08B · Fallback: send encrypted audio via TURN" "TURN-relayed DTLS-SRTP"
        stunTurn -> peerDevice "08C · Deliver relayed encrypted audio" "TURN UDP"
        turnCredentials -> stunTurn "07 · Authorize bounded TURN allocation"
        relayControl -> pushProvider "F01 · Future: request call wake notification"
        pushProvider -> peerDevice "F02 · Future: wake or ring background app"
        bridgeClient -> chatProtocol "N01 · Open call-signaling transport"
        chatProtocol -> peerSession "N02 · Open authenticated peer stream"
        peerSession -> relayControl "N03 · Keep circuit-relay fallback"
    }

    views {
        systemContext mknoon "01_ProductView" {
            title "Can two Mknoon users call one another?"
            description "Yes. Keep libp2p as the encrypted signaling/control plane and add WebRTC as the real-time media plane, with TURN as the reliable fallback."
            include caller
            include callee
            include mknoon
            include peerDevice
            include relayInfra
            include pushProvider
            autoLayout lr
        }

        container mknoon "02_ForegroundCallFlow" {
            title "Foreground one-to-one audio-call flow"
            description "MVP path: encrypted call signaling over existing libp2p; direct WebRTC audio where possible; TURN fallback where necessary."
            include caller
            include callee
            include mobileApp
            include goRuntime
            include peerDevice
            include relayControl
            include turnCredentials
            include stunTurn
            autoLayout
        }

        component mobileApp "03_FlutterCallFeature" {
            title "Flutter components to introduce"
            description "Proposed call feature layered on existing conversation, permission, router, P2P service, and bridge seams."
            include caller
            include conversationHeader
            include callController
            include callSession
            include signalingAdapter
            include callEngine
            include micGateway
            include callScreens
            include incomingRouter
            include p2pService
            include bridgeClient
            include goRuntime
            include turnCredentials
            include stunTurn
            include peerDevice
            autoLayout lr
        }

        component goRuntime "04_ControlPlaneUpgrade" {
            title "Existing libp2p control path and optional direct upgrade"
            description "DCUtR can improve the libp2p signaling path, but it does not replace WebRTC ICE/STUN/TURN for reliable live audio."
            include bridgeClient
            include chatProtocol
            include peerSession
            include dcutr
            include relayControl
            include peerDevice
            autoLayout lr
        }

        styles {
            element "Person" {
                background #075985
                color #e0f2fe
                shape person
                stroke #7dd3fc
            }

            element "Software System" {
                background #0b4f8a
                color #eff8ff
                stroke #9bd8ff
            }

            element "Container" {
                background #0b66a3
                color #eff8ff
                stroke #b6e3ff
            }

            element "Component" {
                background #0a75bd
                color #ffffff
                stroke #d6f0ff
            }

            element "External" {
                background #164e63
                color #cffafe
                stroke #67e8f9
            }

            relationship "Relationship" {
                color #d9f3ff
                thickness 2
            }
        }
    }

}
