import '../../../../services/relay_push_service.dart';

RelayPushStatus aggregateRelayStatus({
  required bool active,
  required Iterable<RelayPushStatus> statuses,
  bool allowPartialSuccess = false,
}) {
  if (!active) return RelayPushStatus.idle;
  if (allowPartialSuccess) {
    if (statuses.any((status) => status == RelayPushStatus.ok)) {
      return RelayPushStatus.ok;
    }
    if (statuses.any((status) => status == RelayPushStatus.error)) {
      return RelayPushStatus.error;
    }
    return RelayPushStatus.idle;
  }
  if (statuses.any((status) => status == RelayPushStatus.error)) {
    return RelayPushStatus.error;
  }
  if (statuses.every((status) => status == RelayPushStatus.ok)) {
    return RelayPushStatus.ok;
  }
  return RelayPushStatus.idle;
}
