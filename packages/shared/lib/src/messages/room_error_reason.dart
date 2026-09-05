/// Reasons the signaling server can reject or terminate a room join.
enum RoomErrorReason {
  /// The room already has two peers (e.g. a third client tried to join).
  codeAlreadyInUse,

  /// The room never reached two peers within its lifetime and was reaped.
  roomExpired,

  /// The submitted code does not match the expected format.
  invalidCode,

  /// The client is sending `JoinRoom` attempts too fast.
  rateLimited;

  static RoomErrorReason fromWire(String value) => values.firstWhere(
    (reason) => reason.name == value,
    orElse: () => throw FormatException('Unknown RoomErrorReason: $value'),
  );
}
