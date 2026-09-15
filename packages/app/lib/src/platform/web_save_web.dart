import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'web_save.dart';

@JS('window.showSaveFilePicker')
external JSPromise<JSObject> _showSaveFilePicker(JSObject options);

extension type _SaveFilePickerOptions._(JSObject _) implements JSObject {
  external factory _SaveFilePickerOptions({String suggestedName});
}

extension type _FileSystemFileHandle._(JSObject _) implements JSObject {
  external JSPromise<JSObject> createWritable();
}

extension type _FileSystemWritableFileStream._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSAny data);
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> abort();
}

bool get _isWebSaveSupported => globalContext.has('showSaveFilePicker');

class _JsWebWritableSink implements WebWritableSink {
  _JsWebWritableSink(this._stream);
  final _FileSystemWritableFileStream _stream;

  @override
  Future<void> write(Uint8List chunk) => _stream.write(chunk.toJS).toDart;
  @override
  Future<void> close() => _stream.close().toDart;
  @override
  Future<void> abort() => _stream.abort().toDart;
}

/// Must be called synchronously within a user-gesture handler (a button's
/// onPressed), before any other await — see the design spec §2 for why:
/// `showSaveFilePicker()` requires transient user activation, and the
/// activation window (~1-2s in practice) can be consumed by intervening
/// async work regardless of elapsed time.
///
/// Returns null if the API isn't supported, the user cancels the picker, or
/// the browser rejects the call for having lost transient activation.
/// Callers fall back to the existing in-memory path on null, exactly as if
/// this feature didn't exist.
Future<WebWritableSink?> pickWebSink(String suggestedName) async {
  if (!_isWebSaveSupported) return null;
  try {
    final handleObj = await _showSaveFilePicker(
      _SaveFilePickerOptions(suggestedName: suggestedName),
    ).toDart;
    final handle = handleObj as _FileSystemFileHandle;
    final streamObj = await handle.createWritable().toDart;
    return _JsWebWritableSink(streamObj as _FileSystemWritableFileStream);
  } catch (_) {
    return null;
  }
}
