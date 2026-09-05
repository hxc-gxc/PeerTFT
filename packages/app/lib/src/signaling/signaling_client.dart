import 'dart:async';
import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Thin client for the signaling server's WebSocket endpoint (`/ws`).
///
/// Owns nothing about WebRTC itself: it only carries [SignalingMessage]s to
/// and from the server. The caller drives room joining and reacts to
/// incoming messages via [messages].
class SignalingClient {
  SignalingClient(this._channel);

  factory SignalingClient.connect(Uri serverUri) =>
      SignalingClient(WebSocketChannel.connect(serverUri));

  final WebSocketChannel _channel;
  late final Stream<SignalingMessage> messages = _channel.stream
      .map((raw) => SignalingMessage.fromJson(jsonDecode(raw as String) as Map<String, dynamic>))
      .asBroadcastStream();

  void joinRoom(String code) => _send(JoinRoom(code));

  void sendRelay({required String targetPeerId, required WebRtcPayload payload}) {
    _send(RelayMessage(targetPeerId: targetPeerId, payload: payload.encode()));
  }

  void _send(SignalingMessage message) {
    _channel.sink.add(jsonEncode(message.toJson()));
  }

  Future<void> close() => _channel.sink.close();
}
