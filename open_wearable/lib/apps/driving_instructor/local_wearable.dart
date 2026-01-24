import 'dart:async';
import 'dart:math';

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:open_wearable/apps/driving_instructor/utils.dart';

// TODO: Make sure your code calls registerDummyWearable
void registerDummyWearable() {
  WearableManager().addWearableFactory(MyCustomWearableFactory());
}

class DummyWearableDisconnectNotifier extends WearableDisconnectNotifier {}

class MyCustomWearableFactory extends WearableFactory {
  @override
  Future<bool> matches(
    DiscoveredDevice device,
    List<BleService> services,
  ) async {
    // Any bluetooth device can be treated as a dummy wearable for testing purposes
    // The phone can not discover itself over bluetooth, so one device would have to
    // serve as a dummy
    return true;
  }

  @override
  Future<Wearable> createFromDevice(
    DiscoveredDevice device, {
    Set<ConnectionOption> options = const {},
  }) async {
    if (bleManager == null) {
      throw Exception("BleGattManager is not initialized");
    }

    return DummyWearableDevice(
      name: device.name,
      disconnectNotifier: DummyWearableDisconnectNotifier(),
      sensors: [
        DummySensor(
          sensorName: "Accelerometer",
          chartTitle: "Accelerometer",
          shortChartTitle: "Accel",
          axisNames: ["X", "Y", "Z"],
          axisUnits: ["m/s²", "m/s²", "m/s²"],
          relatedConfigurations: [],
        ),
        DummySensor(
          sensorName: "Gyroscope",
          chartTitle: "Gyroscope",
          shortChartTitle: "Gyro",
          axisNames: ["X", "Y", "Z"],
          axisUnits: ["dps", "dps", "dps"],
          relatedConfigurations: [],
        ),
        DummySensor(
          sensorName: "Euler",
          chartTitle: "Euler Angles",
          shortChartTitle: "Euler",
          axisNames: ["Yaw", "Pitch", "Roll"],
          axisUnits: ["deg", "deg", "deg"],
          relatedConfigurations: [],
        ),
      ],
    );
  }
}

class DummyWearableDevice extends Wearable
    implements SensorManager, SensorConfigurationManager {
  final List<SensorConfiguration> _sensorConfigs;
  final List<Sensor> _sensors;

  DummyWearableDevice({
    required super.name,
    required super.disconnectNotifier,
    List<Sensor> sensors = const [],
    List<SensorConfiguration> sensorConfigs = const [],
  })  : _sensorConfigs = sensorConfigs,
        _sensors = sensors;

  @override
  Future<void> disconnect() async {}

  @override
  String get deviceId => "dummy_phone_sensors";

  @override
  List<SensorConfiguration<SensorConfigurationValue>>
      get sensorConfigurations => _sensorConfigs;

  @override
  List<Sensor<SensorValue>> get sensors => _sensors;

  @override
  Stream<
      Map<SensorConfiguration<SensorConfigurationValue>,
          SensorConfigurationValue>> get sensorConfigurationStream =>
      const Stream.empty();
}

class SensorState {
  double ax = 0.0;
  double ay = 0.0;
  double az = 0.0;

  double gx = 0.0;
  double gy = 0.0;
  double gz = 0.0;

  DateTime lastUpdate = DateTime.now();

  Map<String, dynamic> toParsedData() {
    return {
      "ACC": {
        "X": ax,
        "Y": ay,
        "Z": az,
      },
      "GYRO": {
        "X": gx,
        "Y": gy,
        "Z": gz,
      },
      "timestamp": lastUpdate.millisecondsSinceEpoch,
    };
  }
}

class DummySensor extends Sensor<SensorDoubleValue> {
  final List<String> _axisNames;
  final List<String> _axisUnits;
  final MahonyAHRS _mahonyAHRS = MahonyAHRS();
  final SensorState _sensorState = SensorState();

  DummySensor({
    required super.sensorName,
    required super.chartTitle,
    required super.shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required super.relatedConfigurations,
  })  : _axisNames = axisNames,
        _axisUnits = axisUnits;

  String _sensorKey() {
    return switch (sensorName.toLowerCase()) {
      "accelerometer" || "acc" => "ACC",
      "gyroscope" || "gyro" => "GYRO",
      "magnetometer" || "mag" => "MAG",
      _ => throw UnimplementedError("Sensor $sensorName not supported"),
    };
  }

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;

  Map<String, dynamic> buildParsedData() {
    var timestamp = DateTime.now();
    Map<String, dynamic> parsedData = _sensorState.toParsedData();
    parsedData["timestamp"] = timestamp.millisecondsSinceEpoch;

    double ax = parsedData["ACC"]["X"];
    double ay = parsedData["ACC"]["Y"];
    double az = parsedData["ACC"]["Z"];

    double gx = parsedData["GYRO"]["X"];
    double gy = parsedData["GYRO"]["Y"];
    double gz = parsedData["GYRO"]["Z"];

    double dt =
        timestamp.difference(_sensorState.lastUpdate).inMilliseconds / 1000.0;

    _mahonyAHRS.update(
      ax,
      ay,
      az,
      gx,
      gy,
      gz,
      dt,
    );

    _sensorState.lastUpdate = DateTime.now();

    List<double> q = _mahonyAHRS.quaternion;
    double yaw = -atan2(
      2 * (q[0] * q[3] + q[1] * q[2]),
      1 - 2 * (q[2] * q[2] + q[3] * q[3]),
    );

    // Pitch (around Y-axis)
    double pitch = -asin(2 * (q[0] * q[2] - q[3] * q[1]));

    // Roll (around X-axis)
    double roll = -atan2(
      2 * (q[0] * q[1] + q[2] * q[3]),
      1 - 2 * (q[1] * q[1] + q[2] * q[2]),
    );

    parsedData["EULER"] = {};
    parsedData["EULER"]["YAW"] = yaw * 57.2957795;
    parsedData["EULER"]["PITCH"] = pitch * 57.2957795;
    parsedData["EULER"]["ROLL"] = roll * 57.2957795;
    parsedData["EULER"]
        ["units"] = {"YAW": "deg", "PITCH": "deg", "ROLL": "deg"};

    return parsedData;
  }

  Stream<Map<String, dynamic>> subscribeToSensorData() {
    StreamController<Map<String, dynamic>> streamController =
        StreamController();
    var accelSubscription = accelerometerEventStream().listen(
      (AccelerometerEvent event) {
        _sensorState.ax = event.x;
        _sensorState.ay = event.y;
        _sensorState.az = event.z;

        Map<String, dynamic> parsedData = buildParsedData();

        streamController.add(parsedData);
      },
    );

    var gyroSubscription = gyroscopeEventStream().listen(
      (GyroscopeEvent event) {
        _sensorState.gx = event.x;
        _sensorState.gy = event.y;
        _sensorState.gz = event.z;

        Map<String, dynamic> parsedData = buildParsedData();

        streamController.add(parsedData);
      },
    );

    streamController.onCancel = () {
      accelSubscription.cancel();
      gyroSubscription.cancel();
    };

    return streamController.stream;
  }

  Stream<SensorDoubleValue> _getAccGyroMagStream() {
    final errorMeasure = {
      "ACC": 5.0,
      "GYRO": 10.0,
      "MAG": 25.0,
    };

    SimpleKalman kalmanX = SimpleKalman(
      errorMeasure: errorMeasure[_sensorKey()]!,
      errorEstimate: errorMeasure[_sensorKey()]!,
      q: 0.9,
    );
    SimpleKalman kalmanY = SimpleKalman(
      errorMeasure: errorMeasure[_sensorKey()]!,
      errorEstimate: errorMeasure[_sensorKey()]!,
      q: 0.9,
    );
    SimpleKalman kalmanZ = SimpleKalman(
      errorMeasure: errorMeasure[_sensorKey()]!,
      errorEstimate: errorMeasure[_sensorKey()]!,
      q: 0.9,
    );

    return subscribeToSensorData().map((data) {
      int timestamp = data["timestamp"];

      return SensorDoubleValue(
        values: [
          kalmanX.filtered(data[_sensorKey()]["X"]),
          kalmanY.filtered(data[_sensorKey()]["Y"]),
          kalmanZ.filtered(data[_sensorKey()]["Z"]),
        ],
        timestamp: timestamp,
      );
    });
  }

  Stream<SensorDoubleValue> _getEulerStream() {
    return subscribeToSensorData().map((data) {
      int timestamp = data["timestamp"];

      return SensorDoubleValue(
        values: [
          data["EULER"]["YAW"],
          data["EULER"]["PITCH"],
          data["EULER"]["ROLL"],
        ],
        timestamp: timestamp,
      );
    });
  }

  @override
  Stream<SensorDoubleValue> get sensorStream {
    switch (sensorName.toLowerCase()) {
      case "accelerometer":
      case "gyroscope":
      case "magnetometer":
        return _getAccGyroMagStream();
      case "euler":
        return _getEulerStream();
      //case "BARO":
      //  return _createSingleDataSubscription("Pressure");
      //case "TEMP":
      //  return _createSingleDataSubscription("Temperature");
      default:
        throw UnimplementedError();
    }
  }
}

// Code from https://github.com/nelsonwenner/mobile-sensors-filter-mahony/

class MahonyAHRS {
  //late double _defaultFrequency = 512.0; // (1.0 / 512.0) sample frequency in Hz
  late double _qW; // data quaternion
  late double _qX; // data quaternion
  late double _qY; // data quaternion
  late double _qZ; // data quaternion
  late double _integralFbX; // apply integral feedback
  late double _integralFbY; // apply integral feedback
  late double _integralFbZ; // apply integral feedback
  late double _ki; // 2 * integral gain (Ki), (2.0 * 0.0) = 0.0
  late double _kp; // 2 * proportional gain (Kp), (2.0 * 0.5) = 1.0

  MahonyAHRS() {
    _qW = 1.0;
    _qX = 0.0;
    _qY = 0.0;
    _qZ = 0.0;
    _integralFbX = 0.0;
    _integralFbY = 0.0;
    _integralFbZ = 0.0;
    _kp = 10.0;
    _ki = 0.0;
  }

  List<double> get quaternion => [_qW, _qX, _qY, _qZ];

  void resetValues() {
    _qW = 1.0;
    _qX = 0.0;
    _qY = 0.0;
    _qZ = 0.0;
    _integralFbX = 0.0;
    _integralFbY = 0.0;
    _integralFbZ = 0.0;
    _kp = 1.0;
    _ki = 0.0;
  }

  void update(
    double ax,
    double ay,
    double az,
    double gx,
    double gy,
    double gz,
    double td,
  ) {
    double q1 = _qW;
    double q2 = _qX;
    double q3 = _qY;
    double q4 = _qZ;

    double norm;
    double vx, vy, vz;
    double ex, ey, ez;
    double pa, pb, pc;

    // Convert gyroscope degrees/sec to radians/sec, deg2rad
    // PI = 3.141592653589793
    // (PI / 180) = 0.0174533
    gx *= 0.0174533;
    gy *= 0.0174533;
    gz *= 0.0174533;

    // Compute feedback only if accelerometer measurement valid
    // (avoids NaN in accelerometer normalisation)
    if ((!((ax == 0.0) && (ay == 0.0) && (az == 0.0)))) {
      // Normalise accelerometer measurement
      norm = 1.0 / sqrt(ax * ax + ay * ay + az * az);
      ax *= norm;
      ay *= norm;
      az *= norm;

      // Estimated direction of gravity
      vx = 2.0 * (q2 * q4 - q1 * q3);
      vy = 2.0 * (q1 * q2 + q3 * q4);
      vz = q1 * q1 - q2 * q2 - q3 * q3 + q4 * q4;

      // Error is cross product between estimated
      // direction and measured direction of gravity
      ex = (ay * vz - az * vy);
      ey = (az * vx - ax * vz);
      ez = (ax * vy - ay * vx);

      if (_ki > 0.0) {
        _integralFbX += ex; // accumulate integral error
        _integralFbY += ey;
        _integralFbZ += ez;
      } else {
        _integralFbX = 0.0; // prevent integral wind up
        _integralFbY = 0.0;
        _integralFbZ = 0.0;
      }

      // Apply feedback terms
      gx += _kp * ex + _ki * _integralFbX;
      gy += _kp * ey + _ki * _integralFbY;
      gz += _kp * ez + _ki * _integralFbZ;
    }

    // Integrate rate of change of quaternion
    gx *= (0.5 * td); // pre-multiply common factors
    gy *= (0.5 * td);
    gz *= (0.5 * td);
    pa = q2;
    pb = q3;
    pc = q4;
    q1 = q1 + (-q2 * gx - q3 * gy - q4 * gz); // create quaternion
    q2 = pa + (q1 * gx + pb * gz - pc * gy);
    q3 = pb + (q1 * gy - pa * gz + pc * gx);
    q4 = pc + (q1 * gz + pa * gy - pb * gx);

    // Normalise _quaternion
    norm = 1.0 / sqrt(q1 * q1 + q2 * q2 + q3 * q3 + q4 * q4);

    _qW = q1 * norm;
    _qX = q2 * norm;
    _qY = q3 * norm;
    _qZ = q4 * norm;
  }
}
