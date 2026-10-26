# RG-001: store 126 to store 127, with soft/forced update variants

Execution owner: `flutter_app`, using actual Appium MCP tools after the current
127 lanes release their targets. Host preparation only; no device leg has been
run by Astra. Planning estimate: 20–35 minutes plus store availability/downloads.
Use Pixel from Play and the available iPhone 11 from TestFlight. If that exact
model is unavailable, record its leg N/A under project policy; another available
iPhone may provide a separately labelled iOS leg. Do not require absent hardware.

## 1. Establish the actual store baseline before upgrading

1. In Play on Pixel and TestFlight on iPhone, select/install **126 from the
   store**, then prove the installed app reports build 126. TestFlight's Previous
   Builds is usable if 126 is actually offered. Capture both the store/build
   selection and the installed build, distribution channel, bundle/package and
   release-manifest/source/artifact bindings supplied by the coordinator.
2. If a store no longer offers 126, record `BLOCKED: store 126 baseline
   unavailable`. Do not replace it with a sideload, forced package downgrade,
   source build or an app merely labelled 126. The official store selection in
   step 1 must preserve the existing app data. If authentication is required, leave that
   access issue to the coordinator; do not read or enter credentials.
3. Use only owned test conversations/groups. Preserve the owner identity,
   existing chats, contacts, membership and history; no uninstall/data clear,
   restore-from-migration fixture, imported database or regenerated identity.
   An existing non-126 installation is not permission to erase the owner's app.
4. Make a private before-state table for **each** platform:

   | Surface | Exact retained observation |
   | --- | --- |
   | Account/linking | existing identity and linked test peers; no secret-key export |
   | Contacts | test contact names/count and accepted relationship |
   | Chats | owned canary message IDs/content/order and a retained historical row |
   | Groups | owned group identity, membership/roles and a historical message |
   | Settings | actual current language/theme/photo-quality/privacy settings available in UI |
   | Media/unread | one owned full-image open and current unread state, where present |

   Save exact private content and identifiers locally, not in coordinator mail.
   Send a baseline exact text each way while both are 126; record one received
   copy and the existing trusted relationship. Avoid resetting settings to defaults.

## 2. Receive the coordinator's chosen policy variant

The owner has not chosen soft versus forced. Keep both alternatives below.
The coordinator supplies the approved active policy and its accepted freshness:
soft means latest 127 / minimum 126; forced means latest 127 / minimum 127.
This script contains no policy publication, signing, version-file upload or
relay access. Do not inject debug policy fixtures into the store-installed 126.

Perform one chosen variant on each 126 installation before its upgrade. If both
are requested, collect both pre-upgrade variants **while still on 126**, under
the coordinator's approved policy transitions, then upgrade once. Never update
to 127 and relabel a later check as an old-126 test, or downgrade to repeat it.

A soft decision rechecks on resume only when due (six-hour policy); a fresh
process launch checks again. Use an ordinary owned-app terminate/relaunch to
observe a newly supplied policy, preserving all data. Hard decisions recheck
on resume. Record policy/setup not ready separately from a UI failure; do not
change the clock, clear secure state or silently extend the case deadline.

## 3. Mandatory old-126 Update-button destination check

Before either phone installs 127, open its **own build-126** notice and tap its
Update action through MCP. Save the old app's build, visible action, native
handoff and destination. On iPhone with TestFlight installed, reach Mknoon's
TestFlight entry; on Android, reach Mknoon's Play entry. A browser hop must end
at the intended TestFlight/Play product, not an unrelated page or App Store.
Return without installing yet so the X behavior can also be checked.

Source audit: `update_store_urls.dart:9,12` in both `9ec2091a3` and the recorded
iOS-126 build source `f140206c5` selects TestFlight/Play. The controller, policy,
service, hard gate and URL files at `f140206c5` are byte-identical to the audited
preparation base. That is a source expectation, **not** evidence of the actual
installed old button. `docs/release/ios-builds.md` at `53fd89cff` still labels its
126 row PENDING; use actual store inventory/installation evidence, not that row
alone, as publication proof. Do not use 127's fixed button to certify 126.

If the old button opens the wrong destination, retain and report that exact
old-build defect to Kayan without an app patch. The ordinary store UI can still
collect preservation evidence, but it does not turn the failed button into PASS.

## 4a. Soft: latest 127, minimum 126

1. With 126, no active call and the accepted soft policy, open Orbit/home and
   require the update banner. App navigation and existing content remain usable.
2. Complete the old-button destination check above, return, then tap its X.
   Require the banner to dismiss and the underlying navigation/content to work.
   A cold relaunch with the same latest 127 remains dismissed when persistence
   succeeds; record the actual outcome, not a new policy or cleared-data result.
3. Use the real store entry to perform the in-place 127 upgrade in section 5.
   Prove installed 127 and the accepted policy after the update. Banner absence
   alone is insufficient because the X already hid it while still on 126.

## 4b. Forced: latest 127, minimum 127

1. With 126, no live incoming/outgoing/active call and the accepted hard policy,
   require the blocking update screen. Its installed/minimum build labels and
   Update action must be readable; taps/Back must not reach hidden app content.
2. Complete the old-button destination check, return, then test the visible X.
   **The X dismisses this requirement for the current app session**, allowing
   the existing app/navigation to be used. It does not erase data, update the
   build or promise a permanent minimum-version waiver.
3. Terminate/relaunch the same app without clearing storage. With unchanged
   hard policy, the blocking screen returns. This session-only rule is visible
   in `update_required_gate.dart:68,159,194,232` and the 126 source `f140206c5`.
4. Use the real Update/store route to install 127; after the app resumes/reopens
   on 127, this requirement is gone. Record the first failure if X, native
   navigation or the destination differs; do not repair app behavior here.

## 5. Upgrade one phone at a time and prove preservation

1. Upgrade Pixel **in place through Play** to 127. Leave iPhone on 126 for the
   intermediate compatibility check. Verify installed 127 and compare every
   Pixel before-state row, including usable history, contacts, group membership
   and settings. No onboarding, new identity or re-pairing may be needed.
2. Exchange a new exact text 126→127 and 127→126 through the retained contact;
   require exact content/order and one received copy within 60 seconds each.
3. Upgrade iPhone **in place through TestFlight** to 127. Compare every iPhone
   before-state row. Verify both installed builds and store channels again.
4. Exchange new direct messages both ways and an owned group message to every
   entitled receiver. Reopen retained history and the owned media. Terminate/
   relaunch both without clearing data; state/settings and new message identity,
   content, order and uniqueness remain intact.
5. With installed 127 and the accepted chosen policy, no outdated-126 banner or
   blocking screen remains. Retain before/after screenshots, actual store
   provenance, builds, policy observations, message/group checks and any first
   failure in the private attempt directory. Restore only this run's owned state.

## Verdict and scope

Record separately per platform/variant: store-126 baseline, old-button
destination, X behavior, actual store upgrade, preservation table, old/new and
127/127 messaging, and post-upgrade notice removal. Missing observations remain
incomplete; unavailable targets are N/A; unavailable store builds/policy/access
are setup blockers. No successful source test substitutes for store execution.

Reuse the existing update campaign/`production_update_check_criteria.dart` for
adjacent signed-policy/UI contracts, not store-install proof: its controlled
fixtures explicitly leave real store installs separate. This packet supplies
the RG-001 ordinary preservation/store observations; it does not close the
wider quiet-message/relay assertions in mandatory `signed-upgrade-compat`.
No host boolean checklist is presented as independent proof of store behavior.
