import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/polar/h10/models/ecg_data.dart';

void main() {
  final ts = DateTime.utc(2026, 3, 10, 12, 0, 0);

  group('EcgData.toJson', () {
    test('includes samples_uv, sample_rate_hz and ISO-8601 UTC timestamp', () {
      final data = EcgData(samples: [100, -50, 200], timestamp: ts);
      final json = data.toJson();

      expect(json['samples_uv'], [100, -50, 200]);
      expect(json['sample_rate_hz'], 130);
      expect(json['timestamp'], '2026-03-10T12:00:00.000Z');
    });

    test('handles empty samples', () {
      final json = EcgData(samples: const [], timestamp: ts).toJson();
      expect(json['samples_uv'], isEmpty);
    });

    test('negative (signed) sample values are preserved', () {
      final data = EcgData(samples: [-8388608, 8388607], timestamp: ts);
      final json = data.toJson();
      expect(json['samples_uv'], [-8388608, 8388607]);
    });
  });
}
