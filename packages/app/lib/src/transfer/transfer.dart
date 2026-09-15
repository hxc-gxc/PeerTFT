import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../platform/web_save.dart';

/// Result of a completed send.
class SendResult {
  const SendResult(this.sha256Hex, this.bytesSent);
  final String sha256Hex;
  final int bytesSent;
}

/// Result of a completed receive.
class ReceiveResult {
  const ReceiveResult(
    this.savedPath,
    this.sha256Sent,
    this.sha256Received,
    this.hashMatch, {
    this.bytes,
    this.fileName,
  });
  final String? savedPath; // null on web
  final Uint8List? bytes; // populated on web
  final String? fileName; // populated on web
  final String sha256Sent;
  final String sha256Received;
  final bool hashMatch;
}

const _chunkSize = 16 * 1024; // 16 KB
const _bufferHighWatermark = 1024 * 1024; // 1 MB — backpressure threshold

/// Sends a file over an established [RTCDataChannel].
///
/// Protocol: `file-meta` → wait for `file-ack` → stream binary chunks →
/// `file-end` with SHA-256. The file is streamed from disk and hashed
/// chunk-by-chunk, so it is never fully held in memory.
class FileSender {
  FileSender(
    this._channel,
    this._messages, {
    this.onProgress,
    this.isResume = false,
  });

  final RTCDataChannel _channel;
  final Stream<RTCDataChannelMessage> _messages;
  final void Function(int bytesSent)? onProgress;
  final bool isResume;

  Future<SendResult> send(File file) async {
    final size = await file.length();
    var resumeFrom = 0;

    if (isResume) {
      resumeFrom = await _waitForResume();
    } else {
      final name = file.uri.pathSegments.last;
      _sendJson({'type': 'file-meta', 'name': name, 'size': size});
      final ack = await _waitForAck();
      if (!ack) throw Exception('Transfer rejected by receiver');
    }

    final raf = await file.open();
    final sha256 = _Sha256Sink();
    var bytesSent = 0;
    final buffer = Uint8List(_chunkSize);

    try {
      if (resumeFrom > 0) {
        // Replay [0, resumeFrom) through the hash (local disk read, not a
        // network send) to reconstruct a correct running hash before
        // continuing the chunked send loop from the same offset.
        final replay = Uint8List(_chunkSize);
        var replayed = 0;
        while (replayed < resumeFrom) {
          final toRead = (resumeFrom - replayed).clamp(0, _chunkSize);
          final read = await raf.readInto(replay, 0, toRead);
          if (read <= 0) break;
          sha256.add(
            read == replay.length
                ? replay
                : Uint8List.view(replay.buffer, 0, read),
          );
          replayed += read;
        }
        bytesSent = replayed;
      }

      while (bytesSent < size) {
        final read = await raf.readInto(buffer);
        if (read <= 0) break;
        final data = read == buffer.length
            ? buffer
            : Uint8List.view(buffer.buffer, 0, read);
        sha256.add(data);
        await _sendWithBackpressure(data);
        bytesSent += read;
        onProgress?.call(bytesSent);
      }
    } finally {
      await raf.close();
    }

    final hashHex = sha256.hexDigest();
    _sendJson({'type': 'file-end', 'sha256': hashHex});

    return SendResult(hashHex, bytesSent);
  }

  /// Web path: send from in-memory bytes (no filesystem access).
  Future<SendResult> sendBytes(String name, Uint8List bytes) async {
    var resumeFrom = 0;

    if (isResume) {
      resumeFrom = await _waitForResume();
    } else {
      _sendJson({'type': 'file-meta', 'name': name, 'size': bytes.length});
      final ack = await _waitForAck();
      if (!ack) throw Exception('Transfer rejected by receiver');
    }

    final sha256 = _Sha256Sink();
    if (resumeFrom > 0) sha256.add(bytes.sublist(0, resumeFrom));
    var bytesSent = resumeFrom;

    while (bytesSent < bytes.length) {
      final end = (bytesSent + _chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(bytesSent, end);
      sha256.add(chunk);
      await _sendWithBackpressure(chunk);
      bytesSent = end;
      onProgress?.call(bytesSent);
    }

    final hashHex = sha256.hexDigest();
    _sendJson({'type': 'file-end', 'sha256': hashHex});
    return SendResult(hashHex, bytesSent);
  }

  Future<int> _waitForResume() async {
    return _messages
        .where((m) => !m.isBinary)
        .map((m) => jsonDecode(m.text) as Map<String, dynamic>)
        .where((m) => m['type'] == 'resume')
        .first
        .then((m) => m['bytesReceived'] as int);
  }

  Future<bool> _waitForAck() async {
    // ponytail: timeout is generous; if the peer is slow to respond we'd
    // rather wait than fail prematurely.
    return _messages
        .where((m) => !m.isBinary)
        .map((m) => jsonDecode(m.text) as Map<String, dynamic>)
        .where((m) => m['type'] == 'file-ack' || m['type'] == 'file-reject')
        .first
        .then((m) => m['type'] == 'file-ack');
  }

  Future<void> _sendWithBackpressure(Uint8List data) async {
    // ponytail: poll-based backpressure; fine for single-file transfer.
    while ((_channel.bufferedAmount ?? 0) > _bufferHighWatermark) {
      if (_channel.state != RTCDataChannelState.RTCDataChannelOpen) {
        throw Exception('Canal de données fermé pendant le transfert.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (_channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('Canal de données fermé avant l\'envoi.');
    }
    _channel.send(RTCDataChannelMessage.fromBinary(data));
  }

  void _sendJson(Map<String, dynamic> json) {
    if (_channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('Canal de données non ouvert (état: ${_channel.state}).');
    }
    _channel.send(RTCDataChannelMessage(jsonEncode(json)));
  }
}

/// Receives a file over an established [RTCDataChannel].
///
/// Protocol: wait for `file-meta` → ask caller for save path via callback →
/// send `file-ack` → stream binary chunks to disk + hash → on `file-end`
/// compare hashes. The file is streamed to disk, never full file in memory.
///
/// Single-use: call [receive] exactly once per instance. `_bytesReceived`,
/// `_sink` and `_bytesBuilder` are populated during that one call, not reset
/// between calls — a second call would append into a stale sink or a
/// leftover `BytesBuilder`. To resume a transfer, construct a new
/// `FileReceiver` (with `resumeFromByte`/`initialBytes` set) rather than
/// calling `receive()` again on the same one.
class FileReceiver {
  FileReceiver(
    this._channel,
    this._messages,
    // null = web mode: buffer bytes in memory instead of writing to disk.
    this.savePathProvider, {
    this.onProgress,
    this.onMeta,
    this.resumeFromByte = 0,
    this.resumeFileName,
    this.resumeSavePath,
    this.initialBytes,
    this.webSink,
  }) : assert(
         resumeFromByte == 0 || (resumeFileName != null),
         'resumeFileName is required whenever resumeFromByte > 0',
       ),
       assert(
         webSink == null || resumeFromByte == 0,
         'webSink-based receives do not support resume -- callers must '
         'never construct one this way. (Note: this assert is stripped in '
         'release/profile builds; it is not a runtime-enforced guarantee.)',
       );

  final RTCDataChannel _channel;
  final Stream<RTCDataChannelMessage> _messages;
  final Future<String?> Function(String fileName)? savePathProvider;
  final void Function(int bytesReceived)? onProgress;

  /// Fires once, on a *fresh* receive only, right after the save path (or
  /// web save-dialog-equivalent) is resolved.
  final void Function(String fileName, int totalBytes, String? savePath)?
  onMeta;
  final int resumeFromByte;
  final String? resumeFileName;
  final String? resumeSavePath;
  final Uint8List? initialBytes; // web only; seeds the BytesBuilder
  final WebWritableSink? webSink;

  int _bytesReceived = 0;
  IOSink? _sink;
  BytesBuilder? _bytesBuilder;

  int get bytesReceivedSoFar => _bytesReceived;
  Future<void> flushProgress() => _sink?.flush() ?? Future.value();
  Uint8List? snapshotBytes() =>
      _bytesBuilder?.toBytes(); // does NOT clear the builder

  Future<ReceiveResult?> receive() async {
    final isResume = resumeFromByte > 0;
    final String fileName;
    String? savePath;
    final webMode = savePathProvider == null;

    if (isResume) {
      fileName = resumeFileName!;
      savePath = resumeSavePath;
    } else {
      final meta = await _waitForMeta();
      if (meta == null) return null;
      fileName = meta['name'] as String;
      final totalBytes = meta['size'] as int;

      if (!webMode) {
        savePath = await savePathProvider!(fileName);
        if (savePath == null) {
          _sendJson({'type': 'file-reject'});
          return null;
        }
      }
      onMeta?.call(fileName, totalBytes, savePath);
      _sendJson({'type': 'file-ack'});
    }

    if (webSink != null) {
      // Already open -- the caller obtained it from the browser's save
      // picker before this receive even started (see receive_page.dart).
      // Nothing to initialize here.
    } else if (webMode) {
      _bytesBuilder = BytesBuilder(copy: false);
      if (initialBytes != null) _bytesBuilder!.add(initialBytes!);
    } else {
      _sink = File(
        savePath!,
      ).openWrite(mode: isResume ? FileMode.append : FileMode.write);
    }
    _bytesReceived = resumeFromByte;

    // The hash must cover the *whole* file, matching the sender's
    // replay-then-continue hash, so the final SHA-256 comparison is
    // meaningful on a resume: seed it with the already-known pre-resume
    // bytes before the loop below adds anything new.
    final sha256 = _Sha256Sink();
    if (isResume) {
      if (webMode) {
        sha256.add(initialBytes!);
      } else {
        await for (final chunk in File(
          resumeSavePath!,
        ).openRead(0, resumeFromByte)) {
          sha256.add(chunk);
        }
      }
      // Yield once before signaling resume: a real RTCDataChannel is
      // inherently async, but the in-memory fake channel used in tests
      // sends synchronously, so without this yield a resume message sent
      // here (before returning control to the caller) can race ahead of
      // the sender's listener subscribing and be dropped on the broadcast
      // stream (no buffering for late subscribers).
      await Future<void>.value();
      _sendJson({'type': 'resume', 'bytesReceived': resumeFromByte});
    }
    String? receivedHash;

    await for (final msg in _messages) {
      if (msg.isBinary) {
        final data = msg.binary;
        if (webSink != null) {
          // Awaited deliberately, unlike _sink?.add (which buffers
          // internally): this is what gives the File System Access path
          // its backpressure, the whole reason to stream instead of
          // buffering the file in memory.
          await webSink!.write(data);
        } else {
          _sink?.add(data);
          _bytesBuilder?.add(data);
        }
        sha256.add(data);
        _bytesReceived += data.length;
        onProgress?.call(_bytesReceived);
        continue;
      }
      final decoded = jsonDecode(msg.text) as Map<String, dynamic>;
      if (decoded['type'] == 'file-end') {
        receivedHash = decoded['sha256'] as String;
        break;
      }
    }

    await _sink?.flush();
    await _sink?.close();

    if (webSink != null && receivedHash == null) {
      // Stream ended without ever seeing file-end (peer dropped
      // mid-transfer). Unlike the native/BytesBuilder branches below, which
      // unconditionally flush/close regardless of how the loop ended, an
      // open FileSystemWritableFileStream left un-closed holds an OS-level
      // lock on the destination file -- abort discards the partial write.
      // A future caller reading `receive()`'s null return should treat
      // this sink as already cleaned up -- do not call abort() again on it.
      await webSink!.abort();
      return null;
    }

    final computed = sha256.hexDigest();
    final hashMatch = receivedHash == computed;

    if (webSink != null) {
      await webSink!.close();
      return ReceiveResult(
        null,
        receivedHash!,
        computed,
        hashMatch,
        fileName: fileName,
        // no `bytes:` populated -- nothing to hand to webDownload(), the
        // browser already has the file on disk via the FileSystemFileHandle
        // the user picked before the transfer started.
      );
    }

    if (webMode) {
      return ReceiveResult(
        null,
        receivedHash ?? '',
        computed,
        hashMatch,
        bytes: _bytesBuilder!.takeBytes(),
        fileName: fileName,
      );
    }
    return ReceiveResult(savePath!, receivedHash ?? '', computed, hashMatch);
  }

  Future<Map<String, dynamic>?> _waitForMeta() async {
    return _messages
        .where((m) => !m.isBinary)
        .map((m) => jsonDecode(m.text) as Map<String, dynamic>)
        .where((m) => m['type'] == 'file-meta')
        .first;
  }

  void _sendJson(Map<String, dynamic> json) {
    if (_channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('Canal de données non ouvert (état: ${_channel.state}).');
    }
    _channel.send(RTCDataChannelMessage(jsonEncode(json)));
  }
}

/// ponytail: wraps sha256's chunked conversion API in a minimal add/finalize
/// interface. DigestSink exists in crypto/src but isn't re-exported, so we
/// inline an equivalent sink here.
class _Sha256Sink {
  final _output = _DigestSink();
  late final _input = sha256.startChunkedConversion(_output);

  void add(List<int> data) => _input.add(data);

  String hexDigest() {
    _input.close();
    return _output.value.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest digest) => _value = digest;

  @override
  void close() {}
}
