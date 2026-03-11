class AccData {
  /// Acceleration samples in milli-g per axis at 200 Hz.
  final List<Map<String, int>> samples;
  final DateTime timestamp;

  const AccData({required this.samples, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'samples_mg': samples,
    'sample_rate_hz': 200,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}
