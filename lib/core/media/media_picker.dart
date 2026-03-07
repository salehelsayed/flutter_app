import 'package:image_picker/image_picker.dart';

/// Thin abstraction over [ImagePicker] so widget tests can inject results
/// without going through platform channels.
abstract class MediaPicker {
  Future<List<XFile>> pickMultipleMedia();
  Future<XFile?> pickImage({required ImageSource source});
  Future<XFile?> pickVideo({required ImageSource source});
}

class SystemMediaPicker implements MediaPicker {
  final ImagePicker _picker;

  SystemMediaPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  @override
  Future<List<XFile>> pickMultipleMedia() => _picker.pickMultipleMedia();

  @override
  Future<XFile?> pickImage({required ImageSource source}) =>
      _picker.pickImage(source: source);

  @override
  Future<XFile?> pickVideo({required ImageSource source}) =>
      _picker.pickVideo(source: source);
}
