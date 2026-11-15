import 'dart:async';

import '../../../core/utils/flow_event_emitter.dart';
import '../application/call_endpoint_resolver.dart';
import '../application/call_recovery_budget.dart';
import '../domain/call_wake_handle_grant.dart';
import '../domain/received_call_wake_handle_store.dart';
import 'call_authority_client.dart';
import 'call_trusted_roster_provider.dart';

/// One canonical episode's remote lookup quota and verified routing custody.
/// Every read still checks local authority. Nothing survives budget retirement.
final class CallEndpointRecovery {
  CallEndpointRecovery({
    required this.budget,
    required ResolvedCallEndpoint admitted,
    this.bindingCurrent,
  }) : admitted = ResolvedCallEndpoint.frozen(admitted);

  final CallRecoveryBudget budget;
  final ResolvedCallEndpoint admitted;
  final bool Function()? bindingCurrent;
  int _lookups = 0;
  ResolvedCallEndpoint? _verified;
  bool _transient = false;
  bool _denied = false;

  void _check() {
    if (bindingCurrent?.call() == false) _deny();
    if (budget.remaining <= Duration.zero) {
      _verified = null;
      _transient = false;
      throw const CallEndpointRecoveryUnavailable();
    }
    if (_denied) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.mismatched,
      );
    }
  }

  void _record(String stage, String reason, {int? durationMs}) {
    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_RECOVERY_ENDPOINT',
        details: {
          'stage': stage,
          'reason': reason,
          'lookupCount': _lookups,
          'remainingMs': budget.remaining.inMilliseconds,
          'durationMs': durationMs ?? 0,
        },
      );
    } catch (_) {
      // Observation cannot change routing authority or the reconnect deadline.
    }
  }

  Future<ResolvedCallEndpoint> resolve({
    required String accountPeerId,
    required CallEndpointResolver resolver,
    required CallTrustedRosterProvider rosterProvider,
    required ReceivedCallWakeHandleStore wakeStore,
    required CallAuthorityClient authorityClient,
    Future<void> Function()? beforeOperation,
  }) async {
    _check();
    if (accountPeerId != admitted.accountPeerId) {
      _deny();
    }
    late CallTrustedRosterSnapshot roster;
    CallWakeHandleGrant? grant;
    Future<void> local() async {
      _check();
      await beforeOperation?.call();
      _check();
      roster = await rosterProvider
          .loadForContact(accountPeerId)
          .timeout(budget.remaining);
      _check();
      grant = await wakeStore
          .readForIssuer(accountPeerId)
          .timeout(budget.remaining);
      _check();
      resolver.requireCurrentPinnedAuthority(
        endpoint: admitted,
        contactAccepted: roster.contactAccepted,
        contactBlocked: roster.contactBlocked,
        trustedDevices: roster.devices,
        wakeHandleGrant: grant,
      );
      final verified = _verified;
      if (verified != null) {
        resolver.requireCurrentPinnedAuthority(
          endpoint: verified,
          contactAccepted: roster.contactAccepted,
          contactBlocked: roster.contactBlocked,
          trustedDevices: roster.devices,
          wakeHandleGrant: grant,
        );
      }
      await beforeOperation?.call();
      _check();
    }

    try {
      await local();
      if (_lookups >= 3) {
        final reusable = _verified ?? (_transient ? admitted : null);
        if (reusable == null) throw const CallEndpointRecoveryUnavailable();
        _record(
          'reuse',
          _verified == null ? 'transient_pin' : 'episode_verified',
        );
        return reusable;
      }
      _lookups++;
      _record('lookup', 'started');
      final remaining = budget.remaining;
      final slice = remaining < const Duration(seconds: 2)
          ? remaining
          : const Duration(seconds: 2);
      final lookupClock = Stopwatch()..start();
      int durationMs() => lookupClock.elapsedMilliseconds.clamp(0, 15000);
      SignedCallEndpointRecord? remote;
      try {
        remote = await authorityClient
            .getEndpoint(accountPeerId)
            .timeout(slice)
            .whenComplete(lookupClock.stop);
      } on TimeoutException {
        _transient = true;
        await local();
        _record('pin', 'lookup_timeout', durationMs: durationMs());
        return _verified ?? admitted;
      } on CallAuthorityException catch (error) {
        if (error.code != CallAuthorityErrorCode.bridgeFailure ||
            !(error.isTransient ||
                error.relayErrorCode == 'CALL_CONTROL_UNAVAILABLE')) {
          _deny();
        }
        _transient = true;
        await local();
        _record('pin', 'transport_unavailable', durationMs: durationMs());
        return _verified ?? admitted;
      }
      await local();
      if (remote == null) {
        _verified = null;
        _transient = false;
        _record('lookup', 'endpoint_absent', durationMs: durationMs());
        throw const CallEndpointRecoveryUnavailable();
      }
      final endpoint = await resolver.resolve(
        contactAccountPeerId: accountPeerId,
        contactAccepted: roster.contactAccepted,
        contactBlocked: roster.contactBlocked,
        trustedDevices: roster.devices,
        relayCapabilities: [remote],
        wakeHandleGrant: grant,
      );
      await local();
      if (!_sameAuthority(admitted, endpoint)) _deny();
      _verified = ResolvedCallEndpoint.frozen(endpoint);
      _record('lookup', 'verified', durationMs: durationMs());
      return _verified!;
    } on CallEndpointRecoveryUnavailable {
      rethrow;
    } on TimeoutException {
      _record('local', 'deadline');
      throw const CallEndpointRecoveryUnavailable();
    } catch (_) {
      _deny();
    }
  }

  Never _deny() {
    _verified = null;
    _transient = false;
    _denied = true;
    _record('authorization', 'rejected');
    // Local unavailability must not be mistaken for a missing remote directory
    // record by legacy adapters, which otherwise try their own pinned endpoint.
    throw const CallEndpointResolutionException(
      CallEndpointResolutionCode.mismatched,
    );
  }

  static bool _sameAuthority(ResolvedCallEndpoint a, ResolvedCallEndpoint b) =>
      a.accountPeerId == b.accountPeerId &&
      a.devicePeerId == b.devicePeerId &&
      a.signingPublicKey == b.signingPublicKey &&
      a.mlKemPublicKey == b.mlKemPublicKey &&
      a.admissionAuthority == b.admissionAuthority &&
      a.deviceKeyEpoch == b.deviceKeyEpoch &&
      a.preferenceEpoch == b.preferenceEpoch &&
      a.platform == b.platform &&
      a.routingHandle == b.routingHandle &&
      a.wakeHandle == b.wakeHandle &&
      a.capabilities.length == b.capabilities.length &&
      a.capabilities.containsAll(b.capabilities);
}
