import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/features/stickers/application/received_sticker_feedback.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/sticker_editor_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_custom_sticker_library.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final sticker = CustomSticker(
    id: 's',
    asset: fakeStickerAsset('s'),
    createdAtMs: 0,
    lastUsedAtMs: 0,
    position: 0,
  );

  Future<List<String>> run(Future<CustomSticker?> Function() save) async {
    final shown = <String>[];
    await saveReceivedStickerWithFeedback(
      l10n: l10n,
      isCurrent: () => true,
      editPhoto: ({required sourceImagePath, required outputDirectory}) async =>
          const StickerEditorResult.cancelled(),
      save: (_) => save(),
      show: shown.add,
    );
    return shown;
  }

  test('a saved sticker says Saved to My stickers', () async {
    expect(await run(() async => sticker), ['Saved to My stickers']);
  });

  test('a cancelled editor shows nothing', () async {
    expect(await run(() async => null), isEmpty);
  });

  test('a full library says so', () async {
    expect(
      await run(
        () async => throw const CustomStickerException(
          CustomStickerErrorCode.byteQuota,
        ),
      ),
      ['My stickers is full. Delete one to add another.'],
    );
  });

  test('a late core refusal or any failure says Couldn\'t save', () async {
    for (final error in <Object>[
      const CustomStickerException(CustomStickerErrorCode.notEligible),
      const CustomStickerException(CustomStickerErrorCode.unavailable),
      const FileSystemException('disk full'),
    ]) {
      expect(await run(() async => throw error), [
        "Couldn't save this sticker. Try again.",
      ]);
    }
  });

  test(
    'a chat left while core prepares opens no editor and shows nothing',
    () async {
      var current = true;
      final prepared = Completer<void>();
      final editorCalls = <String>[];
      final shown = <String>[];
      StickerEditorResult? editorResult;

      final pending = saveReceivedStickerWithFeedback(
        l10n: l10n,
        isCurrent: () => current,
        editPhoto:
            ({required sourceImagePath, required outputDirectory}) async {
              editorCalls.add(sourceImagePath);
              return StickerEditorResult.ready(fakeStickerAsset('edited'));
            },
        save: (editPhoto) async {
          await prepared.future;
          editorResult = await editPhoto(
            sourceImagePath: '/lent/photo.jpg',
            outputDirectory: Directory.systemTemp,
          );
          return editorResult is StickerEditorReady ? sticker : null;
        },
        show: shown.add,
      );
      current = false;
      prepared.complete();
      await pending;

      expect(editorCalls, isEmpty);
      expect(editorResult, isA<StickerEditorCancelled>());
      expect(shown, isEmpty);
    },
  );

  test('a chat left after the save shows no late message', () async {
    var current = true;
    final shown = <String>[];

    await saveReceivedStickerWithFeedback(
      l10n: l10n,
      isCurrent: () => current,
      editPhoto: ({required sourceImagePath, required outputDirectory}) async =>
          const StickerEditorResult.cancelled(),
      save: (_) async {
        current = false;
        return sticker;
      },
      show: shown.add,
    );

    expect(shown, isEmpty);
  });
}
