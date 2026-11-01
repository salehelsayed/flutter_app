import 'dart:async';

import '../../../core/utils/flow_event_emitter.dart';
import '../diagnostics/call_diagnostics.dart';
import '../application/call_endpoint_resolver.dart';
import '../domain/received_call_wake_handle_store.dart';
import 'call_authority_client.dart';
import 'call_trusted_roster_provider.dart';

/// Production call endpoint resolution shared by the foreground signaling
/// graph and the headless decline reply (plan 404): trusted roster, the
/// caller's wake-handle grant, and the relay endpoint record feed one
/// [CallEndpointResolver.resolve], with identifier-free diagnostics.
typedef EnsureReceivedCallWakeHandle =
    Future<bool> Function(String contactAccountPeerId);
typedef RepairCallEndpoint =
    Future<bool> Function(
      String contactAccountPeerId, {
      Future<void> Function()? beforeRequest,
    });

Future<ResolvedCallEndpoint> resolveProductionCallEndpoint({
  required String contactAccountPeerId,
  required CallEndpointResolver resolver,
  required CallTrustedRosterProvider rosterProvider,
  required CallAuthorityClient authorityClient,
  required ReceivedCallWakeHandleStore receivedCallWakeHandleStore,
  EnsureReceivedCallWakeHandle? ensureReceivedCallWakeHandle,
  RepairCallEndpoint? repairMissingEndpoint,
  Future<void> Function()? beforeOperation,
}) async {
  await beforeOperation?.call();
  var roster = await loadCallEndpointDependency(
    stage: 'trusted_roster_load',
    load: () => rosterProvider.loadForContact(contactAccountPeerId),
  );
  await beforeOperation?.call();
  try {
    await ensureReceivedCallWakeHandle?.call(contactAccountPeerId);
  } catch (_) {
    // Recovery is best effort. The durable store read below remains authority.
  }
  await beforeOperation?.call();
  var wakeHandleGrant = await loadCallEndpointDependency(
    stage: 'received_wake_handle_load',
    load: () => receivedCallWakeHandleStore.readForIssuer(contactAccountPeerId),
  );
  await beforeOperation?.call();
  var relayEndpoint = await loadCallEndpointDependency(
    stage: 'relay_endpoint_load',
    load: () => authorityClient.getEndpoint(contactAccountPeerId),
  );
  Future<void> reload() async {
    await beforeOperation?.call();
    roster = await rosterProvider.loadForContact(contactAccountPeerId);
    if (!roster.contactAccepted || roster.contactBlocked) {
      throw CallEndpointResolutionException(
        roster.contactBlocked
            ? CallEndpointResolutionCode.blocked
            : CallEndpointResolutionCode.notAccepted,
      );
    }
    await beforeOperation?.call();
    wakeHandleGrant = await receivedCallWakeHandleStore.readForIssuer(
      contactAccountPeerId,
    );
    await beforeOperation?.call();
    relayEndpoint = await authorityClient.getEndpoint(contactAccountPeerId);
    await beforeOperation?.call();
  }

  Future<bool> canRepair() => resolver.canRepairEndpoint(
    contactAccountPeerId: contactAccountPeerId,
    contactAccepted: roster.contactAccepted,
    contactBlocked: roster.contactBlocked,
    trustedDevices: roster.devices,
    relayEndpoint: relayEndpoint,
    wakeHandleGrant: wakeHandleGrant,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'CALL_ENDPOINT_RESOLUTION_INPUT',
    details: <String, Object?>{
      'contactAccepted': roster.contactAccepted,
      'contactBlocked': roster.contactBlocked,
      'trustedDeviceCount': roster.devices.length,
      'relayEndpointPresent': relayEndpoint != null,
      'wakeHandleGrantPresent': wakeHandleGrant != null,
    },
  );
  try {
    var repairRequested = false;
    while (true) {
      await beforeOperation?.call();
      try {
        final endpoint = await resolver.resolve(
          contactAccountPeerId: contactAccountPeerId,
          contactAccepted: roster.contactAccepted,
          contactBlocked: roster.contactBlocked,
          trustedDevices: roster.devices,
          relayCapabilities: relayEndpoint == null
              ? const <SignedCallEndpointRecord>[]
              : <SignedCallEndpointRecord>[relayEndpoint!],
          wakeHandleGrant: wakeHandleGrant,
        );
        await beforeOperation?.call();
        emitCallEndpointResolutionResult(
          stage: 'ready',
          outcome: 'available',
          reason: 'none',
        );
        return endpoint;
      } on CallEndpointResolutionException {
        if (repairMissingEndpoint == null || !await canRepair()) rethrow;
        if (!repairRequested) {
          // Re-read authority after the failed lookup before requesting any
          // peer work. A concurrently published endpoint needs no repair.
          await reload();
          if (!await canRepair()) continue;
          await beforeOperation?.call();
          repairRequested = true;
          if (!await repairMissingEndpoint(
            contactAccountPeerId,
            beforeRequest: () async {
              await beforeOperation?.call();
              roster = await rosterProvider.loadForContact(
                contactAccountPeerId,
              );
              await beforeOperation?.call();
              wakeHandleGrant = await receivedCallWakeHandleStore.readForIssuer(
                contactAccountPeerId,
              );
              await beforeOperation?.call();
              if (!await canRepair()) {
                throw const CallEndpointResolutionException(
                  CallEndpointResolutionCode.unavailable,
                );
              }
              await beforeOperation?.call();
            },
          )) {
            rethrow;
          }
        } else {
          // The one authenticated request can complete before advertisement.
          // Only rechecks follow, under the caller's original contact budget.
          await beforeOperation?.call();
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        await reload();
      }
    }
  } on CallEndpointResolutionException catch (error) {
    final reason = switch (error.code) {
      CallEndpointResolutionCode.blocked => 'blocked',
      CallEndpointResolutionCode.notAccepted => 'authority_rejected',
      CallEndpointResolutionCode.invalidSignature => 'signature_invalid',
      CallEndpointResolutionCode.stale => 'expired',
      CallEndpointResolutionCode.unavailable when relayEndpoint == null =>
        'endpoint_not_found',
      CallEndpointResolutionCode.unavailable when wakeHandleGrant == null =>
        'wake_authority_missing',
      CallEndpointResolutionCode.unavailable => 'capability_unavailable',
      _ => 'endpoint_invalid',
    };
    final diagnostics = CallDiagnostics.instance;
    diagnostics.record(
      stage: 'preflight',
      action: 'lookup',
      outcome: 'rejected',
      reason: reason,
    );
    if (diagnostics.currentTraceId != null) {
      diagnostics.finishAttempt(outcome: 'preflight_failed', reason: reason);
    }
    emitCallEndpointResolutionResult(
      stage: 'endpoint_resolve',
      outcome: 'unavailable',
      reason: error.code.name,
    );
    rethrow;
  } catch (_) {
    emitCallEndpointResolutionResult(
      stage: 'endpoint_resolve',
      outcome: 'error',
      reason: 'dependency_error',
    );
    rethrow;
  }
}

Future<T> loadCallEndpointDependency<T>({
  required String stage,
  required Future<T> Function() load,
}) async {
  try {
    return await load();
  } catch (_) {
    emitCallEndpointResolutionResult(
      stage: stage,
      outcome: 'error',
      reason: 'dependency_error',
    );
    rethrow;
  }
}

void emitCallEndpointResolutionResult({
  required String stage,
  required String outcome,
  required String reason,
}) {
  try {
    CallDiagnostics.instance.record(
      stage: 'preflight',
      action: 'lookup',
      outcome: outcome == 'available'
          ? 'ok'
          : outcome == 'error'
          ? 'failed'
          : 'rejected',
      reason: outcome == 'available'
          ? 'none'
          : outcome == 'error'
          ? 'authority_unreachable'
          : 'authority_invalid',
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_ENDPOINT_RESOLUTION_RESULT',
      details: <String, Object?>{
        'stage': stage,
        'outcome': outcome,
        'reason': reason,
      },
    );
  } catch (_) {
    // Diagnostic observers must never change call availability.
  }
}
