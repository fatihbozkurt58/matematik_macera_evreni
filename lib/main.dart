import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MatematikEvreniApp());
}

class MatematikEvreniApp extends StatelessWidget {
  const MatematikEvreniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matematik Evreni',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1463FF)),
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
      ),
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(
              'Matematik Evreni',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF172033),
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
