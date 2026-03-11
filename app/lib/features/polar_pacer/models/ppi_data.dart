class PpiSample {
  final int ppMs;
  final int errorEstimateMs;
  final int hr;
  final bool blockerBit;
  final bool skinContactStatus;
  final bool skinContactSupported;

  const PpiSample({
    required this.ppMs,
    required this.errorEstimateMs,
    required this.hr,
    required this.blockerBit,
    required this.skinContactStatus,
    required this.skinContactSupported,
  });

  Map<String, dynamic> toJson() => {
    'pp_ms': ppMs,
    'pp_error_ms': errorEstimateMs,
    'hr': hr,
    'blocker': blockerBit,
    'skin_contact': skinContactStatus,
    'skin_contact_supported': skinContactSupported,
  };

  @override
  String toString() => 'PpiSample(ppMs=$ppMs, hr=$hr, blocker=$blockerBit)';
}

class PpiData {
  /// One notification frame from the Polar PMD PPI stream.
  /// Each sample is a single pulse-to-pulse interval derived from the
  /// optical PPG sensor. Samples with [PpiSample.blockerBit] == true
  /// indicate movement artefact and should be treated with caution.
  final List<PpiSample> samples;
  final DateTime timestamp;

  const PpiData({required this.samples, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'samples': samples.map((s) => s.toJson()).toList(),
    'timestamp': timestamp.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'PpiData(${samples.length} samples)';
}
