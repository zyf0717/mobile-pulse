import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_env.dart';
import '../../../services/pulse_service.dart';
import '../../../services/relay_push_service.dart';

class PulseState {
  final bool active;
  final RelayPushStatus status;

  const PulseState({this.active = false, this.status = RelayPushStatus.idle});

  PulseState copyWith({bool? active, RelayPushStatus? status}) =>
      PulseState(active: active ?? this.active, status: status ?? this.status);
}

class PulseNotifier extends Notifier<PulseState> {
  @override
  PulseState build() {
    final relay = ref.watch(pulseRelayPushServiceProvider);

    final sub = relay.statusStream.listen(
      (s) => state = state.copyWith(status: s),
    );

    ref.onDispose(() {
      sub.cancel();
      relay.dispose();
    });

    return const PulseState();
  }

  void toggle() {
    final relay = ref.read(pulseRelayPushServiceProvider);
    final pulse = ref.read(pulseServiceProvider);

    if (state.active) {
      relay.stop();
      state = state.copyWith(active: false, status: RelayPushStatus.idle);
    } else {
      relay.start(pulse.pulseStream.map((p) => p.toJson()));
      state = state.copyWith(active: true);
    }
  }

  void startIfInactive() {
    if (!state.active) toggle();
  }

  void stopIfActive() {
    if (state.active) toggle();
  }
}

final pulseServiceProvider = Provider<PulseService>((_) => PulseService());

final pulseRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  return RelayPushService(
    relayUrl: AppEnv.relayPulseUrl,
    relayUrlLabel: AppEnvKeys.relayPulseUrl,
  );
});

final pulseNotifierProvider = NotifierProvider<PulseNotifier, PulseState>(
  PulseNotifier.new,
);
