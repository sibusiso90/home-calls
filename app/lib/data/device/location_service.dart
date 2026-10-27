import 'package:geolocator/geolocator.dart';

/// A GPS fix with its accuracy radius.
typedef GpsFix = ({double lat, double lng, double accuracyM, DateTime at});

/// Thin wrapper over geolocator so screens can be tested without GPS.
class LocationService {
  const LocationService();

  static const _settings = LocationSettings();

  /// Requests permission if needed. Returns a reason string when GPS is
  /// unavailable, or null when it is ready.
  Future<String?> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Location is switched off on this device.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.denied ||
      LocationPermission.deniedForever => 'Location permission was denied.',
      _ => null,
    };
  }

  Future<GpsFix?> currentFix({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (await ensureReady() != null) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(timeLimit: timeout),
      );
      return _fix(p);
    } on Object {
      return null;
    }
  }

  Stream<GpsFix> watch() =>
      Geolocator.getPositionStream(locationSettings: _settings).map(_fix);

  static GpsFix _fix(Position p) => (
    lat: p.latitude,
    lng: p.longitude,
    accuracyM: p.accuracy,
    at: p.timestamp,
  );
}
