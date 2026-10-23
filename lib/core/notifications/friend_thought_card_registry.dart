import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:flutter_app/core/notifications/bounded_posix_flock.dart';

/// The outcome of claiming a friend's card for one thought. [current] is
/// false when a later thought already superseded this one. [retired] names
/// the card this claim replaced, for the caller to cancel.
typedef FriendThoughtCardClaim = ({bool current, String? retired});

/// Which thought card each friend holds right now: one card per friend.
///
/// The headless push isolate and the main isolate both show thought cards, and
/// the iOS notification extension shows them without touching this record, so
/// a thought can reach the main isolate after a newer one already holds the
/// friend's card. Each friend's file therefore keeps the keys claimed so far in
/// order, newest last, and a key behind the newest is superseded rather than
/// allowed to displace it. Files are named by the SHA-256 of the sender peer
/// id and every claim runs under one `flock`. Cards keep their own
/// `post:<postId>` key because expiry cancels by post; this registry only says
/// which one is current.
final class FriendThoughtCardRegistry {
  FriendThoughtCardRegistry({required this.directory});

  /// The shared registry beside the conversation notification ids.
  factory FriendThoughtCardRegistry.under(Directory notificationRoot) =>
      FriendThoughtCardRegistry(
        directory: Directory(
          '${notificationRoot.path}${Platform.pathSeparator}$directoryName',
        ),
      );

  final Directory directory;

  static const directoryName = 'ThoughtCards';
  static const _lockFileName = '.lock';

  /// Keys remembered per friend. Thoughts live three days, so a key this many
  /// thoughts behind is gone before it could be replayed.
  static const _historyLength = 32;

  /// Makes [cardKey] the friend's current card unless a later key already
  /// superseded it.
  Future<FriendThoughtCardClaim> claim({
    required String senderPeerId,
    required String cardKey,
  }) async {
    final sender = senderPeerId.trim();
    final key = cardKey.trim();
    if (sender.isEmpty) {
      throw ArgumentError.value(
        senderPeerId,
        'senderPeerId',
        'must not be empty',
      );
    }
    if (key.isEmpty) {
      throw ArgumentError.value(cardKey, 'cardKey', 'must not be empty');
    }
    await directory.create(recursive: true);
    final slot = _file(sha256.convert(utf8.encode(sender)).toString());
    return BoundedPosixFlock.withExclusive(_file(_lockFileName), () async {
      final history = await _read(slot);
      final index = history.indexOf(key);
      if (index >= 0) {
        return (current: index == history.length - 1, retired: null);
      }
      final kept = [...history, key];
      await _write(slot, kept.sublist(max(0, kept.length - _historyLength)));
      return (current: true, retired: history.isEmpty ? null : history.last);
    });
  }

  File _file(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  Future<List<String>> _read(File slot) async {
    try {
      if (!await slot.exists()) return const [];
      return [
        for (final line in (await slot.readAsString()).split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
    } on FileSystemException {
      return const [];
    }
  }

  Future<void> _write(File slot, List<String> history) async {
    final token = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    final temporary = _file(
      '.${base64UrlEncode(token).replaceAll('=', '')}.tmp',
    );
    try {
      await temporary.writeAsString(history.join('\n'), flush: true);
      // One atomic rename: a reader sees the old history or the new one,
      // never a half-written file, and a crash leaves an ignored temp file.
      await temporary.rename(slot.path);
      BoundedPosixFlock.syncDirectory(directory);
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Hidden leftovers are never read as a slot.
      }
    }
  }
}
