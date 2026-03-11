class PpiSample {
  final int ppiMs;
  final int errorEstimateMs;
  final int hr;
  final bool blockerBit;
  final bool skinContactStatus;
  final bool skinContactSupported;
  final int timestampNs;

  const PpiSample({
    required this.ppiMs,
    required this.errorEstimateMs,
    required this.hr,
    required this.blockerBit,
    required this.skinContactStatus,
    required this.skinContactSupported,
    required this.timestampNs,
  });

  Map<String, dynamic> toJson() => {
    'ppi_ms': ppiMs,
    'error_estimate_ms': errorEstimateMs,
    'hr': hr,
    'blocker_bit': blockerBit,
    'skin_contact_status': skinContactStatus,
    'skin_contact_supported': skinContactSupported,
    'timestamp_ns': timestampNs,
  };
}

class PpiData {
  final List<PpiSample> samples;
  final DateTime timestamp;

  const PpiData({required this.samples, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'samples': samples.map((sample) => sample.toJson()).toList(),
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}
