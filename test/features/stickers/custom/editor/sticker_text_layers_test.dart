import 'package:flutter_app/features/stickers/custom/editor/sticker_text_layers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an eleventh layer is refused once ten exist', () {
    final history = StickerTextHistory();
    for (var i = 0; i < 11; i++) {
      history.apply(AddTextLayer('L$i'));
    }

    expect(history.present.layers.map((l) => l.text).toList(), [
      'L0',
      'L1',
      'L2',
      'L3',
      'L4',
      'L5',
      'L6',
      'L7',
      'L8',
      'L9',
    ]);
    expect(history.present.canAddLayer, isFalse);
  });

  test('position is clamped to the canvas and scale to its bounds', () {
    final history = StickerTextHistory()..apply(const AddTextLayer('Hi'));
    final id = history.present.selectedId!;

    history.apply(
      TransformTextLayer(
        id,
        center: const Offset(1.7, -0.4),
        scale: 9,
        rotation: 1,
      ),
    );
    expect(history.present.selected!.center, const Offset(1, 0));
    expect(history.present.selected!.scale, 4);
    expect(history.present.selected!.rotation, 1);

    history.apply(
      TransformTextLayer(
        id,
        center: const Offset(0.2, 0.3),
        scale: 0.01,
        rotation: 0,
      ),
    );
    expect(history.present.selected!.center, const Offset(0.2, 0.3));
    expect(history.present.selected!.scale, 0.4);
  });

  test('undo walks back at least twenty steps', () {
    final history = StickerTextHistory()..apply(const AddTextLayer('Hi'));
    final id = history.present.selectedId!;
    for (var i = 1; i <= 22; i++) {
      history.apply(
        TransformTextLayer(
          id,
          center: Offset(0.5, i / 100),
          scale: 1,
          rotation: 0,
        ),
      );
    }
    expect(history.present.selected!.center, const Offset(0.5, 0.22));

    for (var i = 0; i < 22; i++) {
      history.undo();
    }

    expect(history.present.selected!.center, const Offset(0.5, 0.5));
    expect(history.present.layers.single.text, 'Hi');
  });

  test('a whole gesture is one undo step', () {
    final history = StickerTextHistory()..apply(const AddTextLayer('Hi'));
    final id = history.present.selectedId!;

    history.beginGesture();
    for (var i = 1; i <= 5; i++) {
      history.updateGesture(
        TransformTextLayer(
          id,
          center: Offset(0.5 + i / 50, 0.5),
          scale: 1,
          rotation: 0,
        ),
      );
    }
    history.endGesture();
    expect(history.present.selected!.center, const Offset(0.6, 0.5));

    history.undo();
    expect(history.present.selected!.center, const Offset(0.5, 0.5));
  });

  test('emptying a layer text removes it', () {
    final history = StickerTextHistory()..apply(const AddTextLayer('Hi'));
    history.apply(EditLayerText(history.present.selectedId!, '  '));

    expect(history.present.layers, isEmpty);
    expect(history.present.selectedId, isNull);
  });

  test('direction follows the first strong character of each layer', () {
    String dir(String text) =>
        StickerTextLayer(id: 1, text: text).direction.name;

    expect(dir('مرحبا بك'), 'rtl');
    expect(dir('١٢ مرحبا'), 'rtl');
    expect(dir('😀 مرحبا Hello'), 'rtl');
    expect(dir('Hello مرحبا'), 'ltr');
    expect(dir('😀 Hi'), 'ltr');
  });

  test('Arabic digits and punctuation before Latin letters stay left to right', () {
    String dir(String text) => StickerTextLayer(id: 1, text: text).direction.name;
    expect(
      [dir('١٢ Hello'), dir('، Hello'), dir('Hello مرحبا')],
      ['ltr', 'ltr', 'ltr'],
    );
    expect([dir('١٢ مرحبا'), dir('😀 مرحبا')], ['rtl', 'rtl']);
  });
}
