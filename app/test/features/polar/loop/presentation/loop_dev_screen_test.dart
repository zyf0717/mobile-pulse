import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_pulse/features/polar/common/models/polar_connection_state.dart';
import 'package:mobile_pulse/features/polar/loop/logic/loop_provider.dart';
import 'package:mobile_pulse/features/polar/loop/logic/loop_service.dart';
import 'package:mobile_pulse/features/polar/loop/models/loop_models.dart';
import 'package:mobile_pulse/features/polar/loop/presentation/loop_dev_screen.dart';

class MockPolarLoopService extends Mock implements PolarLoopService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPolarLoopService mockLoop;
  late StreamController<PolarConnectionState> connCtrl;
  late StreamController<PolarLoopError> errorCtrl;
  late StreamController<LoopDownloadProgress> progressCtrl;

  final deviceTime = LoopDeviceTime(
    localTime: DateTime.utc(2026, 5, 24, 8, 0),
    zoneId: 'UTC',
    offsetSeconds: 0,
  );
  const normalSettings = LoopSensorSettings(
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
  final recording = LoopOfflineRecordingEntry(
    path: '/U/0/ACC/file.bin',
    sizeBytes: 2048,
    startedAt: DateTime(2026, 5, 24, 9, 0),
    dataType: LoopOfflineDataType.acc,
    exportConfirmed: false,
  );
  final exportedRecording = LoopOfflineRecordingEntry(
    path: '/U/0/ACC/file.bin',
    sizeBytes: 2048,
    startedAt: DateTime(2026, 5, 24, 9, 0),
    dataType: LoopOfflineDataType.acc,
    exportConfirmed: true,
  );
  const progress = LoopDownloadProgress(
    path: '/U/0/ACC/file.bin',
    bytesDownloaded: 1024,
    totalBytes: 2048,
    progressPercent: 50,
  );
  const summary = LoopOfflineRecordSummary(
    sampleCount: 100,
    firstSampleTimestampNs: 1,
    lastSampleTimestampNs: 99,
    metrics: {'min_x': -1, 'max_x': 2},
  );
  final downloadedRecord = LoopDownloadedRecord(
    entry: recording,
    downloadedAt: DateTime.utc(2026, 5, 24, 9, 15),
    selectedSettings: const {
      LoopSensorSettingType.sampleRate: [50],
      LoopSensorSettingType.range: [8],
    },
    summary: summary,
  );
  final exportedRecord = LoopExportedRecord(
    entry: exportedRecording,
    exportedAt: DateTime.utc(2026, 5, 24, 9, 20),
    rawFilePath: '/tmp/loop.raw',
    summaryFilePath: '/tmp/loop.summary.json',
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
    when(() => mockLoop.dispose()).thenAnswer((_) {});
    when(() => mockLoop.connect()).thenAnswer((_) async {
      connCtrl.add(PolarConnectionState.connected);
    });
    when(() => mockLoop.disconnect()).thenAnswer((_) async {});
    when(() => mockLoop.getDeviceTime()).thenAnswer((_) async => deviceTime);
    when(
      () => mockLoop.setDeviceTime(any()),
    ).thenAnswer((_) async => deviceTime);
    when(() => mockLoop.getAvailableOfflineDataTypes()).thenAnswer(
      (_) async => {LoopOfflineDataType.acc, LoopOfflineDataType.ppg},
    );
    when(
      () => mockLoop.requestOfflineRecordingSettings(any()),
    ).thenAnswer((_) async => normalSettings);
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

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [polarLoopServiceProvider.overrideWithValue(mockLoop)],
        child: const MaterialApp(home: LoopDevScreen()),
      ),
    );
    await tester.pump();
  }

  Future<void> connectDevice(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('loop-connect-button')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'fetches available types and full settings, then starts recording with selected defaults',
    (tester) async {
      await pumpScreen(tester);
      await connectDevice(tester);

      await tester.tap(find.byKey(const ValueKey('loop-fetch-types-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('loop-type-ACC')), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-type-PPG')), findsOneWidget);
      expect(find.text('Selected type'), findsOneWidget);
      expect(find.text('ACC'), findsWidgets);

      final fetchFullSettingsButton = find.byKey(
        const ValueKey('loop-fetch-full-settings-button'),
      );
      await tester.ensureVisible(fetchFullSettingsButton);
      await tester.pumpAndSettle();
      await tester.tap(fetchFullSettingsButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('loop-setting-sample_rate')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('loop-setting-range')), findsOneWidget);
      expect(find.text('sample_rate: 12, 25, 50'), findsOneWidget);
      expect(find.text('range: 2, 4, 8, 16'), findsOneWidget);

      final startButton = find.byKey(
        const ValueKey('loop-start-recording-button'),
      );
      await tester.ensureVisible(startButton);
      await tester.pumpAndSettle();
      await tester.tap(startButton);
      await tester.pumpAndSettle();

      verify(
        () => mockLoop.startOfflineRecording(
          LoopOfflineDataType.acc,
          selectedSettings: const {
            LoopSensorSettingType.sampleRate: 50,
            LoopSensorSettingType.range: 16,
          },
        ),
      ).called(1);
      expect(find.text('Active recording types'), findsOneWidget);
    },
  );

  testWidgets(
    'lists recordings, exports a record, and only enables delete after export confirmation',
    (tester) async {
      var listCalls = 0;
      when(() => mockLoop.listOfflineRecordings()).thenAnswer((_) async {
        listCalls += 1;
        return listCalls == 1 ? [recording] : [exportedRecording];
      });

      await pumpScreen(tester);
      await connectDevice(tester);

      final listButton = find.byKey(
        const ValueKey('loop-list-recordings-button'),
      );
      await tester.ensureVisible(listButton);
      await tester.pumpAndSettle();
      await tester.tap(listButton);
      await tester.pumpAndSettle();

      expect(find.text(recording.path), findsOneWidget);
      final deleteFinder = find.byKey(
        ValueKey('loop-recording-${recording.path}-delete'),
      );
      final disabledDelete = tester.widget<OutlinedButton>(deleteFinder);
      expect(disabledDelete.onPressed, isNull);

      await tester.tap(
        find.byKey(ValueKey('loop-recording-${recording.path}-export')),
      );
      await tester.pumpAndSettle();

      expect(find.text('/tmp/loop.raw'), findsOneWidget);
      expect(find.text('/tmp/loop.summary.json'), findsOneWidget);
      final enabledDelete = tester.widget<OutlinedButton>(deleteFinder);
      expect(enabledDelete.onPressed, isNotNull);

      await tester.tap(deleteFinder);
      await tester.pumpAndSettle();

      verify(() => mockLoop.exportOfflineRecord(recording.path)).called(1);
      verify(() => mockLoop.deleteOfflineRecord(recording.path)).called(1);
    },
  );

  testWidgets('renders download progress and downloaded summary state', (
    tester,
  ) async {
    when(
      () => mockLoop.listOfflineRecordings(),
    ).thenAnswer((_) async => [recording]);

    await pumpScreen(tester);
    await connectDevice(tester);

    progressCtrl.add(progress);
    await tester.pump();
    await tester.pump();

    final transferSection = find.text('Transfer & Export State');
    await tester.ensureVisible(transferSection);
    await tester.pumpAndSettle();
    expect(find.textContaining('50% (1024/2048 bytes)'), findsOneWidget);

    final listButton = find.byKey(
      const ValueKey('loop-list-recordings-button'),
    );
    await tester.ensureVisible(listButton);
    await tester.pumpAndSettle();
    await tester.tap(listButton);
    await tester.pumpAndSettle();
    final downloadButton = find.byKey(
      ValueKey('loop-recording-${recording.path}-download'),
    );
    await tester.ensureVisible(downloadButton);
    await tester.pumpAndSettle();
    await tester.tap(downloadButton);
    await tester.pumpAndSettle();

    expect(find.text('Selected settings'), findsOneWidget);
    expect(find.text('sample_rate=50, range=8'), findsOneWidget);
    expect(find.text('Samples'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('min_x: -1'), findsOneWidget);
  });
}
