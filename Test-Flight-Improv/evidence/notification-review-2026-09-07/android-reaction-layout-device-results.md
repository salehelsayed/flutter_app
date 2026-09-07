# Android114 final expanded reaction live verification

**PASS: group and direct current reaction lines survive background processing and settled silent updates alongside existing unread ordinary history.** Both OS payloads and actual expanded screenshots were inspected. Receivers remained background throughout their respective proof legs.

## Installed targets and preservation

Pixel21071FDF600CSC and emulator-5554 both received install-r, retained accounts picel / TC256-B and their existing unread histories, and verified versionCode114 / versionName1.0.0-807874437-notification260907-r4. APK SHA256f80e83093fb5e711a48fd919834b903162a366def4fbe0f786c7f5f9aceebcec. Source provenance: `android-reaction-layout-final-provenance.json` alongside this report. Raw logs, OS dumps, actions and screenshots are in `build/notification-review-20260907/android-layout-114/`. Startup and wake registration events are preserved in *-proof.log. No iPhone action, relay mutation, account reset, or app source edit was performed in this leg. All times below UTC; raw device logs display UTC+02.

## Group: initial and settled PASS

Emulator replaced previous😮 with😂 on an existing Pixel video, target26af6e62 / groupf4d26c1d. UI tap10:47:43.714, sender FLOW10:47:44.341, Pixel FCM10:47:46.308. Initial background notification shown10:47:52.634 with silent=false; initial OS evidence10:47:52.910. Pixel OS703171339 InboxStyle contains2lines: preserved `TC256-B: NNotification-review-build112-group-unread` and current `TC256-B reacted to your video`.

Background SQL drain stored current😂10:47:59.228 (also draining earlier😮). Settled payload and actual expanded screenshot10:48:33.822, over41s after initial post, still contain both lines. The same OS notification has ONLY_ALERT_ONCE|SILENT flags after settlement. Pixel remained background; no group was opened. This reproduces the prior112 failing scenario and now preserves the reaction through the later update.

Evidence: group-reaction-initial.txt, group-reaction-settled.txt, group-expanded-final.xml, group-expanded-final.png. Generic group reaction wording does not include emoji by current product format; exact sender/ingress logs establish this is the fresh😂 event.

## Direct: initial and settled PASS

Pixel replaced previous😮 with🙏 on TC256-B message b4feae46. Tap10:49:20.875, sender FLOW start10:49:21.682 / success10:49:24.884 (reaction1ef7d866). Emulator FCM10:49:21.287, durable OS_POSTED10:49:26.064. Initial payload10:49:30.207 contains2lines: existing `Notification-review-final-build111-text` and current `Reacted 🙏 to your message`.

Settled payload and actual expanded screenshot10:50:18.156, over52s after durable post, retain both lines. Emulator remained background and its direct conversation was not opened. OS1968162080 retained correct identity. This repeated-reaction rendering case posts silent=true and does not independently establish an audible alert; earlier audible delivery proof remains in the prior audit/deployment evidence.

Evidence: direct-reaction-initial.txt, direct-reaction-settled.txt, direct-expanded-final.xml, direct-expanded-final.png.

## Closure and retained limits

Historical112 group failure and113 held install/not-exercised evidence are preserved in sibling directories. This bounded rendering retest does not broaden prior matrix claims, erase the earlier117.7s iPhone ingress delay, or change live direct-mute/generic-file/accepted-iPhone-group limitations. No new build or device QA is required by these two rendering cases.

Owned capture PIDs75211/75212 stopped at 2026-09-07T10:51:17.971591+00:00 by SIGTERM; see capture-shutdown.json. Raw logcats, compact *-proof.log, actions.jsonl, version files, OS dumps and screenshots retained; evidence files mode0600. Emulator and all accounts remain available.
