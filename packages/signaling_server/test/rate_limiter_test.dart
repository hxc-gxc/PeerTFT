import 'package:signaling_server/src/rate_limiter.dart';
import 'package:test/test.dart';

void main() {
  group('RateLimiter', () {
    test('allows up to maxAttempts within the window, then blocks', () {
      var now = DateTime(2026, 1, 1);
      final limiter = RateLimiter(maxAttempts: 3, now: () => now);

      expect(limiter.allow('1.2.3.4'), isTrue);
      expect(limiter.allow('1.2.3.4'), isTrue);
      expect(limiter.allow('1.2.3.4'), isTrue);
      expect(limiter.allow('1.2.3.4'), isFalse);
    });

    test('different keys have independent budgets', () {
      final limiter = RateLimiter(maxAttempts: 1);
      expect(limiter.allow('a'), isTrue);
      expect(limiter.allow('b'), isTrue);
      expect(limiter.allow('a'), isFalse);
    });

    test('budget resets once attempts fall outside the window', () {
      var now = DateTime(2026, 1, 1);
      final limiter = RateLimiter(
        maxAttempts: 1,
        window: const Duration(seconds: 30),
        now: () => now,
      );

      expect(limiter.allow('a'), isTrue);
      expect(limiter.allow('a'), isFalse);

      now = now.add(const Duration(seconds: 31));
      expect(limiter.allow('a'), isTrue);
    });
  });
}
