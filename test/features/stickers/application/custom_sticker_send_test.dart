import 'dart:async';

import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_send.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_custom_sticker_library.dart';

void main() {
  late FakeCustomStickerLibrary library;
  late List<String> log;

  setUp(() {
    library = FakeCustomStickerLibrary(ids: ['a']);
    log = [];
  });

  Future<void> send({
    bool Function()? isCurrent,
    bool adopted = true,
    Object? failBeforeAdopting,
    Object? failAfterAdopting,
  }) => sendCustomSticker(
    library: library,
    id: 'a',
    isCurrent: isCurrent ?? () => true,
    send: (markerId, media, adopt) async {
      log.add('send $markerId ${media.file.path}');
      if (failBeforeAdopting != null) throw failBeforeAdopting;
      if (adopted) adopt();
      if (failAfterAdopting != null) throw failAfterAdopting;
    },
    discard: (PendingComposerMedia media) =>
        log.add('discard ${media.file.path}'),
    onPrepareError: (error) => log.add('error ${error.runtimeType}'),
  );

  test('prepares once with the shared default and sends as custom', () async {
    await send();

    expect(library.prepareCalls, [
      ('a', defaultCustomStickerSendRepresentation),
    ]);
    expect(log, ['send custom /nonexistent/send-a.webp']);
  });

  test('a chat left during preparation discards the media unsent', () async {
    var current = true;
    library.prepareGate = Completer<void>();

    final pending = send(isCurrent: () => current);
    current = false;
    library.prepareGate!.complete();
    await pending;

    expect(log, ['discard /nonexistent/send-a.webp']);
  });

  test('a send the chat refuses releases the prepared copy', () async {
    await send(adopted: false);

    expect(log, [
      'send custom /nonexistent/send-a.webp',
      'discard /nonexistent/send-a.webp',
    ]);
  });

  test(
    'a send that fails before adopting releases the copy and rethrows',
    () async {
      await expectLater(
        send(failBeforeAdopting: StateError('db read failed')),
        throwsStateError,
      );

      expect(log, [
        'send custom /nonexistent/send-a.webp',
        'discard /nonexistent/send-a.webp',
      ]);
    },
  );

  test(
    'a send that fails after adopting keeps the copy for its retries',
    () async {
      await expectLater(
        send(failAfterAdopting: StateError('upload failed')),
        throwsStateError,
      );

      expect(log, ['send custom /nonexistent/send-a.webp']);
    },
  );

  test('a preparation failure is reported and nothing is sent', () async {
    library.prepareError = const CustomStickerException(
      CustomStickerErrorCode.unavailable,
    );

    await send();

    expect(log, ['error CustomStickerException']);
  });
}
