import 'dart:async';
import 'dart:math';

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:flutter/material.dart';
import 'package:step_progress_indicator/step_progress_indicator.dart';
import 'sensor.dart';
import 'utils.dart';

import 'package:provider/provider.dart';
import 'package:open_wearable/widgets/sensors/values/sensor_value_card.dart';
import 'package:open_wearable/view_models/sensor_data_provider.dart';

const mediumColDivider = SizedBox(height: 32);
const smallColDivider = SizedBox(height: 16);
const largeColDivider = SizedBox(height: 30);

const rowDivider = SizedBox(width: 20);

class DrivingInstructorPage extends StatefulWidget {
  final Wearable wearable;
  final SensorManager manager;

  const DrivingInstructorPage({
    super.key,
    required this.wearable,
    required this.manager,
  });

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

enum DetectionStatus {
  none("Detecting...", Colors.grey, Icons.hourglass_empty),
  left("Looking Left", Colors.green, Icons.turn_left_rounded),
  stronglyLeft(
    "Looking Strongly Left",
    Colors.greenAccent,
    Icons.arrow_back_rounded,
  ),
  right("Looking Right", Colors.lightBlue, Icons.turn_right_rounded),
  stronglyRight(
    "Looking Strongly Right",
    Colors.blueAccent,
    Icons.arrow_forward_rounded,
  );

  final String text;
  final Color color;
  final IconData icon;

  const DetectionStatus(this.text, this.color, this.icon);
}

/// This class keeps track of the current head turn state based on the sensor data.
class DetectionStateMachine {
  static final double angleThreshold = 15.0; // degrees

  /// The current estimated angle of the head.
  /// 0.0° is forward, negative is left, positive is right.
  double currentAngle = 0.0; // looking forward

  /// The last time the state changed, e.g. from left to right or to center.
  DateTime _lastStateChange = DateTime.now();

  /// The last time the sensor status was updated.
  DateTime? _lastStatusTime;

  /// Call this function repeatedly with new sensor data to update the state machine.
  void update(SensorStatus status) {
    if (_lastStatusTime == null) {
      _lastStatusTime = status.timestamp;
      return;
    }

    _lastStatusTime = status.timestamp;

    var previousStatus = currentStatus();
    // degrees per second = degrees / seconds
    //
    // by multiplying with the seconds it took since the last update,
    // it will return the angle change since the last update.
    //
    // This is a basic integration, assuming constant angular velocity.
    // Could be improved, but this already works reasonably well.
    currentAngle += status.gx * (1.0 / 50.0); // TODO: Use actual frequency

    // It could happen that the state machine gets stuck in a specific state,
    // maybe due to drift, noise or measurement errors.
    //
    // To mitigate this, we reset the state to center if no changes have occurred
    // for a certain amount of time. It assumes that when people are driving,
    // they generally look forward most of the time, and only glance left/right briefly.
    if (currentStatus() != previousStatus) {
      _lastStateChange = DateTime.now();
    }

    // TODO: Make this configurable
    if (_lastStateChange.difference(DateTime.now()).inMilliseconds.abs() >
        4000) {
      print("Force resetting state machine to center");
      // Reset to center after some seconds of no changes
      currentAngle = 0.0;
      _lastStateChange = DateTime.now();
    }
  }

  DetectionStatus currentStatus() {
    if (currentAngle < -angleThreshold) {
      if (currentAngle < -angleThreshold * 2) {
        return DetectionStatus.stronglyLeft;
      }

      return DetectionStatus.left;
    } else if (currentAngle > angleThreshold) {
      if (currentAngle > angleThreshold * 2) {
        return DetectionStatus.stronglyRight;
      }
      return DetectionStatus.right;
    } else {
      return DetectionStatus.none;
    }
  }
}

class _MotionDisplayState extends State<MotionDisplay> {
  static final Duration sensorRefreshInterval = Duration(milliseconds: 100);

  SensorStatus currentStatus = SensorStatus();
  StreamSubscription<SensorStatus>? status;
  DetectionStatus detectionStatus = DetectionStatus.none;
  DetectionStateMachine stateMachine = DetectionStateMachine();
  DateTime _lastUpdate = DateTime.now();

  @override
  void initState() {
    status =
        widget.tracker.streamGyroStatus().listen((SensorStatus sensorStatus) {
      currentStatus = sensorStatus;
      _runDetectionLoop();
    });

    super.initState();
  }

  @override
  void dispose() {
    status?.cancel();
    super.dispose();
  }

  void _runDetectionLoop() {
    stateMachine.update(currentStatus);

    DetectionStatus newStatus = stateMachine.currentStatus();

    if (newStatus != detectionStatus) {
      print(newStatus);
      setState(() {
        detectionStatus = newStatus;
      });
    } else if (DateTime.now().difference(_lastUpdate) > sensorRefreshInterval) {
      setState(() {}); // Refresh graphs/raw numbers
      _lastUpdate = DateTime.now();
    }
  }

  Widget _dataColumn(String label, double value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value.toStringAsFixed(3),
          style: const TextStyle(fontSize: 18, fontFamily: 'Monospace'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DetectionStatusCard(
          status: detectionStatus.text,
          statusColor: detectionStatus.color,
          icon: detectionStatus.icon,
        ),
        mediumColDivider,
        const Text(
          "Real-time Sensor Data",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        smallColDivider,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _dataColumn("Gyro X", currentStatus.gx),
            _dataColumn("Gyro Y", currentStatus.gy),
            _dataColumn("Gyro Z", currentStatus.gz),
          ],
        ),
        smallColDivider,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _dataColumn("Accel X", currentStatus.ax),
            _dataColumn("Accel Y", currentStatus.ay),
            _dataColumn("Accel Z", currentStatus.az),
          ],
        ),
        smallColDivider,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _dataColumn("Angle", stateMachine.currentAngle),
          ],
        ),
        mediumColDivider,
        ElevatedButton(
          onPressed: () async {
            // TODO: Add a minor calibration screen with instructions like "Place the device on a flat surface",
            //       and maybe a small timer?
            await status?.cancel();
            await widget.tracker
                .calibrate(targetDuration: Duration(milliseconds: 3000));
            status = widget.tracker
                .streamStatus()
                .listen((SensorStatus sensorStatus) {
              setState(() {
                currentStatus = sensorStatus;
              });
            });
          },
          child: const Text("Calibrate Sensors"),
        ),
      ],
    );
  }
}

class _DrivingInstructorPageState extends State<DrivingInstructorPage> {
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
            tracker: EsenseSensorTracker(manager: widget.manager),
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
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsView() {
    var children = <Widget>[];

    for (var sensor in widget.manager.sensors) {
      var wrappedSensor =
          EsenseSensorWrapper(sensor: sensor, samplingFrequencyHz: 50.0);
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

class DetectionStatusCard extends StatelessWidget {
  final Color _statusColor;
  final String _status;
  final IconData _icon;

  const DetectionStatusCard({
    super.key,
    required String status,
    required Color statusColor,
    required IconData icon,
  })  : _status = status,
        _statusColor = statusColor,
        _icon = icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _statusColor, width: 2),
      ),
      child: Column(
        children: [
          Icon(_icon, size: 50, color: _statusColor),
          const SizedBox(height: 10),
          Text(
            _status,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _statusColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
