import 'dart:math';

import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import 'fake_p2p_network.dart';

/// Configuration for chaos injection.
class ChaosConfig {
  /// Probability of duplicating a message (0.0-1.0).
  final double duplicateRate;

  /// Buffer N messages, shuffle, then deliver as a batch.
  final int reorderBufferSize;

  /// Random delay per message (0..maxDelay).
  final Duration maxDelay;

  /// Probability of dropping a message entirely (0.0-1.0).
  final double dropRate;

  /// Optional seed for deterministic randomness.
  final int? seed;

  const ChaosConfig({
    this.duplicateRate = 0.0,
    this.reorderBufferSize = 0,
    this.maxDelay = Duration.zero,
    this.dropRate = 0.0,
    this.seed,
  });
}

/// Pending delivery entry for reorder buffer.
class _PendingDelivery {
  final String fromPeerId;
  final String toPeerId;
  final String content;

  _PendingDelivery(this.fromPeerId, this.toPeerId, this.content);
}

/// Network layer that injects chaos: drops, duplicates, reorders, delays.
///
/// Extends [FakeP2PNetwork] and overrides [deliver] with configurable
/// chaos behaviors.
class ChaosP2PNetwork extends FakeP2PNetwork {
  final ChaosConfig config;
  late final Random _random;

  /// Messages that were dropped (for test assertions).
  final List<String> droppedMessages = [];

  /// Reorder buffer — accumulates messages until buffer is full.
  final List<_PendingDelivery> _reorderBuffer = [];

  // -- Fault-injection hooks --

  /// When true, drop the very next message regardless of [ChaosConfig.dropRate].
  bool forceDropNext = false;

  /// Count of messages successfully delivered through this network.
  int deliveredCount = 0;

  /// Count of all deliver() attempts (including drops).
  int totalAttempted = 0;

  ChaosP2PNetwork({this.config = const ChaosConfig()}) {
    _random = config.seed != null ? Random(config.seed) : Random();
  }

  @override
  Future<bool> deliver(
      String fromPeerId, String toPeerId, String content) async {
    totalAttempted++;

    // 0. Force-drop override
    if (forceDropNext) {
      forceDropNext = false;
      droppedMessages.add(content);
      return false;
    }

    // 1. Drop check
    if (config.dropRate > 0 && _random.nextDouble() < config.dropRate) {
      droppedMessages.add(content);
      return false;
    }

    // 2. Delay
    if (config.maxDelay > Duration.zero) {
      final delayMs = _random.nextInt(config.maxDelay.inMilliseconds + 1);
      await Future.delayed(Duration(milliseconds: delayMs));
    }

    // 3. Reorder buffer
    if (config.reorderBufferSize > 1) {
      _reorderBuffer.add(_PendingDelivery(fromPeerId, toPeerId, content));

      if (_reorderBuffer.length >= config.reorderBufferSize) {
        // Shuffle and deliver the batch
        final batch = List<_PendingDelivery>.from(_reorderBuffer);
        _reorderBuffer.clear();
        batch.shuffle(_random);

        bool anyDelivered = false;
        for (final entry in batch) {
          final delivered = await _deliverWithDuplicate(
              entry.fromPeerId, entry.toPeerId, entry.content);
          if (delivered) anyDelivered = true;
        }
        return anyDelivered;
      }
      // Buffer not full yet — report success but don't deliver yet
      return true;
    }

    // 4. No reorder — deliver immediately (with possible duplicate)
    return _deliverWithDuplicate(fromPeerId, toPeerId, content);
  }

  /// Delivers a message and optionally duplicates it.
  Future<bool> _deliverWithDuplicate(
      String fromPeerId, String toPeerId, String content) async {
    final delivered = await super.deliver(fromPeerId, toPeerId, content);

    if (delivered) {
      deliveredCount++;
    }

    // Duplicate check — send the same message again
    if (config.duplicateRate > 0 &&
        _random.nextDouble() < config.duplicateRate) {
      await super.deliver(fromPeerId, toPeerId, content);
    }

    return delivered;
  }

  /// Flush any remaining messages in the reorder buffer.
  Future<void> flushReorderBuffer() async {
    if (_reorderBuffer.isEmpty) return;
    final batch = List<_PendingDelivery>.from(_reorderBuffer);
    _reorderBuffer.clear();
    batch.shuffle(_random);
    for (final entry in batch) {
      await _deliverWithDuplicate(
          entry.fromPeerId, entry.toPeerId, entry.content);
    }
  }

  /// Number of messages waiting in the reorder buffer.
  int get reorderBufferLength => _reorderBuffer.length;
}
