Yes, there is a real, architectural difference. Posts are genuinely slower by design. Here's why:

  ---
  1. Optimistic UI — the biggest perceived difference

  ┌──────────┬────────────────────────────────────────────────────────────────────────────────┬─────────────────────────────────┐
  │ Feature  │                                 Optimistic UI?                                 │       What the user sees        │
  ├──────────┼────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────┤
  │ 1:1 Chat │ Yes — message appears instantly with "sending" status before any network call  │ Message shows up immediately    │
  ├──────────┼────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────┤
  │ Group    │ Yes — same pattern, instant insert with "sending" status                       │ Message shows up immediately    │
  │ Chat     │                                                                                │                                 │
  ├──────────┼────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────┤
  │          │ Partial — post is saved to DB as "sending" (may appear in feed), but the       │ User stares at a spinner until  │
  │ Posts    │ compose sheet stays open with a disabled "Posting..." button until the entire  │ all recipients are processed    │
  │          │ send completes                                                                 │                                 │
  └──────────┴────────────────────────────────────────────────────────────────────────────────┴─────────────────────────────────┘

  In chat, you tap send → message appears → you can type the next one. In Posts, you tap Post → the sheet blocks → you wait.

  ---
  2. Per-recipient serial loop (Posts only)

  ┌───────────┬───────────────────────────────────────────────────────────────────────────────┬────────────────────────────────┐
  │  Feature  │                                Delivery model                                 │        Time complexity         │
  ├───────────┼───────────────────────────────────────────────────────────────────────────────┼────────────────────────────────┤
  │ 1:1 Chat  │ Single target. Race: local WiFi vs direct, then relay fallback                │ O(1) — one peer                │
  ├───────────┼───────────────────────────────────────────────────────────────────────────────┼────────────────────────────────┤
  │ Group     │ Single topic.Publish() to GossipSub + one concurrent inbox:store              │ O(1) — one publish             │
  │ Chat      │                                                                               │                                │
  ├───────────┼───────────────────────────────────────────────────────────────────────────────┼────────────────────────────────┤
  │ Posts     │ Serial loop over every recipient: encrypt → direct send (4s timeout) → inbox  │ O(N) — up to 4+ seconds per    │
  │           │ fallback, one by one                                                          │ recipient                      │
  └───────────┴───────────────────────────────────────────────────────────────────────────────┴────────────────────────────────┘

  With 10 friends, a post can take 40+ seconds in the worst case (all offline, each hitting the 4-second direct-send timeout before
  falling back to inbox). Chat messages never have this problem.

  ---
  3. Media processing in the critical path (Posts)

  ┌──────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │ Feature  │                                            Media handling during send                                            │
  ├──────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 1:1 Chat │ Media uploaded before the send use case is called (in the wired layer). If upload fails, send is aborted early   │
  ├──────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Group    │ Same — media uploaded in wired layer before use case                                                             │
  │ Chat     │                                                                                                                  │
  ├──────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Posts    │ EXIF stripping + compression + media:upload all happen inside sendPost, while the compose sheet is blocked. Each │
  │          │  image goes through flutter_image_compress (native) then Go bridge upload                                        │
  └──────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  4. Encryption overhead

  ┌────────────┬──────────────────────────────────────────────────────────────────────────────┐
  │  Feature   │                                  Encryption                                  │
  ├────────────┼──────────────────────────────────────────────────────────────────────────────┤
  │ 1:1 Chat   │ One callEncryptMessage call (ML-KEM-768 + AES-256-GCM)                       │
  ├────────────┼──────────────────────────────────────────────────────────────────────────────┤
  │ Group Chat │ One symmetric AES-256-GCM encrypt + Ed25519 sign (fast, done Go-side)        │
  ├────────────┼──────────────────────────────────────────────────────────────────────────────┤
  │ Posts      │ One callEncryptMessage per recipient — N bridge round-trips for N recipients │
  └────────────┴──────────────────────────────────────────────────────────────────────────────┘

  ---
  5. No send-queue / background delivery (Posts)

  Chat sends are fire-and-forget from the user's perspective (optimistic UI). Posts have no background send queue — everything is
  awaited inline. The compose sheet has no timeout guard, so if network is slow, the user is stuck indefinitely.

  ---
  Summary of root causes (ranked by impact)

  1. Compose sheet blocks until full completion — no optimistic dismiss
  2. Serial per-recipient loop — O(N) × 4s timeout vs O(1)
  3. Per-recipient encryption — N bridge round-trips
  4. Media processing inline — EXIF strip + compress + upload during blocked send
  5. No background send queue — everything synchronous in the UI callback