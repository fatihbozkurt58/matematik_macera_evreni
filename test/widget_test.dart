import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matematik/app/adult_access.dart';
import 'package:matematik/main.dart';

class FakeAdultAuth implements AdultAuth {
  int initializations = 0;
  AdultSession? current;
  int appleSignIns = 0;
  int resetRequests = 0;
  Object? appleError;

  @override
  Future<AdultSession?> initialize() async {
    initializations++;
    return current;
  }

  @override
  Future<AdultSession> register(String email, String password) async {
    current = AdultSession('test-uid', email, false);
    return current!;
  }

  @override
  Future<AdultSession> signIn(String email, String password) async =>
      current = AdultSession('test-uid', email, false);

  @override
  Future<AdultSession> signInWithGoogle() async =>
      current = const AdultSession('google-uid', 'test@example.com', true);

  @override
  Future<AdultSession> signInWithApple() async {
    appleSignIns++;
    if (appleError != null) throw appleError!;
    return current = const AdultSession(
      'apple-uid',
      'adult@privaterelay.appleid.com',
      true,
    );
  }

  @override
  Future<void> sendVerification() async {}

  @override
  Future<AdultSession?> refresh() async => current;

  @override
  Future<void> resetPassword(String email) async {
    resetRequests++;
  }

  @override
  Future<void> signOut() async => current = null;
}

class FakeConsentStore implements AdultConsentStore {
  FakeConsentStore({this.accepted = false});
  bool accepted;
  int writes = 0;

  @override
  Future<bool> hasCurrentConsent() async => accepted;

  @override
  Future<void> acceptCurrentConsent() async {
    accepted = true;
    writes++;
  }
}

Future<void> openCredentials(
  WidgetTester tester,
  FakeAdultAuth auth,
  FakeConsentStore consent,
) async {
  await tester.pumpWidget(
    MatematikEvreniApp(auth: auth, consentStore: consent),
  );
  await tester.pumpAndSettle();
  expect(find.text('Apple ile devam et'), findsOneWidget);
  expect(find.byType(CheckboxListTile), findsNothing);
}

Future<void> acceptConsent(WidgetTester tester) async {
  expect(find.text('Yetişkin onayı'), findsOneWidget);
  await tester.ensureVisible(find.byType(CheckboxListTile).first);
  await tester.tap(find.byType(CheckboxListTile).first);
  await tester.ensureVisible(find.byType(CheckboxListTile).last);
  await tester.tap(find.byType(CheckboxListTile).last);
  await tester.pump();
  await tester.ensureVisible(find.text('Onayla ve devam et'));
  await tester.tap(find.text('Onayla ve devam et'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Apple relay account signs in and can sign out', (tester) async {
    final auth = FakeAdultAuth();
    final consent = FakeConsentStore();
    await openCredentials(tester, auth, consent);
    await tester.ensureVisible(find.text('Apple ile devam et'));
    await tester.tap(find.text('Apple ile devam et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(auth.appleSignIns, 0);
    await acceptConsent(tester);
    expect(consent.writes, 1);
    expect(auth.initializations, 1);
    await tester.pumpAndSettle();
    expect(auth.appleSignIns, 1);
    expect(find.textContaining('Çocuk profili'), findsOneWidget);
    expect(find.textContaining('apple-uid'), findsNothing);
    await tester.ensureVisible(find.text('Çıkış yap'));
    await tester.tap(find.text('Çıkış yap'));
    await tester.pumpAndSettle();
    expect(auth.current, isNull);
    expect(find.text('Apple ile devam et'), findsOneWidget);
    await tester.ensureVisible(find.text('Apple ile devam et'));
    await tester.tap(find.text('Apple ile devam et'));
    await tester.pumpAndSettle();
    expect(find.text('Yetişkin onayı'), findsNothing);
    expect(auth.appleSignIns, 2);
  });

  for (final code in [
    'web-context-canceled',
    'operation-not-allowed',
    'account-exists-with-different-credential',
  ]) {
    testWidgets('Apple $code keeps the user on the sign-in screen', (
      tester,
    ) async {
      final auth = FakeAdultAuth()
        ..appleError = FirebaseAuthException(code: code);
      await openCredentials(tester, auth, FakeConsentStore(accepted: true));
      await tester.ensureVisible(find.text('Apple ile devam et'));
      await tester.tap(find.text('Apple ile devam et'));
      await tester.pumpAndSettle();
      expect(auth.current, isNull);
      expect(find.textContaining('Çocuk profili'), findsNothing);
      final button = find.widgetWithText(OutlinedButton, 'Apple ile devam et');
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      if (code == 'account-exists-with-different-credential') {
        expect(
          find.textContaining('Önce o yöntemle giriş yapın'),
          findsOneWidget,
        );
      } else if (code == 'operation-not-allowed') {
        expect(find.textContaining('henüz etkinleştirilmemiş'), findsOneWidget);
      } else {
        expect(find.textContaining('Giriş iptal edildi'), findsOneWidget);
      }
    });
  }

  testWidgets('Firebase starts only after both adult checks', (tester) async {
    final auth = FakeAdultAuth();
    final consent = FakeConsentStore();
    await openCredentials(tester, auth, consent);
    expect(find.text('Matematik Macerası'), findsOneWidget);
    expect(auth.initializations, 0);
    await tester.ensureVisible(find.text('Apple ile devam et'));
    await tester.tap(find.text('Apple ile devam et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(auth.initializations, 0);
    expect(auth.appleSignIns, 0);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Onayla ve devam et'),
          )
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.byType(CheckboxListTile).first);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Onayla ve devam et'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(auth.initializations, 0);
    expect(consent.writes, 0);

    await tester.tap(find.text('Apple ile devam et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.byType(CheckboxListTile).last);
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pump();
    expect(auth.initializations, 0);
    await tester.ensureVisible(find.byType(CheckboxListTile).first);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.text('Onayla ve devam et'));
    await tester.pumpAndSettle();
    expect(auth.initializations, 1);
    expect(auth.appleSignIns, 1);
    expect(consent.writes, 1);
  });

  testWidgets('Unverified account cannot enter profile area', (tester) async {
    final auth = FakeAdultAuth();
    await openCredentials(tester, auth, FakeConsentStore(accepted: true));
    await tester.tap(find.text('Kayıt'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'adult@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Password1234');
    await tester.ensureVisible(find.text('Hesap oluştur'));
    await tester.tap(find.text('Hesap oluştur'));
    await tester.pumpAndSettle();
    expect(find.text('Doğrulamayı kontrol et'), findsOneWidget);
    expect(find.textContaining('Çocuk profili'), findsNothing);

    auth.current = const AdultSession('test-uid', 'adult@example.com', true);
    await tester.tap(find.text('Doğrulamayı kontrol et'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Çocuk profili'), findsOneWidget);
    await tester.tap(find.text('Çıkış yap'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Giriş yap'), findsOneWidget);
  });

  testWidgets('Stored consent restores session without showing login', (
    tester,
  ) async {
    final auth = FakeAdultAuth()
      ..current = const AdultSession('saved-uid', 'adult@example.com', true);
    final consent = FakeConsentStore(accepted: true);
    await tester.pumpWidget(
      MatematikEvreniApp(auth: auth, consentStore: consent),
    );
    await tester.pumpAndSettle();
    expect(auth.initializations, 1);
    expect(find.text('Apple ile devam et'), findsNothing);
    expect(find.text('Yetişkin onayı'), findsNothing);
    expect(find.textContaining('Çocuk profili'), findsOneWidget);
    expect(find.textContaining('saved-uid'), findsNothing);
    expect(auth.resetRequests, 0);
  });

  testWidgets('Password reset requires an email and does not invent success', (
    tester,
  ) async {
    final auth = FakeAdultAuth();
    await openCredentials(tester, auth, FakeConsentStore(accepted: true));
    await tester.enterText(
      find.byType(TextFormField).first,
      'adult@example.com',
    );
    await tester.ensureVisible(find.text('Şifremi unuttum'));
    await tester.tap(find.text('Şifremi unuttum'));
    await tester.pumpAndSettle();
    expect(auth.resetRequests, 1);
    expect(find.textContaining('sıfırlama bağlantısı'), findsOneWidget);
  });

  testWidgets('Compact phone keeps login and consent usable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openCredentials(tester, FakeAdultAuth(), FakeConsentStore());
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Apple ile devam et'));
    await tester.tap(find.text('Apple ile devam et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Yetişkin onayı'), findsOneWidget);
    await tester.ensureVisible(find.text('Onayla ve devam et'));
    expect(tester.takeException(), isNull);
  });
}
