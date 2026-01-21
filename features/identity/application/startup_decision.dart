import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Represents the startup routing decision based on identity presence.
enum StartupDecision {
  /// An identity exists in the database; proceed to main app.
  hasIdentity,

  /// No identity exists; show identity onboarding flow.
  needsIdentity,
}

/// Determines the startup route based on whether an identity exists.
///
/// This function checks the database for an existing identity and returns
/// the appropriate [StartupDecision] to guide navigation.
///
/// Parameters:
///   - [repo]: The identity repository to query for existing identity.
///
/// Returns:
///   - [StartupDecision.hasIdentity] if an identity is found in the database.
///   - [StartupDecision.needsIdentity] if no identity exists.
///
/// Flow events emitted:
///   - `ID_STARTUP_DECIDE_ROUTE_CALL` before loading identity
///   - `ID_STARTUP_HAS_ID` if identity exists
///   - `ID_STARTUP_NEEDS_ID` if no identity exists
Future<StartupDecision> decideStartupRoute(IdentityRepository repo) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_STARTUP_DECIDE_ROUTE_CALL',
    details: {},
  );

  final identity = await repo.loadIdentity();

  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_NEEDS_ID',
      details: {'hasIdentity': false},
    );
    return StartupDecision.needsIdentity;
  } else {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_HAS_ID',
      details: {'hasIdentity': true},
    );
    return StartupDecision.hasIdentity;
  }
}
