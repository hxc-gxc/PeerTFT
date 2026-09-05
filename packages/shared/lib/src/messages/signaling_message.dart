import 'room_error_reason.dart';

/// Envelope for every message exchanged between a client and the signaling
/// server over the WebSocket connection.
///
/// The server only ever needs to understand [JoinRoom], [RoomJoined],
/// [PeerConnected], [PeerDisconnected], [RoomError] and the outer shape of
/// [RelayMessage]. It never parses [RelayMessage.payload]: that string is an
/// opaque, client-encoded [Offer]/[Answer]/[IceCandidate].
sealed class SignalingMessage {
  const SignalingMessage();

  Map<String, dynamic> toJson();

  static SignalingMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) {
      throw FormatException('Missing "type" field in signaling message: $json');
    }
    return switch (type) {
      'joinRoom' => JoinRoom.fromJson(json),
      'roomJoined' => RoomJoined.fromJson(json),
      'peerConnected' => PeerConnected.fromJson(json),
      'peerDisconnected' => const PeerDisconnected(),
      'roomError' => RoomError.fromJson(json),
      'relay' => RelayMessage.fromJson(json),
      _ => throw FormatException('Unknown signaling message type: $type'),
    };
  }
}

/// Sent by a client to create or join a room identified by a human-readable
/// [code] (see `codes/code_generator.dart`).
final class JoinRoom extends SignalingMessage {
  const JoinRoom(this.code);

  final String code;

  factory JoinRoom.fromJson(Map<String, dynamic> json) =>
      JoinRoom(json['code'] as String);

  @override
  Map<String, dynamic> toJson() => {'type': 'joinRoom', 'code': code};
}

/// Server response confirming a [JoinRoom]; [peerId] is a random, ephemeral
/// identifier scoped to the room, never a persistent account identity.
final class RoomJoined extends SignalingMessage {
  const RoomJoined(this.peerId);

  final String peerId;

  factory RoomJoined.fromJson(Map<String, dynamic> json) =>
      RoomJoined(json['peerId'] as String);

  @override
  Map<String, dynamic> toJson() => {'type': 'roomJoined', 'peerId': peerId};
}

/// Sent to both peers once a room has exactly two members: the initiator
/// should now create the WebRTC offer. [remotePeerId] is the *other* peer's
/// id -- each side needs it to address its `RelayMessage`s.
final class PeerConnected extends SignalingMessage {
  const PeerConnected(this.remotePeerId);

  final String remotePeerId;

  factory PeerConnected.fromJson(Map<String, dynamic> json) =>
      PeerConnected(json['remotePeerId'] as String);

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'peerConnected', 'remotePeerId': remotePeerId};
}

/// Sent when the other peer's WebSocket closes before the handshake ends.
final class PeerDisconnected extends SignalingMessage {
  const PeerDisconnected();

  @override
  Map<String, dynamic> toJson() => {'type': 'peerDisconnected'};
}

/// Terminal error for the current room/connection attempt.
final class RoomError extends SignalingMessage {
  const RoomError(this.reason);

  final RoomErrorReason reason;

  factory RoomError.fromJson(Map<String, dynamic> json) =>
      RoomError(RoomErrorReason.fromWire(json['reason'] as String));

  @override
  Map<String, dynamic> toJson() => {'type': 'roomError', 'reason': reason.name};
}

/// Opaque relay envelope. The server reads [targetPeerId] to know where to
/// forward the message and otherwise treats [payload] as a black box; it is
/// the JSON encoding of an [Offer], [Answer] or [IceCandidate] produced by
/// the sending client.
final class RelayMessage extends SignalingMessage {
  const RelayMessage({required this.targetPeerId, required this.payload});

  final String targetPeerId;
  final String payload;

  factory RelayMessage.fromJson(Map<String, dynamic> json) => RelayMessage(
        targetPeerId: json['targetPeerId'] as String,
        payload: json['payload'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'relay',
        'targetPeerId': targetPeerId,
        'payload': payload,
      };
}
