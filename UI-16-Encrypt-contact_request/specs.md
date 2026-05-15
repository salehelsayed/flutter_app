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












orchestrate multiple agents (up to 10 agent) to work in parallel or sequence,  in order to create a plan to update @C4_MODEL.md and @file-structure.md to be updated withour current codebase, they are pretty outdated. each agent should be responsible of planning and executing a specific part.


PRompt:
the emojis are now implemented in bubble card in the main chat screen. I want you to enable users to send emojies on the feed cards in the app and also when they press on a chat bubble the emojies appear and they can select it. like in whatsapp/signal/telegram.

orchestrate multiple agents (up to 5) to review codebase to identify all the information you need to create a detailed TDD plan for this feature




ok great, now orchestrate up to 5 agents to work in parallel or sequence to lookup the codebase and understand everything it needs in order to generate a detailed TDD plan for this feature. take into consideration all the componentes from database to go-libp2p to bridnge to UI/UX. in your plan create all the unit tests, integration tests, smoke tests needed for the group messaging to work we.. when you orchestrate the agents and create the plan, make sure that you utilize multiple agents (up to 5 agents ) to implement the plan in parrallel or in sequnce as you needed to implement this well.