import 'dart:async';

import 'package:polar/polar.dart';

import '../features/polar/models/acc_data.dart';
import '../features/polar/models/hr_data.dart';
import '../features/polar_pacer/models/ppi_data.dart';
import 'polar_connection_state.dart';

class PolarPacerService {
  /// The 8-character Polar device ID. Defaults to the Polar Pacer DA2E2324;
  /// override via the POLAR_PACER_DEVICE_ID dart-define or constructor arg.
  final String deviceId;

  PolarPacerService({this.deviceId = 'DA2E2324'});

  // Shared singleton with PolarH10Service.
  static final _polar = Polar();

  final _connectionController =
      StreamController<PolarConnectionState>.broadcast();
  final _hrController = StreamController<HrData>.broadcast();
  final _accController = StreamController<AccData>.broadcast();
  final _ppiController = StreamController<PpiData>.broadcast();

  StreamSubscription<PolarDeviceInfo>? _connectingSub;
  StreamSubscription<PolarDeviceInfo>? _connectedSub;
  StreamSubscription<PolarDeviceDisconnectedEvent>? _disconnectedSub;
  StreamSubscription<PolarSdkFeatureReadyEvent>? _featureReadySub;
  StreamSubscription<PolarHrData>? _hrSub;
  StreamSubscription<PolarAccData>? _accSub;
  StreamSubscription<PolarPpiData>? _ppiSub;

  Stream<PolarConnectionState> get connectionState =>
      _connectionController.stream;
  Stream<HrData> get hrStream => _hrController.stream;
  Stream<AccData> get accStream => _accController.stream;
  Stream<PpiData> get ppiStream => _ppiController.stream;

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
          // HR and PPI use fixed BLE services — start immediately on connect.
          _startHrAndPpiStreaming();
        });

    // ACC (PMD stream) requires onlineStreaming feature to be ready.
    _featureReadySub = _polar.sdkFeatureReady
        .where(
          (e) =>
              _matchId(e.identifier) &&
              e.feature == PolarSdkFeature.onlineStreaming,
        )
        .listen((_) => _startAccStreaming());

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

  Future<void> _startHrAndPpiStreaming() async {
    _hrSub = _polar.startHrStreaming(deviceId).listen((data) {
      for (final s in data.samples) {
        if (!_hrController.isClosed) {
          _hrController.add(
            HrData(bpm: s.hr, rrMs: s.rrsMs, timestamp: DateTime.now()),
          );
        }
      }
    }, onError: (_) {});

    // PPI requires no settings — streams at the device's natural optical rate.
    _ppiSub = _polar.startPpiStreaming(deviceId).listen((data) {
      if (data.samples.isEmpty || _ppiController.isClosed) return;
      _ppiController.add(
        PpiData(
          samples: data.samples
              .map(
                (s) => PpiSample(
                  ppMs: s.ppi,
                  errorEstimateMs: s.errorEstimate,
                  hr: s.hr,
                  blockerBit: s.blockerBit,
                  skinContactStatus: s.skinContactStatus,
                  skinContactSupported: s.skinContactSupported,
                ),
              )
              .toList(),
          timestamp: DateTime.now(),
        ),
      );
    }, onError: (_) {});
  }

  Future<void> _startAccStreaming() async {
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
    _accController.close();
    _ppiController.close();
  }

  void _cancelStreamSubs() {
    _hrSub?.cancel();
    _accSub?.cancel();
    _ppiSub?.cancel();
    _hrSub = _accSub = _ppiSub = null;
  }

  bool _matchId(String id) => id.toUpperCase() == deviceId.toUpperCase();
}
