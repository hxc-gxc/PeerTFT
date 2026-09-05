import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/src/transfer/transfer.dart';

/// Minimal in-memory RTCDataChannel: send() pipes messages to an output
/// StreamController that the other side reads from. bufferedAmount is always 0
/// so backpressure is never triggered in tests.
class _FakeChannel extends RTCDataChannel {
  _FakeChannel(this._out);

  final StreamController<RTCDataChannelMessage> _out;

  @override
  int? get bufferedAmount => 0;

  @override
  Future<void> send(RTCDataChannelMessage message) async => _out.add(message);

  @override
  Future<void> close() async {}

  // Unused by FileSender / FileReceiver (they use the injected _messages stream):
  @override
  RTCDataChannelState? get state => RTCDataChannelState.RTCDataChannelOpen;
  @override
  int? get id => null;
  @override
  String? get label => null;
  @override
  late Stream<RTCDataChannelState> stateChangeStream;
  @override
  late Stream<RTCDataChannelMessage> messageStream;
}

/// Connect sender and receiver through in-memory broadcast channels.
///
/// IMPORTANT: always call `receiver.receive()` BEFORE `sender.send*(…)`.
/// The broadcast stream does not buffer — if sender fires file-meta before
/// receiver subscribes (via _waitForMeta → .first), the message is dropped
/// and both sides deadlock.
({FileSender sender, FileReceiver receiver}) _makePipe({
  Future<String?> Function(String)? savePathProvider,
}) {
  final s2r = StreamController<RTCDataChannelMessage>.broadcast();
  final r2s = StreamController<RTCDataChannelMessage>.broadcast();

  final sender = FileSender(_FakeChannel(s2r), r2s.stream);
  final receiver = FileReceiver(
    _FakeChannel(r2s),
    s2r.stream,
    savePathProvider, // null = web mode (buffer in memory)
  );

  return (sender: sender, receiver: receiver);
}

void main() {
  group('FileSender / FileReceiver protocol', () {
    test('sendBytes round-trip: bytes and hash match', () async {
      final (:sender, :receiver) = _makePipe();
      final bytes = Uint8List.fromList(List.generate(300, (i) => i % 256));

      // Receiver subscribes first (broadcast stream drops events without listeners).
      final receiverFuture = receiver.receive();
      final (sendResult, receiveResult) = await (
        sender.sendBytes('hello.bin', bytes),
        receiverFuture,
      ).wait;

      expect(receiveResult, isNotNull);
      expect(receiveResult!.hashMatch, isTrue);
      expect(receiveResult.fileName, 'hello.bin');
      expect(receiveResult.bytes, bytes);
      expect(sendResult.sha256Hex, receiveResult.sha256Sent);
      expect(sendResult.sha256Hex, receiveResult.sha256Received);
    });

    test('multi-chunk transfer (> 16 KB) preserves all bytes', () async {
      final (:sender, :receiver) = _makePipe();

      // 3 chunks worth of data (chunk size is 16 KB).
      final bytes = Uint8List.fromList(
        List.generate(50 * 1024, (i) => (i * 7 + 13) % 256),
      );

      final receiverFuture = receiver.receive();
      final (_, receiveResult) = await (
        sender.sendBytes('big.bin', bytes),
        receiverFuture,
      ).wait;

      expect(receiveResult!.hashMatch, isTrue);
      expect(receiveResult.bytes!.length, bytes.length);
      // Spot-check across chunk boundaries.
      expect(receiveResult.bytes![0], bytes[0]);
      expect(receiveResult.bytes![16 * 1024], bytes[16 * 1024]);
      expect(receiveResult.bytes![50 * 1024 - 1], bytes[50 * 1024 - 1]);
    });

    test('receiver returns null when save-path dialog is cancelled', () async {
      final (:sender, :receiver) = _makePipe(
        savePathProvider: (_) async =>
            null, // simulates user dismissing the picker
      );
      final bytes = Uint8List.fromList([1, 2, 3]);

      final receiverFuture = receiver.receive();
      // Sender throws because receiver sends file-reject; check separately to
      // avoid ParallelWaitError wrapping.
      await expectLater(
        sender.sendBytes('f.bin', bytes),
        throwsA(isA<Exception>()),
      );
      expect(await receiverFuture, isNull);
    });

    test('empty file transfer completes with matching hash', () async {
      final (:sender, :receiver) = _makePipe();
      final bytes = Uint8List(0);

      final receiverFuture = receiver.receive();
      final (_, receiveResult) = await (
        sender.sendBytes('empty.txt', bytes),
        receiverFuture,
      ).wait;

      expect(receiveResult!.hashMatch, isTrue);
      expect(receiveResult.bytes, isEmpty);
    });
  });
}
