Your plan is the right direction, but it misses a few critical integration details in this codebase.

  1. media_ready direction is inconsistent.
     In your flow, media_ready is “internal receiver app event”, but in sender flow you wait for it over
     WS. Pick one.
     If sender must wait, send a WS media_uploaded/media_ready back to sender with id + nonce.
  2. Local-first cannot be achieved by changing only use cases.
     Attachments are uploaded before sendChatMessage in conversation_wired.dart (/Users/I560101/Project-
     Sat/mknoon-2/flutter_app/lib/features/conversation/presentation/screens/conversation_wired.dart), and
     voice also uploads first in send_voice_message_use_case.dart (/Users/I560101/Project-Sat/mknoon-2/
     flutter_app/lib/features/conversation/application/send_voice_message_use_case.dart).
     So your orchestration point must move there (or into a new shared orchestrator used by UI + voice
     flow).
  3. Current dual-path behavior conflicts with local-only media IDs.
     sendChatMessage intentionally continues to relay/inbox after WiFi success. If media is only local,
     relay recipients may get metadata for blobs that do not exist.
     You must decide:

  - local success => skip relay path for that message, or
  - still upload media to relay (background) before relay/inbox.

  4. GET /media/<id> is unnecessary in v1 and adds surface area.
     Receiver app and HTTP server are in the same process; after PUT you can emit local file path and mark
     attachment done.
     Start with PUT only.
  5. WS control messages need per-message correlation (nonce/requestId).
     You already rely on nonce correlation in local_ws_server.dart (/Users/I560101/Project-Sat/mknoon-2/
     flutter_app/lib/core/local_discovery/local_ws_server.dart). Media offer/accept/ready/received should
     do the same, especially for concurrent transfers.
  6. Don’t auto-delete completed files after 10 minutes.
     That conflicts with chat history persistence. Pending/failed temp files can expire; completed media
     should move to persistent media path and stay.
  7. Add one more integration point.
     chat_message_listener.dart (/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/
     application/chat_message_listener.dart) currently auto-downloads pending media from relay. Local-
     received media should be marked done with localPath so this path is skipped.
