import 'dart:async';

// Process-owned hint; persisted attachments remain the recovery authority.
// A foreground sender emits only after releasing its upload lease. This
// avoids waiting for a reconnect or the five-minute periodic sweep when an
// individual transfer fails on an otherwise usable connection.
final _directUploadRetryRequests = StreamController<void>.broadcast();

Stream<void> get directUploadRetryRequests => _directUploadRetryRequests.stream;

void requestDirectUploadRetry() => _directUploadRetryRequests.add(null);
