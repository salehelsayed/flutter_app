import 'dart:async';

import 'package:flutter_app/core/media/composer_draft_store.dart';
import 'package:flutter_app/shared/widgets/conversation/composer_draft_autosave.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedLoadStore implements ComposerDraftStore {
  _DelayedLoadStore(this.saved);

  final ComposerDraft saved;
  final loaded = Completer<ComposerDraft?>();
  final saves = <ComposerDraft>[];

  @override
  Future<ComposerDraft?> load(ComposerDraftKey key) => loaded.future;

  @override
  Future<void> save(ComposerDraftKey key, ComposerDraft draft) async {
    saves.add(draft);
  }

  @override
  Future<void> clear(ComposerDraftKey key) async {}
}

void main() {
  const key = ComposerDraftKey.direct('peer-alice');
  final saved = ComposerDraft(text: 'Saved draft text');

  test(
    'a draft that finishes loading during a sent-message edit is not put into that edit',
    () async {
      final store = _DelayedLoadStore(saved);
      ComposerDraft? composer = ComposerDraft.empty;
      final applied = <String>[];
      final autosave = ComposerDraftAutosave(
        store: store,
        key: key,
        read: () => composer,
      );

      final restoring = autosave.restore((draft) {
        applied.add(draft.text);
        composer = draft;
      });
      composer = null;
      store.loaded.complete(saved);
      await restoring;

      expect(applied, isEmpty);
      expect(store.saves, isEmpty);

      composer = ComposerDraft.empty;
      autosave.changed();

      expect(applied, ['Saved draft text']);
    },
  );

  test('typing before the saved draft arrives keeps what was typed', () async {
    final store = _DelayedLoadStore(saved);
    ComposerDraft? composer = ComposerDraft.empty;
    final applied = <String>[];
    final autosave = ComposerDraftAutosave(
      store: store,
      key: key,
      read: () => composer,
    );

    final restoring = autosave.restore((draft) => applied.add(draft.text));
    composer = ComposerDraft(text: 'Typed first');
    store.loaded.complete(saved);
    await restoring;

    expect(applied, isEmpty);
    expect(store.saves.map((draft) => draft.text), ['Typed first']);
  });

  test('a saved draft is restored into an empty composer', () async {
    final store = _DelayedLoadStore(saved);
    final applied = <String>[];
    final autosave = ComposerDraftAutosave(
      store: store,
      key: key,
      read: () => ComposerDraft.empty,
    );

    final restoring = autosave.restore((draft) => applied.add(draft.text));
    store.loaded.complete(saved);
    await restoring;

    expect(applied, ['Saved draft text']);
  });
}
