import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/polar_h10_service.dart';
import '../../../services/relay_push_service.dart';

class PolarH10State {
  final PolarConnectionState connectionState;
  final int? latestBpm;
  final bool h10RelayActive;
  final RelayPushStatus hrRelayStatus;
  final RelayPushStatus ecgRelayStatus;
  final RelayPushStatus accRelayStatus;

  const PolarH10State({
    this.connectionState = PolarConnectionState.disconnected,
    this.latestBpm,
    this.h10RelayActive = false,
    this.hrRelayStatus = RelayPushStatus.idle,
    this.ecgRelayStatus = RelayPushStatus.idle,
    this.accRelayStatus = RelayPushStatus.idle,
  });

  /// Aggregate status for the UI chip.
  /// error if any sub-relay errored; ok if all three confirmed ok;
  /// idle otherwise (inactive or still initialising).
  RelayPushStatus get h10RelayStatus {
    if (!h10RelayActive) return RelayPushStatus.idle;
    if (hrRelayStatus == RelayPushStatus.error ||
        ecgRelayStatus == RelayPushStatus.error ||
        accRelayStatus == RelayPushStatus.error) {
      return RelayPushStatus.error;
    }
    if (hrRelayStatus == RelayPushStatus.ok &&
        ecgRelayStatus == RelayPushStatus.ok &&
        accRelayStatus == RelayPushStatus.ok) {
      return RelayPushStatus.ok;
    }
    return RelayPushStatus.idle;
  }

  PolarH10State copyWith({
    PolarConnectionState? connectionState,
    int? latestBpm,
    bool? latestBpmSet,
    bool? h10RelayActive,
    RelayPushStatus? hrRelayStatus,
    RelayPushStatus? ecgRelayStatus,
    RelayPushStatus? accRelayStatus,
  }) => PolarH10State(
    connectionState: connectionState ?? this.connectionState,
    latestBpm: latestBpmSet == true ? null : (latestBpm ?? this.latestBpm),
    h10RelayActive: h10RelayActive ?? this.h10RelayActive,
    hrRelayStatus: hrRelayStatus ?? this.hrRelayStatus,
    ecgRelayStatus: ecgRelayStatus ?? this.ecgRelayStatus,
    accRelayStatus: accRelayStatus ?? this.accRelayStatus,
  );
}

class PolarH10Notifier extends Notifier<PolarH10State> {
  bool _startAllPending = false;

  @override
  PolarH10State build() {
    final h10 = ref.watch(polarH10ServiceProvider);
    final hrRelay = ref.watch(h10HrRelayPushServiceProvider);
    final ecgRelay = ref.watch(h10EcgRelayPushServiceProvider);
    final accRelay = ref.watch(h10AccRelayPushServiceProvider);

    final connSub = h10.connectionState.listen((s) {
      if (s == PolarConnectionState.disconnected ||
          s == PolarConnectionState.error) {
        _startAllPending = false;
        hrRelay.stop();
        ecgRelay.stop();
        accRelay.stop();
        state = state.copyWith(
          connectionState: s,
          latestBpmSet: true,
          h10RelayActive: false,
          hrRelayStatus: RelayPushStatus.idle,
          ecgRelayStatus: RelayPushStatus.idle,
          accRelayStatus: RelayPushStatus.idle,
        );
      } else {
        state = state.copyWith(connectionState: s);
        if (s == PolarConnectionState.connected && _startAllPending) {
          _startAllPending = false;
          _startH10Relay();
        }
      }
    });

    final hrSub = h10.hrStream.listen(
      (hr) => state = state.copyWith(latestBpm: hr.bpm),
    );
    final hrRelaySub = hrRelay.statusStream.listen(
      (s) => state = state.copyWith(hrRelayStatus: s),
    );
    final ecgRelaySub = ecgRelay.statusStream.listen(
      (s) => state = state.copyWith(ecgRelayStatus: s),
    );
    final accRelaySub = accRelay.statusStream.listen(
      (s) => state = state.copyWith(accRelayStatus: s),
    );

    ref.onDispose(() {
      connSub.cancel();
      hrSub.cancel();
      hrRelaySub.cancel();
      ecgRelaySub.cancel();
      accRelaySub.cancel();
      h10.dispose();
      hrRelay.dispose();
      ecgRelay.dispose();
      accRelay.dispose();
    });

    return const PolarH10State();
  }

  Future<void> connect() => ref.read(polarH10ServiceProvider).connect();

  /// Used by Start All: connect then auto-start the H10 relay once connected.
  Future<void> connectAndStartRelay() {
    if (state.connectionState == PolarConnectionState.connected) {
      if (!state.h10RelayActive) _startH10Relay();
      return Future.value();
    }
    _startAllPending = true;
    return ref.read(polarH10ServiceProvider).connect();
  }

  /// Used by Stop All: stop relay + disconnect.
  Future<void> stopAll() async {
    _startAllPending = false;
    await disconnect();
  }

  void _startH10Relay() {
    final hrRelay = ref.read(h10HrRelayPushServiceProvider);
    final ecgRelay = ref.read(h10EcgRelayPushServiceProvider);
    final accRelay = ref.read(h10AccRelayPushServiceProvider);
    final h10 = ref.read(polarH10ServiceProvider);
    hrRelay.start(h10.hrStream.map((hr) => hr.toJson()));
    ecgRelay.start(h10.ecgStream.map((ecg) => ecg.toJson()));
    accRelay.start(h10.accStream.map((acc) => acc.toJson()));
    state = state.copyWith(h10RelayActive: true);
  }

  Future<void> disconnect() async {
    ref.read(h10HrRelayPushServiceProvider).stop();
    ref.read(h10EcgRelayPushServiceProvider).stop();
    ref.read(h10AccRelayPushServiceProvider).stop();
    state = state.copyWith(
      h10RelayActive: false,
      hrRelayStatus: RelayPushStatus.idle,
      ecgRelayStatus: RelayPushStatus.idle,
      accRelayStatus: RelayPushStatus.idle,
    );
    await ref.read(polarH10ServiceProvider).disconnect();
  }

  void toggleH10Relay() {
    if (state.h10RelayActive) {
      final hrRelay = ref.read(h10HrRelayPushServiceProvider);
      final ecgRelay = ref.read(h10EcgRelayPushServiceProvider);
      final accRelay = ref.read(h10AccRelayPushServiceProvider);
      hrRelay.stop();
      ecgRelay.stop();
      accRelay.stop();
      state = state.copyWith(
        h10RelayActive: false,
        hrRelayStatus: RelayPushStatus.idle,
        ecgRelayStatus: RelayPushStatus.idle,
        accRelayStatus: RelayPushStatus.idle,
      );
    } else {
      _startH10Relay();
    }
  }
}

final polarH10ServiceProvider = Provider<PolarH10Service>((ref) {
  const deviceId = String.fromEnvironment('POLAR_H10_DEVICE_ID');
  return PolarH10Service(deviceId: deviceId);
});

final h10HrRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  const url = String.fromEnvironment('RELAY_H10_HR_URL');
  return RelayPushService(relayUrl: url);
});

final h10EcgRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  const url = String.fromEnvironment('RELAY_H10_ECG_URL');
  return RelayPushService(relayUrl: url);
});

final h10AccRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  const url = String.fromEnvironment('RELAY_H10_ACC_URL');
  return RelayPushService(relayUrl: url);
});

final polarH10NotifierProvider =
    NotifierProvider<PolarH10Notifier, PolarH10State>(PolarH10Notifier.new);
