Here's the honest picture and what I'd recommend:

  What You Have Now vs What You Need

  Your relay server currently tracks operational metrics
  (connections, messages, bytes) but not business metrics
  (users, engagement, retention). The core problem: every peer
  connection looks the same — there's no concept of "new user"
  vs "returning user."

  The 3 Metrics That Matter for a Business Plan

  1. Total Users (Cumulative Signups)

  Proxy: unique peers who have ever uploaded a profile

  Your profile.go stores profile blobs to disk at
  /data/profiles/{peerId}.blob. The number of files there =
  total users who ever set up a profile. But you can't tell
  when each one was created over time.

  What to add: A relay_profile_first_upload_total counter that
  only increments when a peer uploads a profile for the first
  time (file doesn't already exist). This gives you a new user
  signups over time graph.

  2. Daily / Weekly / Monthly Active Users (DAU/WAU/MAU)

  This is the number investors and business plans care about
  most.

  Currently impossible — relay_connections_total counts
  connection events, not unique users. One user reconnecting 10
   times counts as 10.

  What to add: A relay_unique_peers_daily gauge that tracks
  unique peer IDs seen per day (using an in-memory set that
  resets at midnight). This gives you DAU. Prometheus can then
  derive WAU/MAU using max_over_time().

  3. Engagement Depth (Messages per Active User)

  Shows whether users actually use the app, not just open it.

  You have relay_inbox_stored_total (170 lifetime messages) and
   relay_media_uploaded_total (24), but no per-user breakdown.

  What to add: A daily message counter that, combined with DAU,
   gives you messages per user per day — the single best
  engagement metric.

  ---
  What I'd Build — A Single New File: business_metrics.go

  The implementation would add these Prometheus metrics:

  Metric: relay_unique_peers_daily
  Type: Gauge
  What It Tells You: DAU — unique peers connected today
  ────────────────────────────────────────
  Metric: relay_unique_peers_seen_total
  Type: Counter
  What It Tells You: Total users ever — cumulative unique peers
  ────────────────────────────────────────
  Metric: relay_new_users_total
  Type: Counter
  What It Tells You: New signups over time — first-time profile

    uploads
  ────────────────────────────────────────
  Metric: relay_messages_daily
  Type: Gauge
  What It Tells You: Messages sent today (resets at midnight)
  ────────────────────────────────────────
  Metric: relay_push_tokens_by_platform
  Type: Gauge, label: platform
  What It Tells You: iOS vs Android user split

  With these, the Grafana dashboard would show:

  ┌────────────────┬───────────────────────────────────────┐
  │ Business Panel │                PromQL                 │
  ├────────────────┼───────────────────────────────────────┤
  │ DAU            │ relay_unique_peers_daily              │
  ├────────────────┼───────────────────────────────────────┤
  │ WAU            │ max_over_time(relay_unique_peers_dail │
  │                │ y[7d])                                │
  ├────────────────┼───────────────────────────────────────┤
  │ New Users      │ increase(relay_new_users_total[1d])   │
  │ Today          │                                       │
  ├────────────────┼───────────────────────────────────────┤
  │ Total Users    │ relay_unique_peers_seen_total         │
  ├────────────────┼───────────────────────────────────────┤
  │ Messages/User/ │ relay_messages_daily /                │
  │ Day            │ relay_unique_peers_daily              │
  ├────────────────┼───────────────────────────────────────┤
  │ iOS vs Android │ relay_push_tokens_by_platform         │
  ├────────────────┼───────────────────────────────────────┤
  │ User Growth    │ rate(relay_unique_peers_seen_total[7d │
  │ Rate           │ ]) * 86400                            │
  └────────────────┴───────────────────────────────────────┘

  ---
  Honest Assessment for Your Business Plan

  Right now with the raw numbers on your server:
  - 13 profiles on disk = ~13 total users ever
  - 1 push token registered = 1 active install with
  notifications
  - 2 active connections right now
  - 170 messages lifetime, 24 media uploads lifetime

  These are early-stage numbers. The metrics I described above
  would let you show a growth curve and engagement trend over
  time — which is what matters in a business plan, not absolute
   numbers.



   ====
    I want to make sure that i'm not violating privacy policy or
 anything or measuring anything that tracks user behavior or
creates profiles. would that be ok?

⏺ Great instinct — this is worth thinking through carefully
  before building anything.

  What's at stake

  Libp2p peer IDs are pseudonymous identifiers (derived from
  cryptographic keys). Under GDPR, CCPA, and most privacy
  frameworks, pseudonymous IDs that can be linked to a person
  are personal data. So:

  ┌──────────────────────┬─────────────────────────────────┐
  │   Proposed Metric    │          Privacy Risk           │
  ├──────────────────────┼─────────────────────────────────┤
  │                      │ Yes — this is behavioral        │
  │ Storing peer IDs in  │ tracking. You're recording      │
  │ a set for DAU        │ which identifiers were active   │
  │                      │ and when.                       │
  ├──────────────────────┼─────────────────────────────────┤
  │ "First-seen"         │ Yes — creates a user profile    │
  │ detection per peer   │ (identity + first appearance    │
  │ ID                   │ timestamp).                     │
  ├──────────────────────┼─────────────────────────────────┤
  │ Messages per user    │ Yes — per-user behavioral       │
  │ per day              │ profiling.                      │
  ├──────────────────────┼─────────────────────────────────┤
  │ Platform breakdown   │ Low risk — aggregate counts, no │
  │ (iOS/Android)        │  individual association.        │
  ├──────────────────────┼─────────────────────────────────┤
  │ Pure counters (total │ No risk — no individual         │
  │  messages, total     │ identifiers involved.           │
  │ uploads)             │                                 │
  └──────────────────────┴─────────────────────────────────┘

  What's safe: Aggregate-only metrics

  You can get meaningful business numbers without tracking any
  individual peer ID by counting things, not people:

  Metric: Total users ever
  How: Count profile files on disk: relay_profile_count
  Why It's Safe: Already exists. Just counts files — no
  tracking
    of who or when.
  ────────────────────────────────────────
  Metric: New signups over time
  How: Increment a counter when a profile file is created (not
    updated)
  Why It's Safe: Only records "a new profile appeared" — not
    which peer ID.
  ────────────────────────────────────────
  Metric: App activity level
  How: rate(relay_connections_total[1d])
  Why It's Safe: Counts connection events, not people. One user

    reconnecting 10x = 10, but that's fine for trend analysis.
  ────────────────────────────────────────
  Metric: Messaging volume
  How: rate(relay_inbox_stored_total[1d])
  Why It's Safe: Total messages flowing through — no per-user
    association.
  ────────────────────────────────────────
  Metric: Media adoption
  How: rate(relay_media_uploaded_total[1d])
  Why It's Safe: Same — aggregate count.
  ────────────────────────────────────────
  Metric: Push reach
  How: relay_inbox_push_tokens
  Why It's Safe: Count of registered tokens, no identity tied
  to
    it.
  ────────────────────────────────────────
  Metric: Platform split
  How: Push tokens by platform (iOS/Android count)
  Why It's Safe: Aggregate only.

  Estimated DAU without tracking individuals

  If you want a DAU estimate without storing peer IDs, you can
  use a HyperLogLog — a probabilistic data structure that
  estimates cardinality (unique count) without storing the
  actual identifiers. The peer ID is hashed and only a few bits
   are kept. You cannot reconstruct who connected.

  - Accuracy: ~2% error margin
  - Memory: ~12 KB regardless of user count
  - Privacy: the actual peer IDs are not recoverable from the
  data structure
  - Resets daily — nothing persists

  This is the same technique Google Analytics, Cloudflare, and
  other privacy-conscious systems use for unique visitor
  counting.

  My recommendation

  Build aggregate-only counters + HyperLogLog for DAU estimate.
   This gives you:

  - New user growth curve (profile creation counter)
  - DAU trend (HyperLogLog, no stored IDs)
  - Activity trends (message/media volume)
  - Platform split
  - Total user base (profile file count)

  Zero individual tracking. No stored peer IDs. No behavioral
  profiles. No privacy policy headaches.