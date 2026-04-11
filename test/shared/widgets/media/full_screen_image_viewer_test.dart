import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('uses the video page builder for video paths', (tester) async {
    const videoPath = '/tmp/sample.mp4';

    await tester.pumpWidget(
      wrap(
        FullScreenImageViewer(
          localPath: videoPath,
          videoPageBuilder: (path, isActive) => Container(
            key: ValueKey('video-page-$path'),
            child: Text(isActive ? 'active-video' : 'inactive-video'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('video-page-/tmp/sample.mp4')),
      findsOneWidget,
    );
    expect(find.text('active-video'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('uses the image viewer branch for image paths', (tester) async {
    const imagePath = '/tmp/sample.jpg';

    await tester.pumpWidget(
      wrap(const FullScreenImageViewer(localPath: imagePath)),
    );
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('renders GIF paths without ResizeImage cache hints', (tester) async {
    const gifPath = '/tmp/sample.gif';

    await tester.pumpWidget(
      wrap(const FullScreenImageViewer(localPath: gifPath)),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isNot(isA<ResizeImage>()));
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('swipes between GIF and JPEG pages', (tester) async {
    const gifPath = '/tmp/sample.gif';
    const jpgPath = '/tmp/sample.jpg';

    await tester.pumpWidget(
      wrap(
        const FullScreenImageViewer(
          localPath: gifPath,
          allPaths: [gifPath, jpgPath],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1 / 2'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
  });
}
