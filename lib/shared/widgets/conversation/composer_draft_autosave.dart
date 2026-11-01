import 'dart:async';

import 'package:flutter_app/core/media/composer_draft_store.dart';

/// Mirrors one chat screen's composer into a [ComposerDraftStore].
///
/// Changes are ignored until [restore] or [startWithoutRestore] runs, so the
/// screen's own initial publishes cannot clear the draft it is about to load.
/// [read] returns null while the composer holds something that is not a
/// draft, such as an edit of a sent message.
final class ComposerDraftAutosave {
  ComposerDraftAutosave({
    required ComposerDraftStore store,
    required ComposerDraftKey key,
    required ComposerDraft? Function() read,
  }) : _store = store,
       _key = key,
       _read = read;

  final ComposerDraftStore _store;
  final ComposerDraft? Function() _read;
  ComposerDraftKey _key;
  bool _ready = false;
  bool _closed = false;
  ComposerDraft? _lastSaved;

  /// Loads the saved draft and passes it to [apply] if the user has not
  /// started composing in the meantime. A failed load restores nothing.
  Future<void> restore(void Function(ComposerDraft draft) apply) async {
    final key = _key;
    ComposerDraft? saved;
    try {
      saved = await _store.load(key);
    } on Object {
      saved = null;
    }
    if (_closed || _ready || key != _key) return;
    final current = _read();
    if (saved != null && (current == null || current.isEmpty)) apply(saved);
    _lastSaved = saved ?? ComposerDraft.empty;
    _ready = true;
    changed();
  }

  /// For a screen opened with its own content (a share, a thought reply):
  /// that content replaces the saved draft once it is non-empty.
  void startWithoutRestore() {
    if (_closed) return;
    _lastSaved = ComposerDraft.empty;
    _ready = true;
    changed();
  }

  /// Saves the composer if it differs from what was last saved.
  void changed() {
    if (!_ready || _closed) return;
    final draft = _read();
    if (draft == null || draft == _lastSaved) return;
    _lastSaved = draft;
    unawaited(_store.save(_key, draft).catchError((_) {}));
  }

  /// Saves the current chat's draft, then stops saving until the new chat's
  /// draft is restored or skipped.
  void switchTo(ComposerDraftKey key) {
    changed();
    _key = key;
    _ready = false;
    _lastSaved = null;
  }

  /// Saves the final state. Later calls do nothing.
  void close() {
    changed();
    _closed = true;
  }
}
