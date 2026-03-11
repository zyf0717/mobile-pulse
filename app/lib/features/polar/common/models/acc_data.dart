class AccData {
  /// Acceleration samples in milli-g per axis.
  final List<Map<String, int>> samples;
  final int sampleRateHz;
  final DateTime timestamp;

  const AccData({
    required this.samples,
    required this.sampleRateHz,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'samples_mg': samples,
    'sample_rate_hz': sampleRateHz,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}
