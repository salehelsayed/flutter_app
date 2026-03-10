A More Honest Model

  Instead of paying for technical infrastructure (which phones do poorly), pay for social infrastructure (which people do naturally):

  You earn Noons by:

  1. Bringing friends onto the app — you invited Ali, Ali stays active for 3 months → you earn Noons. Real value: you grew the network.
  2. Being responsive — you reply to friends within the day, you keep conversations going → small steady earning. Real value: you make the app worth opening.
  3. Offering services — you help a friend translate a document, tutor their kid, recommend a plumber → they pay you in Noons. Real value: actual human help.
  4. Hosting a community — you run an active group (local neighborhood, study group, hobby) → you earn based on group activity. Real value: you created a place people want to be.
  5. Vouching for trust — you verify a friend is who they say they are → strengthens the trust graph. Real value: makes the network safer.

  Where Does the Server Fit?

  You own the server. That's your business asset. The subscription pays for it. Don't give away infrastructure costs to phones that can barely help — instead, invest that 40% pool into rewarding the human behaviors that actually make or
   break a social app.

  Revised Revenue Flow

  User pays $5/month subscription
           │
           ├── 60% → Your operations (servers, dev, team)
           │
           └── 40% → Community Rewards Pool
                        │
                        ├── Referral rewards (brought friends)
                        ├── Activity rewards (kept friends engaged)
                        ├── Service payments (helped friends)
                        └── Community hosting rewards (ran active groups)

  The Bottom Line

  The phone-as-node idea sounds cool technically, but the real engine of a chat app is people being good to each other. Pay for that instead. It's honest, it's measurable, and it doesn't drain anyone's battery.

  Want me to flesh out this revised model with specific earning rates and rules?


  =====
# Question 1
For services that must remain continuously available (for example, an online mailbox), if users can choose their friends to store their messages, a fallback mechanism is needed.
What would be a meaningful fallback solution if those friends go offline for several hours while other people are trying to deliver messages to the user?

This is the right question. A single friend is a single point of failure. Here's how to make it reliable without giving up the friend-based model.

  The Core Idea: Don't Pick One Friend. Pick a Small Circle.

  Think of it like giving your house key to 3 friends, not 1. If one is out of town, another can check your mail.

  Someone sends you a message while you're offline
                      │
                      ▼
           ┌── Ali's Desktop       (keeper 1) ✓ online → stores it
           │
  Message ─┼── Sara's Desktop      (keeper 2) ✓ online → stores it
           │
           └── Omar's Desktop      (keeper 3) ✗ offline → skipped


  You come back online:
           → Pull from Ali   → got message
           → Pull from Sara  → same message (duplicate, skip)
           → Pull from Omar  → he's back too, but you already have it

  Same message goes to everyone who's available. You deduplicate when you collect. Simple, no coordination needed between keepers.

  Why 3 Keepers Is Enough

  ┌───────────────────┬──────────────────────────────────────┬────────────────────┐
  │  Keepers online   │ Probability (each online ~10hrs/day) │   Messages safe?   │
  ├───────────────────┼──────────────────────────────────────┼────────────────────┤
  │ All 3 offline     │ ~3% of the day                       │ No — need fallback │
  ├───────────────────┼──────────────────────────────────────┼────────────────────┤
  │ At least 1 online │ ~97% of the day                      │ Yes                │
  └───────────────────┴──────────────────────────────────────┴────────────────────┘

  With 3 friends who keep normal waking hours across even slightly different schedules, coverage is very good. But that 3% gap still matters — you need a fallback for it.

  The Escalation Ladder

  Message arrives for offline user
             │
             ▼
      ① Try all 3 keepers
             │
       ┌─────┴──────┐
       │             │
    At least      All 3
    one online    offline
       │             │
    Stored. ✓        ▼
                  ② Queue on YOUR server
                     (temporary holding —
                      not permanent storage)
                          │
                          ▼
                     When any keeper
                     comes online:
                          │
                     ③ Server pushes
                       queued messages
                       to keeper
                          │
                     ④ Server deletes
                       its copy

  Your server is not the mailbox. It's the safety net. It only holds messages when all 3 friends are down, and it hands them off to a keeper as soon as one wakes up. It's temporary, not permanent.

  What the User Sees

  In settings:

  ┌─────────────────────────────────┐
  │  My Mailbox Keepers             │
  │                                 │
  │  ● Ali        Desktop  🟢 online│
  │  ● Sara       Desktop  🟢 online│
  │  ● Omar       Desktop  🔴 offline│
  │                                 │
  │  Coverage: 2 of 3 online        │
  │  Status: Your mailbox is safe ✓ │
  │                                 │
  │  [+ Add Keeper]                 │
  │                                 │
  │  ─────────────────────────────  │
  │  Safety net: Mknoon servers     │
  │  (holds messages only when all  │
  │   keepers are offline)          │
  └─────────────────────────────────┘

  No technical jargon. Just "these friends are holding your mail" and a green/red status.

  Why This Beats a Pure Server Model

  ┌─────────────┬────────────────────────────────────────┬─────────────────────────────────────────────────┐
  │             │              Server only               │            Friends + server fallback            │
  ├─────────────┼────────────────────────────────────────┼─────────────────────────────────────────────────┤
  │ Privacy     │ Company stores all your messages       │ Friends store them (people you chose and trust) │
  ├─────────────┼────────────────────────────────────────┼─────────────────────────────────────────────────┤
  │ Cost to you │ Scales with every user                 │ Friends absorb most of the storage              │
  ├─────────────┼────────────────────────────────────────┼─────────────────────────────────────────────────┤
  │ Resilience  │ Server goes down = everyone loses mail │ Server goes down = friends still have it        │
  ├─────────────┼────────────────────────────────────────┼─────────────────────────────────────────────────┤
  │ Trust       │ "Trust the company"                    │ "Trust my friends"                              │
  └─────────────┴────────────────────────────────────────┴─────────────────────────────────────────────────┘

  One Important Rule: Keepers Can't Read the Messages

  This is critical. Friends store encrypted blobs, not readable messages. They're holding a locked box — they have no key.

  Sender encrypts message with YOUR public key
           │
           ▼
     Encrypted blob → stored on keeper's desktop
           │
           ▼
     You come online → download blob → YOUR device decrypts it

  Keepers provide storage, not access. Even if Ali is curious, all he sees is random bytes. You already have ML-KEM encryption in your app — this fits naturally.

  The Earning Angle

  Keepers earn Noons for this service based on:

  - Messages held — how many they stored
  - Time held — how long until you came to collect
  - Reliability — what percentage of the time they were available when needed

  This is measurable, honest, and real work. Your friend kept your mailbox running. They earned it.

  ---
  So in summary: 3 keepers, replicate to all, deduplicate on collect, server as temporary safety net, everything encrypted. Simple, reliable, and your friends actually earn their Noons.

