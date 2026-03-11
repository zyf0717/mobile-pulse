import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/polar_pacer/logic/polar_pacer_provider.dart';
import 'package:mobile_pulse/services/polar_connection_state.dart';
import 'package:mobile_pulse/services/relay_push_service.dart';

void main() {
  group('PolarPacerState defaults', () {
    test('initial state is fully idle / disconnected', () {
      const s = PolarPacerState();
      expect(s.connectionState, PolarConnectionState.disconnected);
      expect(s.latestBpm, isNull);
      expect(s.pacerRelayActive, isFalse);
      expect(s.hrRelayStatus, RelayPushStatus.idle);
      expect(s.accRelayStatus, RelayPushStatus.idle);
      expect(s.ppiRelayStatus, RelayPushStatus.idle);
      expect(s.pacerRelayStatus, RelayPushStatus.idle);
    });
  });

  group('PolarPacerState.copyWith', () {
    test('updates supplied fields and leaves others unchanged', () {
      const base = PolarPacerState();
      final next = base.copyWith(
        connectionState: PolarConnectionState.connected,
        latestBpm: 65,
        pacerRelayActive: true,
        hrRelayStatus: RelayPushStatus.ok,
      );

      expect(next.connectionState, PolarConnectionState.connected);
      expect(next.latestBpm, 65);
      expect(next.pacerRelayActive, isTrue);
      expect(next.hrRelayStatus, RelayPushStatus.ok);
      // ACC and PPI statuses stay at defaults.
      expect(next.accRelayStatus, RelayPushStatus.idle);
      expect(next.ppiRelayStatus, RelayPushStatus.idle);
    });

    test('latestBpmSet: true clears latestBpm to null', () {
      const base = PolarPacerState(latestBpm: 65);
      final next = base.copyWith(latestBpmSet: true);
      expect(next.latestBpm, isNull);
    });

    test('latestBpm in copyWith overrides previously stored value', () {
      const base = PolarPacerState(latestBpm: 60);
      final next = base.copyWith(latestBpm: 80);
      expect(next.latestBpm, 80);
    });

    test('omitting latestBpm preserves original value', () {
      const base = PolarPacerState(latestBpm: 72);
      final next = base.copyWith(pacerRelayActive: true);
      expect(next.latestBpm, 72);
    });
  });

  group('PolarPacerState.pacerRelayStatus (computed)', () {
    test('idle when pacerRelayActive is false regardless of sub-statuses', () {
      final s = const PolarPacerState().copyWith(
        hrRelayStatus: RelayPushStatus.ok,
        accRelayStatus: RelayPushStatus.ok,
        ppiRelayStatus: RelayPushStatus.ok,
      );
      expect(s.pacerRelayStatus, RelayPushStatus.idle);
    });

    test('ok when active and all three sub-relays report ok', () {
      final s = const PolarPacerState().copyWith(
        pacerRelayActive: true,
        hrRelayStatus: RelayPushStatus.ok,
        accRelayStatus: RelayPushStatus.ok,
        ppiRelayStatus: RelayPushStatus.ok,
      );
      expect(s.pacerRelayStatus, RelayPushStatus.ok);
    });

    test('error when active and any sub-relay reports error', () {
      final s = const PolarPacerState().copyWith(
        pacerRelayActive: true,
        hrRelayStatus: RelayPushStatus.ok,
        accRelayStatus: RelayPushStatus.ok,
        ppiRelayStatus: RelayPushStatus.error,
      );
      expect(s.pacerRelayStatus, RelayPushStatus.error);
    });

    test(
      'idle (initialising) when active but not all sub-relays confirmed ok',
      () {
        final s = const PolarPacerState().copyWith(
          pacerRelayActive: true,
          hrRelayStatus: RelayPushStatus.ok,
          accRelayStatus: RelayPushStatus.idle,
          ppiRelayStatus: RelayPushStatus.idle,
        );
        expect(s.pacerRelayStatus, RelayPushStatus.idle);
      },
    );
  });
}
