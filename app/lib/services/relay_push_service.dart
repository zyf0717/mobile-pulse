import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/location/models/location_data.dart';

enum RelayPushStatus { idle, ok, error }

class RelayPushService {
  static const String _envRelayUrl = String.fromEnvironment('RELAY_URL');

  final String _relayUrl;
  final http.Client _client;
  final _statusController = StreamController<RelayPushStatus>.broadcast();

  StreamSubscription<LocationData>? _subscription;

  RelayPushService({http.Client? client, String? relayUrl})
    : _client = client ?? http.Client(),
      _relayUrl = relayUrl ?? _envRelayUrl;

  /// Emits a [RelayPushStatus] after every POST attempt, and [RelayPushStatus.idle] on stop.
  Stream<RelayPushStatus> get statusStream => _statusController.stream;

  /// Subscribes to [stream] and POSTs each [LocationData] as JSON to the relay.
  void start(Stream<LocationData> stream) {
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

  Future<void> _post(LocationData data) async {
    if (_relayUrl.isEmpty) {
      _statusController.add(RelayPushStatus.error);
      _log(
        'RELAY_URL is not set — launch with --dart-define-from-file=dart_defines.env',
      );
      return;
    }
    try {
      final response = await _client.post(
        Uri.parse(_relayUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data.toJson()),
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
