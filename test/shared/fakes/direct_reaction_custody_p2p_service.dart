import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import '../../core/services/fake_p2p_service.dart';

/// Sender-test transport with the optional typed inbox capability enabled.
class DirectReactionCustodyP2PService extends FakeP2PService
    implements DetailedInboxStore {
  DirectReactionCustodyP2PService({super.initialState});

  InboxStoreOutcome detailedInboxOutcome = const InboxStoreOutcome(
    status: InboxStoreStatus.stored,
  );
  Future<InboxStoreOutcome> Function(
    String toPeerId,
    String message, {
    int? timeoutMs,
  })?
  onStoreInInboxDetailed;
  bool throwOnDetailedInboxStore = false;
  bool throwOnLiveSend = false;

  @override
  Future<InboxStoreOutcome> storeInInboxDetailed(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    await super.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
    if (throwOnDetailedInboxStore) {
      throw StateError('synthetic detailed inbox store error');
    }
    final hook = onStoreInInboxDetailed;
    return hook == null
        ? detailedInboxOutcome
        : hook(toPeerId, message, timeoutMs: timeoutMs);
  }

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    final result = await super.sendMessage(peerId, message);
    if (throwOnLiveSend) throw StateError('synthetic live send error');
    return result;
  }
}
