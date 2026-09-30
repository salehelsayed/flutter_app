"""Headless recovery convergence: a plaintext delivery_receipt parked for the foreground runtime
(typed_handler_unavailable in recovery-only mode) must not hold the drain open forever. Content types still block.
Adds a regression test. Both checkouts, exact-match guards."""
import pathlib
code_rel = 'lib/core/services/p2p_impl/p2p_inbox_coordinator.dart'
code_old = """  Future<DirectInboxDrainOutcome> _verifyFullDrainOutcome(
    DirectInboxDrainOutcome outcome,
  ) async {
    if (!outcome.isSuccessful || outcome.hasMore) return outcome;
    try {
      final recoverable = await _inboxStagingRepository.getRecoverableEntries(
        limit: 1,
      );
      if (recoverable.isEmpty) return outcome;
"""
code_new = """  /// A recovery-only runtime parks a plaintext delivery receipt for the
  /// foreground runtime. No further headless pass can replay it and it never
  /// notifies, so it must not keep headless recovery from converging.
  bool _isForegroundDeferredReceipt(InboxStagingEntry entry) =>
      _recoveryOnly &&
      entry.messageType == 'delivery_receipt' &&
      entry.rejectReasonCode == 'typed_handler_unavailable';

  Future<DirectInboxDrainOutcome> _verifyFullDrainOutcome(
    DirectInboxDrainOutcome outcome,
  ) async {
    if (!outcome.isSuccessful || outcome.hasMore) return outcome;
    try {
      final recoverable = await _inboxStagingRepository.getRecoverableEntries(
        limit: _recoveryOnly ? _maxRecoverableInboxReplayEntries : 1,
      );
      if (recoverable.every(_isForegroundDeferredReceipt)) return outcome;
"""
test_rel = 'test/core/services/p2p_service_recovery_only_test.dart'
test_anchor = """  test('recovery seal awaits admitted LAN staged replay', () async {
"""
test_new = """  test(
    'recovery drain converges when only a foreground-deferred delivery receipt remains',
    () async {
      final bridge = _RecoveryBridge()
        ..when('node:start', (_) => _nodeState(peerId: 'self-peer'))
        ..when(
          'inbox:retrieve_pending',
          (_) => <String, dynamic>{
            'ok': true,
            'messages': <dynamic>[],
            'hasMore': false,
            'custodyContract': ackOrExpiryInboxCustodyContract,
          },
        );
      final repo = InMemoryInboxStagingRepository()
        ..seed(
          InboxStagingEntry(
            entryId: 'receipt',
            ownerPeerId: 'self-peer',
            senderPeerId: 'remote-peer',
            messageType: 'delivery_receipt',
            relayTimestamp: '2026-08-16T00:00:00.000Z',
            envelope: jsonEncode(<String, dynamic>{
              'type': 'delivery_receipt',
              'messageId': 'sent-1',
            }),
            stagedAt: '2026-08-16T00:00:00.000Z',
          ),
        );
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        recoveryOnly: true,
      );
      addTearDown(service.dispose);

      expect(
        await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
        isTrue,
      );
      final outcome = await service.drainOfflineInboxFully();

      expect(outcome.isSuccessful, isTrue);
      expect(outcome.hasMore, isFalse);
      expect(outcome.failureReason, isNull);
      // The receipt stays durable for the foreground runtime to apply.
      expect(repo.entry('receipt')?.status, 'retryable');
      expect(
        repo.entry('receipt')?.rejectReasonCode,
        'typed_handler_unavailable',
      );
    },
  );

""" + test_anchor
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    for rel, old, new in ((code_rel, code_old, code_new), (test_rel, test_anchor, test_new)):
        p = pathlib.Path(root, rel); s = p.read_text()
        if new in s: continue
        assert s.count(old) == 1, (root, rel); p.write_text(s.replace(old, new))
    print('patched', root)
