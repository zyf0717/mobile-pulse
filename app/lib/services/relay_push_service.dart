import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/location/models/location_data.dart';

class RelayPushService {
  static const String _envRelayUrl = String.fromEnvironment('RELAY_URL');

  final String _relayUrl;
  final http.Client _client;

  StreamSubscription<LocationData>? _subscription;

  RelayPushService({http.Client? client, String? relayUrl})
    : _client = client ?? http.Client(),
      _relayUrl = relayUrl ?? _envRelayUrl;

  /// Subscribes to [stream] and POSTs each [LocationData] as JSON to the relay.
  void start(Stream<LocationData> stream) {
    _subscription?.cancel();
    _subscription = stream.listen(
      _post,
      onError: (Object error) => _log('stream error: $error'),
    );
  }

  /// Cancels the active subscription. Does not close the HTTP client.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _post(LocationData data) async {
    try {
      final response = await _client.post(
        Uri.parse(_relayUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data.toJson()),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _log('unexpected status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _log('POST failed: $e');
    }
  }

  // ignore: avoid_print
  void _log(String message) => print('[RelayPushService] $message');
}
