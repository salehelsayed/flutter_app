import 'package:flutter/foundation.dart';

import 'package:flutter_app/features/posts/domain/models/post_route_target.dart';

class PendingPostTargetStore extends ChangeNotifier {
  PostRouteTarget? _target;
  String? _statusMessage;

  PostRouteTarget? get target => _target;
  String? get statusMessage => _statusMessage;

  void setTarget(PostRouteTarget target) {
    _target = target;
    _statusMessage = null;
    notifyListeners();
  }

  void showStatus(String? message) {
    _statusMessage = message;
    notifyListeners();
  }

  void clear() {
    if (_target == null && _statusMessage == null) {
      return;
    }
    _target = null;
    _statusMessage = null;
    notifyListeners();
  }
}
