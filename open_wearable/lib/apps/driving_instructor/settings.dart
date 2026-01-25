import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:open_wearable/apps/driving_instructor/asset_finder.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_wearable/apps/driving_instructor/utils.dart';
import 'package:open_wearable/apps/driving_instructor/sensor.dart';
import 'package:open_wearable/apps/driving_instructor/calibration.dart';
import 'package:open_wearable/apps/driving_instructor/logs.dart';

/// This class represents a driving session with start and end times.
///
/// It is mostly there to group log entries together.
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
/// It uses a singleton pattern to ensure only one instance exists, because there would
/// be problems with multiple instances writing to SharedPreferences at the same time.
///
/// In addition it is a ChangeNotifier, so widgets can update when settings change.
/// Not all settings will notify listeners when they change, because these might not be
/// relevant for UI updates.
class ActiveSettings with ChangeNotifier {
  static ActiveSettings? _instance;

  late final SharedPreferencesWithCache _prefs;
  bool _isInitialized = false;

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
    return _prefs.getDouble('accelerationThreshold') ?? 2.2;
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

  double accelDetectionEnd() {
    return _prefs.getDouble('accelDetectionEnd') ?? 1.0;
  }

  void _setAccelDetectionEnd(double value) {
    _prefs.setDouble('accelDetectionEnd', value);
  }

  List<LogEntryCard> logEntries() {
    return (_prefs.getStringList('logEntries') ?? [])
        .map(LogEntryCard.fromString)
        .toList();
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
    int? counter = _prefs.getInt('drivingSessionCounter');
    if (counter == null) {
      return [];
    }

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
    int? counter = _prefs.getInt('drivingSessionCounter');
    if (counter != null) {
      for (var i = 1; i <= counter; i++) {
        _prefs.remove('drivingSessionStart_$i');
        _prefs.remove('drivingSessionEnd_$i');
      }
    }

    _prefs.remove('drivingSessionCounter');
  }

  void addLogEntry(LogEntryCard entry) {
    if (!_enableAccelerationDetection() &&
        (entry.kind == LogKind.acceleration || entry.kind == LogKind.braking)) {
      return;
    }

    if (!_enableMirrorDetection() && entry.kind == LogKind.awareness) {
      return;
    }

    var entries = logEntries();
    entries.add(entry);
    setLogEntries(entries);

    var soundPath = warningSound();
    if (soundPath != null) {
      soundPath = AssetFinder()
          .listSounds()
          .where((e) => e.contains(soundPath!))
          .firstOrNull;
    }

    if (soundPath == null) {
      return;
    }

    AudioPlayer().play(AssetSource("../$soundPath"));
  }

  void setLogEntries(List<LogEntryCard> entries) {
    if (entries.isEmpty) {
      clearDrivingSessions();
    }

    List<String> stringEntries =
        entries.map((entry) => entry.toDataString()).toList();
    _prefs.setStringList('logEntries', stringEntries);
    notifyListeners();
  }

  void _setWarningSound(String? soundPath) {
    if (soundPath == null) {
      _prefs.remove('warningSound');
    } else {
      _prefs.setString('warningSound', soundPath);
    }
  }

  String? warningSound() {
    return _prefs.getString('warningSound');
  }

  double maxViolationsPerMinute() {
    return _prefs.getDouble('maxViolationsPerMinute') ?? 5.0;
  }

  void _setMaxViolationsPerMinute(double value) {
    _prefs.setDouble('maxViolationsPerMinute', value);
  }

  bool _enableMirrorDetection() {
    return _prefs.getBool('enableMirrorDetection') ?? true;
  }

  void _setEnableMirrorDetection(bool value) {
    _prefs.setBool('enableMirrorDetection', value);
  }

  bool _enableAccelerationDetection() {
    return _prefs.getBool('enableAccelerationDetection') ?? true;
  }

  void _setEnableAccelerationDetection(bool value) {
    _prefs.setBool('enableAccelerationDetection', value);
  }

  bool showDebugInformation() {
    return _prefs.getBool('showDebugInformation') ?? false;
  }

  void _setShowDebugInformation(bool value) {
    _prefs.setBool('showDebugInformation', value);
    notifyListeners();
  }
}

/// The widget that shows the settings screen.
class SettingsScreen extends StatefulWidget {
  final SensorTracker tracker;

  const SettingsScreen({super.key, required this.tracker});

  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  // The actual state is stored in the ActiveSettings singleton,
  // which is why this class does not have any fields.

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
          onChanged: (value) {
            setState(() => ActiveSettings()._setSelectedMapName(value));
          },
          subtitle: ActiveSettings().selectedMapUrl(),
          options: ActiveSettings().mapTileOptions.keys.toList(),
        ),
        const SectionName(name: "General Detection Settings"),
        _ValueSelection(
          icon: Icons.audio_file,
          name: "Select the sound to be played for reminders.",
          value: ActiveSettings().warningSound() ?? "none",
          onChanged: (value) => setState(
            () => ActiveSettings()
                ._setWarningSound(value == "none" ? null : value),
          ),
          subtitle: "Select the sound to be played for reminders.",
          options: [
            "none",
            ...(AssetFinder()
                .listSounds()
                .map((e) => e.split("/").last.split(".").first)),
          ],
        ),
        _ValueRange(
          name:
              "The expected maximum number of violations (mirror checks missed, rapid acceleration/braking) per minute",
          value: ActiveSettings().maxViolationsPerMinute().toDouble(),
          onChanged: (value) => setState(
            () => ActiveSettings()._setMaxViolationsPerMinute(value),
          ),
          min: 1.0,
          max: 20.0,
          stepSize: 0.5,
          description:
              "This is used to calculate the eco score, a higher value will result in a more lenient score while a lower value will result in stricter results.",
        ),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.bug_report_outlined),
          title: const Text("Show Debug Information"),
          value: ActiveSettings().showDebugInformation(),
          onChanged: (bool value) {
            setState(() => ActiveSettings()._setShowDebugInformation(value));
          },
        ),
        const SectionName(name: "Mirror Detection"),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.minor_crash_rounded),
          title: const Text("Enable Mirror Detection"),
          value: ActiveSettings()._enableMirrorDetection(),
          onChanged: (bool value) {
            setState(() => ActiveSettings()._setEnableMirrorDetection(value));
          },
        ),
        _ValueRange(
          name:
              "How frequently mirrors should be checked (number of checks per minute)",
          value: ActiveSettings().mirrorCheckCountPerMinute().toDouble(),
          onChanged: (value) => setState(
            () => ActiveSettings()._setMirrorCheckCountPerMinute(value.toInt()),
          ),
          min: 1.0,
          max: 30.0,
          stepSize: 1.0,
          description:
              "If the driver does not check their mirrors at least this frequently, a warning will be issued.",
        ),
        _ValueRange(
          name: "Head Threshold (degrees)",
          value: ActiveSettings().turnThreshold(),
          onChanged: (value) =>
              setState(() => ActiveSettings()._setTurnThreshold(value)),
          min: 2.0,
          max: 90.0,
          stepSize: 1.0,
          description:
              "The angle (in degrees) at which a look to the side is detected. Note that this value might be different from the actual head angle.",
        ),
        _ValueRange(
          name: "Reset After (ms)",
          value:
              ActiveSettings().resetAfterDuration().inMilliseconds.toDouble(),
          onChanged: (value) => setState(
            () => ActiveSettings()._setResetAfterDuration(
              Duration(milliseconds: value.toInt()),
            ),
          ),
          min: 500.0,
          max: 6000.0,
          stepSize: 500.0,
          description:
              "The duration after which the head turn state resets to center if no further turns are detected.",
        ),
        const SectionName(name: "Acceleration Detection"),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.speed_sharp),
          title: const Text("Enable Acceleration Detection"),
          value: ActiveSettings()._enableAccelerationDetection(),
          onChanged: (bool value) {
            setState(
              () => ActiveSettings()._setEnableAccelerationDetection(value),
            );
          },
        ),
        _ValueRange(
          name:
              "Acceleration Threshold (m/s²) for detecting rapid acceleration",
          value: ActiveSettings().accelerationThreshold(),
          onChanged: (value) => setState(
            () => ActiveSettings()._setAccelerationThreshold(value),
          ),
          min: 1.0,
          max: 10.0,
          stepSize: 0.1,
          description:
              "If the measured acceleration exceeds this threshold, a warning will be issued.",
        ),
        _ValueRange(
          name: "Braking Threshold (m/s²) for detecting strong deceleration",
          value: ActiveSettings().brakingThreshold(),
          onChanged: (value) => setState(
            () => ActiveSettings()._setBrakingThreshold(value),
          ),
          min: -10.0,
          max: -1.0,
          stepSize: 0.1,
          description:
              "If the measured acceleration exceeds this threshold, a warning will be issued.",
        ),
        _ValueRange(
          name: "Acceleration end threshold (m/s²)",
          value: ActiveSettings().accelDetectionEnd(),
          onChanged: (value) => setState(
            () => ActiveSettings()._setAccelDetectionEnd(value),
          ),
          min: 0.0,
          max: 4.0,
          stepSize: 0.5,
          description:
              "This value defines when acceleration/braking events are considered to have ended.",
        ),
        const Divider(),
        const SectionName(name: "Esense Settings"),
        _ValueSelection(
          icon: Icons.phonelink_ring_outlined,
          name: "Polling Frequency (Hz)",
          value: ActiveSettings().pollingFrequency(),
          onChanged: (value) =>
              setState(() => ActiveSettings()._setPollingFrequency(value)),
          subtitle:
              "How frequently sensor data is requested from the device, a higher value might improve responsiveness.",
          options: [10.0, 20.0, 50.0, 100.0, 200.0],
        ),
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
        //: Text(subtitle), // Shows the URL
        isThreeLine: true,
        subtitle: DropdownButton<T>(
          value: value,
          underline: Container(), // Hides the default underline
          icon: const Icon(Icons.arrow_drop_down),
          onChanged: (T? newValue) {
            if (newValue != null) {
              onChanged?.call(newValue);
            }
          },
          items: options
              .map<DropdownMenuItem<T>>(
                (T name) => DropdownMenuItem<T>(
                  value: name,
                  child: Text(name.toString()),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _ValueRange extends StatelessWidget {
  final int roundTo = 1;

  final void Function(double)? onChanged;
  final double min;
  final double max;
  final double value;
  final String name;
  final double? stepSize;
  final String description;

  const _ValueRange({
    required this.name,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    this.stepSize,
    required this.description,
  });

  int? get _divisions {
    if (stepSize == null) {
      return null;
    }

    // The abs is necessary in case of negative ranges (e.g., -6 to -0.5)
    return ((max - min) / stepSize!).round().abs();
  }

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
                value.toStringAsFixed(roundTo),
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
            divisions: _divisions,
            label: value.toStringAsFixed(roundTo),
            onChanged: (value) =>
                onChanged?.call(value.clamp(min, max).toDouble()),
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
