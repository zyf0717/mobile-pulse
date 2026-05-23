import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/polar/loop/models/loop_models.dart';

void main() {
  group('LoopOfflineDataType.fromWireName', () {
    test('maps known wire values', () {
      expect(
        LoopOfflineDataType.fromWireName('SKIN_TEMPERATURE'),
        LoopOfflineDataType.skinTemperature,
      );
      expect(LoopOfflineDataType.fromWireName('ACC'), LoopOfflineDataType.acc);
    });

    test('throws for unknown wire values', () {
      expect(
        () => LoopOfflineDataType.fromWireName('NOPE'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('LoopSensorSettings', () {
    test('parses settings and exposes maxSelection', () {
      final settings = LoopSensorSettings.fromMap({
        'data_type': 'ACC',
        'full_settings': true,
        'values': {
          'sample_rate': [50, 12, 25],
          'range': [8, 2, 16, 4],
          'resolution': [16],
        },
      });

      expect(settings.dataType, LoopOfflineDataType.acc);
      expect(settings.isFullSettings, isTrue);
      expect(settings.values[LoopSensorSettingType.sampleRate], [12, 25, 50]);
      expect(settings.values[LoopSensorSettingType.range], [2, 4, 8, 16]);
      expect(settings.maxSelection, {
        LoopSensorSettingType.sampleRate: 50,
        LoopSensorSettingType.range: 16,
        LoopSensorSettingType.resolution: 16,
      });
    });
  });

  group('LoopDownloadedRecord.fromMap', () {
    test('parses nested settings and summary payload', () {
      final record = LoopDownloadedRecord.fromMap({
        'entry': {
          'path': '/U/0/ACC/file.bin',
          'size_bytes': 2048,
          'started_at': '2026-05-23T12:00:00',
          'data_type': 'ACC',
          'export_confirmed': false,
        },
        'downloaded_at': '2026-05-23T12:30:00Z',
        'settings': {
          'sample_rate': [50],
          'range': [8],
        },
        'summary': {
          'sample_count': 100,
          'first_sample_timestamp_ns': 1,
          'last_sample_timestamp_ns': 1000,
          'metrics': {
            'min_x': -1,
            'channels': [1, 2, 3],
            'nested': {'max_x': 10},
          },
        },
      });

      expect(record.entry.path, '/U/0/ACC/file.bin');
      expect(record.entry.dataType, LoopOfflineDataType.acc);
      expect(record.selectedSettings?[LoopSensorSettingType.sampleRate], [50]);
      expect(record.summary.sampleCount, 100);
      expect(record.summary.firstSampleTimestampNs, 1);
      expect(record.summary.metrics['channels'], [1, 2, 3]);
      expect(record.summary.metrics['nested'], {'max_x': 10});
    });
  });

  group('LoopExportedRecord.fromMap', () {
    test('parses exported file paths and summary', () {
      final record = LoopExportedRecord.fromMap({
        'entry': {
          'path': '/U/0/PPG/file.bin',
          'size_bytes': 512,
          'started_at': '2026-05-23T14:00:00',
          'data_type': 'PPG',
          'export_confirmed': true,
        },
        'exported_at': '2026-05-23T14:10:00Z',
        'raw_file_path': '/tmp/raw.bin',
        'summary_file_path': '/tmp/summary.json',
        'summary': {
          'sample_count': 22,
          'first_sample_timestamp_ns': 100,
          'last_sample_timestamp_ns': 200,
          'metrics': {'channel_count': 2},
        },
      });

      expect(record.entry.exportConfirmed, isTrue);
      expect(record.rawFilePath, '/tmp/raw.bin');
      expect(record.summaryFilePath, '/tmp/summary.json');
      expect(record.summary.metrics['channel_count'], 2);
    });
  });

  group('LoopDownloadProgress.fromMap', () {
    test('parses numeric progress values', () {
      final progress = LoopDownloadProgress.fromMap({
        'path': '/U/0/PPI/file.bin',
        'bytes_downloaded': 500,
        'total_bytes': 1000,
        'progress_percent': 50,
      });

      expect(progress.path, '/U/0/PPI/file.bin');
      expect(progress.bytesDownloaded, 500);
      expect(progress.totalBytes, 1000);
      expect(progress.progressPercent, 50);
    });
  });
}
