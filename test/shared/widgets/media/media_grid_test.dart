import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

MediaAttachment _makeMedia(int i) {
  return MediaAttachment(
    id: 'media-$i',
    messageId: 'msg-1',
    mime: 'image/jpeg',
    size: 1024,
    mediaType: 'image',
    downloadStatus: 'done',
    createdAt: '2024-01-01T00:00:00Z',
  );
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('MediaGrid', () {
    testWidgets('renders single item with 4:3 AspectRatio', (tester) async {
      await tester.pumpWidget(wrap(MediaGrid(media: [_makeMedia(0)])));
      expect(find.byType(AspectRatio), findsOneWidget);
      final ar = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(ar.aspectRatio, closeTo(4 / 3, 0.01));
    });

    testWidgets('renders 2 items side by side', (tester) async {
      await tester.pumpWidget(wrap(MediaGrid(
        media: [_makeMedia(0), _makeMedia(1)],
      )));
      // 2 items each with 1:1 aspect ratio
      final aspects = tester.widgetList<AspectRatio>(find.byType(AspectRatio));
      expect(aspects.length, 2);
    });

    testWidgets('renders ClipRRect container', (tester) async {
      await tester.pumpWidget(wrap(MediaGrid(media: [_makeMedia(0)])));
      expect(find.byType(ClipRRect), findsWidgets);
    });

    testWidgets('renders empty SizedBox when media is empty', (tester) async {
      await tester.pumpWidget(wrap(const MediaGrid(media: [])));
      expect(find.byType(SizedBox), findsWidgets);
    });
  });
}
