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

    test(
      'disconnect on a paired room starts the grace period, not an immediate teardown',
      () {
        fakeAsync((async) {
          final manager = RoomManager();
          final a = _FakeHandle('a');
          final b = _FakeHandle('b');
          manager.join(code: 'code', handle: a);
          manager.join(code: 'code', handle: b);

          manager.disconnect(code: 'code', peerId: 'a');
          expect(b.received.last, isA<PeerReconnecting>());
          expect(manager.roomCount, 1); // still tracked during the grace window

          // a's slot is pending, not active: a stray relay targeting it is a
          // no-op, not a crash.
          manager.relay(
            code: 'code',
            fromPeerId: 'b',
            message: const RelayMessage(targetPeerId: 'a', payload: 'x'),
          );

          // Drain the pending grace-period timer so it doesn't leak past the
          // test (it fires a no-op _expirePending on an already-verified room).
          async.elapse(const Duration(seconds: 31));
        });
      },
    );

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

  group('RoomManager reconnect grace window', () {
    test(
      'reconnect within the grace window with a matching token restores the slot',
      () {
        fakeAsync((async) {
          final manager = RoomManager();
          final a = _FakeHandle('a');
          final b = _FakeHandle('b');
          manager.join(code: 'code', handle: a);
          manager.join(code: 'code', handle: b); // room now full (everConnected)

          manager.disconnect(code: 'code', peerId: 'a');
          expect(b.received.last, isA<PeerReconnecting>());

          async.elapse(const Duration(seconds: 10)); // well inside the 30s window

          final aAgain = _FakeHandle('a2');
          manager.join(code: 'code', handle: aAgain, reconnectToken: 'a');

          expect(b.received.last, isA<PeerConnected>());
          expect((b.received.last as PeerConnected).remotePeerId, 'a2');
          expect(aAgain.received.last, isA<PeerConnected>());
          expect((aAgain.received.last as PeerConnected).remotePeerId, 'b');
        });
      },
    );

    test(
      'a join with a non-matching token while a slot is pending is rejected (hijack case)',
      () {
        fakeAsync((async) {
          final manager = RoomManager();
          final a = _FakeHandle('a');
          final b = _FakeHandle('b');
          manager.join(code: 'code', handle: a);
          manager.join(code: 'code', handle: b);
          manager.disconnect(code: 'code', peerId: 'a'); // a's slot -> _Pending

          expect(
            () => manager.join(code: 'code', handle: _FakeHandle('stranger')),
            throwsA(
              isA<RoomManagerException>().having(
                (e) => e.reason,
                'reason',
                RoomErrorReason.codeAlreadyInUse,
              ),
            ),
          );
          // Same rejection for a wrong/stale token, not just a missing one.
          expect(
            () => manager.join(
              code: 'code',
              handle: _FakeHandle('stranger2'),
              reconnectToken: 'not-a',
            ),
            throwsA(isA<RoomManagerException>()),
          );
        });
      },
    );

    test(
      'grace window expires with no reconnect: surviving peer gets PeerDisconnected, room removed',
      () {
        fakeAsync((async) {
          final manager = RoomManager();
          final a = _FakeHandle('a');
          final b = _FakeHandle('b');
          manager.join(code: 'code', handle: a);
          manager.join(code: 'code', handle: b);
          manager.disconnect(code: 'code', peerId: 'a');

          async.elapse(const Duration(seconds: 31));

          expect(b.received.last, isA<PeerDisconnected>());
          expect(manager.roomCount, 0);
        });
      },
    );

    test(
      'both peers disconnect within the window: each can independently reconnect, pairing fires once both are back',
      () {
        fakeAsync((async) {
          final manager = RoomManager();
          final a = _FakeHandle('a');
          final b = _FakeHandle('b');
          manager.join(code: 'code', handle: a);
          manager.join(code: 'code', handle: b);

          manager.disconnect(code: 'code', peerId: 'a');
          // b is still active when a drops, so it hears about it.
          expect(b.received.last, isA<PeerReconnecting>());
          manager.disconnect(code: 'code', peerId: 'b');
          // a's slot was already pending when b dropped: nobody left to tell.
          expect(a.received, [isA<PeerConnected>()]); // just the original pairing

          async.elapse(const Duration(seconds: 5));
          final bAgain = _FakeHandle('b2');
          manager.join(code: 'code', handle: bAgain, reconnectToken: 'b');
          // a's slot is still _Pending: no PeerConnected yet.
          expect(bAgain.received, isEmpty);

          final aAgain = _FakeHandle('a2');
          manager.join(code: 'code', handle: aAgain, reconnectToken: 'a');
          expect(aAgain.received.last, isA<PeerConnected>());
          expect(bAgain.received.last, isA<PeerConnected>());
        });
      },
    );

    test(
      'disconnect on a room that never finished pairing tears down immediately (no grace period)',
      () {
        final manager = RoomManager();
        final a = _FakeHandle('a');
        manager.join(code: 'code', handle: a); // room never fills -> everConnected stays false

        manager.disconnect(code: 'code', peerId: 'a');
        expect(manager.roomCount, 0); // gone immediately, not _Pending
      },
    );
  });
}
