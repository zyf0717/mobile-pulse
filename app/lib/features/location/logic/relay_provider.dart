import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/relay_push_service.dart';
import 'location_provider.dart';

class RelayState {
  final bool active;
  final RelayPushStatus status;

  const RelayState({this.active = false, this.status = RelayPushStatus.idle});

  RelayState copyWith({bool? active, RelayPushStatus? status}) =>
      RelayState(active: active ?? this.active, status: status ?? this.status);
}

class RelayNotifier extends Notifier<RelayState> {
  @override
  RelayState build() {
    final service = ref.watch(relayPushServiceProvider);

    final sub = service.statusStream.listen(
      (s) => state = state.copyWith(status: s),
    );

    ref.onDispose(() {
      sub.cancel();
      service.dispose();
    });

    return const RelayState();
  }

  void toggle() {
    final service = ref.read(relayPushServiceProvider);
    final repository = ref.read(locationRepositoryProvider);

    if (state.active) {
      service.stop();
      state = state.copyWith(active: false, status: RelayPushStatus.idle);
    } else {
      service.start(repository.locationStream);
      state = state.copyWith(active: true);
    }
  }
}

final relayPushServiceProvider = Provider<RelayPushService>(
  (_) => RelayPushService(),
);

final relayNotifierProvider = NotifierProvider<RelayNotifier, RelayState>(
  RelayNotifier.new,
);
