import 'dart:convert';

/// A WebRTC negotiation payload, opaque to the signaling server.
///
/// Instances are JSON-encoded by the sending client and carried as the
/// [payload] string of a `RelayMessage`; the server never decodes them.
sealed class WebRtcPayload {
  const WebRtcPayload();

  Map<String, dynamic> toJson();

  String encode() => jsonEncode(toJson());

  static WebRtcPayload decode(String source) =>
      fromJson(jsonDecode(source) as Map<String, dynamic>);

  static WebRtcPayload fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    if (kind is! String) {
      throw FormatException('Missing "kind" field in WebRTC payload: $json');
    }
    return switch (kind) {
      'offer' => Offer.fromJson(json),
      'answer' => Answer.fromJson(json),
      'iceCandidate' => IceCandidate.fromJson(json),
      _ => throw FormatException('Unknown WebRTC payload kind: $kind'),
    };
  }
}

/// SDP offer created by the initiating peer.
final class Offer extends WebRtcPayload {
  const Offer(this.sdp);

  final String sdp;

  factory Offer.fromJson(Map<String, dynamic> json) =>
      Offer(json['sdp'] as String);

  @override
  Map<String, dynamic> toJson() => {'kind': 'offer', 'sdp': sdp};
}

/// SDP answer created by the receiving peer in response to an [Offer].
final class Answer extends WebRtcPayload {
  const Answer(this.sdp);

  final String sdp;

  factory Answer.fromJson(Map<String, dynamic> json) =>
      Answer(json['sdp'] as String);

  @override
  Map<String, dynamic> toJson() => {'kind': 'answer', 'sdp': sdp};
}

/// A single ICE candidate gathered by either peer during negotiation.
final class IceCandidate extends WebRtcPayload {
  const IceCandidate({
    required this.candidate,
    required this.sdpMLineIndex,
    this.sdpMid,
  });

  final String candidate;
  final int sdpMLineIndex;
  final String? sdpMid;

  factory IceCandidate.fromJson(Map<String, dynamic> json) => IceCandidate(
    candidate: json['candidate'] as String,
    sdpMLineIndex: json['sdpMLineIndex'] as int,
    sdpMid: json['sdpMid'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'iceCandidate',
    'candidate': candidate,
    'sdpMLineIndex': sdpMLineIndex,
    'sdpMid': sdpMid,
  };
}
