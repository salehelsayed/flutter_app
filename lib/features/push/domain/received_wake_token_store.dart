/// FDC-09 §12 / CV-14 — the SENDER-SIDE store of the wake-tokens a peer has
/// RECEIVED from its contacts. When contact R sends a signed contact_request
/// carrying its minted `wt` (the opaque token R authorized ME to present when
/// waking R), I persist it here keyed by R's peerId. Later, every `inbox:store`
/// I send to R attaches `received[R]` so the relay's §12 access-token gate
/// authorizes waking R ("only contacts can wake you").
///
/// Deliberately ASYMMETRIC vs [WakeTokenStore] (the recipient-minted
/// {contact -> token} map): this holds {peerId -> {"tok","ts"}} where `ts` is the
/// ISO8601 UTC timestamp of the distributing contact_request payload, kept for
/// anti-rollback (a replayed OLD token must not clobber a newer stored one).
abstract class ReceivedWakeTokenStore {
  /// The received {"tok","ts"} for [peerId], or null if none. `ts` is the
  /// ISO8601 UTC string from the distributing contact_request payload.
  Future<Map<String, String>?> readTokenFor(String peerId);

  /// Stores/replaces the received token for [peerId]. Anti-rollback is the
  /// caller's responsibility (only write when the inbound ts is strictly newer).
  Future<void> writeTokenFor(String peerId, String token, String ts);

  /// Removes the received token for [peerId] (contact archived/blocked/removed).
  Future<void> removeTokenFor(String peerId);

  /// Clears all received wake-tokens.
  Future<void> clear();
}
