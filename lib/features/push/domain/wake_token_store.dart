/// FDC-09 §12 — persistence for the opaque wake-tokens a recipient MINTS for its
/// contacts (anti-spam: "only contacts can wake you"). The recipient keeps a map
/// {contactPeerId -> opaque token} so it can re-register the set after a reload
/// and (later) resolve which contact a token belongs to. The tokens are opaque
/// random strings — the relay never learns the contact graph (unlinkable).
abstract class WakeTokenStore {
  /// The persisted {contactPeerId -> opaque wake-token} map ({} if none).
  Future<Map<String, String>> readTokens();

  /// Replaces the persisted map.
  Future<void> writeTokens(Map<String, String> tokens);

  /// Clears all persisted wake-tokens.
  Future<void> clear();
}
