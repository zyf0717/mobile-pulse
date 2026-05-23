enum LoopOfflineDataType {
  hr('HR'),
  ecg('ECG'),
  acc('ACC'),
  ppg('PPG'),
  ppi('PPI'),
  gyro('GYRO'),
  magnetometer('MAGNETOMETER'),
  pressure('PRESSURE'),
  location('LOCATION'),
  temperature('TEMPERATURE'),
  skinTemperature('SKIN_TEMPERATURE');

  const LoopOfflineDataType(this.wireName);

  final String wireName;

  static LoopOfflineDataType fromWireName(String value) {
    return values.firstWhere(
      (type) => type.wireName == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unsupported offline data type',
      ),
    );
  }
}

enum LoopSensorSettingType {
  sampleRate('sample_rate'),
  resolution('resolution'),
  range('range'),
  channels('channels');

  const LoopSensorSettingType(this.wireName);

  final String wireName;

  static LoopSensorSettingType fromWireName(String value) {
    return values.firstWhere(
      (type) => type.wireName == value,
      orElse: () =>
          throw ArgumentError.value(value, 'value', 'Unsupported setting type'),
    );
  }
}

class LoopDeviceTime {
  final DateTime localTime;
  final String zoneId;
  final int offsetSeconds;

  const LoopDeviceTime({
    required this.localTime,
    required this.zoneId,
    required this.offsetSeconds,
  });

  factory LoopDeviceTime.fromMap(Map<dynamic, dynamic> map) {
    return LoopDeviceTime(
      localTime: DateTime.parse(map['local_time'] as String),
      zoneId: map['zone_id'] as String? ?? '',
      offsetSeconds: (map['offset_seconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class LoopSensorSettings {
  final LoopOfflineDataType dataType;
  final bool isFullSettings;
  final Map<LoopSensorSettingType, List<int>> values;

  const LoopSensorSettings({
    required this.dataType,
    required this.isFullSettings,
    required this.values,
  });

  factory LoopSensorSettings.fromMap(Map<dynamic, dynamic> map) {
    final rawValues = Map<String, dynamic>.from(
      map['values'] as Map<dynamic, dynamic>? ?? const {},
    );
    return LoopSensorSettings(
      dataType: LoopOfflineDataType.fromWireName(map['data_type'] as String),
      isFullSettings: map['full_settings'] as bool? ?? false,
      values: {
        for (final entry in rawValues.entries)
          LoopSensorSettingType.fromWireName(entry.key): List<int>.from(
            (entry.value as List<dynamic>? ?? const []).map(
              (value) => (value as num).toInt(),
            ),
          )..sort(),
      },
    );
  }

  Map<LoopSensorSettingType, int> get maxSelection => {
    for (final entry in values.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value.reduce(_max),
  };

  static int _max(int left, int right) => left > right ? left : right;
}

class LoopOfflineRecordingEntry {
  final String path;
  final int sizeBytes;
  final DateTime startedAt;
  final LoopOfflineDataType dataType;
  final bool exportConfirmed;

  const LoopOfflineRecordingEntry({
    required this.path,
    required this.sizeBytes,
    required this.startedAt,
    required this.dataType,
    required this.exportConfirmed,
  });

  factory LoopOfflineRecordingEntry.fromMap(Map<dynamic, dynamic> map) {
    return LoopOfflineRecordingEntry(
      path: map['path'] as String,
      sizeBytes: (map['size_bytes'] as num?)?.toInt() ?? 0,
      startedAt: DateTime.parse(map['started_at'] as String),
      dataType: LoopOfflineDataType.fromWireName(map['data_type'] as String),
      exportConfirmed: map['export_confirmed'] as bool? ?? false,
    );
  }
}

class LoopOfflineRecordSummary {
  final int sampleCount;
  final int? firstSampleTimestampNs;
  final int? lastSampleTimestampNs;
  final Map<String, Object?> metrics;

  const LoopOfflineRecordSummary({
    required this.sampleCount,
    required this.firstSampleTimestampNs,
    required this.lastSampleTimestampNs,
    required this.metrics,
  });

  factory LoopOfflineRecordSummary.fromMap(Map<dynamic, dynamic> map) {
    return LoopOfflineRecordSummary(
      sampleCount: (map['sample_count'] as num?)?.toInt() ?? 0,
      firstSampleTimestampNs: (map['first_sample_timestamp_ns'] as num?)
          ?.toInt(),
      lastSampleTimestampNs: (map['last_sample_timestamp_ns'] as num?)?.toInt(),
      metrics: _deepCastMap(
        map['metrics'] as Map<dynamic, dynamic>? ?? const {},
      ),
    );
  }
}

class LoopDownloadedRecord {
  final LoopOfflineRecordingEntry entry;
  final DateTime downloadedAt;
  final Map<LoopSensorSettingType, List<int>>? selectedSettings;
  final LoopOfflineRecordSummary summary;

  const LoopDownloadedRecord({
    required this.entry,
    required this.downloadedAt,
    required this.selectedSettings,
    required this.summary,
  });

  factory LoopDownloadedRecord.fromMap(Map<dynamic, dynamic> map) {
    return LoopDownloadedRecord(
      entry: LoopOfflineRecordingEntry.fromMap(
        Map<dynamic, dynamic>.from(map['entry'] as Map<dynamic, dynamic>),
      ),
      downloadedAt: DateTime.parse(map['downloaded_at'] as String),
      selectedSettings: _parseSelectedSettings(map['settings']),
      summary: LoopOfflineRecordSummary.fromMap(
        Map<dynamic, dynamic>.from(map['summary'] as Map<dynamic, dynamic>),
      ),
    );
  }
}

class LoopExportedRecord {
  final LoopOfflineRecordingEntry entry;
  final DateTime exportedAt;
  final String rawFilePath;
  final String summaryFilePath;
  final LoopOfflineRecordSummary summary;

  const LoopExportedRecord({
    required this.entry,
    required this.exportedAt,
    required this.rawFilePath,
    required this.summaryFilePath,
    required this.summary,
  });

  factory LoopExportedRecord.fromMap(Map<dynamic, dynamic> map) {
    return LoopExportedRecord(
      entry: LoopOfflineRecordingEntry.fromMap(
        Map<dynamic, dynamic>.from(map['entry'] as Map<dynamic, dynamic>),
      ),
      exportedAt: DateTime.parse(map['exported_at'] as String),
      rawFilePath: map['raw_file_path'] as String,
      summaryFilePath: map['summary_file_path'] as String,
      summary: LoopOfflineRecordSummary.fromMap(
        Map<dynamic, dynamic>.from(map['summary'] as Map<dynamic, dynamic>),
      ),
    );
  }
}

class LoopDownloadProgress {
  final String path;
  final int bytesDownloaded;
  final int totalBytes;
  final int progressPercent;

  const LoopDownloadProgress({
    required this.path,
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.progressPercent,
  });

  factory LoopDownloadProgress.fromMap(Map<dynamic, dynamic> map) {
    return LoopDownloadProgress(
      path: map['path'] as String,
      bytesDownloaded: (map['bytes_downloaded'] as num?)?.toInt() ?? 0,
      totalBytes: (map['total_bytes'] as num?)?.toInt() ?? 0,
      progressPercent: (map['progress_percent'] as num?)?.toInt() ?? 0,
    );
  }
}

Map<LoopSensorSettingType, List<int>>? _parseSelectedSettings(dynamic raw) {
  if (raw is! Map) return null;
  final mapped = Map<String, dynamic>.from(raw);
  return {
    for (final entry in mapped.entries)
      LoopSensorSettingType.fromWireName(entry.key): List<int>.from(
        (entry.value as List<dynamic>? ?? const []).map(
          (value) => (value as num).toInt(),
        ),
      )..sort(),
  };
}

Map<String, Object?> _deepCastMap(Map<dynamic, dynamic> source) {
  return {
    for (final entry in source.entries)
      entry.key.toString(): _deepCastValue(entry.value),
  };
}

Object? _deepCastValue(Object? value) {
  if (value is Map) {
    return _deepCastMap(Map<dynamic, dynamic>.from(value));
  }
  if (value is List) {
    return value.map(_deepCastValue).toList(growable: false);
  }
  return value;
}
