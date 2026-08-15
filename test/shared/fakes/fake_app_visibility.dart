import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';

/// Test-only bridge for preservation suites written against the pre-N04
/// tracker/lifecycle inputs. Production notification owners never use it.
final class TrackerBackedAppVisibility extends AppVisibilitySuppressionReader {
  TrackerBackedAppVisibility({required this.tracker, required this.lifecycle});

  final ActiveConversationTracker tracker;
  final AppLifecycleState Function() lifecycle;
  int evaluations = 0;

  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async {
    evaluations += 1;
    final isForegroundActive = lifecycle() == AppLifecycleState.resumed;
    return AppVisibilityEvaluation(
      isForegroundActive: isForegroundActive,
      maySuppress:
          isForegroundActive &&
          identity != null &&
          tracker.isViewing(identity.normalizedValue),
    );
  }
}

final class FixedAppVisibility extends AppVisibilitySuppressionReader {
  FixedAppVisibility({
    bool isForegroundActive = false,
    bool maySuppress = false,
  }) : foregroundActiveValue = isForegroundActive,
       suppressionValue = maySuppress;

  final bool foregroundActiveValue;
  final bool suppressionValue;
  int evaluations = 0;

  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async {
    evaluations += 1;
    return AppVisibilityEvaluation(
      isForegroundActive: foregroundActiveValue,
      maySuppress: suppressionValue && identity != null,
    );
  }
}

final class TrackerBackedTopRouteReader implements AppVisibilityTopRouteReader {
  TrackerBackedTopRouteReader(this.tracker);

  final ActiveConversationTracker? tracker;

  @override
  AppVisibilityConversationIdentity? get currentTopConversation {
    final value = tracker?.activePeerId;
    if (value == null || value.isEmpty) return null;
    return AppVisibilityConversationIdentity.tryParse(
      lane: value.startsWith('group:')
          ? AppVisibilityConversationLane.group
          : AppVisibilityConversationLane.direct,
      value: value,
    );
  }

  @override
  bool isCurrentTopConversation(AppVisibilityConversationIdentity identity) =>
      tracker?.isViewing(identity.normalizedValue) ?? false;

  @override
  bool isCurrentTopConversationValue({
    required AppVisibilityConversationLane lane,
    required String value,
  }) {
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: lane,
      value: value,
    );
    return identity != null && isCurrentTopConversation(identity);
  }
}
