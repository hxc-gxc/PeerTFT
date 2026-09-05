import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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
  FileSender(this._channel, this._messages, {this.onProgress});

  final RTCDataChannel _channel;
  final Stream<RTCDataChannelMessage> _messages;
  final void Function(int bytesSent)? onProgress;

  Future<SendResult> send(File file) async {
    final name = file.uri.pathSegments.last;
    final size = await file.length();

    _sendJson({'type': 'file-meta', 'name': name, 'size': size});

    final ack = await _waitForAck();
    if (!ack) throw Exception('Transfer rejected by receiver');

    final raf = await file.open();
    final sha256 = _Sha256Sink();
    var bytesSent = 0;
    final buffer = Uint8List(_chunkSize);

    try {
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
    _sendJson({'type': 'file-meta', 'name': name, 'size': bytes.length});

    final ack = await _waitForAck();
    if (!ack) throw Exception('Transfer rejected by receiver');

    final sha256 = _Sha256Sink();
    var bytesSent = 0;

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
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _channel.send(RTCDataChannelMessage.fromBinary(data));
  }

  void _sendJson(Map<String, dynamic> json) {
    _channel.send(RTCDataChannelMessage(jsonEncode(json)));
  }
}

/// Receives a file over an established [RTCDataChannel].
///
/// Protocol: wait for `file-meta` → ask caller for save path via callback →
/// send `file-ack` → stream binary chunks to disk + hash → on `file-end`
/// compare hashes. The file is streamed to disk, never full file in memory.
class FileReceiver {
  FileReceiver(
    this._channel,
    this._messages,
    // null = web mode: buffer bytes in memory instead of writing to disk.
    this.savePathProvider, {
    this.onProgress,
  });

  final RTCDataChannel _channel;
  final Stream<RTCDataChannelMessage> _messages;
  final Future<String?> Function(String fileName)? savePathProvider;
  final void Function(int bytesReceived)? onProgress;

  Future<ReceiveResult?> receive() async {
    final meta = await _waitForMeta();
    if (meta == null) return null;
    final fileName = meta['name'] as String;

    final webMode = savePathProvider == null;
    String? savePath;

    if (!webMode) {
      savePath = await savePathProvider!(fileName);
      if (savePath == null) {
        _sendJson({'type': 'file-reject'});
        return null;
      }
    }

    _sendJson({'type': 'file-ack'});

    IOSink? sink;
    BytesBuilder? bytesBuilder;
    if (webMode) {
      bytesBuilder = BytesBuilder(copy: false);
    } else {
      sink = File(savePath!).openWrite();
    }
    final sha256 = _Sha256Sink();
    String? receivedHash;
    var bytesReceived = 0;

    await for (final msg in _messages) {
      if (msg.isBinary) {
        final data = msg.binary;
        sink?.add(data);
        bytesBuilder?.add(data);
        sha256.add(data);
        bytesReceived += data.length;
        onProgress?.call(bytesReceived);
        continue;
      }
      final decoded = jsonDecode(msg.text) as Map<String, dynamic>;
      if (decoded['type'] == 'file-end') {
        receivedHash = decoded['sha256'] as String;
        break;
      }
    }

    await sink?.flush();
    await sink?.close();

    final computed = sha256.hexDigest();
    final hashMatch = receivedHash == computed;

    if (webMode) {
      return ReceiveResult(
        null,
        receivedHash ?? '',
        computed,
        hashMatch,
        bytes: bytesBuilder!.takeBytes(),
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
