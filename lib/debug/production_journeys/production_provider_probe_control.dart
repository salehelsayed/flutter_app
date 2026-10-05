import 'production_journey_controller.dart';

/// Exposes the token issued to the production-configured receiver to one
/// run-bound provider probe. The host consumes it in memory and never records
/// it in a journey receipt.
void bindProductionProviderProbeControl({
  required ProductionJourneyController controller,
  required Future<String?> Function() getToken,
}) {
  if (controller.profileId != 'android.production_fcm.journey' ||
      controller.invocation.role != 'bob' ||
      !{
        notificationOpenJourney,
        notificationTapLatencyJourney,
        notificationSoundJourney,
      }.contains(controller.invocation.scenarioId)) {
    return;
  }
  var used = false;
  controller.bindAction('provider_token', (arguments) async {
    if (used || arguments.isNotEmpty) {
      throw StateError('provider token probe must be claimed once');
    }
    used = true;
    final token = await getToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('production receiver has no Firebase token');
    }
    return {'token': token};
  });
}
