import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/polar/common/models/polar_connection_state.dart';
import 'package:mobile_pulse/features/polar/h10/logic/polar_provider.dart';
import 'package:mobile_pulse/services/relay_push_service.dart';

void main() {
  group('PolarState defaults', () {
    test('initial state is fully idle / disconnected', () {
      const s = PolarState();
      expect(s.connectionState, PolarConnectionState.disconnected);
      expect(s.latestBpm, isNull);
      expect(s.h10RelayActive, isFalse);
      expect(s.hrRelayStatus, RelayPushStatus.idle);
      expect(s.ecgRelayStatus, RelayPushStatus.idle);
      expect(s.accRelayStatus, RelayPushStatus.idle);
      expect(s.h10RelayStatus, RelayPushStatus.idle);
    });
  });

  group('PolarState.copyWith', () {
    test('updates supplied fields and leaves others unchanged', () {
      const base = PolarState();
      final next = base.copyWith(
        connectionState: PolarConnectionState.connected,
        latestBpm: 72,
        h10RelayActive: true,
        hrRelayStatus: RelayPushStatus.ok,
      );

      expect(next.connectionState, PolarConnectionState.connected);
      expect(next.latestBpm, 72);
      expect(next.h10RelayActive, isTrue);
      expect(next.hrRelayStatus, RelayPushStatus.ok);
      expect(next.ecgRelayStatus, RelayPushStatus.idle);
      expect(next.accRelayStatus, RelayPushStatus.idle);
    });

    test('latestBpmSet: true clears latestBpm to null', () {
      const base = PolarState(latestBpm: 75);
      final next = base.copyWith(latestBpmSet: true);
      expect(next.latestBpm, isNull);
    });

    test('latestBpm in copyWith overrides previously stored value', () {
      const base = PolarState(latestBpm: 60);
      final next = base.copyWith(latestBpm: 90);
      expect(next.latestBpm, 90);
    });

    test('omitting latestBpm preserves original value', () {
      const base = PolarState(latestBpm: 80);
      final next = base.copyWith(h10RelayActive: true);
      expect(next.latestBpm, 80);
    });
  });

  group('PolarState.h10RelayStatus (computed)', () {
    test('idle when h10RelayActive is false regardless of sub-statuses', () {
      final s = const PolarState().copyWith(
        hrRelayStatus: RelayPushStatus.ok,
        ecgRelayStatus: RelayPushStatus.ok,
        accRelayStatus: RelayPushStatus.ok,
      );
      expect(s.h10RelayStatus, RelayPushStatus.idle);
    });

    test('ok when active and all three sub-relays report ok', () {
      final s = const PolarState().copyWith(
        h10RelayActive: true,
        hrRelayStatus: RelayPushStatus.ok,
        ecgRelayStatus: RelayPushStatus.ok,
        accRelayStatus: RelayPushStatus.ok,
      );
      expect(s.h10RelayStatus, RelayPushStatus.ok);
    });

    test('error when active and any sub-relay reports error', () {
      final s = const PolarState().copyWith(
        h10RelayActive: true,
        hrRelayStatus: RelayPushStatus.ok,
        ecgRelayStatus: RelayPushStatus.error,
        accRelayStatus: RelayPushStatus.ok,
      );
      expect(s.h10RelayStatus, RelayPushStatus.error);
    });

    test(
      'idle (initialising) when active but not all sub-relays confirmed ok',
      () {
        final s = const PolarState().copyWith(
          h10RelayActive: true,
          hrRelayStatus: RelayPushStatus.ok,
          ecgRelayStatus: RelayPushStatus.idle,
          accRelayStatus: RelayPushStatus.idle,
        );
        expect(s.h10RelayStatus, RelayPushStatus.idle);
      },
    );
  });
}
