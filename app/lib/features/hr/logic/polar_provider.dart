import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/polar_h10_service.dart';
import '../../../services/relay_push_service.dart';

class PolarState {
  final PolarConnectionState connectionState;
  final int? latestBpm;
  final bool relayActive;
  final RelayPushStatus relayStatus;

  const PolarState({
    this.connectionState = PolarConnectionState.disconnected,
    this.latestBpm,
    this.relayActive = false,
    this.relayStatus = RelayPushStatus.idle,
  });

  PolarState copyWith({
    PolarConnectionState? connectionState,
    int? latestBpm,
    bool? latestBpmSet,
    bool? relayActive,
    RelayPushStatus? relayStatus,
  }) => PolarState(
    connectionState: connectionState ?? this.connectionState,
    latestBpm: latestBpmSet == true ? null : (latestBpm ?? this.latestBpm),
    relayActive: relayActive ?? this.relayActive,
    relayStatus: relayStatus ?? this.relayStatus,
  );
}

class PolarNotifier extends Notifier<PolarState> {
  @override
  PolarState build() {
    final h10 = ref.watch(polarH10ServiceProvider);
    final relay = ref.watch(hrRelayPushServiceProvider);

    final connSub = h10.connectionState.listen((s) {
      if (s == PolarConnectionState.disconnected ||
          s == PolarConnectionState.error) {
        // Auto-stop relay and clear BPM when connection drops.
        relay.stop();
        state = state.copyWith(
          connectionState: s,
          latestBpmSet: true, // clears latestBpm
          relayActive: false,
          relayStatus: RelayPushStatus.idle,
        );
      } else {
        state = state.copyWith(connectionState: s);
      }
    });

    final hrSub = h10.hrStream.listen((hr) {
      state = state.copyWith(latestBpm: hr.bpm);
    });

    final relaySub = relay.statusStream.listen((s) {
      state = state.copyWith(relayStatus: s);
    });

    ref.onDispose(() {
      connSub.cancel();
      hrSub.cancel();
      relaySub.cancel();
      h10.dispose();
      relay.dispose();
    });

    return const PolarState();
  }

  Future<void> connect() => ref.read(polarH10ServiceProvider).connect();

  Future<void> disconnect() async {
    ref.read(hrRelayPushServiceProvider).stop();
    state = state.copyWith(
      relayActive: false,
      relayStatus: RelayPushStatus.idle,
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
}

final polarH10ServiceProvider = Provider<PolarH10Service>((ref) {
  const deviceId = String.fromEnvironment('POLAR_DEVICE_ID');
  return PolarH10Service(deviceId: deviceId);
});

final hrRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  const hrUrl = String.fromEnvironment('RELAY_HR_URL');
  return RelayPushService(relayUrl: hrUrl);
});

final polarNotifierProvider = NotifierProvider<PolarNotifier, PolarState>(
  PolarNotifier.new,
);
