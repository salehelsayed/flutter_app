import 'dart:convert';
import 'dart:math';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';

/// FDC-09 §12 — mints a per-contact opaque wake-token for each contact (so only
/// a contact presenting a member token can wake the recipient), persists the
/// {contact -> token} map, and registers the token SET with the relay.
///
/// NET-REL-07: an old relay that does not support `register_wake_tokens`
/// (registrar returns false) is a GRACEFUL degrade — the minted tokens are still
/// persisted client-side and the existing plain push keeps working ungated. It
/// never throws or retries/spams.
///
/// Not auto-wired into the live contact flow yet (host-tested capability) — like
/// FDC-09's lifecycle wiring, activation lands with the device/live-relay closure
/// (the relay gate fails open until a recipient registers a set, so production is
/// unaffected until then).
class IssueWakeTokensUseCase {
  IssueWakeTokensUseCase({
    required this.wakeTokenStore,
    required this.registerWakeTokens,
    String Function()? mintToken,
  }) : _mint = mintToken ?? _defaultMintToken;

  final WakeTokenStore wakeTokenStore;

  /// Registers the opaque wake-token SET with the relay. Returns true when the
  /// relay accepted it; false when unsupported (old relay) or it failed.
  final Future<bool> Function(List<String> tokens) registerWakeTokens;

  final String Function() _mint;

  /// Ensures every contact in [contactPeerIds] has a minted+persisted wake-token,
  /// then (re-)registers the full set with the relay. Returns the relay's
  /// acceptance (false = unsupported/failed → graceful degrade). Never throws.
  Future<bool> issueForContacts(List<String> contactPeerIds) async {
    final tokens = Map<String, String>.from(await wakeTokenStore.readTokens());
    var minted = false;
    for (final contact in contactPeerIds) {
      if (contact.isEmpty) continue;
      if (!tokens.containsKey(contact)) {
        tokens[contact] = _mint();
        minted = true;
        emitFlowEvent(
          layer: 'FL',
          event: 'WAKE_TOKEN_ISSUED',
          details: {'contact': contact},
        );
      }
    }
    if (minted) {
      await wakeTokenStore.writeTokens(tokens);
    }
    if (tokens.isEmpty) {
      return true; // nothing to register
    }

    final ok = await registerWakeTokens(tokens.values.toList(growable: false));
    if (!ok) {
      // NET-REL-07: old relay / failure. The minted tokens are persisted client-
      // side and the existing plain push keeps working ungated — never spam/retry.
      emitFlowEvent(
        layer: 'FL',
        event: 'WAKE_TOKEN_REGISTER_UNSUPPORTED',
        details: {'count': tokens.length},
      );
    }
    return ok;
  }

  static String _defaultMintToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }
}
