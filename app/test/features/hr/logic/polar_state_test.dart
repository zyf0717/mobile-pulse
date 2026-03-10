import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/hr/logic/polar_provider.dart';
import 'package:mobile_pulse/services/polar_h10_service.dart';
import 'package:mobile_pulse/services/relay_push_service.dart';

void main() {
  group('PolarState defaults', () {
    test('initial state is fully idle / disconnected', () {
      const s = PolarState();
      expect(s.connectionState, PolarConnectionState.disconnected);
      expect(s.latestBpm, isNull);
      expect(s.relayActive, isFalse);
      expect(s.relayStatus, RelayPushStatus.idle);
      expect(s.ecgRelayActive, isFalse);
      expect(s.ecgRelayStatus, RelayPushStatus.idle);
      expect(s.accRelayActive, isFalse);
      expect(s.accRelayStatus, RelayPushStatus.idle);
    });
  });

  group('PolarState.copyWith', () {
    test('updates supplied fields and leaves others unchanged', () {
      const base = PolarState();
      final next = base.copyWith(
        connectionState: PolarConnectionState.connected,
        latestBpm: 72,
        relayActive: true,
        relayStatus: RelayPushStatus.ok,
      );

      expect(next.connectionState, PolarConnectionState.connected);
      expect(next.latestBpm, 72);
      expect(next.relayActive, isTrue);
      expect(next.relayStatus, RelayPushStatus.ok);
      // ECG and ACC fields stay at defaults.
      expect(next.ecgRelayActive, isFalse);
      expect(next.ecgRelayStatus, RelayPushStatus.idle);
      expect(next.accRelayActive, isFalse);
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
      final next = base.copyWith(relayActive: true);
      expect(next.latestBpm, 80);
    });

    test('ecgRelayActive and accRelayActive toggle independently', () {
      const base = PolarState();
      final s1 = base.copyWith(ecgRelayActive: true);
      expect(s1.ecgRelayActive, isTrue);
      expect(s1.accRelayActive, isFalse);

      final s2 = s1.copyWith(accRelayActive: true);
      expect(s2.ecgRelayActive, isTrue);
      expect(s2.accRelayActive, isTrue);
    });
  });
}
