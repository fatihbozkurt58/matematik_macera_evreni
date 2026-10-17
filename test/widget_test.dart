import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matematik/app/adult_access.dart';
import 'package:matematik/main.dart';

class FakeAdultAuth implements AdultAuth {
  int initializations = 0;
  AdultSession? current;

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
  Future<void> sendVerification() async {}

  @override
  Future<AdultSession?> refresh() async => current;

  @override
  Future<void> resetPassword(String email) async {}

  @override
  Future<void> signOut() async => current = null;
}

void main() {
  testWidgets('Firebase starts only after both adult checks', (tester) async {
    final auth = FakeAdultAuth();
    await tester.pumpWidget(MatematikEvreniApp(auth: auth));
    expect(find.text('Matematik Macerası'), findsOneWidget);
    expect(auth.initializations, 0);
    final button = find.widgetWithText(FilledButton, 'Yetişkin hesabına geç');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pump();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(auth.initializations, 1);
    expect(find.text('Giriş yap'), findsOneWidget);
  });

  testWidgets('Unverified account cannot enter profile area', (tester) async {
    final auth = FakeAdultAuth();
    await tester.pumpWidget(MatematikEvreniApp(auth: auth));
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pump();
    await tester.ensureVisible(find.text('Yetişkin hesabına geç'));
    await tester.tap(find.text('Yetişkin hesabına geç'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kayıt'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'adult@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Password1234');
    await tester.tap(find.text('Hesap oluştur'));
    await tester.pumpAndSettle();
    expect(find.text('Doğrulamayı kontrol et'), findsOneWidget);
    expect(find.textContaining('Öğrenci profili'), findsNothing);

    auth.current = const AdultSession('test-uid', 'adult@example.com', true);
    await tester.tap(find.text('Doğrulamayı kontrol et'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Öğrenci profili'), findsOneWidget);
    await tester.tap(find.text('Çıkış yap'));
    await tester.pumpAndSettle();
    expect(find.text('Giriş yap'), findsOneWidget);
  });
}
