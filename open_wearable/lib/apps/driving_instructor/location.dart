import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// The geolocator library provides asynchronous access to the location,
/// this is problematic for other parts of the app that need synchronous access.
///
/// This singleton class wraps the geolocator and provides synchronous access
/// to the current location after an initial asynchronous setup.
///
/// This works by starting the stream in the background and it updating the
/// current location whenever a new location is received.
class CurrentLocationTracker {
  static final CurrentLocationTracker _instance =
      CurrentLocationTracker._internal();
  late StreamSubscription<Position> positionStream;
  LatLng? _currentLocation;

  factory CurrentLocationTracker() {
    return _instance;
  }

  CurrentLocationTracker._internal() {
    final LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 100,
    );

    positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position? position) {
      if (position != null) {
        _currentLocation = LatLng(position.latitude, position.longitude);
      }
    });
  }

  Future<void> init() async {
    // If we already have a location, no need to init again,
    // this reduces startup time of the app.
    if (_currentLocation != null) {
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    // Request permission if not already granted, if denied it will always
    // return the location (0.0, 0.0), so the application continues to work.
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    Position position = await Geolocator.getCurrentPosition();
    _currentLocation = LatLng(position.latitude, position.longitude);
  }

  LatLng currentLocation() {
    return _currentLocation ?? LatLng(0.0, 0.0);
  }
}
