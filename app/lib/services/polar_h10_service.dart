import 'dart:async';

import 'package:polar/polar.dart';

import '../features/polar/models/acc_data.dart';
import '../features/polar/models/hr_data.dart';
import '../features/polar_h10/models/ecg_data.dart';
import 'polar_connection_state.dart';
import 'polar_instance.dart';

export 'polar_connection_state.dart';

class PolarH10Service {
  /// The 8-character Polar device ID (e.g. "6FFF5628").
  final String deviceId;

  PolarH10Service({required this.deviceId});

  // App-wide shared Polar instance — see polar_instance.dart.
  static final _polar = sharedPolar;

  final _connectionController =
      StreamController<PolarConnectionState>.broadcast();
  final _hrController = StreamController<HrData>.broadcast();
  final _ecgController = StreamController<EcgData>.broadcast();
  final _accController = StreamController<AccData>.broadcast();

  StreamSubscription<PolarDeviceInfo>? _connectingSub;
  StreamSubscription<PolarDeviceInfo>? _connectedSub;
  StreamSubscription<PolarDeviceDisconnectedEvent>? _disconnectedSub;
  StreamSubscription<PolarSdkFeatureReadyEvent>? _featureReadySub;
  StreamSubscription<PolarHrData>? _hrSub;
  StreamSubscription<PolarEcgData>? _ecgSub;
  StreamSubscription<PolarAccData>? _accSub;

  Stream<PolarConnectionState> get connectionState =>
      _connectionController.stream;
  Stream<HrData> get hrStream => _hrController.stream;
  Stream<EcgData> get ecgStream => _ecgController.stream;
  Stream<AccData> get accStream => _accController.stream;

  Future<void> connect() async {
    if (_connectionController.isClosed) return;
    _connectionController.add(PolarConnectionState.scanning);

    _connectingSub?.cancel();
    _connectedSub?.cancel();
    _disconnectedSub?.cancel();

    _connectingSub = _polar.deviceConnecting
        .where((i) => _matchId(i.deviceId))
        .listen((_) {
          if (!_connectionController.isClosed) {
            _connectionController.add(PolarConnectionState.connecting);
          }
        });

    _connectedSub = _polar.deviceConnected
        .where((i) => _matchId(i.deviceId))
        .listen((_) {
          if (!_connectionController.isClosed) {
            _connectionController.add(PolarConnectionState.connected);
          }
          // Start HR immediately — it uses the standard BLE Heart Rate service.
          _startHrStreaming();
        });

    // ECG and ACC (PMD streams) require onlineStreaming feature to be ready.
    _featureReadySub = _polar.sdkFeatureReady
        .where(
          (e) =>
              _matchId(e.identifier) &&
              e.feature == PolarSdkFeature.onlineStreaming,
        )
        .listen((_) => _startPmdStreaming());

    _disconnectedSub = _polar.deviceDisconnected
        .where((e) => _matchId(e.info.deviceId))
        .listen((_) {
          _cancelStreamSubs();
          if (!_connectionController.isClosed) {
            _connectionController.add(PolarConnectionState.disconnected);
          }
        });

    try {
      await _polar.connectToDevice(deviceId);
    } catch (_) {
      if (!_connectionController.isClosed) {
        _connectionController.add(PolarConnectionState.error);
      }
    }
  }

  void _startHrStreaming() {
    _hrSub = _polar.startHrStreaming(deviceId).listen((data) {
      for (final s in data.samples) {
        if (!_hrController.isClosed) {
          _hrController.add(
            HrData(bpm: s.hr, rrMs: s.rrsMs, timestamp: DateTime.now()),
          );
        }
      }
    }, onError: (_) {});
  }

  Future<void> _startPmdStreaming() async {
    try {
      _ecgSub = _polar.startEcgStreaming(deviceId).listen((data) {
        if (data.samples.isEmpty || _ecgController.isClosed) return;
        _ecgController.add(
          EcgData(
            samples: data.samples.map((s) => s.voltage).toList(),
            timestamp: data.samples.first.timeStamp,
          ),
        );
      }, onError: (_) {});
    } catch (_) {}

    try {
      _accSub = _polar.startAccStreaming(deviceId).listen((data) {
        if (data.samples.isEmpty || _accController.isClosed) return;
        _accController.add(
          AccData(
            samples: data.samples
                .map((s) => {'x_mg': s.x, 'y_mg': s.y, 'z_mg': s.z})
                .toList(),
            timestamp: data.samples.first.timeStamp,
          ),
        );
      }, onError: (_) {});
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _cancelStreamSubs();
    await _connectingSub?.cancel();
    await _connectedSub?.cancel();
    await _disconnectedSub?.cancel();
    await _featureReadySub?.cancel();
    _connectingSub = _connectedSub = _disconnectedSub = _featureReadySub = null;
    try {
      await _polar.disconnectFromDevice(deviceId);
    } catch (_) {}
    if (!_connectionController.isClosed) {
      _connectionController.add(PolarConnectionState.disconnected);
    }
  }

  void dispose() {
    _cancelStreamSubs();
    _connectingSub?.cancel();
    _connectedSub?.cancel();
    _disconnectedSub?.cancel();
    _featureReadySub?.cancel();
    _connectionController.close();
    _hrController.close();
    _ecgController.close();
    _accController.close();
  }

  void _cancelStreamSubs() {
    _hrSub?.cancel();
    _ecgSub?.cancel();
    _accSub?.cancel();
    _hrSub = _ecgSub = _accSub = null;
  }

  bool _matchId(String id) => id.toUpperCase() == deviceId.toUpperCase();
}
