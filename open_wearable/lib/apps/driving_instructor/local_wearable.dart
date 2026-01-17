import 'dart:async';
import 'dart:math';

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:universal_ble/universal_ble.dart';

import 'mahony_ahrs.dart';

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
          axisUnits: ["g", "g", "g"], // TODO: convert to m/s²?
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
        // TODO: This one doesn't technically exist in the earable, but it is useful
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
  Future<void> disconnect() async {
    // TODO: implement disconnect?
  }

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

    // TODO: Is this specific to the earable device?
    // x, y, z was changed in firmware to -x, z, y
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
      // TODO: original code had an onError handler here
    );

    var gyroSubscription = gyroscopeEventStream().listen(
      (GyroscopeEvent event) {
        _sensorState.gx = event.x;
        _sensorState.gy = event.y;
        _sensorState.gz = event.z;

        Map<String, dynamic> parsedData = buildParsedData();

        streamController.add(parsedData);
      },
      // TODO: original code had an onError handler here
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

// copy-pasta, because utils/simple_kalman.dart is not exported by the earable package

/// Here is a one-dimensional Kalman filter.
///
/// {@category Filter}
class SimpleKalman {
  /// value range
  final double errorMeasure;

  /// error range
  double errorEstimate;

  /// filter sensitivity factor (0.001 ... 10)
  final double q;

  double _lastEstimate = 0.0;

  /// Create Kalman filter object
  SimpleKalman({
    required this.errorMeasure,
    required this.errorEstimate,
    required this.q,
  });

  /// Function to filter values
  double filtered(double value) {
    double kalmanGain;
    double currentEstimate;
    kalmanGain = errorEstimate / (errorEstimate + errorMeasure);
    currentEstimate = _lastEstimate + kalmanGain * (value - _lastEstimate);
    errorEstimate = (1.0 - kalmanGain) * errorEstimate +
        (_lastEstimate - currentEstimate).abs() * q;
    _lastEstimate = currentEstimate;

    return currentEstimate;
  }
}
