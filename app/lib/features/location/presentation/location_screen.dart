import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/location_provider.dart';
import '../models/location_data.dart';

class LocationScreen extends ConsumerWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(locationStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('GPS Location')),
      body: locationAsync.when(
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

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
