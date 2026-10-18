import 'package:flutter/material.dart';
import 'app/student_access.dart';
import 'app/student_profile.dart';
import 'main.dart';

/// CI-only entry point: never use for production builds.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MatematikEvreniApp(
    auth: ScreenshotAuth(),
    profiles: ScreenshotProfiles(),
  ));
}

class ScreenshotAuth implements StudentAuth {
  const ScreenshotAuth();
  @override
  Stream<StudentSession?> get sessionChanges => const Stream<StudentSession?>.empty();
  @override
  Future<StudentSession?> initialize() async => null;
  @override
  Future<StudentSession> register(String nickname, String email, String password) async =>
      const StudentSession('preview', 'preview@example.test', false);
  @override
  Future<StudentSession> signIn(String email, String password) async =>
      const StudentSession('preview', 'preview@example.test', false);
  @override
  Future<StudentSession> signInWithGoogle() async =>
      const StudentSession('preview', 'preview@example.test', false);
  @override
  Future<StudentSession> signInWithApple() async =>
      const StudentSession('preview', 'preview@example.test', false);
  @override
  Future<void> sendVerification() async {}
  @override
  Future<StudentSession?> refresh() async => null;
  @override
  Future<void> resetPassword(String email) async {}
  @override
  Future<void> signOut() async {}
}

class ScreenshotProfiles implements StudentProfileRepository {
  const ScreenshotProfiles();
  @override
  Future<StudentProfile?> load(String uid) async => null;
  @override
  Future<StudentProfile> complete(String uid, String nickname, int grade) async =>
      StudentProfile(
        uid: uid,
        nickname: nickname,
        grade: grade,
        registrationStatus: 'pendingCompliance',
        consentComplianceState: 'unverified',
      );
}
