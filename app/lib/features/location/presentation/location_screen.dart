import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/location_provider.dart';
import '../logic/relay_provider.dart';
import '../models/location_data.dart';
import '../../../services/relay_push_service.dart';
import '../../../services/polar_h10_service.dart';
import '../../polar_h10/logic/polar_h10_provider.dart';
import '../../polar_pacer/logic/polar_pacer_provider.dart';
import '../../pulse/logic/pulse_provider.dart';

class LocationScreen extends ConsumerWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(locationStreamProvider);

    return Scaffold(
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
    final pulse = ref.watch(pulseNotifierProvider);
    final polar = ref.watch(polarH10NotifierProvider);
    final pacer = ref.watch(polarPacerNotifierProvider);
    final pNotifier = ref.read(polarH10NotifierProvider.notifier);
    final pacerNotifier = ref.read(polarPacerNotifierProvider.notifier);
    final rNotifier = ref.read(relayNotifierProvider.notifier);
    final puNotifier = ref.read(pulseNotifierProvider.notifier);

    final h10Connected =
        polar.connectionState == PolarConnectionState.connected;
    final h10Idle =
        polar.connectionState == PolarConnectionState.disconnected ||
        polar.connectionState == PolarConnectionState.error;
    final pacerConnected =
        pacer.connectionState == PolarConnectionState.connected;
    final pacerIdle =
        pacer.connectionState == PolarConnectionState.disconnected ||
        pacer.connectionState == PolarConnectionState.error;

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
          _ControlRow(
            leading: _StatusChip(
              active: pulse.active,
              status: pulse.status,
              offLabel: 'Pulse relay off',
              okLabel: 'Pulse relay OK',
            ),
            trailing: _RelayButton(
              active: pulse.active,
              pushLabel: 'Push Pulse',
              onToggle: puNotifier.toggle,
            ),
          ),
          const Divider(height: 1),
          _ControlRow(
            leading: _H10StatusChip(polar: polar),
            trailing: _DeviceConnectButton(
              connectionState: polar.connectionState,
              isIdle: h10Idle,
              isConnected: h10Connected,
              onConnect: pNotifier.connect,
              onDisconnect: pNotifier.disconnect,
            ),
          ),
          _ControlRow(
            leading: _StatusChip(
              active: polar.h10RelayActive,
              status: polar.h10RelayStatus,
              offLabel: 'H10 relay off',
              okLabel: 'H10 relay OK',
            ),
            trailing: _RelayButton(
              active: polar.h10RelayActive,
              pushLabel: 'Push H10',
              onToggle: h10Connected ? pNotifier.toggleH10Relay : null,
            ),
          ),
          const Divider(height: 1),
          _ControlRow(
            leading: _PacerStatusChip(pacer: pacer),
            trailing: _DeviceConnectButton(
              connectionState: pacer.connectionState,
              isIdle: pacerIdle,
              isConnected: pacerConnected,
              onConnect: pacerNotifier.connect,
              onDisconnect: pacerNotifier.disconnect,
            ),
          ),
          _ControlRow(
            leading: _StatusChip(
              active: pacer.pacerRelayActive,
              status: pacer.pacerRelayStatus,
              offLabel: 'Pacer relay off',
              okLabel: 'Pacer relay OK',
            ),
            trailing: _RelayButton(
              active: pacer.pacerRelayActive,
              pushLabel: 'Push Pacer',
              onToggle: pacerConnected ? pacerNotifier.togglePacerRelay : null,
            ),
          ),
          const Divider(height: 1),
          _StartStopAllButton(
            relay: relay,
            pulse: pulse,
            polar: polar,
            pacer: pacer,
            rNotifier: rNotifier,
            puNotifier: puNotifier,
            pNotifier: pNotifier,
            pacerNotifier: pacerNotifier,
          ),
        ],
      ),
    );
  }
}

// ── Start All / Stop All button ───────────────────────────────────────────────

class _StartStopAllButton extends StatelessWidget {
  final RelayState relay;
  final PulseState pulse;
  final PolarH10State polar;
  final PolarPacerState pacer;
  final RelayNotifier rNotifier;
  final PulseNotifier puNotifier;
  final PolarH10Notifier pNotifier;
  final PolarPacerNotifier pacerNotifier;

  const _StartStopAllButton({
    required this.relay,
    required this.pulse,
    required this.polar,
    required this.pacer,
    required this.rNotifier,
    required this.puNotifier,
    required this.pNotifier,
    required this.pacerNotifier,
  });

  bool get _anyActive =>
      relay.active ||
      pulse.active ||
      polar.h10RelayActive ||
      polar.connectionState == PolarConnectionState.connected ||
      polar.connectionState == PolarConnectionState.scanning ||
      polar.connectionState == PolarConnectionState.connecting ||
      pacer.pacerRelayActive ||
      pacer.connectionState == PolarConnectionState.connected ||
      pacer.connectionState == PolarConnectionState.scanning ||
      pacer.connectionState == PolarConnectionState.connecting;

  @override
  Widget build(BuildContext context) {
    final stopping = _anyActive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Center(
        child: FilledButton(
          onPressed: () {
            if (stopping) {
              rNotifier.stopIfActive();
              puNotifier.stopIfActive();
              pNotifier.stopAll();
              pacerNotifier.stopAll();
            } else {
              rNotifier.startIfInactive();
              puNotifier.startIfInactive();
              pNotifier.connectAndStartRelay();
              pacerNotifier.connectAndStartRelay();
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: stopping ? Colors.red : null,
            minimumSize: const Size(180, 44),
          ),
          child: Text(stopping ? 'Stop All' : 'Start All'),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
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

// ── Device connect button (shared) ────────────────────────────────────────────

class _DeviceConnectButton extends StatelessWidget {
  final PolarConnectionState connectionState;
  final bool isIdle;
  final bool isConnected;
  final VoidCallback onConnect;
  final Future<void> Function() onDisconnect;

  const _DeviceConnectButton({
    required this.connectionState,
    required this.isIdle,
    required this.isConnected,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    if (isIdle) {
      return SizedBox(
        width: 120,
        child: OutlinedButton(
          onPressed: onConnect,
          child: const Text('Connect'),
        ),
      );
    }
    if (isConnected) {
      return SizedBox(
        width: 120,
        child: OutlinedButton(
          onPressed: onDisconnect,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
          ),
          child: const Text('Disconnect'),
        ),
      );
    }
    // scanning / connecting — disabled button with label
    return SizedBox(
      width: 120,
      child: OutlinedButton(onPressed: null, child: const Text('Connecting…')),
    );
  }
}

// ── H10 status chip ───────────────────────────────────────────────────────────

class _H10StatusChip extends StatelessWidget {
  final PolarH10State polar;
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

// ── Pacer status chip ─────────────────────────────────────────────────────────

class _PacerStatusChip extends StatelessWidget {
  final PolarPacerState pacer;
  const _PacerStatusChip({required this.pacer});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (pacer.connectionState) {
      PolarConnectionState.disconnected => (
        Colors.grey,
        Icons.bluetooth_disabled,
        'Polar Pacer',
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
        pacer.latestBpm != null
            ? 'Pacer — ${pacer.latestBpm} bpm'
            : 'Pacer — waiting…',
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
