/// Fixed-size circular buffer for normalized amplitude values.
///
/// Used to feed the [AmplitudeBars] widget with a sliding window
/// of recent amplitude samples.
class AmplitudeBuffer {
  final int size;
  late final List<double> _data;
  int _writeIndex = 0;
  bool _full = false;

  AmplitudeBuffer({required this.size}) : _data = List.filled(size, 0.0);

  void push(double value) {
    _data[_writeIndex] = value.clamp(0.0, 1.0);
    _writeIndex++;
    if (_writeIndex >= size) {
      _writeIndex = 0;
      _full = true;
    }
  }

  /// Returns a copy of the buffer in chronological order (oldest first).
  List<double> get values {
    if (!_full) {
      // Right-align: zeros first, then written values
      return [
        ...List.filled(size - _writeIndex, 0.0),
        ..._data.sublist(0, _writeIndex),
      ];
    }
    return [
      ..._data.sublist(_writeIndex),
      ..._data.sublist(0, _writeIndex),
    ];
  }

  void reset() {
    _data.fillRange(0, size, 0.0);
    _writeIndex = 0;
    _full = false;
  }
}
