import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/polar_h10_service.dart';
import '../../../services/relay_push_service.dart';

class PolarState {
  final PolarConnectionState connectionState;
  final int? latestBpm;
  final bool relayActive;
  final RelayPushStatus relayStatus;
  final bool ecgRelayActive;
  final RelayPushStatus ecgRelayStatus;
  final bool accRelayActive;
  final RelayPushStatus accRelayStatus;

  const PolarState({
    this.connectionState = PolarConnectionState.disconnected,
    this.latestBpm,
    this.relayActive = false,
    this.relayStatus = RelayPushStatus.idle,
    this.ecgRelayActive = false,
    this.ecgRelayStatus = RelayPushStatus.idle,
    this.accRelayActive = false,
    this.accRelayStatus = RelayPushStatus.idle,
  });

  PolarState copyWith({
    PolarConnectionState? connectionState,
    int? latestBpm,
    bool? latestBpmSet,
    bool? relayActive,
    RelayPushStatus? relayStatus,
    bool? ecgRelayActive,
    RelayPushStatus? ecgRelayStatus,
    bool? accRelayActive,
    RelayPushStatus? accRelayStatus,
  }) => PolarState(
    connectionState: connectionState ?? this.connectionState,
    latestBpm: latestBpmSet == true ? null : (latestBpm ?? this.latestBpm),
    relayActive: relayActive ?? this.relayActive,
    relayStatus: relayStatus ?? this.relayStatus,
    ecgRelayActive: ecgRelayActive ?? this.ecgRelayActive,
    ecgRelayStatus: ecgRelayStatus ?? this.ecgRelayStatus,
    accRelayActive: accRelayActive ?? this.accRelayActive,
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
          relayActive: false,
          relayStatus: RelayPushStatus.idle,
          ecgRelayActive: false,
          ecgRelayStatus: RelayPushStatus.idle,
          accRelayActive: false,
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
      (s) => state = state.copyWith(relayStatus: s),
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
      relayActive: false,
      relayStatus: RelayPushStatus.idle,
      ecgRelayActive: false,
      ecgRelayStatus: RelayPushStatus.idle,
      accRelayActive: false,
      accRelayStatus: RelayPushStatus.idle,
    );
    await ref.read(polarH10ServiceProvider).disconnect();
  }

  void toggleRelay() {
    final relay = ref.read(hrRelayPushServiceProvider);
    final h10 = ref.read(polarH10ServiceProvider);
    if (state.relayActive) {
      relay.stop();
      state = state.copyWith(
        relayActive: false,
        relayStatus: RelayPushStatus.idle,
      );
    } else {
      relay.start(h10.hrStream.map((hr) => hr.toJson()));
      state = state.copyWith(relayActive: true);
    }
  }

  void toggleEcgRelay() {
    final relay = ref.read(ecgRelayPushServiceProvider);
    final h10 = ref.read(polarH10ServiceProvider);
    if (state.ecgRelayActive) {
      relay.stop();
      state = state.copyWith(
        ecgRelayActive: false,
        ecgRelayStatus: RelayPushStatus.idle,
      );
    } else {
      relay.start(h10.ecgStream.map((ecg) => ecg.toJson()));
      state = state.copyWith(ecgRelayActive: true);
    }
  }

  void toggleAccRelay() {
    final relay = ref.read(accRelayPushServiceProvider);
    final h10 = ref.read(polarH10ServiceProvider);
    if (state.accRelayActive) {
      relay.stop();
      state = state.copyWith(
        accRelayActive: false,
        accRelayStatus: RelayPushStatus.idle,
      );
    } else {
      relay.start(h10.accStream.map((acc) => acc.toJson()));
      state = state.copyWith(accRelayActive: true);
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
