import 'package:flutter/material.dart';

/// Builds the route used when entering a 1:1 conversation.
///
/// Uses [MaterialPageRoute] so that on iOS the conversation gets the platform
/// edge-swipe-back gesture for free — identical to the group conversation
/// screen (`GroupConversationWired`, also pushed via `MaterialPageRoute`).
///
/// Previously this was a `PageRouteBuilder` slide-up + fade, which silently
/// dropped the iOS edge-swipe-back gesture (the gesture lives inside the same
/// `buildTransitions` that owned the bespoke transition). See
/// Test-Flight-Improv/1to1-swipe-back-navigation-tdd-plan.md (Option A): the
/// accepted trade-off is the enter animation changing from slide-up to the
/// platform slide-from-right, in exchange for swipe-back parity with groups.
Route<T> buildConversationRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return MaterialPageRoute<T>(
    settings: settings,
    builder: builder,
  );
}
