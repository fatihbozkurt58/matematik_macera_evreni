import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matematik/app/student_access.dart';
import 'package:matematik/app/student_profile.dart';
import 'package:matematik/main.dart';

class FakeStudentAuth implements StudentAuth {
  final changes = StreamController<StudentSession?>.broadcast();
  int initializations = 0;
  int signIns = 0;
  int registrations = 0;
  int googleSignIns = 0;
  int appleSignIns = 0;
  int resetRequests = 0;
  int initializationFailures = 0;
  String? registeredNickname;
  StudentSession? current;

  @override
  Stream<StudentSession?> get sessionChanges => changes.stream;

  void changeSession(StudentSession? next) {
    current = next;
    changes.add(next);
  }

  @override
  Future<StudentSession?> initialize() async {
    initializations++;
    if (initializationFailures > 0) {
      initializationFailures--;
      throw StateError('temporary bootstrap failure');
    }
    return current;
  }

  @override
  Future<StudentSession> signIn(String email, String password) async {
    signIns++;
    return current = StudentSession('test-uid', email, false);
  }

  @override
  Future<StudentSession> register(
    String nickname,
    String email,
    String password,
  ) async {
    registrations++;
    registeredNickname = nickname;
    return current = StudentSession('new-uid', email, false);
  }

  @override
  Future<StudentSession> signInWithGoogle() async {
    googleSignIns++;
    return current = const StudentSession(
      'google-uid',
      'test@example.com',
      true,
    );
  }

  @override
  Future<StudentSession> signInWithApple() async {
    appleSignIns++;
    return current = const StudentSession(
      'apple-uid',
      'test@example.com',
      true,
    );
  }

  @override
  Future<void> sendVerification() async {}

  @override
  Future<StudentSession?> refresh() async => current;

  @override
  Future<void> resetPassword(String email) async => resetRequests++;

  @override
  Future<void> signOut() async => current = null;
}

class FakeStudentProfiles implements StudentProfileRepository {
  StudentProfile? current;
  bool failLoads = false;
  int loads = 0;
  int completions = 0;

  @override
  Future<StudentProfile?> load(String uid) async {
    loads++;
    if (failLoads) throw StateError('temporary profile failure');
    return current?.uid == uid ? current : null;
  }

  @override
  Future<StudentProfile> complete(
    String uid,
    String nickname,
    int grade,
  ) async {
    completions++;
    return current = StudentProfile(
      uid: uid,
      nickname: nickname,
      grade: grade,
      registrationStatus: 'pendingCompliance',
      consentComplianceState: 'unverified',
    );
  }
}

Future<void> openAccess(
  WidgetTester tester,
  FakeStudentAuth auth, {
  FakeStudentProfiles? profiles,
  TargetPlatform platform = TargetPlatform.iOS,
  bool allowDevTestAccounts = false,
}) async {
  await tester.pumpWidget(
    MatematikEvreniApp(
      auth: auth,
      profiles: profiles ?? FakeStudentProfiles(),
      platform: platform,
      allowDevTestAccounts: allowDevTestAccounts,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('Apple provider rejects Android', () async {
    await expectLater(
      FirebaseStudentAuth().signInWithApple(),
      throwsUnsupportedError,
    );
  });

  testWidgets('Android has no adult flow or Apple; registration stays closed', (
    tester,
  ) async {
    final auth = FakeStudentAuth();
    await openAccess(tester, auth, platform: TargetPlatform.android);
    expect(auth.initializations, 1);
    expect(find.text('Hoş geldin'), findsOneWidget);
    expect(find.textContaining('Test sürümü'), findsNothing);
    expect(find.text('Yetişkin hesabı'), findsNothing);
    expect(find.text('Yetişkin onayı'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Kayıt'), findsNothing);
    expect(find.text('Hesap oluştur'), findsNothing);
    expect(find.text('Apple ile devam et'), findsNothing);
    final google = find.widgetWithText(OutlinedButton, 'Google ile devam et');
    expect(google, findsOneWidget);
    expect(tester.widget<OutlinedButton>(google).onPressed, isNull);
    expect(auth.googleSignIns, 0);
    expect(auth.appleSignIns, 0);
  });

  testWidgets('iOS keeps Google and Apple visible pending approval', (
    tester,
  ) async {
    final auth = FakeStudentAuth();
    await openAccess(tester, auth);
    for (final label in ['Google ile devam et', 'Apple ile devam et']) {
      final button = find.widgetWithText(OutlinedButton, label);
      expect(button, findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    }
  });

  testWidgets('Dev test mode enables Android Google and no Apple', (
    tester,
  ) async {
    final auth = FakeStudentAuth();
    await openAccess(
      tester,
      auth,
      platform: TargetPlatform.android,
      allowDevTestAccounts: true,
    );
    await tester.ensureVisible(find.text('Google ile devam et'));
    await tester.tap(find.text('Google ile devam et'));
    await tester.pumpAndSettle();
    expect(auth.googleSignIns, 1);
    expect(auth.appleSignIns, 0);
    expect(find.text('Apple ile devam et'), findsNothing);
  });

  testWidgets('Dev test mode registers a new unverified UID', (tester) async {
    final auth = FakeStudentAuth();
    await openAccess(tester, auth, allowDevTestAccounts: true);
    await tester.tap(find.text('Kayıt'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(4));
    await tester.enterText(fields.at(0), 'MatematikYildizi');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), 'Password1234');
    await tester.enterText(fields.at(3), 'Password1234');
    await tester.ensureVisible(find.text('Hesap oluştur'));
    await tester.tap(find.text('Hesap oluştur'));
    await tester.pumpAndSettle();
    expect(auth.registrations, 1);
    expect(auth.registeredNickname, 'MatematikYildizi');
    expect(auth.current?.uid, 'new-uid');
    expect(find.text('Doğrulamayı kontrol et'), findsOneWidget);
    expect(find.textContaining('Öğrenci profili'), findsNothing);
  });

  testWidgets('Registration validates nickname and password confirmation', (
    tester,
  ) async {
    final auth = FakeStudentAuth();
    await openAccess(tester, auth, allowDevTestAccounts: true);
    await tester.tap(find.text('Kayıt'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'A');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), 'Password1234');
    await tester.enterText(fields.at(3), 'Different1234');
    await tester.ensureVisible(find.text('Hesap oluştur'));
    await tester.tap(find.text('Hesap oluştur'));
    await tester.pumpAndSettle();
    expect(auth.registrations, 0);
    expect(find.text('3-20 karakterlik bir takma ad girin.'), findsOneWidget);
    expect(find.text('Şifreler eşleşmiyor.'), findsOneWidget);
    expect(find.text('Ad'), findsNothing);
    expect(find.text('Soyad'), findsNothing);
  });

  testWidgets('Existing test account signs in and verifies email', (
    tester,
  ) async {
    final auth = FakeStudentAuth();
    await openAccess(tester, auth);
    await tester.enterText(
      find.byType(TextFormField).first,
      'test@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Password1234');
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(auth.signIns, 1);
    expect(find.text('Doğrulamayı kontrol et'), findsOneWidget);
    expect(find.textContaining('Öğrenci profili'), findsNothing);

    auth.current = const StudentSession('test-uid', 'test@example.com', true);
    await tester.tap(find.text('Doğrulamayı kontrol et'));
    await tester.pumpAndSettle();
    expect(find.text('Profilini tamamla'), findsOneWidget);
    await tester.tap(find.text('Çıkış yap'));
    await tester.pumpAndSettle();
    expect(auth.current, isNull);
    expect(find.text('Hoş geldin'), findsOneWidget);
  });

  testWidgets('Restored session skips login without an adult gate', (
    tester,
  ) async {
    final auth = FakeStudentAuth()
      ..current = const StudentSession('saved-uid', 'test@example.com', true);
    final profiles = FakeStudentProfiles()
      ..current = const StudentProfile(
        uid: 'saved-uid',
        nickname: 'KayitliOyuncu',
        grade: 3,
        registrationStatus: 'pendingCompliance',
        consentComplianceState: 'unverified',
      );
    await openAccess(tester, auth, profiles: profiles);
    expect(auth.initializations, 1);
    expect(profiles.loads, 1);
    expect(find.text('Giriş yap'), findsNothing);
    expect(find.text('Hesap hazırlanıyor'), findsOneWidget);
    expect(find.textContaining('saved-uid'), findsNothing);
  });

  testWidgets('Verified UID completes profile but cannot bypass compliance', (
    tester,
  ) async {
    final auth = FakeStudentAuth()
      ..current = const StudentSession('saved-uid', 'test@example.com', true);
    final profiles = FakeStudentProfiles();
    await openAccess(tester, auth, profiles: profiles);
    expect(find.text('Profilini tamamla'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'BilgeKaptan');
    await tester.tap(find.text('Sınıfın'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3. sınıf').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profili kaydet'));
    await tester.pumpAndSettle();
    expect(profiles.completions, 1);
    expect(profiles.current?.uid, 'saved-uid');
    expect(find.text('Hesap hazırlanıyor'), findsOneWidget);
    expect(find.text('Hazırsın'), findsNothing);
  });

  testWidgets('External sign-out removes protected profile state', (
    tester,
  ) async {
    final auth = FakeStudentAuth()
      ..current = const StudentSession('uid-a', 'a@example.com', true);
    final profiles = FakeStudentProfiles()
      ..current = const StudentProfile(
        uid: 'uid-a',
        nickname: 'OyuncuA',
        grade: 2,
        registrationStatus: 'pendingCompliance',
        consentComplianceState: 'unverified',
      );
    await openAccess(tester, auth, profiles: profiles);
    expect(find.text('Hesap hazırlanıyor'), findsOneWidget);
    auth.changeSession(null);
    await tester.pumpAndSettle();
    expect(find.text('Hoş geldin'), findsOneWidget);
    expect(find.text('Hesap hazırlanıyor'), findsNothing);
  });

  testWidgets('UID switch never displays previous student profile', (
    tester,
  ) async {
    final auth = FakeStudentAuth()
      ..current = const StudentSession('uid-a', 'a@example.com', true);
    final profiles = FakeStudentProfiles()
      ..current = const StudentProfile(
        uid: 'uid-a',
        nickname: 'OyuncuA',
        grade: 2,
        registrationStatus: 'pendingCompliance',
        consentComplianceState: 'unverified',
      );
    await openAccess(tester, auth, profiles: profiles);
    auth.changeSession(const StudentSession('uid-b', 'b@example.com', true));
    await tester.pumpAndSettle();
    expect(find.text('Profilini tamamla'), findsOneWidget);
    expect(find.textContaining('OyuncuA'), findsNothing);
  });

  testWidgets('Profile load failure offers retry instead of a blank screen', (
    tester,
  ) async {
    final auth = FakeStudentAuth()
      ..current = const StudentSession('uid-a', 'a@example.com', true);
    final profiles = FakeStudentProfiles()..failLoads = true;
    await openAccess(tester, auth, profiles: profiles);
    expect(find.text('Profil yüklenemedi'), findsOneWidget);
    profiles.failLoads = false;
    await tester.tap(find.text('Yeniden dene'));
    await tester.pumpAndSettle();
    expect(find.text('Profilini tamamla'), findsOneWidget);
  });

  testWidgets('Bootstrap failure can recover on next sign-in attempt', (
    tester,
  ) async {
    final auth = FakeStudentAuth()..initializationFailures = 1;
    await openAccess(tester, auth);
    expect(find.text('Hoş geldin'), findsOneWidget);
    expect(find.textContaining('İşlem tamamlanamadı'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'a@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'Password1234');
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(auth.initializations, 2);
    expect(find.text('E-postanızı doğrulayın'), findsOneWidget);
  });

  testWidgets('Foreground refresh applies lost session', (tester) async {
    final auth = FakeStudentAuth()
      ..current = const StudentSession('uid-a', 'a@example.com', true);
    await openAccess(tester, auth);
    auth.current = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Hoş geldin'), findsOneWidget);
  });

  testWidgets('Blank sign-in never sends credentials', (tester) async {
    final auth = FakeStudentAuth();
    await openAccess(tester, auth);
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(auth.signIns, 0);
    expect(find.text('Geçerli bir e-posta girin.'), findsOneWidget);
    expect(find.text('Şifre girin.'), findsOneWidget);
  });

  testWidgets('Password reset requires a valid email', (tester) async {
    final auth = FakeStudentAuth();
    await openAccess(tester, auth);
    await tester.ensureVisible(find.text('Şifremi unuttum'));
    await tester.tap(find.text('Şifremi unuttum'));
    await tester.pumpAndSettle();
    expect(auth.resetRequests, 0);
    await tester.enterText(
      find.byType(TextFormField).first,
      'test@example.com',
    );
    await tester.ensureVisible(find.text('Şifremi unuttum'));
    await tester.tap(find.text('Şifremi unuttum'));
    await tester.pumpAndSettle();
    expect(auth.resetRequests, 1);
    expect(find.textContaining('sıfırlama bağlantısı'), findsOneWidget);
  });

  testWidgets('Compact phone keeps login usable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openAccess(tester, FakeStudentAuth());
    await tester.ensureVisible(find.text('Apple ile devam et'));
    expect(tester.takeException(), isNull);
  });
}
