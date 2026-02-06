import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Represents the startup routing decision based on identity and contacts.
enum StartupDecision {
  /// Identity exists and at least one contact is stored.
  hasIdentityWithContacts,

  /// Identity exists but no contacts are stored yet.
  hasIdentityNoContacts,

  /// No identity exists; show identity onboarding flow.
  needsIdentity,
}

/// Determines startup route from identity and contact count.
///
/// Flow events emitted:
/// - `ID_STARTUP_DECIDE_ROUTE_CALL`
/// - `ID_STARTUP_NEEDS_ID`
/// - `ID_STARTUP_HAS_ID_NO_CONTACTS`
/// - `ID_STARTUP_HAS_ID_WITH_CONTACTS`
Future<StartupDecision> decideStartupRoute({
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_STARTUP_DECIDE_ROUTE_CALL',
    details: {},
  );

  final identity = await identityRepo.loadIdentity();

  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_NEEDS_ID',
      details: {'hasIdentity': false},
    );
    return StartupDecision.needsIdentity;
  }

  final contactCount = await contactRepo.getContactCount();
  if (contactCount > 0) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_HAS_ID_WITH_CONTACTS',
      details: {'hasIdentity': true, 'contactCount': contactCount},
    );
    return StartupDecision.hasIdentityWithContacts;
  } else {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_HAS_ID_NO_CONTACTS',
      details: {'hasIdentity': true, 'contactCount': 0},
    );
    return StartupDecision.hasIdentityNoContacts;
  }
}
