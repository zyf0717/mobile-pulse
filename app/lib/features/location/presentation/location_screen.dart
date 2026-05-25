import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/location_provider.dart';
import '../logic/relay_provider.dart';
import '../models/location_data.dart';
import '../../pulse/logic/pulse_provider.dart';
import '../../polar/common/models/polar_connection_state.dart';
import '../../polar/h10/logic/polar_provider.dart';
import '../../polar/pacer/logic/pacer_provider.dart';
import '../../../services/relay_push_service.dart';

const double _controlButtonWidth = 152;
const double _screenPadding = 16;
const double _controlRowVerticalPadding = 6;
const double _sectionSpacing = 12;
const double _tileSpacing = 12;
const int _gpsPanelFlex = 3;
const int _controlsPanelFlex = 4;

class LocationScreen extends ConsumerWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(locationStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Polar Streams')),
      body: Column(
        children: [
          Expanded(
            flex: _gpsPanelFlex,
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
                  padding: const EdgeInsets.all(_screenPadding),
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
          const Expanded(flex: _controlsPanelFlex, child: _BottomPanel()),
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
    final h10 = ref.watch(polarNotifierProvider);
    final pacer = ref.watch(pacerNotifierProvider);
    final h10Notifier = ref.read(polarNotifierProvider.notifier);
    final pacerNotifier = ref.read(pacerNotifierProvider.notifier);
    final rNotifier = ref.read(relayNotifierProvider.notifier);
    final puNotifier = ref.read(pulseNotifierProvider.notifier);

    final h10Connected = h10.connectionState == PolarConnectionState.connected;
    final h10Idle =
        h10.connectionState == PolarConnectionState.disconnected ||
        h10.connectionState == PolarConnectionState.error;
    final pacerConnected =
        pacer.connectionState == PolarConnectionState.connected;
    final pacerIdle =
        pacer.connectionState == PolarConnectionState.disconnected ||
        pacer.connectionState == PolarConnectionState.error;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
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
              leading: _H10StatusChip(polar: h10),
              trailing: SizedBox(
                width: _controlButtonWidth,
                child: h10Idle
                    ? OutlinedButton(
                        onPressed: h10Notifier.connect,
                        child: const Text('Connect'),
                      )
                    : h10Connected
                    ? OutlinedButton(
                        onPressed: h10Notifier.disconnect,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        child: const Text('Disconnect'),
                      )
                    : OutlinedButton(
                        onPressed: null,
                        child: const Text(
                          'Connecting...',
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
              ),
            ),
            _ControlRow(
              leading: _StatusChip(
                active: h10.h10RelayActive,
                status: h10.h10RelayStatus,
                offLabel: 'H10 relay off',
                okLabel: 'H10 relay OK',
              ),
              trailing: _RelayButton(
                active: h10.h10RelayActive,
                pushLabel: 'Push H10',
                onToggle: h10Connected ? h10Notifier.toggleH10Relay : null,
              ),
            ),
            const Divider(height: 1),
            _ControlRow(
              leading: _PacerStatusChip(pacer: pacer),
              trailing: SizedBox(
                width: _controlButtonWidth,
                child: !pacer.isConfigured
                    ? const OutlinedButton(
                        onPressed: null,
                        child: Text('No ID', maxLines: 1, softWrap: false),
                      )
                    : pacerIdle
                    ? OutlinedButton(
                        onPressed: pacerNotifier.connect,
                        child: const Text('Connect'),
                      )
                    : pacerConnected
                    ? OutlinedButton(
                        onPressed: pacerNotifier.disconnect,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        child: const Text('Disconnect'),
                      )
                    : OutlinedButton(
                        onPressed: null,
                        child: const Text(
                          'Connecting...',
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
              ),
            ),
            _ControlRow(
              leading: _StatusChip(
                active: pacer.pacerRelayActive,
                status: pacer.pacerRelayStatus,
                offLabel: 'Pacer relay off',
                okLabel: 'Pacer relay OK',
                errorLabel: 'Relay error',
              ),
              trailing: _RelayButton(
                active: pacer.pacerRelayActive,
                pushLabel: 'Push Pacer',
                onToggle: pacerConnected
                    ? pacerNotifier.togglePacerRelay
                    : null,
              ),
            ),
            const Divider(height: 1),
            _StartStopAllButton(
              relay: relay,
              pulse: pulse,
              h10: h10,
              pacer: pacer,
              rNotifier: rNotifier,
              puNotifier: puNotifier,
              h10Notifier: h10Notifier,
              pacerNotifier: pacerNotifier,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Start All / Stop All button ───────────────────────────────────────────────

class _StartStopAllButton extends StatelessWidget {
  final RelayState relay;
  final PulseState pulse;
  final PolarState h10;
  final PacerState pacer;
  final RelayNotifier rNotifier;
  final PulseNotifier puNotifier;
  final PolarNotifier h10Notifier;
  final PacerNotifier pacerNotifier;

  const _StartStopAllButton({
    required this.relay,
    required this.pulse,
    required this.h10,
    required this.pacer,
    required this.rNotifier,
    required this.puNotifier,
    required this.h10Notifier,
    required this.pacerNotifier,
  });

  bool get _anyActive =>
      relay.active ||
      pulse.active ||
      h10.h10RelayActive ||
      h10.connectionState == PolarConnectionState.connected ||
      h10.connectionState == PolarConnectionState.scanning ||
      h10.connectionState == PolarConnectionState.connecting ||
      pacer.pacerRelayActive ||
      pacer.connectionState == PolarConnectionState.connected ||
      pacer.connectionState == PolarConnectionState.scanning ||
      pacer.connectionState == PolarConnectionState.connecting;

  @override
  Widget build(BuildContext context) {
    final stopping = _anyActive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _screenPadding,
        _sectionSpacing,
        _screenPadding,
        _controlRowVerticalPadding,
      ),
      child: Center(
        child: FilledButton(
          onPressed: () {
            if (stopping) {
              rNotifier.stopIfActive();
              puNotifier.stopIfActive();
              h10Notifier.stopAll();
              pacerNotifier.stopAll();
            } else {
              rNotifier.startIfInactive();
              puNotifier.startIfInactive();
              h10Notifier.connectAndStartRelay();
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
      padding: const EdgeInsets.symmetric(
        horizontal: _screenPadding,
        vertical: _controlRowVerticalPadding,
      ),
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
  final String? errorLabel;

  const _StatusChip({
    required this.active,
    required this.status,
    required this.offLabel,
    required this.okLabel,
    this.errorLabel,
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
      label = errorLabel ?? '${offLabel.split(' ').first} error';
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

class _PacerStatusChip extends StatelessWidget {
  final PacerState pacer;
  const _PacerStatusChip({required this.pacer});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (pacer.connectionState) {
      PolarConnectionState.disconnected => (
        Colors.grey,
        Icons.watch_outlined,
        'Polar Pacer',
      ),
      PolarConnectionState.scanning => (
        Colors.orange,
        Icons.bluetooth_searching,
        'Scanning…',
      ),
      PolarConnectionState.connecting => (
        Colors.blue,
        Icons.watch,
        'Connecting…',
      ),
      PolarConnectionState.connected => (
        Colors.green,
        Icons.watch,
        pacer.latestBpm != null
            ? 'Pacer — ${pacer.latestBpm} bpm'
            : 'Pacer — waiting…',
      ),
      PolarConnectionState.error => (
        Colors.red,
        Icons.watch_off,
        pacer.lastError ?? 'Pacer error',
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
      width: _controlButtonWidth,
      child: FilledButton(
        onPressed: onToggle,
        style: active
            ? FilledButton.styleFrom(backgroundColor: Colors.red)
            : null,
        child: Text(active ? 'Stop' : pushLabel, maxLines: 1, softWrap: false),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(_screenPadding, 8, _screenPadding, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tile(
            icon: Icons.location_on,
            label: 'Latitude',
            value: loc.latitude.toStringAsFixed(6),
          ),
          const SizedBox(height: _tileSpacing),
          _Tile(
            icon: Icons.location_on_outlined,
            label: 'Longitude',
            value: loc.longitude.toStringAsFixed(6),
          ),
          const SizedBox(height: _tileSpacing),
          _Tile(
            icon: Icons.speed,
            label: 'Speed',
            value: '${loc.speedKmh.toStringAsFixed(1)} km/h',
          ),
          const SizedBox(height: _tileSpacing),
          _Tile(
            icon: Icons.terrain,
            label: 'Altitude',
            value: '${loc.altitude.toStringAsFixed(1)} m',
          ),
          const SizedBox(height: _tileSpacing),
          _Tile(
            icon: Icons.gps_fixed,
            label: 'Accuracy',
            value: '±${loc.accuracy.toStringAsFixed(1)} m',
          ),
          const SizedBox(height: _sectionSpacing),
          Text(
            'Updated ${TimeOfDay.fromDateTime(loc.timestamp).format(context)}',
            style: textTheme.bodySmall,
          ),
        ],
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
        const SizedBox(width: _tileSpacing),
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
