❯ If I enable users to pay subscriptions , what can students and GenZ actually affrod per month for such an app?

⏺ This is more of a market/business question than technical, but here's what the data shows:

  What Gen Z / students actually pay

  ┌──────────────────┬───────────────────────────────────────────┬─────────────────────────────────────────────────────────┐
  │   Price point    │                Willingness                │                        Examples                         │
  ├──────────────────┼───────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ Free             │ Everyone                                  │ Most messaging apps                                     │
  ├──────────────────┼───────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ $0.99 - $1.99/mo │ High — "coffee money"                     │ iCloud 50GB, add-on stickers                            │
  ├──────────────────┼───────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ $2.99 - $4.99/mo │ Moderate — if clear value                 │ Spotify student ($5.99), Discord Nitro Basic ($2.99)    │
  ├──────────────────┼───────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ $5.99 - $9.99/mo │ Low — needs strong justification          │ YouTube Premium student ($7.99), Notion ($4/mo student) │
  ├──────────────────┼───────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ $10+/mo          │ Very low — competing with Spotify/Netflix │ Most won't pay this                                     │
  └──────────────────┴───────────────────────────────────────────┴─────────────────────────────────────────────────────────┘

  The sweet spot for your app

  Your infra cost per user is tiny — €12/mo for 3 nodes supporting ~15,000+ users. That's < $0.001 per user/month.

  ┌───────┬──────────┬──────────────────────────────────────────────────────────────┐
  │ Tier  │  Price   │                        What they get                         │
  ├───────┼──────────┼──────────────────────────────────────────────────────────────┤
  │ Free  │ $0       │ Core messaging, basic relay access                           │
  ├───────┼──────────┼──────────────────────────────────────────────────────────────┤
  │ Pro   │ $1.99/mo │ Larger media uploads, priority relay, longer inbox retention │
  ├───────┼──────────┼──────────────────────────────────────────────────────────────┤
  │ Group │ $3.99/mo │ Larger groups, more storage, custom features                 │
  └───────┴──────────┴──────────────────────────────────────────────────────────────┘

  Why $1.99 works

  - 100 paying users at $1.99 = $199/mo — covers your entire infrastructure many times over
  - It's below the "do I really need this?" threshold for students
  - Annual option ($19.99/yr = $1.67/mo) increases conversion
  - Gen Z will pay if the free tier has a real limitation, not an artificial paywall

  What NOT to do

  - Don't gate core messaging behind a paywall — users leave
  - Don't charge for things that cost you nothing (custom themes, etc.) — feels exploitative
  - Don't use ads as the alternative — Gen Z hates ads more than paying

  What works as paid features for your architecture

  Since you control the relay server, natural paid tiers map to real resource usage:

  ┌─────────────────────────┬─────────────┬──────────────────┬───────────────────┐
  │         Feature         │    Free     │       Paid       │  Costs you more?  │
  ├─────────────────────────┼─────────────┼──────────────────┼───────────────────┤
  │ Inbox message retention │ 24 hours    │ 30 days          │ Yes (RAM/storage) │
  ├─────────────────────────┼─────────────┼──────────────────┼───────────────────┤
  │ Media upload size       │ 5MB         │ 50MB             │ Yes (disk)        │
  ├─────────────────────────┼─────────────┼──────────────────┼───────────────────┤
  │ Group inbox size        │ 50 messages │ 500 messages     │ Yes (RAM)         │
  ├─────────────────────────┼─────────────┼──────────────────┼───────────────────┤
  │ Relay priority          │ Best-effort │ Priority routing │ Minimal           │
  ├─────────────────────────┼─────────────┼──────────────────┼───────────────────┤
  │ Offline message queue   │ 10 messages │ Unlimited        │ Yes (storage)     │
  └─────────────────────────┴─────────────┴──────────────────┴───────────────────┘

  These limits already exist in your ServerLimits config — you could enforce them per-user based on subscription status.

  
⏺ A few models that actually work:

  1. Pay-what-you-can

  Let users choose their own price ($0 - $5). Bandcamp proved this works — some people pay more than the minimum, which subsidizes those who pay nothing. Simple to implement, no gatekeeping.

  2. Earn access

  Give users a way to "earn" Pro features without money:

  ┌─────────────────────────────────────┬──────────────┐
  │               Action                │    Reward    │
  ├─────────────────────────────────────┼──────────────┤
  │ Invite 3 friends who stay active    │ 1 month Pro  │
  ├─────────────────────────────────────┼──────────────┤
  │ Report a bug that gets fixed        │ 1 month Pro  │
  ├─────────────────────────────────────┼──────────────┤
  │ Translate the app to a new language │ 6 months Pro │
  ├─────────────────────────────────────┼──────────────┤
  │ Create content/tutorials            │ Pro status   │
  └─────────────────────────────────────┴──────────────┘

  This costs you almost nothing (your infra cost per user is < $0.001) and grows your user base.

  3. Student verification

  Free Pro for verified students (via email .edu domain or SheerID). Students tell their friends — it's how Spotify, Notion, and GitHub grew. When they graduate and earn money, they're already hooked.

  4. Regional pricing

  $1.99 in the US is very different from $1.99 in Egypt or India. Adjust by country:

  ┌─────────────────────────┬───────────────┐
  │         Region          │     Price     │
  ├─────────────────────────┼───────────────┤
  │ US / EU / UK            │ $1.99         │
  ├─────────────────────────┼───────────────┤
  │ Latin America / SE Asia │ $0.49 - $0.99 │
  ├─────────────────────────┼───────────────┤
  │ Africa / South Asia     │ $0.29 - $0.49 │
  ├─────────────────────────┼───────────────┤
  │ Students anywhere       │ Free          │
  └─────────────────────────┴───────────────┘

  Apple and Google both support regional pricing on their app stores.

  5. Community-funded

  Add an option for paying users to "gift" Pro to someone. A simple button: "Give Pro to someone who can't afford it". People love this — it feels good to give, and it creates community loyalty.

  The honest truth

  Your infrastructure for 10,000 users costs ~$13/mo. If just 7 people pay $1.99/mo, you've covered your entire server costs. You don't need everyone to pay. You need:

  - A large free user base (network effect, word of mouth)
  - A small percentage (~2-5%) who pay because they want to, not because they have to
  - Zero guilt for those who can't

  The best approach: make the free tier genuinely good, and let paying be a choice, not a requirement. The people who can pay will pay to support something they like — especially Gen Z, who are very intentional about supporting creators
   and products they believe in.



===

# Business Model:
  The pitch in one line

  "Privacy-first messaging where no one — not even us — can read your messages. Built on peer-to-peer technology."

  That's what investors care about: a defensible position in a massive market.

  Revenue layers (not just subscriptions)

  Layer 1: Consumer subscriptions (B2C)

  Your baseline. But frame it as supporting privacy, not paying for features:

  ┌───────────┬──────────┬──────────────────────────────────────────────────────────────────┐
  │   Tier    │  Price   │                           Positioning                            │
  ├───────────┼──────────┼──────────────────────────────────────────────────────────────────┤
  │ Free      │ $0       │ Full messaging, relay access                                     │
  ├───────────┼──────────┼──────────────────────────────────────────────────────────────────┤
  │ Supporter │ $1.99/mo │ "Support private messaging" + larger media, longer offline inbox │
  ├───────────┼──────────┼──────────────────────────────────────────────────────────────────┤
  │ Pro       │ $4.99/mo │ Priority relay, large groups, custom domains for groups          │
  └───────────┴──────────┴──────────────────────────────────────────────────────────────────┘

  Realistic target: 5% conversion rate on a free user base.

  ┌───────────┬─────────────┬─────────────────────┐
  │   Users   │ Paying (5%) │   Monthly revenue   │
  ├───────────┼─────────────┼─────────────────────┤
  │ 10,000    │ 500         │ $1,000 - $2,500     │
  ├───────────┼─────────────┼─────────────────────┤
  │ 100,000   │ 5,000       │ $10,000 - $25,000   │
  ├───────────┼─────────────┼─────────────────────┤
  │ 1,000,000 │ 50,000      │ $100,000 - $250,000 │
  └───────────┴─────────────┴─────────────────────┘

  Layer 2: Business/Team plans (B2B) — where the real money is

  Companies and organizations will pay much more for private, decentralized communication:

  ┌─────────────────────────┬──────────────────────────────────────────────────┬────────────────┐
  │         Segment         │                  Why they care                   │     Price      │
  ├─────────────────────────┼──────────────────────────────────────────────────┼────────────────┤
  │ Journalists / activists │ Censorship-resistant, no server logs             │ $9.99/user/mo  │
  ├─────────────────────────┼──────────────────────────────────────────────────┼────────────────┤
  │ Healthcare teams        │ HIPAA-friendly (no data at rest on servers)      │ $14.99/user/mo │
  ├─────────────────────────┼──────────────────────────────────────────────────┼────────────────┤
  │ Legal firms             │ Attorney-client privilege, no third-party access │ $19.99/user/mo │
  ├─────────────────────────┼──────────────────────────────────────────────────┼────────────────┤
  │ Schools / universities  │ Student privacy (FERPA compliance)               │ $2.99/user/mo  │
  ├─────────────────────────┼──────────────────────────────────────────────────┼────────────────┤
  │ DAOs / crypto teams     │ Decentralized ethos matches their values         │ $9.99/user/mo  │
  └─────────────────────────┴──────────────────────────────────────────────────┴────────────────┘

  A single 50-person law firm paying $20/user/mo = $1,000/mo from one client. That's 500 free consumer users' worth of revenue from one sale.

  Layer 3: API / Infrastructure (B2B2C)

  Other developers want to build on private p2p messaging too. Sell access to your relay network:

  ┌──────────────────────────────────────────────────────────┬────────────────────────────────────┐
  │                         Product                          │               Price                │
  ├──────────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ Relay-as-a-Service API                                   │ $49 - $499/mo based on connections │
  ├──────────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ White-label SDK (embed your p2p messaging in other apps) │ $999/mo + per-user fee             │
  ├──────────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ Managed relay nodes for enterprises                      │ $199/node/mo                       │
  └──────────────────────────────────────────────────────────┴────────────────────────────────────┘

  This is where investor interest really kicks in — it turns you from "an app" into "infrastructure."

  What investors want to see

  ┌───────────────────────┬─────────────────────────┬─────────────────────────────────┐
  │        Metric         │     What it proves      │           Your target           │
  ├───────────────────────┼─────────────────────────┼─────────────────────────────────┤
  │ MAU growth rate       │ Product-market fit      │ 20%+ month-over-month           │
  ├───────────────────────┼─────────────────────────┼─────────────────────────────────┤
  │ Retention (Day 30)    │ Users stick around      │ > 40%                           │
  ├───────────────────────┼─────────────────────────┼─────────────────────────────────┤
  │ Conversion rate       │ Willingness to pay      │ > 3%                            │
  ├───────────────────────┼─────────────────────────┼─────────────────────────────────┤
  │ CAC (cost to acquire) │ Efficient growth        │ < $2 (organic/viral)            │
  ├───────────────────────┼─────────────────────────┼─────────────────────────────────┤
  │ LTV (lifetime value)  │ Business sustainability │ > $30                           │
  ├───────────────────────┼─────────────────────────┼─────────────────────────────────┤
  │ Gross margin          │ Scalable business       │ > 80% (your infra cost is tiny) │
  └───────────────────────┴─────────────────────────┴─────────────────────────────────┘

  Your gross margin is insane — $13/mo in infra supports 15,000+ users. That's > 95% margin. Investors love that.

  The investor story (3 stages)

  Stage 1: Pre-seed / Angel ($50K - $200K)

  - "We built a working p2p messaging app on libp2p"
  - "We have X users with Y% retention"
  - "Our infra cost per user is < $0.001"
  - Use funds for: growth, app polish, App Store presence

  Stage 2: Seed ($500K - $2M)

  - "We have 50,000+ users, 5% paying, $X MRR"
  - "We're launching B2B plans for privacy-sensitive industries"
  - "We're building the relay API platform"
  - Use funds for: team, B2B sales, multi-region infra

  Stage 3: Series A ($3M - $10M)

  - "We're the privacy messaging standard"
  - "X companies use our B2B product"
  - "Our API powers messaging in Y third-party apps"
  - Use funds for: scale, enterprise sales team, compliance certs

  Competitive positioning

  ┌─────────────┬─────────────────────────┬─────────────────────────────────────────────┐
  │     App     │          Model          │               Your advantage                │
  ├─────────────┼─────────────────────────┼─────────────────────────────────────────────┤
  │ Signal      │ Donations, no revenue   │ You actually make money                     │
  ├─────────────┼─────────────────────────┼─────────────────────────────────────────────┤
  │ Telegram    │ Freemium + ads          │ You have no ads, true p2p                   │
  ├─────────────┼─────────────────────────┼─────────────────────────────────────────────┤
  │ WhatsApp    │ Meta-owned, data mining │ You can't mine data even if you wanted to   │
  ├─────────────┼─────────────────────────┼─────────────────────────────────────────────┤
  │ Slack/Teams │ B2B subscription        │ You're decentralized, no server breach risk │
  └─────────────┴─────────────────────────┴─────────────────────────────────────────────┘

  My recommendation: Start here

  1. Launch free — grow the user base, prove retention
  2. Add Supporter tier ($1.99/mo) — prove willingness to pay
  3. Build the B2B plan — this is your real revenue engine
  4. Pitch investors with — "p2p infrastructure company" not "messaging app"

  The messaging app is your distribution channel. The relay infrastructure and privacy platform is the business. That's what's fundable

  ====

