import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matematik/main.dart';

void main() {
  testWidgets('Uygulama adi gorunur', (tester) async {
    await tester.pumpWidget(const MatematikEvreniApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Matematik Evreni'), findsOneWidget);
  });
}
