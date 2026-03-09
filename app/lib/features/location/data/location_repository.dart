import '../../../services/location_service.dart';
import '../models/location_data.dart';

class LocationRepository {
  final LocationService _service;

  LocationRepository(this._service);

  Future<bool> requestPermission() => _service.requestPermission();

  Stream<LocationData> get locationStream => _service.locationStream;
}
