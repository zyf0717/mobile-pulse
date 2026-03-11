import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/polar_pacer/models/ppi_data.dart';

void main() {
  final ts = DateTime.utc(2026, 3, 11, 10, 0, 0);

  PpiSample sample({
    int ppMs = 850,
    int errorEstimateMs = 5,
    int hr = 70,
    bool blocker = false,
    bool skinContact = true,
    bool skinContactSupported = true,
  }) => PpiSample(
    ppMs: ppMs,
    errorEstimateMs: errorEstimateMs,
    hr: hr,
    blockerBit: blocker,
    skinContactStatus: skinContact,
    skinContactSupported: skinContactSupported,
  );

  group('PpiSample.toJson', () {
    test('serialises all fields correctly', () {
      final json = sample().toJson();
      expect(json['pp_ms'], 850);
      expect(json['pp_error_ms'], 5);
      expect(json['hr'], 70);
      expect(json['blocker'], isFalse);
      expect(json['skin_contact'], isTrue);
      expect(json['skin_contact_supported'], isTrue);
    });

    test('blockerBit = true is preserved', () {
      expect(sample(blocker: true).toJson()['blocker'], isTrue);
    });

    test('skinContactStatus = false is preserved', () {
      expect(sample(skinContact: false).toJson()['skin_contact'], isFalse);
    });
  });

  group('PpiData.toJson', () {
    test('includes samples list and ISO-8601 UTC timestamp', () {
      final data = PpiData(
        samples: [sample(), sample(ppMs: 900)],
        timestamp: ts,
      );
      final json = data.toJson();

      expect((json['samples'] as List).length, 2);
      expect((json['samples'] as List).first['pp_ms'], 850);
      expect((json['samples'] as List).last['pp_ms'], 900);
      expect(json['timestamp'], '2026-03-11T10:00:00.000Z');
    });

    test('handles empty samples list', () {
      final json = PpiData(samples: const [], timestamp: ts).toJson();
      expect(json['samples'], isEmpty);
    });

    test('timestamp is coerced to UTC in output', () {
      final local = DateTime(2026, 3, 11, 10, 0, 0);
      final json = PpiData(samples: const [], timestamp: local).toJson();
      expect((json['timestamp'] as String).endsWith('Z'), isTrue);
    });
  });
}
