Step 1 — QR code (offline, in-person)
  The QR contains Ed25519 identity (pk, ns, sig) but deliberately excludes the ML-KEM key to keep the QR compact.

  build_qr_payload_use_case.dart lines 59-60 — ML-KEM key is explicitly skipped.

  Step 2 — Contact request (over P2P)
  After scanning, the scanner sends a contact_request message that includes the mlkem field. The recipient accepts and sends
  back their own contact_request with their mlkem key.

  So the exchange is:

  QR scan        →  Ed25519 only (pk, ns, sig, rv, un)
                    No ML-KEM key

  contact_request →  Ed25519 + ML-KEM public key
  (Alice → Bob)     { "ns", "pk", "sig", "mlkem", "un", ... }

  contact_request →  Ed25519 + ML-KEM public key
  (Bob → Alice)     { "ns", "pk", "sig", "mlkem", "un", ... }

  Both contact_request messages travel as v1 plaintext envelopes — signed but not encrypted at the application layer. Chat
  messages are blocked until both sides have each other's ML-KEM key (send_chat_message_use_case.dart:131 returns
  encryptionRequired if the recipient's key is null).

  There's also a retry_incomplete_key_exchanges_use_case.dart that re-sends contact requests on app resume for any contact
  still missing an ML-KEM key.