import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

import '../firebase_options_dev.dart';

class FirebaseDevBootstrap {
  static Future<FirebaseApp>? _initialization;
  static const useLocalEmulators = bool.fromEnvironment(
    'USE_LOCAL_FIREBASE_EMULATORS',
  );
  static FirebaseApp? _app;
  static FirebaseApp get app => _app ?? Firebase.app();

  static AndroidAppCheckProvider androidProvider({required bool debug}) => debug
      ? const AndroidDebugProvider()
      : const AndroidPlayIntegrityProvider();
  static AppleAppCheckProvider appleProvider({required bool debug}) => debug
      ? const AppleDebugProvider()
      : const AppleAppAttestWithDeviceCheckFallbackProvider();
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
        options.appId != expectedAppIds[platform] ||
        options.messagingSenderId != '1086662773964' ||
        options.storageBucket != 'matematik-evreni-dev.firebasestorage.app' ||
        (platform == TargetPlatform.iOS &&
            options.iosBundleId != 'com.fatihbozkurt.matematik.dev')) {
      throw StateError('Firebase app/project identity mismatch.');
    }
    return options;
  }

  static Future<FirebaseApp> initialize() {
    return _initialization ??= _initialize().catchError((Object error) {
      _initialization = null;
      throw error;
    });
  }

  static Future<FirebaseApp> _initialize() async {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured.');
    }
    final options = optionsFor(
      flavor: appFlavor,
      platform: defaultTargetPlatform,
    );
    if (useLocalEmulators) {
      if (!kDebugMode || appFlavor != 'dev') {
        throw StateError('EMULATOR_DEBUG_ONLY');
      }
      final app = await Firebase.initializeApp(
        name: 'local-demo',
        options: FirebaseOptions(
          apiKey: options.apiKey,
          appId: options.appId,
          messagingSenderId: options.messagingSenderId,
          projectId: 'demo-matematik-evreni',
          storageBucket: 'demo-matematik-evreni.firebasestorage.app',
        ),
      );
      const host = String.fromEnvironment(
        'FIREBASE_EMULATOR_HOST',
        defaultValue: '127.0.0.1',
      );
      await FirebaseAuth.instanceFor(app: app)
          .useAuthEmulator(host, 9099, automaticHostMapping: false);
      FirebaseFirestore.instanceFor(app: app)
          .useFirestoreEmulator(host, 8080, automaticHostMapping: false);
      FirebaseFunctions.instanceFor(
        app: app,
        region: 'europe-west1',
      ).useFunctionsEmulator(host, 5001, automaticHostMapping: false);
      await FirebaseStorage.instanceFor(app: app)
          .useStorageEmulator(host, 9199, automaticHostMapping: false);
      _app = app;
      return app;
    }
    final app = Firebase.apps.any((app) => app.name == '[DEFAULT]')
        ? Firebase.app()
        : await Firebase.initializeApp(options: options);
    if (app.options.projectId != options.projectId ||
        app.options.appId != options.appId) {
      throw StateError('FIREBASE_EXISTING_APP_MISMATCH');
    }
    final appCheck = FirebaseAppCheck.instanceFor(app: app);
    await appCheck.activate(
      providerAndroid: androidProvider(debug: kDebugMode),
      providerApple: appleProvider(debug: kDebugMode),
    );
    if (kDebugMode) unawaited(appCheck.getToken().catchError((_) => null));
    _app = app;
    return app;
  }
}
