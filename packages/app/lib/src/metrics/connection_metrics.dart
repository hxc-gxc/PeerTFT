import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

/// How a connection attempt ended. There is no "relayed" outcome: this
/// prototype never falls back to TURN, so [directSuccess] always means a
/// genuine peer-to-peer path (host or STUN-assisted `srflx` candidate).
enum ConnectionOutcome { directSuccess, iceFailed, timeout, userCancelled }

/// Anonymous, aggregate-only record of one connection attempt. Deliberately
/// carries no IP, room code or file identifier -- see the architecture doc,
/// section 10.
class ConnectionMetrics {
  const ConnectionMetrics({
    required this.outcome,
    required this.timeToConnect,
    this.networkType,
    this.candidateTypeUsed,
  });

  final ConnectionOutcome outcome;
  final Duration timeToConnect;
  final String? networkType;

  /// `host` or `srflx` in practice; never `relay`, since no TURN server is
  /// configured.
  final String? candidateTypeUsed;

  Map<String, dynamic> toJson() => {
        'outcome': outcome.name,
        'timeToConnectMs': timeToConnect.inMilliseconds,
        if (networkType != null) 'networkType': networkType,
        if (candidateTypeUsed != null) 'candidateTypeUsed': candidateTypeUsed,
      };
}

/// Posts [ConnectionMetrics] to the signaling server's `POST /metrics`.
/// Best-effort and fire-and-forget: a failed report must never affect the
/// transfer UX.
class MetricsReporter {
  MetricsReporter(this.metricsUri, {http.Client? client}) : _client = client ?? http.Client();

  final Uri metricsUri;
  final http.Client _client;

  Future<void> report(ConnectionMetrics metrics) async {
    try {
      await _client.post(
        metricsUri,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(metrics.toJson()),
      );
    } catch (_) {
      // Metrics are best-effort; swallow network errors.
    }
  }

  static Future<String?> currentNetworkType() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty) return null;
      return results.first.name;
    } catch (_) {
      return null;
    }
  }
}
