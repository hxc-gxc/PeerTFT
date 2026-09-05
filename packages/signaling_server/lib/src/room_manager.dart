import 'dart:async';

import 'package:shared/shared.dart';

/// A connected peer, abstracted away from the transport (a real WebSocket in
/// production, a fake in tests) so [RoomManager] stays transport-agnostic.
abstract interface class PeerConnectionHandle {
  String get peerId;
  void send(SignalingMessage message);
}

/// Thrown when a join is rejected; [reason] is what the caller should relay
/// back to the client as a [RoomError].
class RoomManagerException implements Exception {
  RoomManagerException(this.reason);
  final RoomErrorReason reason;
}

class _Room {
  _Room(this.code) : createdAt = DateTime.now();

  final String code;
  final DateTime createdAt;
  PeerConnectionHandle? peerA;
  PeerConnectionHandle? peerB;
  Timer? expiryTimer;

  bool get isFull => peerA != null && peerB != null;

  PeerConnectionHandle? handleFor(String peerId) {
    if (peerA?.peerId == peerId) return peerA;
    if (peerB?.peerId == peerId) return peerB;
    return null;
  }

  PeerConnectionHandle? otherThan(String peerId) {
    if (peerA?.peerId == peerId) return peerB;
    if (peerB?.peerId == peerId) return peerA;
    return null;
  }
}

/// Matches pairs of clients that present the same room [code] and relays
/// their WebRTC signaling messages. Entirely in-memory: rooms are created on
/// first join and destroyed as soon as they complete their purpose (a peer
/// disconnects) or expire without ever reaching two members.
///
/// Dart is single-threaded per isolate and this class is only ever driven
/// from request handlers running in one isolate, so no locking is needed
/// around `_rooms`.
class RoomManager {
  RoomManager({this.roomTtl = const Duration(seconds: 60)});

  final Duration roomTtl;
  final Map<String, _Room> _rooms = {};

  /// Number of currently tracked rooms. Exposed for tests and metrics only.
  int get roomCount => _rooms.length;

  /// Registers [handle] under [code], creating the room if this is the first
  /// client to use it. Throws [RoomManagerException] if the room already has
  /// two peers. When the room becomes full, both peers are sent
  /// [PeerConnected].
  void join({required String code, required PeerConnectionHandle handle}) {
    final room = _rooms.putIfAbsent(code, () {
      final created = _Room(code);
      created.expiryTimer = Timer(roomTtl, () => _expire(code));
      return created;
    });

    if (room.peerA == null) {
      room.peerA = handle;
    } else if (room.peerB == null) {
      room.peerB = handle;
    } else {
      throw RoomManagerException(RoomErrorReason.codeAlreadyInUse);
    }

    if (room.isFull) {
      room.expiryTimer?.cancel();
      room.expiryTimer = null;
      room.peerA!.send(PeerConnected(room.peerB!.peerId));
      room.peerB!.send(PeerConnected(room.peerA!.peerId));
    }
  }

  /// Forwards [message] to the other peer in [code]'s room, provided
  /// [message.targetPeerId] actually matches that peer -- a cheap sanity
  /// check against a confused or malicious client, since the server never
  /// otherwise inspects the payload.
  void relay({
    required String code,
    required String fromPeerId,
    required RelayMessage message,
  }) {
    final room = _rooms[code];
    if (room == null) return;
    if (room.handleFor(fromPeerId) == null) return;
    final target = room.otherThan(fromPeerId);
    if (target == null || target.peerId != message.targetPeerId) return;
    target.send(message);
  }

  /// Tears down [code]'s room because [peerId] disconnected, notifying the
  /// remaining peer (if any) with [PeerDisconnected].
  void disconnect({required String code, required String peerId}) {
    final room = _rooms.remove(code);
    if (room == null) return;
    room.expiryTimer?.cancel();
    final other = room.otherThan(peerId);
    other?.send(const PeerDisconnected());
  }

  void _expire(String code) {
    final room = _rooms.remove(code);
    if (room == null || room.isFull) return;
    room.peerA?.send(const RoomError(RoomErrorReason.roomExpired));
  }

  /// Cancels every pending expiry timer. Call on server shutdown so the
  /// process can exit instead of being kept alive by pending [Timer]s.
  void dispose() {
    for (final room in _rooms.values) {
      room.expiryTimer?.cancel();
    }
    _rooms.clear();
  }
}
