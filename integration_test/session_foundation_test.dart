import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matematik/app/account_security.dart';
import 'package:matematik/app/firebase_dev_bootstrap.dart';
import 'package:matematik/app/session_preference.dart';
import 'package:matematik/app/student_access.dart';
import 'package:matematik/app/student_profile.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native Auth, profile, session policy, linking and UID isolation', (
    tester,
  ) async {
    expect(
      FirebaseDevBootstrap.useLocalEmulators,
      isTrue,
      reason: 'Refuse tests against live Firebase.',
    );
    final app = await FirebaseDevBootstrap.initialize();
    expect(app.options.projectId, 'demo-matematik-evreni');
    final sdk = FirebaseAuth.instanceFor(app: app);
    final profiles = FirebaseStudentProfileRepository();
    final policy = SecureSessionPreference();
    const phase = String.fromEnvironment(
      'SESSION_TEST_PHASE',
      defaultValue: 'all',
    );
    if (phase != 'all') {
      final phaseAuth = FirebaseStudentAuth();
      if (phase == 'seed') {
        await policy.write(true);
        await phaseAuth.initialize();
        await phaseAuth.signIn(
          'device-fixture-a@example.invalid',
          'SyntheticOnly1234',
        );
      } else if (phase == 'restore') {
        expect((await phaseAuth.initialize())?.uid, 'device-fixture-a');
        await phaseAuth.setStaySignedIn(false);
      } else if (phase == 'forget') {
        expect(await phaseAuth.initialize(), isNull);
        expect(sdk.currentUser, isNull);
        await policy.write(true);
      } else {
        fail('Unknown session test phase');
      }
      return;
    }
    await sdk.signOut();
    await policy.write(true);
    final auth = FirebaseStudentAuth();
    expect(await auth.initialize(), isNull);
    final signedIn = await auth.signIn(
      'device-fixture-a@example.invalid',
      'SyntheticOnly1234',
    );
    expect(signedIn.uid, 'device-fixture-a');
    expect(signedIn.verified, isTrue);
    expect((await auth.refresh())?.uid, signedIn.uid);
    final profile = await profiles.complete(signedIn.uid, 'CihazKaptani', 3);
    expect(profile.uid, signedIn.uid);
    expect(profile.canEnterGame, isFalse);
    expect((await profiles.complete(signedIn.uid, 'CihazKaptani', 3)).grade, 3);
    // A fresh adapter applies the native persisted policy before returning a UID.
    expect((await FirebaseStudentAuth().initialize())?.uid, signedIn.uid);
    await auth.setStaySignedIn(false);
    expect(await FirebaseStudentAuth().initialize(), isNull);
    expect(sdk.currentUser, isNull);
    await policy.write(true);
    await auth.signIn('device-fixture-a@example.invalid', 'SyntheticOnly1234');
    final functions = FirebaseFunctions.instanceFor(
      app: app,
      region: 'europe-west1',
    );
    final security = AccountSecurity(sdk, functions);
    String part(Map<String, Object> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${part({'alg': 'none', 'typ': 'JWT'})}.${part({'sub': 'synthetic-google-subject', 'email': 'synthetic-oauth@example.invalid', 'email_verified': true, 'iss': 'https://accounts.google.com', 'aud': 'demo-matematik-evreni', 'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.';
    final google = GoogleAuthProvider.credential(idToken: token);
    await security.linkCredential(
      reauthentication: EmailAuthProvider.credential(
        email: 'device-fixture-a@example.invalid',
        password: 'SyntheticOnly1234',
      ),
      newCredential: google,
    );
    expect(sdk.currentUser?.uid, signedIn.uid);
    expect(
      sdk.currentUser!.providerData.map((p) => p.providerId),
      contains('google.com'),
    );
    await auth.signOut();
    expect(sdk.currentUser, isNull);
    await auth.signIn('device-fixture-b@example.invalid', 'SyntheticOnly1234');
    await expectLater(
      FirebaseFirestore.instanceFor(app: app)
          .collection('users')
          .doc('device-fixture-a')
          .get(const GetOptions(source: Source.server)),
      throwsA(isA<FirebaseException>()),
    );
    await expectLater(
      security.linkCredential(
        reauthentication: EmailAuthProvider.credential(
          email: 'device-fixture-b@example.invalid',
          password: 'SyntheticOnly1234',
        ),
        newCredential: google,
      ),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(sdk.currentUser?.uid, 'device-fixture-b');
    await auth.signOut();
    await policy.write(true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
