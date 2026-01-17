import 'dart:async';
import 'dart:math';

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:flutter/material.dart';
import 'package:step_progress_indicator/step_progress_indicator.dart';

const mediumColDivider = SizedBox(height: 32);
const smallColDivider = SizedBox(height: 16);
const largeColDivider = SizedBox(height: 30);

const rowDivider = SizedBox(width: 20);

const int windowSize = 10_000;

/// This class contains all the data provided by the IMU.
class SensorStatus {
  List<RollingAverage> accelerometer = [
    RollingAverage(windowSize),
    RollingAverage(windowSize),
    RollingAverage(windowSize),
  ];

  List<RollingAverage> gyroscope = [
    RollingAverage(windowSize),
    RollingAverage(windowSize),
    RollingAverage(windowSize),
  ];

  List<RollingAverage> euler = [
    RollingAverage(windowSize),
    RollingAverage(windowSize),
    RollingAverage(windowSize),
  ];

  double get ax => accelerometer[0].average;
  double get ay => accelerometer[1].average;
  double get az => accelerometer[2].average;

  double get gx => gyroscope[0].average;
  double get gy => gyroscope[1].average;
  double get gz => gyroscope[2].average;

  double get roll => euler[0].average;
  double get pitch => euler[1].average;
  double get yaw => euler[2].average;

  set ax(double value) => accelerometer[0].add(value);
  set ay(double value) => accelerometer[1].add(value);
  set az(double value) => accelerometer[2].add(value);

  set gx(double value) => gyroscope[0].add(value);
  set gy(double value) => gyroscope[1].add(value);
  set gz(double value) => gyroscope[2].add(value);

  set roll(double value) => euler[0].add(value);
  set pitch(double value) => euler[1].add(value);
  set yaw(double value) => euler[2].add(value);
}

class RollingAverage {
  final int windowSize;
  final List<double> _values = [];

  RollingAverage(this.windowSize);

  double add(double value) {
    _values.add(value);
    if (_values.length > windowSize) {
      _values.removeAt(0);
    }

    return average;
  }

  double get average {
    if (_values.isEmpty) return 0.0;
    return _values.reduce((a, b) => a + b) / _values.length;
  }
}

// TODO: Smooth values using rolling average

class SensorTracker {
  final SensorManager manager;

  const SensorTracker({required this.manager});

  Stream<SensorStatus> streamStatus() {
    StreamController<SensorStatus> controller =
        StreamController<SensorStatus>();
    List<StreamSubscription<SensorValue>> subscriptions = [];

    var lastStatus = SensorStatus();
    for (var sensor in manager.sensors) {
      if (!["accelerometer", "gyroscope", "euler"]
          .contains(sensor.sensorName.toLowerCase())) {
        continue;
      }

      var sub = sensor.sensorStream.listen((sensorValue) {
        if (sensor.sensorName.toLowerCase() == "accelerometer" &&
            sensorValue is SensorDoubleValue) {
          lastStatus.ax = sensorValue.values[0];
          lastStatus.ay = sensorValue.values[1];
          lastStatus.az = sensorValue.values[2];
        } else if (sensor.sensorName.toLowerCase() == "gyroscope" &&
            sensorValue is SensorDoubleValue) {
          lastStatus.gx = sensorValue.values[0];
          lastStatus.gy = sensorValue.values[1];
          lastStatus.gz = sensorValue.values[2];
        } else if (sensor.sensorName.toLowerCase() == "euler" &&
            sensorValue is SensorDoubleValue) {
          lastStatus.roll =
              sensorValue.values[0] * 57.2957795; // Radians to degrees
          lastStatus.pitch =
              sensorValue.values[1] * 57.2957795; // Radians to degrees
          lastStatus.yaw =
              sensorValue.values[2] * 57.2957795; // Radians to degrees
        }

        controller.add(lastStatus);
      });
      subscriptions.add(sub);
    }

    controller.onCancel = () {
      for (var sub in subscriptions) {
        sub.cancel();
      }
    };

    return controller.stream;
  }
}

class DrivingInstructorPage extends StatefulWidget {
  final SensorManager manager;

  const DrivingInstructorPage({super.key, required this.manager});

  @override
  State<DrivingInstructorPage> createState() => _DrivingInstructorPageState();
}

class MotionDisplay extends StatefulWidget {
  final SensorTracker tracker;

  const MotionDisplay({
    super.key,
    required this.tracker,
  });

  @override
  State<MotionDisplay> createState() => _MotionDisplayState();
}

class _MotionDisplayState extends State<MotionDisplay> {
  SensorStatus currentStatus = SensorStatus();
  StreamSubscription<SensorStatus>? status;

  @override
  void initState() {
    status = widget.tracker.streamStatus().listen((SensorStatus sensorStatus) {
      setState(() {
        currentStatus = sensorStatus;
      });
    });

    super.initState();
  }

  @override
  void dispose() {
    status?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          "AX: ${currentStatus.ax}",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        Text(
          "AY: ${currentStatus.ay}",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        Text(
          "AZ: ${currentStatus.az}",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        mediumColDivider,
        Text(
          "GX: ${currentStatus.gx}",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        Text(
          "GY: ${currentStatus.gy}",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        Text(
          "GZ: ${currentStatus.gz}",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        mediumColDivider,
        Text(
          "Pitch: ${currentStatus.pitch}",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        Text(
          "Roll: ${currentStatus.roll}",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        Text(
          "Yaw: ${currentStatus.yaw}",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _DrivingInstructorPageState extends State<DrivingInstructorPage> {
  int touchedIndex = -1;
  bool isRecording = false;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "Driving Instructor",
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(icon: Icon(Icons.drive_eta)),
              Tab(icon: Icon(Icons.settings)),
            ],
          ),
        ),
        body: TabBarView(
          children: [_buildInstructorView(), _buildSettingsView()]
              // Use SingleChildScrollView to enable scrolling when content overflows
              .map(
                (widget) => SingleChildScrollView(
                  padding: const EdgeInsets.all(32.0),
                  child: widget,
                ),
              )
              .toList(),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            setState(() {
              isRecording = !isRecording;
            });
          },
          tooltip: '${isRecording ? 'Stop' : 'Start'} Recording',
          child: Icon(
            isRecording ? Icons.stop_rounded : Icons.play_arrow_rounded,
          ),
        ),
      ),
    );
  }

  Widget _buildInstructorView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Your Driving Score",
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        smallColDivider,
        const Center(child: EcoScore(score: 70.0)),
        smallColDivider,
        Center(
          child: MotionDisplay(
            tracker: SensorTracker(manager: widget.manager),
          ),
        ),
        smallColDivider,
        Text(
          "Violation History",
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        smallColDivider,
        Logbook(
          entries: [
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.rapidAcceleration,
            ),
            LogEntry(timestamp: DateTime.now(), kind: Violation.missedBlinking),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.didntCheckBlindspot,
            ),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.rapidAcceleration,
            ),
            LogEntry(timestamp: DateTime.now(), kind: Violation.missedBlinking),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.didntCheckBlindspot,
            ),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.rapidAcceleration,
            ),
            LogEntry(timestamp: DateTime.now(), kind: Violation.missedBlinking),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.didntCheckBlindspot,
            ),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.rapidAcceleration,
            ),
            LogEntry(timestamp: DateTime.now(), kind: Violation.missedBlinking),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.didntCheckBlindspot,
            ),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.rapidAcceleration,
            ),
            LogEntry(timestamp: DateTime.now(), kind: Violation.missedBlinking),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.didntCheckBlindspot,
            ),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.rapidAcceleration,
            ),
            LogEntry(timestamp: DateTime.now(), kind: Violation.missedBlinking),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.didntCheckBlindspot,
            ),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.rapidAcceleration,
            ),
            LogEntry(timestamp: DateTime.now(), kind: Violation.missedBlinking),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.didntCheckBlindspot,
            ),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.rapidAcceleration,
            ),
            LogEntry(timestamp: DateTime.now(), kind: Violation.missedBlinking),
            LogEntry(
              timestamp: DateTime.now(),
              kind: Violation.didntCheckBlindspot,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsView() {
    return Center(child: Text("Settings"));
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
      //constraints: BoxConstraints(minWidth: 100, maxWidth: 200),
      constraints: BoxConstraints.expand(width: targetSize, height: targetSize),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: CircularStepProgressIndicator(
          totalSteps: resolution * 100,
          currentStep: (score * resolution).toInt(),
          stepSize: 10,
          selectedStepSize: 20,
          selectedColor: Colors.greenAccent,
          unselectedColor: Colors.grey[200],
          //gradientColor: LinearGradient(
          //  colors: [Color(0xFFFDAF31), Color(0xFFFDD060)],
          //),
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
      ),
    );
  }
}

extension IntersperseExtension<T> on List<T> {
  List<U> intersperse<U extends T>(U element) {
    if (length < 2) return this as List<U>;
    final List<U> result = [];
    for (var i = 0; i < length; i++) {
      result.add(this[i] as U);
      if (i < length - 1) {
        result.add(element);
      }
    }
    return result;
  }
}

class Logbook extends StatelessWidget {
  final List<LogEntry> entries;

  const Logbook({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: (entries as List<Widget>).intersperse(rowDivider),
      ),
    );
  }
}

enum Violation {
  rapidAcceleration(description: "Accelerated too rapidly"),
  missedBlinking(description: "Forgot to blink while turning"),
  didntCheckBlindspot(description: "Didn't check blindspot while turning");

  final String description;

  const Violation({required this.description});
}

class LogEntry extends StatelessWidget {
  final DateTime timestamp;
  final Violation kind;

  const LogEntry({super.key, required this.timestamp, required this.kind});

  @override
  Widget build(BuildContext context) {
    // TODO: Implement horizontal wrapping if screen is too narrow
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          timestamp.toIso8601String(),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        rowDivider,
        Text(kind.description, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
