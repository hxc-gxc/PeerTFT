import 'dart:typed_data';

/// A destination a receive can stream binary chunks to, backed by the
/// browser's File System Access API on platforms that support it. Never
/// constructed directly — obtain one via `pickWebSink` (see
/// `web_save_stub.dart`/`web_save_web.dart`), or substitute a test double
/// that implements this interface directly.
abstract interface class WebWritableSink {
  Future<void> write(Uint8List chunk);
  Future<void> close();
  Future<void> abort();
}
