import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matematik/app/adventure_home.dart';
import 'package:matematik/app/student_profile.dart';

const profile = StudentProfile(
  uid: 'home-test',
  nickname: 'BilgeKaptan',
  grade: 3,
  registrationStatus: 'pendingCompliance',
  consentComplianceState: 'unverified',
);

void main() {
  test('Catalog browsing never grants game permission', () {
    expect(profile.canOpenHome, isTrue);
    expect(profile.canEnterGame, isFalse);
    for (var grade = 1; grade <= 5; grade++) {
      final islands = islandsForGrade(grade);
      expect(islands.length, 5);
      expect(islands.map((i) => i.id).toSet().length, 5);
      expect(islands.every((i) => i.lessons.length == 3), isTrue);
    }
    expect(islandsForGrade(5).first.id, 'g5_geometry');
  });

  testWidgets(
    'Home opens island catalog, list alternative and account logout',
    (tester) async {
      var logouts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AdventureHome(
            profile: profile,
            onLogout: () async {
              logouts++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Merhaba, BilgeKaptan'), findsOneWidget);
      await tester.tap(find.text('Liste görünümü'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kesir ve Ölçme Limanı'));
      await tester.pumpAndSettle();
      expect(find.text('Kesirde pay ve payda'), findsOneWidget);
      expect(find.text('Oyuna başla'), findsNothing);
      await tester.ensureVisible(find.text('Haritaya dön'));
      await tester.tap(find.text('Haritaya dön'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byTooltip('Kaşifim'), -400);
      await tester.tap(find.byTooltip('Kaşifim'));
      await tester.pumpAndSettle();
      expect(find.text('BilgeKaptan'), findsOneWidget);
      await tester.tap(find.text('Çıkış yap'));
      await tester.pumpAndSettle();
      expect(logouts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Compact home supports 200 percent text and reduced motion', (
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
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: AdventureHome(profile: profile, onLogout: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Adayı keşfet'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adayı keşfet'));
    await tester.pumpAndSettle();
    expect(find.text('1000’e kadar sayılar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Route control selects an island and updates the persistent dock',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdventureHome(profile: profile, onLogout: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keşif rotan'));
      await tester.pumpAndSettle();
      expect(find.text('Adalarını keşfet'), findsOneWidget);
      await tester.ensureVisible(find.text('Geometri Atölyesi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Geometri Atölyesi'));
      await tester.pumpAndSettle();
      expect(find.text('Adalarını keşfet'), findsNothing);
      expect(find.text('Haydi keşfe!'), findsOneWidget);
      expect(find.text('Geometri Atölyesi'), findsOneWidget);
      await tester.tap(find.text('Adayı keşfet'));
      await tester.pumpAndSettle();
      expect(find.text('Düşey simetri'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Rapid map-list toggles keep a single map scroll controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdventureHome(profile: profile, onLogout: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liste görünümü'));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('Harita görünümü'));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Sonraki ada'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sonraki ada'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Kesir ve Ölçme Limanı'), findsOneWidget);
  });
}
