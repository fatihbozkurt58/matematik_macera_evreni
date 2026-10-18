import 'package:flutter/material.dart';

import 'app/student_access.dart';
import 'app/student_profile.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MatematikEvreniApp());
}

class MatematikEvreniApp extends StatelessWidget {
  const MatematikEvreniApp({
    super.key,
    this.auth,
    this.profiles,
    this.platform,
    this.allowDevTestAccounts,
  });

  final StudentAuth? auth;
  final StudentProfileRepository? profiles;
  final TargetPlatform? platform;
  final bool? allowDevTestAccounts;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matematik Macerası',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        platform: platform,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087C8C),
          secondary: const Color(0xFFE68753),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5FAFB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: StudentAccess(
        auth: auth ?? FirebaseStudentAuth(),
        profiles: profiles ?? FirebaseStudentProfileRepository(),
        allowDevTestAccounts: allowDevTestAccounts ?? devTestAccountsEnabled,
      ),
    );
  }
}
