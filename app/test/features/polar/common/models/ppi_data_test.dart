import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/polar/common/models/ppi_data.dart';

void main() {
  final ts = DateTime.utc(2026, 3, 10, 12, 0, 0);

  test('PpiData serializes samples and timestamp', () {
    final data = PpiData(
      timestamp: ts,
      samples: const [
        PpiSample(
          ppiMs: 940,
          errorEstimateMs: 4,
          hr: 64,
          blockerBit: false,
          skinContactStatus: true,
          skinContactSupported: true,
          timestampNs: 1234,
        ),
      ],
    );

    final json = data.toJson();
    final samples = json['samples'] as List<dynamic>;
    expect(samples.single['ppi_ms'], 940);
    expect(samples.single['error_estimate_ms'], 4);
    expect(samples.single['timestamp_ns'], 1234);
    expect(json['timestamp'], '2026-03-10T12:00:00.000Z');
  });
}
