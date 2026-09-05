/// Fixed-window rate limiter keyed by an arbitrary string (in practice, the
/// client's IP address). Guards `JoinRoom` attempts: without this, an
/// attacker could brute-force an active room code during its short lifetime
/// and take the legitimate recipient's place.
class RateLimiter {
  RateLimiter({
    this.maxAttempts = 20,
    this.window = const Duration(minutes: 1),
    DateTime Function() now = DateTime.now,
  }) : _now = now;

  final int maxAttempts;
  final Duration window;
  final DateTime Function() _now;

  final Map<String, List<DateTime>> _attempts = {};

  /// Records an attempt for [key] and returns whether it should be allowed.
  /// Expired timestamps are pruned lazily on each call, so idle keys don't
  /// leak memory indefinitely.
  bool allow(String key) {
    final now = _now();
    final cutoff = now.subtract(window);
    final attempts = _attempts.putIfAbsent(key, () => []);
    attempts.removeWhere((t) => t.isBefore(cutoff));

    if (attempts.length >= maxAttempts) {
      return false;
    }
    attempts.add(now);
    return true;
  }

  /// Drops bookkeeping for keys with no attempts inside the current window.
  /// Call this periodically (e.g. on a timer) on a long-running server to
  /// bound memory usage under sustained distinct-IP traffic.
  void sweep() {
    final cutoff = _now().subtract(window);
    _attempts.removeWhere((_, attempts) {
      attempts.removeWhere((t) => t.isBefore(cutoff));
      return attempts.isEmpty;
    });
  }
}
