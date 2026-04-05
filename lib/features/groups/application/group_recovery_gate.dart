class GroupRecoveryGate {
  int _activeDepth = 0;

  bool get isActive => _activeDepth > 0;

  void begin() {
    _activeDepth += 1;
  }

  void end() {
    if (_activeDepth == 0) {
      return;
    }
    _activeDepth -= 1;
  }

  Future<T> run<T>(Future<T> Function() action) async {
    begin();
    try {
      return await action();
    } finally {
      end();
    }
  }

  void resetForTest() {
    _activeDepth = 0;
  }
}

final groupRecoveryGate = GroupRecoveryGate();

const groupRecoveryPendingError =
    'Group recovery is in progress. Try again after resync completes.';

bool isGroupRecoveryInProgress() => groupRecoveryGate.isActive;

Future<T> runWithGroupRecoveryGate<T>(Future<T> Function() action) {
  return groupRecoveryGate.run(action);
}
