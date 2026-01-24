import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_wearable/apps/driving_instructor/location.dart';
import 'package:open_wearable/apps/driving_instructor/logs.dart';
import 'package:open_wearable/apps/driving_instructor/sensor.dart';
import 'package:open_wearable/apps/driving_instructor/utils.dart';
import 'package:open_wearable/apps/driving_instructor/settings.dart';

/// This enum represents the different detected motion states.
///
/// It is used to represent whether the user is looking left, right, or forward.
/// It also has states for strongly left/right to indicate more direct head turns.
enum _DetectionStatus {
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

  const _DetectionStatus(this.text, this.color, this.icon);
}

/// This class keeps track of the current head turn state based on the sensor data.
class _DetectionStateMachine {
  static final double angleThreshold =
      ActiveSettings().turnThreshold(); // degrees
  static final double strongAngleThreshold = angleThreshold * 2; // degrees
  static final Duration resetAfterDuration =
      ActiveSettings().resetAfterDuration();
  static final double pollingFrequency =
      ActiveSettings().pollingFrequency(); // Hz

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
    currentAngle += status.gx * (1.0 / pollingFrequency);

    // It could happen that the state machine gets stuck in a specific state,
    // maybe due to drift, noise or measurement errors.
    //
    // To mitigate this, we reset the state to center if no changes have occurred
    // for a certain amount of time. It assumes that when people are driving,
    // they generally look forward most of the time, and only glance left/right briefly.
    if (currentStatus() != previousStatus) {
      _lastStateChange = DateTime.now();
    }

    if (_lastStateChange.difference(DateTime.now()).inMilliseconds.abs() >
        resetAfterDuration.inMilliseconds) {
      print("Force resetting state machine to center");
      // Reset to center after some seconds of no changes
      currentAngle = 0.0;
      _lastStateChange = DateTime.now();
    }
  }

  /// Computes the current detection status based on the current angle.
  _DetectionStatus currentStatus() {
    if (currentAngle < -angleThreshold) {
      if (currentAngle < -angleThreshold * 2) {
        return _DetectionStatus.stronglyLeft;
      }

      return _DetectionStatus.left;
    } else if (currentAngle > angleThreshold) {
      if (currentAngle > angleThreshold * 2) {
        return _DetectionStatus.stronglyRight;
      }
      return _DetectionStatus.right;
    } else {
      return _DetectionStatus.none;
    }
  }
}

/// This widget displays the current motion status of the user.
///
/// It is what will be shown when the user starts the recording session.
class MotionDisplay extends StatefulWidget {
  final SensorTracker tracker;

  const MotionDisplay({
    super.key,
    required this.tracker,
  });

  @override
  State<MotionDisplay> createState() => _MotionDisplayState();
}

// TODO: How about separating the detection logic from the display logic?

class _MotionDisplayState extends State<MotionDisplay> {
  static final Duration sensorRefreshInterval = Duration(milliseconds: 100);

  SensorStatus currentStatus = SensorStatus();
  StreamSubscription<SensorStatus>? status;
  _DetectionStatus detectionStatus = _DetectionStatus.none;
  _DetectionStateMachine stateMachine = _DetectionStateMachine();
  DateTime _lastUpdate = DateTime.now();

  DateTime _lastLeftMirrorCheck = DateTime.now();
  DateTime _lastRightMirrorCheck = DateTime.now();

  late final int sessionId;

  @override
  void initState() {
    // TODO: For now this exclusively uses gyro data for head turn detection.
    // Therefore accel data is not shown at all.
    status =
        widget.tracker.streamGyroStatus().listen((SensorStatus sensorStatus) {
      currentStatus = sensorStatus;
      _runDetectionLoop();
    });
    sessionId = ActiveSettings().addDrivingSession(DateTime.now());

    super.initState();
  }

  @override
  void dispose() {
    status?.cancel();
    ActiveSettings().setDrivingSessionEndTime(sessionId, DateTime.now());
    super.dispose();
  }

  void _runDetectionLoop() {
    stateMachine.update(currentStatus);

    _DetectionStatus newStatus = stateMachine.currentStatus();

    if (newStatus != detectionStatus) {
      print(newStatus);

      print("Updating mirror check timestamps");
      switch (newStatus) {
        // TODO: maybe use strongly left/right for mirror checks?
        case _DetectionStatus.left:
          _lastLeftMirrorCheck = DateTime.now();
          break;
        case _DetectionStatus.right:
          _lastRightMirrorCheck = DateTime.now();
          break;
        default:
          break;
      }

      setState(() {
        detectionStatus = newStatus;
      });
    } else if (DateTime.now().difference(_lastUpdate) > sensorRefreshInterval) {
      setState(() {}); // Refresh graphs/raw numbers
      _lastUpdate = DateTime.now();

      Duration mirrorCheckInterval = ActiveSettings().mirrorCheckDuration();

      if (DateTime.now().difference(_lastLeftMirrorCheck) >
              mirrorCheckInterval ||
          DateTime.now().difference(_lastRightMirrorCheck) >
              mirrorCheckInterval) {
        print("Adding awareness log entry");
        _lastLeftMirrorCheck = DateTime.now();
        _lastRightMirrorCheck = DateTime.now();

        // Add a log entry:
        ActiveSettings().addLogEntry(
          LogEntryCard(
            kind: LogKind.awareness,
            timestamp: DateTime.now(),
            location: CurrentLocationTracker().currentLocation(),
            drivingSession: sessionId,
          ),
        );
      }
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
        _DetectionStatusCard(
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
      ],
    );
  }
}

/// This widget displays a card in the specific color, with an icon and status text.
class _DetectionStatusCard extends StatelessWidget {
  final Color _statusColor;
  final String _status;
  final IconData _icon;

  const _DetectionStatusCard({
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
          smallColDivider,
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
