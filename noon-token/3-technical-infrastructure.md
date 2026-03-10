another question, if I provided reverse proxies, can people then run the app on their desktops and connect it to the reverse prxies? the idea here is to enable non-tech users to support the network and offer services by offering them
 a software that can acts as a node

⏺ Yes, this is technically doable — and you don't even need traditional reverse proxies. Your libp2p relay infrastructure already solves this.

  What You Already Have

  Phone A ──→ Your Relay Server ←── Phone B
                (always on)

  The relay server is already acting as the "reverse proxy" — it gives every device a reachable address even behind home routers/firewalls.

  What You're Proposing

  Phone A ──→ Ali's Desktop Node ←── Phone B
                    │
                    │ (connects outbound to your relay
                    │  to get a public address)
                    ▼
              Your Relay Server
              (discovery only,
               less traffic now)

  Ali installs the desktop app → it connects to your relay → registers itself as available → friends' traffic can now route through Ali's desktop instead of your server.

  Ali's desktop IS the relay for his friend circle.

  Does This Create Real Value?

  This time, yes — unlike the phone model:

  ┌───────────────────┬─────────────────────────┬──────────────────────────┐
  │                   │          Phone          │         Desktop          │
  ├───────────────────┼─────────────────────────┼──────────────────────────┤
  │ Uptime            │ 2 hrs/day               │ 8-12 hrs/day             │
  ├───────────────────┼─────────────────────────┼──────────────────────────┤
  │ Background limits │ Severe (iOS kills it)   │ None                     │
  ├───────────────────┼─────────────────────────┼──────────────────────────┤
  │ Bandwidth         │ Mobile data, expensive  │ Home broadband, "free"   │
  ├───────────────────┼─────────────────────────┼──────────────────────────┤
  │ Storage           │ Limited, shared         │ Hundreds of GB available │
  ├───────────────────┼─────────────────────────┼──────────────────────────┤
  │ CPU               │ Busy running other apps │ Mostly idle              │
  └───────────────────┴─────────────────────────┴──────────────────────────┘

  A desktop running 10 hours a day on home broadband is a genuinely useful node. It can:

  - Relay messages for the friend circle all day
  - Cache media (photos, voice notes) for offline friends
  - Bridge connections between friends who can't reach each other
  - Store group message history so new members can catch up

  Making It Dead Simple for Non-Tech Users

  The key is: it should feel like installing Spotify, not running a server.

  The User Experience

  1. Download "Mknoon Desktop"
  2. Sign in (same account as phone)
  3. Toggle: "Support my friends' network"  ✓
  4. Done. Runs quietly in system tray.

  Behind the scenes:
  - App opens an outbound connection to your relay (no port forwarding, no router config, nothing)
  - Your relay says "Ali's desktop is reachable at this address"
  - Friends' devices learn about it and start routing through Ali when he's online
  - When Ali's desktop goes offline, traffic falls back to your server seamlessly

  The user never touches a config file, never opens a port, never sees a terminal.

  What You Save

  This is the business case. Every message that routes through Ali's desktop is a message your server doesn't have to handle.

  Say you have 10,000 users and 500 run desktop nodes covering their friend circles:

  Without desktop nodes:
    Your servers handle 100% of relay traffic
    Monthly server cost: $X

  With 500 desktop nodes:
    Each covers ~10 friends for ~10 hrs/day (~40% of the day)
    Your servers handle maybe 50-60% of traffic
    Monthly server cost: ~$0.5X - $0.6X

    Savings: 40-50% of infrastructure costs

  Those savings are real money you can share back with the desktop node runners. The economics are honest — they provide real infrastructure, you pay them real value.

  The Revised Earning Model

  Combine both layers — human value AND infrastructure:

  ┌─────────────────────────────────────────────┐
  │  How You Earn Noons                         │
  │                                             │
  │  Everyone (phone):                          │
  │    • Invite friends          (human value)  │
  │    • Stay active             (human value)  │
  │    • Offer services          (human value)  │
  │    • Host communities        (human value)  │
  │                                             │
  │  Desktop supporters:                        │
  │    • Relay messages          (infra value)  │
  │    • Cache media             (infra value)  │
  │    • Bridge connections      (infra value)  │
  │    • Store group history     (infra value)  │
  │                                             │
  │  Both are real. Both get paid.              │
  └─────────────────────────────────────────────┘

  One Honest Caveat

  You still need your relay servers as the guaranteed fallback. Desktop nodes go offline (user shuts laptop, internet drops, power outage). The promise to users must be:

  "Your messages always work. Desktop supporters make them faster and help the network grow — but nothing breaks if they go offline."

  Never build a critical path that depends on volunteer nodes. They're a bonus, not the backbone.

  ---
  Want me to start designing how this would integrate with your existing libp2p relay architecture in Go?