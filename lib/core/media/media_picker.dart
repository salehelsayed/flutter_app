import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Thin abstraction over [ImagePicker] so widget tests can inject results
/// without going through platform channels.
abstract class MediaPicker {
  Future<List<XFile>> pickMultipleMedia();
  Future<XFile?> pickImage({required ImageSource source});
  Future<XFile?> pickVideo({required ImageSource source});

  /// 414: PDF documents from the system document picker. Empty when the user
  /// cancels. Callers still check the bytes (documentFileRejection).
  Future<List<XFile>> pickDocuments();
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

  @override
  Future<List<XFile>> pickDocuments() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: true,
    );
    if (result == null) return const [];
    return [
      for (final file in result.files)
        if (file.path != null) XFile(file.path!, name: file.name),
    ];
  }
}
