import 'package:flutter_app/core/media/media_picker.dart';
import 'package:image_picker/image_picker.dart';

class FakeMediaPicker implements MediaPicker {
  List<XFile> multipleMediaResult = const [];
  XFile? imageResult;
  XFile? videoResult;

  int pickMultipleMediaCalls = 0;
  int pickImageCalls = 0;
  int pickVideoCalls = 0;

  @override
  Future<List<XFile>> pickMultipleMedia() async {
    pickMultipleMediaCalls++;
    return multipleMediaResult;
  }

  @override
  Future<XFile?> pickImage({required ImageSource source}) async {
    pickImageCalls++;
    return imageResult;
  }

  @override
  Future<XFile?> pickVideo({required ImageSource source}) async {
    pickVideoCalls++;
    return videoResult;
  }
}
