class HrData {
  final int bpm;
  final List<int> rrMs;
  final DateTime timestamp;

  const HrData({
    required this.bpm,
    this.rrMs = const [],
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'bpm': bpm,
    'rr_ms': rrMs,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'HrData(bpm=$bpm)';
}
