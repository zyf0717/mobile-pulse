import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/app_env.dart';
import '../../common/logic/polar_relay_status.dart';
import '../../common/models/polar_connection_state.dart';
import '../../../../services/polar_h10_service.dart';
import '../../../../services/relay_push_service.dart';

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
  RelayPushStatus get h10RelayStatus => aggregateRelayStatus(
    active: h10RelayActive,
    statuses: [hrRelayStatus, ecgRelayStatus, accRelayStatus],
  );

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
  bool _startAllPending = false;

  @override
  PolarState build() {
    final h10 = ref.watch(polarH10ServiceProvider);
    final hrRelay = ref.watch(hrRelayPushServiceProvider);
    final ecgRelay = ref.watch(ecgRelayPushServiceProvider);
    final accRelay = ref.watch(accRelayPushServiceProvider);

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

    return const PolarState();
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
    final hrRelay = ref.read(hrRelayPushServiceProvider);
    final ecgRelay = ref.read(ecgRelayPushServiceProvider);
    final accRelay = ref.read(accRelayPushServiceProvider);
    final h10 = ref.read(polarH10ServiceProvider);
    hrRelay.start(h10.hrStream.map((hr) => hr.toJson()));
    ecgRelay.start(h10.ecgStream.map((ecg) => ecg.toJson()));
    accRelay.start(h10.accStream.map((acc) => acc.toJson()));
    state = state.copyWith(h10RelayActive: true);
  }

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
    if (state.h10RelayActive) {
      final hrRelay = ref.read(hrRelayPushServiceProvider);
      final ecgRelay = ref.read(ecgRelayPushServiceProvider);
      final accRelay = ref.read(accRelayPushServiceProvider);
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
  return PolarH10Service(deviceId: AppEnv.polarH10DeviceId);
});

final hrRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  return RelayPushService(
    relayUrl: AppEnv.relayH10HrUrl,
    relayUrlLabel: AppEnvKeys.relayH10HrUrl,
  );
});

final ecgRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  return RelayPushService(
    relayUrl: AppEnv.relayH10EcgUrl,
    relayUrlLabel: AppEnvKeys.relayH10EcgUrl,
  );
});

final accRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  return RelayPushService(
    relayUrl: AppEnv.relayH10AccUrl,
    relayUrlLabel: AppEnvKeys.relayH10AccUrl,
  );
});

final polarNotifierProvider = NotifierProvider<PolarNotifier, PolarState>(
  PolarNotifier.new,
);
