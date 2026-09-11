# Live UI automation handoff

Prepared without placing calls, sending messages, changing settings, uninstalling apps, or resetting app data.

## iPhone 11

- Explicit target: `00008030-001A6D2801BB802E`, iOS 26.5.
- Existing WebDriverAgent was stale. Restarted only its old iPhone-11 xcodebuild process; the other iPhone's WDA process was preserved.
- WDA is healthy through existing USB forwarding at `http://127.0.0.1:18100`.
- MCP embedded XCUITest session: `b51bc841-baa2-4564-92f9-c9ae539c2f94`.
- Session capabilities preserve data and app lifecycle: `noReset=true`, `fullReset=false`, `autoLaunch=false`, `shouldTerminateApp=false`, `forceAppLaunch=false`, attaching the existing WDA URL.
- WDA orchestration exec session: `80708`. Log: `/tmp/beta-call-review-20260908/iphone11-wda-restart.log`.
- Verified activation of `com.mknoon.app`, source snapshots, navigation back to the existing QA landing page, accessibility lookup and tap of `Open settings`.
- Use explicit `sessionId` with every MCP tool action. Element IDs are transient: locate again after navigation/rebuild.

## Pixel

- Explicit target: `21071FDF600CSC`.
- ADB activation and fresh UI hierarchy capture work; app data is preserved.
- Existing QA landing page exposes exact descriptions `Open chat with iphone-11`, `Open settings`, and `Show all chats`.
- Local helper `/tmp/beta-call-review-20260908/pixel_ui_control.py` pins the target, refuses stale hierarchy coordinates, and requires exactly one enabled current node for a tap. It keeps raw UI XML local and emits only bounded operation/status metadata.
- Example: `python3 /tmp/beta-call-review-20260908/pixel_ui_control.py tap --selector 'Open settings'`. `status` reads the current QA controls; `launch` foregrounds the installed app.
- The helper refuses call-related selectors unless explicitly invoked with `--allow-call-action` after the coordinating task authorizes the live call leg.

## Current app state and proof limits

Both installed development apps initially showed the disabled header label **Voice calling is unavailable right now**: Android resource ID `mknoon.conversation.iphone-11`, iOS accessibility ID `mknoon.conversation.pixel`. Both settings views exposed ordinary settings but no visible voice-call setting. The coordinating build task should resolve feature/configuration readiness before starting the call leg.

The conversation header identifier covers the entire app bar. Individual back/call icon children are unlabeled in these installed builds. Navigation back was verified from the current hierarchy's left icon bounds; do not blindly tap the center of the merged header as a call action. Refresh the hierarchy after the new builds and use the current call icon bounds or a newly supplied dedicated identifier.

Incoming answer/end-call controls cannot be verified before a call exists. The driver is ready to inspect and operate them once the coordinator starts the authorized call leg; this handoff does not claim those UI assertions have passed.
