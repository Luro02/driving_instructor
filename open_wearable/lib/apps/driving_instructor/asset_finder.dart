import 'package:flutter/services.dart';

/// Small utility class to list assets from the asset manifest.
///
/// In this app it is used to list available sound files for alerts.
class AssetFinder {
  List<String> manifestContent = [];

  static final AssetFinder _instance = AssetFinder._internal();

  factory AssetFinder() {
    return _instance;
  }

  Future<void> init() async {
    manifestContent =
        (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets();

    print("AssetFinder initialized with ${manifestContent.length} assets");
  }

  AssetFinder._internal();

  List<String> listSounds() {
    return manifestContent
        .where((String key) => key.contains('.mp3') || key.contains('.wav'))
        .toList();
  }
}
