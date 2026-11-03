import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart';
import 'package:flutter_app/features/share/presentation/screens/group_media_batch_forward_picker_screen.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/avatar_image_provider.dart';

enum _Picker { share, directBatch, groupBatch }

ContactModel _contact(String id, {String? avatarPath}) => ContactModel(
  peerId: id,
  publicKey: 'fixture-public-key',
  rendezvous: '/dns4/relay.invalid/tcp/443',
  username: 'Friend',
  signature: 'fixture-signature',
  scannedAt: '2026-11-03T12:00:00Z',
  avatarPath: avatarPath,
);

GroupModel _group({String? avatarPath}) => GroupModel(
  id: 'photo-group',
  name: 'Friends Group',
  type: GroupType.chat,
  topicName: 'fixture-topic',
  createdAt: DateTime.utc(2026, 11, 3),
  createdBy: 'self',
  myRole: GroupRole.admin,
  avatarPath: avatarPath,
);

Finder _contactRow(_Picker picker, String id) => find.byKey(
  ValueKey(switch (picker) {
    _Picker.share => 'share-contact-$id',
    _Picker.directBatch => 'direct-batch-forward-contact-$id',
    _Picker.groupBatch => 'group-batch-forward-contact-$id',
  }),
);

Finder _groupRow(_Picker picker, String id) => find.byKey(
  ValueKey(
    picker == _Picker.share
        ? 'share-group-$id'
        : 'group-batch-forward-group-$id',
  ),
);

Widget _screen(
  _Picker picker, {
  List<ContactModel> contacts = const [],
  List<GroupModel> groups = const [],
  ValueChanged<ContactModel>? onToggleContact,
  ValueChanged<GroupModel>? onToggleGroup,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: switch (picker) {
    _Picker.share => ShareTargetPickerScreen(
      contacts: contacts,
      groups: groups,
      onToggleContact: onToggleContact ?? (_) {},
      onToggleGroup: onToggleGroup ?? (_) {},
    ),
    _Picker.directBatch => DirectMediaBatchForwardPickerScreen(
      items: const [],
      captionControllers: const [],
      contacts: contacts,
      selectedContactPeerIds: const {},
      isLoading: false,
      isSending: false,
      targetsFrozen: false,
      matrix: null,
      progress: null,
      showSourceUnavailable: false,
      onToggleContact: onToggleContact ?? (_) {},
      onClose: () {},
    ),
    _Picker.groupBatch => GroupMediaBatchForwardPickerScreen(
      items: const [],
      captionControllers: const [],
      contacts: contacts,
      groups: groups,
      selectedContactPeerIds: const {},
      selectedGroupIds: const {},
      isLoading: false,
      isSending: false,
      targetsFrozen: false,
      matrix: null,
      progress: null,
      sourceDenial: null,
      onToggleContact: onToggleContact ?? (_) {},
      onToggleGroup: onToggleGroup ?? (_) {},
      onClose: () {},
    ),
  },
);

Future<File> _writePhoto(WidgetTester tester, File file) async {
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 160, 80),
      Paint()..color = Colors.blue,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(160, 80);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
    picture.dispose();

    final decoded = Completer<void>();
    final stream = avatarResizedProvider(
      FileImage(file),
      40,
    ).resolve(const ImageConfiguration());
    final listener = ImageStreamListener((_, _) {
      if (!decoded.isCompleted) decoded.complete();
    }, onError: decoded.completeError);
    stream.addListener(listener);
    try {
      await decoded.future.timeout(const Duration(seconds: 5));
    } finally {
      stream.removeListener(listener);
    }
  });
  return file;
}

Future<void> _resolveFriendPhoto(WidgetTester tester, String id) async {
  await tester.runAsync(() async {
    final path = UserAvatar.avatarPathListenable(id);
    if (path.value != null) return;
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
  });
}

Future<void> _expectPhoto(
  WidgetTester tester,
  Finder row,
  File expectedFile,
) async {
  final rawPhoto = find.descendant(of: row, matching: find.byType(RawImage));
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (rawPhoto.evaluate().length == 1 &&
        tester.renderObject<RenderImage>(rawPhoto).image != null) {
      break;
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  expect(
    rawPhoto,
    findsOneWidget,
    reason: 'The stored photo must be displayed',
  );
  expect(tester.renderObject<RenderImage>(rawPhoto).image, isNotNull);
  final photo = tester.widget<Image>(
    find.descendant(of: row, matching: find.byType(Image)),
  );
  final provider = photo.image is ResizeImage
      ? (photo.image as ResizeImage).imageProvider
      : photo.image;
  expect(provider, isA<FileImage>());
  expect((provider as FileImage).file.path, expectedFile.path);
  expect(
    find.descendant(of: row, matching: find.byType(RingAvatar)),
    findsNothing,
  );
  expect(tester.takeException(), isNull);
}

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('share_picker_avatar_');
    UserAvatar.setDocumentsDir(directory.path);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  void prepare(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  }

  for (final picker in _Picker.values) {
    testWidgets('${picker.name} picker displays the stored friend photo', (
      tester,
    ) async {
      prepare(tester);
      const id = 'photo-friend';
      const avatarPath = 'media/avatars/$id.jpg';
      final photo = await _writePhoto(
        tester,
        File('${directory.path}/$avatarPath'),
      );
      await _resolveFriendPhoto(tester, id);

      await tester.pumpWidget(
        _screen(picker, contacts: [_contact(id, avatarPath: avatarPath)]),
      );

      await _expectPhoto(tester, _contactRow(picker, id), photo);
    });

    testWidgets(
      '${picker.name} picker keeps missing-photo targets selectable',
      (tester) async {
        prepare(tester);
        final contact = _contact('missing-photo-friend');
        final group = _group(avatarPath: 'media/groups/missing-photo.png');
        ContactModel? selectedContact;
        GroupModel? selectedGroup;
        await tester.pumpWidget(
          _screen(
            picker,
            contacts: [contact],
            groups: picker == _Picker.directBatch ? const [] : [group],
            onToggleContact: (value) => selectedContact = value,
            onToggleGroup: (value) => selectedGroup = value,
          ),
        );
        final contactRow = _contactRow(picker, contact.peerId);
        expect(
          find.descendant(of: contactRow, matching: find.byType(RingAvatar)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: contactRow, matching: find.byType(RawImage)),
          findsNothing,
        );
        await tester.tap(contactRow);
        expect(selectedContact, same(contact));
        if (picker != _Picker.directBatch) {
          final groupRow = _groupRow(picker, group.id);
          expect(
            find.descendant(of: groupRow, matching: find.byType(RawImage)),
            findsNothing,
          );
          await tester.tap(groupRow);
          expect(selectedGroup, same(group));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final picker in [_Picker.share, _Picker.groupBatch]) {
    testWidgets('${picker.name} picker displays the stored group photo', (
      tester,
    ) async {
      prepare(tester);
      const avatarPath = 'media/groups/photo-group.png';
      final photo = await _writePhoto(
        tester,
        File('${directory.path}/$avatarPath'),
      );
      final group = _group(avatarPath: avatarPath);
      await tester.pumpWidget(_screen(picker, groups: [group]));

      await _expectPhoto(tester, _groupRow(picker, group.id), photo);
    });
  }
}
