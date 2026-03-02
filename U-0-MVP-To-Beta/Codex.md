 1. What is missing before MVP focus-group testing

  - Release analytics is missing: event logging is debug-only in flow_event_emitter.dart:6 (/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/utils/flow_event_emitter.dart:6).
  - Crash observability is missing: dependencies include firebase_messaging but not analytics/crash SDKs in pubspec.yaml:53 (/Users/I560101/Project-Sat/mknoon-2/flutter_app/pubspec.yaml:53).
  - Security/reliability gaps that can skew feedback:
      - Contact request can still fall back to plaintext v1 in send_contact_request_use_case.dart:195 (/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/contact_request/application/send_contact_request_use_case.dart:195).
      - Local WiFi transport uses ws:// in local_ws_server.dart:385 (/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/local_discovery/local_ws_server.dart:385).
      - Relay inbox is in-memory (restart risk) in inbox.go:174 (/Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server/inbox.go:174).
  - Test hardening is partial: docs still report significant gaps in test-gaps.md:1 (/Users/I560101/Project-Sat/mknoon-2/flutter_app/UI-13-NewFeed/test-gaps.md:1).
  - No CI/release automation: no .github, .circleci, fastlane detected.
  - Operationally missing for focus groups: consent/privacy sheet, moderator script, and structured feedback form (outside code).

  2. How many focus groups

  - Recommended: 4 groups total (2 groups per key segment).
  - If you treat users as one homogeneous segment: 3 groups is a practical minimum.
  - Why: saturation research shows 2–3 groups often capture most themes, 3–6 captures deeper coverage.

  3. How many people per group

  - Target: 6–8 participants per group.
  - Recruit 8–10 to absorb no-shows and still run with 6–8 live participants.

  4. What feedback/KPIs to track

  - Qualitative (focus group):
      - Onboarding clarity (identity create/restore).
      - Contact exchange comprehension (QR flow).
      - Trust perception (“is this private/safe enough?”).
      - Messaging confidence (send/deliver/reply expectations).
      - Biggest confusion/friction moments.
  - Quantitative (must-have MVP KPIs):
      - Activation: % who complete first successful message exchange in 24h.
      - Time-to-first-value: install -> first delivered message.
      - Critical task success: onboarding, add contact, send message, receive reply.
      - Reliability: delivery success rate, retry/fallback rate.
      - Stability: crash-free users/sessions.
      - Retention: D1, D7.
      - UX score: SUS + “would use weekly” intent.

  5. What is meaningful in 60 days

  - Meaningful target in 60 days:
      1. Week 1–2: add analytics/crash reporting + fix top blocking reliability issues.
      2. Week 3–4: run round 1 (2 groups, ~12–16 active participants), prioritize top 10 issues.
      3. Week 5–6: ship fixes + tighten test gates.
      4. Week 7–8: run round 2 (2 groups), validate improvements.
  - Success by day 60:
      - Activation >= 70%
      - Critical task success >= 85%
      - Crash-free users >= 97%
      - Clear list of top 5 product changes with evidence
      - Go/no-go decision for larger beta

  Sources

  - NN/g focus-group guidance: https://www.nngroup.com/articles/focus-groups/
  - NN/g iterative small-sample testing: https://www.nngroup.com/articles/why-you-only-need-to-test-with-5-users/
  - Focus-group saturation evidence (Hennink et al.): https://pmc.ncbi.nlm.nih.gov/articles/PMC6635912/
  - Google HEART framework: https://research.google/pubs/measuring-the-user-experience-on-a-large-scale-user-centered-metrics-for-web-applications/
  - Firebase crash-free metrics definitions: https://firebase.google.com/docs/crashlytics/crash-free-metrics
