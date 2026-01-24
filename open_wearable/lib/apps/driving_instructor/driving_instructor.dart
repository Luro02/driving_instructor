import 'dart:math';

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:flutter/material.dart';
import 'package:step_progress_indicator/step_progress_indicator.dart';
import 'package:provider/provider.dart';

import 'package:open_wearable/apps/driving_instructor/settings.dart';
import 'package:open_wearable/apps/driving_instructor/logs.dart';
import 'package:open_wearable/widgets/sensors/values/sensor_value_card.dart';
import 'package:open_wearable/apps/driving_instructor/sensor.dart';
import 'package:open_wearable/apps/driving_instructor/utils.dart';
import 'package:open_wearable/apps/driving_instructor/motion_status.dart';
import 'package:open_wearable/view_models/sensor_data_provider.dart';

class DrivingInstructorPage extends StatefulWidget {
  final Wearable wearable;
  final SensorManager manager;
  late final SensorTracker tracker;

  DrivingInstructorPage({
    super.key,
    required this.wearable,
    required this.manager,
  }) {
    tracker = EsenseSensorTracker(
      manager: manager,
      targetFrequencyHz: ActiveSettings().pollingFrequency(),
    );
  }

  @override
  State<DrivingInstructorPage> createState() => _DrivingInstructorPageState();
}

class _DrivingInstructorPageState extends State<DrivingInstructorPage> {
  final List<LogEntryCard> _logEntries = [];
  late final int handle;

  @override
  void initState() {
    super.initState();

    _logEntries.addAll(ActiveSettings().logEntries());
    _logEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    handle = ActiveSettings().registerOnLogChanged(() {
      setState(() {
        _logEntries.clear();
        _logEntries.addAll(ActiveSettings().logEntries());
        _logEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      });
    });
  }

  @override
  void dispose() {
    ActiveSettings().unregisterOnLogChanged(handle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Driving Instructor"),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => openPopupWindow(
              context: context,
              title: "Settings",
              child: SettingsScreen(
                tracker: widget.tracker,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.bug_report),
            onPressed: () => openPopupWindow(
              context: context,
              title: "Debug",
              child: _buildDebugView(context),
            ),
          ),
        ],
      ),
      body: _buildInstructorView(context),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openPopupWindow(
          context: context,
          title: "Recording",
          child: MotionDisplay(
            tracker: widget.tracker,
          ),
        ),
        tooltip: 'Start Recording',
        child: Icon(Icons.play_arrow_rounded),
      ),
    );
  }

  double _calculateSessionScore(int sessionId, List<LogEntryCard> entries) {
    Duration totalDuration =
        ActiveSettings().drivingSession(sessionId).duration();

    // At most one could miss the mirror check x times per minute
    double maxViolationsPerMinute =
        ActiveSettings().mirrorCheckCountPerMinute().toDouble();

    double maximumViolations =
        totalDuration.toSecondsDouble() / 60.0 * maxViolationsPerMinute;
    double actualViolations = entries.length.toDouble();
    print(
      "Session $sessionId duration: $totalDuration maxViolations: $maximumViolations actualViolations: $actualViolations",
    );

    return (100.0 * (1.0 - (actualViolations / maximumViolations)))
        .clamp(0.0, 100.0);
  }

  double _calculateEcoScore() {
    if (_logEntries.isEmpty) {
      return 100.0;
    }

    // To calculate the score we measure the timespan of all logged issues
    Map<int, List<LogEntryCard>> sessionLogs = {};

    // group by driving session
    for (var entry in _logEntries) {
      sessionLogs.putIfAbsent(entry.drivingSession, () => []).add(entry);
    }

    for (var session in ActiveSettings().allDrivingSessions()) {
      sessionLogs.putIfAbsent(session.id, () => []);
    }

    double totalScore = 0.0;
    for (var sessionId in sessionLogs.keys) {
      double sessionScore = _calculateSessionScore(
        sessionId,
        sessionLogs[sessionId]!,
      );
      print(
        "Session $sessionId has ${sessionLogs[sessionId]!.length} logs: score $sessionScore",
      );

      totalScore += sessionScore;
    }

    return totalScore / sessionLogs.keys.length;
  }

  Widget _buildInstructorView(BuildContext context) {
    return ListView(
      padding: itemPadding,
      children: [
        Text(
          "Your Driving Score",
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        largeColDivider,
        Center(child: EcoScore(score: _calculateEcoScore())),
        largeColDivider,
        AppBar(
          title: Text("Issues Log"),
          automaticallyImplyLeading: false,
          forceMaterialTransparency: true,
          actions: [
            IconButton(
              icon: Icon(Icons.clear_all_rounded),
              onPressed: () => ActiveSettings().setLogEntries([]),
            ),
          ],
        ),
        mediumColDivider,
        Column(
          children: _buildLogEntriesWithDivider(),
        ),
      ],
    );
  }

  List<Widget> _buildLogEntriesWithDivider() {
    List<Widget> widgets = [];
    DateTime? lastStartDate;
    for (var entry in _logEntries.reversed) {
      var entryStartDate =
          ActiveSettings().drivingSession(entry.drivingSession).startTime;

      if (lastStartDate != entryStartDate) {
        widgets.add(Divider());
        widgets.add(SectionName(name: getSmartDate(entryStartDate)));
        lastStartDate = entryStartDate;
      }

      widgets.add(entry);
    }

    return widgets;
  }

  Widget _buildDebugView(BuildContext context) {
    var children = <Widget>[];

    for (var sensor in widget.manager.sensors) {
      var wrappedSensor = EsenseSensorWrapper(
        sensor: sensor,
        samplingFrequencyHz: ActiveSettings().pollingFrequency(),
      );
      children.add(
        ChangeNotifierProvider.value(
          value: SensorDataProvider(sensor: wrappedSensor),
          child: SensorValueCard(
            sensor: wrappedSensor,
            wearable: widget.wearable,
          ),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class EcoScore extends StatelessWidget {
  final double score;
  final int resolution = 10;

  const EcoScore({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    var targetSize = min(
      MediaQuery.of(context).size.width * 0.5,
      MediaQuery.of(context).size.height * 0.5,
    );

    return Container(
      constraints: BoxConstraints.expand(width: targetSize, height: targetSize),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularStepProgressIndicator(
              totalSteps: resolution * 100,
              currentStep: (score * resolution).toInt(),
              stepSize: 10,
              selectedStepSize: 20,
              selectedColor: Colors.transparent,
              unselectedColor: Theme.of(context).colorScheme.surfaceContainer,
              roundedCap: (_, __) => true,
            ),
            CircularStepProgressIndicator(
              totalSteps: resolution * 100,
              currentStep: (score * resolution).toInt(),
              stepSize: 10,
              selectedStepSize: 20,
              unselectedColor: Colors.transparent,
              gradientColor: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.cyan, Colors.purple],
              ),
              roundedCap: (_, __) => true,
              // Texts don't scale by default, the fitted box scales it to fit the parent.
              // The actual chosen text size doesn't matter here.
              //
              // The padding is to create some distance from the circular progress indicator.
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(15),
                  child: Text(
                    "${score.toStringAsFixed(0)}%",
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
