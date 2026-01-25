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

/// This is the main entry point for the driving instructor app.
///
/// It shows the driving score, the log of issues and a button to start/stop recording.
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
  final ActiveSettings _activeSettings = ActiveSettings();

  bool isRecording = false;
  int? sessionId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        // The action button on the bottom right starts/stops the recording.
        //
        // The screen changes while a recording is active. The user might try
        // to stop the recording by using this back button, so we need to handle that.
        leading: BackButton(
          onPressed: () {
            if (isRecording) {
              setState(() {
                isRecording = false;
                sessionId = ActiveSettings().addDrivingSession(DateTime.now());
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text("Driving Instructor"),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => openPopupWindow(
              context: context,
              title: "Settings",
              child: SettingsScreen(tracker: widget.tracker),
            ),
          ),
          ListenableBuilder(
            listenable: _activeSettings,
            builder: (context, child) {
              if (ActiveSettings().showDebugInformation()) {
                return IconButton(
                  icon: Icon(Icons.bug_report),
                  onPressed: () => openPopupWindow(
                    context: context,
                    title: "Debug",
                    child: _buildDebugView(context),
                  ),
                );
              } else {
                return Container();
              }
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _activeSettings,
        builder: (context, child) =>
            _buildInstructorView(context, _activeSettings.logEntries()),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() {
          isRecording = !isRecording;

          // Ensure a new session is created when starting recording
          if (isRecording) {
            sessionId = ActiveSettings().addDrivingSession(DateTime.now());
          } else if (sessionId != null) {
            // Stop the current session when stopping recording
            ActiveSettings()
                .setDrivingSessionEndTime(sessionId!, DateTime.now());
          }
        }),
        tooltip: "Start/Stop Recording",
        child: isRecording ? Icon(Icons.pause) : Icon(Icons.play_arrow_rounded),
      ),
    );
  }

  double _calculateSessionScore(int sessionId, List<LogEntryCard> entries) {
    Duration totalDuration =
        ActiveSettings().drivingSession(sessionId).duration();

    double maxViolationsPerMinute = ActiveSettings().maxViolationsPerMinute();

    double maximumViolations =
        totalDuration.toSecondsDouble() / 60.0 * maxViolationsPerMinute;
    double actualViolations = entries.length.toDouble();
    print(
      "Session $sessionId duration: $totalDuration maxViolations: $maximumViolations actualViolations: $actualViolations",
    );

    return (100.0 * (1.0 - (actualViolations / maximumViolations)))
        .clamp(0.0, 100.0);
  }

  double _calculateEcoScore(List<LogEntryCard> logEntries) {
    if (logEntries.isEmpty) {
      return 100.0;
    }

    // To calculate the score we measure the timespan of all logged issues
    Map<int, List<LogEntryCard>> sessionLogs = {};

    // group by driving session
    for (var entry in logEntries) {
      sessionLogs.putIfAbsent(entry.drivingSession, () => []).add(entry);
    }

    for (var session in ActiveSettings().allDrivingSessions()) {
      sessionLogs.putIfAbsent(session.id, () => []);
    }
    print(sessionLogs);

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

  Widget _buildInstructorView(
    BuildContext context,
    List<LogEntryCard> logEntries,
  ) {
    List<Widget> leadingWidgets = [];

    if (isRecording) {
      leadingWidgets.add(
        MotionDisplay(
          tracker: widget.tracker,
          sessionId: sessionId!,
        ),
      );
    } else {
      leadingWidgets.addAll([
        Text(
          "Your Driving Score",
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        smallColDivider,
        Center(child: EcoScore(score: _calculateEcoScore(logEntries))),
      ]);
    }

    logEntries = logEntries.toList()
      ..sort(
        (a, b) => a.timestamp.compareTo(b.timestamp),
      ); // sort by timestamp descending, starting with the latest

    return ListView(
      padding: itemPadding,
      children: [
        ...leadingWidgets,
        smallColDivider,
        AppBar(
          title: Text("Issues Log"),
          // No back button is necessary here
          automaticallyImplyLeading: false,
          titleSpacing: 0.0,
          // Without this, the bar would have a darker background when scrolled through the entries below
          forceMaterialTransparency: true,
          actions: [
            IconButton(
              icon: Icon(Icons.clear_all_rounded),
              onPressed: () => ActiveSettings().setLogEntries([]),
            ),
          ],
        ),
        ..._buildLogEntriesWithDivider(logEntries),
      ],
    );
  }

  List<Widget> _buildLogEntriesWithDivider(List<LogEntryCard> logEntries) {
    List<Widget> widgets = [];
    DateTime? lastStartDate;

    // This groups the log entries by driving session, adding a section widget with the date range
    for (var entry in logEntries.reversed) {
      DrivingSession entrySession =
          ActiveSettings().drivingSession(entry.drivingSession);

      if (lastStartDate != entrySession.startTime) {
        widgets.add(
          SectionName(
            name:
                "${getSmartDate(entrySession.startTime)} until ${getSmartDate(entrySession.endTime ?? DateTime.now(), showDate: false)}",
          ),
        );
        lastStartDate = entrySession.startTime;
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

    return ListView(
      children: children,
    );
  }
}

/// This widget is the circular score that is shown on the main driving instructor page.
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
        // The gradient is colored all the way, including the part that is not filled (unselected).
        // This looks off. To make it look the way it should, a stack is used to only
        // show the gradient on the filled/selected part.
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
