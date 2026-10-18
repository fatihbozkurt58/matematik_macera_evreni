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
      title: 'Matematik Macera Evreni',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        platform: platform,
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF246447),
          secondary: const Color(0xFFD8803B),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFEEF7F2),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
