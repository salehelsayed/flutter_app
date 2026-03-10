 ---
  The Big Picture: "Be Valuable to Your Friends, Get Paid for It"

  Your app already has the foundation — friends connect peer-to-peer, relay messages for each other, and form circles. The monetization model should reward what's already happening naturally: friends helping friends stay connected.

  ---
  The Token: Noon (نون)

  Since mknoon (مكنون) means "treasured/precious" — Noon fits perfectly. A small, precious unit.

  Value: 1 Noon = a fixed weight of gold (e.g. 0.01 gram). Gold is understood worldwide, holds value across cultures, and doesn't swing wildly like Bitcoin. Users think in gold, not in crypto jargon.

  ---
  How Users Earn Noons — By Being a Good Friend

  In your libp2p network, every user's phone is a small node. When you're online, your device can help your friends. That help is worth money.

  1. Message Relay ("I'll hold that for you")

  When your friend is offline, your phone can temporarily store and forward their messages when they come back. Today your relay server does this — but friends' devices could share the load.

  - Friend goes offline → your phone holds their incoming messages
  - Friend comes back → your phone delivers them
  - You earn a tiny Noon for each message relayed

  2. Connection Bridge ("I'll help you connect")

  In libp2p, sometimes two people can't connect directly. A mutual friend's device can act as the bridge (circuit relay). You're already doing this with relay servers — now friends can do it for each other.

  - Your phone bridges a connection for a friend → you earn Noons
  - The more reliably online you are → the more you earn

  3. Media Hosting ("I'll keep your photo safe")

  Friends send photos, voice notes, videos. Instead of paying for cloud storage, friends' devices can cache media for each other.

  - You store 50MB of your friend's media → you earn Noons proportional to size + time held

  4. Services ("I can help you with that")

  This is the creative part — a friend-to-friend service marketplace:
  - Translation help, tutoring, local recommendations, design work
  - Friend posts "I need help with X" → friends in their circle can respond
  - Payment in Noons, within the trusted circle

  ---
  The Circle Model — Local First, Expand If You Want

  ┌─────────────────────────────────────┐
  │         Community Circle            │  ← opt-in, earn least per task
  │    ┌───────────────────────┐        │     but highest volume
  │    │    Extended Circle     │        │
  │    │   ┌───────────────┐   │        │
  │    │   │ Inner Circle   │   │        │  ← your direct friends
  │    │   │    (Friends)   │   │        │     earn the most here
  │    │   │   ┌───────┐    │   │        │     free to support
  │    │   │   │  You  │    │   │        │
  │    │   │   └───────┘    │   │        │
  │    │   └───────────────┘   │        │
  │    │  (Friends of Friends) │        │
  │    └───────────────────────┘        │
  └─────────────────────────────────────┘

  - Inner Circle (your friends): You support them automatically. Highest earning rate per task. This is the default.
  - Extended Circle (friends of friends): Opt-in. You see who they are through your mutual friend. Moderate earnings.
  - Community Circle (wider network): Opt-in. For power users who want to run a stronger node. Lower per-task rate but more volume.

  The key rule: You never lose opportunity in your inner circle. Your friends always get priority. Only spare capacity goes to outer circles.

  ---
  Where the Money Comes From — The Subscription Loop

    User pays subscription ($5/month)
             │
             ▼
      ┌──────────────┐
      │   App Revenue │
      │              │
      │  60% ──→ Operations (servers, development, team)
      │  40% ──→ Support Pool
      │              │
      └──────┬───────┘
             ▼
      ┌──────────────┐
      │  Support Pool │──→ Distributed as Noons to users
      │              │     who supported the network
      │              │     this month
      └──────────────┘

  This is what makes the token real — it's backed by actual subscription revenue converted to gold-equivalent value. It's not speculative; people paid real money, and that money flows to those who earned it.

  Example month:

  - 10,000 subscribers × $5 = $50,000
  - 40% to Support Pool = $20,000
  - Gold price = $60/gram → Pool buys ~333 grams worth of Noons
  - Distributed to all users based on their contribution score

  ---
  Contribution Score — Fair Distribution

  Each user's monthly earnings depend on:

  ┌───────────────────────┬────────┬──────────────────────────────┐
  │        Factor         │ Weight │             Why              │
  ├───────────────────────┼────────┼──────────────────────────────┤
  │ Messages relayed      │ 30%    │ Core network value           │
  ├───────────────────────┼────────┼──────────────────────────────┤
  │ Connection uptime     │ 25%    │ Reliability matters          │
  ├───────────────────────┼────────┼──────────────────────────────┤
  │ Media cached          │ 20%    │ Storage costs real resources │
  ├───────────────────────┼────────┼──────────────────────────────┤
  │ Services provided     │ 15%    │ Human value to friends       │
  ├───────────────────────┼────────┼──────────────────────────────┤
  │ Circle size supported │ 10%    │ Wider support = more reward  │
  └───────────────────────┴────────┴──────────────────────────────┘

  ---
  Send/Receive Money — The PayPal Part

  This is straightforward in the UI:

  - Send Noons: Open a friend's chat → tap "Send Noon" → enter amount → confirm. Uses your existing libp2p connection, no intermediary.
  - Receive Noons: Notification "Ali sent you 2.5 Noons" → balance updates instantly
  - Balance: Always shown in both Noons and local currency equivalent (via gold price)
  - Cash out: Convert Noons to local currency via a partner service (like how PayPal connects to your bank)

  ---
  Why This Model Works

  1. It's not abstract — you're not "mining" or "staking." You're helping your friend get their messages. That's real and understandable.
  2. It's local — your money stays in your circle. You earn from people you know, spend with people you trust. Like a village economy.
  3. It's stable — gold doesn't crash 40% overnight like crypto. Your 10 Noons today are worth roughly 10 Noons next month.
  4. It's sustainable — the money comes from subscriptions (real revenue), not speculation. The app makes money, shares it with the community. Simple.
  5. It scales naturally — as more friends join, each person's node becomes more valuable because there's more to relay/store/bridge. Growth rewards early supporters.

  ---
  What Would You Like to Do Next?

  Some options:
  - Design the data model — Noon wallet tables, transaction ledger, contribution tracking
  - Design the protocol — how Noon transfers work over libp2p
  - Build the UI — wallet screen, send/receive flow, earnings dashboard
  - Flesh out the economics — more detailed math on distribution, pricing, gold peg mechanics

  What feels right to start with?