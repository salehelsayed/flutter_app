import 'dart:async';

final StreamController<void> _linkedGroupStatusRefreshController =
    StreamController<void>.broadcast(sync: true);

Stream<void> get linkedGroupStatusRefreshes =>
    _linkedGroupStatusRefreshController.stream;

Future<void> refreshLinkedGroupStatusProjection() async {
  if (!_linkedGroupStatusRefreshController.isClosed) {
    _linkedGroupStatusRefreshController.add(null);
  }
}
