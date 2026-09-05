import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('SignalingMessage JSON round-trip', () {
    test('JoinRoom', () {
      const message = JoinRoom('renard-bureau-lampe-zenith');
      final decoded = SignalingMessage.fromJson(
        jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>,
      );
      expect(decoded, isA<JoinRoom>());
      expect((decoded as JoinRoom).code, message.code);
    });

    test('RoomJoined', () {
      const message = RoomJoined('peer-123');
      final decoded = SignalingMessage.fromJson(message.toJson());
      expect(decoded, isA<RoomJoined>());
      expect((decoded as RoomJoined).peerId, 'peer-123');
    });

    test('PeerConnected carries the other peer\'s id', () {
      const message = PeerConnected('peer-b');
      final decoded = SignalingMessage.fromJson(message.toJson());
      expect(decoded, isA<PeerConnected>());
      expect((decoded as PeerConnected).remotePeerId, 'peer-b');
    });

    test('PeerDisconnected has no payload', () {
      expect(
        SignalingMessage.fromJson(const PeerDisconnected().toJson()),
        isA<PeerDisconnected>(),
      );
    });

    test('RoomError preserves the reason', () {
      const message = RoomError(RoomErrorReason.codeAlreadyInUse);
      final decoded = SignalingMessage.fromJson(message.toJson());
      expect((decoded as RoomError).reason, RoomErrorReason.codeAlreadyInUse);
    });

    test('RelayMessage carries an opaque payload string untouched', () {
      const offer = Offer('v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\n');
      final relay = RelayMessage(
        targetPeerId: 'peer-b',
        payload: offer.encode(),
      );
      final decoded = SignalingMessage.fromJson(relay.toJson()) as RelayMessage;
      expect(decoded.targetPeerId, 'peer-b');
      expect(WebRtcPayload.decode(decoded.payload), isA<Offer>());
      expect((WebRtcPayload.decode(decoded.payload) as Offer).sdp, offer.sdp);
    });

    test('unknown type throws FormatException', () {
      expect(
        () => SignalingMessage.fromJson({'type': 'bogus'}),
        throwsFormatException,
      );
    });
  });

  group('WebRtcPayload JSON round-trip', () {
    test('IceCandidate', () {
      const candidate = IceCandidate(
        candidate: 'candidate:1 1 UDP 2122260223 10.0.0.1 5000 typ host',
        sdpMLineIndex: 0,
        sdpMid: '0',
      );
      final decoded = WebRtcPayload.decode(candidate.encode()) as IceCandidate;
      expect(decoded.candidate, candidate.candidate);
      expect(decoded.sdpMLineIndex, 0);
      expect(decoded.sdpMid, '0');
    });

    test('Answer', () {
      const answer = Answer('v=0\r\n');
      final decoded = WebRtcPayload.decode(answer.encode());
      expect(decoded, isA<Answer>());
      expect((decoded as Answer).sdp, 'v=0\r\n');
    });
  });
}
