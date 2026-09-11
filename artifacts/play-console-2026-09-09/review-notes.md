# mknoon Play Console review — September 9, 2026

## Tester link

https://play.google.com/apps/internaltest/4701439081038788969

The active internal track shows release **114 (1.0.1)**. The selected email list is **mknoon-List-1**, with **30 users**. Each tester should use the Google account included in that list, join the test, and follow the installation link. The Console still labels the store app `com.mknoon.app (unreviewed)`.

## Changes and outstanding declarations

- **Full-screen intent:** saved in Play Console with **Making and receiving calls** and **Yes** to requesting pre-grant at installation. The Console confirmed “Change saved. Send for review in Publishing overview.” This has not been sent for review; eligibility remains Google's decision.
- **Foreground services:** the browser has unsaved selections for **Data sync → Backing up, restoring**, **Microphone → Background audio input**, and **Phone call → Voice over Internet Protocol (VoiP), telecom APIs**. Each selected use case requires a real demonstration video link. No placeholder video has been entered.
- **Child safety:** the owner approved the policy and it is published at **https://mknoon.space/child-safety**. Contact: **Saleh Elsayed, saleh.m.elsayed@proton.me**, as confirmed by the owner. The public URL and contact are entered in the browser draft. The two reporting/compliance certifications have not been checked; the new in-app contact still needs to ship in the reviewed build.

After saving full-screen intent and refreshing Publishing overview, the Console shows **14 pending changes** and **2 remaining issues**.

The foreground-service choices are based on the current source: `MigrationKeepAliveService` holds an explicit data-sync service during Move Account, and `MknoonCallForegroundService` declares phone-call and microphone service types. A recording must demonstrate the actual build being submitted. These source observations do not verify every older bundle still active in Play Console.

## Child-safety owner review

The approved, published policy says mknoon is **18+**, uses **QR contact invitations**, prohibits child sexual abuse and exploitation, and accepts safety reports at the confirmed email address. It explains that the developer cannot read end-to-end encrypted conversations.

The owner explicitly approved the policy's operational commitments: monitor and review reports, take appropriate action on services under the developer's control, and report identified CSAM to competent regional or national authorities when legally required. These remain ongoing operational responsibilities.

The Play Console also requires an **in-app reporting mechanism**. At the owner's request, a **Safety & support** panel has now been added to the current Flutter source, reachable from the Settings help icon. It displays the reporting email, opens an email draft with a static subject, offers a copy-address fallback, and links to the published standards. It attaches no app or conversation data and does not send a report automatically. The panel is localized in English, German, and Arabic.

The active internal release **114** has not been replaced in this session. Build and upload a release containing this change before certifying that the reviewed app includes the reporting route. No assertion has been made that this source change is already installed on testers' phones.

Verification: **29 focused Flutter tests passed** using the installed Flutter **3.47.2** SDK. Coverage includes the real Settings-to-panel route, exact email recipient and subject, unavailable email handlers, clipboard failures, the public policy link, completion after dismissal, 320px layouts at 1.5× text in all three languages, and existing Settings layout/sub-sheet behavior. The SDK on the default shell path is older (3.41.4), so commands used `/Users/I560101/development/flutter-3.47.2/bin/flutter`.

Targeted static analysis of the ten changed Dart files passed with **no issues**. Diff checks passed, the existing localization entries and pre-existing Settings edits were preserved, and the architecture graph was refreshed incrementally. This verification used widget tests; it does not claim a device installation or a Play Store rollout.

Focused test command:

```sh
/Users/I560101/development/flutter-3.47.2/bin/flutter test test/features/settings/presentation/widgets/safety_support_sheet_test.dart test/features/settings/presentation/screens/settings_sub_sheets_test.dart test/features/settings/presentation/screens/settings_one_screen_layout_test.dart --reporter expanded
```

Google explicitly applies the child-safety requirement to Social apps even if children are excluded or the app is age-gated:
https://support.google.com/googleplay/android-developer/answer/14747720?hl=en

## Website hosting and published update

- **Live host:** Cloudflare **Pages**, project **mknoon-website**.
- **Dashboard:** https://dash.cloudflare.com/6cd83cfe724eb5e0b112ae0c88c672a7/pages/view/mknoon-website
- **Production domains:** `mknoon.space` and `mknoon-website.pages.dev`.
- **Current deployment:** `https://d01c54fd.mknoon-website.pages.dev` (ID `d01c54fd-f8ab-4a81-ba61-19bcad5d81c7`).
- **Previous deployment:** `https://0d517ce8.mknoon-website.pages.dev`.
- **Deployment model:** direct/manual upload; the project list reports no Git connection.
- **Related repository:** https://github.com/salehelsayed/mknoon-website
- A separate **Worker** named `mknoon-website` has no active routes and is not serving the live website.

The `website/` directory contains the eight published files, assembled from the previous live deployment. It adds the child-safety page, adds footer links, and changes the privacy policy's age wording from 17 to 18 with an updated effective date. Existing CSS, JavaScript, and QR image are preserved. The local Flutter repository's newer privacy-policy text was not substituted for the live page. `live-baseline-sha256.json` records the fetched files before these edits. `website-draft.zip` is the upload archive (its original draft filename was retained).

The site was deployed to **Production** through the existing Cloudflare Pages dashboard after owner approval. All eight files at the immutable deployment URL match the prepared files. Anonymous requests to the public child-safety page, privacy policy, and home page return HTTP 200. Cloudflare email protection rewrites the custom-domain HTML; the normal browser was checked and displays the correct email address and working `mailto` targets. `deployment-verification.json` records the origin hashes and initial raw custom-domain comparisons. No GitHub changes were pushed.

## Required video evidence

Use real recordings from the build that will be submitted. Do not use an animation, mock-up, or a video of code. Host the clips at accessible, stable links, such as unlisted YouTube videos. Check that reviewers can watch without requesting access.

**Clip 1 — calling and microphone:**

1. Use two controlled test accounts/devices connected as contacts.
2. Show an incoming call while the receiving app is in the background or the phone is locked, then answer it.
3. Demonstrate two-way audio during the active call.
4. Put the app in the background and show the ongoing call notification while audio continues.
5. End the call and show that the ongoing notification ends.

The same clip can support the microphone and phone-call selections if both uses are clearly demonstrated.

**Clip 2 — Move Account data sync:**

1. Start Move Account explicitly and connect the receiving test device.
2. Start the account-data transfer and show progress.
3. Background the transferring app and show its “Moving account” notification.
4. Return to the app, let the transfer finish, and show that the ongoing notification ends.

Only declare use cases present in the submitted build. Add separate evidence if other active bundles rely on additional data-sync behavior.

Google's foreground-service evidence requirements:
https://support.google.com/googleplay/android-developer/answer/13392821?hl=en

## Pending release review

Before this session's saved full-screen declaration, Publishing overview listed **13 pending changes** and three blocking declaration issues. The pending closed test `mknoon-track-1` proposes **build 92 (1.0.0)**, Egypt and Germany, and the same tester list. This is older than the active internal release 114. Check which release should go to closed testing before submitting the pending changes. No rollout or review submission was performed.

## Follow-up Console status check

The owner will build later. A fresh check of App content confirms exactly **2 declarations needing attention**: foreground service permissions and child safety standards, both marked overdue. The other **11 declarations** are actioned and **ready to send for review**, including full-screen intent, Data safety, target audience, content ratings, ads, sign-in details, and privacy policy. They have not yet been reviewed. Policy status says compliance information will be available after review. Publishing overview still shows **14 pending changes** and the older closed-test build 92.

The app dashboard shows a further requirement for a public launch: publish a closed-test release, have **at least 12 testers opted in continuously for at least 14 days**, then apply for production access and answer the testing/readiness questions. It currently shows **0 closed-test opt-ins**. The 30 addresses in the tester list are eligible invitations, not 30 actual closed-test opt-ins. The shared internal-testing link is for a different track and does not satisfy the required closed test.

Official testing requirements: https://support.google.com/googleplay/android-developer/answer/14151465

The owner confirmed reusing the existing tester list; the pending closed track already selects **mknoon-List-1**. Testers who joined **this app's internal test** must first opt out of that test, then opt into the closed test once its release is available. Reusing the email list does not migrate their enrollment automatically. Official track eligibility guidance: https://support.google.com/googleplay/android-developer/answer/9845334?hl=en


## Foreground-service videos completed — 9 September 2026

- Review page: https://mknoon.space/review-videos/
- PHONE_CALL and MICROPHONE video: https://mknoon.space/review-videos/mknoon-background-calls.mp4
- DATA_SYNC video: https://mknoon.space/review-videos/mknoon-account-transfer.mp4
- Both links saved in Play Console. The console confirmed “Change saved. Send for review in Publishing overview.” No review was submitted.
- New website production deployment: https://98772442.mknoon-website.pages.dev. Existing approved site and policies preserved; only review page and two MP4s added. Eleven files deployed. Both public videos returned HTTP 200 with matching local hashes. Existing child-safety and privacy pages checked.
- Filmed the installed build 111 (1.0.1) on the physical Pixel 6 and Android Pixel 7 emulator. No new app build. Call clip 47.67 seconds; transfer clip 47.4 seconds. Silent screen captures with captions, privacy masks, and documented edits.
- The real account transfer succeeded; @pixel and its original peer identity are now on the emulator. The physical phone displayed Transfer complete. The emulator’s old mknoon data was cleared with user authorization to use current test accounts. Private pre-clear archive is outside the public site; keystore restoration is not guaranteed.
- Temporary USB tunnel and 128 KiB/s rate enabled the physical-to-emulator local transfer demonstration. Both were documented; tunnel, discovery advertisement, and Appium sessions cleaned up afterward.
- See videos/README.md, capture-metadata.json, raw captures and service snapshots for exact evidence and limits. Incoming-call visibility when already backgrounded was not proven by the successful ongoing-call clip; an earlier preflight did not show a visible incoming call. New support UI still needs the user’s future build. Child-safety certification and replacing closed-track build 92 remain outstanding.


## After user published build 115 — verified in Console

Build 115 (1.0.1) is available to internal testers, released 9 September at 16:42, not reviewed. This supersedes the earlier note that the next app build was still pending. The connected Pixel 6 remains on installed build 111; the emulator is no longer connected.

Publishing overview still has 14 changes not submitted and exactly one blocker: Incomplete child safety standards declaration. The child-safety form is blank, including the URL, contact selection and two certification boxes. The published approved policy and email remain https://mknoon.space/child-safety and saleh.m.elsayed@proton.me. Foreground-service declaration remains saved.

Closed testing mknoon-track-1 (track ID 4697806336001008061) still references release 92 (1.0.0), not yet sent for review. Tester list mknoon-List-1 and countries Egypt/Germany remain in the pending changes. Replace the pending closed release with 115 before review submission. No Console settings, declarations or release contents were changed during this status check.

Next: verify the reporting UI in 115, complete child-safety certification, prepare closed build 115 with the existing list, and submit for review. After closed testing is available, at least 12 testers must remain opted in continuously for 14 days before applying for production access. Internal testers must first opt out of this app’s internal test and join its closed test.


## Closed testing build 115 replacement (2026-09-09T15:02:42.489632+00:00)

- At task entry, `mknoon-track-1` had no releases; the old 92 release had already been removed.
- Added existing bundle **115 (1.0.1)** from the library and copied its internal release notes (`fixed few bugs`, en-GB).
- Preview and confirm showed **Ready to release**, with no errors or warnings. Saved release 3; the track now shows **Latest release: 115 (1.0.1)** and **Not yet sent for review**.
- Verified `mknoon-List-1` remains selected with **30** users and countries remain **Egypt and Germany**.
- Closed-test opt-in link exposed by Console: https://play.google.com/apps/testing/com.mknoon.app . It should be shared for closed testing once the release is available.
- Completed and saved the child-safety declaration using the approved standards at https://mknoon.space/child-safety and the approved contact saleh.m.elsayed@proton.me. User confirmed Safety & support works in 115. The incomplete-declaration blocker disappeared.
- Publishing overview has **14 changes not yet submitted**, **Submit 14 changes for review** enabled, and automatic checks running. **No Google review submission was performed.**
- Durable verification: `closed-release-115-verification.json`. This supersedes earlier notes that identified build 92 or the blank child-safety declaration as pending replacement/completion.
