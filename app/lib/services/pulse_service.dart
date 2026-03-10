import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../features/pulse/models/pulse_data.dart';

/// Collects Android device metrics via standard Android platform APIs.
///
/// Memory, network, and thermal data are retrieved through a MethodChannel
/// backed by [ActivityManager], [TrafficStats], and [PowerManager] in
/// MainActivity — all available to untrusted apps without any permission.
///
/// CPU usage (system-wide) is unavailable: SELinux blocks /proc/stat for
/// untrusted_app and no public Android API provides an equivalent.
/// [PulseData.cpuTotalPct] and [PulseData.cpuPerCorePct] are always 0 / [].
///
/// CPU frequency is read best-effort from sysfs (not in the SELinux denial
/// list on this device); it silently produces null values if blocked.
class PulseService {
  static const _samplePeriod = Duration(seconds: 1);
  static const _channel = MethodChannel(
    'com.example.mobile_pulse/device_metrics',
  );

  Stream<PulseData> get pulseStream => _buildStream();

  Stream<PulseData> _buildStream() async* {
    // Prime — establish baseline cumulative network counters.
    var prevRx = 0;
    var prevTx = 0;
    var prevTs = DateTime.now().millisecondsSinceEpoch;
    try {
      final snap = await _channel.invokeMapMethod<String, dynamic>(
        'getSnapshot',
      );
      if (snap != null) {
        prevRx = (snap['rxBytesTotal'] as num?)?.toInt() ?? 0;
        prevTx = (snap['txBytesTotal'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}

    while (true) {
      await Future.delayed(_samplePeriod);

      Map<String, dynamic>? snap;
      try {
        snap = await _channel.invokeMapMethod<String, dynamic>('getSnapshot');
      } catch (_) {}

      final now = DateTime.now();
      final dt = max((now.millisecondsSinceEpoch - prevTs) / 1000.0, 1e-6);

      // ── Memory (ActivityManager.getMemoryInfo) ────────────────────────────
      final totalMem = (snap?['totalMemBytes'] as num?)?.toInt() ?? 0;
      final availMem = (snap?['availMemBytes'] as num?)?.toInt() ?? 0;
      final usedMem = max(0, totalMem - availMem);
      final memPct = totalMem > 0 ? usedMem / totalMem * 100.0 : 0.0;

      // ── Network (TrafficStats — cumulative bytes since boot) ──────────────
      final nextRx = (snap?['rxBytesTotal'] as num?)?.toInt() ?? prevRx;
      final nextTx = (snap?['txBytesTotal'] as num?)?.toInt() ?? prevTx;
      final rxDelta = max(0, nextRx - prevRx);
      final txDelta = max(0, nextTx - prevTx);

      // ── Thermal (PowerManager) ────────────────────────────────────────────
      final thermalStatus = (snap?['thermalStatus'] as num?)?.toInt();
      final thermalHeadroom = (snap?['thermalHeadroom'] as num?)?.toDouble();

      // ── CPU frequency (best-effort sysfs) ────────────────────────────────
      final freqsMhz = await _readCpuFreqsMhz();
      double? freqAvg;
      if (freqsMhz.isNotEmpty) {
        final valid = freqsMhz.whereType<double>().toList();
        if (valid.isNotEmpty) {
          freqAvg = valid.reduce((a, b) => a + b) / valid.length;
        }
      }

      // CPU usage: /proc/stat is blocked by SELinux (proc_stat domain) for
      // untrusted_app. No public Android API offers system-wide CPU %.
      yield PulseData(
        cpuTotalPct: null,
        cpuPerCorePct: const [],
        cpuFreqAvgMhz: freqAvg != null ? _round1(freqAvg) : null,
        cpuFreqPerCoreMhz: freqsMhz
            .map((f) => f != null ? _round1(f) : null)
            .toList(),
        memPct: _round1(memPct),
        memUsedBytes: usedMem,
        memAvailableBytes: availMem,
        socTempC: null,
        thermalStatus: thermalStatus,
        thermalHeadroom: thermalHeadroom != null
            ? _round1(thermalHeadroom)
            : null,
        netRxBpsTotal: (rxDelta / dt).round(),
        netTxBpsTotal: (txDelta / dt).round(),
        timestamp: now.toUtc(),
      );

      prevRx = nextRx;
      prevTx = nextTx;
      prevTs = now.millisecondsSinceEpoch;
    }
  }

  // ── CPU frequency (per core, MHz) ─────────────────────────────────────────
  //
  // Reads /sys/devices/system/cpu/cpuN/cpufreq/scaling_cur_freq (kHz → MHz).

  Future<List<double?>> _readCpuFreqsMhz() async {
    final result = <double?>[];
    for (int i = 0; i < 16; i++) {
      final path = '/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq';
      try {
        final raw = await File(path).readAsString();
        final kHz = int.tryParse(raw.trim());
        result.add(kHz != null ? kHz / 1000.0 : null);
      } on PathNotFoundException {
        break; // no more cores
      } catch (_) {
        result.add(null);
      }
    }
    return result;
  }

  static double _round1(double v) => (v * 10).round() / 10.0;
}
