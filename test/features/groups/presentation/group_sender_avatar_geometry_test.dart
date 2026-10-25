import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/avatar_image_provider.dart';

void main() {
  testWidgets('group sender photo stays square in the real message gutter', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = Directory.systemTemp.createTempSync(
      'group_avatar_square_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    const sender = 'avatar-square-sender';
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 160, 80),
        Paint()..color = Colors.blue,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(160, 80);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${directory.path}/media/avatars/$sender.jpg');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      UserAvatar.setDocumentsDir(directory.path);
      final path = UserAvatar.avatarPathListenable(sender);
      if (path.value == null) {
        final resolved = Completer<void>();
        void onResolved() {
          if (path.value != null && !resolved.isCompleted) resolved.complete();
        }

        path.addListener(onResolved);
        try {
          await resolved.future.timeout(const Duration(seconds: 5));
        } finally {
          path.removeListener(onResolved);
        }
      }
      // Decode outside fake async before the widget starts sharing this stream.
      final ready = Completer<void>();
      final stream = avatarResizedProvider(
        FileImage(file),
        32,
      ).resolve(const ImageConfiguration());
      final listener = ImageStreamListener(
        (_, _) => ready.complete(),
        onError: ready.completeError,
      );
      stream.addListener(listener);
      try {
        await ready.future.timeout(const Duration(seconds: 5));
      } finally {
        stream.removeListener(listener);
      }
    });
    final timestamp = DateTime.utc(2026, 10, 24);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GroupConversationScreen(
            group: GroupModel(
              id: 'avatar-square-group',
              name: 'Group',
              type: GroupType.chat,
              topicName: 'avatar-square-topic',
              createdAt: timestamp,
              createdBy: 'self',
              myRole: GroupRole.admin,
            ),
            messages: [
              GroupMessage(
                id: 'avatar-square-message',
                groupId: 'avatar-square-group',
                senderPeerId: sender,
                senderUsername: 'Sender',
                text: 'A group message',
                timestamp: timestamp,
                createdAt: timestamp,
                isIncoming: true,
              ),
            ],
            ownPeerId: 'self',
            onSend: (_) {},
            onBack: () {},
          ),
        ),
      ),
    );
    final avatar = find.byType(UserAvatar);
    final photo = find.descendant(of: avatar, matching: find.byType(Image));
    final imageWidget = tester.widget<Image>(photo);
    await tester.pump();
    final rawImage = tester.renderObject<RenderImage>(
      find.descendant(of: avatar, matching: find.byType(RawImage)),
    );
    expect(rawImage.image, isNotNull);
    expect(rawImage.image!.width, rawImage.image!.height * 2);
    expect(imageWidget.fit, BoxFit.cover);
    final clip = tester.getSize(
      find.descendant(of: avatar, matching: find.byType(ClipOval)),
    );
    expect(clip.width, clip.height, reason: 'a photo clip must be circular');
    expect(tester.getSize(avatar), const Size(32, 32));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
