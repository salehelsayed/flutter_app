import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/application/received_sticker_saver.dart';
import 'package:flutter_app/features/stickers/custom/create/sticker_create_screens.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/sticker_editor_result.dart';
import 'package:flutter_app/features/stickers/presentation/custom_sticker_scope.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../../shared/fakes/fake_just_audio.dart';
import '../../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../stickers/fake_custom_sticker_library.dart';
import 'conversation_wired_test.dart' as fixtures;

class _PreparingSave extends Fake implements ReceivedMediaActionController {
  _PreparingSave(this.source, this.output);

  final File source;
  final Directory output;
  final prepared = Completer<void>();
  StickerEditorResult? editorResult;

  @override
  Future<CustomSticker?> saveReceivedSticker({
    required DirectReceivedMediaActionIdentity identity,
    required CustomStickerLibrary library,
    required ReceivedStickerEditor editPhoto,
  }) async {
    await prepared.future;
    if (identity.attachmentId == 'photo') {
      editorResult = await editPhoto(
        sourceImagePath: source.path,
        outputDirectory: output,
      );
      return null;
    }
    return CustomSticker(
      id: 'saved',
      asset: fakeStickerAsset('saved'),
      createdAtMs: 0,
      lastUsedAtMs: 0,
      position: 0,
    );
  }
}

void main() {
  testWidgets('received sticker action respects its gate and an accepted Back '
      'while the chat is still mounted', (tester) async {
    installFakeJustAudioPlatform();
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
    addTearDown(
      () => UploadWakeLockController.debugReset(
        driver: FakeUploadWakeLockDriver(),
      ),
    );
    final root = Directory.systemTemp.createTempSync('sticker-route-exit-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = File('${root.path}/source.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 30)));
    final output = Directory('${root.path}/output')..createSync();
    final controller = _PreparingSave(source, output);
    final messages = fixtures.FakeMessageRepository();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('Previous page')),
      ),
    );
    final route = MaterialPageRoute<void>(
      builder: (_) => CustomStickerScope(
        library: FakeCustomStickerLibrary(),
        child: ConversationWired(
          contact: const ContactModel(
            peerId: 'contact',
            publicKey: 'pub',
            rendezvous: '',
            username: 'Alice',
            signature: 'sig',
            scannedAt: '2026-11-11',
          ),
          identityRepo: fixtures.FakeIdentityRepository(
            IdentityModel(
              peerId: 'self',
              publicKey: 'pub',
              privateKey: 'priv',
              mnemonic12:
                  'one two three four five six seven eight nine ten eleven twelve',
              username: 'Me',
              createdAt: '2026-11-11',
              updatedAt: '2026-11-11',
            ),
          ),
          messageRepo: messages,
          chatMessageListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messages,
            contactRepo: fixtures.FakeContactRepository(),
          ),
          p2pService: fixtures.FakeP2PService(),
          audioRecorderService: FakeAudioRecorderService(),
          micPermissionGateway: FakeMicPermissionGateway(),
          receivedMediaActionController: controller,
        ),
      ),
    );
    unawaited(navigatorKey.currentState!.push(route));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final chatState = tester.state(find.byType(ConversationWired));
    final save = tester
        .widget<ConversationScreen>(find.byType(ConversationScreen))
        .onSaveReceivedSticker;
    if (!kCustomStickersEnabled) {
      expect(save, isNull);
      return;
    }
    expect(save, isNotNull);
    var photoDone = false;
    var savedDone = false;
    unawaited(
      save!(
        const DirectReceivedMediaActionIdentity(
          messageId: 'message',
          attachmentId: 'photo',
        ),
      ).then((_) => photoDone = true),
    );
    unawaited(
      save(
        const DirectReceivedMediaActionIdentity(
          messageId: 'message',
          attachmentId: 'canonical',
        ),
      ).then((_) => savedDone = true),
    );
    expect(await navigatorKey.currentState!.maybePop(), isTrue);
    await tester.pump();
    expect(route.isActive, isFalse);
    expect(chatState.mounted, isTrue);
    controller.prepared.complete();
    for (var i = 0; i < 100 && !photoDone; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find.byType(StickerCropScreen).evaluate().isNotEmpty) break;
    }
    expect(chatState.mounted, isTrue);
    expect(find.byType(StickerCropScreen), findsNothing);
    expect(controller.editorResult, isA<StickerEditorCancelled>());
    expect(photoDone && savedDone, isTrue);
    expect(find.byType(SnackBar), findsNothing);
    expect(output.listSync(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
