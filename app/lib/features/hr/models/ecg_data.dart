class EcgData {
  /// Signed 24-bit µV samples at 130 Hz (one notification = ~13 samples).
  final List<int> samples;
  final DateTime timestamp;

  const EcgData({required this.samples, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'samples_uv': samples,
    'sample_rate_hz': 130,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}
