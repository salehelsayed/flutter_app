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

===

# Question 2: who then will get the money? both Ali and Sara ?
 Yes, both. They both did the work — they both stored the message and kept it safe until you came back.

  But the amount should reflect what they actually contributed, not just split 50/50.

  Fair Payment: Pay for What You Held and How Long

  You were offline for 3 hours.
  During that time, 10 messages arrived.

  Ali:  online the whole 3 hours → stored all 10 messages
  Sara: came online 1 hour in    → stored 7 messages
  Omar: offline the whole time   → stored 0 messages

  Payment:
    Ali:  10 messages × 3 hrs = 30 units  →  gets most
    Sara:  7 messages × 2 hrs = 14 units  →  gets some
    Omar:  0 messages × 0 hrs =  0 units  →  gets nothing

  Simple rule: you get paid for what you actually held, for how long you held it.

  This is fair because:
  - Ali was there from the start and caught everything — he earned the most
  - Sara showed up late but still helped — she earned less but not zero
  - Omar wasn't there — he earns nothing, and that's honest

  What About Duplicates? Am I Paying Double?

  You might think: "I'm paying two people to store the same message — isn't that wasteful?"

  No. You're paying for reliability, not storage. It's like insurance:

  You don't complain that your house didn't burn down and you paid insurance for nothing. You paid for the peace of mind that at least one copy of your messages would be there.

  If only Ali was your keeper and his internet went out at hour 2, you'd lose 3 messages. Sara being there as backup is what saved you. That backup has value.

  Keep It Cheap

  The total cost per message should be tiny — fractions of a Noon. Something like:

  ┌────────────────┬───────────┬────────────────────┐
  │ Messages/month │  Keepers  │    Monthly cost    │
  ├────────────────┼───────────┼────────────────────┤
  │ 500 messages   │ 3 keepers │ ~0.5 Noon (~$0.30) │
  ├────────────────┼───────────┼────────────────────┤
  │ 2,000 messages │ 3 keepers │ ~2 Noons (~$1.20)  │
  └────────────────┴───────────┴────────────────────┘

  Cheap enough that nobody thinks about it. Meaningful enough that keepers feel appreciated over time.

  This cost comes out of the subscription the user already pays — not as an extra charge. The subscription covers your mailbox keepers, just like it covers server costs today.

===
# Questin 3
If Sarah and Ali are both paid from the 40% of subscription revenue contributed by all users, how should storage be counted?

Should two keepers (Sarah and Ali) be treated as one logical storage unit, similar to a single server? For example, if there are 10 offline messages that are replicated and stored by both Sarah and Ali, should the payment for those 10 messages be split between them? Or should Sarah and Ali each be paid for storing 10 messages, even though the messages are duplicates?

 Great question. Treat them as 1 server. Split the price of 10 messages.

  Why

  The value to you is: 10 messages were kept safe. That's the job. That's what you're paying for.

  The duplication is a reliability mechanism, not extra work that deserves extra pay. Think of it this way:

  You need your couch moved. You hire 2 friends to carry it.
  You pay the moving fee once and split it — not pay each the full fee.
  The couch moved once, not twice.

  Same here. 10 messages were delivered to you once. Pay once, split by contribution.

  What Happens If You Pay Each the Full Price

  10 messages × 3 keepers = paying for 30 message-stores
  But only 10 messages actually exist

  With 10,000 users, each getting 500 messages/month:
    Actual messages:  5,000,000
    You're paying for: 15,000,000  ← 3x the real work

  The 40% pool drains 3x faster. Unsustainable.

  Worse — users would be incentivized to add more keepers just to multiply payouts. 5 keepers = 5x payout for the same 10 messages. The system gets gamed.

  The Right Calculation

  10 messages arrive while you're offline

  The job: "hold 10 messages" → costs 1 Noon (example)

  Ali:  held all 10 for 3 hours  → contribution: 30
  Sara: held 7 for 2 hours       → contribution: 14
                                     total: 44

  Ali gets:  30/44 × 1 Noon = 0.68 Noon
  Sara gets: 14/44 × 1 Noon = 0.32 Noon

  Total paid: 1 Noon (same as if your server did it)

  The Simple Rule

  1 job = 1 price, no matter how many keepers helped.

  This keeps your economics clean:

  ┌───────────────────────────┬─────────────────────┬──────────────────────┐
  │           Model           │ Cost of 10 messages │     Sustainable?     │
  ├───────────────────────────┼─────────────────────┼──────────────────────┤
  │ Your server               │ 1 Noon              │ Yes                  │
  ├───────────────────────────┼─────────────────────┼──────────────────────┤
  │ 3 keepers, each paid full │ 3 Noons             │ No — 3x server cost  │
  ├───────────────────────────┼─────────────────────┼──────────────────────┤
  │ 3 keepers, split the job  │ 1 Noon              │ Yes — same as server │
  └───────────────────────────┴─────────────────────┴──────────────────────┘

  The whole point of friend-nodes is to reduce your costs, not multiply them. If keepers cost more than your server, there's no business reason to have them.

  Will Keepers Feel Underpaid?

  No, because:

  1. They're earning from multiple friends — Ali isn't keeper for just you. He's keeper for 5-10 friends. Each pays a share. It adds up.
  2. It's passive — Ali's desktop just sits there. He's not doing manual work. Even small earnings for zero effort feel good.
  3. The alternative is zero — without this system, Ali's idle desktop earns nothing. Even 2-3 Noons/month for doing nothing is appealing.

====
