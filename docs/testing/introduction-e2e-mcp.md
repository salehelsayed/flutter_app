# Introductions: Pass and notification routing through MCP

Execution owner: `flutter_app`. Astra prepared these steps from source; every
device leg below is unrun by Astra. Use actual Appium MCP tools, existing setup
checks, owned device leases and the exact candidate/artifact/configuration.
Keep raw identities, payloads and screenshots in the private run directory.
Report first failures and restore only this run's state.

Use three available owned app instances for introducer I, original recipient P
and introduced person Q. Shared Android behavior defaults to a USB Android plus
available emulators. Do not displace another campaign or create a hardware
requirement for an unavailable target. IN-008's iOS boundary is a separate leg
on an available iOS target; a shipped-iOS claim needs the actual signed candidate.
Missing provider access or a missing artifact is a setup/evidence blocker, not
unavailable hardware.

## Reuse and scope

| Item | Existing evidence to reuse | Missing execution prepared here |
| --- | --- | --- |
| IN-003 | Pass/terminal/late-accept host controls | real three-person Pass UI, delivery and restart |
| IN-008 | resolver, Orbit route and consent roundtrip host controls | real OS notification delivery and tap, platform/state separately |

The existing `run_production_introduction_mutual.dart` and
`run_production_introduction_offline.dart` campaigns remain useful for mutual
acceptance and offline completion. Their runner requires three disposable
Android emulator roles with `prepareContactMesh: false`; retain that topology
when using that runner. The offline criteria explicitly leave Pass/late-accept
fencing to IN-003. Those campaigns and the direct-notification-open campaign do
not substitute for the two MCP legs here. Add no generic UI driver.

Useful exact host controls, with scope kept separate from native execution:

- `test/features/introduction/application/pass_introduction_test.dart`
- `test/features/introduction/application/mutual_acceptance_test.dart`
- `test/features/introduction/application/edge_cases_test.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/application/resolve_introduction_notification_target_use_case_test.dart`
- `test/features/push/application/intro_notification_orbit_route_test.dart`
- `test/integration/notification_tap_smoke_test.dart`
- `test/features/introduction/integration/notification_consent_route_roundtrip_test.dart`

## IN-003 — either participant can Pass before mutual acceptance

Planning estimate: 15–25 minutes for the four orders, excluding setup.

1. Establish only I↔P and I↔Q through the real consent flow. P/Q start unlinked;
   do not seed an all-pairs contact mesh. Record existing contacts and unrelated
   histories so a missing new relationship cannot hide damage to an old one.
2. Use a fresh owned introduction and eligible P/Q identities for each row below.
   Create through I's supported UI, prove both intended offers arrived, then
   perform exactly the ordered actions. Do not reset identity or clear app data
   at a persistence checkpoint.

   | Order | First action | Second action | Expected terminal result |
   | --- | --- | --- | --- |
   | P declines first | P taps Pass while Q is pending | deliver queued status normally | passed |
   | Q declines first | Q taps Pass while P is pending | deliver queued status normally | passed |
   | P accepts first | P explicitly accepts | Q taps Pass | passed |
   | Q accepts first | Q explicitly accepts | P taps Pass | passed |

3. Let ordinary live/inbox processing settle on all three instances. The current
   introduction is terminal `passed`; P/Q have no new mutually authorized
   relationship or successful first exchange. An optimistic local pending
   intent is not proof of mutual acceptance. Preserve I's original contacts and
   histories. The UI action is Pass, not a separate invented Declined state;
   secrecy about which participant passed is not this case's contract.
4. Restart the participants and introducer without clearing data. Reopen the
   exact introduction: terminal state persists, no accept action revives it and
   no new P↔Q conversation/contact appears through replay. Do not exercise Pass
   on an already mutually accepted introduction and expect it to undo consent;
   that terminal state has a different existing host control.
5. For the delayed-accept leg, retain an actual same-introduction acceptance
   queued through an existing supported offline/outbox path, then deliver it
   after the other participant's Pass has become terminal. It must not revive
   the introduction or create the relationship. Record the actual queue/order
   observations. If this build cannot stage and observe that exact order,
   retain the host causal late-envelope proof and mark the native late-accept
   injection unrun/incomplete. A later tap on a different introduction or a
   fabricated notification is not that control. Add no production fault seam.

## IN-008 — notification opens the current authorized destination

Planning estimate: 20–35 minutes per platform, excluding provider/setup time.
Use fresh introductions for independent rows and preserve the original role
mapping. Record the native permission/channel state and an eligible delivered
notification before relying on a negative result.

Source contract: `resolve_introduction_notification_target_use_case.dart:94–105`
routes a canonical acceptance to a conversation only when the viewer is I, the
exact introduction still exists and its original recipient P is still a
contact. It always selects P's conversation, even when Q sent the acceptance.
Other viewers/offers/unanchored messages fall back to Intros. Its existing
status convergence window is 45 seconds; navigation need not wait for it.

| Real notification and viewer | Expected destination and consent check |
| --- | --- |
| Offer delivered to participant P or Q | Intros with the current intended offer; opening does not accept or create the P/Q relationship |
| Mutual-acceptance update delivered to participant P or Q | current Intros state; prior explicit accepts explain the established pair, and tapping adds no duplicate contact or consent |
| Canonical acceptance delivered to introducer I, from P | original P conversation, with current introduction state |
| Canonical acceptance delivered to introducer I, from Q | the same original P conversation, with current introduction state |
| Missing introduction, unanchored/non-accept payload, non-introducer viewer, or missing original P contact | generic Intros fallback rather than another private conversation |

1. On each available platform, exercise an actual recipient offer and actual
   mutual-acceptance notification from supported background, OS-terminated and
   locked states. Record the precise lifecycle state and target/artifact per
   cell. A user force-stop/force-quit is not ordinary OS termination; do not
   claim delivery in a state the OS intentionally suppresses. Use existing
   verified owned-process/lifecycle support where MCP alone cannot establish
   the state, and keep setup limitations explicit. No replacement UI harness.
2. Trigger through the real introduction/accept actions, retain native delivery,
   then tap the actual OS notification through MCP. Capture the first route and
   the settled current state. For a locked device, complete only the existing
   authorized unlock flow; do not collect or transmit a passcode. If access
   cannot be completed, record that setup blocker without claiming the tap leg.
3. Check exact intended introduction and viewer role, contacts before/after,
   and whether any accept action occurred. Opening an offer grants no consent;
   opening a mutual update neither accepts again nor duplicates a contact.
   Existing unrelated conversations stay unchanged. Test I's P-accept and
   Q-accept routing separately with real canonical acceptance notifications;
   Q's identity must not redirect I into Q's private conversation.
4. Retain a real notification, then make the exact introduction terminal through
   Pass, expiry or a supported deletion before tapping it. Judge the current
   state and authority: no resurrection, no automatic acceptance, no unrelated
   conversation. If the OS/app has already removed the card, record that actual
   cancellation instead of reposting a synthetic payload to manufacture a tap.
   Expiry must be naturally available or already staged by existing fixtures;
   do not change the host/device clock or require a long wait in this quick leg.
5. A retained terminal introduction does **not** impose a blanket Intros-only
   rule on I. If the canonical acceptance anchor and original P contact remain,
   opening P's existing conversation can still be correct; it must show current
   state and cannot revive P/Q consent. A genuinely missing row/contact uses
   fallback. Host resolver controls cover malformed/unanchored inputs that the
   real UI/provider cannot produce; keep them labelled as host controls rather
   than creating a new push-injection path.
6. Restore only owned notification, network and UI state. Retain first-attempt
   failures and platform-specific results; a passing Android tap does not fill
   an unrun iOS cell or certify a different signed artifact.

Record one row per case/platform/state: source/artifact/configuration, actor
roles, actual introduction/notification anchor, delivery evidence, first and
settled route, persisted status, contacts/consent before and after, restart,
raw evidence paths, cleanup and scoped verdict. Keep manual MCP observations
distinct from host test outputs. Missing raw observations remain incomplete;
unavailable hardware is N/A under project policy, with current discovery proof.
