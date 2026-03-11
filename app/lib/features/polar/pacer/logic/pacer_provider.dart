import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/app_env.dart';
import '../../../../services/polar_pacer_service.dart';
import '../../../../services/relay_push_service.dart';
import '../../common/logic/polar_relay_status.dart';
import '../../common/models/polar_connection_state.dart';

class PacerState {
  final bool isConfigured;
  final PolarConnectionState connectionState;
  final int? latestBpm;
  final String? lastError;
  final bool pacerRelayActive;
  final RelayPushStatus hrRelayStatus;
  final RelayPushStatus accRelayStatus;
  final RelayPushStatus ppiRelayStatus;

  const PacerState({
    this.isConfigured = false,
    this.connectionState = PolarConnectionState.disconnected,
    this.latestBpm,
    this.lastError,
    this.pacerRelayActive = false,
    this.hrRelayStatus = RelayPushStatus.idle,
    this.accRelayStatus = RelayPushStatus.idle,
    this.ppiRelayStatus = RelayPushStatus.idle,
  });

  RelayPushStatus get pacerRelayStatus => aggregateRelayStatus(
    active: pacerRelayActive,
    statuses: [hrRelayStatus, accRelayStatus, ppiRelayStatus],
  );

  PacerState copyWith({
    bool? isConfigured,
    PolarConnectionState? connectionState,
    int? latestBpm,
    bool? latestBpmSet,
    String? lastError,
    bool? clearLastError,
    bool? pacerRelayActive,
    RelayPushStatus? hrRelayStatus,
    RelayPushStatus? accRelayStatus,
    RelayPushStatus? ppiRelayStatus,
  }) => PacerState(
    isConfigured: isConfigured ?? this.isConfigured,
    connectionState: connectionState ?? this.connectionState,
    latestBpm: latestBpmSet == true ? null : (latestBpm ?? this.latestBpm),
    lastError: clearLastError == true ? null : (lastError ?? this.lastError),
    pacerRelayActive: pacerRelayActive ?? this.pacerRelayActive,
    hrRelayStatus: hrRelayStatus ?? this.hrRelayStatus,
    accRelayStatus: accRelayStatus ?? this.accRelayStatus,
    ppiRelayStatus: ppiRelayStatus ?? this.ppiRelayStatus,
  );
}

class PacerNotifier extends Notifier<PacerState> {
  bool _startAllPending = false;

  @override
  PacerState build() {
    final pacer = ref.watch(polarPacerServiceProvider);
    final hrRelay = ref.watch(pacerHrRelayPushServiceProvider);
    final accRelay = ref.watch(pacerAccRelayPushServiceProvider);
    final ppiRelay = ref.watch(pacerPpiRelayPushServiceProvider);

    final connSub = pacer.connectionState.listen((s) {
      if (s == PolarConnectionState.disconnected ||
          s == PolarConnectionState.error) {
        _startAllPending = false;
        hrRelay.stop();
        accRelay.stop();
        ppiRelay.stop();
        state = state.copyWith(
          connectionState: s,
          latestBpmSet: true,
          clearLastError: s != PolarConnectionState.error,
          pacerRelayActive: false,
          hrRelayStatus: RelayPushStatus.idle,
          accRelayStatus: RelayPushStatus.idle,
          ppiRelayStatus: RelayPushStatus.idle,
        );
      } else {
        state = state.copyWith(connectionState: s);
        if (s == PolarConnectionState.connected && _startAllPending) {
          _startAllPending = false;
          _startPacerRelay();
        }
      }
    });

    final hrSub = pacer.hrStream.listen(
      (hr) => state = state.copyWith(latestBpm: hr.bpm),
    );
    final ppiSub = pacer.ppiStream.listen((ppi) {
      if (ppi.samples.isNotEmpty) {
        state = state.copyWith(latestBpm: ppi.samples.first.hr);
      }
    });
    final errorSub = pacer.errorStream.listen(
      (message) => state = state.copyWith(lastError: message),
    );
    final hrRelaySub = hrRelay.statusStream.listen(
      (s) => state = state.copyWith(hrRelayStatus: s),
    );
    final accRelaySub = accRelay.statusStream.listen(
      (s) => state = state.copyWith(accRelayStatus: s),
    );
    final ppiRelaySub = ppiRelay.statusStream.listen(
      (s) => state = state.copyWith(ppiRelayStatus: s),
    );

    ref.onDispose(() {
      connSub.cancel();
      hrSub.cancel();
      ppiSub.cancel();
      errorSub.cancel();
      hrRelaySub.cancel();
      accRelaySub.cancel();
      ppiRelaySub.cancel();
      pacer.dispose();
      hrRelay.dispose();
      accRelay.dispose();
      ppiRelay.dispose();
    });

    return PacerState(isConfigured: pacer.isConfigured);
  }

  Future<void> connect() async {
    if (!state.isConfigured) return;
    await ref.read(polarPacerServiceProvider).connect();
  }

  Future<void> connectAndStartRelay() {
    if (!state.isConfigured) return Future.value();
    if (state.connectionState == PolarConnectionState.connected) {
      if (!state.pacerRelayActive) return _startPacerRelay();
      return Future.value();
    }
    _startAllPending = true;
    return ref.read(polarPacerServiceProvider).connect();
  }

  Future<void> stopAll() async {
    _startAllPending = false;
    await disconnect();
  }

  Future<void> togglePacerRelay() async {
    if (state.pacerRelayActive) {
      await _stopPacerRelay();
    } else {
      await _startPacerRelay();
    }
  }

  Future<void> disconnect() async {
    await _stopPacerRelay();
    await ref.read(polarPacerServiceProvider).disconnect();
  }

  Future<void> _startPacerRelay() async {
    final hrRelay = ref.read(pacerHrRelayPushServiceProvider);
    final accRelay = ref.read(pacerAccRelayPushServiceProvider);
    final ppiRelay = ref.read(pacerPpiRelayPushServiceProvider);
    final pacer = ref.read(polarPacerServiceProvider);
    hrRelay.start(pacer.hrStream.map((hr) => hr.toJson()));
    accRelay.start(pacer.accStream.map((acc) => acc.toJson()));
    ppiRelay.start(pacer.ppiStream.map((ppi) => ppi.toJson()));
    await pacer.startRelayStreams();
    state = state.copyWith(pacerRelayActive: true, clearLastError: true);
  }

  Future<void> _stopPacerRelay() async {
    final hrRelay = ref.read(pacerHrRelayPushServiceProvider);
    final accRelay = ref.read(pacerAccRelayPushServiceProvider);
    final ppiRelay = ref.read(pacerPpiRelayPushServiceProvider);
    hrRelay.stop();
    accRelay.stop();
    ppiRelay.stop();
    await ref.read(polarPacerServiceProvider).stopRelayStreams();
    state = state.copyWith(
      pacerRelayActive: false,
      hrRelayStatus: RelayPushStatus.idle,
      accRelayStatus: RelayPushStatus.idle,
      ppiRelayStatus: RelayPushStatus.idle,
    );
  }
}

final polarPacerServiceProvider = Provider<PolarPacerService>((ref) {
  return PolarPacerService(deviceId: AppEnv.polarPacerDeviceId);
});

final pacerHrRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  return RelayPushService(
    relayUrl: AppEnv.relayPacerHrUrl,
    relayUrlLabel: AppEnvKeys.relayPacerHrUrl,
  );
});

final pacerAccRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  return RelayPushService(
    relayUrl: AppEnv.relayPacerAccUrl,
    relayUrlLabel: AppEnvKeys.relayPacerAccUrl,
  );
});

final pacerPpiRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  return RelayPushService(
    relayUrl: AppEnv.relayPacerPpiUrl,
    relayUrlLabel: AppEnvKeys.relayPacerPpiUrl,
  );
});

final pacerNotifierProvider = NotifierProvider<PacerNotifier, PacerState>(
  PacerNotifier.new,
);
