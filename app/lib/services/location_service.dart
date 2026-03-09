import 'package:geolocator/geolocator.dart';

import '../features/location/models/location_data.dart';

class LocationService {
  /// Requests location permission if not already granted.
  /// Returns true when the app has usable permission.
  Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Emits a new [LocationData] roughly every second.
  Stream<LocationData> get locationStream => Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      intervalDuration: const Duration(seconds: 1),
      distanceFilter: 0,
    ),
  ).map(LocationData.fromPosition);
}
