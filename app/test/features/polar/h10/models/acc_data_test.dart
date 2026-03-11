import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/polar/h10/models/acc_data.dart';

void main() {
  final ts = DateTime.utc(2026, 3, 10, 12, 0, 0);

  group('AccData.toJson', () {
    test('includes samples_mg, sample_rate_hz and ISO-8601 UTC timestamp', () {
      final data = AccData(
        samples: [
          {'x_mg': 100, 'y_mg': -200, 'z_mg': 9800},
        ],
        timestamp: ts,
      );
      final json = data.toJson();
      final samples = json['samples_mg'] as List;

      expect(samples.length, 1);
      expect(samples[0]['x_mg'], 100);
      expect(samples[0]['y_mg'], -200);
      expect(samples[0]['z_mg'], 9800);
      expect(json['sample_rate_hz'], 200);
      expect(json['timestamp'], '2026-03-10T12:00:00.000Z');
    });

    test('handles empty samples', () {
      final json = AccData(samples: const [], timestamp: ts).toJson();
      expect(json['samples_mg'], isEmpty);
    });

    test('preserves multiple samples', () {
      final data = AccData(
        samples: [
          {'x_mg': 0, 'y_mg': 0, 'z_mg': 9810},
          {'x_mg': 50, 'y_mg': -30, 'z_mg': 9800},
        ],
        timestamp: ts,
      );
      expect((data.toJson()['samples_mg'] as List).length, 2);
    });
  });
}
