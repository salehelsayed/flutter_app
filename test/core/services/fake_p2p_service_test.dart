import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import 'fake_p2p_service.dart';

void main() {
  test('sentMessageLog records all sendMessage calls', () async {
    final svc = FakeP2PService(initialState: const NodeState(isStarted: true));
    await svc.sendMessage('peer-a', 'msg-1');
    await svc.sendMessage('peer-b', 'msg-2');

    expect(svc.sentMessageLog.length, 2);
    expect(svc.sentMessageLog[0], (peerId: 'peer-a', content: 'msg-1'));
    expect(svc.sentMessageLog[1], (peerId: 'peer-b', content: 'msg-2'));
  });
}
