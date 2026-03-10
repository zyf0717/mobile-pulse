import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/location_provider.dart';
import '../logic/relay_provider.dart';
import '../models/location_data.dart';
import '../../../services/relay_push_service.dart';
import '../../../services/polar_h10_service.dart';
import '../../hr/logic/polar_provider.dart';

class LocationScreen extends ConsumerWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(locationStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mobile Pulse')),
      body: Column(
        children: [
          Expanded(
            child: locationAsync.when(
              data: (loc) => _LocationDisplay(loc: loc),
              loading: () => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Acquiring GPS fix…'),
                  ],
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'GPS error: $e',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          const _GpsRelayRow(),
          const Divider(height: 1),
          const _H10Section(),
        ],
      ),
    );
  }
}

// ── GPS relay row ────────────────────────────────────────────────────────────

class _GpsRelayRow extends ConsumerWidget {
  const _GpsRelayRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relay = ref.watch(relayNotifierProvider);
    return _RelayRow(
      status: relay.status,
      active: relay.active,
      label: 'GPS relay',
      pushLabel: 'Push GPS',
      onToggle: () => ref.read(relayNotifierProvider.notifier).toggle(),
      addSafeArea: false,
    );
  }
}

// ── Polar H10 section ────────────────────────────────────────────────────────

class _H10Section extends ConsumerWidget {
  const _H10Section();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final polar = ref.watch(polarNotifierProvider);
    final notifier = ref.read(polarNotifierProvider.notifier);

    final (
      btColor,
      btIcon,
      btLabel,
      canToggleRelay,
    ) = switch (polar.connectionState) {
      PolarConnectionState.disconnected => (
        Colors.grey,
        Icons.bluetooth_disabled,
        'Polar H10',
        false,
      ),
      PolarConnectionState.scanning => (
        Colors.orange,
        Icons.bluetooth_searching,
        'Scanning…',
        false,
      ),
      PolarConnectionState.connecting => (
        Colors.blue,
        Icons.bluetooth_connected,
        'Connecting…',
        false,
      ),
      PolarConnectionState.connected => (
        Colors.green,
        Icons.bluetooth_connected,
        polar.latestBpm != null
            ? 'Polar H10 — ${polar.latestBpm} bpm'
            : 'Polar H10 — waiting…',
        true,
      ),
      PolarConnectionState.error => (
        Colors.red,
        Icons.bluetooth_disabled,
        'Not found / error',
        false,
      ),
    };

    final isConnected = polar.connectionState == PolarConnectionState.connected;
    final isIdle =
        polar.connectionState == PolarConnectionState.disconnected ||
        polar.connectionState == PolarConnectionState.error;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(btIcon, color: btColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    btLabel,
                    style: TextStyle(
                      color: btColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isIdle)
                  OutlinedButton.icon(
                    onPressed: notifier.connect,
                    icon: const Icon(Icons.bluetooth, size: 18),
                    label: const Text('Connect'),
                  )
                else if (isConnected)
                  OutlinedButton.icon(
                    onPressed: notifier.disconnect,
                    icon: const Icon(Icons.bluetooth_disabled, size: 18),
                    label: const Text('Disconnect'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  )
                else
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _RelayRow(
              status: polar.relayStatus,
              active: polar.relayActive,
              label: 'HR relay',
              pushLabel: 'Push HR',
              onToggle: canToggleRelay ? notifier.toggleRelay : null,
              addSafeArea: false,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared relay row ─────────────────────────────────────────────────────────

class _RelayRow extends StatelessWidget {
  final RelayPushStatus status;
  final bool active;
  final String label;
  final String pushLabel;
  final VoidCallback? onToggle;
  final bool addSafeArea;

  const _RelayRow({
    required this.status,
    required this.active,
    required this.label,
    required this.pushLabel,
    required this.onToggle,
    required this.addSafeArea,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String statusLabel;

    if (!active) {
      color = Colors.grey;
      icon = Icons.cloud_off_outlined;
      statusLabel = '$label off';
    } else if (status == RelayPushStatus.ok) {
      color = Colors.green;
      icon = Icons.cloud_done;
      statusLabel = '$label OK';
    } else if (status == RelayPushStatus.error) {
      color = Colors.red;
      icon = Icons.cloud_off;
      statusLabel = '$label error';
    } else {
      color = Colors.orange;
      icon = Icons.sync;
      statusLabel = 'Connecting…';
    }

    final row = Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            statusLabel,
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onToggle,
            icon: Icon(active ? Icons.stop : Icons.play_arrow, size: 18),
            label: Text(active ? 'Stop' : pushLabel),
            style: active
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
          ),
        ],
      ),
    );

    return addSafeArea ? SafeArea(child: row) : row;
  }
}

// ── GPS data display ─────────────────────────────────────────────────────────

class _LocationDisplay extends StatelessWidget {
  final LocationData loc;
  const _LocationDisplay({required this.loc});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Tile(
              icon: Icons.location_on,
              label: 'Latitude',
              value: loc.latitude.toStringAsFixed(6),
            ),
            const SizedBox(height: 16),
            _Tile(
              icon: Icons.location_on_outlined,
              label: 'Longitude',
              value: loc.longitude.toStringAsFixed(6),
            ),
            const SizedBox(height: 16),
            _Tile(
              icon: Icons.speed,
              label: 'Speed',
              value: '${loc.speedKmh.toStringAsFixed(1)} km/h',
            ),
            const SizedBox(height: 16),
            _Tile(
              icon: Icons.terrain,
              label: 'Altitude',
              value: '${loc.altitude.toStringAsFixed(1)} m',
            ),
            const SizedBox(height: 16),
            _Tile(
              icon: Icons.gps_fixed,
              label: 'Accuracy',
              value: '±${loc.accuracy.toStringAsFixed(1)} m',
            ),
            const SizedBox(height: 24),
            Text(
              'Updated ${TimeOfDay.fromDateTime(loc.timestamp).format(context)}',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Tile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ],
    );
  }
}
