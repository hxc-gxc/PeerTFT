import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'peer_id.dart';
import 'rate_limiter.dart';
import 'room_manager.dart';

const _codeValidator = CodeGenerator();

/// Drives a single client's WebSocket connection: validates and rate-limits
/// its `JoinRoom`, registers it with [roomManager], and relays subsequent
/// `RelayMessage`s. One instance is created per connection.
class ConnectionHandler {
  ConnectionHandler({
    required this.channel,
    required this.roomManager,
    required this.rateLimiter,
    required this.clientKey,
  });

  final WebSocketChannel channel;
  final RoomManager roomManager;
  final RateLimiter rateLimiter;

  /// Rate-limiter bucket key, typically the client's IP address.
  final String clientKey;

  String? _code;
  late final String _peerId = generatePeerId();
  bool _joined = false;

  void listen() {
    channel.stream.listen(
      _onData,
      onDone: _onDone,
      onError: (_) => _onDone(),
      cancelOnError: true,
    );
  }

  void _onData(dynamic raw) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw as String) as Map<String, dynamic>;
    } on FormatException {
      return; // Malformed frame: drop silently, do not crash the connection.
    }

    final SignalingMessage message;
    try {
      message = SignalingMessage.fromJson(json);
    } on FormatException {
      return;
    }

    switch (message) {
      case JoinRoom():
        _handleJoinRoom(message);
      case RelayMessage():
        _handleRelay(message);
      case RoomJoined() || PeerConnected() || PeerDisconnected() || RoomError():
        // Server-to-client-only messages; a client sending one is ignored.
        break;
    }
  }

  void _handleJoinRoom(JoinRoom message) {
    if (_joined) return; // One JoinRoom per connection.

    if (!rateLimiter.allow(clientKey)) {
      _send(const RoomError(RoomErrorReason.rateLimited));
      channel.sink.close();
      return;
    }

    if (!_codeValidator.isWellFormed(message.code)) {
      _send(const RoomError(RoomErrorReason.invalidCode));
      channel.sink.close();
      return;
    }

    try {
      roomManager.join(code: message.code, handle: _handle);
    } on RoomManagerException catch (e) {
      _send(RoomError(e.reason));
      channel.sink.close();
      return;
    }

    _code = message.code;
    _joined = true;
    _send(RoomJoined(_peerId));
  }

  void _handleRelay(RelayMessage message) {
    final code = _code;
    if (code == null) return; // Not joined yet: ignore.
    roomManager.relay(code: code, fromPeerId: _peerId, message: message);
  }

  void _onDone() {
    final code = _code;
    if (code != null) {
      roomManager.disconnect(code: code, peerId: _peerId);
    }
  }

  void _send(SignalingMessage message) {
    channel.sink.add(jsonEncode(message.toJson()));
  }

  late final PeerConnectionHandle _handle = _Handle(_peerId, _send);
}

class _Handle implements PeerConnectionHandle {
  _Handle(this.peerId, this._send);

  @override
  final String peerId;

  final void Function(SignalingMessage) _send;

  @override
  void send(SignalingMessage message) => _send(message);
}
