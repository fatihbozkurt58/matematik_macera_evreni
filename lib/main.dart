import 'package:flutter/material.dart';

import 'app/adult_access.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MatematikEvreniApp());
}

class MatematikEvreniApp extends StatelessWidget {
  const MatematikEvreniApp({super.key, this.auth});

  final AdultAuth? auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matematik Macerası',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF137C72)),
        scaffoldBackgroundColor: const Color(0xFFF7FAF9),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: AdultAccess(auth: auth ?? FirebaseAdultAuth()),
    );
  }
}
