Below is the developer questionnaire I’d need to write a **meaningful, “strong” privacy policy** for a chat/social application—especially one that stands up well against major apps (WhatsApp/Signal/etc.) on **ads/selling/tracking** and overall transparency.

I’m not a lawyer, but this is the **practical information** privacy counsel / privacy teams typically gather to draft a policy that’s accurate, complete, and defensible.

---

## 0) First principle: policy must match reality

Before the questions: a “strong” privacy policy is only strong if your **product practices** (data minimization, no ad tracking, retention limits, encryption design) actually match what the policy promises. So I’ll ask several “implementation” questions too.

---

## 1) Company, ownership, and scope

1. What is the **legal entity name**, registration country, and address?
2. Any parent company, subsidiaries, or affiliates involved in running the app?
3. Who is the **data controller** (usually your company)? Any cases where you act as a **processor** for others?
4. What markets do you serve: EU/EEA, UK, US (CA), Brazil, India, etc.?
5. Do you block or restrict any countries?
6. What is the official privacy contact email? Do you have a **DPO** (Data Protection Officer) or EU/UK representative?

---

## 2) Product description and platforms

7. What’s the product: **messaging app**, “social network,” or both?
8. Platforms: iOS, Android, Web, Desktop? Any browser extension?
9. Is there a public website with cookies/tracking pixels?
10. Are there distinct modes: personal vs business vs enterprise vs kids/education version?

---

## 3) Target users, age gates, and minors

11. Minimum age allowed? Do you allow under-13 / under-16 users anywhere?
12. Do you have **age verification** or just “age self-declaration”?
13. Do you offer family accounts / parental controls?
14. If minors are allowed: do you collect **parental consent** anywhere?

---

## 4) Account creation and identity model

15. How do users sign up: phone number, email, username, SSO (Google/Apple/Facebook), anonymous?
16. Do you require a real name? Is identity verified?
17. Do you store phone numbers/email in plaintext, hashed, or encrypted?
18. What profile fields exist: name, username, bio, profile photo, location, links?
19. Can users discover others via phone number/email/username?
20. Do you allow multiple accounts per device? Any device binding?

---

## 5) Core messaging data: content vs metadata

### A) Message content handling

21. Do you store message **content** on your servers at any time?

* If yes: for how long? (delivery queue, backups, multi-device sync, compliance)

22. Do you support **end-to-end encryption** (E2EE) for:

* 1:1 chats
* group chats
* voice calls
* video calls
* file attachments
* link previews

23. If E2EE exists, is it:

* always on by default, or optional?
* per-chat setting?

24. If not E2EE: what encryption exists in transit and at rest?
25. Do you decrypt content server-side for any reason (spam scanning, moderation, AI features)?

### B) Metadata (often the biggest privacy issue)

26. What metadata do you log/store:

* sender/recipient identifiers
* group membership
* timestamps
* message delivery status (sent/delivered/read)
* IP address
* device identifiers
* approximate location inferred from IP
* contact graph / “who talks to whom”

27. Do you store “last seen,” online status, typing indicators? Can users disable them?
28. Do you log who joined which group/channel and when?
29. Do you keep server logs that could reconstruct social graphs?

---

## 6) Groups, channels, communities, and public content

30. Are groups private, public, or both?
31. Can groups/channels be discovered via search or invites only?
32. Do you provide public profiles/posts? Is anything indexed by search engines?
33. Do you show member lists publicly?
34. Do you offer “forwarding,” “reposting,” “quote tweeting”-like features?

---

## 7) Contacts, invites, and social graph building

35. Do you request access to the user’s **address book**?
36. If yes: do you upload contacts to your servers?

* Full address book, or hashed matching only?

37. Do you store uploaded contacts permanently or temporarily?
38. Do you allow “find friends” via contacts, Facebook, Google, etc.?
39. Do you send invites via SMS/email? Who sends them (you or user’s device)?
40. Do you build “people you may know” suggestions? Based on what signals?

---

## 8) Media, files, camera/mic, and link previews

41. What media types are supported: images, videos, voice notes, documents?
42. Where are attachments stored: your servers, third-party storage (S3), or P2P?
43. Do you generate thumbnails server-side?
44. Link previews:

* Does the user’s device fetch preview metadata, or do your servers fetch it?
* Do you log URLs shared?

45. Do you use any content scanning (malware scanning for attachments)?

---

## 9) Voice/video calling

46. Do you offer voice/video calls? Group calls?
47. Is calling E2EE?
48. Do you store call logs (who called whom, duration, timestamps)?
49. Do you use third-party call infrastructure (e.g., Twilio, Agora, WebRTC relays)? Which vendors?

---

## 10) Notifications & push services

50. Do you use APNs (Apple) / FCM (Google) for push?
51. What data is included in push payloads:

* message content snippets?
* sender name?
* chat ID only?

52. Do you store device tokens? How long after logout/deletion?

---

## 11) Analytics, tracking, ads, and monetization (your main focus)

### A) Business model

53. How do you make money?

* subscriptions
* ads
* data licensing
* enterprise
* donations
* in-app purchases

54. Do you *sell* personal data (as defined by laws like CPRA) or share for “cross-context behavioral advertising”?

### B) Ads

55. Do you show ads at all?
56. If yes: are ads contextual or targeted?
57. Do you use third-party ad networks (Google AdMob, Meta Audience Network, etc.)?
58. Do you allow ad partners to use device identifiers (IDFA/AAID), cookies, or SDK tracking?

### C) Tracking & measurement

59. Do you use analytics SDKs (Firebase, Amplitude, Mixpanel, Segment, AppsFlyer, Adjust, etc.)?
60. Do you use attribution SDKs? (Install tracking, campaign tracking)
61. Do you collect:

* advertising ID (IDFA/AAID)
* device fingerprinting signals
* precise location
* browsing across other apps/sites

62. Do you track users across your own apps/services? Across third-party apps?
63. Do you use “pixels” on your website (Meta Pixel, TikTok Pixel, etc.)?

### D) Profiling and inference

64. Do you build profiles for personalization (recommendations, ranking, feed)?
65. Do you infer interests, demographics, or sensitive traits?
66. Do you use data to train ML/AI models? If yes, does it include message content or only metadata?

---

## 12) Moderation, safety, abuse reporting

67. Do you moderate content? (automated, human, user reports)
68. When users report content, what is shared with moderators?

* reported message content
* chat history context
* reporter identity

69. Do you use third-party trust/safety vendors?
70. Do you block/ban accounts? What data do you retain for banned users and why?
71. Do you scan content for CSAM/terrorism/abuse? If yes, where and how?

---

## 13) Third parties, vendors, and data sharing

72. List every third party/vendor/SDK that receives user data:

* hosting/cloud (AWS/GCP/Azure)
* crash reporting (Sentry, Crashlytics)
* analytics
* email/SMS (SendGrid, Twilio)
* payments (Stripe, Apple/Google)
* support tools (Zendesk, Intercom)
* moderation vendors

73. For each vendor: what data is shared, purpose, and contract status (DPA)?
74. Do you share data with affiliates?
75. Do you share data with other users (e.g., profile visibility settings)?
76. Do you share data with law enforcement/governments? Under what rules?

---

## 14) Data storage locations and international transfers

77. Where are servers physically located (regions)?
78. Do you transfer EU/UK data to the US or elsewhere?
79. What transfer mechanism do you rely on (SCCs, adequacy, etc.)?
80. Do you have a data residency option?

---

## 15) Retention, deletion, backups

81. What’s your retention policy for:

* message content (if stored)
* message metadata
* call logs
* IP logs
* device identifiers
* analytics events
* account profile data
* support tickets

82. Are backups encrypted? How long are backups kept?
83. When a user deletes a message, is it deleted everywhere (including backups)?
84. When a user deletes account:

* what is deleted immediately?
* what is retained and for how long (fraud/security/legal)?

85. Do you offer “disappearing messages”? How is it implemented?

---

## 16) User controls and privacy settings

86. What privacy controls exist:

* who can message me
* who can find me by phone/email
* who sees my profile photo/status/last seen
* read receipts
* group invites
* blocked users

87. Can users download/export their data?
88. Can users opt out of analytics or targeted ads?
89. Can users disable contact syncing?

---

## 17) Legal bases and compliance posture (especially GDPR/UK GDPR)

90. Which legal bases do you use per processing purpose:

* consent
* contract necessity
* legitimate interests
* legal obligation

91. If using “legitimate interests,” do you have an LIA (balancing test)?
92. Do you do DPIAs (data protection impact assessments) for high-risk features?
93. Do you process sensitive data categories (health, biometric, political, etc.)?

---

## 18) User rights handling (DSAR)

94. How can users submit requests (access, deletion, correction)?
95. Identity verification process for requests?
96. Response time targets and workflow?
97. Do you have separate flows for EU/UK vs California vs other regions?

---

## 19) Security practices (policy must match)

98. Encryption at rest and in transit specifics.
99. Access controls (least privilege, MFA, logging).
100. Do you do security audits / pen tests / bug bounties?
101. Incident response: breach detection, notification timelines.
102. Do you keep transparency reports about government requests?

---

## 20) Cookies and website tracking (if you have a web presence)

103. Do you have:

* marketing site
* web app
* help center

104. What cookies/trackers do you use and for what purpose?
105. Do you have a cookie banner/consent manager in the EU?

---

## 21) Payments and financial data (if applicable)

106. Do you sell subscriptions? One-time purchases?
107. Who processes payments (Apple/Google/Stripe)?
108. Do you store payment card data (hopefully no)?
109. Do you do identity verification for payments?

---

## 22) Communications (email/SMS) and marketing

110. Do you send:

* transactional emails (verification, receipts)
* product announcements
* marketing newsletters

111. Can users opt out? Is opt-out global or per channel?
112. Do you do referral programs?

---

## 23) Governance and policy operations

113. How often do you plan to update the privacy policy?
114. How do you notify users of changes (in-app, email)?
115. Do you maintain version history?

---

## 24) “Strong compared to known apps” — extra questions to achieve that

These determine whether your policy can credibly say “we don’t monetize via tracking”:

116. Will you commit to **no selling** personal data?
117. Will you commit to **no third-party targeted advertising**?
118. Will you commit to **no cross-app tracking** (no IDFA/AAID use for tracking)?
119. Will you commit to **no data sharing with data brokers**?
120. Will you commit to collecting the **minimum** metadata needed to run messaging?
121. Can you publish a **vendor list** (subprocessors) and update it?
122. Can you publish a **retention schedule** in the policy?
123. Will you support **E2EE by default** (or at least for 1:1 + groups)?
124. Will you avoid storing message content server-side (or keep it strictly limited)?
125. Can you provide a clear “**What we collect / Why / How long / Who we share with**” table?

---

## 25) Documents/artifacts I’d ask you to provide (to avoid inaccurate claims)

126. Data map or architecture diagram (even rough)
127. List of SDKs + what events they collect
128. Current privacy policy drafts (if any), ToS, community guidelines
129. App store privacy “nutrition labels” (Apple) / Data Safety (Google)
130. Internal retention settings / log retention configs
131. Vendor DPAs/subprocessor list (or at least vendor names)

---

### If you want, paste your answers in a structured way

If you reply with:

* app description + sign-up method
* encryption model (E2EE yes/no, content storage yes/no)
* monetization model (ads yes/no, tracking yes/no, analytics SDKs)
* list of vendors/SDKs
* retention goals

…then I can turn it into a privacy policy that is **very explicit** about ads/selling/tracking and reads “strong” next to major chat apps (because it’ll have the clear commitments and tables that ratings bodies look for).

---
# Answers 1

  ---
  1) Company, Ownership, and Scope (Q1–6)

  Cannot answer from code — legal entity, registration, DPO, markets served are business/legal decisions not in the codebase.

  ---
  2) Product Description and Platforms (Q7–10)

  ┌─────┬────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │    Question    │                                            Answer                                            │
  ├─────┼────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 7   │ Product type   │ Private P2P messaging app — 1:1 + group chat, not a social network                           │
  ├─────┼────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 8   │ Platforms      │ iOS + Android (via Flutter). Web explicitly disabled (!kIsWeb). No desktop builds published. │
  ├─────┼────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 9   │ Public website │ No — mknoun.xyz is a libp2p relay node, not a web server. No cookies/pixels.                 │
  ├─────┼────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 10  │ Distinct modes │ No — single universal identity model, no business/enterprise/kids tiers                      │
  └─────┴────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  3) Target Users, Age Gates, Minors (Q11–14)

  No age verification or age gate exists in the codebase. No parental controls, family accounts, or COPPA compliance code. This is a
   policy decision you'll need to make.

  ---
  4) Account Creation and Identity Model (Q15–20)

  ┌─────┬─────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │    Question     │                                               Answer                                                │
  ├─────┼─────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 15  │ Signup method   │ Fully anonymous — "I'm new here" generates Ed25519 keypair + ML-KEM-768 keys locally. "Load my key" │
  │     │                 │  restores from 12-word BIP39 mnemonic. No phone, email, SSO, or username required.                  │
  ├─────┼─────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 16  │ Real name       │ No — default username is "Username", user can edit to anything                                      │
  │     │ required?       │                                                                                                     │
  ├─────┼─────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 17  │ Phone/email     │ Neither collected — no phone or email fields exist anywhere in the data model                       │
  │     │ storage         │                                                                                                     │
  ├─────┼─────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 18  │ Profile fields  │ username (editable), peerId (crypto ID), publicKey (Ed25519), avatarBlob (optional, EXIF-stripped). │
  │     │                 │  No bio, location, links, real name, or email.                                                      │
  ├─────┼─────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 19  │ Discovery       │ None — contacts added exclusively via in-person QR code scan or peer-facilitated introductions.     │
  │     │ mechanism       │ Zero searchability.                                                                                 │
  ├─────┼─────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 20  │ Multiple        │ Single identity per install (enforced by singleton DB record). Identity portable across devices via │
  │     │ accounts        │  mnemonic. No device binding.                                                                       │
  └─────┴─────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  5) Core Messaging Data (Q21–29)

  A) Message Content

  ┌─────┬─────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │      Question       │                                             Answer                                              │
  ├─────┼─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │     │ Server-side content │ Yes, temporarily — relay inbox stores encrypted messages max 7 days, capped at 100/peer (1:1)   │
  │ 21  │  storage            │ or 500/group. 1:1 messages deleted on retrieval (destructive read). Group messages persist      │
  │     │                     │ until 7-day TTL (pruned hourly).                                                                │
  ├─────┼─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │     │                     │ 1:1: Yes (ML-KEM-768 + AES-256-GCM, v2 envelope). Groups: Yes (encrypted + signed, v3           │
  │ 22  │ E2EE support        │ envelope). Voice/video calls: Not implemented. File attachments: Yes (encrypted .enc blobs).    │
  │     │                     │ Link previews: Not implemented.                                                                 │
  ├─────┼─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │     │ E2EE                │ 1:1: Auto-enabled if contact has ML-KEM key (all new contacts do); falls back to plaintext v1   │
  │ 23  │ default/optional    │ for legacy contacts. Groups: Always encrypted. Contact requests: Always encrypted (X25519       │
  │     │                     │ ECDH).                                                                                          │
  ├─────┼─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 24  │ Non-E2EE encryption │ Transport: libp2p Noise/TLS. At rest: SQLCipher (256-bit AES). Secrets in iOS Keychain /        │
  │     │                     │ Android EncryptedSharedPreferences.                                                             │
  ├─────┼─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 25  │ Server-side         │ Never — relay stores opaque encrypted payloads. No spam scanning, moderation, or AI processing  │
  │     │ decryption          │ on server.                                                                                      │
  └─────┴─────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────┘

  B) Metadata

  ┌─────┬────────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │      Question      │                                              Answer                                              │
  ├─────┼────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │     │                    │ Relay sees: sender/recipient peer IDs, timestamps, group topic subscriptions. Relay does NOT     │
  │ 26  │ Metadata logged    │ log: IP addresses separately, device identifiers, location. Locally stored: full message         │
  │     │                    │ metadata (status, read_at, transport type).                                                      │
  ├─────┼────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 27  │ Last seen / online │ None implemented — no last-seen tracking, no online status broadcast, no typing indicators. Read │
  │     │  / typing          │  receipts tracked locally only (never sent to sender).                                           │
  ├─────┼────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 28  │ Group join logging │ Relay sees GossipSub topic subscriptions (peer joins group namespace). Stored only               │
  │     │                    │ in-memory/transient rendezvous registrations.                                                    │
  ├─────┼────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
  │     │ Social graph       │ Partially possible from relay's in-memory state: inbox shows who-sends-to-whom, rendezvous shows │
  │ 29  │ reconstruction     │  active peers, group subscriptions show membership. No persistent audit log — data is transient, │
  │     │                    │  resets on restart.                                                                              │
  └─────┴────────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  6) Groups, Channels, Communities (Q30–34)

  ┌─────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │       Question       │                                             Answer                                             │
  ├─────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 30  │ Group privacy        │ Private only — three types (chat, announcement, qa) but all invite-only                        │
  ├─────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 31  │ Discoverability      │ Invite-only — no public search or directory. Discovery via rendezvous namespace                │
  │     │                      │ /mknoon/group/<groupId>                                                                        │
  ├─────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 32  │ Public               │ No — nothing indexed by search engines, no public URLs                                         │
  │     │ profiles/posts       │                                                                                                │
  ├─────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 33  │ Public member lists  │ No — member lists visible only to group members (local DB)                                     │
  ├─────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 34  │ Forwarding/reposting │ Quote-reply exists (quoting a message within same conversation). No cross-chat forwarding or   │
  │     │                      │ public reposting.                                                                              │
  └─────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  7) Contacts, Invites, Social Graph (Q35–40)

  ┌─────┬───────────────────────┬────────────────────────────────────────────┐
  │  #  │       Question        │                   Answer                   │
  ├─────┼───────────────────────┼────────────────────────────────────────────┤
  │ 35  │ Address book access   │ No — no READ_CONTACTS permission requested │
  ├─────┼───────────────────────┼────────────────────────────────────────────┤
  │ 36  │ Contact upload        │ No                                         │
  ├─────┼───────────────────────┼────────────────────────────────────────────┤
  │ 37  │ Contact storage       │ N/A                                        │
  ├─────┼───────────────────────┼────────────────────────────────────────────┤
  │ 38  │ Find friends          │ No — no Facebook/Google/email/phone lookup │
  ├─────┼───────────────────────┼────────────────────────────────────────────┤
  │ 39  │ SMS/email invites     │ No — no invite sending mechanism           │
  ├─────┼───────────────────────┼────────────────────────────────────────────┤
  │ 40  │ "People you may know" │ No — no algorithmic suggestions            │
  └─────┴───────────────────────┴────────────────────────────────────────────┘

  ---
  8) Media, Files, Camera/Mic (Q41–45)

  ┌─────┬─────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │    Question     │                                               Answer                                                │
  ├─────┼─────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 41  │ Supported media │ Images (JPG/PNG/GIF/WebP/HEIC), videos (MP4/MOV/AVI/MKV), audio (AAC/MP3/M4A/OGG), documents (PDF)  │
  ├─────┼─────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │     │ Attachment      │ P2P + relay fallback — files stored locally on device; sent via local WiFi (HTTP PUT) or relay      │
  │ 42  │ storage         │ server as encrypted .enc blobs. 1:1 blobs auto-deleted after download; group blobs kept 7 days. Max │
  │     │                 │  100MB/blob, 50 blobs/peer.                                                                         │
  ├─────┼─────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 43  │ Server-side     │ No                                                                                                  │
  │     │ thumbnails      │                                                                                                     │
  ├─────┼─────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 44  │ Link previews   │ URLs detected and made tappable but no metadata fetching (no server or client-side preview          │
  │     │                 │ generation). URLs not logged.                                                                       │
  ├─────┼─────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 45  │ Content         │ No malware scanning, CSAM scanning, or content moderation                                           │
  │     │ scanning        │                                                                                                     │
  └─────┴─────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  9) Voice/Video Calling (Q46–49)

  Not implemented. No voice or video calling features exist. Voice messages (audio recordings) are supported as attachments but no
  real-time calls.

  ---
  10) Notifications & Push (Q50–52)

  ┌─────┬──────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │   Question   │                                                 Answer                                                 │
  ├─────┼──────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 50  │ Push         │ FCM (Firebase Cloud Messaging) for both iOS and Android                                                │
  │     │ services     │                                                                                                        │
  ├─────┼──────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 51  │ Push payload │ 1:1: sender username + message text (full content in notification). Groups: group ID only. Background  │
  │     │  data        │ fallback: generic "New Message" / "You have a new message".                                            │
  ├─────┼──────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 52  │ Device       │ Registered with relay server. Platform ('ios'/'android') + token stored. No explicit cleanup on        │
  │     │ tokens       │ logout/deletion — tokens persist until app reinstall or manual deregistration.                         │
  └─────┴──────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  Privacy concern: Push payloads for 1:1 messages include message text, which transits through Google/Apple infrastructure
  unencrypted at the push layer.

  ---
  11) Analytics, Tracking, Ads, Monetization (Q53–66)

  A) Business Model

  ┌─────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │                                                   Answer                                                   │
  ├─────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 53  │ No monetization visible in codebase — no ads, subscriptions, payments, data licensing, or in-app purchases │
  ├─────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 54  │ No data selling or cross-context behavioral advertising                                                    │
  └─────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  B) Ads

  ┌───────┬────────────────────────────────────────────────────┐
  │   #   │                       Answer                       │
  ├───────┼────────────────────────────────────────────────────┤
  │ 55–58 │ No ads whatsoever — no ad SDKs (AdMob, Meta, etc.) │
  └───────┴────────────────────────────────────────────────────┘

  C) Tracking

  ┌─────┬───────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │                                          Answer                                           │
  ├─────┼───────────────────────────────────────────────────────────────────────────────────────────┤
  │ 59  │ No analytics SDKs — Firebase imported only for FCM push, not analytics                    │
  ├─────┼───────────────────────────────────────────────────────────────────────────────────────────┤
  │ 60  │ No attribution or install tracking SDKs                                                   │
  ├─────┼───────────────────────────────────────────────────────────────────────────────────────────┤
  │ 61  │ No collection of: IDFA/AAID, fingerprinting signals, precise location, cross-app browsing │
  ├─────┼───────────────────────────────────────────────────────────────────────────────────────────┤
  │ 62  │ No cross-app or cross-service tracking                                                    │
  ├─────┼───────────────────────────────────────────────────────────────────────────────────────────┤
  │ 63  │ No website pixels                                                                         │
  └─────┴───────────────────────────────────────────────────────────────────────────────────────────┘

  D) Profiling

  ┌───────┬──────────────────────────────────────────────────────────────────────┐
  │   #   │                                Answer                                │
  ├───────┼──────────────────────────────────────────────────────────────────────┤
  │ 64–65 │ No profile building, personalization, interest/demographic inference │
  ├───────┼──────────────────────────────────────────────────────────────────────┤
  │ 66    │ No ML/AI model training on user data                                 │
  └───────┴──────────────────────────────────────────────────────────────────────┘

  ---
  12) Moderation, Safety (Q67–71)

  ┌─────┬──────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────┐
  │  #  │             Question             │                                    Answer                                    │
  ├─────┼──────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤
  │ 67  │ Content moderation               │ None — no automated or human moderation                                      │
  ├─────┼──────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤
  │ 68  │ Reporting                        │ No report system exists                                                      │
  ├─────┼──────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤
  │ 69  │ Third-party trust/safety vendors │ None                                                                         │
  ├─────┼──────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤
  │ 70  │ Banning                          │ No ban system. Users can locally block contacts (preventing message receipt) │
  ├─────┼──────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤
  │ 71  │ CSAM/terrorism scanning          │ No                                                                           │
  └─────┴──────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────┘

  ---
  13) Third Parties, Vendors, Data Sharing (Q72–76)

  Complete Vendor/SDK List

  Flutter App:

  ┌────────────────────────────────────┬───────────────────────────┬────────────────────────────────────┐
  │             Vendor/SDK             │        Data Shared        │              Purpose               │
  ├────────────────────────────────────┼───────────────────────────┼────────────────────────────────────┤
  │ firebase_core + firebase_messaging │ FCM push token + platform │ Push notification delivery         │
  ├────────────────────────────────────┼───────────────────────────┼────────────────────────────────────┤
  │ flutter_secure_storage             │ None (local only)         │ Secure key storage                 │
  ├────────────────────────────────────┼───────────────────────────┼────────────────────────────────────┤
  │ sqflite_sqlcipher                  │ None (local only)         │ Encrypted local database           │
  ├────────────────────────────────────┼───────────────────────────┼────────────────────────────────────┤
  │ flutter_image_compress             │ None (local only)         │ Image compression + EXIF stripping │
  ├────────────────────────────────────┼───────────────────────────┼────────────────────────────────────┤
  │ bonsoir (mDNS)                     │ None (local network only) │ WiFi peer discovery                │
  ├────────────────────────────────────┼───────────────────────────┼────────────────────────────────────┤
  │ mobile_scanner                     │ None (camera only)        │ QR code scanning                   │
  ├────────────────────────────────────┼───────────────────────────┼────────────────────────────────────┤
  │ record / just_audio                │ None (local only)         │ Voice message record/playback      │
  └────────────────────────────────────┴───────────────────────────┴────────────────────────────────────┘

  Go Relay Server:

  ┌───────────────────────────┬─────────────────────────────────────┬───────────────────────────┐
  │        Vendor/SDK         │             Data Shared             │          Purpose          │
  ├───────────────────────────┼─────────────────────────────────────┼───────────────────────────┤
  │ firebase.google.com/go/v4 │ Push tokens + notification payloads │ FCM delivery              │
  ├───────────────────────────┼─────────────────────────────────────┼───────────────────────────┤
  │ go-libp2p                 │ Peer IDs, multiaddrs                │ P2P networking            │
  ├───────────────────────────┼─────────────────────────────────────┼───────────────────────────┤
  │ go-redis                  │ Inbox data, push tokens             │ Temporary storage backend │
  ├───────────────────────────┼─────────────────────────────────────┼───────────────────────────┤
  │ prometheus/client_golang  │ Operational metrics only            │ Server monitoring         │
  └───────────────────────────┴─────────────────────────────────────┴───────────────────────────┘

  ┌─────┬─────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │                                       Answer                                        │
  ├─────┼─────────────────────────────────────────────────────────────────────────────────────┤
  │ 73  │ Only Firebase (Google) receives user-facing data (push tokens). DPA status unknown. │
  ├─────┼─────────────────────────────────────────────────────────────────────────────────────┤
  │ 74  │ No affiliate data sharing                                                           │
  ├─────┼─────────────────────────────────────────────────────────────────────────────────────┤
  │ 75  │ Profile data (username, avatar, public keys) shared with contacts via P2P           │
  ├─────┼─────────────────────────────────────────────────────────────────────────────────────┤
  │ 76  │ No law enforcement data sharing mechanism exists in code                            │
  └─────┴─────────────────────────────────────────────────────────────────────────────────────┘

  ---
  14) Data Storage & International Transfers (Q77–80)

  Cannot fully answer from code. Relay server address is mknoun.xyz — hosting location not specified in code. Redis can be external.
   These are infrastructure decisions.

  ---
  15) Retention, Deletion, Backups (Q81–85)

  ┌─────┬──────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │     Question     │                                               Answer                                               │
  ├─────┼──────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 81  │ Retention policy │ Local: Messages/contacts stored indefinitely (no auto-expiry). Relay: 7-day TTL for inbox          │
  │     │                  │ messages, 7-day TTL for media blobs, 1:1 deleted on retrieval.                                     │
  ├─────┼──────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 82  │ Backup           │ No app-level backup feature. DB is SQLCipher-encrypted. iOS Keychain items set to                  │
  │     │ encryption       │ kSecAttrAccessibleWhenUnlockedThisDeviceOnly (excluded from iCloud backup).                        │
  ├─────┼──────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 83  │ Message deletion │ Contact/group deletion removes all local messages permanently. No mechanism to delete from         │
  │     │  scope           │ recipient's device.                                                                                │
  ├─────┼──────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 84  │ Account deletion │ Not implemented — no "delete account" feature exists                                               │
  ├─────┼──────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 85  │ Disappearing     │ Not implemented                                                                                    │
  │     │ messages         │                                                                                                    │
  └─────┴──────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  16) User Controls & Privacy Settings (Q86–89)

  ┌─────┬───────────────┬───────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │   Question    │                                                Answer                                                 │
  ├─────┼───────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │     │ Controls      │ Block contact (prevents message receipt), archive contact (hides conversation), delete contact        │
  │ 86  │ available     │ (permanent with all messages), delete group. No controls for: who can message me, who sees profile,   │
  │     │               │ read receipts, group invites.                                                                         │
  ├─────┼───────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 87  │ Data export   │ Not implemented                                                                                       │
  ├─────┼───────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 88  │ Analytics     │ N/A — no analytics to opt out of                                                                      │
  │     │ opt-out       │                                                                                                       │
  ├─────┼───────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 89  │ Contact sync  │ N/A — no contact sync exists                                                                          │
  │     │ disable       │                                                                                                       │
  └─────┴───────────────┴───────────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  17–18) Legal Bases & User Rights (Q90–97)

  Policy decisions — not derivable from code.

  ---
  19) Security Practices (Q98–102)

  ┌─────┬─────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │      Question       │                                             Answer                                              │
  ├─────┼─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 98  │ Encryption at rest  │ SQLCipher (AES-256) with random key in platform secure storage. Secrets in iOS Keychain /       │
  │     │                     │ Android EncryptedSharedPreferences.                                                             │
  ├─────┼─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 99  │ Encryption in       │ libp2p Noise/TLS for transport. ML-KEM-768 + AES-256-GCM per-message E2EE. X25519 ECDH for      │
  │     │ transit             │ contact requests.                                                                               │
  ├─────┼─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 100 │ Audits/pen          │ No evidence in codebase                                                                         │
  │     │ tests/bounty        │                                                                                                 │
  ├─────┼─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 101 │ Incident response   │ Not defined in code                                                                             │
  ├─────┼─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 102 │ Transparency        │ No                                                                                              │
  │     │ reports             │                                                                                                 │
  └─────┴─────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  20–23) Cookies, Payments, Communications, Governance (Q103–115)

  ┌──────────────────┬─────────────────────────────────────────────────────────────┐
  │       Area       │                           Answer                            │
  ├──────────────────┼─────────────────────────────────────────────────────────────┤
  │ Cookies/website  │ No website — N/A                                            │
  ├──────────────────┼─────────────────────────────────────────────────────────────┤
  │ Payments         │ No payment processing in codebase                           │
  ├──────────────────┼─────────────────────────────────────────────────────────────┤
  │ Marketing emails │ No email/SMS sending capability                             │
  ├──────────────────┼─────────────────────────────────────────────────────────────┤
  │ Policy updates   │ Not implemented — no version history or update notification │
  └──────────────────┴─────────────────────────────────────────────────────────────┘

  ---
  24) "Strong Compared to Known Apps" (Q116–125)

  ┌─────┬──────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │        Commitment        │                                           Status                                           │
  ├─────┼──────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 116 │ No selling personal data │ YES — no data sales infrastructure exists                                                  │
  ├─────┼──────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 117 │ No third-party targeted  │ YES — zero ad SDKs                                                                         │
  │     │ ads                      │                                                                                            │
  ├─────┼──────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 118 │ No cross-app tracking    │ YES — no IDFA/AAID collection                                                              │
  ├─────┼──────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 119 │ No data broker sharing   │ YES — no data broker integrations                                                          │
  ├─────┼──────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 120 │ Minimum metadata         │ YES — no location, no IP logging, no device fingerprinting, no contact upload              │
  ├─────┼──────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 121 │ Published vendor list    │ Feasible — only vendor is Firebase (FCM)                                                   │
  ├─────┼──────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 122 │ Published retention      │ Feasible — relay: 7-day TTL; local: indefinite until user deletes                          │
  │     │ schedule                 │                                                                                            │
  ├─────┼──────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 123 │ E2EE by default          │ YES for new contacts (ML-KEM keys auto-generated). Legacy v1 fallback exists but           │
  │     │                          │ diminishing. Groups always encrypted.                                                      │
  ├─────┼──────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 124 │ No server-side content   │ Partially — relay stores encrypted messages up to 7 days for offline delivery, but cannot  │
  │     │ storage                  │ decrypt them                                                                               │
  ├─────┼──────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 125 │ Clear data table         │ Feasible — data model is simple enough for a clear table                                   │
  └─────┴──────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  Key Gaps to Address Before Policy

  1. Push notification content — 1:1 messages include plaintext text in FCM payloads (transits Google infra)
  2. No account deletion feature — needs implementation for GDPR Art. 17
  3. No data export — needed for GDPR Art. 20 (data portability)
  4. No age gate — needed if serving EU/US markets
  5. No disappearing messages — not required but expected for "strong" positioning
  6. Push token cleanup — tokens not deregistered on app removal
  7. v1 plaintext fallback — legacy contacts without ML-KEM keys receive unencrypted messages
---

# Answers 2

> The answers below were produced by auditing the mknoon codebase (Flutter app, Go relay server, Go client library, native platform wrappers). Where a question requires a business/legal decision rather than a technical fact, it is marked **[POLICY DECISION NEEDED]**.

---

## 1) Company, ownership, and scope

1. **[POLICY DECISION NEEDED]** — Legal entity name, country, and address are not defined in the codebase.
2. **[POLICY DECISION NEEDED]** — No parent/subsidiary/affiliate references in code.
3. **[POLICY DECISION NEEDED]** — The relay server operator is the data controller for relay-stored data. The app itself is fully decentralized (user’s device is the primary data store).
4. **[POLICY DECISION NEEDED]** — No geo-restriction logic exists in the app or relay server.
5. **No** — No country blocking or restriction code exists.
6. **[POLICY DECISION NEEDED]** — No privacy contact email, DPO, or EU/UK representative configured in the app.

---

## 2) Product description and platforms

7. **Private peer-to-peer messaging app** — 1:1 encrypted chat + group chat. Not a social network (no public profiles, no followers, no feed of strangers).
8. **iOS + Android** (Flutter). Web is explicitly disabled (`!kIsWeb` guards). No desktop builds published. No browser extension.
9. **No** — `mknoun.xyz` is a libp2p relay node (P2P infrastructure), not a website. No cookies, tracking pixels, or web analytics.
10. **No** — Single universal identity model. No business, enterprise, kids, or education modes.

---

## 3) Target users, age gates, and minors

11. **[POLICY DECISION NEEDED]** — No minimum age enforcement exists in the codebase.
12. **Neither** — No age verification or self-declaration screen.
13. **No** — No family accounts or parental controls.
14. **No** — No parental consent flow.

---

## 4) Account creation and identity model

15. **Fully anonymous / cryptographic** — Two paths: “I’m new here” (generates Ed25519 keypair + ML-KEM-768 keys locally on-device) or “Load my key” (restores from a 12-word BIP39 mnemonic). No phone number, email, username, or SSO required.
16. **No** — Default username is “Username”; editable to anything. No real-name requirement. Identity is verified cryptographically (Ed25519 signatures), not by government ID or KYC.
17. **N/A** — Phone numbers and emails are never collected. They do not exist in the data model.
18. **Minimal**: `username` (editable string), `peerId` (libp2p cryptographic identifier), `publicKey` (Ed25519, base64), `avatarBlob` (optional profile image, EXIF metadata always stripped). **Not present**: email, phone, real name, bio, location, links.
19. **No discovery mechanism** — Contacts are added exclusively by scanning another user’s QR code in person, or via peer-facilitated introductions. No directory, no username lookup, no phone/email search.
20. **Single identity per app installation** (enforced by singleton DB record). No device binding — identity is portable across devices via the 12-word mnemonic.

---

## 5) Core messaging data: content vs metadata

### A) Message content handling

21. **Yes, temporarily on the relay server** — The relay stores encrypted messages in an offline inbox for up to **7 days** (`maxMessageAge = 7 * 24 * time.Hour`), capped at **100 messages per peer** (1:1) or **500 per group**. 1:1 messages are **deleted immediately upon retrieval** (destructive read). Group messages persist until the 7-day TTL (pruned hourly). The relay **cannot decrypt** any of these messages.

22. E2EE support:
    * **1:1 chats** — Yes: ML-KEM-768 (FIPS 203, post-quantum) + AES-256-GCM per message (v2 envelope)
    * **Group chats** — Yes: Encrypted + signed v3 envelope via GossipSub pubsub
    * **Voice calls** — Not implemented (no calling feature)
    * **Video calls** — Not implemented (no calling feature)
    * **File attachments** — Yes: Media uploaded as encrypted `.enc` blobs; relay stores opaque ciphertext
    * **Link previews** — Not implemented (no link preview fetching)

23. **1:1**: Automatically enabled when the contact has an ML-KEM public key (all new identities generate one). Falls back to plaintext v1 envelope only for legacy contacts without ML-KEM keys. Not a per-chat toggle — it’s determined by key availability. **Groups**: Always encrypted (mandatory). **Contact requests**: Always encrypted (X25519 ECDH + AES-256-GCM).

24. **Transport**: libp2p Noise protocol + TLS for all peer-to-peer and relay connections. **At rest (device)**: SQLCipher database with 256-bit AES encryption; key stored in iOS Keychain / Android EncryptedSharedPreferences. **At rest (relay)**: Messages stored as encrypted JSON payloads (relay has no decryption keys).

25. **No** — The relay server never decrypts message content. No spam scanning, content moderation, or AI processing exists in the relay codebase. Server logs record only peer IDs and aggregate statistics, never message content.

### B) Metadata

26. Metadata stored:
    * **Sender/recipient peer IDs** — Yes, on relay (inbox `from`/`to` fields) and locally
    * **Group membership** — Yes, on relay (GossipSub topic subscriptions) and locally (`group_members` table)
    * **Timestamps** — Yes, both message timestamp and server creation time
    * **Delivery status** — Locally only (`sending`, `sent`, `delivered`, `failed`). Relay tracks `stored=1` but no delivery confirmation back to sender.
    * **IP address** — Not logged separately. Relay sees connection IPs via libp2p but does not persist them.
    * **Device identifiers** — Only FCM push tokens (platform + token string). No IDFA/AAID, no hardware IDs.
    * **Approximate location** — Not collected. No IP-to-location inference.
    * **Contact graph** — Partially reconstructable from relay’s transient in-memory state (inbox peers, rendezvous registrations, group subscriptions). No persistent audit log — data resets on relay restart.

27. **None implemented** — No last-seen tracking, no online status broadcast, no typing indicators. Read receipts (`read_at`) are tracked locally only and never sent back to the sender.

28. Relay sees GossipSub topic subscriptions (peer joins group namespace), but this is transient in-memory state, not a persistent log.

29. **Partially, from transient state only** — Relay’s in-memory inbox shows who-sends-to-whom; rendezvous registrations show active peers; group subscriptions show membership. No persistent audit log exists. Prometheus metrics track aggregate counts only (number of peers, messages, groups), not per-user data.

---

## 6) Groups, channels, communities, and public content

30. **Private only** — Three group types exist (`chat`, `announcement`, `qa`) but all are invite-only.
31. **Invites only** — No public group search or directory. Groups discovered via rendezvous namespace `/mknoon/group/<groupId>` after being invited.
32. **No** — No public profiles, no public posts, nothing indexed by search engines.
33. **No** — Member lists visible only to group members (stored locally in `group_members` table).
34. **Quote-reply only** — Users can quote a message within the same conversation. No cross-chat forwarding, reposting, or “quote tweeting.”

---

## 7) Contacts, invites, and social graph building

35. **No** — The app does not request `READ_CONTACTS` permission. No address book access.
36. **N/A** — No contact upload.
37. **N/A** — No contact upload.
38. **No** — No “find friends” via contacts, Facebook, Google, or any external service.
39. **No** — No SMS or email invite capability.
40. **No** — No “people you may know” suggestions. No algorithmic recommendations.

---

## 8) Media, files, camera/mic, and link previews

41. **Images** (JPG, PNG, GIF, WebP, HEIC), **videos** (MP4, MOV, AVI, MKV, M4V), **audio/voice notes** (AAC, MP3, M4A, OGG via `record` package), **documents** (PDF).
42. **P2P + relay fallback** — Files stored locally on device at `<app_documents>/media/<contactPeerId>/<blobId>.<ext>`. Sent via local WiFi (HTTP PUT) or relay server as encrypted `.enc` blobs. 1:1 blobs auto-deleted from relay after download; group blobs kept up to 7 days. Max 100 MB per blob, 50 blobs per peer. No third-party cloud storage (no S3, GCS, etc.).
43. **No** — No server-side thumbnail generation.
44. **No link preview fetching** — URLs in messages are detected and made tappable (opens system browser via `url_launcher`), but neither the device nor the server fetches preview metadata. URLs are not logged.
45. **No** — No malware scanning, virus scanning, or content scanning of any kind.

---

## 9) Voice/video calling

46. **Not implemented** — No voice or video calling. The app supports voice *messages* (audio recordings sent as attachments) but no real-time calls.
47. **N/A**
48. **N/A** — No call logs.
49. **N/A** — No third-party call infrastructure.

---

## 10) Notifications & push services

50. **Yes** — Firebase Cloud Messaging (FCM) for both iOS and Android. APNs is used under the hood by FCM on iOS.
51. Push payload contents:
    * **1:1 messages**: Sender username + message text (full content visible in notification)
    * **Group messages**: Group ID indicator only
    * **Background fallback** (Android): Generic “New Message” / “You have a new message”
    * **⚠️ Privacy note**: 1:1 push payloads contain plaintext message text, which transits through Google (FCM) / Apple (APNs) infrastructure.
52. **Yes** — FCM device tokens are registered with the relay server (platform + token string stored in memory/Redis via `push_token_store.go`). **No explicit cleanup on logout or app deletion** — tokens persist until app reinstall or manual deregistration.

---

## 11) Analytics, tracking, ads, and monetization

### A) Business model

53. **No monetization visible in the codebase** — No ads, subscriptions, payment processing (Stripe, IAP), data licensing, enterprise features, or donation mechanisms.
54. **No** — No data selling, no cross-context behavioral advertising, no data sharing with any third party for advertising purposes.

### B) Ads

55. **No** — Zero ads in the app.
56. **N/A**
57. **No** — No ad SDKs (AdMob, Meta Audience Network, etc.) in dependencies.
58. **No** — No ad partner integrations whatsoever.

### C) Tracking & measurement

59. **No** — No analytics SDKs. Firebase is imported solely for FCM push notifications; Firebase Analytics is NOT included in `pubspec.yaml`.
60. **No** — No attribution or install-tracking SDKs (AppsFlyer, Adjust, Branch, etc.).
61. The app does **not** collect:
    * Advertising ID (IDFA/AAID) — not accessed
    * Device fingerprinting signals — not collected
    * Precise location (GPS) — no location permission requested
    * Browsing across other apps/sites — app is isolated
62. **No** — No cross-app or cross-service tracking.
63. **No** — No website, therefore no pixels.

### D) Profiling and inference

64. **No** — No profile building, personalization engine, recommendations, or ranking.
65. **No** — No interest, demographic, or sensitive-trait inference.
66. **No** — No ML/AI model training on user data (content or metadata).

---

## 12) Moderation, safety, abuse reporting

67. **No content moderation** — No automated scanning, no human review, no user-report system.
68. **N/A** — No reporting mechanism exists.
69. **No** — No third-party trust/safety vendors.
70. **No server-side banning** — Users can locally block contacts (`is_blocked` column), which prevents receiving messages from that peer. No centralized ban list.
71. **No** — No CSAM, terrorism, or abuse scanning. The relay cannot read encrypted content.

---

## 13) Third parties, vendors, and data sharing

72. **Complete vendor/SDK list:**

    **Flutter app dependencies that touch external services:**
    | Vendor/SDK | Data Shared | Purpose |
    |---|---|---|
    | `firebase_core` + `firebase_messaging` (Google) | FCM push token + platform identifier | Push notification delivery |

    **Flutter app dependencies that are local-only (no external data sharing):**
    `flutter_secure_storage`, `sqflite_sqlcipher`, `flutter_image_compress`, `bonsoir` (mDNS, LAN only), `mobile_scanner`, `record`, `just_audio`, `video_compress`, `image_picker`, `url_launcher`, `qr_flutter`, `flutter_svg`, `uuid`, `crypto`, `path_provider`, `receive_sharing_intent`, `flutter_local_notifications`

    **Go relay server dependencies:**
    | Vendor/SDK | Data Shared | Purpose |
    |---|---|---|
    | `firebase.google.com/go/v4` (Google) | Push tokens + notification payloads | FCM push delivery |
    | `go-libp2p` (Protocol Labs, open source) | Peer IDs, multiaddrs | P2P networking infrastructure |
    | `go-redis` | Inbox data, push tokens (on same infra) | Temporary storage backend |
    | `prometheus/client_golang` | Aggregate operational metrics only | Server monitoring |

    **Not present:** crash reporting (Sentry, Crashlytics), analytics, email/SMS (SendGrid, Twilio), payments (Stripe), support tools (Zendesk, Intercom), moderation vendors, ad networks.

73. Only **Firebase/Google** receives user-facing data (push tokens + notification content for 1:1 messages). **[POLICY DECISION NEEDED]** — DPA status with Google.
74. **No** — No affiliate data sharing.
75. **Yes** — Profile data (username, avatar, public keys) is shared with accepted contacts via P2P. Group members see each other’s usernames and public keys.
76. **[POLICY DECISION NEEDED]** — No law enforcement data sharing mechanism or process exists in code. Relay server stores only encrypted messages it cannot read.

---

## 14) Data storage locations and international transfers

77. **[POLICY DECISION NEEDED]** — Relay server address is `mknoun.xyz`; hosting region not specified in code.
78. **[POLICY DECISION NEEDED]** — Depends on relay server hosting location.
79. **[POLICY DECISION NEEDED]** — No transfer mechanism configured.
80. **No** — No data residency option. All user data is on-device; relay storage is transient (7-day TTL).

---

## 15) Retention, deletion, backups

81. Retention policy:
    * **Message content (relay)**: Max 7 days; 1:1 deleted on retrieval; group messages pruned hourly after 7-day TTL
    * **Message content (local device)**: Stored indefinitely until user deletes the contact or group
    * **Message metadata (local)**: Same as content — indefinite
    * **Call logs**: N/A (no calling feature)
    * **IP logs**: Not logged
    * **Device identifiers**: FCM push tokens stored in relay memory/Redis with no explicit expiry
    * **Analytics events**: N/A (no analytics)
    * **Account profile data (local)**: Stored indefinitely
    * **Support tickets**: N/A (no support system)

82. **No app-level backup feature.** The SQLCipher database is encrypted at rest. iOS Keychain items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (excluded from iCloud/iTunes backup). System-level device backups may capture the encrypted database file but cannot read it without the encryption key (which is in secure storage, also device-bound on iOS).

83. **Local only** — Deleting a contact calls `deleteContactAndMessages()`, which permanently removes all messages for that contact from the local database. No mechanism exists to delete messages from the recipient’s device or from relay (relay auto-deletes after retrieval or 7-day TTL anyway).

84. **Account deletion is not implemented.** No “delete account” feature exists. If implemented, it would need to: delete all local DB tables (identity, contacts, messages, groups), clear secure storage secrets (`identity_private_key`, `identity_mnemonic12`, `identity_ml_kem_secret_key`, `db_encryption_key`), and deregister the FCM push token from the relay. **⚠️ Gap: This feature needs to be built.**

85. **Not implemented** — No disappearing/ephemeral messages feature.

---

## 16) User controls and privacy settings

86. Available controls:
    * **Who can message me**: Not configurable — anyone with your QR code can send a contact request
    * **Who can find me**: Only via in-person QR scan or introduction (no directory to control)
    * **Profile photo/status/last seen visibility**: No visibility controls (no last-seen or status features exist)
    * **Read receipts**: Tracked locally only; never sent to sender (not configurable since they’re never shared)
    * **Group invites**: User approves group joins via incoming messages
    * **Blocked users**: Yes — contacts can be blocked (`is_blocked` flag), preventing message receipt
    * **Archive contact**: Yes — hides conversation without deleting
    * **Delete contact**: Yes — permanently deletes contact + all messages
    * **Delete group**: Yes — permanently deletes group + all messages

87. **No** — No data export/download feature. **⚠️ Gap: Needed for GDPR Art. 20 (data portability).**
88. **N/A** — No analytics or ads to opt out of.
89. **N/A** — No contact syncing feature to disable.

---

## 17) Legal bases and compliance posture

90–93. **[POLICY DECISION NEEDED]** — Legal bases, LIA, DPIAs are legal/policy decisions. The app does not process sensitive data categories (health, biometric, political). Biometric data (face recognition, fingerprints) is not collected.

---

## 18) User rights handling (DSAR)

94–97. **[POLICY DECISION NEEDED]** — No DSAR submission mechanism exists in the app. **⚠️ Gap: Needs a contact method or in-app flow for access/deletion/correction requests.**

---

## 19) Security practices

98. **Encryption at rest**: SQLCipher (AES-256) with random 256-bit key in platform secure storage (iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` / Android EncryptedSharedPreferences backed by Android Keystore). Identity secrets (Ed25519 private key, BIP39 mnemonic, ML-KEM-768 secret key) stored only in secure storage — never in the database (DB columns enforced NULL via CHECK constraints in migration 005).

    **Encryption in transit**: libp2p Noise protocol + TLS for all P2P and relay connections. Per-message E2EE: ML-KEM-768 key encapsulation + AES-256-GCM authenticated encryption (1:1, v2 envelope). Group messages: encrypted with group shared key + Ed25519 signature (v3 envelope). Contact requests: X25519 ECDH + AES-256-GCM.

99. **Access controls**: Private keys never leave secure storage. Database accessible only by app process. Per-contact ML-KEM public keys exchanged in encrypted contact requests. Group encryption keys stored encrypted in `group_keys` table per key generation.

100. **[POLICY DECISION NEEDED]** — No evidence of security audits, pen tests, or bug bounty program in the codebase.
101. **[POLICY DECISION NEEDED]** — No incident response plan or breach notification process defined.
102. **No** — No transparency reports.

---

## 20) Cookies and website tracking

103. **No website** — No marketing site, no web app, no help center.
104. **N/A**
105. **N/A**

---

## 21) Payments and financial data

106. **No** — No subscriptions, purchases, or payment features.
107. **N/A**
108. **No** — No payment card data stored.
109. **N/A**

---

## 22) Communications (email/SMS) and marketing

110. **No** — The app sends no emails, no SMS, no marketing communications of any kind.
111. **N/A**
112. **No** — No referral program.

---

## 23) Governance and policy operations

113–115. **[POLICY DECISION NEEDED]** — No policy versioning or update notification mechanism exists in the app.

---

## 24) “Strong compared to known apps”

116. **YES** — No data sales infrastructure exists. Zero data monetization.
117. **YES** — Zero ad SDKs, zero ad network integrations.
118. **YES** — IDFA/AAID are never accessed or collected.
119. **YES** — No data broker integrations or data sharing agreements.
120. **YES** — Minimal metadata: only peer IDs, timestamps, and group membership. No location, no IP logging, no device fingerprinting, no contact upload.
121. **YES, feasible** — Only vendor receiving user data is Firebase/Google (FCM push tokens). A vendor list would be very short.
122. **YES, feasible** — Relay: 7-day TTL (inbox + media). Local: indefinite until user deletes. FCM tokens: no defined expiry (gap).
123. **YES** — E2EE is on by default for all new contacts (ML-KEM keys auto-generated). Groups are always encrypted. Only legacy contacts without ML-KEM keys fall back to plaintext v1.
124. **YES, with caveat** — Relay stores only encrypted messages it cannot decrypt, for max 7 days, deleted on read (1:1). This is strictly a store-and-forward delivery queue, not persistent storage.
125. **YES, feasible** — The data model is simple enough for a clear table:

| What We Collect | Why | How Long | Who We Share With |
|---|---|---|---|
| Peer ID (cryptographic identifier) | Routing messages | Indefinite (local) / transient (relay) | Contacts, relay |
| Username | Display name for contacts | Indefinite (local) | Contacts |
| Avatar photo (EXIF-stripped) | Profile picture | Indefinite (local) | Contacts |
| Ed25519 + ML-KEM public keys | Encryption & verification | Indefinite (local) | Contacts |
| Message content (encrypted) | Communication | Indefinite (local) / max 7 days (relay, encrypted) | Recipient only |
| FCM push token | Delivering notifications | Until deregistration | Firebase/Google |
| Group membership | Group messaging | Indefinite (local) / transient (relay) | Group members |

---

## 25) Documents/artifacts

126. **Architecture**: Decentralized P2P (libp2p) with circuit relay for NAT traversal. Local WiFi fallback (mDNS + WebSocket). Single relay server at `mknoun.xyz`. All user data on-device in SQLCipher DB. Secrets in platform secure storage.
127. **SDK list**: See Q72 above. Firebase (FCM push only). No events collected for analytics.
128. **[POLICY DECISION NEEDED]** — No existing privacy policy or ToS drafts found.
129. **[POLICY DECISION NEEDED]** — App store nutrition labels / Data Safety not yet configured.
130. **Relay retention**: `maxMessageAge = 7 days`, `maxMessagesPerPeer = 100`, `maxMessagesPerGroup = 500`, `groupMessageTTL = 7 days`, `mediaTTL = 7 days`, `maxBlobsPerPeer = 50`, prune interval = 1 hour.
131. **Vendor list**: Firebase/Google (FCM). That’s it.

---

## ⚠️ Key Gaps to Address Before Publishing a Privacy Policy

1. **Push notification content** — 1:1 messages include plaintext text in FCM payloads (visible to Google/Apple infrastructure). Consider sending only a “new message” signal and decrypting in-app.
2. **No account deletion feature** — Needed for GDPR Art. 17 (right to erasure).
3. **No data export feature** — Needed for GDPR Art. 20 (data portability).
4. **No age gate** — Needed if serving EU (GDPR, min 16) or US (COPPA, min 13) markets.
5. **No disappearing messages** — Not legally required but expected for “strong privacy” positioning.
6. **FCM push token cleanup** — Tokens are not deregistered on app removal; should be cleaned up.
7. **v1 plaintext fallback** — Legacy contacts without ML-KEM keys receive unencrypted messages. Consider deprecating v1.
8. **No DSAR mechanism** — Need a way for users to submit data access/deletion requests.
