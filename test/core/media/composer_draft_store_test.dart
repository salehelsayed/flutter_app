import 'dart:io';

import 'package:flutter_app/core/media/composer_draft_store.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory documents;
  late Directory picked;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('composer_draft_store_');
    documents = Directory(p.join(sandbox.path, 'Documents'))..createSync();
    picked = Directory(p.join(sandbox.path, 'picker_tmp'))..createSync();
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  FileComposerDraftStore newStore({bool excluded = true}) =>
      FileComposerDraftStore(
        documentsDirectory: () async => documents,
        excludeFromBackup: (_) async => excluded,
      );

  File pickedPhoto() =>
      File(p.join(picked.path, 'IMG_0001.JPG'))
        ..writeAsBytesSync(const [1, 2, 3, 4, 5]);

  List<String> filesUnder(Directory root) =>
      root
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => p.relative(file.path, from: root.path))
          .toList()
        ..sort();

  String draftsRoot() => p.join(documents.path, 'composer_drafts');

  test('composer draft store round trips caption, photo and size', () async {
    final store = newStore();
    final key = ComposerDraftKey.direct('peer-alice');
    final photo = pickedPhoto();

    await store.save(
      key,
      ComposerDraft(
        text: 'Look at this',
        attachments: [
          PendingComposerMedia(
            file: photo,
            budgetBytes: 5,
            width: 640,
            height: 480,
          ),
        ],
      ),
    );
    final loaded = await store.load(key);

    expect(loaded!.text, 'Look at this');
    final media = loaded.attachments.single;
    expect(media.file.readAsBytesSync(), const [1, 2, 3, 4, 5]);
    expect((media.budgetBytes, media.width, media.height), (5, 640, 480));
    expect(p.extension(media.file.path), '.jpg');
    expect(p.isWithin(draftsRoot(), media.file.path), isTrue);
    expect(loaded.privateMediaPolicy, const PrivateMediaPolicy.ordinary());
  });

  test(
    'composer draft store keeps the photo after the picker temp file is gone',
    () async {
      final store = newStore();
      final key = ComposerDraftKey.direct('peer-alice');
      final photo = pickedPhoto();
      await store.save(
        key,
        ComposerDraft(
          text: '',
          attachments: [PendingComposerMedia(file: photo, budgetBytes: 5)],
        ),
      );

      photo.deleteSync();
      final loaded = await store.load(key);

      expect(loaded!.attachments.single.file.readAsBytesSync(), const [
        1,
        2,
        3,
        4,
        5,
      ]);
    },
  );

  test(
    'composer draft store loads a private photo draft in a new store instance',
    () async {
      final key = ComposerDraftKey.direct('peer-alice');
      await newStore().save(
        key,
        ComposerDraft(
          text: '',
          attachments: [
            PendingComposerMedia(file: pickedPhoto(), budgetBytes: 5),
          ],
          privateMediaPolicy: const PrivateMediaPolicy.protected(),
        ),
      );

      final loaded = await newStore().load(key);

      expect(loaded!.privateMediaPolicy, const PrivateMediaPolicy.protected());
      expect(loaded.attachments.single.file.readAsBytesSync(), const [
        1,
        2,
        3,
        4,
        5,
      ]);
    },
  );

  test(
    'composer draft store saving an empty draft removes the chat folder',
    () async {
      final store = newStore();
      final key = ComposerDraftKey.group('group-1');
      await store.save(
        key,
        ComposerDraft(
          text: 'half typed',
          attachments: [
            PendingComposerMedia(file: pickedPhoto(), budgetBytes: 5),
          ],
        ),
      );
      expect(filesUnder(Directory(draftsRoot())), hasLength(2));

      await store.save(key, ComposerDraft(text: '  '));

      expect(await store.load(key), isNull);
      expect(filesUnder(Directory(draftsRoot())), <String>[]);
    },
  );

  test(
    'composer draft store a save queued before a clear does not come back',
    () async {
      final store = newStore();
      final key = ComposerDraftKey.direct('peer-alice');

      final staleSave = store.save(key, ComposerDraft(text: 'old text'));
      final clear = store.clear(key);
      await Future.wait([staleSave, clear]);

      expect(await store.load(key), isNull);
      expect(await newStore().load(key), isNull);
    },
  );

  test('composer draft store the latest of several saves wins', () async {
    final store = newStore();
    final key = ComposerDraftKey.direct('peer-alice');

    await Future.wait([
      store.save(key, ComposerDraft(text: 'H')),
      store.save(key, ComposerDraft(text: 'He')),
      store.save(key, ComposerDraft(text: 'Hello')),
    ]);

    expect((await newStore().load(key))!.text, 'Hello');
  });

  test(
    'composer draft store keeps ids with slashes or dot-dot under its root',
    () async {
      final store = newStore();
      await store.save(
        ComposerDraftKey.direct('../../escape'),
        ComposerDraft(text: 'one'),
      );
      await store.save(
        ComposerDraftKey.group('a/../../b/c'),
        ComposerDraft(text: 'two'),
      );

      expect(documents.listSync().map((entity) => p.basename(entity.path)), [
        'composer_drafts',
      ]);
      expect(sandbox.listSync().map((e) => p.basename(e.path)).toSet(), {
        'Documents',
        'picker_tmp',
      });
      expect(
        (await store.load(ComposerDraftKey.direct('../../escape')))!.text,
        'one',
      );
      expect(
        (await store.load(ComposerDraftKey.group('a/../../b/c')))!.text,
        'two',
      );
    },
  );

  test(
    'composer draft store copies no media when backup exclusion is unconfirmed',
    () async {
      final store = newStore(excluded: false);
      final key = ComposerDraftKey.direct('peer-alice');
      await store.save(
        key,
        ComposerDraft(
          text: 'caption only',
          attachments: [
            PendingComposerMedia(file: pickedPhoto(), budgetBytes: 5),
          ],
        ),
      );

      final loaded = await store.load(key);

      expect(loaded!.text, 'caption only');
      expect(loaded.attachments, isEmpty);
      expect(filesUnder(Directory(draftsRoot())).map(p.basename).toList(), [
        'draft.json',
      ]);
    },
  );
}
