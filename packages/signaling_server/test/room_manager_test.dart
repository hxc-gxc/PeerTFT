import 'package:fake_async/fake_async.dart';
import 'package:shared/shared.dart';
import 'package:signaling_server/src/room_manager.dart';
import 'package:test/test.dart';

class _FakeHandle implements PeerConnectionHandle {
  _FakeHandle(this.peerId);

  @override
  final String peerId;

  final List<SignalingMessage> received = [];

  @override
  void send(SignalingMessage message) => received.add(message);
}

void main() {
  group('RoomManager', () {
    test('first join creates the room and does not notify anyone yet', () {
      final manager = RoomManager();
      final a = _FakeHandle('a');
      manager.join(code: 'renard-lampe', handle: a);
      expect(manager.roomCount, 1);
      expect(a.received, isEmpty);
    });

    test('second join with the same code notifies both peers', () {
      final manager = RoomManager();
      final a = _FakeHandle('a');
      final b = _FakeHandle('b');
      manager.join(code: 'renard-lampe', handle: a);
      manager.join(code: 'renard-lampe', handle: b);

      expect(a.received, [isA<PeerConnected>()]);
      expect(b.received, [isA<PeerConnected>()]);
      expect((a.received.single as PeerConnected).remotePeerId, 'b');
      expect((b.received.single as PeerConnected).remotePeerId, 'a');
    });

    test('a third join on the same code is rejected', () {
      final manager = RoomManager();
      manager.join(code: 'renard-lampe', handle: _FakeHandle('a'));
      manager.join(code: 'renard-lampe', handle: _FakeHandle('b'));

      expect(
        () => manager.join(code: 'renard-lampe', handle: _FakeHandle('c')),
        throwsA(
          isA<RoomManagerException>().having(
            (e) => e.reason,
            'reason',
            RoomErrorReason.codeAlreadyInUse,
          ),
        ),
      );
    });

    test(
      'relay forwards only to the other peer, and only with a matching target',
      () {
        final manager = RoomManager();
        final a = _FakeHandle('a');
        final b = _FakeHandle('b');
        manager.join(code: 'code', handle: a);
        manager.join(code: 'code', handle: b);

        expect(a.received, [
          isA<PeerConnected>(),
        ]); // joined notification, no relay yet

        manager.relay(
          code: 'code',
          fromPeerId: 'a',
          message: const RelayMessage(targetPeerId: 'b', payload: 'offer-json'),
        );
        expect(b.received.last, isA<RelayMessage>());
        expect((b.received.last as RelayMessage).payload, 'offer-json');
        expect(a.received, hasLength(1)); // still just PeerConnected, no echo

        // Wrong target id: dropped rather than misdelivered.
        manager.relay(
          code: 'code',
          fromPeerId: 'a',
          message: const RelayMessage(targetPeerId: 'not-b', payload: 'x'),
        );
        expect(b.received, hasLength(2));
      },
    );

    test('disconnect tears down the room and notifies the remaining peer', () {
      final manager = RoomManager();
      final a = _FakeHandle('a');
      final b = _FakeHandle('b');
      manager.join(code: 'code', handle: a);
      manager.join(code: 'code', handle: b);

      manager.disconnect(code: 'code', peerId: 'a');
      expect(b.received.last, isA<PeerDisconnected>());
      expect(manager.roomCount, 0);

      // Room is gone: a stray relay after disconnect is a no-op, not a crash.
      manager.relay(
        code: 'code',
        fromPeerId: 'b',
        message: const RelayMessage(targetPeerId: 'a', payload: 'x'),
      );
    });

    test('a room that never fills expires and notifies the lone peer', () {
      fakeAsync((async) {
        final manager = RoomManager(roomTtl: const Duration(seconds: 1));
        final a = _FakeHandle('a');
        manager.join(code: 'code', handle: a);

        async.elapse(const Duration(seconds: 2));

        expect(a.received.last, isA<RoomError>());
        expect(
          (a.received.last as RoomError).reason,
          RoomErrorReason.roomExpired,
        );
        expect(manager.roomCount, 0);
      });
    });
  });
}
