# Task Prompt: FL_XS_05 - StartupDecision and decideStartupRoute()

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M1 – Identity Initialization (First Run)

App Startup Behavior:
  - If DB has identity row (id=1) → load it, go to main app
  - If DB has no identity row → go to IdentityChoiceScreen (onboarding)

Existing components:
  - IdentityRepository: Interface with loadIdentity() that returns IdentityModel?
```

---

## Task Definition

```
[TASK FL_XS_05 – StartupDecision enum + decideStartupRoute()]

Owner: Flutter

Goal:
  Decide at startup whether to go to main app or identity onboarding.

What to implement:
  - enum StartupDecision { hasIdentity, needsIdentity }
  
  - Function:
      Future<StartupDecision> decideStartupRoute(IdentityRepository repo) async {
        final identity = await repo.loadIdentity();
        return identity == null
            ? StartupDecision.needsIdentity
            : StartupDecision.hasIdentity;
      }

Inputs:
  - IdentityRepository repo

Outputs:
  - StartupDecision.hasIdentity if identity != null
  - StartupDecision.needsIdentity if identity == null

Flow_events:
  - Before calling repo.loadIdentity():
      - layer: "FL", event: "ID_STARTUP_DECIDE_ROUTE_CALL", details: {}
  - After decision - has identity:
      - layer: "FL", event: "ID_STARTUP_HAS_ID", details: { "hasIdentity": true }
  - After decision - needs identity:
      - layer: "FL", event: "ID_STARTUP_NEEDS_ID", details: { "hasIdentity": false }

Constraints:
  - Do not include navigation logic here; just return the decision

Deliverable:
  - File: lib/features/identity/application/startup_decision.dart
```

---

## Begin Implementation

Output the full code for `startup_decision.dart`.
