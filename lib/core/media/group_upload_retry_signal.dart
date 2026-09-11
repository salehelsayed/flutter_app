import 'dart:async';

// Foreground hints are emitted after releasing upload leases. Persisted group
// rows and their authority checks still decide which uploads can be retried.
final _groupUploadRetryRequests = StreamController<void>.broadcast();

Stream<void> get groupUploadRetryRequests => _groupUploadRetryRequests.stream;

void requestGroupUploadRetry() => _groupUploadRetryRequests.add(null);
