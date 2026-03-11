import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum RelayPushStatus { idle, ok, error }

class RelayPushService {
  final String _relayUrl;
  final String _relayUrlLabel;
  final http.Client _client;
  final _statusController = StreamController<RelayPushStatus>.broadcast();

  StreamSubscription<Map<String, dynamic>>? _subscription;

  RelayPushService({
    http.Client? client,
    String relayUrl = '',
    String relayUrlLabel = 'relay URL',
  }) : _client = client ?? http.Client(),
       _relayUrl = relayUrl,
       _relayUrlLabel = relayUrlLabel;

  /// Emits a [RelayPushStatus] after every POST attempt, and [RelayPushStatus.idle] on stop.
  Stream<RelayPushStatus> get statusStream => _statusController.stream;

  /// Subscribes to [stream] and POSTs each map as JSON to the relay.
  void start(Stream<Map<String, dynamic>> stream) {
    _subscription?.cancel();
    _subscription = stream.listen(
      _post,
      onError: (Object error) => _log('stream error: $error'),
    );
  }

  /// Cancels the active subscription.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _statusController.add(RelayPushStatus.idle);
  }

  Future<void> _post(Map<String, dynamic> data) async {
    if (_relayUrl.isEmpty) {
      _statusController.add(RelayPushStatus.error);
      _log(
        '$_relayUrlLabel is not set — launch with --dart-define-from-file=dart_defines.env',
      );
      return;
    }
    try {
      final response = await _client.post(
        Uri.parse(_relayUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _statusController.add(RelayPushStatus.ok);
      } else {
        _statusController.add(RelayPushStatus.error);
        _log('unexpected status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _statusController.add(RelayPushStatus.error);
      _log('POST failed: $e');
    }
  }

  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }

  // ignore: avoid_print
  void _log(String message) => print('[RelayPushService] $message');
}
