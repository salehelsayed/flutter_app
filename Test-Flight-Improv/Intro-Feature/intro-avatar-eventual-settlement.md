# Intro Avatar Eventual Settlement

## 1. Title and Type

- Title: Intro avatar eventual settlement after mutual acceptance
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/Intro-Feature/intro-avatar-eventual-settlement.md`

## 2. Problem Statement

When two people complete an introduction, the app creates the new contact and
tries to fetch that contact's avatar as follow-up work.

Today the contact itself is preserved, which is good, but the avatar follow-up
is only best-effort. If the relay or avatar source is not ready at the moment
of mutual acceptance, the app retries once and then gives up.

From the user's perspective, that means a newly created intro connection can
remain visually incomplete forever even though the connection itself succeeded.
The reliability problem is not contact creation. It is the lack of a recoverable
path for the avatar to eventually settle.

## 3. Impact Analysis

- Who is affected: users who complete an introduction and expect the resulting
  new contact to look fully settled shortly after the connection is created.
- When the issue appears: after mutual acceptance when avatar download is
  unavailable, delayed, or transiently failing.
- Severity: low to medium. The contact is created, so the social action
  succeeds, but the resulting connection can remain visually incomplete.
- Frequency: not established by repo evidence. The repo shows the current retry
  behavior and partial coverage, but it does not contain production telemetry
  for how often avatar fetch misses happen.
- User-visible consequence: a new connection can exist without the expected
  avatar ever appearing later, which makes the intro feel only partially
  finished.

## 4. Current State

- `handleMutualAcceptance(...)` creates the new contact and then starts avatar
  download as fire-and-forget work in
  `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`.
- That path:
  - tries one avatar fetch immediately,
  - retries once after a short delay when the first result is null,
  - emits `INTRO_AVATAR_DOWNLOAD_ERROR` on failure,
  - and does not keep any durable retry substrate after that.
- Existing tests already prove the narrow no-rollback contract:
  - `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
    proves avatar retry failure does not remove the created contact or the
    intro system message.
- Existing tests also prove the adjacent completion path:
  - system message insertion and contact creation after mutual acceptance
  - intro listener notification behavior for the new connection
- The current repo does not contain direct proof that avatar settlement
  eventually recovers later after the initial failure window has been missed.

## 5. Scope Clarification

- In scope: the user-visible expectation that avatar follow-up for a new intro
  connection has a recoverable path and does not silently stop forever after one
  transient miss.
- In scope: preserving contact creation, intro system message insertion, and
  the existing no-rollback contract while strengthening follow-up reliability.
- In scope: later app reopen, resume, or retry-friendly recovery if that is the
  product path chosen in implementation.
- Out of scope: changing how mutual acceptance creates the underlying contact.
- Out of scope: redesigning avatars globally across contacts, groups, feed, or
  profile flows unrelated to Intro.
- Out of scope: changing intro push routing, intro dedupe, or Orbit/Feed intro
  presentation rules.
- Accepted ambiguity for later implementation: this spec does not require a
  specific retry mechanism. It only requires that avatar follow-up has a
  recoverable user-visible completion contract rather than a single fire-and-
  forget window.

## 6. Test Cases

### Happy Path

- `TC-IAES-HP-01` Given two users reach mutual acceptance, when the new contact
  is created, then the contact appears immediately and its avatar eventually
  settles successfully.
- `TC-IAES-HP-02` Given the first avatar attempt is temporarily unavailable,
  when the app later gets another valid chance to fetch it, then the new
  contact's avatar still appears without requiring the intro to be repeated.

### Edge Cases

- `TC-IAES-EC-01` Given mutual acceptance succeeds while avatar fetch returns no
  result at first, then the new contact still exists immediately and the app
  retains a recoverable path to settle the avatar later.
- `TC-IAES-EC-02` Given the app is reopened or resumed after the initial avatar
  fetch window was missed, then the contact does not stay permanently avatar-
  incomplete if the avatar becomes available later.
- `TC-IAES-EC-03` Given the new contact already has all intro provenance and the
  intro system message inserted, then later avatar recovery must not duplicate
  the contact or duplicate the intro system message.

### Regressions To Preserve

- `TC-IAES-RG-01` Bug regression: Given avatar download fails during
  mutual-acceptance follow-up, then the created contact is still preserved and
  the intro system message is still preserved.
- `TC-IAES-RG-02` Given mutual acceptance creates the new contact, then the
  contact is usable immediately even before avatar follow-up has completed.
- `TC-IAES-RG-03` Given an intro never reaches mutual acceptance, then no new
  contact avatar flow should be started for that unfinished intro.

### Existing Coverage And Gaps

- Existing partial coverage:
  - `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`
  - `test/features/introduction/application/introduction_listener_test.dart`
  - `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
- Current gap:
  - the repo proves `avatar failure does not roll back the contact`, but does
    not yet prove eventual avatar settlement after the first failure window has
    passed.
- Current gap:
  - no current smoke or end-to-end intro proof explicitly exercises later avatar
    recovery after transient failure.
