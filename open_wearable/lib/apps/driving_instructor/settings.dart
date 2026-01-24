import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_wearable/apps/driving_instructor/utils.dart';
import 'package:open_wearable/apps/driving_instructor/sensor.dart';
import 'package:open_wearable/apps/driving_instructor/calibration.dart';
import 'package:open_wearable/apps/driving_instructor/logs.dart';

class DrivingSession {
  final int id;
  final DateTime startTime;
  final DateTime? endTime;

  const DrivingSession({
    required this.id,
    required this.startTime,
    this.endTime,
  });

  Duration duration() {
    DateTime end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }
}

/// This class provides access to the active settings.
///
/// It uses a singleton pattern to ensure only one instance exists.
class ActiveSettings {
  static ActiveSettings? _instance;

  late final SharedPreferencesWithCache _prefs;
  bool _isInitialized = false;
  final List<VoidCallback> _logListeners = [];

  factory ActiveSettings() {
    return _instance ??= ActiveSettings._internal();
  }

  ActiveSettings._internal();

  /// This method must be called on app startup to initialize SharedPreferences, otherwise settings access will fail.
  Future<void> init() async {
    if (_isInitialized) {
      return;
    }

    WidgetsFlutterBinding.ensureInitialized();
    _prefs = await SharedPreferencesWithCache.create(
      cacheOptions: SharedPreferencesWithCacheOptions(),
    );
    _isInitialized = true;
  }

  final Map<String, String> mapTileOptions = {
    'OpenStreetMap': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'OpenStreetMap DE': 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
    'Satellite View':
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'Dark Mode':
        'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
  };

  String selectedMapName() {
    return _prefs.getString('selectedMapName') ?? 'OpenStreetMap';
  }

  String selectedMapUrl() {
    return mapTileOptions[selectedMapName()]!;
  }

  void _setSelectedMapName(String name) {
    _prefs.setString('selectedMapName', name);
  }

  // TODO: Allow disabling some of the detection things?
  bool showTraffic() {
    return _prefs.getBool('showTraffic') ?? false;
  }

  void _setShowTraffic(bool value) {
    _prefs.setBool('showTraffic', value);
  }

  double turnThreshold() {
    return _prefs.getDouble('turnThreshold') ?? 15.0;
  }

  void _setTurnThreshold(double value) {
    _prefs.setDouble('turnThreshold', value);
  }

  Duration resetAfterDuration() {
    return Duration(milliseconds: _prefs.getInt('resetAfterDuration') ?? 4000);
  }

  void _setResetAfterDuration(Duration value) {
    _prefs.setInt('resetAfterDuration', value.inMilliseconds);
  }

  double pollingFrequency() {
    return _prefs.getDouble('pollingFrequency') ?? 50.0;
  }

  void _setPollingFrequency(double value) {
    _prefs.setDouble('pollingFrequency', value);
  }

  int mirrorCheckCountPerMinute() {
    return _prefs.getInt('mirrorCheckCount') ?? 4;
  }

  Duration mirrorCheckDuration() {
    // For example, 4 checks per minute = every 15 seconds
    // 60 seconds / 4 = 15 seconds
    //
    // The below uses milliseconds for better precision in case the number does not divide
    // nicely.
    return Duration(
      milliseconds:
          (1000.0 * 60.0 / mirrorCheckCountPerMinute().toDouble()).toInt(),
    );
  }

  void _setMirrorCheckCountPerMinute(int count) {
    _prefs.setInt('mirrorCheckCount', count);
  }

  double accelerationThreshold() {
    return _prefs.getDouble('accelerationThreshold') ?? 3.5;
  }

  void _setAccelerationThreshold(double value) {
    _prefs.setDouble('accelerationThreshold', value);
  }

  double brakingThreshold() {
    return _prefs.getDouble('brakingThreshold') ?? -2.0;
  }

  void _setBrakingThreshold(double value) {
    _prefs.setDouble('brakingThreshold', value);
  }

  List<LogEntryCard> logEntries() {
    return (_prefs.getStringList('logEntries') ?? [])
        .map(LogEntryCard.fromString)
        .toList();
  }

  int registerOnLogChanged(VoidCallback listener) {
    int id = identityHashCode(listener);
    _logListeners.add(listener);
    return id;
  }

  void unregisterOnLogChanged([int? id]) {
    if (id != null) {
      _logListeners.removeWhere((listener) => identityHashCode(listener) == id);
    } else {
      _logListeners.clear();
    }
  }

  int addDrivingSession(DateTime startTime) {
    int id = _prefs.getInt('drivingSessionCounter') ?? 0;
    id += 1;
    _prefs.setInt('drivingSessionCounter', id);
    _prefs.setString('drivingSessionStart_$id', startTime.toIso8601String());
    return id;
  }

  DrivingSession drivingSession(int sessionId) {
    return DrivingSession(
      id: sessionId,
      startTime: _drivingSessionStartTime(sessionId),
      endTime: _drivingSessionEndTime(sessionId),
    );
  }

  List<DrivingSession> allDrivingSessions() {
    int counter = _prefs.getInt('drivingSessionCounter') ?? 0;
    List<DrivingSession> sessions = [];
    for (var i = 1; i <= counter; i++) {
      sessions.add(drivingSession(i));
    }
    return sessions;
  }

  DateTime _drivingSessionStartTime(int sessionId) {
    return DateTime.parse(_prefs.getString('drivingSessionStart_$sessionId')!);
  }

  DateTime? _drivingSessionEndTime(int sessionId) {
    String? endTimeStr = _prefs.getString('drivingSessionEnd_$sessionId');
    if (endTimeStr != null) {
      return DateTime.parse(endTimeStr);
    }
    return null;
  }

  void setDrivingSessionEndTime(int sessionId, DateTime endTime) {
    _prefs.setString('drivingSessionEnd_$sessionId', endTime.toIso8601String());
  }

  void clearDrivingSessions() {
    _prefs.remove('drivingSessionCounter');
  }

  void addLogEntry(LogEntryCard entry) {
    var entries = logEntries();
    entries.add(entry);
    setLogEntries(entries);
  }

  void setLogEntries(List<LogEntryCard> entries) {
    List<String> stringEntries =
        entries.map((entry) => entry.toDataString()).toList();
    _prefs.setStringList('logEntries', stringEntries);
    for (var listener in _logListeners) {
      listener();
    }
  }
}

class SettingsScreen extends StatefulWidget {
  final SensorTracker tracker;

  const SettingsScreen({super.key, required this.tracker});

  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: itemPadding,
          child: Text(
            "Some settings will require an app restart to take effect.",
            style: TextStyle(color: Colors.grey),
          ),
        ),
        const SectionName(name: "Map Source"),
        _ValueSelection(
          icon: Icons.map_outlined,
          name: "Tile Provider",
          value: ActiveSettings().selectedMapName(),
          onChanged: (val) {
            setState(() => ActiveSettings()._setSelectedMapName(val));
          },
          subtitle: ActiveSettings().selectedMapUrl(),
          options: ActiveSettings().mapTileOptions.keys.toList(),
        ),
        const SectionName(name: "Driving Settings"),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.traffic),
          title: const Text("Show Traffic"),
          value: ActiveSettings().showTraffic(),
          onChanged: (bool val) {
            setState(() => ActiveSettings()._setShowTraffic(val));
          },
        ),
        _ValueRange(
          name:
              "How frequently mirrors should be checked (number of checks per minute)",
          value: ActiveSettings().mirrorCheckCountPerMinute().toDouble(),
          onChanged: (val) => setState(
            () => ActiveSettings()._setMirrorCheckCountPerMinute(
              val.clamp(1.0, 30.0).toInt(),
            ),
          ),
          min: 1.0,
          max: 30.0,
          divisions: 29,
          description:
              "If the driver does not check their mirrors at least this frequently, a warning will be issued.",
        ),
        _ValueRange(
          name:
              "Acceleration Threshold (m/s²) for detecting rapid acceleration",
          value: ActiveSettings().accelerationThreshold(),
          onChanged: (val) => setState(
            () => ActiveSettings()._setAccelerationThreshold(
              val.clamp(0.5, 6.0).toDouble(),
            ),
          ),
          min: 0.5,
          max: 6.0,
          // TODO: Check divisions divide into 0.5 steps
          divisions: 55,
          description:
              "If the measured acceleration exceeds this threshold, a warning will be issued.",
        ),
        _ValueRange(
          // TODO: What if braking results in positive acceleration?
          name: "Braking Threshold (m/s²) for detecting strong deceleration",
          value: ActiveSettings().brakingThreshold(),
          onChanged: (val) => setState(
            () => ActiveSettings()._setBrakingThreshold(
              val.clamp(-0.5, -6.0).toDouble(),
            ),
          ),
          min: -6.0,
          max: -0.5,
          // TODO: Check divisions divide into 0.5 steps
          divisions: 55,
          description:
              "If the measured acceleration exceeds this threshold, a warning will be issued.",
        ),
        const Divider(),
        const SectionName(name: "Esense Settings"),
        _ValueRange(
          name: "Head Threshold (degrees)",
          value: ActiveSettings().turnThreshold(),
          onChanged: (val) =>
              setState(() => ActiveSettings()._setTurnThreshold(val)),
          min: 2.0,
          max: 90.0,
          divisions: 88,
          description:
              "The angle (in degrees) at which a look to the side is detected. Note that this value might be different from the actual head angle.",
        ),
        _ValueRange(
          name: "Reset After (ms)",
          value:
              ActiveSettings().resetAfterDuration().inMilliseconds.toDouble(),
          onChanged: (val) => setState(
            () => ActiveSettings()._setResetAfterDuration(
              Duration(milliseconds: val.clamp(500.0, 10000.0).toInt()),
            ),
          ),
          min: 500.0,
          max: 6000.0,
          divisions: 11,
          description:
              "The duration after which the head turn state resets to center if no further turns are detected.",
        ),
        _ValueSelection(
          icon: Icons.phonelink_ring_outlined,
          name: "Polling Frequency (Hz)",
          value: ActiveSettings().pollingFrequency(),
          onChanged: (val) =>
              setState(() => ActiveSettings()._setPollingFrequency(val)),
          subtitle:
              "How frequently sensor data is requested from the device, a higher value might improve responsiveness.",
          options: [10.0, 20.0, 50.0, 100.0, 200.0],
        ),
        mediumColDivider,
        ElevatedButton(
          onPressed: () => openPopupWindow(
            context: context,
            title: "Calibration",
            child: CalibrationScreen(tracker: widget.tracker),
          ),
          child: const Text("Calibrate Sensors"),
        ),
        largeColDivider,
      ],
    );
  }
}

class _ValueSelection<T> extends StatelessWidget {
  final void Function(T)? onChanged;
  final T value;
  final String name;
  final String subtitle;
  final List<T> options;
  final IconData icon;

  const _ValueSelection({
    required this.icon,
    required this.name,
    required this.value,
    required this.onChanged,
    required this.subtitle,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: itemPadding,
      child: ListTile(
        leading: Icon(icon),
        title: Text(name),
        subtitle: Text(subtitle), // Shows the URL
        isThreeLine: true,
        trailing: DropdownButton<T>(
          value: value,
          underline: Container(), // Hides the default underline
          icon: const Icon(Icons.arrow_drop_down),
          onChanged: (T? newValue) {
            if (newValue != null) {
              onChanged?.call(newValue);
            }
          },
          items: options.map<DropdownMenuItem<T>>((T name) {
            return DropdownMenuItem<T>(
              value: name,
              child: Text(name.toString()),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ValueRange extends StatelessWidget {
  final void Function(double)? onChanged;
  final double min;
  final double max;
  final double value;
  final String name;
  final int? divisions;
  final String description;

  const _ValueRange({
    required this.name,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    this.divisions,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: itemPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(fontSize: 16),
                ),
              ),
              Text(
                value.toStringAsFixed(1),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
          smallColDivider,
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(1),
            onChanged: onChanged,
          ),
          Text(
            description,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
