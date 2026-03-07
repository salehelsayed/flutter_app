Repo-wide, the current UI uses about 20 BackdropFilters, 7 SingleChildScrollViews, 30
  AnimationControllers, and 26 AnimatedBuilders. That is a high visual-cost budget for a
  mobile chat app.

  Top Findings

  1. High Whole-screen feed reloads are the biggest structural problem.
     Evidence: feed_wired.dart:225, feed_wired.dart:372, feed_wired.dart:391,
     feed_wired.dart:766, load_feed_use_case.dart:19.
     Impact: every incoming chat, contact update, group message, intro change, and many
     route returns trigger a full feed reload. loadFeed() loops all contacts, loads
     messages per contact, resolves attachment paths one by one, then sorts everything
     again. As the user’s network grows, the feed will feel increasingly sluggish and
     “jumpy”.
     Recommendation: move to incremental updates for unread counts, new messages,
     reactions, and thread ordering; keep full DB reloads for cold start/manual refresh
     only.
  2. High Feed and Orbit are not virtualized.
     Evidence: feed_screen.dart:136, feed_screen.dart:190, orbit_screen.dart:111,
     orbit_screen.dart:188.
     Impact: all feed cards, orbit rows, avatars, reply inputs, and visual effects are laid
     out and painted eagerly. This is fine for a tiny dataset; it does not scale. Scroll
     smoothness, memory use, and tab responsiveness will all degrade with contact/thread
     count.
     Recommendation: convert Feed and Orbit to CustomScrollView/SliverList or
     ListView.builder so off-screen content is not built.
  3. High The glassmorphism style is too expensive inside lists.
     Evidence: feed_card.dart:113, connection_card.dart:89, message_bubble.dart:63,
     letter_card.dart:61, conversation_header.dart:26, compose_area.dart:132,
     feed_navigation_bar.dart:23, ambient_background.dart:23.
     Impact: BackdropFilter is one of the most expensive visual effects in Flutter,
     especially when repeated in scrolling content over an animated background. The app is
     stacking blur over blur over animation. That raises GPU cost and makes dropped frames
     more likely on mid-range devices.
     Recommendation: keep blur for one or two hero surfaces per screen, but replace
     repeated list-item blur with flat translucent fills, gradients, and subtle borders.
  4. High UserAvatar does synchronous filesystem work during build.
     Evidence: user_avatar.dart:47.
     Impact: file.existsSync() runs in build for every contact avatar. Because avatars are
     used in feed cards, orbit rows, headers, and message cards, scroll/build work can
     block on disk checks. This is one of the clearest avoidable jank sources in the repo.
     Recommendation: resolve avatar state before build and pass an ImageProvider/path/bytes
     from state; cache existence in memory.
  5. Medium-High Orbit has the same full-reload pattern as Feed.
     Evidence: orbit_wired.dart:257, orbit_wired.dart:426, orbit_wired.dart:452,
     orbit_wired.dart:465, load_orbit_data_use_case.dart:9.
     Impact: Orbit reloads active/archived friends and groups repeatedly; the use case does
     three message queries per contact. Search also rebuilds the whole screen and re-sorts
     merged content. This will feel heavy once there are many contacts/groups.
     Recommendation: cache orbit models, update rows incrementally, and isolate search
     results from the orbital header so typing does not rebuild the whole screen.
  6. Medium-High Recording and video-processing state rebuild whole conversation screens
     many times per second.
     Evidence: conversation_wired.dart:869, conversation_wired.dart:938,
     group_conversation_wired.dart:452, group_conversation_wired.dart:526.
     Impact: duration ticks, amplitude updates, and video progress all call setState on the
     page state, which means header, message list, and compose area all rebuild. During
     voice/video workflows, that is unnecessary work and risks input latency.
     Recommendation: isolate recording/progress into a small widget driven by
     ValueNotifier, StreamBuilder, or a dedicated controller.
  7. Medium Group conversation reloads full messages and media on each new group message.
     Evidence: group_conversation_wired.dart:156, group_conversation_wired.dart:203,
     group_conversation_wired.dart:234.
     Impact: every incoming group message triggers a full reload of messages, attachments,
     path resolution, and pending download checks. This can cause list churn, attachment
     flicker, and inconsistent scroll feel.
     Recommendation: append/update a single message in memory; background-fetch only
     missing media.
  8. Medium Perceived performance is weaker than it needs to be.
     Evidence: feed_screen.dart:190, feed_wired.dart:432, feed_wired.dart:396.
     Impact: the feed is blank while loading, and some navigation waits for data before
     pushing the next screen. Even if backend latency is acceptable, the app can feel
     slower than it is.
     Recommendation: navigate immediately, then hydrate content in place; use skeleton
     cards/placeholders instead of blank space; keep optimistic state visible longer.
  9. Medium Animation density is high for a messaging app.
     Evidence: ambient_background.dart:23, feed_card.dart:56, connection_card.dart:29,
     friend_row.dart:156, empty_circle_state.dart:14.
     Impact: many elements animate at once, including persistent background animation. The
     result can feel stylish but busy, and it consumes frame budget continuously instead of
     only when it adds meaning.
     Recommendation: define a motion budget; keep hero transitions, but reduce per-item
     entrance animation and disable decorative motion during scrolling.
  10. Low-Medium There are smaller layout inefficiencies that will compound at scale.
     Evidence: intros_tab.dart:49, friend_picker_screen.dart:140,
     editable_username_widget.dart:99, scrollable_message_preview.dart:130.
     Impact: nested shrink-wrapped lists, IntrinsicWidth, and shader-masked preview lists
     increase layout work. These are not the main problem, but they add cost on top of the
     bigger issues above.
     Recommendation: clean these up after the main architecture fixes.

  What’s Already Good

  - Conversation and group threads at least use ListView.builder:
    conversation_screen.dart:214, group_conversation_screen.dart:206.
  - Onboarding/QR screens already use RepaintBoundary in a few smart places:
    first_time_experience_screen.dart:174, qr_display_screen.dart:131.
  - Startup defers P2P startup until after navigation, which helps first paint:
    startup_router.dart:343.
  - IdentityLoadingCard explicitly avoids blur, which is the right instinct:
    identity_loading_card.dart:10.

  Recommended Order

  1. Re-architect Feed and Orbit around virtualized lists plus incremental state updates.
  2. Remove UserAvatar sync file checks from build.
  3. Replace blur in repeated cards/messages with cheaper translucent surfaces.
  4. Isolate recording/video progress state from whole-page rebuilds.
  5. Add skeleton/loading placeholders and navigate before data hydration.
  6. Reduce decorative animation density and add a reduced-motion path.