import '../data/call_history_repository.dart';
import '../domain/call_id.dart';

/// Optional access supplied by the existing durable history projection.
abstract interface class CallHistoryAccess {
  Future<CallHistoryEntry?> findCall(CallId id);
  Future<List<CallHistoryEntry>> recentCallsForContact(String peerId);
}

abstract interface class CallHistoryBrowsingSource {
  CallHistoryBrowser? get callHistoryBrowser;
}
