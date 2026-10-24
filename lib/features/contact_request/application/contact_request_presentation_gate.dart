import 'package:flutter/foundation.dart';

class ContactRequestPresentationGate extends ChangeNotifier {
  final Set<String> _suppressedPeerIds = <String>{};
  bool _suppressAll = false;

  void suppressAll() {
    _suppressAll = true;
  }

  void releaseAll() {
    if (!_suppressAll) return;
    _suppressAll = false;
    notifyListeners();
  }

  void suppress(String peerId) {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) {
      return;
    }
    _suppressedPeerIds.add(normalizedPeerId);
  }

  void release(String peerId) {
    if (_suppressedPeerIds.remove(peerId.trim())) notifyListeners();
  }

  bool shouldSuppress(String peerId) {
    return _suppressAll || _suppressedPeerIds.contains(peerId.trim());
  }
}
