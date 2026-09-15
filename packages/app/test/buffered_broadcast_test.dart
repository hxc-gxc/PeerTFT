import 'package:flutter_test/flutter_test.dart';

import 'package:app/src/webrtc/buffered_broadcast.dart';

void main() {
  group('BufferedBroadcast', () {
    test('replays events added before the first listener', () async {
      final bus = BufferedBroadcast<int>();
      bus.add(1);
      bus.add(2);

      final received = <int>[];
      final sub = bus.stream.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      expect(received, [1, 2]);
      await sub.cancel();
    });

    test('delivers live events normally once a listener is attached', () async {
      final bus = BufferedBroadcast<int>();
      final received = <int>[];
      final sub = bus.stream.listen(received.add);
      bus.add(1);
      bus.add(2);
      await Future<void>.delayed(Duration.zero);

      expect(received, [1, 2]);
      await sub.cancel();
    });

    test('does not replay an event twice to a later listener', () async {
      final bus = BufferedBroadcast<int>();
      final sub1 = bus.stream.listen((_) {});
      bus.add(1);
      await sub1.cancel();

      final received = <int>[];
      final sub2 = bus.stream.listen(received.add);
      bus.add(2);
      await Future<void>.delayed(Duration.zero);

      expect(received, [2]);
      await sub2.cancel();
    });
  });
}
