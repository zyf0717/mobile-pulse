import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/polar/common/models/acc_data.dart';
import '../features/polar/common/models/hr_data.dart';
import '../features/polar/common/models/polar_connection_state.dart';
import '../features/polar/common/models/ppi_data.dart';

class PolarPacerService {
  static const _methodChannel = MethodChannel(
    'com.example.mobile_pulse/polar_pacer/methods',
  );
  static const _eventChannel = EventChannel(
    'com.example.mobile_pulse/polar_pacer/events',
  );

  final String deviceId;

  final _connectionController =
      StreamController<PolarConnectionState>.broadcast();
  final _hrController = StreamController<HrData>.broadcast();
  final _accController = StreamController<AccData>.broadcast();
  final _ppiController = StreamController<PpiData>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;

  PolarPacerService({this.deviceId = ''}) {
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
  Stream<HrData> get hrStream => _hrController.stream;
  Stream<AccData> get accStream => _accController.stream;
  Stream<PpiData> get ppiStream => _ppiController.stream;
  Stream<String> get errorStream => _errorController.stream;

  Future<void> connect() async {
    if (!await _requestPermissions()) {
      if (!_connectionController.isClosed) {
        _connectionController.add(PolarConnectionState.error);
      }
      return;
    }
    if (!isConfigured) {
      if (!_connectionController.isClosed) {
        _connectionController.add(PolarConnectionState.error);
      }
      return;
    }
    if (!_connectionController.isClosed) {
      _connectionController.add(PolarConnectionState.scanning);
    }
    await _methodChannel.invokeMethod<void>('connect', {'deviceId': deviceId});
  }

  Future<void> disconnect() => _methodChannel.invokeMethod<void>('disconnect');

  Future<void> startRelayStreams() async {
    await _methodChannel.invokeMethod<void>('startAccStreaming');
    await _methodChannel.invokeMethod<void>('startPpiStreaming');
  }

  Future<void> stopRelayStreams() async {
    await _methodChannel.invokeMethod<void>('stopAccStreaming');
    await _methodChannel.invokeMethod<void>('stopPpiStreaming');
  }

  void dispose() {
    _eventSubscription?.cancel();
    _connectionController.close();
    _hrController.close();
    _accController.close();
    _ppiController.close();
    _errorController.close();
  }

  Future<bool> _requestPermissions() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    return scan.isGranted && connect.isGranted;
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final mapped = Map<String, dynamic>.from(event);
    final type = mapped['type'] as String?;
    switch (type) {
      case 'connection':
        final stateName = mapped['state'] as String?;
        final state = switch (stateName) {
          'scanning' => PolarConnectionState.scanning,
          'connecting' => PolarConnectionState.connecting,
          'connected' => PolarConnectionState.connected,
          'error' => PolarConnectionState.error,
          _ => PolarConnectionState.disconnected,
        };
        if (!_connectionController.isClosed) {
          _connectionController.add(state);
        }
      case 'hr':
        if (_hrController.isClosed) return;
        _hrController.add(
          HrData(
            bpm: mapped['bpm'] as int? ?? 0,
            rrMs: (mapped['rr_ms'] as List<dynamic>? ?? const [])
                .map((value) => value as int)
                .toList(),
            timestamp:
                DateTime.tryParse(mapped['timestamp'] as String? ?? '') ??
                DateTime.now(),
          ),
        );
      case 'acc':
        if (_accController.isClosed) return;
        final samples = (mapped['samples_mg'] as List<dynamic>? ?? const [])
            .map((sample) => Map<String, int>.from(sample as Map))
            .toList();
        _accController.add(
          AccData(
            samples: samples,
            sampleRateHz: mapped['sample_rate_hz'] as int? ?? 50,
            timestamp:
                DateTime.tryParse(mapped['timestamp'] as String? ?? '') ??
                DateTime.now(),
          ),
        );
      case 'ppi':
        if (_ppiController.isClosed) return;
        final samples = (mapped['samples'] as List<dynamic>? ?? const [])
            .map(
              (sample) => PpiSample(
                ppiMs: (sample as Map)['ppi_ms'] as int,
                errorEstimateMs: sample['error_estimate_ms'] as int,
                hr: sample['hr'] as int,
                blockerBit: sample['blocker_bit'] as bool,
                skinContactStatus: sample['skin_contact_status'] as bool,
                skinContactSupported: sample['skin_contact_supported'] as bool,
                timestampNs: sample['timestamp_ns'] as int,
              ),
            )
            .toList();
        _ppiController.add(
          PpiData(
            samples: samples,
            timestamp:
                DateTime.tryParse(mapped['timestamp'] as String? ?? '') ??
                DateTime.now(),
          ),
        );
      case 'error':
        final message =
            mapped['message'] as String? ?? 'Polar Pacer stream error';
        if (!_errorController.isClosed) {
          _errorController.add(message);
        }
        if (!_connectionController.isClosed) {
          _connectionController.add(PolarConnectionState.error);
        }
    }
  }
}
