/// Which surface the shipped Orbit screen shows (193).
///
/// [innerCircle] is the default on EVERY entry into Orbit (cold start, nav tap,
/// edge swipe, tab re-entry) — the orbital visualization only, no list. [allChats]
/// is the classic list surface (friends, groups, filters, search, intros),
/// reachable via the top-left view toggle and forced when the screen is opened
/// with a non-null `initialFilterTab` (e.g. the intro-notification route, so
/// pending intros stay reachable from notifications). The mode is deliberately
/// NOT persisted — in-session or across launches.
enum OrbitViewMode { innerCircle, allChats }
