import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:mobile_pulse/features/polar/common/models/polar_connection_state.dart';
import 'package:mobile_pulse/features/polar/loop/logic/loop_service.dart';
import 'package:mobile_pulse/features/polar/loop/models/loop_models.dart';

class _EventChannelMock {
  final MethodChannel _methodChannel;
  final Stream<dynamic> stream;
  StreamSubscription<dynamic>? _subscription;

  _EventChannelMock({required String channelName, required this.stream})
    : _methodChannel = MethodChannel(channelName) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodChannel, _handler);
  }

  Future<void> _handler(MethodCall call) async {
    switch (call.method) {
      case 'listen':
        _subscription = stream.listen(
          _sendSuccessEnvelope,
          onError: _sendErrorEnvelope,
          onDone: () => _sendEnvelope(null),
        );
      case 'cancel':
        await _subscription?.cancel();
    }
  }

  void _sendSuccessEnvelope(dynamic event) {
    _sendEnvelope(const StandardMethodCodec().encodeSuccessEnvelope(event));
  }

  void _sendErrorEnvelope(Object error) {
    if (error is PlatformException) {
      _sendEnvelope(
        const StandardMethodCodec().encodeErrorEnvelope(
          code: 'EVENT_ERROR',
          message: 'event error',
          details: null,
        ),
      );
      return;
    }
    _sendEnvelope(null);
  }

  void _sendEnvelope(ByteData? envelope) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(_methodChannel.name, envelope, (_) {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const loopMethodChannel = MethodChannel(
    'com.example.mobile_pulse/polar_loop/methods',
  );
  const loopEventChannelName = 'com.example.mobile_pulse/polar_loop/events';
  const permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );

  late StreamController<dynamic> eventCtrl;
  late List<MethodCall> loopCalls;
  Future<dynamic> Function(MethodCall call)? loopOverride;
  bool permissionsGranted = true;

  Map<int, int> permissionResponse() => {
    Permission.bluetoothScan.value: permissionsGranted ? 1 : 0,
    Permission.bluetoothConnect.value: permissionsGranted ? 1 : 0,
  };

  setUp(() {
    eventCtrl = StreamController<dynamic>();
    loopCalls = [];
    loopOverride = null;
    permissionsGranted = true;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
          if (call.method == 'requestPermissions') {
            return permissionResponse();
          }
          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(loopMethodChannel, (call) async {
          loopCalls.add(call);
          if (loopOverride != null) {
            return loopOverride!(call);
          }
          switch (call.method) {
            case 'connect':
            case 'disconnect':
            case 'startOfflineRecording':
            case 'stopOfflineRecording':
            case 'deleteOfflineRecord':
              return null;
            case 'getDeviceTime':
            case 'setDeviceTime':
              return {
                'local_time': '2026-05-23T09:00:00.000',
                'zone_id': 'UTC',
                'offset_seconds': 0,
              };
            case 'getAvailableOfflineDataTypes':
            case 'getOfflineRecordingStatus':
              return ['ACC', 'PPG'];
            case 'requestOfflineRecordingSettings':
              return {
                'data_type': 'ACC',
                'full_settings': call.arguments['fullSettings'] as bool,
                'values': {
                  'sample_rate': [25, 50],
                  'range': [4, 8],
                },
              };
            case 'listOfflineRecordings':
              return [
                {
                  'path': '/U/0/ACC/file.bin',
                  'size_bytes': 2048,
                  'started_at': '2026-05-23T09:15:00',
                  'data_type': 'ACC',
                  'export_confirmed': false,
                },
              ];
            case 'downloadOfflineRecord':
              return {
                'entry': {
                  'path': '/U/0/ACC/file.bin',
                  'size_bytes': 2048,
                  'started_at': '2026-05-23T09:15:00',
                  'data_type': 'ACC',
                  'export_confirmed': false,
                },
                'downloaded_at': '2026-05-23T09:30:00Z',
                'settings': {
                  'sample_rate': [50],
                  'range': [8],
                },
                'summary': {
                  'sample_count': 100,
                  'first_sample_timestamp_ns': 1,
                  'last_sample_timestamp_ns': 99,
                  'metrics': {'min_x': -1, 'max_x': 2},
                },
              };
            case 'exportOfflineRecord':
              return {
                'entry': {
                  'path': '/U/0/ACC/file.bin',
                  'size_bytes': 2048,
                  'started_at': '2026-05-23T09:15:00',
                  'data_type': 'ACC',
                  'export_confirmed': true,
                },
                'exported_at': '2026-05-23T09:35:00Z',
                'raw_file_path': '/tmp/raw.bin',
                'summary_file_path': '/tmp/summary.json',
                'summary': {
                  'sample_count': 100,
                  'first_sample_timestamp_ns': 1,
                  'last_sample_timestamp_ns': 99,
                  'metrics': {'min_x': -1, 'max_x': 2},
                },
              };
          }
          return null;
        });

    _EventChannelMock(
      channelName: loopEventChannelName,
      stream: eventCtrl.stream,
    );
  });

  tearDown(() async {
    await eventCtrl.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(loopMethodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(loopEventChannelName), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
  });

  test(
    'connect requests permissions, emits scanning, and invokes native connect',
    () async {
      final service = PolarLoopService(deviceId: 'LOOP1234');
      final states = <PolarConnectionState>[];
      final sub = service.connectionState.listen(states.add);
      addTearDown(sub.cancel);
      addTearDown(service.dispose);

      await service.connect();
      await Future<void>.delayed(Duration.zero);

      expect(states, contains(PolarConnectionState.scanning));
      expect(loopCalls.single.method, 'connect');
      expect(loopCalls.single.arguments, {'deviceId': 'LOOP1234'});
    },
  );

  test(
    'connect emits error and skips native call when permissions are denied',
    () async {
      permissionsGranted = false;
      final service = PolarLoopService(deviceId: 'LOOP1234');
      final states = <PolarConnectionState>[];
      final errors = <PolarLoopError>[];
      final stateSub = service.connectionState.listen(states.add);
      final errorSub = service.errorStream.listen(errors.add);
      addTearDown(stateSub.cancel);
      addTearDown(errorSub.cancel);
      addTearDown(service.dispose);

      await service.connect();
      await Future<void>.delayed(Duration.zero);

      expect(states, contains(PolarConnectionState.error));
      expect(errors.single.message, 'Bluetooth permissions denied');
      expect(loopCalls, isEmpty);
    },
  );

  test('get/set device time map platform payloads', () async {
    final service = PolarLoopService(deviceId: 'LOOP1234');
    addTearDown(service.dispose);

    final current = await service.getDeviceTime();
    final updated = await service.setDeviceTime(
      DateTime.utc(2026, 5, 23, 9, 5),
    );

    expect(current.zoneId, 'UTC');
    expect(current.offsetSeconds, 0);
    expect(updated.localTime, DateTime.parse('2026-05-23T09:00:00.000'));
    expect(loopCalls.map((c) => c.method), ['getDeviceTime', 'setDeviceTime']);
  });

  test('settings and recording methods map arguments and responses', () async {
    final service = PolarLoopService(deviceId: 'LOOP1234');
    addTearDown(service.dispose);

    final available = await service.getAvailableOfflineDataTypes();
    final normal = await service.requestOfflineRecordingSettings(
      LoopOfflineDataType.acc,
    );
    final full = await service.requestFullOfflineRecordingSettings(
      LoopOfflineDataType.acc,
    );

    await service.startOfflineRecording(
      LoopOfflineDataType.acc,
      selectedSettings: const {
        LoopSensorSettingType.sampleRate: 50,
        LoopSensorSettingType.range: 8,
      },
    );
    await service.stopOfflineRecording(LoopOfflineDataType.acc);

    expect(available, {LoopOfflineDataType.acc, LoopOfflineDataType.ppg});
    expect(normal.isFullSettings, isFalse);
    expect(full.isFullSettings, isTrue);
    expect(
      loopCalls
          .where((call) => call.method == 'startOfflineRecording')
          .single
          .arguments,
      {
        'dataType': 'ACC',
        'settings': {'sample_rate': 50, 'range': 8},
      },
    );
  });

  test('list, download, and export map nested payloads', () async {
    final service = PolarLoopService(deviceId: 'LOOP1234');
    addTearDown(service.dispose);

    final recordings = await service.listOfflineRecordings();
    final download = await service.downloadOfflineRecord('/U/0/ACC/file.bin');
    final export = await service.exportOfflineRecord('/U/0/ACC/file.bin');

    expect(recordings.single.dataType, LoopOfflineDataType.acc);
    expect(download.entry.path, '/U/0/ACC/file.bin');
    expect(download.selectedSettings?[LoopSensorSettingType.sampleRate], [50]);
    expect(export.entry.exportConfirmed, isTrue);
    expect(export.rawFilePath, '/tmp/raw.bin');
  });

  test('event channel updates connection, progress, and errors', () async {
    final service = PolarLoopService(deviceId: 'LOOP1234');
    final states = <PolarConnectionState>[];
    final progress = <LoopDownloadProgress>[];
    final errors = <PolarLoopError>[];
    final stateSub = service.connectionState.listen(states.add);
    final progressSub = service.downloadProgressStream.listen(progress.add);
    final errorSub = service.errorStream.listen(errors.add);
    addTearDown(stateSub.cancel);
    addTearDown(progressSub.cancel);
    addTearDown(errorSub.cancel);
    addTearDown(service.dispose);

    eventCtrl.add({'type': 'connection', 'state': 'connected'});
    await Future<void>.delayed(Duration.zero);
    eventCtrl.add({
      'type': 'download_progress',
      'path': '/U/0/ACC/file.bin',
      'bytes_downloaded': 100,
      'total_bytes': 200,
      'progress_percent': 50,
    });
    await Future<void>.delayed(Duration.zero);
    eventCtrl.add({
      'type': 'error',
      'scope': 'connection',
      'code': 'ERR_TIMEOUT',
      'message': 'Timed out',
    });
    await Future<void>.delayed(Duration.zero);

    expect(
      states,
      containsAllInOrder([
        PolarConnectionState.connected,
        PolarConnectionState.error,
      ]),
    );
    expect(progress.single.progressPercent, 50);
    expect(errors.single.code, 'ERR_TIMEOUT');
    expect(errors.single.message, 'Timed out');
  });
}
