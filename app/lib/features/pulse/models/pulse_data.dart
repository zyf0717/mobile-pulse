class PulseData {
  // null when system-wide CPU % is unavailable (e.g. SELinux blocks /proc/stat).
  final double? cpuTotalPct;
  final List<double> cpuPerCorePct;
  final double? cpuFreqAvgMhz;
  final List<double?> cpuFreqPerCoreMhz;
  final double memPct;
  final int memUsedBytes;
  final int memAvailableBytes;
  final double? socTempC;
  // PowerManager.THERMAL_STATUS_* constant: 0=none 1=light 2=moderate
  // 3=severe 4=critical 5=emergency 6=shutdown. Requires API 29.
  final int? thermalStatus;
  // Distance to severe throttle threshold (0.0–1.0). Requires API 30.
  final double? thermalHeadroom;
  final int netRxBpsTotal;
  final int netTxBpsTotal;
  final DateTime timestamp;

  const PulseData({
    required this.cpuTotalPct,
    required this.cpuPerCorePct,
    required this.cpuFreqAvgMhz,
    required this.cpuFreqPerCoreMhz,
    required this.memPct,
    required this.memUsedBytes,
    required this.memAvailableBytes,
    required this.socTempC,
    this.thermalStatus,
    this.thermalHeadroom,
    required this.netRxBpsTotal,
    required this.netTxBpsTotal,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'cpu_total_pct': cpuTotalPct ?? 'N/A',
    'cpu_per_core_pct': cpuPerCorePct,
    'cpu_freq_avg_mhz': cpuFreqAvgMhz,
    'cpu_freq_per_core_mhz': cpuFreqPerCoreMhz,
    'mem_pct': memPct,
    'mem_used_bytes': memUsedBytes,
    'mem_available_bytes': memAvailableBytes,
    'soc_temp_c': socTempC ?? 'N/A',
    'thermal_status': thermalStatus,
    'thermal_headroom': thermalHeadroom,
    'net_rx_bps_total': netRxBpsTotal,
    'net_tx_bps_total': netTxBpsTotal,
    'cpu': cpuTotalPct ?? 'N/A',
    'mem': memPct,
    'temp': socTempC ?? 'N/A',
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}
