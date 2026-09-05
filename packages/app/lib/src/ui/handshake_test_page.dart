import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../metrics/connection_metrics.dart';
import '../signaling/signaling_client.dart';
import '../webrtc/webrtc_connection.dart';

/// Throwaway prototype screen (architecture doc, section 13): no file
/// transfer, no encryption -- just prove out room matching + raw WebRTC
/// handshake + a "hello" over the DataChannel, with ICE outcome reporting.
///
/// Superseded by the real screens from section 9 once the handshake and NAT
/// traversal numbers are validated.
class HandshakeTestPage extends StatefulWidget {
  const HandshakeTestPage({
    super.key,
    required this.signalingHttpUri,
    required this.signalingWsUri,
    required this.stunUri,
  });

  final Uri signalingHttpUri;
  final Uri signalingWsUri;
  final String stunUri;

  @override
  State<HandshakeTestPage> createState() => _HandshakeTestPageState();
}

class _HandshakeTestPageState extends State<HandshakeTestPage> {
  final _codeController = TextEditingController();
  final _codeGenerator = const CodeGenerator();

  SignalingClient? _signaling;
  WebRtcConnection? _webrtc;
  bool _isInitiator = false;
  String? _peerId;
  String _status = 'idle';

  @override
  void dispose() {
    _codeController.dispose();
    _webrtc?.dispose();
    _signaling?.close();
    super.dispose();
  }

  Future<void> _start({required bool isInitiator}) async {
    final code = isInitiator ? _codeGenerator.generate() : _codeController.text.trim();
    if (code.isEmpty) return;
    _codeController.text = code;
    _isInitiator = isInitiator;

    setState(() => _status = 'connecting to signaling server...');

    final signaling = SignalingClient.connect(widget.signalingWsUri);
    _signaling = signaling;
    signaling.messages.listen(_onSignalingMessage);
    signaling.joinRoom(code);
  }

  void _onSignalingMessage(SignalingMessage message) {
    switch (message) {
      case RoomJoined():
        setState(() {
          _peerId = message.peerId;
          _status = 'waiting for the other peer...';
        });
      case PeerConnected():
        setState(() => _status = 'peer connected, negotiating WebRTC...');
        // Per the architecture doc (section 3): PeerConnected is what
        // triggers the handshake on the offerer's side. The answerer starts
        // its own PeerConnection here too, so it is ready to receive the
        // Offer the moment it arrives as a relayed message.
        unawaited(_beginWebRtc(remotePeerId: message.remotePeerId));
      case RelayMessage():
        final payload = WebRtcPayload.decode(message.payload);
        unawaited(_webrtc?.handleRemotePayload(payload));
      case PeerDisconnected():
        setState(() => _status = 'peer disconnected');
      case RoomError():
        setState(() => _status = 'room error: ${message.reason.name}');
      case JoinRoom():
        break; // Never sent by the server.
    }
  }

  Future<void> _beginWebRtc({required String remotePeerId}) async {
    final signaling = _signaling;
    if (signaling == null) return;

    final webrtc = WebRtcConnection(stunUri: widget.stunUri);
    _webrtc = webrtc;
    webrtc.received.listen((_) => setState(() => _status = 'received hello ✓'));
    // Subscribed before `initialize()` runs: the initiator's Offer is
    // emitted synchronously inside it, and this is a broadcast stream with
    // no buffering for late listeners.
    webrtc.localPayloads.listen((payload) {
      signaling.sendRelay(targetPeerId: remotePeerId, payload: payload);
    });

    await webrtc.initialize(isInitiator: _isInitiator);

    unawaited(_reportOutcomeWhenDecided(webrtc));
  }

  Future<void> _reportOutcomeWhenDecided(WebRtcConnection webrtc) async {
    final outcome = await webrtc.outcome;
    final candidateType = await webrtc.candidateTypeUsed();
    final networkType = await MetricsReporter.currentNetworkType();

    setState(() => _status = 'ICE outcome: ${outcome.name}');
    if (outcome == ConnectionOutcome.directSuccess) {
      webrtc.sendHello();
    }

    final timeToConnect = webrtc.timeToConnect ?? Duration.zero;
    await MetricsReporter(widget.signalingHttpUri.replace(path: '/metrics')).report(
      ConnectionMetrics(
        outcome: outcome,
        timeToConnect: timeToConnect,
        networkType: networkType,
        candidateTypeUsed: candidateType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PeerTFT -- handshake prototype')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'Room code'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _start(isInitiator: true),
                    child: const Text('Create room'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _start(isInitiator: false),
                    child: const Text('Join room'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Status: $_status'),
            if (_peerId != null) Text('Local peer id: $_peerId'),
          ],
        ),
      ),
    );
  }
}
