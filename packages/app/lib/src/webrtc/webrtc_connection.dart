import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared/shared.dart';

import '../metrics/connection_metrics.dart';

/// WebRTC handshake wrapper: Offer/Answer/ICE exchange over the signaling
/// server, then a DataChannel ready for chunked file transfer.
///
/// Only STUN is configured. There is no TURN fallback: a failed ICE
/// negotiation surfaces as [ConnectionOutcome.iceFailed] rather than being
/// silently retried through a relay.
class WebRtcConnection {
  WebRtcConnection({
    required this.stunUri,
    this.timeout = const Duration(seconds: 20),
  });

  /// e.g. `stun:signaling.example.com:3478`.
  final String stunUri;
  final Duration timeout;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  Timer? _timeoutTimer;
  DateTime? _startedAt;
  DateTime? _decidedAt;
  final _outcomeCompleter = Completer<ConnectionOutcome>();
  // Completes when the DataChannel is bound (may lag ICE Connected on receiver).
  final _dataChannelCompleter = Completer<RTCDataChannel?>();
  // Trickle-ICE buffering: candidates received before setRemoteDescription
  // completes are queued and flushed once the remote description is set.
  bool _remoteDescriptionSet = false;
  final _pendingCandidates = <RTCIceCandidate>[];

  /// Emits every locally-generated payload (the offer/answer once, then one
  /// event per gathered ICE candidate) that the caller must relay to the
  /// remote peer via [SignalingClient.sendRelay].
  final _localPayloads = StreamController<WebRtcPayload>.broadcast();
  Stream<WebRtcPayload> get localPayloads => _localPayloads.stream;

  /// Emits every message received on the DataChannel (text and binary).
  final _dataChannelMessages =
      StreamController<RTCDataChannelMessage>.broadcast();
  Stream<RTCDataChannelMessage> get dataChannelMessages =>
      _dataChannelMessages.stream;

  /// The negotiated DataChannel, available after ICE success.
  RTCDataChannel? get dataChannel => _dataChannel;

  /// Waits up to 5 s for the DataChannel to be bound.
  /// On the receiver side onDataChannel can arrive slightly after ICE Connected.
  Future<RTCDataChannel?> get dataChannelReady => _dataChannelCompleter.future
      .timeout(const Duration(seconds: 5), onTimeout: () => null);

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
      // Browsers signal end-of-candidates with "" (empty string); native with null.
      final c = candidate.candidate;
      if (c == null || c.isEmpty) return;
      _localPayloads.add(
        IceCandidate(
          candidate: candidate.candidate!,
          sdpMLineIndex: candidate.sdpMLineIndex ?? 0,
          sdpMid: candidate.sdpMid,
        ),
      );
    };

    pc.onIceConnectionState = _onIceConnectionState;

    _timeoutTimer = Timer(timeout, () => _complete(ConnectionOutcome.timeout));
  }

  Future<void> handleRemotePayload(WebRtcPayload payload) async {
    final pc = _pc;
    if (pc == null) return;
    switch (payload) {
      case Offer():
        await pc.setRemoteDescription(
          RTCSessionDescription(payload.sdp, 'offer'),
        );
        _remoteDescriptionSet = true;
        await _flushPendingCandidates(pc);
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        _localPayloads.add(Answer(answer.sdp ?? ''));
      case Answer():
        await pc.setRemoteDescription(
          RTCSessionDescription(payload.sdp, 'answer'),
        );
        _remoteDescriptionSet = true;
        await _flushPendingCandidates(pc);
      case IceCandidate():
        if (payload.candidate.isEmpty) break;
        final candidate = RTCIceCandidate(
          payload.candidate,
          payload.sdpMid,
          payload.sdpMLineIndex,
        );
        if (_remoteDescriptionSet) {
          await pc.addCandidate(candidate);
        } else {
          _pendingCandidates.add(candidate);
        }
    }
  }

  Future<void> _flushPendingCandidates(RTCPeerConnection pc) async {
    for (final candidate in _pendingCandidates) {
      await pc.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  void _bindDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;
    channel.onMessage = _dataChannelMessages.add;
    if (!_dataChannelCompleter.isCompleted) {
      _dataChannelCompleter.complete(channel);
    }
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
    await _dataChannelMessages.close();
  }
}
