import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:vector_math/vector_math.dart';

const mediumColDivider = SizedBox(height: 32);
const smallColDivider = SizedBox(height: 16);
const largeColDivider = SizedBox(height: 30);

const rowDivider = SizedBox(width: 20);

const EdgeInsets itemPadding =
    EdgeInsets.symmetric(horizontal: 16, vertical: 8);

extension VectorStreamExt on Stream<Vector3> {
  /// Implements a rolling average over the stream of Vector3 data
  Stream<Vector3> rollingAverage(int windowSize) {
    final List<Vector3> buffer = [];
    return transform(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) {
          buffer.add(data);
          if (buffer.length > windowSize) {
            buffer.removeAt(0);
          }
          final avgX = buffer
                  .map((v) => v.x)
                  .reduce((value, element) => value + element) /
              buffer.length;
          final avgY = buffer
                  .map((v) => v.y)
                  .reduce((value, element) => value + element) /
              buffer.length;
          final avgZ = buffer
                  .map((v) => v.z)
                  .reduce((value, element) => value + element) /
              buffer.length;
          sink.add(Vector3(avgX, avgY, avgZ));
        },
      ),
    );
  }
}

extension VectorIterableExt on Iterable<Vector3> {
  Vector3 average() {
    if (isEmpty) {
      return Vector3.zero();
    }
    double sumX = 0.0;
    double sumY = 0.0;
    double sumZ = 0.0;
    int count = 0;

    for (var vector in this) {
      sumX += vector.x;
      sumY += vector.y;
      sumZ += vector.z;
      count++;
    }

    return Vector3(sumX / count, sumY / count, sumZ / count);
  }
}

extension RollingAverageExt on Stream<SensorDoubleValue> {
  /// Implements a rolling average over the stream of Vector3 data
  Stream<SensorDoubleValue> rollingAverage(int windowSize) {
    final List<SensorDoubleValue> buffer = [];
    return transform(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) {
          buffer.add(data);
          if (buffer.length > windowSize) {
            buffer.removeAt(0);
          }

          int index = 0;
          List<double> avgValues = [];
          for (var _ in data.values) {
            avgValues.add(
              buffer
                      .map((v) => v.values[index])
                      .reduce((value, element) => value + element) /
                  buffer.length,
            );

            index += 1;
          }

          sink.add(
            SensorDoubleValue(values: avgValues, timestamp: data.timestamp),
          );
        },
      ),
    );
  }
}

extension DurationExt on Duration {
  /// Converts the duration to a double representing the total number of seconds.
  ///
  /// For example, a duration of 1 second and 500 milliseconds would be converted to 1.5.
  ///
  /// Returns a double value representing the total seconds.
  double toSecondsDouble() {
    return inMicroseconds.toDouble() /
        Duration.microsecondsPerSecond.toDouble();
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

// copy-paste, because utils/simple_kalman.dart is not exported by the earable package

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

class PopupWindow extends StatelessWidget {
  final String title;
  final Widget child;

  const PopupWindow({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: itemPadding,
        child: child,
      ),
    );
  }
}

Future<Object?> openPopupWindow({
  required BuildContext context,
  required String title,
  required Widget child,
}) async {
  return Navigator.push(
    context,
    PageRouteBuilder(
      fullscreenDialog: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation1, animation2) => PopupWindow(
        title: title,
        child: child,
      ),
    ),
  );
}

class SectionName extends StatelessWidget {
  final String name;

  const SectionName({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        name.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
