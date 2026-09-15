import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared/shared.dart';

import '../metrics/connection_metrics.dart';
import '../platform/web_download_stub.dart'
    if (dart.library.html) '../platform/web_download_web.dart';
import '../platform/web_save.dart';
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

class Reconnecting extends TransferState {
  const Reconnecting({required this.deadline});
  final DateTime deadline; // for a UI countdown
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

class _PendingResume {
  _PendingResume({required this.resumeFromByte, this.initialBytes});
  final int resumeFromByte;
  final Uint8List? initialBytes; // web only; null on native
}

/// Notifier driving the full session: signaling → WebRTC → file transfer.
class TransferSession extends Notifier<TransferState> {
  @override
  TransferState build() => const Idle();

  SignalingClient? _signaling;
  WebRtcConnection? _webrtc;
  StreamSubscription<SignalingMessage>? _signalingSub;
  StreamSubscription<WebRtcPayload>? _localPayloadsSub;
  StreamSubscription<void>? _connectionLostSub;
  bool _isInitiator = false;
  String? _filePath;
  // Web: in-memory file data.
  Uint8List? _fileBytes;
  String? _fileName;
  int? _fileSize;
  String? _code;
  String? _myPeerId;
  // ignore: unused_field // written for reconnect bookkeeping; read by a later chunk's UI
  String? _remotePeerId;
  String? _savePath;
  int _generation = 0;
  FileReceiver? _currentReceiver;
  // ignore: unused_field // live reference held for a later chunk (e.g. cancel-during-resume)
  FileSender? _currentSender;
  _PendingResume? _pendingResume;
  WebWritableSink? _webSink;

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

  Future<void> startSend(PlatformFile platformFile) async {
    await _beginSession(
      code: const CodeGenerator().generate(),
      isInitiator: true,
    );
    if (kIsWeb) {
      _fileBytes = await platformFile.readAsBytes();
      _fileName = platformFile.name;
      _fileSize = await platformFile.length();
    } else {
      _filePath = platformFile.path;
    }
  }

  Future<void> startReceive(String code, {WebWritableSink? webSink}) async {
    await _beginSession(
      code: code,
      isInitiator: false,
    ); // _beginSession itself starts with `await _cancelInternal()`, which
    // aborts whatever `_webSink` is left over from a PRIOR session
    _webSink = webSink; // must be assigned AFTER _beginSession returns --
    // assigning before would have this same call's _cancelInternal() abort
    // the sink the user just granted, before the session even starts
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
    _signalingSub = signaling.messages.listen(
      _onSignalingMessage,
      onError: (_) => unawaited(_handleSignalingDrop()),
      onDone: () => unawaited(_handleSignalingDrop()),
    );
    signaling.joinRoom(code);
  }

  Future<void> _handleSignalingDrop() async {
    if ((state is Transferring || state is Negotiating) && _webSink == null) {
      await _captureResumeState();
      // The ICE-drop trigger (_onConnectionLost) runs synchronously and could
      // have already claimed Reconnecting while the await above was in
      // flight -- re-check instead of unconditionally overwriting it.
      if (state is Reconnecting) return;
      _stallTimer?.cancel();
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      state = Reconnecting(deadline: deadline);
      unawaited(_attemptReconnect(deadline));
      return;
    }
    if (state is WaitingForPeer ||
        state is Connecting ||
        state is Transferring ||
        state is Negotiating) {
      // Either not resumable at all (today's pre-existing cases), or
      // mid-transfer but using a WebWritableSink, which can't resume
      // (see this task's header comment) -- fail now rather than entering
      // Reconnecting.
      _failMidTransfer('Connexion au serveur perdue.');
    }
  }

  Future<void> _attemptReconnect(DateTime deadline) async {
    var backoff = const Duration(seconds: 2);
    while (DateTime.now().isBefore(deadline)) {
      if (state is! Reconnecting) {
        return; // superseded by a successful PeerConnected
      }

      try {
        final signaling = SignalingClient.connect(_signalingWsUri);
        _signaling = signaling;
        _signalingSub = signaling.messages.listen(
          _onSignalingMessage,
          onError: (_) => unawaited(_handleSignalingDrop()),
          onDone: () => unawaited(_handleSignalingDrop()),
        );
        signaling.joinRoom(_code!, reconnectToken: _myPeerId);
        // Wait for either PeerConnected (via _onSignalingMessage, which
        // flips state out of Reconnecting) or this attempt's own timeout.
        await Future.doWhile(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return state is Reconnecting && DateTime.now().isBefore(deadline);
        });
        if (state is! Reconnecting) return; // succeeded
      } catch (_) {
        // Falls through to backoff below, same as a plain timeout.
      }
      await Future<void>.delayed(backoff);
      backoff *= 2;
      if (backoff > const Duration(seconds: 8)) {
        backoff = const Duration(seconds: 8);
      }
    }
    if (state is Reconnecting) {
      state = const Failed('Connexion perdue.');
      await _cancelInternal();
    }
  }

  void _onSignalingMessage(SignalingMessage message) {
    switch (message) {
      case RoomJoined():
        _myPeerId = message.peerId;
        if (state is Reconnecting) {
          return; // stay put until PeerConnected/PeerDisconnected
        }
        state = WaitingForPeer(code: _code ?? '', isInitiator: _isInitiator);
      case PeerConnected():
        // Captured *before* the state overwrite below -- this is the only
        // place that can tell "first-ever pairing" (state was Negotiating)
        // apart from "made it back after a signaling-drop reconnect" (state
        // was Reconnecting); _negotiateWebRtc can't infer this from `state`
        // itself since by the time it runs, this case has already
        // overwritten it to Negotiating either way.
        final resuming = state is Reconnecting;
        _remotePeerId = message.remotePeerId;
        state = const Negotiating();
        unawaited(
          _negotiateWebRtc(message.remotePeerId, isResume: resuming).then((
            success,
          ) {
            if (!success) {
              _releaseWebSink();
              state = const Failed(
                'Connexion directe impossible sur ce réseau.',
              );
            }
          }),
        );
      case PeerReconnecting():
        if ((state is Transferring || state is Negotiating) &&
            _webSink == null) {
          unawaited(
            _captureResumeState().then((_) {
              // Same race guard as _handleSignalingDrop: the ICE-drop trigger
              // could have already claimed Reconnecting while this awaited.
              if (state is Reconnecting) return;
              _stallTimer?.cancel();
              state = Reconnecting(
                deadline: DateTime.now().add(const Duration(seconds: 30)),
              );
              // Nothing to retry locally -- this side's own signaling
              // connection is fine. Just wait for PeerConnected/PeerDisconnected.
            }),
          );
        } else if (state is Transferring || state is Negotiating) {
          // Using a WebWritableSink for this receive -- resume isn't
          // supported for it (see _handleSignalingDrop's comment), so don't
          // wait out the other peer's own grace window; fail now instead of
          // entering Reconnecting.
          _failMidTransfer('Le pair s\'est déconnecté.');
        }
      case RelayMessage():
        final payload = WebRtcPayload.decode(message.payload);
        unawaited(_webrtc?.handleRemotePayload(payload));
      case PeerDisconnected():
        state = const Failed('Le pair s\'est déconnecté.');
        unawaited(_cancelInternal());
      case RoomError():
        _releaseWebSink();
        state = Failed('Erreur de salle: ${message.reason.name}');
      case JoinRoom():
        break;
    }
  }

  /// Aborts `_webSink` and clears it -- unless a `FileReceiver.receive()`
  /// call is already in flight (`_currentReceiver != null`), in which case
  /// that call already owns aborting the sink itself once its stream ends
  /// (see `transfer.dart`'s `receivedHash == null` branch); calling
  /// `abort()` here too would double-abort the same underlying stream.
  ///
  /// Call this -- never abort `_webSink` directly -- from any site outside
  /// `_runReceiver`'s own `catch` handler (which is the one place a
  /// genuine exception means `receive()` never reached its own cleanup, so
  /// there's nothing already in flight to defer to).
  void _releaseWebSink() {
    if (_currentReceiver == null) {
      unawaited(_webSink?.abort());
    }
    _webSink = null;
  }

  /// Shared tail for the two reconnect-trigger sites that fail a
  /// webSink-based receive immediately instead of entering `Reconnecting`
  /// (see `_handleSignalingDrop`'s comment for why webSink can't resume).
  void _failMidTransfer(String message) {
    _releaseWebSink();
    state = Failed(message);
    unawaited(_cancelInternal());
  }

  Future<void> _captureResumeState() async {
    if (_isInitiator || _webSink != null) {
      _pendingResume = null;
      return;
    }
    final receiver = _currentReceiver;
    if (receiver == null) {
      _pendingResume = null;
      return;
    }
    if (kIsWeb) {
      _pendingResume = _PendingResume(
        resumeFromByte: receiver.bytesReceivedSoFar,
        initialBytes: receiver.snapshotBytes(),
      );
    } else {
      await receiver.flushProgress();
      _pendingResume = _PendingResume(
        resumeFromByte: await File(_savePath!).length(),
      );
    }
  }

  Future<bool> _negotiateWebRtc(
    String remotePeerId, {
    Duration timeout = const Duration(seconds: 20),
    bool isResume = false,
  }) async {
    await _webrtc?.dispose();
    await _connectionLostSub?.cancel();
    await _localPayloadsSub?.cancel();

    final signaling = _signaling;
    if (signaling == null) return false;

    final webrtc = WebRtcConnection(stunUri: _stunUri, timeout: timeout);
    _webrtc = webrtc;
    _localPayloadsSub = webrtc.localPayloads.listen(
      (payload) =>
          signaling.sendRelay(targetPeerId: remotePeerId, payload: payload),
    );
    await webrtc.initialize(isInitiator: _isInitiator);

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
    if (outcome != ConnectionOutcome.directSuccess) return false;

    final channel = await webrtc.dataChannelReady;
    if (channel == null) return false;

    final myGeneration = ++_generation;
    _connectionLostSub = webrtc.connectionLost.listen(
      (_) => _onConnectionLost(remotePeerId),
    );
    _throughputWindow.clear();
    final resume = _pendingResume;
    _pendingResume = null;

    if (_isInitiator) {
      _lastTransferred = 0; // sender's own counter; resume offset comes from
      // the receiver's wire message, not this field
      // -- isResume is threaded through separately, below.
      unawaited(
        _runSender(channel, webrtc.dataChannelMessages, myGeneration, isResume),
      );
    } else {
      _lastTransferred = resume?.resumeFromByte ?? 0;
      if (resume != null) {
        state = Transferring(
          fileName: _fileName!,
          totalBytes: _fileSize!,
          transferredBytes: _lastTransferred,
        );
      }
      unawaited(
        _runReceiver(channel, webrtc.dataChannelMessages, myGeneration, resume),
      );
    }
    return true;
  }

  void _onConnectionLost(String remotePeerId) {
    // Only a drop mid-transfer is worth resuming. Without this guard, an ICE
    // state change that fires *after* a successful Complete (e.g. the other
    // peer closing its RTCPeerConnection during normal post-transfer
    // cleanup) would silently overwrite Complete with Reconnecting, then
    // Failed 30s later -- corrupting an already-finished transfer's result.
    // This also covers "the signaling-drop path already claimed
    // Reconnecting", since Reconnecting is neither Transferring nor
    // Negotiating.
    if (state is! Transferring && state is! Negotiating) return;
    if (_webSink != null) {
      // Using a WebWritableSink -- resume isn't supported for it (see
      // _handleSignalingDrop's comment).
      _failMidTransfer('Connexion perdue.');
      return;
    }
    _stallTimer?.cancel();
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    state = Reconnecting(deadline: deadline);
    unawaited(_attemptWebRtcResume(remotePeerId, deadline));
  }

  // Every call into this method follows a *post-success* connectionLost
  // event (see _onConnectionLost above), so isResume: true unconditionally
  // -- there is no "fresh connect" case reachable through this path.
  Future<void> _attemptWebRtcResume(
    String remotePeerId,
    DateTime deadline,
  ) async {
    await _captureResumeState();
    var backoff = const Duration(seconds: 2);
    while (DateTime.now().isBefore(deadline)) {
      if (state is! Reconnecting) return;
      if (await _negotiateWebRtc(
        remotePeerId,
        timeout: const Duration(seconds: 8),
        isResume: true,
      )) {
        return;
      }
      await Future<void>.delayed(backoff);
      backoff *= 2;
    }
    if (state is Reconnecting) {
      state = const Failed('Connexion perdue.');
      await _cancelInternal();
    }
  }

  final _throughputWindow = <_ThroughputSample>[];
  Timer? _stallTimer;
  int _lastTransferred = 0;

  void _onProgress(
    String fileName,
    int totalBytes,
    int transferred,
    int myGeneration,
  ) {
    if (myGeneration != _generation) return;
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

    if (transferred != _lastTransferred) {
      _lastTransferred = transferred;
      _stallTimer?.cancel();
      _stallTimer = Timer(const Duration(seconds: 30), () {
        if (myGeneration != _generation) return;
        if (state is Transferring) {
          state = const Failed(
            'Transfert bloqué — aucune progression depuis 30 secondes.',
          );
        }
      });
    }
  }

  Future<void> _runSender(
    RTCDataChannel channel,
    Stream<RTCDataChannelMessage> messages,
    int myGeneration,
    bool isResume,
  ) async {
    final sender = FileSender(
      channel,
      messages,
      isResume: isResume,
      onProgress: (bytes) {
        _onProgress(_fileName ?? '', _fileSize ?? 0, bytes, myGeneration);
      },
    );
    _currentSender = sender;

    try {
      if (kIsWeb) {
        final bytes = _fileBytes;
        final name = _fileName;
        if (bytes == null || name == null) {
          if (myGeneration == _generation) {
            state = const Failed('Aucun fichier sélectionné.');
          }
          return;
        }
        if (myGeneration == _generation && state is! Transferring) {
          state = Transferring(
            fileName: name,
            totalBytes: bytes.length,
            transferredBytes: 0,
          );
        }
        final result = await sender.sendBytes(name, bytes);
        if (myGeneration != _generation) return;
        state = Complete(
          sha256Sent: result.sha256Hex,
          sha256Received: result.sha256Hex,
          hashMatch: true,
        );
      } else {
        final filePath = _filePath;
        if (filePath == null) {
          if (myGeneration == _generation) {
            state = const Failed('Aucun fichier sélectionné.');
          }
          return;
        }
        final file = File(filePath);
        final fileName = file.uri.pathSegments.last;
        final fileSize = await file.length();
        if (myGeneration == _generation && state is! Transferring) {
          state = Transferring(
            fileName: fileName,
            totalBytes: fileSize,
            transferredBytes: 0,
          );
        }
        final result = await sender.send(file);
        if (myGeneration != _generation) return;
        state = Complete(
          sha256Sent: result.sha256Hex,
          sha256Received: result.sha256Hex,
          hashMatch: true,
        );
      }
    } catch (e) {
      if (myGeneration == _generation) state = Failed('Erreur d\'envoi: $e');
    }
  }

  Future<void> _runReceiver(
    RTCDataChannel channel,
    Stream<RTCDataChannelMessage> messages,
    int myGeneration,
    _PendingResume? resume,
  ) async {
    // On web: null savePathProvider → buffer bytes in memory, then download.
    final receiver = FileReceiver(
      channel,
      messages,
      kIsWeb ? null : _pickSavePath,
      onProgress: (bytes) {
        _onProgress(_fileName ?? '', _fileSize ?? 0, bytes, myGeneration);
      },
      onMeta: (fileName, totalBytes, savePath) {
        _fileName = fileName;
        _fileSize = totalBytes;
        _savePath = savePath;
        if (myGeneration == _generation) {
          state = Transferring(
            fileName: fileName,
            totalBytes: totalBytes,
            transferredBytes: 0,
          );
        }
      },
      resumeFromByte: resume?.resumeFromByte ?? 0,
      resumeFileName: resume != null ? _fileName : null,
      resumeSavePath: resume != null ? _savePath : null,
      initialBytes: resume?.initialBytes,
      webSink: _webSink,
    );
    _currentReceiver = receiver;

    try {
      final result = await receiver.receive();
      if (myGeneration != _generation) return;
      if (result == null) {
        _webSink = null;
        state = const Idle();
        return;
      }
      if (kIsWeb && result.bytes != null) {
        await webDownload(result.fileName ?? 'fichier', result.bytes!);
      }
      _webSink = null;
      state = Complete(
        savedPath: result.savedPath,
        sha256Sent: result.sha256Sent,
        sha256Received: result.sha256Received,
        hashMatch: result.hashMatch,
      );
    } catch (e) {
      if (myGeneration == _generation) {
        unawaited(_webSink?.abort());
        _webSink = null;
        state = Failed('Erreur de réception: $e');
      }
    }
  }

  Future<String?> _pickSavePath(String fileName) async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choisir le dossier de destination',
    );
    if (dir == null) return null;
    return '$dir${Platform.pathSeparator}$fileName';
  }

  Future<void> cancel() async {
    await _cancelInternal();
    state = const Idle();
  }

  Future<void> _cancelInternal() async {
    // Invalidate any in-flight negotiation attempt first: without this, a
    // _runSender/_runReceiver call that's already past _negotiateWebRtc's
    // dispose/init point when the user taps "Annuler" could still complete
    // afterward and, since its captured myGeneration would otherwise still
    // match, overwrite the user's Idle with Complete/Failed.
    _generation++;
    _stallTimer?.cancel();
    _stallTimer = null;
    await _localPayloadsSub?.cancel();
    _localPayloadsSub = null;
    await _connectionLostSub?.cancel();
    _connectionLostSub = null;
    await _signalingSub?.cancel();
    _signalingSub = null;
    await _webrtc?.dispose();
    _webrtc = null;
    await _signaling?.close();
    _signaling = null;
    _filePath = null;
    _fileBytes = null;
    _fileName = null;
    _fileSize = null;
    _savePath = null;
    _code = null;
    _myPeerId = null;
    _remotePeerId = null;
    _pendingResume = null;
    _releaseWebSink(); // must run before nulling _currentReceiver below
    _currentReceiver = null;
    _currentSender = null;
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
