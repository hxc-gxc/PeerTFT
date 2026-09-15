import 'web_save.dart';

/// Non-web builds never call this — see `web_save_web.dart` for the real
/// implementation, selected via conditional import.
Future<WebWritableSink?> pickWebSink(String suggestedName) async => null;
