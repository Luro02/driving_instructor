import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:open_wearable/apps/driving_instructor/utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';

import 'package:open_wearable/apps/driving_instructor/settings.dart';

/// Always displaying the dates like this 2026-01-24 10:30 is awful to look at,
/// this function returns a smarter representation of the date.
String getSmartDate(DateTime date, {bool showDate = true}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // checks if the date is today, in which case we omit the date part
  if (DateTime(date.year, date.month, date.day) == today || !showDate) {
    return DateFormat.Hms().format(date); // "10:30"
  }

  // Otherwise we show the date and time like this:
  // "Oct 24 - 10:30"
  return "${DateFormat.MMMd().format(date)} - ${DateFormat.Hms().format(date)}";
}

/// This is an entry in the driving logs, it contains and displays the information
/// about the log for the user.
class LogEntryCard extends StatelessWidget {
  final LogKind kind;
  final DateTime timestamp;
  final LatLng location;
  final int drivingSession;

  const LogEntryCard({
    super.key,
    required this.kind,
    required this.timestamp,
    required this.location,
    required this.drivingSession,
  });

  /// This constructs the LogEntryCard from a string representation.
  ///
  /// json_serializable and dart_mappable both require code generation,
  /// and I am not sure if I am allowed to require that in this project.
  ///
  /// So even though it is unnecessarily manual, the below is a naive implementation
  /// of serialization and deserialization to and from string.
  factory LogEntryCard.fromString(String data) {
    // Expected format: "kind|timestamp|drivingStart|latitude,longitude"
    var parts = data.split('|');
    var kind = LogKind.values.firstWhere(
      (k) => k.name == parts[0],
      orElse: () => LogKind.awareness,
    );
    var timestamp = DateTime.parse(parts[1]);
    var drivingSession = int.parse(parts[2]);
    var latLngParts = parts[3].split(',');
    var location = LatLng(
      double.parse(latLngParts[0]),
      double.parse(latLngParts[1]),
    );

    return LogEntryCard(
      kind: kind,
      timestamp: timestamp,
      location: location,
      drivingSession: drivingSession,
    );
  }

  /// This converts the LogEntryCard to a string representation that can be used to
  /// reconstruct it through fromString later.
  String toDataString() {
    return '${kind.name}|${timestamp.toIso8601String()}|$drivingSession|${location.latitude},${location.longitude}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: ListTile(
        leading: Icon(kind.icon),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                kind.name,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              getSmartDate(timestamp),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
        visualDensity: VisualDensity.comfortable,
        subtitle: Text(kind.description),
        onTap: () => openPopupWindow(
          context: context,
          title: "Details",
          child: _LogDetails(kind: kind, location: location),
        ),
      ),
    );
  }
}

/// This widget is the popup that displays when you tap on a log entry.
///
/// It mainly shows a detailed explanation of the log and a map of where
/// it was logged. This might be useful for the user to understand where
/// and how they made mistakes while driving.
class _LogDetails extends StatelessWidget {
  final LogKind kind;
  final LatLng location;

  const _LogDetails({required this.kind, required this.location});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        kind.buildExplanation(context),
        smallColDivider,
        Text(
          "Location where this was logged, (latitude=${location.latitude}, longitude=${location.longitude}): ",
        ),
        mediumColDivider,
        _LocationMap(
          location: location,
          mapStyleUrl: ActiveSettings().selectedMapUrl(),
        ),
      ],
    );
  }
}

/// Small wrapper for displaying the location on a map.
///
/// It uses flutter_map and flutter_map_location_marker to show the
/// current location on the map. Mainly abstracts away the map setup.
class _LocationMap extends StatelessWidget {
  final LatLng location;
  final double initialZoom;
  final double minimumZoom;
  final String mapStyleUrl;

  const _LocationMap({
    required this.location,
    this.initialZoom = 18.0,
    this.minimumZoom = 14.0,
    required this.mapStyleUrl,
  }) : assert(
          initialZoom >= minimumZoom,
          'initial zoom must be greater than or equal to minimum zoom',
        );

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: location,
          initialZoom: initialZoom,
          minZoom: minimumZoom,
          // Only allow zooming with two fingers and dragging around, this disables rotation
          interactionOptions: InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: mapStyleUrl,
            userAgentPackageName:
                'open_wearable.apps.driving_instructor', // Add your app identifier
          ),
          SimpleAttributionWidget(
            source: Text(
              'OpenStreetMap contributors',
              style: TextStyle(
                fontSize: 10,
              ),
            ),
            onTap: () =>
                launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
          ),
          CurrentLocationLayer(
            alignPositionOnUpdate: AlignOnUpdate.always,
            alignDirectionOnUpdate: AlignOnUpdate.never,
            style: LocationMarkerStyle(
              marker: const DefaultLocationMarker(),
              markerSize: const Size(25, 25),
              markerDirection: MarkerDirection.heading,
            ),
            positionStream: Stream.value(
              LocationMarkerPosition(
                latitude: location.latitude,
                longitude: location.longitude,
                accuracy: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// This enum represents the different kinds of logs that can be recorded
/// by the driving instructor app.
enum LogKind {
  awareness(
    "Awareness",
    "A good driver is always aware of their surroundings, frequently looking at the mirrors and checking blind spots.",
    Icons.remove_red_eye_outlined,
  ),
  acceleration(
    "Acceleration",
    "Slowly accelerating helps to improve fuel efficiency and provides a smoother driving experience.",
    Icons.speed,
  ),
  braking(
    "Braking",
    "It is important to brake gently to ensure passenger comfort and maintain vehicle control.",
    Icons.car_crash,
  );

  final String name;
  final String description;
  final IconData icon;

  const LogKind(this.name, this.description, this.icon);

  /// Each log kind has a different explanation that is shown
  /// to the user when they tap on a log entry.
  ///
  /// This is built here, because the content might vastly differ
  /// between log kinds. It is not a build, because the enum cannot
  /// inherit from StatelessWidget.
  Widget buildExplanation(BuildContext context) {
    switch (this) {
      case LogKind.awareness:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              description,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            smallColDivider,
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        "This issue is logged when the driver does not check their mirrors within ",
                  ),
                  TextSpan(
                    text: ActiveSettings()
                        .mirrorCheckDuration()
                        .inSeconds
                        .toString(),
                    style:
                        Theme.of(context).primaryTextTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                  ),
                  TextSpan(text: " seconds."),
                ],
              ),
            ),
            smallColDivider,
            Text(
              "This is detected through the users head turns. If this is too sensitive, consider changing the settings.",
            ),
          ],
        );
      case LogKind.acceleration:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              description,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            smallColDivider,
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text:
                        "This issue is logged when the driver accelerates too quickly, exceeding ",
                  ),
                  TextSpan(
                    text: ActiveSettings().accelerationThreshold().toString(),
                    style:
                        Theme.of(context).primaryTextTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                  ),
                  const TextSpan(text: " m/s²."),
                ],
              ),
            ),
            smallColDivider,
            Text(
              "If this is too sensitive, consider changing the settings.",
            ),
          ],
        );
      case LogKind.braking:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              description,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            smallColDivider,
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text:
                        "This issue is logged when the driver brakes too strongly, exceeding ",
                  ),
                  TextSpan(
                    text: ActiveSettings().brakingThreshold().toString(),
                    style:
                        Theme.of(context).primaryTextTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                  ),
                  const TextSpan(text: " m/s²."),
                ],
              ),
            ),
            smallColDivider,
            Text(
              "If this is too sensitive, consider changing the settings.",
            ),
          ],
        );
    }
  }
}
