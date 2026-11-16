import 'dart:typed_data';

typedef EngagementChatBeforeCommit =
    Future<void> Function(String temporaryPath);
typedef EngagementChatRename =
    Future<void> Function(String temporaryPath, String checkpointPath);

/// A single private checkpoint, with a shared physical writer per canonical path.
///
/// The two filesystem seams permit controlled prepare/issued-rename races.
/// They do not replace the store's ownership, bounds or serialization policy.
final class EngagementChatCheckpointStore {
  EngagementChatCheckpointStore._(
    this.privateDirectory, {
    this.beforeCommit,
    this.rename,
  });

  final String privateDirectory;
  final EngagementChatBeforeCommit? beforeCommit;
  final EngagementChatRename? rename;

  String get checkpointPath =>
      '$privateDirectory/engagement-chat-witness-v1.json';

  static Future<EngagementChatCheckpointStore> open(
    String privateDirectory, {
    EngagementChatBeforeCommit? beforeCommit,
    EngagementChatRename? rename,
  }) => Future.value(
    EngagementChatCheckpointStore._(
      privateDirectory,
      beforeCommit: beforeCommit,
      rename: rename,
    ),
  );

  Future<Uint8List?> read({required bool Function() isCurrent}) =>
      Future<Uint8List?>.value();

  Future<bool> replace(
    Uint8List bytes, {
    required bool Function() isCurrent,
  }) => Future.value(false);

  Future<bool> clear({required bool Function() isCurrent}) =>
      Future.value(false);

  Future<void> close() => Future<void>.value();
}
