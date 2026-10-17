import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matematik/app/firebase_dev_bootstrap.dart';

void main() {
  test('dev maps to the registered Android and iOS apps', () {
    final android = FirebaseDevBootstrap.optionsFor(
      flavor: 'dev',
      platform: TargetPlatform.android,
    );
    final ios = FirebaseDevBootstrap.optionsFor(
      flavor: 'dev',
      platform: TargetPlatform.iOS,
    );

    expect(android.projectId, 'matematik-evreni-dev');
    expect(ios.projectId, 'matematik-evreni-dev');
    expect(android.messagingSenderId, '1086662773964');
    expect(ios.messagingSenderId, '1086662773964');
    expect(android.storageBucket, 'matematik-evreni-dev.firebasestorage.app');
    expect(ios.storageBucket, 'matematik-evreni-dev.firebasestorage.app');
    expect(ios.iosBundleId, 'com.fatihbozkurt.matematik.dev');
    expect(android.appId, isNot(ios.appId));
  });

  test('dev configuration refuses other flavors and platforms', () {
    for (final flavor in <String?>[null, 'staging', 'prod']) {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(
          () => FirebaseDevBootstrap.optionsFor(
            flavor: flavor,
            platform: platform,
          ),
          throwsStateError,
        );
      }
    }
    expect(
      () => FirebaseDevBootstrap.optionsFor(
        flavor: 'dev',
        platform: TargetPlatform.macOS,
      ),
      throwsUnsupportedError,
    );
  });
}
