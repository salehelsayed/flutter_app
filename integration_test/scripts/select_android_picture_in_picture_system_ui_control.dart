import 'dart:io';

import '../support/android_picture_in_picture_system_ui_control.dart';
import '../support/android_picture_in_picture_system_ui_selection_result.dart';

void main(List<String> arguments) {
  if (arguments.length != 8 || arguments[6] != '--output') {
    stderr.writeln(
      'Usage: dart run select_android_picture_in_picture_system_ui_control.dart '
      '<expand|close> <xml-path> <left> <top> <right> <bottom> '
      '--output <json-path>',
    );
    exitCode = 2;
    return;
  }

  final action = switch (arguments[0]) {
    'expand' => AndroidPictureInPictureSystemUiAction.expand,
    'close' => AndroidPictureInPictureSystemUiAction.close,
    _ => null,
  };
  final coordinates = arguments.sublist(2, 6).map(int.tryParse).toList();
  if (action == null || coordinates.any((value) => value == null)) {
    stderr.writeln('The action or live PiP bounds are invalid.');
    exitCode = 2;
    return;
  }

  try {
    final control = selectAndroidPictureInPictureSystemUiControl(
      File(arguments[1]).readAsStringSync(),
      action: action,
      pictureInPictureBounds: AndroidPictureInPictureBounds(
        left: coordinates[0]!,
        top: coordinates[1]!,
        right: coordinates[2]!,
        bottom: coordinates[3]!,
      ),
    );
    AndroidPictureInPictureSystemUiSelectionResult(
      selectorSource: control.selectorSource,
      resourceId: control.resourceId,
      contentDescription: control.contentDescription.replaceAll('\n', ' '),
      bounds: <int>[
        control.bounds.left,
        control.bounds.top,
        control.bounds.right,
        control.bounds.bottom,
      ],
      center: <int>[control.bounds.centerX, control.bounds.centerY],
      geometryEvidence: '',
    ).writeAtomic(File(arguments[7]));
    stdout.writeln('selectionResult=${arguments[7]}');
  } on AndroidPictureInPictureSystemUiSelectionException catch (error) {
    stderr.writeln(error.message);
    exitCode = 3;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}
