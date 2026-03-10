import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/hr/models/hr_data.dart';

enum PolarConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class PolarH10Service {
  static const _hrServiceUuid = '180d';
  static const _hrCharUuid = '2a37';

  /// The 8-character Polar device ID shown in the Polar app (e.g. "6FFF5628").
  /// When non-empty, only a device whose advertised name contains this ID is
  /// accepted during scanning. When empty, the first Polar H10 found is used.
  final String deviceId;

  PolarH10Service({this.deviceId = ''});

  final _connectionController =
      StreamController<PolarConnectionState>.broadcast();
  final _hrController = StreamController<HrData>.broadcast();

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;

  Stream<PolarConnectionState> get connectionState =>
      _connectionController.stream;
  Stream<HrData> get hrStream => _hrController.stream;

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
        _notifySub?.cancel();
        if (!_connectionController.isClosed) {
          _connectionController.add(PolarConnectionState.disconnected);
        }
      }
    });

    // Discover the HR characteristic.
    final services = await device.discoverServices();
    BluetoothCharacteristic? hrChar;
    for (final svc in services) {
      if (svc.serviceUuid == Guid(_hrServiceUuid)) {
        for (final ch in svc.characteristics) {
          if (ch.characteristicUuid == Guid(_hrCharUuid)) {
            hrChar = ch;
            break;
          }
        }
        if (hrChar != null) break;
      }
    }

    if (hrChar == null) {
      if (!_connectionController.isClosed) {
        _connectionController.add(PolarConnectionState.error);
      }
      return;
    }

    await hrChar.setNotifyValue(true);
    _notifySub = hrChar.onValueReceived.listen((bytes) {
      if (bytes.length < 2) return;
      final bpm = _parseHrBpm(bytes);
      if (!_hrController.isClosed) {
        _hrController.add(HrData(bpm: bpm, timestamp: DateTime.now()));
      }
    });

    if (!_connectionController.isClosed) {
      _connectionController.add(PolarConnectionState.connected);
    }
  }

  Future<void> disconnect() async {
    await FlutterBluePlus.stopScan();
    await _notifySub?.cancel();
    await _connectionSub?.cancel();
    await _device?.disconnect();
    _device = null;
    if (!_connectionController.isClosed) {
      _connectionController.add(PolarConnectionState.disconnected);
    }
  }

  void dispose() {
    _notifySub?.cancel();
    _connectionSub?.cancel();
    _device?.disconnect();
    _connectionController.close();
    _hrController.close();
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

  /// Parses BPM from a Heart Rate Measurement characteristic value.
  /// Byte 0 flags: bit 0 = 0 → UINT8, bit 0 = 1 → UINT16.
  static int _parseHrBpm(List<int> bytes) {
    final isUint16 = (bytes[0] & 0x01) != 0;
    if (isUint16 && bytes.length >= 3) {
      return bytes[1] | (bytes[2] << 8);
    }
    return bytes[1];
  }
}
