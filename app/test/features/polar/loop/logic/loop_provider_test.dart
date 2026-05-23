import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_pulse/features/polar/common/models/polar_connection_state.dart';
import 'package:mobile_pulse/features/polar/loop/logic/loop_provider.dart';
import 'package:mobile_pulse/features/polar/loop/logic/loop_service.dart';
import 'package:mobile_pulse/features/polar/loop/models/loop_models.dart';

class MockPolarLoopService extends Mock implements PolarLoopService {}

void main() {
  late MockPolarLoopService mockLoop;
  late StreamController<PolarConnectionState> connCtrl;
  late StreamController<PolarLoopError> errorCtrl;
  late StreamController<LoopDownloadProgress> progressCtrl;

  const settings = LoopSensorSettings(
    dataType: LoopOfflineDataType.acc,
    isFullSettings: false,
    values: {
      LoopSensorSettingType.sampleRate: [25, 50],
      LoopSensorSettingType.range: [4, 8],
    },
  );
  const fullSettings = LoopSensorSettings(
    dataType: LoopOfflineDataType.acc,
    isFullSettings: true,
    values: {
      LoopSensorSettingType.sampleRate: [12, 25, 50],
      LoopSensorSettingType.range: [2, 4, 8, 16],
    },
  );
  final deviceTime = LoopDeviceTime(
    localTime: DateTime.utc(2026, 5, 23, 9, 0),
    zoneId: 'UTC',
    offsetSeconds: 0,
  );
  final recording = LoopOfflineRecordingEntry(
    path: '/U/0/ACC/file.bin',
    sizeBytes: 2048,
    startedAt: DateTime(2026, 5, 23, 9, 15),
    dataType: LoopOfflineDataType.acc,
    exportConfirmed: false,
  );
  final exportedRecording = LoopOfflineRecordingEntry(
    path: '/U/0/ACC/file.bin',
    sizeBytes: 2048,
    startedAt: DateTime(2026, 5, 23, 9, 15),
    dataType: LoopOfflineDataType.acc,
    exportConfirmed: true,
  );
  const downloadProgress = LoopDownloadProgress(
    path: '/U/0/ACC/file.bin',
    bytesDownloaded: 1024,
    totalBytes: 2048,
    progressPercent: 50,
  );
  const summary = LoopOfflineRecordSummary(
    sampleCount: 100,
    firstSampleTimestampNs: 1,
    lastSampleTimestampNs: 100,
    metrics: {'min_x': -1, 'max_x': 2},
  );
  final downloadedRecord = LoopDownloadedRecord(
    entry: recording,
    downloadedAt: DateTime.utc(2026, 5, 23, 10, 0),
    selectedSettings: const {
      LoopSensorSettingType.sampleRate: [50],
      LoopSensorSettingType.range: [8],
    },
    summary: summary,
  );
  final exportedRecord = LoopExportedRecord(
    entry: exportedRecording,
    exportedAt: DateTime.utc(2026, 5, 23, 10, 5),
    rawFilePath: '/tmp/raw.bin',
    summaryFilePath: '/tmp/summary.json',
    summary: summary,
  );

  setUpAll(() {
    registerFallbackValue(LoopOfflineDataType.acc);
    registerFallbackValue(<LoopSensorSettingType, int>{});
  });

  setUp(() {
    mockLoop = MockPolarLoopService();
    connCtrl = StreamController<PolarConnectionState>.broadcast();
    errorCtrl = StreamController<PolarLoopError>.broadcast();
    progressCtrl = StreamController<LoopDownloadProgress>.broadcast();

    when(() => mockLoop.isConfigured).thenReturn(true);
    when(() => mockLoop.connectionState).thenAnswer((_) => connCtrl.stream);
    when(() => mockLoop.errorStream).thenAnswer((_) => errorCtrl.stream);
    when(
      () => mockLoop.downloadProgressStream,
    ).thenAnswer((_) => progressCtrl.stream);
    when(() => mockLoop.connect()).thenAnswer((_) async {});
    when(() => mockLoop.disconnect()).thenAnswer((_) async {});
    when(() => mockLoop.dispose()).thenAnswer((_) {});
    when(() => mockLoop.getDeviceTime()).thenAnswer((_) async => deviceTime);
    when(
      () => mockLoop.setDeviceTime(any()),
    ).thenAnswer((_) async => deviceTime);
    when(() => mockLoop.getAvailableOfflineDataTypes()).thenAnswer(
      (_) async => {LoopOfflineDataType.acc, LoopOfflineDataType.ppg},
    );
    when(
      () => mockLoop.requestOfflineRecordingSettings(any()),
    ).thenAnswer((_) async => settings);
    when(
      () => mockLoop.requestFullOfflineRecordingSettings(any()),
    ).thenAnswer((_) async => fullSettings);
    when(
      () => mockLoop.getActiveOfflineRecordingTypes(),
    ).thenAnswer((_) async => {LoopOfflineDataType.acc});
    when(
      () => mockLoop.startOfflineRecording(
        any(),
        selectedSettings: any(named: 'selectedSettings'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockLoop.stopOfflineRecording(any())).thenAnswer((_) async {});
    when(
      () => mockLoop.listOfflineRecordings(),
    ).thenAnswer((_) async => [recording]);
    when(
      () => mockLoop.downloadOfflineRecord(any()),
    ).thenAnswer((_) async => downloadedRecord);
    when(
      () => mockLoop.exportOfflineRecord(any()),
    ).thenAnswer((_) async => exportedRecord);
    when(() => mockLoop.deleteOfflineRecord(any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    await Future.wait([
      connCtrl.close(),
      errorCtrl.close(),
      progressCtrl.close(),
    ]);
  });

  ProviderContainer container({bool configured = true}) {
    when(() => mockLoop.isConfigured).thenReturn(configured);
    final c = ProviderContainer(
      overrides: [polarLoopServiceProvider.overrideWithValue(mockLoop)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('starts configured and disconnected', () {
    final state = container().read(loopNotifierProvider);
    expect(state.isConfigured, isTrue);
    expect(state.connectionState, PolarConnectionState.disconnected);
    expect(state.recordings, isEmpty);
  });

  test('connect is skipped when loop device is not configured', () async {
    final c = container(configured: false);

    await c.read(loopNotifierProvider.notifier).connect();

    verifyNever(() => mockLoop.connect());
  });

  test('connection and error streams update notifier state', () async {
    final c = container();
    c.read(loopNotifierProvider);

    connCtrl.add(PolarConnectionState.connected);
    await Future<void>.delayed(Duration.zero);
    expect(
      c.read(loopNotifierProvider).connectionState,
      PolarConnectionState.connected,
    );

    errorCtrl.add(const PolarLoopError(message: 'native failure'));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(loopNotifierProvider).lastError, 'native failure');

    connCtrl.add(PolarConnectionState.disconnected);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(loopNotifierProvider).activeOfflineRecordingTypes, isEmpty);
  });

  test('progress stream is stored by path', () async {
    final c = container();
    c.read(loopNotifierProvider);

    progressCtrl.add(downloadProgress);
    await Future<void>.delayed(Duration.zero);

    expect(
      c
          .read(loopNotifierProvider)
          .downloadProgressByPath[downloadProgress.path],
      downloadProgress,
    );
  });

  test('get/set device time update state', () async {
    final c = container();
    final notifier = c.read(loopNotifierProvider.notifier);

    await notifier.getDeviceTime();
    expect(c.read(loopNotifierProvider).deviceTime, deviceTime);

    await notifier.setDeviceTime(DateTime.utc(2026, 5, 23, 9, 5));
    expect(c.read(loopNotifierProvider).deviceTime, deviceTime);
    verify(() => mockLoop.setDeviceTime(any())).called(1);
  });

  test(
    'settings requests cache normal and full settings independently',
    () async {
      final c = container();
      final notifier = c.read(loopNotifierProvider.notifier);

      await notifier.requestOfflineRecordingSettings(LoopOfflineDataType.acc);
      await notifier.requestFullOfflineRecordingSettings(
        LoopOfflineDataType.acc,
      );

      final state = c.read(loopNotifierProvider);
      expect(state.normalSettingsByType[LoopOfflineDataType.acc], settings);
      expect(state.fullSettingsByType[LoopOfflineDataType.acc], fullSettings);
    },
  );

  test('start and stop offline recording refresh active status', () async {
    final c = container();
    final notifier = c.read(loopNotifierProvider.notifier);

    await notifier.startOfflineRecording(
      LoopOfflineDataType.acc,
      selectedSettings: const {
        LoopSensorSettingType.sampleRate: 50,
        LoopSensorSettingType.range: 8,
      },
    );
    expect(c.read(loopNotifierProvider).activeOfflineRecordingTypes, {
      LoopOfflineDataType.acc,
    });

    await notifier.stopOfflineRecording(LoopOfflineDataType.acc);
    expect(c.read(loopNotifierProvider).activeOfflineRecordingTypes, {
      LoopOfflineDataType.acc,
    });
    verify(
      () => mockLoop.startOfflineRecording(
        LoopOfflineDataType.acc,
        selectedSettings: const {
          LoopSensorSettingType.sampleRate: 50,
          LoopSensorSettingType.range: 8,
        },
      ),
    ).called(1);
    verify(
      () => mockLoop.stopOfflineRecording(LoopOfflineDataType.acc),
    ).called(1);
  });

  test('list and fetch available types update state', () async {
    final c = container();
    final notifier = c.read(loopNotifierProvider.notifier);

    await notifier.fetchAvailableOfflineDataTypes();
    await notifier.listOfflineRecordings();

    final state = c.read(loopNotifierProvider);
    expect(state.availableOfflineDataTypes, {
      LoopOfflineDataType.acc,
      LoopOfflineDataType.ppg,
    });
    expect(state.recordings, [recording]);
  });

  test('download stores record and clears progress for path', () async {
    final c = container();
    c.read(loopNotifierProvider);
    progressCtrl.add(downloadProgress);
    await Future<void>.delayed(Duration.zero);

    await c
        .read(loopNotifierProvider.notifier)
        .downloadOfflineRecord(downloadProgress.path);

    final state = c.read(loopNotifierProvider);
    expect(state.downloadsByPath[downloadProgress.path], downloadedRecord);
    expect(state.downloadProgressByPath, isEmpty);
  });

  test('export stores record and refreshes list', () async {
    var listCalls = 0;
    when(() => mockLoop.listOfflineRecordings()).thenAnswer((_) async {
      listCalls += 1;
      return listCalls == 1 ? [recording] : [exportedRecording];
    });

    final c = container();
    final notifier = c.read(loopNotifierProvider.notifier);

    await notifier.listOfflineRecordings();
    await notifier.exportOfflineRecord(recording.path);

    final state = c.read(loopNotifierProvider);
    expect(state.exportsByPath[recording.path], exportedRecord);
    expect(state.recordings, [exportedRecording]);
  });

  test('delete clears cached data and refreshes recordings', () async {
    var listCalls = 0;
    when(() => mockLoop.listOfflineRecordings()).thenAnswer((_) async {
      listCalls += 1;
      return listCalls == 1
          ? [exportedRecording]
          : <LoopOfflineRecordingEntry>[];
    });

    final c = container();
    final notifier = c.read(loopNotifierProvider.notifier);

    progressCtrl.add(downloadProgress);
    await Future<void>.delayed(Duration.zero);
    await notifier.downloadOfflineRecord(recording.path);
    await notifier.exportOfflineRecord(recording.path);
    await notifier.listOfflineRecordings();
    await notifier.deleteOfflineRecord(recording.path);

    final state = c.read(loopNotifierProvider);
    expect(state.downloadsByPath, isEmpty);
    expect(state.exportsByPath, isEmpty);
    expect(state.downloadProgressByPath, isEmpty);
    expect(state.recordings, isEmpty);
  });
}
