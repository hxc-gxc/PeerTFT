import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:signaling_server/src/rate_limiter.dart';
import 'package:signaling_server/src/room_manager.dart';
import 'package:signaling_server/src/ws_handler.dart';

/// Anonymous ICE-outcome events accepted by `POST /metrics` (see the
/// architecture doc, section 10). No IP, room code or file identifier is
/// ever accepted here -- only these four aggregate fields.
const _allowedOutcomes = {'directSuccess', 'iceFailed', 'timeout', 'userCancelled'};

Future<void> main(List<String> args) async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final roomManager = RoomManager();
  final rateLimiter = RateLimiter();

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router(roomManager: roomManager, rateLimiter: rateLimiter));

  final sweepTimer = Timer.periodic(const Duration(minutes: 1), (_) => rateLimiter.sweep());

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  // ignore: avoid_print
  print('signaling_server listening on ${server.address.host}:${server.port}');

  ProcessSignal.sigterm.watch().listen((_) => _shutdown(server, roomManager, sweepTimer));
  ProcessSignal.sigint.watch().listen((_) => _shutdown(server, roomManager, sweepTimer));
}

Future<void> _shutdown(HttpServer server, RoomManager roomManager, Timer sweepTimer) async {
  sweepTimer.cancel();
  roomManager.dispose();
  await server.close(force: true);
  exit(0);
}

Handler _router({required RoomManager roomManager, required RateLimiter rateLimiter}) {
  return (Request request) {
    if (request.url.path == 'healthz') {
      return Response.ok('ok');
    }

    if (request.url.path == 'metrics' && request.method == 'POST') {
      return _handleMetrics(request);
    }

    if (request.url.path == 'ws') {
      final clientKey = _clientKey(request);
      return webSocketHandler((WebSocketChannel channel, String? protocol) {
        ConnectionHandler(
          channel: channel,
          roomManager: roomManager,
          rateLimiter: rateLimiter,
          clientKey: clientKey,
        ).listen();
      })(request);
    }

    return Response.notFound('not found');
  };
}

String _clientKey(Request request) {
  final forwardedFor = request.headers['x-forwarded-for'];
  if (forwardedFor != null && forwardedFor.isNotEmpty) {
    return forwardedFor.split(',').first.trim();
  }
  final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
  return connectionInfo?.remoteAddress.address ?? 'unknown';
}

Future<Response> _handleMetrics(Request request) async {
  final body = await request.readAsString();
  Map<String, dynamic> json;
  try {
    json = jsonDecode(body) as Map<String, dynamic>;
  } on FormatException {
    return Response.badRequest(body: 'invalid json');
  }

  final outcome = json['outcome'];
  if (outcome is! String || !_allowedOutcomes.contains(outcome)) {
    return Response.badRequest(body: 'invalid outcome');
  }
  final networkType = json['networkType'];
  final candidateTypeUsed = json['candidateTypeUsed'];

  // Fire-and-forget structured log line; no per-user identifier is logged.
  // ignore: avoid_print
  print(jsonEncode({
    'event': 'ice_outcome',
    'outcome': outcome,
    'networkType': networkType is String ? networkType : null,
    'candidateTypeUsed': candidateTypeUsed is String ? candidateTypeUsed : null,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  }));

  return Response(204);
}
