import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared/shared.dart';

import '../metrics/connection_metrics.dart';
import '../signaling/signaling_client.dart';
import '../transfer/transfer.dart';
import '../webrtc/webrtc_connection.dart';

/// State machine for a transfer session. Exhaustive switch at every
/// consumer site is the point of this sealed class.
sealed class TransferState {
  const TransferState();
}

class Idle extends TransferState {
  const Idle();
}

class Connecting extends TransferState {
  const Connecting();
}

class WaitingForPeer extends TransferState {
  const WaitingForPeer({required this.code, required this.isInitiator});
  final String code;
  final bool isInitiator;
}

class Negotiating extends TransferState {
  const Negotiating();
}

class Transferring extends TransferState {
  const Transferring({
    required this.fileName,
    required this.totalBytes,
    required this.transferredBytes,
    this.throughputBps = 0,
  });
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final double throughputBps;

  Transferring copyWith({int? transferredBytes, double? throughputBps}) =>
      Transferring(
        fileName: fileName,
        totalBytes: totalBytes,
        transferredBytes: transferredBytes ?? this.transferredBytes,
        throughputBps: throughputBps ?? this.throughputBps,
      );
}

class Complete extends TransferState {
  const Complete({
    this.savedPath,
    required this.sha256Sent,
    required this.sha256Received,
    required this.hashMatch,
  });
  final String? savedPath;
  final String sha256Sent;
  final String sha256Received;
  final bool hashMatch;
}

class Failed extends TransferState {
  const Failed(this.message);
  final String message;
}

/// Notifier driving the full session: signaling → WebRTC → file transfer.
class TransferSession extends Notifier<TransferState> {
  @override
  TransferState build() => const Idle();

  SignalingClient? _signaling;
  WebRtcConnection? _webrtc;
  StreamSubscription<SignalingMessage>? _signalingSub;
  StreamSubscription<WebRtcPayload>? _localPayloadsSub;
  bool _isInitiator = false;
  String? _filePath;
  String? _code;

  static final _signalingWsUri = Uri.parse(
    const String.fromEnvironment(
      'SIGNALING_WS_URL',
      defaultValue: 'ws://localhost:8080/ws',
    ),
  );
  static final _signalingHttpUri = Uri.parse(
    const String.fromEnvironment(
      'SIGNALING_HTTP_URL',
      defaultValue: 'http://localhost:8080',
    ),
  );
  static const _stunUri = String.fromEnvironment(
    'STUN_URL',
    defaultValue: 'stun:localhost:3478',
  );

  Future<void> startSend(String filePath) async {
    await _beginSession(
      code: const CodeGenerator().generate(),
      isInitiator: true,
    );
    _filePath = filePath;
  }

  Future<void> startReceive(String code) async {
    await _beginSession(code: code, isInitiator: false);
  }

  Future<void> _beginSession({
    required String code,
    required bool isInitiator,
  }) async {
    await _cancelInternal();
    _isInitiator = isInitiator;
    _code = code;
    state = const Connecting();

    final signaling = SignalingClient.connect(_signalingWsUri);
    _signaling = signaling;
    _signalingSub = signaling.messages.listen(_onSignalingMessage);
    signaling.joinRoom(code);
  }

  void _onSignalingMessage(SignalingMessage message) {
    switch (message) {
      case RoomJoined():
        state = WaitingForPeer(code: _code ?? '', isInitiator: _isInitiator);
      case PeerConnected():
        state = const Negotiating();
        unawaited(_beginWebRtc(remotePeerId: message.remotePeerId));
      case RelayMessage():
        final payload = WebRtcPayload.decode(message.payload);
        unawaited(_webrtc?.handleRemotePayload(payload));
      case PeerDisconnected():
        state = const Failed('Le pair s\'est déconnecté.');
        unawaited(_cancelInternal());
      case RoomError():
        state = Failed('Erreur de salle: ${message.reason.name}');
      case JoinRoom():
        break;
    }
  }

  Future<void> _beginWebRtc({required String remotePeerId}) async {
    final signaling = _signaling;
    if (signaling == null) return;

    final webrtc = WebRtcConnection(stunUri: _stunUri);
    _webrtc = webrtc;

    _localPayloadsSub = webrtc.localPayloads.listen((payload) {
      signaling.sendRelay(targetPeerId: remotePeerId, payload: payload);
    });

    await webrtc.initialize(isInitiator: _isInitiator);
    unawaited(_awaitIceOutcome(webrtc));
  }

  Future<void> _awaitIceOutcome(WebRtcConnection webrtc) async {
    final outcome = await webrtc.outcome;

    final candidateType = await webrtc.candidateTypeUsed();
    final networkType = await MetricsReporter.currentNetworkType();
    final timeToConnect = webrtc.timeToConnect ?? Duration.zero;
    unawaited(
      MetricsReporter(_signalingHttpUri.replace(path: '/metrics')).report(
        ConnectionMetrics(
          outcome: outcome,
          timeToConnect: timeToConnect,
          networkType: networkType,
          candidateTypeUsed: candidateType,
        ),
      ),
    );

    if (outcome != ConnectionOutcome.directSuccess) {
      state = const Failed('Connexion directe impossible sur ce réseau.');
      await _cancelInternal();
      return;
    }

    final channel = webrtc.dataChannel;
    if (channel == null) {
      state = const Failed('Canal de données indisponible.');
      return;
    }

    if (_isInitiator) {
      unawaited(_runSender(channel, webrtc.dataChannelMessages));
    } else {
      unawaited(_runReceiver(channel, webrtc.dataChannelMessages));
    }
  }

  final _throughputWindow = <_ThroughputSample>[];

  void _onProgress(String fileName, int totalBytes, int transferred) {
    final now = DateTime.now();
    _throughputWindow.add(_ThroughputSample(now, transferred));
    // Keep only samples from the last 1 second.
    _throughputWindow.removeWhere(
      (s) => now.difference(s.time) > const Duration(seconds: 1),
    );
    double bps = 0;
    if (_throughputWindow.length >= 2) {
      final first = _throughputWindow.first;
      final last = _throughputWindow.last;
      final elapsed = last.time.difference(first.time).inMicroseconds;
      if (elapsed > 0) {
        bps = (last.bytes - first.bytes) * 1000000 / elapsed;
      }
    }
    final current = state is Transferring
        ? state as Transferring
        : Transferring(
            fileName: fileName,
            totalBytes: totalBytes,
            transferredBytes: 0,
          );
    state = current.copyWith(transferredBytes: transferred, throughputBps: bps);
  }

  Future<void> _runSender(
    RTCDataChannel channel,
    Stream<RTCDataChannelMessage> messages,
  ) async {
    final filePath = _filePath;
    if (filePath == null) {
      state = const Failed('Aucun fichier sélectionné.');
      return;
    }
    final file = File(filePath);
    final fileName = file.uri.pathSegments.last;
    final fileSize = await file.length();

    state = Transferring(
      fileName: fileName,
      totalBytes: fileSize,
      transferredBytes: 0,
    );

    final sender = FileSender(
      channel,
      messages,
      onProgress: (bytes) {
        _onProgress(fileName, fileSize, bytes);
      },
    );
    try {
      final result = await sender.send(file);
      state = Complete(
        sha256Sent: result.sha256Hex,
        sha256Received: result.sha256Hex,
        hashMatch: true,
      );
    } catch (e) {
      state = Failed('Erreur d\'envoi: $e');
    }
  }

  Future<void> _runReceiver(
    RTCDataChannel channel,
    Stream<RTCDataChannelMessage> messages,
  ) async {
    final receiver = FileReceiver(
      channel,
      messages,
      _pickSavePath,
      onProgress: (bytes) {
        final s = state;
        if (s is Transferring) {
          _onProgress(s.fileName, s.totalBytes, bytes);
        }
      },
    );
    try {
      final result = await receiver.receive();
      if (result == null) {
        // User cancelled the save dialog.
        state = const Idle();
        return;
      }
      state = Complete(
        savedPath: result.savedPath,
        sha256Sent: result.sha256Sent,
        sha256Received: result.sha256Received,
        hashMatch: result.hashMatch,
      );
    } catch (e) {
      state = Failed('Erreur de réception: $e');
    }
  }

  Future<String?> _pickSavePath(String fileName) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Enregistrer le fichier',
      fileName: fileName,
    );
    return result;
  }

  Future<void> cancel() async {
    await _cancelInternal();
    state = const Idle();
  }

  Future<void> _cancelInternal() async {
    await _localPayloadsSub?.cancel();
    _localPayloadsSub = null;
    await _signalingSub?.cancel();
    _signalingSub = null;
    await _webrtc?.dispose();
    _webrtc = null;
    await _signaling?.close();
    _signaling = null;
    _filePath = null;
    _code = null;
    _throughputWindow.clear();
  }
}

final transferSessionProvider =
    NotifierProvider<TransferSession, TransferState>(TransferSession.new);

class _ThroughputSample {
  _ThroughputSample(this.time, this.bytes);
  final DateTime time;
  final int bytes;
}
