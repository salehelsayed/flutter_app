import 'dart:io';

import 'package:image/image.dart' as image;

import '../support/android_picture_in_picture_system_ui_control.dart';
import '../support/android_picture_in_picture_system_ui_selection_result.dart';

void main(List<String> arguments) {
  if (arguments.length != 15 || arguments[13] != '--output') {
    stderr.writeln(
      'Usage: dart run select_android_picture_in_picture_pixel6_api36_geometry.dart '
      '<expand|close> <png-path> <left> <top> <right> <bottom> '
      '<codename> <model> <sdk> <display-width> <display-height> '
      '<display-density> <rotation> --output <json-path>',
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
  final sdk = int.tryParse(arguments[8]);
  final displayWidth = int.tryParse(arguments[9]);
  final displayHeight = int.tryParse(arguments[10]);
  final displayDensity = int.tryParse(arguments[11]);
  final rotation = int.tryParse(arguments[12]);
  if (action == null ||
      coordinates.any((value) => value == null) ||
      sdk == null ||
      displayWidth == null ||
      displayHeight == null ||
      displayDensity == null ||
      rotation == null) {
    stderr.writeln('The action, geometry, or device environment is invalid.');
    exitCode = 2;
    return;
  }

  try {
    final screenshot = image.decodePng(File(arguments[1]).readAsBytesSync());
    if (screenshot == null) {
      stderr.writeln('The post-reveal screenshot is not a decodable PNG.');
      exitCode = 2;
      return;
    }
    final selection = selectPixel6Api36PictureInPictureSystemUiGeometry(
      screenshot: screenshot,
      action: action,
      pictureInPictureBounds: AndroidPictureInPictureBounds(
        left: coordinates[0]!,
        top: coordinates[1]!,
        right: coordinates[2]!,
        bottom: coordinates[3]!,
      ),
      environment: AndroidPictureInPictureGeometryEnvironment(
        deviceCodename: arguments[6],
        deviceModel: arguments[7],
        sdk: sdk,
        displayWidth: displayWidth,
        displayHeight: displayHeight,
        displayDensity: displayDensity,
        rotation: rotation,
      ),
    );
    AndroidPictureInPictureSystemUiSelectionResult(
      selectorSource: 'pixel6-api36-wmshell-geometry',
      resourceId: '',
      contentDescription: 'AOSP ${action.name} control geometry',
      bounds: coordinates.cast<int>(),
      center: <int>[selection.centerX, selection.centerY],
      geometryEvidence: selection.evidence,
    ).writeAtomic(File(arguments[14]));
    stdout.writeln('selectionResult=${arguments[14]}');
  } on AndroidPictureInPictureSystemUiSelectionException catch (error) {
    stderr.writeln(error.message);
    exitCode = 3;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}
