import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:mobile_pulse/features/location/models/location_data.dart';
import 'package:mobile_pulse/services/relay_push_service.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeUri extends Fake implements Uri {}

LocationData _makeLocation({double latitude = 1.23, double longitude = 4.56}) =>
    LocationData(
      latitude: latitude,
      longitude: longitude,
      accuracy: 3.0,
      altitude: 10.0,
      speed: 2.0,
      timestamp: DateTime.utc(2026, 3, 10, 12, 0, 0),
    );

// Injected directly so tests don't require --dart-define.
const String _testRelayUrl =
    'http://100.103.170.67:8010/ingest/gps/pixel-7/stream';

void main() {
  late MockHttpClient mockClient;
  late RelayPushService service;

  setUpAll(() {
    registerFallbackValue(FakeUri());
  });

  setUp(() {
    mockClient = MockHttpClient();
    service = RelayPushService(client: mockClient, relayUrl: _testRelayUrl);
  });

  tearDown(() => service.stop());

  group('RelayPushService.start', () {
    test('POSTs JSON for each emitted map', () async {
      final location = _makeLocation();

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('', 200));

      final controller = StreamController<Map<String, dynamic>>();
      service.start(controller.stream);
      controller.add(location.toJson());

      // Allow the async _post to run.
      await Future<void>.delayed(Duration.zero);

      final captured = verify(
        () => mockClient.post(
          any(),
          headers: captureAny(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;

      final headers = captured[0] as Map<String, String>;
      expect(headers['Content-Type'], 'application/json');

      final body = jsonDecode(captured[1] as String) as Map<String, dynamic>;
      expect(body['latitude'], location.latitude);
      expect(body['longitude'], location.longitude);
      expect(body['accuracy'], location.accuracy);
      expect(body['altitude'], location.altitude);
      expect(body['speed'], location.speed);
      expect(body['timestamp'], location.timestamp.toIso8601String());

      await controller.close();
    });

    test('POSTs to the correct relay URL', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('', 200));

      final controller = StreamController<Map<String, dynamic>>();
      service.start(controller.stream);
      controller.add(_makeLocation().toJson());

      await Future<void>.delayed(Duration.zero);

      final capturedUri =
          verify(
                () => mockClient.post(
                  captureAny(),
                  headers: any(named: 'headers'),
                  body: any(named: 'body'),
                ),
              ).captured.single
              as Uri;

      expect(
        capturedUri.toString(),
        'http://100.103.170.67:8010/ingest/gps/pixel-7/stream',
      );

      await controller.close();
    });

    test('does not throw on non-2xx HTTP response', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('Server Error', 500));

      final controller = StreamController<Map<String, dynamic>>();
      service.start(controller.stream);
      controller.add(_makeLocation().toJson());

      await expectLater(
        Future<void>.delayed(Duration.zero),
        completes, // no exception propagated
      );

      await controller.close();
    });

    test('does not throw when HTTP client throws', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenThrow(Exception('network unreachable'));

      final controller = StreamController<Map<String, dynamic>>();
      service.start(controller.stream);
      controller.add(_makeLocation().toJson());

      await expectLater(Future<void>.delayed(Duration.zero), completes);

      await controller.close();
    });
  });

  group('RelayPushService.stop', () {
    test('stops forwarding data after stop() is called', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('', 200));

      final controller = StreamController<Map<String, dynamic>>();
      service.start(controller.stream);
      service.stop();

      controller.add(_makeLocation().toJson());
      await Future<void>.delayed(Duration.zero);

      verifyNever(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );

      await controller.close();
    });
  });
}
