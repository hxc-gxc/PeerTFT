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

sealed class _Slot {}

class _Empty extends _Slot {}

class _Active extends _Slot {
  _Active(this.handle);
  final PeerConnectionHandle handle;
}

class _Pending extends _Slot {
  _Pending(this.peerId, this.timer);
  final String peerId; // the peerId that dropped, used to match a reconnectToken
  final Timer timer;
}

class _Room {
  _Room(this.code) : createdAt = DateTime.now();

  final String code;
  final DateTime createdAt;
  _Slot a = _Empty();
  _Slot b = _Empty();
  Timer? expiryTimer;
  bool everConnected = false;

  bool get isFull => a is _Active && b is _Active;

  PeerConnectionHandle? handleFor(String peerId) {
    final slotA = a;
    if (slotA is _Active && slotA.handle.peerId == peerId) return slotA.handle;
    final slotB = b;
    if (slotB is _Active && slotB.handle.peerId == peerId) return slotB.handle;
    return null;
  }

  PeerConnectionHandle? otherThan(String peerId) {
    final slotA = a;
    if (slotA is _Active && slotA.handle.peerId == peerId) {
      final slotB = b;
      return slotB is _Active ? slotB.handle : null;
    }
    final slotB = b;
    if (slotB is _Active && slotB.handle.peerId == peerId) {
      final slotA2 = a;
      return slotA2 is _Active ? slotA2.handle : null;
    }
    return null;
  }
}

/// Matches pairs of clients that present the same room [code] and relays
/// their WebRTC signaling messages. Entirely in-memory: rooms are created on
/// first join and destroyed as soon as they complete their purpose (both
/// peers gone, or a peer disconnects without ever reconnecting) or expire
/// without ever reaching two members.
///
/// Dart is single-threaded per isolate and this class is only ever driven
/// from request handlers running in one isolate, so no locking is needed
/// around `_rooms`.
class RoomManager {
  RoomManager({this.roomTtl = const Duration(seconds: 60)});

  final Duration roomTtl;
  final Map<String, _Room> _rooms = {};

  static const _graceWindow = Duration(seconds: 30);

  /// Number of currently tracked rooms. Exposed for tests and metrics only.
  int get roomCount => _rooms.length;

  /// Registers [handle] under [code]. If [reconnectToken] matches a slot
  /// that's currently mid-grace-period, restores that slot instead of
  /// treating this as a new peer. Throws [RoomManagerException] if the room
  /// already has two active peers, or if a slot is pending and this join
  /// doesn't carry the matching token (the hijack case).
  void join({
    required String code,
    required PeerConnectionHandle handle,
    String? reconnectToken,
  }) {
    final room = _rooms.putIfAbsent(code, () {
      final created = _Room(code);
      created.expiryTimer = Timer(roomTtl, () => _expire(code));
      return created;
    });

    if (reconnectToken != null &&
        _restorePending(room, reconnectToken, handle)) {
      // restored in place
    } else if (room.a is _Pending || room.b is _Pending) {
      throw RoomManagerException(RoomErrorReason.codeAlreadyInUse);
    } else if (room.a is _Empty) {
      room.a = _Active(handle);
    } else if (room.b is _Empty) {
      room.b = _Active(handle);
    } else {
      throw RoomManagerException(RoomErrorReason.codeAlreadyInUse);
    }

    if (room.isFull) {
      room.expiryTimer?.cancel();
      room.expiryTimer = null;
      room.everConnected = true;
      final activeA = (room.a as _Active).handle;
      final activeB = (room.b as _Active).handle;
      activeA.send(PeerConnected(activeB.peerId));
      activeB.send(PeerConnected(activeA.peerId));
    }
  }

  bool _restorePending(
    _Room room,
    String reconnectToken,
    PeerConnectionHandle handle,
  ) {
    final slotA = room.a;
    if (slotA is _Pending && slotA.peerId == reconnectToken) {
      slotA.timer.cancel();
      room.a = _Active(handle);
      return true;
    }
    final slotB = room.b;
    if (slotB is _Pending && slotB.peerId == reconnectToken) {
      slotB.timer.cancel();
      room.b = _Active(handle);
      return true;
    }
    return false;
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

  /// A peer's transport dropped. If the room never finished pairing, tears
  /// it down immediately (today's behavior, unchanged). Otherwise gives that
  /// slot a 30s grace period to reconnect, notifying the other peer (if
  /// still active) with [PeerReconnecting].
  void disconnect({required String code, required String peerId}) {
    final room = _rooms[code];
    if (room == null) return;

    final slotA = room.a;
    final slotB = room.b;
    final bool isA;
    if (slotA is _Active && slotA.handle.peerId == peerId) {
      isA = true;
    } else if (slotB is _Active && slotB.handle.peerId == peerId) {
      isA = false;
    } else {
      return; // already gone (e.g. a stale/duplicate onDone)
    }

    if (!room.everConnected) {
      room.expiryTimer?.cancel();
      _rooms.remove(code);
      return;
    }

    final timer = Timer(_graceWindow, () => _expirePending(code, peerId));
    final pending = _Pending(peerId, timer);
    final other = room.otherThan(peerId);
    if (isA) {
      room.a = pending;
    } else {
      room.b = pending;
    }
    other?.send(const PeerReconnecting());
    // If the other slot is also _Pending, nobody is listening on either
    // socket right now -- both sides find out independently on their own
    // reconnect (join, above) or when a grace timer expires (below).
  }

  void _expirePending(String code, String peerId) {
    final room = _rooms[code];
    if (room == null) return; // already resolved

    final slotA = room.a;
    final slotB = room.b;
    final bool isA;
    if (slotA is _Pending && slotA.peerId == peerId) {
      isA = true;
    } else if (slotB is _Pending && slotB.peerId == peerId) {
      isA = false;
    } else {
      return; // raced with a successful reconnect that already cancelled this timer
    }

    final other = isA ? slotB : slotA;
    if (other is _Active) {
      other.handle.send(const PeerDisconnected());
    } else if (other is _Pending) {
      other.timer.cancel(); // nothing left to wait for either
    }
    _rooms.remove(code);
  }

  void _expire(String code) {
    final room = _rooms.remove(code);
    if (room == null || room.isFull) return;
    if (room.a case final _Active active) {
      active.handle.send(const RoomError(RoomErrorReason.roomExpired));
    }
  }

  /// Cancels every pending timer (pre-pairing expiry and any grace-window
  /// pending slots). Call on server shutdown so the process can exit instead
  /// of being kept alive by pending [Timer]s.
  void dispose() {
    for (final room in _rooms.values) {
      room.expiryTimer?.cancel();
      if (room.a case final _Pending p) p.timer.cancel();
      if (room.b case final _Pending p) p.timer.cancel();
    }
    _rooms.clear();
  }
}
