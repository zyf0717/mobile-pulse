import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pulse/features/polar/common/models/polar_connection_state.dart';
import 'package:mobile_pulse/features/polar/loop/logic/loop_provider.dart';
import 'package:mobile_pulse/features/polar/loop/models/loop_models.dart';

void main() {
  test('LoopState.copyWith clears lastError only when requested', () {
    const base = LoopState(
      connectionState: PolarConnectionState.connected,
      lastError: 'previous error',
      availableOfflineDataTypes: {LoopOfflineDataType.acc},
    );

    final retained = base.copyWith(connectionState: PolarConnectionState.error);
    final cleared = base.copyWith(clearLastError: true);

    expect(retained.lastError, 'previous error');
    expect(retained.connectionState, PolarConnectionState.error);
    expect(cleared.lastError, isNull);
    expect(cleared.availableOfflineDataTypes, {LoopOfflineDataType.acc});
  });
}
