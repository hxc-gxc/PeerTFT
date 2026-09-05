import 'dart:math';

/// Generates short-lived, non-identifying peer ids. These exist only to
/// route messages within a room for the lifetime of the WebSocket
/// connection -- never persisted, never tied to any account.
String generatePeerId([Random? random]) {
  final rng = random ?? _secureRandom;
  final bytes = List.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

final Random _secureRandom = Random.secure();
