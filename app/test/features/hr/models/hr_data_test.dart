import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/hr/models/hr_data.dart';

void main() {
  final ts = DateTime.utc(2026, 3, 10, 12, 0, 0);

  group('HrData.toJson', () {
    test('includes bpm, rr_ms list, and ISO-8601 UTC timestamp', () {
      final data = HrData(bpm: 72, rrMs: [833, 857], timestamp: ts);
      final json = data.toJson();

      expect(json['bpm'], 72);
      expect(json['rr_ms'], [833, 857]);
      expect(json['timestamp'], '2026-03-10T12:00:00.000Z');
    });

    test('rr_ms defaults to empty list', () {
      final data = HrData(bpm: 60, timestamp: ts);
      expect(data.toJson()['rr_ms'], isEmpty);
    });

    test('timestamp is coerced to UTC in output', () {
      // Local DateTime — toJson must still produce a Z-suffixed string.
      final local = DateTime(2026, 3, 10, 12, 0, 0);
      final json = HrData(bpm: 60, timestamp: local).toJson();
      expect((json['timestamp'] as String).endsWith('Z'), isTrue);
    });
  });
}
