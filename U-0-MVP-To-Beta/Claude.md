 MkNoon MVP: Focus Group Readiness Assessment

  1. What's Missing for Focus Group Testing?

  Your app is remarkably feature-complete for an MVP. Here's the honest gap analysis:

  Already Built (Core MVP is done)

  - Identity creation/restoration with 12-word mnemonic
  - QR-based contact exchange with signature verification
  - 1:1 E2E encrypted messaging (ML-KEM-768 post-quantum)
  - Text, image, video, voice messages with EXIF stripping
  - Multi-path delivery: WiFi local -> Relay -> Inbox (offline)
  - Push notifications (FCM)
  - Feed, Conversation (letter cards), Orbit (contacts), Settings
  - Message retry/resilience, reactions, quote-reply
  - SQLCipher encrypted database, secrets in secure storage
  - 245+ test files with strong coverage

  Critical Gaps (Fix Before Focus Group)

  ┌────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────┬──────────┐
  │                      Gap                       │                                  Why It Matters                                  │  Effort  │
  ├────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────┤
  │ Relay inbox is in-memory only                  │ Messages lost if relay server restarts. Users will lose messages during testing. │ 2-3 days │
  ├────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────┤
  │ No message deduplication on receive            │ Retry + inbox fallback can deliver duplicates. Users see double messages.        │ 1 day    │
  ├────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────┤
  │ No loading skeletons/spinners                  │ Screens appear blank during load, users think app is broken.                     │ 1-2 days │
  ├────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────┤
  │ No CI/CD pipeline                              │ You need reliable builds for TestFlight/Play Store internal testing.             │ 1 day    │
  ├────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────┼──────────┤
  │ 4 failing tests (onAddressesUpdated interface) │ Must be green before distributing builds.                                        │ 0.5 day  │
  └────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────┴──────────┘

  High-Priority Polish (Fix During Week 1-2)

  ┌──────────────────────────────────┬───────────────────────────────────────────────────────┐
  │               Gap                │                        Impact                         │
  ├──────────────────────────────────┼───────────────────────────────────────────────────────┤
  │ No delivery status comprehension │ Users don't know if message was sent/delivered/read   │
  ├──────────────────────────────────┼───────────────────────────────────────────────────────┤
  │ No error recovery buttons        │ Snackbar errors vanish with no "Retry" action         │
  ├──────────────────────────────────┼───────────────────────────────────────────────────────┤
  │ No haptic feedback               │ App feels "dead" on iOS without haptics on send/react │
  ├──────────────────────────────────┼───────────────────────────────────────────────────────┤
  │ Missing basic a11y               │ Only 2 semantic labels in entire codebase             │
  ├──────────────────────────────────┼───────────────────────────────────────────────────────┤
  │ Dark theme only                  │ Some testers may struggle in bright environments      │
  └──────────────────────────────────┴───────────────────────────────────────────────────────┘

  NOT Needed for Focus Group (Don't Build These)

  - Group messaging, message search, typing indicators, video calls, stickers/GIFs, message deletion/editing, disappearing messages, localization, desktop polish

  ---
  2. How Many Focus Groups?

  4 groups, structured as distinct segments:

  ┌─────────┬────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────┐
  │  Group  │                  Composition                   │                                        Purpose                                         │
  ├─────────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────┤
  │ Group A │ Privacy-motivated users (Signal/VPN users)     │ Stress-test trust signals, encryption comprehension, "why switch from Signal?"         │
  ├─────────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────┤
  │ Group B │ Privacy-motivated users (different cohort)     │ Validate Group A findings aren't artifacts of group dynamics                           │
  ├─────────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────┤
  │ Group C │ Mainstream messenger users (WhatsApp/iMessage) │ Test onboarding accessibility, first-impression friction, "would you actually switch?" │
  ├─────────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────┤
  │ Group D │ Mainstream messenger users (different cohort)  │ Validate Group C findings                                                              │
  └─────────┴────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────┘

  Optional 5th group: Less tech-savvy participants. This is where your QR contact exchange and mnemonic identity will be most challenged.

  Optional 6th "group": 3-4 dyad sessions (pairs of real contacts testing actual send/receive together). This is essential for a messaging app because you need to observe the two-sided interaction — one person sends, the other receives,
   on different networks.

  Run groups until saturation — when a new group stops producing new insights. This typically happens around group 4-5.

  ---
  3. How Many People Per Group?

  5-6 participants per group. Recruit 7-8 to account for no-shows (15-20% drop rate).

  ┌────────────────────────┬───────────────────────────────────┐
  │       Parameter        │          Recommendation           │
  ├────────────────────────┼───────────────────────────────────┤
  │ Per group              │ 5-6 seated (recruit 7-8)          │
  ├────────────────────────┼───────────────────────────────────┤
  │ Total across 4 groups  │ 20-24 participants                │
  ├────────────────────────┼───────────────────────────────────┤
  │ Dyad sessions          │ 3-4 pairs (6-8 additional people) │
  ├────────────────────────┼───────────────────────────────────┤
  │ Grand total to recruit │ ~30-35 people                     │
  ├────────────────────────┼───────────────────────────────────┤
  │ Session length         │ 90 minutes per group              │
  ├────────────────────────┼───────────────────────────────────┤
  │ Incentive              │ $75-150 per participant           │
  └────────────────────────┴───────────────────────────────────┘

  Composition rules:
  - Within each group: strangers (friends create deference/inside joke dynamics)
  - Platform mix: both iOS and Android users in every group
  - Age spread: at least two age bands (18-30 and 31-50)
  - Half should be from general consumer pools (not tech meetups or your network)

  ---
  4. What Feedback, Metrics, and KPIs to Track

  Quantitative Metrics (During Sessions)

  Task completion rates (the most important metric):

  ┌──────────────────────────────┬─────────────┬────────────────────────┐
  │             Task             │ MVP Target  │   Failing Threshold    │
  ├──────────────────────────────┼─────────────┼────────────────────────┤
  │ Create identity              │ >90%        │ <70% = redesign        │
  ├──────────────────────────────┼─────────────┼────────────────────────┤
  │ Add contact via QR scan      │ >75%        │ <60% = redesign        │
  ├──────────────────────────────┼─────────────┼────────────────────────┤
  │ Send a text message          │ >95%        │ <85% = critical        │
  ├──────────────────────────────┼─────────────┼────────────────────────┤
  │ Read a received message      │ >95%        │ <85% = critical        │
  ├──────────────────────────────┼─────────────┼────────────────────────┤
  │ Understand encryption status │ >60%        │ <40% = trust problem   │
  ├──────────────────────────────┼─────────────┼────────────────────────┤
  │ Complete onboarding flow     │ <90 seconds │ >3 min = drop-off risk │
  └──────────────────────────────┴─────────────┴────────────────────────┘

  Time-to-first-value funnel:
  1. App open -> Identity created: <30 seconds
  2. Identity -> First contact added: <2 minutes
  3. Contact added -> First message sent: <60 seconds
  4. First message -> First reply received: <30 seconds

  Qualitative Feedback (What to Listen For)

  High-signal questions:
  - "Did that work the way you expected?" (after each task)
  - "How confident are you that nobody else can read this message?" (1-10, at 1-min, 5-min, 10-min marks — target 7+ by 5 minutes)
  - "Would you install this tomorrow? Who's the first person you'd message?" (specificity = real intent)
  - "What would make you use this daily?" and "What almost made you give up?"

  Written-before-discussion technique: For key questions, have everyone write answers on cards before group discussion. This prevents groupthink from a dominant voice.

  Frameworks to Use

  ┌──────────────────────────────┬───────────────────────────────────────────────┬───────────────────────┐
  │          Framework           │               What It Measures                │         When          │
  ├──────────────────────────────┼───────────────────────────────────────────────┼───────────────────────┤
  │ SUS (System Usability Scale) │ Overall usability (target >65 for MVP)        │ Post-session          │
  ├──────────────────────────────┼───────────────────────────────────────────────┼───────────────────────┤
  │ UMUX-Lite                    │ 2-question fast usability check               │ After each task block │
  ├──────────────────────────────┼───────────────────────────────────────────────┼───────────────────────┤
  │ Switching Intent Scale (1-7) │ Willingness to adopt (target 4+ from >30%)    │ Post-session          │
  ├──────────────────────────────┼───────────────────────────────────────────────┼───────────────────────┤
  │ Perceived Security Scale     │ Trust in encryption (3 questions, 1-7 each)   │ Post-session          │
  ├──────────────────────────────┼───────────────────────────────────────────────┼───────────────────────┤
  │ NPS                          │ Recommendation likelihood (target >0 for MVP) │ Post-session          │
  └──────────────────────────────┴───────────────────────────────────────────────┴───────────────────────┘

  P2P-Specific KPIs (Unique to Your App)

  ┌───────────────────────────────────────┬────────────────────────────────────────────────────────────┬───────────────────────────────────────────────┐
  │                  KPI                  │                       How to Measure                       │                Why It Matters                 │
  ├───────────────────────────────────────┼────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┤
  │ QR exchange completion time           │ Stopwatch, target <45s per direction                       │ This IS your onboarding gate                  │
  ├───────────────────────────────────────┼────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┤
  │ Encryption comprehension              │ "In your own words, what happens to your message?"         │ If they can't explain it, they won't trust it │
  ├───────────────────────────────────────┼────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┤
  │ Trust indicator noticeability         │ Which trust signals do they notice unprompted? Target >30% │ If invisible, it's wasted engineering         │
  ├───────────────────────────────────────┼────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┤
  │ Delivery perception gap               │ "What % of messages went through?" vs actual %             │ Gap reveals UI communication failure          │
  ├───────────────────────────────────────┼────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┤
  │ Privacy behavior vs stated preference │ Do they actually check encryption indicators?              │ 40-60% gap is typical                         │
  ├───────────────────────────────────────┼────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┤
  │ Failure state comprehension           │ Show error states, ask "what happened?"                    │ P2P has more failure modes than centralized   │
  ├───────────────────────────────────────┼────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┤
  │ Empty state reaction                  │ Observe the "app with zero contacts" moment                │ The hardest problem for any new messenger     │
  └───────────────────────────────────────┴────────────────────────────────────────────────────────────┴───────────────────────────────────────────────┘

  Session Structure (90 minutes)

  ┌───────────────────────────────┬────────┬───────────────────────────────────────────────────────────────┐
  │             Block             │  Time  │                           Activity                            │
  ├───────────────────────────────┼────────┼───────────────────────────────────────────────────────────────┤
  │ Welcome + ground rules        │ 5 min  │ Consent, recording permission                                 │
  ├───────────────────────────────┼────────┼───────────────────────────────────────────────────────────────┤
  │ Warm-up                       │ 10 min │ Current messaging habits, what they like/dislike              │
  ├───────────────────────────────┼────────┼───────────────────────────────────────────────────────────────┤
  │ First impression + onboarding │ 20 min │ Hands-on: create identity, first screen (OBSERVE, don't help) │
  ├───────────────────────────────┼────────┼───────────────────────────────────────────────────────────────┤
  │ Core task scenarios           │ 30 min │ Add contact (QR), send messages, explore conversation         │
  ├───────────────────────────────┼────────┼───────────────────────────────────────────────────────────────┤
  │ Privacy & trust discussion    │ 15 min │ Mental model probing, encryption comprehension                │
  ├───────────────────────────────┼────────┼───────────────────────────────────────────────────────────────┤
  │ Wrap-up + surveys             │ 10 min │ SUS, trust scale, switching intent, open feedback             │
  └───────────────────────────────┴────────┴───────────────────────────────────────────────────────────────┘

  ---
  5. What's Meaningful to Achieve in 60 Days?

  Recommended 60-Day Roadmap

  Phase 1: Stabilize & Test-Ready (Days 1-15)

  ┌────────┬────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  Week  │     Focus      │                                              Deliverables                                              │
  ├────────┼────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Week 1 │ Critical fixes │ Persistent relay inbox, message dedup, fix 4 failing tests, CI/CD pipeline (GitHub Actions)            │
  ├────────┼────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Week 2 │ UX polish      │ Loading skeletons, error recovery buttons, delivery status clarity, haptic feedback, basic a11y labels │
  └────────┴────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  Phase 2: Internal Dogfooding (Days 16-25)
  - Use the app yourself daily for ALL communication with 2-3 trusted people
  - Different networks (WiFi, cellular, behind NAT)
  - Both iOS and Android devices
  - Log every bug, friction point, and "that felt weird" moment
  - Fix bugs as they surface (expect 10-15 medium-severity issues)

  Phase 3: Focus Group Preparation (Days 26-30)
  - Recruit 30-35 participants (screener survey, diverse segments)
  - Prepare TestFlight + Play Store internal testing builds
  - Write moderator guide and task scripts
  - Set up recording equipment/consent forms
  - Pre-install app on test devices as backup

  Phase 4: Focus Groups (Days 31-45)
  - Run 4 groups + 3-4 dyad sessions over 2 weeks
  - 2 groups per week (allows you to iterate between groups)
  - Synthesize notes after each session

  Phase 5: Iterate on Findings (Days 46-55)
  - Fix the top 5 critical issues surfaced by testing
  - Re-test the most problematic flows with 3-5 individual usability sessions
  - Expected critical findings: QR exchange friction, delivery status confusion, trust signal visibility

  Phase 6: Stabilize + Document (Days 56-60)
  - Final bug sweep
  - Performance profiling on older devices
  - Write up findings document with next-phase priorities

  Realistic Outcomes After 60 Days

  You WILL have:
  - A validated MVP with real user feedback on every core flow
  - Quantified usability scores (SUS, trust metrics, switching intent)
  - A prioritized backlog of UX improvements based on evidence, not guesses
  - Confidence in which flows work and which need redesign
  - Data on whether the privacy/P2P value proposition resonates

  You will NOT have:
  - A public launch-ready app (need 1-2 more iteration cycles)
  - Group messaging, message search, or advanced features
  - Accessibility compliance
  - Localization beyond English

  Time Allocation Rule of Thumb

  ┌───────────────────────┬──────────────┐
  │       Activity        │ % of 60 days │
  ├───────────────────────┼──────────────┤
  │ Bug fixes + stability │ 30%          │
  ├───────────────────────┼──────────────┤
  │ UX polish             │ 20%          │
  ├───────────────────────┼──────────────┤
  │ Focus group execution │ 20%          │
  ├───────────────────────┼──────────────┤
  │ Analysis + iteration  │ 15%          │
  ├───────────────────────┼──────────────┤
  │ New features          │ 10%          │
  ├───────────────────────┼──────────────┤
  │ Buffer for unknowns   │ 5%           │
  └───────────────────────┴──────────────┘

  The Single Most Important Thing

  Test the empty-state-to-first-message flow end-to-end with real devices on real networks, and resist the urge to help when participants get stuck. That QR contact exchange is your make-or-break moment. If two strangers can go from "I
  just installed this" to "I just sent you an encrypted message" in under 3 minutes without help, your MVP is working.