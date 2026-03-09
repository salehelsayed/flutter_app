import 'package:flutter/material.dart';

import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';

typedef ShareIntentRouteBuilder = Route<void> Function(ShareIntent intent);

/// Handles a share that arrives while the app is already running.
Future<void> handleShareIntent({
  required ShareIntent intent,
  required ShareIntentService shareIntentService,
  required NavigatorState? navigator,
  required ShareIntentRouteBuilder buildRoute,
}) async {
  if (!shareIntentService.isSettled || navigator == null) {
    await shareIntentService.bufferIntent(intent);
    return;
  }

  navigator.push(buildRoute(intent));
  shareIntentService.reset();
}
