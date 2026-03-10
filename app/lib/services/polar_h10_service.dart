import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/hr/models/acc_data.dart';
import '../features/hr/models/ecg_data.dart';
import '../features/hr/models/hr_data.dart';

enum PolarConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class PolarH10Service {
  // ── Standard BT Heart Rate service ──────────────────────────────────────
  static const _hrServiceUuid = '180d';
  static const _hrCharUuid = '2a37';

  // ── Polar PMD service — proprietary ECG / ACC ────────────────────────────
  static const _pmdCpUuid = 'fb005c81-02e7-f387-1cad-8acd2d8df0c8';
  static const _pmdDataUuid = 'fb005c82-02e7-f387-1cad-8acd2d8df0c8';
  static const _measTypeEcg = 0x00;
  static const _measTypeAcc = 0x02;

  // Start ECG at 130 Hz / 14-bit resolution
  static final _ecgStartCmd = Uint8List.fromList([
    0x02, 0x00, 0x00,
    0x01, 0x82, 0x00, // SAMPLE_RATE=130
    0x01, 0x01, 0x0E, 0x00, // RESOLUTION=14
  ]);

  // Start ACC at 200 Hz / 16-bit resolution / 8 G range
  static final _accStartCmd = Uint8List.fromList([
    0x02, 0x02, 0x00,
    0x01, 0xC8, 0x00, // SAMPLE_RATE=200
    0x01, 0x01, 0x10, 0x00, // RESOLUTION=16
    0x02, 0x01, 0x08, 0x00, // RANGE=8G
  ]);

  /// The 8-character Polar device ID shown in the Polar app (e.g. "6FFF5628").
  /// When non-empty, only a device whose advertised name contains this ID is
  /// accepted during scanning. When empty, the first Polar H10 found is used.
  final String deviceId;

  PolarH10Service({this.deviceId = ''});

  final _connectionController =
      StreamController<PolarConnectionState>.broadcast();
  final _hrController = StreamController<HrData>.broadcast();
  final _ecgController = StreamController<EcgData>.broadcast();
  final _accController = StreamController<AccData>.broadcast();

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _hrNotifySub;
  StreamSubscription<List<int>>? _pmdDataSub;

  Stream<PolarConnectionState> get connectionState =>
      _connectionController.stream;
  Stream<HrData> get hrStream => _hrController.stream;
  Stream<EcgData> get ecgStream => _ecgController.stream;
  Stream<AccData> get accStream => _accController.stream;

  Future<void> connect() async {
    if (_connectionController.isClosed) return;
    _connectionController.add(PolarConnectionState.scanning);

    // Runtime permissions (Android 12+).
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    if (!scan.isGranted || !connect.isGranted) {
      _connectionController.add(PolarConnectionState.error);
      return;
    }

    // Check for an already-connected system device first (e.g. via Polar Flow).
    // A connected peripheral stops advertising, so scanning would never find it.
    BluetoothDevice? device = _findAmongConnected(
      FlutterBluePlus.connectedDevices,
    );

    if (device == null) {
      // Not already connected — run a BLE scan.
      final found = Completer<BluetoothDevice?>();
      StreamSubscription<List<ScanResult>>? scanSub;

      scanSub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          final name = r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : r.device.platformName;
          final matchesName = name.startsWith('Polar H10');
          final matchesId =
              deviceId.isEmpty ||
              name.toUpperCase().contains(deviceId.toUpperCase());
          if (matchesName && matchesId && !found.isCompleted) {
            found.complete(r.device);
            scanSub?.cancel();
          }
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [Guid(_hrServiceUuid)],
        timeout: const Duration(seconds: 15),
      );

      try {
        device = await found.future.timeout(const Duration(seconds: 17));
      } catch (_) {
        device = null;
      } finally {
        scanSub.cancel();
        await FlutterBluePlus.stopScan();
      }
    }

    if (device == null) {
      if (!_connectionController.isClosed) {
        _connectionController.add(PolarConnectionState.error);
      }
      return;
    }

    if (!_connectionController.isClosed) {
      _connectionController.add(PolarConnectionState.connecting);
    }
    _device = device;

    // Only call connect() if the device isn't already connected at the system
    // level (e.g. via Polar Flow). Calling connect() on an already-connected
    // device can throw or cause a double-bond on some Android versions.
    final alreadyConnected = device.isConnected;
    if (!alreadyConnected) {
      try {
        await device.connect(autoConnect: false);
      } catch (e) {
        if (!_connectionController.isClosed) {
          _connectionController.add(PolarConnectionState.error);
        }
        return;
      }
    }

    // Watch for unexpected disconnects.
    _connectionSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _hrNotifySub?.cancel();
        _pmdDataSub?.cancel();
        if (!_connectionController.isClosed) {
          _connectionController.add(PolarConnectionState.disconnected);
        }
      }
    });

    // Discover all services — find HR and PMD characteristics.
    final services = await device.discoverServices();
    BluetoothCharacteristic? hrChar;
    BluetoothCharacteristic? pmdCpChar;
    BluetoothCharacteristic? pmdDataChar;
    for (final svc in services) {
      for (final ch in svc.characteristics) {
        final uuid = ch.characteristicUuid.toString().toLowerCase();
        if (uuid == Guid(_hrCharUuid).toString().toLowerCase()) hrChar = ch;
        if (uuid == _pmdCpUuid) pmdCpChar = ch;
        if (uuid == _pmdDataUuid) pmdDataChar = ch;
      }
    }

    // Subscribe to HR measurement (BPM + RR intervals).
    if (hrChar != null) {
      await hrChar.setNotifyValue(true);
      _hrNotifySub = hrChar.onValueReceived.listen((bytes) {
        if (bytes.length < 2) return;
        if (!_hrController.isClosed) {
          _hrController.add(_parseHrMeasurement(bytes));
        }
      });
    }

    // Subscribe to PMD data and issue ECG + ACC start commands.
    if (pmdCpChar != null && pmdDataChar != null) {
      await pmdCpChar.setNotifyValue(true);
      await pmdDataChar.setNotifyValue(true);
      _pmdDataSub = pmdDataChar.onValueReceived.listen(_onPmdData);
      await pmdCpChar.write(_ecgStartCmd, withoutResponse: false);
      await pmdCpChar.write(_accStartCmd, withoutResponse: false);
    }

    if (!_connectionController.isClosed) {
      _connectionController.add(PolarConnectionState.connected);
    }
  }

  Future<void> disconnect() async {
    await FlutterBluePlus.stopScan();
    await _hrNotifySub?.cancel();
    await _pmdDataSub?.cancel();
    await _connectionSub?.cancel();
    await _device?.disconnect();
    _device = null;
    if (!_connectionController.isClosed) {
      _connectionController.add(PolarConnectionState.disconnected);
    }
  }

  void dispose() {
    _hrNotifySub?.cancel();
    _pmdDataSub?.cancel();
    _connectionSub?.cancel();
    _device?.disconnect();
    _connectionController.close();
    _hrController.close();
    _ecgController.close();
    _accController.close();
  }

  /// Returns the first device in [devices] that matches our Polar H10 criteria.
  BluetoothDevice? _findAmongConnected(List<BluetoothDevice> devices) {
    for (final d in devices) {
      final name = d.platformName;
      if (!name.startsWith('Polar H10')) continue;
      if (deviceId.isEmpty ||
          name.toUpperCase().contains(deviceId.toUpperCase())) {
        return d;
      }
    }
    return null;
  }

  // ── PMD data dispatcher ────────────────────────────────────────────────
  void _onPmdData(List<int> data) {
    if (data.isEmpty) return;
    switch (data[0]) {
      case _measTypeEcg:
        final ecg = _parseEcgFrame(data);
        if (ecg != null && !_ecgController.isClosed) _ecgController.add(ecg);
      case _measTypeAcc:
        final acc = _parseAccFrame(data);
        if (acc != null && !_accController.isClosed) _accController.add(acc);
    }
  }

  // ── HR Measurement (0x2A37) ────────────────────────────────────────────
  // flags byte 0: bit 0 = uint16 HR, bit 4 = RR intervals present
  static HrData _parseHrMeasurement(List<int> bytes) {
    final flags = bytes[0];
    final isUint16 = (flags & 0x01) != 0;
    final rrPresent = (flags & 0x10) != 0;
    var offset = 1;
    final int bpm;
    if (isUint16) {
      bpm = bytes[offset] | (bytes[offset + 1] << 8);
      offset += 2;
    } else {
      bpm = bytes[offset];
      offset += 1;
    }
    final rrMs = <int>[];
    if (rrPresent) {
      while (offset + 1 < bytes.length) {
        final raw = bytes[offset] | (bytes[offset + 1] << 8);
        offset += 2;
        rrMs.add((raw * 1000 / 1024).round());
      }
    }
    return HrData(bpm: bpm, rrMs: rrMs, timestamp: DateTime.now());
  }

  // ── ECG frame (PMD Type 0, uncompressed 24-bit signed) ─────────────────
  static EcgData? _parseEcgFrame(List<int> data) {
    if (data.length < 10) return null;
    final frameTypeByte = data[9];
    if ((frameTypeByte & 0x80) != 0 || (frameTypeByte & 0x7F) != 0) return null;
    final samples = <int>[];
    final payload = data.sublist(10);
    for (var i = 0; i + 2 < payload.length; i += 3) {
      final raw = payload[i] | (payload[i + 1] << 8) | (payload[i + 2] << 16);
      samples.add(raw >= 0x800000 ? raw - 0x1000000 : raw);
    }
    return EcgData(samples: samples, timestamp: DateTime.now());
  }

  // ── ACC frame (PMD Types 0 = int8, 1 = int16 LE, 2 = int24 LE) ────────────
  static AccData? _parseAccFrame(List<int> data) {
    if (data.length < 10) return null;
    final frameTypeByte = data[9];
    if ((frameTypeByte & 0x80) != 0) return null;
    final frameType = frameTypeByte & 0x7F;
    final payload = data.sublist(10);
    final samples = <Map<String, int>>[];
    switch (frameType) {
      case 0:
        for (var i = 0; i + 2 < payload.length; i += 3) {
          samples.add({
            'x_mg': _s8(payload[i]),
            'y_mg': _s8(payload[i + 1]),
            'z_mg': _s8(payload[i + 2]),
          });
        }
      case 1:
        for (var i = 0; i + 5 < payload.length; i += 6) {
          samples.add({
            'x_mg': _s16(payload, i),
            'y_mg': _s16(payload, i + 2),
            'z_mg': _s16(payload, i + 4),
          });
        }
      case 2:
        for (var i = 0; i + 8 < payload.length; i += 9) {
          samples.add({
            'x_mg': _s24(
              payload[i] | payload[i + 1] << 8 | payload[i + 2] << 16,
            ),
            'y_mg': _s24(
              payload[i + 3] | payload[i + 4] << 8 | payload[i + 5] << 16,
            ),
            'z_mg': _s24(
              payload[i + 6] | payload[i + 7] << 8 | payload[i + 8] << 16,
            ),
          });
        }
      default:
        return null;
    }
    return AccData(samples: samples, timestamp: DateTime.now());
  }

  static int _s8(int v) => v >= 0x80 ? v - 0x100 : v;
  static int _s16(List<int> b, int i) {
    final v = b[i] | (b[i + 1] << 8);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  static int _s24(int raw) => raw >= 0x800000 ? raw - 0x1000000 : raw;
}
