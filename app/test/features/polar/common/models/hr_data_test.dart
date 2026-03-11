import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/polar/common/models/hr_data.dart';

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
  });
}
