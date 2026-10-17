import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

import '../firebase_options_dev.dart';

class FirebaseDevBootstrap {
  static FirebaseOptions optionsFor({
    required String? flavor,
    required TargetPlatform platform,
  }) {
    if (flavor != 'dev') {
      throw StateError('Firebase dev configuration requires the dev flavor.');
    }

    final options = switch (platform) {
      TargetPlatform.android => DefaultFirebaseOptions.android,
      TargetPlatform.iOS => DefaultFirebaseOptions.ios,
      _ => throw UnsupportedError('Only Android and iOS are configured.'),
    };

    const expectedAppIds = {
      TargetPlatform.android: '1:1086662773964:android:429cd8d2400e93844fc669',
      TargetPlatform.iOS: '1:1086662773964:ios:7425a6009625acec4fc669',
    };
    if (options.projectId != 'matematik-evreni-dev' ||
        options.appId != expectedAppIds[platform]) {
      throw StateError('Firebase app/project identity mismatch.');
    }
    return options;
  }

  // Call only after the adult has accepted the required account data processing.
  static Future<FirebaseApp> initializeAfterAdultConsent() {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured.');
    }
    final options = optionsFor(
      flavor: appFlavor,
      platform: defaultTargetPlatform,
    );
    return Firebase.initializeApp(options: options);
  }
}
