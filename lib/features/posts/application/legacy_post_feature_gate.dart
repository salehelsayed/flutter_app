import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Plan 407 first version: retain legacy code until Thoughts ships, but make
/// its entry points inert, including listeners invoked without the router.
bool rejectLegacyPostFeature(String type) {
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_FEATURE_DISABLED_DROP',
    details: <String, dynamic>{'type': type},
  );
  return true;
}
