import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared/shared.dart';

import '../metrics/connection_metrics.dart';

/// Raw WebRTC handshake wrapper for the section-13 prototype: no
/// application-layer encryption, no file chunking -- just Offer/Answer/ICE
/// exchange and a single "hello" sent over the resulting DataChannel, plus
/// enough instrumentation to classify the outcome (see [ConnectionOutcome]).
///
/// Only STUN is configured. There is no TURN fallback: a failed ICE
/// negotiation surfaces as [ConnectionOutcome.iceFailed] rather than being
/// silently retried through a relay.
class WebRtcConnection {
  WebRtcConnection({required this.stunUri, this.timeout = const Duration(seconds: 20)});

  /// e.g. `stun:signaling.example.com:3478`.
  final String stunUri;
  final Duration timeout;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  Timer? _timeoutTimer;
  DateTime? _startedAt;
  DateTime? _decidedAt;
  final _outcomeCompleter = Completer<ConnectionOutcome>();

  /// Emits every locally-generated payload (the offer/answer once, then one
  /// event per gathered ICE candidate) that the caller must relay to the
  /// remote peer via [SignalingClient.sendRelay].
  final _localPayloads = StreamController<WebRtcPayload>.broadcast();
  Stream<WebRtcPayload> get localPayloads => _localPayloads.stream;

  /// Emits the text received on the DataChannel (just `"hello"` in this
  /// prototype).
  final _received = StreamController<String>.broadcast();
  Stream<String> get received => _received.stream;

  /// Completes once the ICE handshake reaches a terminal state.
  Future<ConnectionOutcome> get outcome => _outcomeCompleter.future;

  Future<void> initialize({required bool isInitiator}) async {
    _startedAt = DateTime.now();
    final config = <String, dynamic>{
      'iceServers': [
        {'urls': stunUri},
        // Deliberately no TURN server -- see class doc.
      ],
    };
    final pc = await createPeerConnection(config);
    _pc = pc;

    if (isInitiator) {
      final channel = await pc.createDataChannel(
        'file-transfer',
        RTCDataChannelInit()..ordered = true,
      );
      _bindDataChannel(channel);

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _localPayloads.add(Offer(offer.sdp ?? ''));
    } else {
      pc.onDataChannel = _bindDataChannel;
    }

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return; // End-of-candidates marker.
      _localPayloads.add(IceCandidate(
        candidate: candidate.candidate!,
        sdpMLineIndex: candidate.sdpMLineIndex ?? 0,
        sdpMid: candidate.sdpMid,
      ));
    };

    pc.onIceConnectionState = _onIceConnectionState;

    _timeoutTimer = Timer(timeout, () => _complete(ConnectionOutcome.timeout));
  }

  Future<void> handleRemotePayload(WebRtcPayload payload) async {
    final pc = _pc;
    if (pc == null) return;
    switch (payload) {
      case Offer():
        await pc.setRemoteDescription(RTCSessionDescription(payload.sdp, 'offer'));
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        _localPayloads.add(Answer(answer.sdp ?? ''));
      case Answer():
        await pc.setRemoteDescription(RTCSessionDescription(payload.sdp, 'answer'));
      case IceCandidate():
        await pc.addCandidate(RTCIceCandidate(
          payload.candidate,
          payload.sdpMid,
          payload.sdpMLineIndex,
        ));
    }
  }

  void sendHello() {
    _dataChannel?.send(RTCDataChannelMessage(jsonEncode({'type': 'hello'})));
  }

  void _bindDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;
    channel.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) return;
      final decoded = jsonDecode(message.text) as Map<String, dynamic>;
      if (decoded['type'] == 'hello') {
        _received.add('hello');
      }
    };
  }

  void _onIceConnectionState(RTCIceConnectionState state) {
    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        _complete(ConnectionOutcome.directSuccess);
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _complete(ConnectionOutcome.iceFailed);
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
      case RTCIceConnectionState.RTCIceConnectionStateNew:
      case RTCIceConnectionState.RTCIceConnectionStateChecking:
      case RTCIceConnectionState.RTCIceConnectionStateCount:
        break;
    }
  }

  /// Reads the negotiated candidate pair from `getStats()` to tell a direct
  /// LAN/host connection apart from a STUN-assisted `srflx` one. There is no
  /// `relay` case: no TURN server is ever configured.
  Future<String?> candidateTypeUsed() async {
    final pc = _pc;
    if (pc == null) return null;
    final reports = await pc.getStats();
    for (final report in reports) {
      if (report.type != 'candidate-pair') continue;
      if (report.values['state'] != 'succeeded') continue;
      final localId = report.values['localCandidateId'];
      final local = reports.firstWhere(
        (r) => r.type == 'local-candidate' && r.id == localId,
        orElse: () => report,
      );
      final type = local.values['candidateType'];
      if (type is String) return type;
    }
    return null;
  }

  void _complete(ConnectionOutcome result) {
    if (_outcomeCompleter.isCompleted) return;
    _timeoutTimer?.cancel();
    _decidedAt = DateTime.now();
    _outcomeCompleter.complete(result);
  }

  /// Duration between [initialize] and the outcome being decided; `null`
  /// before either has happened.
  Duration? get timeToConnect {
    final startedAt = _startedAt;
    final decidedAt = _decidedAt;
    if (startedAt == null || decidedAt == null) return null;
    return decidedAt.difference(startedAt);
  }

  Future<void> dispose() async {
    _timeoutTimer?.cancel();
    await _dataChannel?.close();
    await _pc?.close();
    await _localPayloads.close();
    await _received.close();
  }
}
