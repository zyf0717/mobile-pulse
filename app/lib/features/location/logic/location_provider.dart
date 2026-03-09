import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/location_service.dart';
import '../data/location_repository.dart';
import '../models/location_data.dart';

final locationServiceProvider = Provider<LocationService>(
  (_) => LocationService(),
);

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => LocationRepository(ref.watch(locationServiceProvider)),
);

/// Emits the latest GPS fix, updating ~every second.
final locationStreamProvider = StreamProvider<LocationData>((ref) async* {
  final repo = ref.watch(locationRepositoryProvider);
  final granted = await repo.requestPermission();
  if (!granted) throw Exception('Location permission denied');
  yield* repo.locationStream;
});
