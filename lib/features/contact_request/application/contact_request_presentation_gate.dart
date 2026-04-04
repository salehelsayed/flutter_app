class ContactRequestPresentationGate {
  final Set<String> _suppressedPeerIds = <String>{};
  bool _suppressAll = false;

  void suppressAll() {
    _suppressAll = true;
  }

  void releaseAll() {
    _suppressAll = false;
  }

  void suppress(String peerId) {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) {
      return;
    }
    _suppressedPeerIds.add(normalizedPeerId);
  }

  void release(String peerId) {
    _suppressedPeerIds.remove(peerId.trim());
  }

  bool shouldSuppress(String peerId) {
    return _suppressAll || _suppressedPeerIds.contains(peerId.trim());
  }
}
