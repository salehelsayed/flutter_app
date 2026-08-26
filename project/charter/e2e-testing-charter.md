# Mknoon behavior and test evidence charter

## Purpose

The dashboard reconciles product intent, static implementation evidence and
executed proof. It is not permitted to turn repository structure into a claim
that user-visible behavior works.

## Evidence rules

1. Every qualifying test maps to at least one stable behavior ID.
2. A Graphify node or edge is implementation evidence only. It does not prove
   reachability, runtime wiring, correctness or a platform boundary.
3. No Graphify match means “not evidenced in the searched graph,” not “missing
   from the product.” A reviewed, bounded source investigation is required
   before calling something an implementation gap.
4. A test artifact means proof is declared. Only a recorded run means it was
   observed, and the record must include revision, command, platform and target.
5. Passing evidence from another revision is stale. A dirty application tree
   also prevents a prior run from being presented as current proof.
6. Required native, relay, encrypted-storage, provider or device behavior must
   cross its real proof boundary. A host fake cannot silently satisfy it.
7. End-to-end tests are for observable, meaningful behavior involving multiple
   real owners. Internal relationships normally belong in unit, host-native or
   contract tests.
8. One Graphify relationship never justifies one new end-to-end test. Add a
   scenario only for user experience, privacy, security, durability, data
   integrity or an explicit product requirement.
9. Device proof is availability-bounded. Resolve the live device matrix at run
   time and pin commands to exact discovered IDs. An unavailable required
   version is not applicable with the project-policy reason, never a fabricated
   pass or an environment blocker.
10. The default two-peer topology for non-iOS-specific behavior is a connected
    physical Android device plus an available Android emulator. iOS proof is
    separate and required only for an iOS boundary or an explicit parity claim.

## Derived vocabulary

| State | Meaning |
|---|---|
| Implementation candidate | All required exact trace anchors were found |
| Implementation partial | Some anchors were found; at least one required anchor was not |
| Implementation not evidenced | No declared anchor matched in the searched graph scope |
| Proof declared | Mapped test artifacts exist but no current qualifying run is recorded |
| Proof partial | Some, but not all, required proof boundaries passed |
| Verified candidate | Static candidate plus current required proof; still not a reviewed implementation claim |
| Covered | Current required proof plus a revision-matched implementation review |
| Failing proof | A current qualifying run failed |
| Intent open question | Product intent is provisional and must not become a final story |

The dashboard must display graph freshness, graph fingerprint, repository
revision and dirty state beside these assessments.

## Notification-specific constraint

The notification PRD’s OQ-01 and OQ-05 remain open. OQ-02 through OQ-04 are
adopted decisions. Same-chat cue assertions remain provisional until OQ-01 is
resolved; the system must not invent a haptic, setting or mute subsystem.
