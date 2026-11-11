import 'dart:async';

import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/data/sqlite_custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';

/// Stable account-library reference retained by routes across account changes.
///
/// The factory combines its captured `isCurrent` predicate with passive account
/// checks in the concrete library's mayUseAccount callback. Construction and
/// subscription do not initialize the factory or access account storage.
final class AccountCustomStickerLibrary implements CustomStickerLibrary {
  AccountCustomStickerLibrary({
    required Future<SqliteCustomStickerLibrary?> Function(
      bool Function() isCurrent,
    )
    createLibrary,
    bool enabled = kCustomStickersEnabled,
  }) : _createLibrary = createLibrary,
       _enabled = enabled;

  final Future<SqliteCustomStickerLibrary?> Function(bool Function() isCurrent)
  _createLibrary;
  final bool _enabled;
  final _changes = StreamController<void>.broadcast(sync: true);
  late final Stream<void> _changeStream = _changes.stream;
  _StickerLibraryGeneration? _current;
  bool _blocked = false;
  Future<void> _retirement = Future<void>.value();

  bool _isCurrent(_StickerLibraryGeneration generation) =>
      !_blocked && identical(_current, generation);

  Future<SqliteCustomStickerLibrary?> _start(
    _StickerLibraryGeneration generation,
    Future<void> previousRetirement,
  ) =>
      generation.initialization ??= _initialize(generation, previousRetirement);

  Future<SqliteCustomStickerLibrary?> _initialize(
    _StickerLibraryGeneration generation,
    Future<void> previousRetirement,
  ) async {
    final SqliteCustomStickerLibrary? library;
    try {
      // Also ensures initialization is published before invoking the factory.
      await previousRetirement;
      if (!_isCurrent(generation)) return null;
      library = await _createLibrary(() => _isCurrent(generation));
    } catch (_) {
      _closeGeneration(generation, allowInitialRetry: false);
      return null;
    }

    // The retirement barrier awaits this result and retires a late delegate.
    // A superseded completion must not alter the replacement generation.
    if (!_isCurrent(generation)) return library;
    if (library == null) {
      _closeGeneration(
        generation,
        allowInitialRetry: generation.retryIfNoIdentity,
      );
      return null;
    }
    generation.subscription = library.changes.listen((_) {
      if (_isCurrent(generation)) _changes.add(null);
    });
    return library;
  }

  void _closeGeneration(
    _StickerLibraryGeneration generation, {
    required bool allowInitialRetry,
  }) {
    if (!identical(_current, generation)) return;
    _current = null;
    _blocked = !allowInitialRetry;
  }

  Future<T> _run<T>(
    Future<T> Function(SqliteCustomStickerLibrary library) action,
  ) async {
    if (!_enabled) {
      throw const CustomStickerException(CustomStickerErrorCode.disabled);
    }
    if (_blocked) _unavailable();
    final generation = _current ??= _StickerLibraryGeneration(
      retryIfNoIdentity: true,
    );
    final library = await _start(generation, _retirement);
    if (library == null || !_isCurrent(generation)) _unavailable();
    return action(library);
  }

  /// Caller persists the export pause before entering this barrier. Its passive
  /// account guard prevents new file work until active authority is restored.
  /// Draining does not initialize an unused library or retire its generation.
  Future<void> drainForExport() {
    if (!_enabled) return Future<void>.value();
    return _drain(_current?.initialization, _retirement);
  }

  Future<void> _drain(
    Future<SqliteCustomStickerLibrary?>? initialization,
    Future<void> retirement,
  ) async {
    await retirement;
    if (initialization == null) return;
    final library = await initialization;
    if (library != null) await library.drain();
  }

  /// Revokes admission before yielding, then waits for initialization and all
  /// concrete file work. The public changes stream stays open for a successor.
  Future<void> retire() {
    if (!_enabled) return Future<void>.value();
    _blocked = true;
    final generation = _current;
    _current = null;
    if (generation == null) return _retirement;
    return _retirement = Future.wait<void>([
      _retirement,
      _retireGeneration(generation),
    ]).then<void>((_) {});
  }

  Future<void> _retireGeneration(_StickerLibraryGeneration generation) async {
    final initialization = generation.initialization;
    if (initialization == null) return;
    final library = await initialization;
    if (library != null) await library.retire();
    await generation.subscription?.cancel();
    generation.subscription = null;
  }

  /// Caller has verified committed activation and refreshed account identity.
  /// An explicit call creates a new generation even for the same account binding.
  /// A failed activation stays closed until another explicit activation.
  Future<void> activate() {
    if (!_enabled) return Future<void>.value();
    final previousRetirement = retire();
    final generation = _StickerLibraryGeneration(retryIfNoIdentity: false);
    _current = generation;
    _blocked = false;
    return _finishActivation(
      generation,
      _start(generation, previousRetirement),
    );
  }

  Future<void> _finishActivation(
    _StickerLibraryGeneration generation,
    Future<SqliteCustomStickerLibrary?> initialization,
  ) async {
    final library = await initialization;
    if (library == null || !_isCurrent(generation)) _unavailable();
    _changes.add(null);
  }

  Never _unavailable() =>
      throw const CustomStickerException(CustomStickerErrorCode.unavailable);

  @override
  Stream<void> get changes => _changeStream;

  @override
  Future<List<CustomSticker>> list() {
    if (!_enabled) return Future.value(const <CustomSticker>[]);
    return _run((library) => library.list());
  }

  @override
  Future<CustomSticker> admit(NormalizedStickerAsset asset) =>
      _run((library) => library.admit(asset));

  @override
  Future<void> remove(String id) => _run((library) => library.remove(id));

  @override
  Future<void> reorder(List<String> orderedIds) =>
      _run((library) => library.reorder(orderedIds));

  @override
  Future<PendingComposerMedia> prepareSend(
    String id, {
    required CustomStickerSendRepresentation representation,
  }) => _run(
    (library) => library.prepareSend(id, representation: representation),
  );
}

final class _StickerLibraryGeneration {
  _StickerLibraryGeneration({required this.retryIfNoIdentity});

  final bool retryIfNoIdentity;
  Future<SqliteCustomStickerLibrary?>? initialization;
  StreamSubscription<void>? subscription;
}
