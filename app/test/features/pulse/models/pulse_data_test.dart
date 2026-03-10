import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/pulse/models/pulse_data.dart';

PulseData _make({
  double? cpuTotalPct = 42.5,
  List<double> cpuPerCorePct = const [40.0, 45.0],
  double? cpuFreqAvgMhz = 1800.0,
  List<double?> cpuFreqPerCoreMhz = const [1700.0, 1900.0],
  double memPct = 55.0,
  int memUsedBytes = 4 * 1024 * 1024 * 1024,
  int memAvailableBytes = 3 * 1024 * 1024 * 1024,
  double? socTempC = 38.5,
  int? thermalStatus,
  double? thermalHeadroom,
  int netRxBpsTotal = 100000,
  int netTxBpsTotal = 50000,
  DateTime? timestamp,
}) => PulseData(
  cpuTotalPct: cpuTotalPct,
  cpuPerCorePct: cpuPerCorePct,
  cpuFreqAvgMhz: cpuFreqAvgMhz,
  cpuFreqPerCoreMhz: cpuFreqPerCoreMhz,
  memPct: memPct,
  memUsedBytes: memUsedBytes,
  memAvailableBytes: memAvailableBytes,
  socTempC: socTempC,
  thermalStatus: thermalStatus,
  thermalHeadroom: thermalHeadroom,
  netRxBpsTotal: netRxBpsTotal,
  netTxBpsTotal: netTxBpsTotal,
  timestamp: timestamp ?? DateTime.utc(2026, 3, 10, 12, 0, 0),
);

void main() {
  final ts = DateTime.utc(2026, 3, 10, 12, 0, 0);

  group('PulseData.toJson', () {
    test('primary metric keys match Python relay schema', () {
      final json = _make(timestamp: ts).toJson();

      expect(json['cpu_total_pct'], 42.5);
      expect(json['cpu_per_core_pct'], [40.0, 45.0]);
      expect(json['cpu_freq_avg_mhz'], 1800.0);
      expect(json['cpu_freq_per_core_mhz'], [1700.0, 1900.0]);
      expect(json['mem_pct'], 55.0);
      expect(json['mem_used_bytes'], 4 * 1024 * 1024 * 1024);
      expect(json['mem_available_bytes'], 3 * 1024 * 1024 * 1024);
      expect(json['soc_temp_c'], 38.5);
      expect(json['net_rx_bps_total'], 100000);
      expect(json['net_tx_bps_total'], 50000);
      expect(json['timestamp'], '2026-03-10T12:00:00.000Z');
    });

    test('short aliases cpu / mem / temp are present', () {
      final json = _make(timestamp: ts).toJson();
      expect(json['cpu'], 42.5);
      expect(json['mem'], 55.0);
      expect(json['temp'], 38.5);
    });

    test('null cpuTotalPct serialises as the string "N/A"', () {
      final json = _make(cpuTotalPct: null).toJson();
      expect(json['cpu_total_pct'], 'N/A');
      expect(json['cpu'], 'N/A');
    });

    test('null socTempC serialises as the string "N/A"', () {
      final json = _make(socTempC: null).toJson();
      expect(json['soc_temp_c'], 'N/A');
      expect(json['temp'], 'N/A');
    });

    test('null cpuFreqAvgMhz is preserved as null in JSON', () {
      final json = _make(cpuFreqAvgMhz: null).toJson();
      expect(json['cpu_freq_avg_mhz'], isNull);
    });

    test('per-core freq list may contain null entries', () {
      final json = _make(cpuFreqPerCoreMhz: [1800.0, null, 2000.0]).toJson();
      final freqs = json['cpu_freq_per_core_mhz'] as List;
      expect(freqs[0], 1800.0);
      expect(freqs[1], isNull);
      expect(freqs[2], 2000.0);
    });

    test('timestamp is coerced to UTC', () {
      final local = DateTime(2026, 3, 10, 12, 0, 0); // local time
      final json = _make(timestamp: local).toJson();
      expect((json['timestamp'] as String).endsWith('Z'), isTrue);
    });

    test('null thermalStatus and thermalHeadroom serialise as null', () {
      final json = _make().toJson();
      expect(json.containsKey('thermal_status'), isTrue);
      expect(json['thermal_status'], isNull);
      expect(json.containsKey('thermal_headroom'), isTrue);
      expect(json['thermal_headroom'], isNull);
    });

    test(
      'non-null thermalStatus and thermalHeadroom round-trip through JSON',
      () {
        final json = _make(thermalStatus: 2, thermalHeadroom: 0.75).toJson();
        expect(json['thermal_status'], 2);
        expect(json['thermal_headroom'], 0.75);
      },
    );
  });
}
