import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../services/app_logger.dart';
import '../../common/models/polar_connection_state.dart';
import '../models/loop_models.dart';

class PolarLoopError {
  final String message;
  final String? code;

  const PolarLoopError({required this.message, this.code});
}

class PolarLoopService {
  static const _methodChannel = MethodChannel(
    'com.example.mobile_pulse_loop/polar_loop/methods',
  );
  static const _eventChannel = EventChannel(
    'com.example.mobile_pulse_loop/polar_loop/events',
  );

  final String deviceId;

  final _connectionController =
      StreamController<PolarConnectionState>.broadcast();
  final _errorController = StreamController<PolarLoopError>.broadcast();
  final _downloadProgressController =
      StreamController<LoopDownloadProgress>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;

  PolarLoopService({this.deviceId = ''}) {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (_) {
        if (!_connectionController.isClosed) {
          _connectionController.add(PolarConnectionState.error);
        }
      },
    );
  }

  bool get isConfigured => deviceId.isNotEmpty;

  Stream<PolarConnectionState> get connectionState =>
      _connectionController.stream;
  Stream<PolarLoopError> get errorStream => _errorController.stream;
  Stream<LoopDownloadProgress> get downloadProgressStream =>
      _downloadProgressController.stream;

  Future<void> connect() async {
    if (!await _requestPermissions()) {
      _emitError('Bluetooth permissions denied');
      _connectionController.add(PolarConnectionState.error);
      return;
    }
    if (!isConfigured) {
      _emitError('POLAR_LOOP_DEVICE_ID is not set');
      _connectionController.add(PolarConnectionState.error);
      return;
    }
    if (!_connectionController.isClosed) {
      AppLogger.log(
        'Polar/Loop',
        'state=${PolarConnectionState.scanning.name}',
      );
      _connectionController.add(PolarConnectionState.scanning);
    }
    await _methodChannel.invokeMethod<void>('connect', {'deviceId': deviceId});
  }

  Future<void> disconnect() {
    AppLogger.log('Polar/Loop', 'disconnect requested');
    return _methodChannel.invokeMethod<void>('disconnect');
  }

  Future<LoopDeviceTime> getDeviceTime() async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'getDeviceTime',
    );
    return LoopDeviceTime.fromMap(result ?? const {});
  }

  Future<LoopDeviceTime> setDeviceTime(DateTime dateTime) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'setDeviceTime',
      {'localTime': dateTime.toIso8601String()},
    );
    return LoopDeviceTime.fromMap(result ?? const {});
  }

  Future<Set<LoopOfflineDataType>> getAvailableOfflineDataTypes() async {
    final result = await _methodChannel.invokeListMethod<String>(
      'getAvailableOfflineDataTypes',
    );
    return {
      for (final value in result ?? const <String>[])
        LoopOfflineDataType.fromWireName(value),
    };
  }

  Future<LoopSensorSettings> requestOfflineRecordingSettings(
    LoopOfflineDataType dataType,
  ) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'requestOfflineRecordingSettings',
      {'dataType': dataType.wireName, 'fullSettings': false},
    );
    return LoopSensorSettings.fromMap(result ?? const {});
  }

  Future<LoopSensorSettings> requestFullOfflineRecordingSettings(
    LoopOfflineDataType dataType,
  ) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'requestOfflineRecordingSettings',
      {'dataType': dataType.wireName, 'fullSettings': true},
    );
    return LoopSensorSettings.fromMap(result ?? const {});
  }

  Future<Set<LoopOfflineDataType>> getActiveOfflineRecordingTypes() async {
    final result = await _methodChannel.invokeListMethod<String>(
      'getOfflineRecordingStatus',
    );
    return {
      for (final value in result ?? const <String>[])
        LoopOfflineDataType.fromWireName(value),
    };
  }

  Future<void> startOfflineRecording(
    LoopOfflineDataType dataType, {
    Map<LoopSensorSettingType, int>? selectedSettings,
  }) {
    return _methodChannel.invokeMethod<void>('startOfflineRecording', {
      'dataType': dataType.wireName,
      'settings': selectedSettings == null
          ? null
          : {
              for (final entry in selectedSettings.entries)
                entry.key.wireName: entry.value,
            },
    });
  }

  Future<void> stopOfflineRecording(LoopOfflineDataType dataType) {
    return _methodChannel.invokeMethod<void>('stopOfflineRecording', {
      'dataType': dataType.wireName,
    });
  }

  Future<List<LoopOfflineRecordingEntry>> listOfflineRecordings() async {
    final result = await _methodChannel.invokeListMethod<dynamic>(
      'listOfflineRecordings',
    );
    return (result ?? const <dynamic>[])
        .map(
          (item) => LoopOfflineRecordingEntry.fromMap(
            Map<dynamic, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<LoopDownloadedRecord> downloadOfflineRecord(String path) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'downloadOfflineRecord',
      {'path': path},
    );
    return LoopDownloadedRecord.fromMap(result ?? const {});
  }

  Future<LoopExportedRecord> exportOfflineRecord(String path) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'exportOfflineRecord',
      {'path': path},
    );
    return LoopExportedRecord.fromMap(result ?? const {});
  }

  Future<void> deleteOfflineRecord(String path) {
    return _methodChannel.invokeMethod<void>('deleteOfflineRecord', {
      'path': path,
    });
  }

  void dispose() {
    _eventSubscription?.cancel();
    _connectionController.close();
    _errorController.close();
    _downloadProgressController.close();
  }

  Future<bool> _requestPermissions() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    return scan.isGranted && connect.isGranted;
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final mapped = Map<String, dynamic>.from(event);
    switch (mapped['type'] as String?) {
      case 'connection':
        final state = switch (mapped['state'] as String?) {
          'scanning' => PolarConnectionState.scanning,
          'connecting' => PolarConnectionState.connecting,
          'connected' => PolarConnectionState.connected,
          'error' => PolarConnectionState.error,
          _ => PolarConnectionState.disconnected,
        };
        if (!_connectionController.isClosed) {
          AppLogger.log('Polar/Loop', 'state=${state.name}');
          _connectionController.add(state);
        }
      case 'download_progress':
        if (_downloadProgressController.isClosed) return;
        _downloadProgressController.add(LoopDownloadProgress.fromMap(mapped));
      case 'error':
        _emitError(
          mapped['message'] as String? ?? 'Polar Loop error',
          code: mapped['code'] as String?,
        );
        if ((mapped['scope'] as String?) == 'connection' &&
            !_connectionController.isClosed) {
          _connectionController.add(PolarConnectionState.error);
        }
    }
  }

  void _emitError(String message, {String? code}) {
    AppLogger.log('Polar/Loop', code == null ? message : '$code: $message');
    if (_errorController.isClosed) return;
    _errorController.add(PolarLoopError(message: message, code: code));
  }
}
