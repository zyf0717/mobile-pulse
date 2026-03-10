class HrData {
  final int bpm;
  final DateTime timestamp;

  const HrData({required this.bpm, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'bpm': bpm,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'HrData(bpm=$bpm)';
}
