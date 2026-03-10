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
          const _BottomPanel(),
        ],
      ),
    );
  }
}

// ── Bottom panel ─────────────────────────────────────────────────────────────

class _BottomPanel extends ConsumerWidget {
  const _BottomPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relay = ref.watch(relayNotifierProvider);
    final polar = ref.watch(polarNotifierProvider);
    final pNotifier = ref.read(polarNotifierProvider.notifier);
    final rNotifier = ref.read(relayNotifierProvider.notifier);

    final isConnected = polar.connectionState == PolarConnectionState.connected;
    final isIdle =
        polar.connectionState == PolarConnectionState.disconnected ||
        polar.connectionState == PolarConnectionState.error;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlRow(
            leading: _StatusChip(
              active: relay.active,
              status: relay.status,
              offLabel: 'GPS relay off',
              okLabel: 'GPS relay OK',
            ),
            trailing: _RelayButton(
              active: relay.active,
              pushLabel: 'Push GPS',
              onToggle: rNotifier.toggle,
            ),
          ),
          const Divider(height: 1),
          _ControlRow(
            leading: _H10StatusChip(polar: polar),
            trailing: SizedBox(
              width: 120,
              child: isIdle
                  ? OutlinedButton(
                      onPressed: pNotifier.connect,
                      child: const Text('Connect'),
                    )
                  : isConnected
                  ? OutlinedButton(
                      onPressed: pNotifier.disconnect,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Text('Disconnect'),
                    )
                  : const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
            ),
          ),
          _ControlRow(
            leading: _StatusChip(
              active: polar.relayActive,
              status: polar.relayStatus,
              offLabel: 'HR relay off',
              okLabel: 'HR relay OK',
            ),
            trailing: _RelayButton(
              active: polar.relayActive,
              pushLabel: 'Push HR',
              onToggle: isConnected ? pNotifier.toggleRelay : null,
            ),
          ),
          _ControlRow(
            leading: _StatusChip(
              active: polar.ecgRelayActive,
              status: polar.ecgRelayStatus,
              offLabel: 'ECG relay off',
              okLabel: 'ECG relay OK',
            ),
            trailing: _RelayButton(
              active: polar.ecgRelayActive,
              pushLabel: 'Push ECG',
              onToggle: isConnected ? pNotifier.toggleEcgRelay : null,
            ),
          ),
          _ControlRow(
            leading: _StatusChip(
              active: polar.accRelayActive,
              status: polar.accRelayStatus,
              offLabel: 'ACC relay off',
              okLabel: 'ACC relay OK',
            ),
            trailing: _RelayButton(
              active: polar.accRelayActive,
              pushLabel: 'Push ACC',
              onToggle: isConnected ? pNotifier.toggleAccRelay : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Layout primitive ──────────────────────────────────────────────────────────

class _ControlRow extends StatelessWidget {
  final Widget leading;
  final Widget trailing;
  const _ControlRow({required this.leading, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(child: leading),
          trailing,
        ],
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final bool active;
  final RelayPushStatus status;
  final String offLabel;
  final String okLabel;

  const _StatusChip({
    required this.active,
    required this.status,
    required this.offLabel,
    required this.okLabel,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String label;

    if (!active) {
      color = Colors.grey;
      icon = Icons.cloud_off_outlined;
      label = offLabel;
    } else if (status == RelayPushStatus.ok) {
      color = Colors.green;
      icon = Icons.cloud_done;
      label = okLabel;
    } else if (status == RelayPushStatus.error) {
      color = Colors.red;
      icon = Icons.cloud_off;
      label = '${offLabel.split(' ').first} error';
    } else {
      color = Colors.orange;
      icon = Icons.sync;
      label = 'Connecting…';
    }

    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── H10 status chip ───────────────────────────────────────────────────────────

class _H10StatusChip extends StatelessWidget {
  final PolarState polar;
  const _H10StatusChip({required this.polar});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (polar.connectionState) {
      PolarConnectionState.disconnected => (
        Colors.grey,
        Icons.bluetooth_disabled,
        'Polar H10',
      ),
      PolarConnectionState.scanning => (
        Colors.orange,
        Icons.bluetooth_searching,
        'Scanning…',
      ),
      PolarConnectionState.connecting => (
        Colors.blue,
        Icons.bluetooth_connected,
        'Connecting…',
      ),
      PolarConnectionState.connected => (
        Colors.green,
        Icons.bluetooth_connected,
        polar.latestBpm != null
            ? 'H10 — ${polar.latestBpm} bpm'
            : 'H10 — waiting…',
      ),
      PolarConnectionState.error => (
        Colors.red,
        Icons.bluetooth_disabled,
        'Not found / error',
      ),
    };

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Relay button ──────────────────────────────────────────────────────────────

class _RelayButton extends StatelessWidget {
  final bool active;
  final String pushLabel;
  final VoidCallback? onToggle;

  const _RelayButton({
    required this.active,
    required this.pushLabel,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: FilledButton(
        onPressed: onToggle,
        style: active
            ? FilledButton.styleFrom(backgroundColor: Colors.red)
            : null,
        child: Text(active ? 'Stop' : pushLabel),
      ),
    );
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
