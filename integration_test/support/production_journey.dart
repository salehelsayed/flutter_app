import 'android_app_state_guard.dart';
import 'production_journey_peer.dart';

/// What catalog journeys use from a host-owned production journey, whatever
/// the platform: the role peers, installation and readiness, UI flows,
/// relaunch, verified process death, cleanup and provenance.
/// [ProductionAndroidJourney] and [ProductionIosSimulatorJourney] implement it.
abstract interface class ProductionJourney {
  String get scenario;
  String get runId;
  AndroidHostProcessRunner get runner;
  abstract ProductionJourneyPeer alice;
  abstract ProductionJourneyPeer bob;
  Map<String, ProductionJourneyPeer> get additionalPeers;
  List<ProductionJourneyPeer> get actors;
  Future<void> prepare();
  Future<ProductionJourneyPeer> reopen(ProductionJourneyPeer previous);
  Future<String> flow(
    ProductionJourneyPeer p,
    String name,
    String label, [
    Map<String, String> values,
  ]);
  Future<void> killOwnedProcess(ProductionJourneyPeer p);
  Future<void> restore();
  Map<String, Object?> provenance();
}
