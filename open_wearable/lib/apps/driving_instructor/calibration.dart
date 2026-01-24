import 'package:flutter/material.dart';

import 'package:open_wearable/apps/driving_instructor/utils.dart';
import 'package:open_wearable/apps/driving_instructor/sensor.dart';

/// This class is the calibration screen that instructs the user on how to
/// do the calibration correctly.
class CalibrationScreen extends StatelessWidget {
  final SensorTracker tracker;

  const CalibrationScreen({
    super.key,
    required this.tracker,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(
          "Lay the wearable flat on a table with the rubber ring facing towards the ceiling.",
        ),
        smallColDivider,
        Text("Do not move the wearable during the calibration process."),
        smallColDivider,
        Text("Press the button below to start the calibration."),
        Text(
          "The screen will automatically close when the calibration is complete.",
        ),
        ElevatedButton(
          onPressed: () async {
            await tracker.calibrate(
              targetDuration: Duration(milliseconds: 3000),
            );

            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text("Calibrate Sensors"),
        ),
      ],
    );
  }
}
