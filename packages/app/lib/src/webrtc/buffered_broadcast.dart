import 'dart:async';

/// A broadcast stream that queues events added before the first listener
/// subscribes, replaying them on listen instead of dropping them the way a
/// plain [StreamController.broadcast] would.
///
/// Only the gap before the very first listener is protected: once a listener
/// has attached at least once, later events follow normal broadcast
/// semantics (dropped if nobody is currently listening).
class BufferedBroadcast<T> {
  final _pending = <T>[];
  bool _listened = false;
  late final _controller = StreamController<T>.broadcast(onListen: _flush);

  Stream<T> get stream => _controller.stream;

  void add(T event) {
    if (_listened) {
      _controller.add(event);
    } else {
      _pending.add(event);
    }
  }

  void _flush() {
    _listened = true;
    _pending.forEach(_controller.add);
    _pending.clear();
  }

  Future<void> close() => _controller.close();
}
