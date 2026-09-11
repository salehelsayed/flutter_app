# Google Play foreground-service evidence — 9 September 2026

Public review page: https://mknoon.space/review-videos/

- PHONE_CALL + MICROPHONE: https://mknoon.space/review-videos/mknoon-background-calls.mp4
- DATA_SYNC: https://mknoon.space/review-videos/mknoon-account-transfer.mp4

Both URLs were saved in Play Console’s Foreground service permissions declaration. Console confirmed “Change saved. Send for review in Publishing overview.” Review was not submitted.

Both devices ran the phone’s existing build 111 (1.0.1), Android 17. No new app build was produced. The emulator’s earlier build 110 was updated using the already-installed phone APK. Existing test accounts were explicitly authorized by the user.

The call capture shows a real answered call, Connected timers on both devices, mute/unmute, the physical phone going Home, Android’s Call in progress notification and microphone indicator, return to the continuing call, and ending the call. It has no recorded audio track. An earlier preflight incoming call while the receiving phone was already backgrounded did not visibly surface; that incoming-call case is not proven by this video.

The account transfer completed successfully from the Pixel 6 to the Pixel 7 emulator. The original @pixel peer identity was verified on the emulator. The physical phone displayed Transfer complete. The emulator’s previous mknoon app data was cleared to make it a new-phone receiver. A private pre-clear data archive remains outside the public site, under /tmp/mknoon-play-videos; Android keystore restoration from that archive is not guaranteed.

The emulator required a temporary ADB network tunnel because its 10.0.2.16 address was unreachable from the physical phone. Bringing the emulator window forward resolved observed long VM response pauses. The tunnel was limited to 128 KiB/s so transfer progress could be followed. The real protocol, account data, foreground service, notifications and UI were used. Temporary tunnel, mDNS advertisement and Appium sessions were removed afterward.

Editing: real screen capture only, captions, privacy masks, removed setup/idle gaps, and captured still frames for the final transfer confirmation. The call clip is about 48 seconds; transfer clip about 47 seconds. Service snapshots prove the native foreground services were active during use. Migration foreground services were absent after completion.

Public files were downloaded without authentication and matched their local SHA-256 hashes. See public-verification.json and capture-metadata.json. Raw videos and diagnostic evidence in this directory are local review artifacts and were not published.

The new support UI still requires the user’s future build. Do not submit the stale closed-track build 92. Child-safety certification and the correct closed-test release remain separate outstanding Play tasks.
