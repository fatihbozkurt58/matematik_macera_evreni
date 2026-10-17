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
    expect(ios.iosBundleId, 'com.fatihbozkurt.matematik.dev');
    expect(android.appId, isNot(ios.appId));
  });

  test('dev configuration refuses other flavors and platforms', () {
    expect(
      () => FirebaseDevBootstrap.optionsFor(
        flavor: 'prod',
        platform: TargetPlatform.android,
      ),
      throwsStateError,
    );
    expect(
      () => FirebaseDevBootstrap.optionsFor(
        flavor: 'dev',
        platform: TargetPlatform.macOS,
      ),
      throwsUnsupportedError,
    );
  });
}
