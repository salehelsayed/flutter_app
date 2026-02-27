# Local Media Test TODO

- [x] 1. Sender fast-fails on `media_offer_rejected` (no timeout wait).
  File: `test/core/local_discovery/local_media_sender_test.dart`
- [x] 2. Sender fast-fails on `media_failed` after PUT (no timeout wait).
  File: `test/core/local_discovery/local_media_sender_test.dart`
- [x] 3. Concurrent `sendMedia` requests do not cross-match `media_offer_accepted` / `media_uploaded` nonces.
  File: `test/core/local_discovery/local_media_sender_test.dart`
- [x] 4. Upload rejects truncated body (declared size not fully received).
  File: `test/core/local_discovery/local_media_server_test.dart`
- [x] 5. WS server handles malformed `media_offer` payloads without crash and without side effects.
  File: `test/core/local_discovery/local_ws_server_test.dart`
- [x] 6. Path traversal guard for `mediaId` in upload path.
  File: `test/core/local_discovery/local_media_server_test.dart`
- [x] 7. Path traversal guard for `contactPeerId` in persist path.
  File: `test/core/local_discovery/local_media_server_test.dart`
- [x] 8. Authorization header variants rejected (`bearer`, malformed prefix, extra spaces).
  File: `test/core/local_discovery/local_media_server_test.dart`
- [x] 9. Boundary acceptance at exact max size (100MB) without buffering test file in memory.
  File: `test/core/local_discovery/local_media_server_test.dart`
- [x] 10. Local P2P delegation tests for `sendMedia` and P2P service `sendLocalMedia` delegation.
  Files: `test/core/local_discovery/local_p2p_service_test.dart`, `test/core/services/p2p_service_impl_test.dart`
- [x] 11. Orchestration coverage:
  - Unit fallback: upload succeeds but send fails returns `SendVoiceMessageResult.sendFailed`.
  - App-flow: local-ready persist path updates attachment to `done` and avoids relay download.
  - Device integration: WiFi media transfer roundtrip over LocalWsServer.
  Files: `test/features/conversation/application/send_voice_message_use_case_test.dart`, `test/features/conversation/application/chat_message_listener_test.dart`, `integration_test/wifi_transport_test.dart`
