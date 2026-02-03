import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_wearable/apps/driving_instructor/location.dart';
import 'package:open_wearable/apps/driving_instructor/logs.dart';
import 'package:open_wearable/apps/driving_instructor/sensor.dart';
import 'package:open_wearable/apps/driving_instructor/utils.dart';
import 'package:open_wearable/apps/driving_instructor/settings.dart';
import 'package:sensors_plus/sensors_plus.dart';

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
  ),
  acceleration("Accelerating", Colors.orange, Icons.speed),
  braking("Braking", Colors.redAccent, Icons.car_crash);

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
      return currentAngle < -strongAngleThreshold
          ? _DetectionStatus.stronglyLeft
          : _DetectionStatus.left;
    }

    if (currentAngle > angleThreshold) {
      return currentAngle > strongAngleThreshold
          ? _DetectionStatus.stronglyRight
          : _DetectionStatus.right;
    }

    return _DetectionStatus.none;
  }
}

/// This class tracks the linear acceleration of the phone
/// to detect acceleration and braking events.
class _AccelerationTracker extends ValueNotifier<_DetectionStatus> {
  StreamSubscription? _streamSubscription;

  DateTime _lastDetectionTime = DateTime.now();

  UserAccelerometerEvent? userAccelEvent;

  final int sessionId;

  _AccelerationTracker({required this.sessionId})
      : super(_DetectionStatus.none) {
    startTracking();
  }

  void startTracking() {
    _lastDetectionTime = DateTime.now();
    if (_streamSubscription != null) {
      return; // already started
    }

    // Initially I planned on using the accelerometer stream,
    // which exposes the raw accelerometer data of the phone,
    // but gravity is interfering too much with the data, resulting
    // in a lot of false positives.
    //
    // For example going uphill or downhill will result in a constant acceleration
    // on the relevant axis, which would be detected as acceleration/braking.
    //
    // The user event stream has these filtered out, providing much cleaner data to work with.

    _streamSubscription = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((UserAccelerometerEvent event) {
      userAccelEvent = event;

      if (super.value == _DetectionStatus.none &&
          event.y > ActiveSettings().accelerationThreshold()) {
        print("Detected acceleration event: ${event.y}");
        super.value = _DetectionStatus.acceleration;
      } else if (super.value == _DetectionStatus.none &&
          event.y < ActiveSettings().brakingThreshold()) {
        print("Detected braking event: ${event.y}");
        super.value = _DetectionStatus.braking;
      } else if (super.value != _DetectionStatus.none &&
          // This debounce ensures that we don't log multiple events in quick succession
          // that might be caused by noise or unexpected driving behavior.
          DateTime.now().difference(_lastDetectionTime) >
              Duration(seconds: 3) &&
          event.y.abs() < ActiveSettings().accelDetectionEnd()) {
        print("Adding acceleration/braking log entry");
        _lastDetectionTime = DateTime.now();

        ActiveSettings().addLogEntry(
          LogEntryCard(
            kind: _DetectionStatus.acceleration == super.value
                ? LogKind.acceleration
                : LogKind.braking,
            timestamp: DateTime.now(),
            location: CurrentLocationTracker().currentLocation(),
            drivingSession: sessionId,
          ),
        );
        super.value = _DetectionStatus.none;
      }
    });
  }

  void stopTracking() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}

/// This class tracks the mirror checks of the user based on the gyroscope data
/// of the esense wearable.
///
/// It logs an awareness log entry if the user hasn't looked left/right
/// for a certain amount of time.
class _MirrorTracker extends ValueNotifier<_DetectionStatus> {
  DateTime _lastLeftMirrorCheck = DateTime.now();
  DateTime _lastRightMirrorCheck = DateTime.now();

  StreamSubscription<SensorStatus>? _streamSubscription;
  _DetectionStateMachine stateMachine = _DetectionStateMachine();

  final int sessionId;

  _MirrorTracker({required this.sessionId, required SensorTracker tracker})
      : super(_DetectionStatus.none) {
    startTracking(tracker);
  }

  void startTracking(SensorTracker tracker) {
    print("Starting mirror tracking");
    if (_streamSubscription != null) {
      return; // already started
    }

    _streamSubscription = tracker.streamGyroStatus().listen(_evaluateStatus);
  }

  void stopTracking() {
    print("Stopping mirror tracking");
    _streamSubscription?.cancel();
    _streamSubscription = null;
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }

  void _evaluateStatus(SensorStatus currentStatus) {
    stateMachine.update(currentStatus);

    _DetectionStatus newStatus = stateMachine.currentStatus();

    if (newStatus != super.value) {
      print(newStatus);

      print("Updating mirror check timestamps");
      switch (newStatus) {
        case _DetectionStatus.left:
          _lastLeftMirrorCheck = DateTime.now();
          break;
        case _DetectionStatus.right:
          _lastRightMirrorCheck = DateTime.now();
          break;
        default:
          break;
      }

      super.value = newStatus;
    }

    Duration mirrorCheckInterval = ActiveSettings().mirrorCheckDuration();

    if (DateTime.now().difference(_lastLeftMirrorCheck) > mirrorCheckInterval ||
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

/// This widget displays the current motion status of the user.
///
/// It is what will be shown when the user starts the recording session.
class MotionDisplay extends StatefulWidget {
  final SensorTracker tracker;
  final int sessionId;

  const MotionDisplay({
    super.key,
    required this.tracker,
    required this.sessionId,
  });

  @override
  State<MotionDisplay> createState() => _MotionDisplayState();
}

class _MotionDisplayState extends State<MotionDisplay> {
  static final Duration sensorRefreshInterval = Duration(milliseconds: 100);

  SensorStatus _currentStatus = SensorStatus();
  StreamSubscription<SensorStatus>? _streamSubscription;
  DateTime _lastUpdate = DateTime.now();

  late _MirrorTracker _mirrorTracker;
  late _AccelerationTracker _accelTracker;

  @override
  void initState() {
    _startTracking();

    super.initState();
  }

  void _startTracking() {
    _mirrorTracker =
        _MirrorTracker(sessionId: widget.sessionId, tracker: widget.tracker);
    _accelTracker = _AccelerationTracker(sessionId: widget.sessionId);

    _streamSubscription =
        widget.tracker.streamGyroStatus().listen((SensorStatus sensorStatus) {
      if (DateTime.now().difference(_lastUpdate) > sensorRefreshInterval) {
        setState(() {
          _currentStatus = sensorStatus;
        });
        _lastUpdate = DateTime.now();
      }
    });
  }

  @override
  void activate() {
    _startTracking();
    super.activate();
  }

  @override
  void deactivate() {
    _stopTracking();
    super.deactivate();
  }

  void _stopTracking() {
    _streamSubscription?.cancel();
    _accelTracker.stopTracking();
    _mirrorTracker.stopTracking();
  }

  @override
  void dispose() {
    _stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([_mirrorTracker, _accelTracker]),
          builder: (context, child) {
            var detectionStatus = _mirrorTracker.value;
            var detectionAccelStatus = _accelTracker.value;

            // These events are independent, so acceleration/braking can occur while the driver is looking left/right.
            //
            // Ideally both should be shown:
            //
            // Mirror | Acceleration | Display
            // ------------------------------
            // None   | None         | None
            // Left   | None         | Left
            // Right  | None         | Right
            // None   | Accel        | Accel
            // None   | Braking      | Braking
            // Left   | Accel        | Left + Accel
            // Right  | Braking      | Right + Braking
            // etc.

            if (detectionAccelStatus == _DetectionStatus.none) {
              return SizedBox(
                width: MediaQuery.of(context).size.width - 20.0,
                child: _DetectionStatusCard(
                  status: detectionStatus.text,
                  statusColor: detectionStatus.color,
                  icon: detectionStatus.icon,
                ),
              );
            }

            if (detectionStatus == _DetectionStatus.none) {
              return SizedBox(
                width: MediaQuery.of(context).size.width - 20.0,
                child: _DetectionStatusCard(
                  status: detectionAccelStatus.text,
                  statusColor: detectionAccelStatus.color,
                  icon: detectionAccelStatus.icon,
                ),
              );
            }

            var targetWidth = (MediaQuery.of(context).size.width - 50.0) / 2.0;

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: targetWidth,
                  child: _DetectionStatusCard(
                    status: detectionStatus.text,
                    statusColor: detectionStatus.color,
                    icon: detectionStatus.icon,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: targetWidth,
                  child: _DetectionStatusCard(
                    status: detectionAccelStatus.text,
                    statusColor: detectionAccelStatus.color,
                    icon: detectionAccelStatus.icon,
                  ),
                ),
              ],
            );
          },
        ),
        if (ActiveSettings().showDebugInformation())
          ..._buildDebugInfo(context),
      ],
    );
  }

  Iterable<Widget> _buildDebugInfo(BuildContext context) {
    return [
      smallColDivider,
      const Text(
        "Real-time Sensor Data",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      smallColDivider,
      _SensorDataRow(
        data: {
          "Gyro X": _currentStatus.gx,
          "Gyro Y": _currentStatus.gy,
          "Gyro Z": _currentStatus.gz,
        },
      ),
      smallColDivider,
      _SensorDataRow(
        data: {
          "Accel X": _accelTracker.userAccelEvent?.x ?? 0.0,
          "Accel Y": _accelTracker.userAccelEvent?.y ?? 0.0,
          "Accel Z": _accelTracker.userAccelEvent?.z ?? 0.0,
        },
      ),
      smallColDivider,
      _SensorDataRow(
        data: {
          "Angle": _mirrorTracker.stateMachine.currentAngle,
        },
      ),
    ];
  }
}

class _SensorDataRow extends StatelessWidget {
  final Map<String, double> data;

  const _SensorDataRow({required this.data});

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: data.entries
          .map((entry) => _dataColumn(entry.key, entry.value))
          .toList(),
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
          ),
        ],
      ),
    );
  }
}
