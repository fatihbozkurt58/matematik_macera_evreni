import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matematik/app/student_access.dart';
import 'package:matematik/app/student_profile.dart';
import 'package:matematik/main.dart';

class FakeStudentAuth implements StudentAuth {
  final changes = StreamController<StudentSession?>.broadcast();
  @override
  bool staySignedIn = true;
  @override
  Future<void> setStaySignedIn(bool value) async {
    if (failPreference) throw StateError('storage unavailable');
    staySignedIn = value;
  }

  int initializations = 0;
  int signIns = 0;
  int registrations = 0;
  int googleSignIns = 0;
  int appleSignIns = 0;
  int resetRequests = 0;
  int initializationFailures = 0;
  String? registeredNickname;
  StudentSession? current;
  Object? refreshFailure;
  Completer<StudentSession?>? delayedRefresh;
  Completer<StudentSession>? delayedSignIn;
  bool failPreference = false;
  Completer<StudentSession?>? delayedInitialization;

  @override
  Stream<StudentSession?> get sessionChanges => changes.stream;

  void changeSession(StudentSession? next) {
    current = next;
    changes.add(next);
  }

  @override
  Future<StudentSession?> initialize() async {
    initializations++;
    if (delayedInitialization != null) return delayedInitialization!.future;
    if (initializationFailures > 0) {
      initializationFailures--;
      throw StateError('temporary bootstrap failure');
    }
    return current;
  }

  @override
  Future<StudentSession> signIn(String email, String password) async {
    signIns++;
    if (delayedSignIn != null) return delayedSignIn!.future;
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
  Future<StudentSession?> refresh() async {
    if (refreshFailure != null) throw refreshFailure!;
    return delayedRefresh == null ? current : delayedRefresh!.future;
  }

  @override
  Future<void> resetPassword(String email) async => resetRequests++;

  @override
  Future<void> signOut() async => current = null;
}

class FakeStudentProfiles implements StudentProfileRepository {
  final changes = StreamController<StudentProfile?>.broadcast();
  @override
  Stream<StudentProfile?> watch(String uid) => changes.stream;
  StudentProfile? current;
  bool failLoads = false;
  int loads = 0;
  int completions = 0;
  final pendingLoads = <Completer<StudentProfile?>>[];

  @override
  Future<StudentProfile?> load(String uid) async {
    loads++;
    if (pendingLoads.isNotEmpty) return pendingLoads.removeAt(0).future;
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
    expect(
      find.widgetWithText(CheckboxListTile, 'Beni hatırla'),
      findsOneWidget,
    );
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
    await tester.ensureVisible(find.text('Giriş yap'));
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
    expect(find.text('Haydi keşfe!'), findsOneWidget);
    expect(find.textContaining('saved-uid'), findsNothing);
  });

  testWidgets(
    'Verified UID completes profile and opens catalog without granting game access',
    (tester) async {
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
      expect(find.text('Haydi keşfe!'), findsOneWidget);
      expect(profiles.current?.canEnterGame, isFalse);
    },
  );

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
    expect(find.text('Haydi keşfe!'), findsOneWidget);
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
    await tester.ensureVisible(find.text('Giriş yap'));
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
    await tester.ensureVisible(find.text('Giriş yap'));
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
  testWidgets('Large text keeps compact registration and keyboard scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            viewInsets: const EdgeInsets.only(bottom: 240),
          ),
          child: child!,
        ),
        home: StudentAccess(
          auth: FakeStudentAuth(),
          profiles: FakeStudentProfiles(),
          allowDevTestAccounts: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kayıt'));
    await tester.tap(find.text('Kayıt'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hesap oluştur'));
    await tester.tap(find.text('Hesap oluştur'));
    await tester.pumpAndSettle();
    expect(find.text('Geçerli bir e-posta girin.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Welcome screen visual baseline', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final configFile = File('.dart_tool/package_config.json').absolute;
      final config = jsonDecode(await configFile.readAsString()) as Map;
      final flutter = (config['packages'] as List).cast<Map>().singleWhere(
        (package) => package['name'] == 'flutter',
      );
      final packageRoot = Directory.fromUri(
        configFile.uri.resolve(flutter['rootUri'] as String),
      );
      final sdk = packageRoot.parent.parent;
      for (final entry in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(
            File(
              '${sdk.path}/bin/cache/artifacts/material_fonts/${entry.value}',
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
      }
    });
    await openAccess(tester, FakeStudentAuth(), allowDevTestAccounts: true);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/welcome_phone.png'),
    );
  });
  testWidgets('Changing access mode clears field errors and preserves email', (
    tester,
  ) async {
    await openAccess(tester, FakeStudentAuth(), allowDevTestAccounts: true);
    await tester.enterText(
      find.byType(TextFormField).first,
      'draft@example.com',
    );
    await tester.ensureVisible(find.text('Giriş yap'));
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(find.text('Şifre girin.'), findsOneWidget);
    await tester.ensureVisible(find.text('Kayıt'));
    await tester.tap(find.text('Kayıt'));
    await tester.pumpAndSettle();
    expect(find.text('Şifre girin.'), findsNothing);
    expect(find.text('draft@example.com'), findsOneWidget);
    await tester.ensureVisible(find.text('Hesap oluştur'));
    await tester.tap(find.text('Hesap oluştur'));
    await tester.pumpAndSettle();
    expect(find.text('3-20 karakterlik bir takma ad girin.'), findsOneWidget);
    await tester.ensureVisible(find.text('Giriş'));
    await tester.tap(find.text('Giriş'));
    await tester.pumpAndSettle();
    expect(find.text('3-20 karakterlik bir takma ad girin.'), findsNothing);
    expect(find.text('draft@example.com'), findsOneWidget);
  });
  testWidgets('Stay signed in defaults on and selected policy precedes login', (
    tester,
  ) async {
    final auth = FakeStudentAuth();
    await openAccess(tester, auth);
    final option = find.widgetWithText(CheckboxListTile, 'Beni hatırla');
    expect(tester.widget<CheckboxListTile>(option).value, isTrue);
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.enterText(
      find.byType(TextFormField).first,
      'test@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Password1234');
    await tester.ensureVisible(find.text('Giriş yap'));
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(auth.staySignedIn, isFalse);
    expect(auth.signIns, 1);
  });

  testWidgets('Cannot start login if session policy cannot be stored', (
    tester,
  ) async {
    final auth = FakeStudentAuth()..failPreference = true;
    await openAccess(tester, auth);
    await tester.enterText(
      find.byType(TextFormField).first,
      'test@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Password1234');
    await tester.ensureVisible(find.text('Giriş yap'));
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(auth.signIns, 0);
  });

  testWidgets('Startup retry restores existing session without credentials', (
    tester,
  ) async {
    final auth = FakeStudentAuth()..initializationFailures = 1;
    await openAccess(tester, auth);
    auth.current = const StudentSession('saved', 'test@example.com', true);
    await tester.ensureVisible(find.text('Oturumu yeniden kontrol et'));
    await tester.tap(find.text('Oturumu yeniden kontrol et'));
    await tester.pumpAndSettle();
    expect(auth.signIns, 0);
    expect(auth.initializations, 2);
    expect(find.text('Profilini tamamla'), findsOneWidget);
  });

  testWidgets('Sign out during pending login cannot resurrect old result', (
    tester,
  ) async {
    final pending = Completer<StudentSession>();
    final auth = FakeStudentAuth()..delayedSignIn = pending;
    await openAccess(tester, auth);
    await tester.enterText(
      find.byType(TextFormField).first,
      'test@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Password1234');
    await tester.ensureVisible(find.text('Giriş yap'));
    await tester.tap(find.text('Giriş yap'));
    await tester.pump();
    auth.changeSession(const StudentSession('old', 'test@example.com', false));
    await tester.pump();
    auth.changeSession(null);
    await tester.pump();
    pending.complete(const StudentSession('old', 'test@example.com', true));
    await tester.pumpAndSettle();
    expect(find.text('Giriş yap'), findsOneWidget);
    expect(find.text('Profilini tamamla'), findsNothing);
  });

  testWidgets('Same UID stale profile read cannot replace newer guard', (
    tester,
  ) async {
    final first = Completer<StudentProfile?>();
    final second = Completer<StudentProfile?>();
    final profiles = FakeStudentProfiles()
      ..pendingLoads.addAll([first, second]);
    final auth = FakeStudentAuth();
    await openAccess(tester, auth, profiles: profiles);
    auth.changeSession(const StudentSession('same', 'test@example.com', true));
    await tester.pump();
    auth.changeSession(null);
    await tester.pump();
    auth.changeSession(const StudentSession('same', 'test@example.com', true));
    await tester.pump();
    second.complete(
      const StudentProfile(
        uid: 'same',
        nickname: 'YeniProfil',
        grade: 2,
        registrationStatus: 'suspended',
        consentComplianceState: 'verified',
      ),
    );
    await tester.pumpAndSettle();
    first.complete(
      const StudentProfile(
        uid: 'same',
        nickname: 'EskiProfil',
        grade: 2,
        registrationStatus: 'active',
        consentComplianceState: 'verified',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hesap kullanılamıyor'), findsOneWidget);
    expect(find.text('Haydi keşfe!'), findsNothing);
  });

  testWidgets('Revoked token removes protected state on foreground refresh', (
    tester,
  ) async {
    final auth = FakeStudentAuth()
      ..current = const StudentSession('saved', 'test@example.com', true);
    await openAccess(tester, auth);
    auth.refreshFailure = FirebaseAuthException(code: 'user-token-expired');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Giriş yap'), findsOneWidget);
    expect(find.text('Profilini tamamla'), findsNothing);
  });

  testWidgets('Old refresh failure cannot clear a newly signed-in UID', (
    tester,
  ) async {
    final pending = Completer<StudentSession?>();
    final auth = FakeStudentAuth()
      ..current = const StudentSession('old', 'old@example.com', true)
      ..delayedRefresh = pending;
    await openAccess(tester, auth);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    auth.changeSession(const StudentSession('new', 'new@example.com', false));
    await tester.pump();
    pending.completeError(FirebaseAuthException(code: 'user-token-expired'));
    await tester.pumpAndSettle();
    expect(find.text('E-postanızı doğrulayın'), findsOneWidget);
    expect(find.text('Giriş yap'), findsNothing);
    expect(find.textContaining('Oturum sona erdi'), findsNothing);
  });

  testWidgets('Network failure closes protected state and retry recovers', (
    tester,
  ) async {
    final auth = FakeStudentAuth()
      ..current = const StudentSession('saved', 'test@example.com', true);
    await openAccess(tester, auth);
    auth.refreshFailure = FirebaseAuthException(code: 'network-request-failed');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Oturum doğrulanamadı'), findsOneWidget);
    expect(find.text('Profilini tamamla'), findsNothing);
    auth.refreshFailure = null;
    await tester.tap(find.text('Oturumu yeniden doğrula'));
    await tester.pumpAndSettle();
    expect(find.text('Profilini tamamla'), findsOneWidget);
  });
  testWidgets('Server profile suspension closes the account immediately', (
    tester,
  ) async {
    final auth = FakeStudentAuth()
      ..current = const StudentSession('saved', 'test@example.com', true);
    final profiles = FakeStudentProfiles()
      ..current = const StudentProfile(
        uid: 'saved',
        nickname: 'Kaptan',
        grade: 3,
        registrationStatus: 'active',
        consentComplianceState: 'verified',
      );
    await openAccess(tester, auth, profiles: profiles);
    expect(find.text('Haydi keşfe!'), findsOneWidget);
    profiles.changes.add(
      const StudentProfile(
        uid: 'saved',
        nickname: 'Kaptan',
        grade: 3,
        registrationStatus: 'suspended',
        consentComplianceState: 'verified',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hesap kullanılamıyor'), findsOneWidget);
    expect(find.text('Haydi keşfe!'), findsNothing);
  });

  testWidgets('Revoked compliance removes game readiness without logout', (
    tester,
  ) async {
    final auth = FakeStudentAuth()
      ..current = const StudentSession('saved', 'test@example.com', true);
    final profiles = FakeStudentProfiles()
      ..current = const StudentProfile(
        uid: 'saved',
        nickname: 'Kaptan',
        grade: 3,
        registrationStatus: 'active',
        consentComplianceState: 'verified',
      );
    await openAccess(tester, auth, profiles: profiles);
    profiles.changes.add(
      const StudentProfile(
        uid: 'saved',
        nickname: 'Kaptan',
        grade: 3,
        registrationStatus: 'active',
        consentComplianceState: 'revoked',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hesap hazırlanıyor'), findsOneWidget);
    expect(find.text('Haydi keşfe!'), findsNothing);
  });

  testWidgets('Profile stream errors fail closed', (tester) async {
    final auth = FakeStudentAuth()
      ..current = const StudentSession('saved', 'test@example.com', true);
    final profiles = FakeStudentProfiles()
      ..current = const StudentProfile(
        uid: 'saved',
        nickname: 'Kaptan',
        grade: 3,
        registrationStatus: 'active',
        consentComplianceState: 'verified',
      );
    await openAccess(tester, auth, profiles: profiles);
    profiles.changes.addError(StateError('permission denied'));
    await tester.pumpAndSettle();
    expect(find.text('Profil yüklenemedi'), findsOneWidget);
    expect(find.text('Haydi keşfe!'), findsNothing);
  });

  testWidgets('Pending bootstrap times out and recovers without losing a UID', (
    tester,
  ) async {
    final auth = FakeStudentAuth()
      ..delayedInitialization = Completer<StudentSession?>();
    await tester.pumpWidget(
      MaterialApp(
        home: StudentAccess(
          auth: auth,
          profiles: FakeStudentProfiles(),
          requestTimeout: const Duration(milliseconds: 100),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('Oturumu yeniden kontrol et'), findsOneWidget);
    expect(find.textContaining('zaman aşımına'), findsOneWidget);
    auth.delayedInitialization = null;
    auth.current = const StudentSession('saved', 'test@example.com', true);
    await tester.ensureVisible(find.text('Oturumu yeniden kontrol et'));
    await tester.tap(find.text('Oturumu yeniden kontrol et'));
    await tester.pumpAndSettle();
    expect(find.text('Profilini tamamla'), findsOneWidget);
  });
}
