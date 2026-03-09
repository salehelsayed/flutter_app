import 'package:flutter/material.dart';

import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';

typedef PendingShareRouteBuilder = Route<void> Function(ShareIntent intent);

/// Marks the share flow as settled and replays any buffered intent once the
/// next frame lands on the target screen.
void settleShareIntentFlow({
  required ShareIntentService? shareIntentService,
  required NavigatorState navigator,
  required PendingShareRouteBuilder buildRoute,
}) {
  final shareService = shareIntentService;
  if (shareService == null) return;

  shareService.isSettled = true;

  final pendingIntent = shareService.consumePendingIntent();
  if (pendingIntent == null) return;

  shareService.reset();

  WidgetsBinding.instance.addPostFrameCallback((_) {
    navigator.push(buildRoute(pendingIntent));
  });
}
