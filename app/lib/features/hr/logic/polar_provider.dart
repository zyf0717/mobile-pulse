import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/polar_h10_service.dart';
import '../../../services/relay_push_service.dart';

class PolarState {
  final PolarConnectionState connectionState;
  final int? latestBpm;
  final bool h10RelayActive;
  final RelayPushStatus hrRelayStatus;
  final RelayPushStatus ecgRelayStatus;
  final RelayPushStatus accRelayStatus;

  const PolarState({
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

  PolarState copyWith({
    PolarConnectionState? connectionState,
    int? latestBpm,
    bool? latestBpmSet,
    bool? h10RelayActive,
    RelayPushStatus? hrRelayStatus,
    RelayPushStatus? ecgRelayStatus,
    RelayPushStatus? accRelayStatus,
  }) => PolarState(
    connectionState: connectionState ?? this.connectionState,
    latestBpm: latestBpmSet == true ? null : (latestBpm ?? this.latestBpm),
    h10RelayActive: h10RelayActive ?? this.h10RelayActive,
    hrRelayStatus: hrRelayStatus ?? this.hrRelayStatus,
    ecgRelayStatus: ecgRelayStatus ?? this.ecgRelayStatus,
    accRelayStatus: accRelayStatus ?? this.accRelayStatus,
  );
}

class PolarNotifier extends Notifier<PolarState> {
  @override
  PolarState build() {
    final h10 = ref.watch(polarH10ServiceProvider);
    final hrRelay = ref.watch(hrRelayPushServiceProvider);
    final ecgRelay = ref.watch(ecgRelayPushServiceProvider);
    final accRelay = ref.watch(accRelayPushServiceProvider);

    final connSub = h10.connectionState.listen((s) {
      if (s == PolarConnectionState.disconnected ||
          s == PolarConnectionState.error) {
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

    return const PolarState();
  }

  Future<void> connect() => ref.read(polarH10ServiceProvider).connect();

  Future<void> disconnect() async {
    ref.read(hrRelayPushServiceProvider).stop();
    ref.read(ecgRelayPushServiceProvider).stop();
    ref.read(accRelayPushServiceProvider).stop();
    state = state.copyWith(
      h10RelayActive: false,
      hrRelayStatus: RelayPushStatus.idle,
      ecgRelayStatus: RelayPushStatus.idle,
      accRelayStatus: RelayPushStatus.idle,
    );
    await ref.read(polarH10ServiceProvider).disconnect();
  }

  void toggleH10Relay() {
    final hrRelay = ref.read(hrRelayPushServiceProvider);
    final ecgRelay = ref.read(ecgRelayPushServiceProvider);
    final accRelay = ref.read(accRelayPushServiceProvider);
    final h10 = ref.read(polarH10ServiceProvider);
    if (state.h10RelayActive) {
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
      hrRelay.start(h10.hrStream.map((hr) => hr.toJson()));
      ecgRelay.start(h10.ecgStream.map((ecg) => ecg.toJson()));
      accRelay.start(h10.accStream.map((acc) => acc.toJson()));
      state = state.copyWith(h10RelayActive: true);
    }
  }
}

final polarH10ServiceProvider = Provider<PolarH10Service>((ref) {
  const deviceId = String.fromEnvironment('POLAR_DEVICE_ID');
  return PolarH10Service(deviceId: deviceId);
});

final hrRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  const url = String.fromEnvironment('RELAY_HR_URL');
  return RelayPushService(relayUrl: url);
});

final ecgRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  const url = String.fromEnvironment('RELAY_ECG_URL');
  return RelayPushService(relayUrl: url);
});

final accRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  const url = String.fromEnvironment('RELAY_ACC_URL');
  return RelayPushService(relayUrl: url);
});

final polarNotifierProvider = NotifierProvider<PolarNotifier, PolarState>(
  PolarNotifier.new,
);
