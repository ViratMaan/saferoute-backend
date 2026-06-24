import 'package:flutter/material.dart';
import 'login.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('access_token');

  runApp(
    DwbApiTrackerApp(
      initialScreen: token != null && token.isNotEmpty
          ? const DashboardScreen()
          : const LoginScreen(),
    ),
  );
}

class DwbApiTrackerApp extends StatelessWidget {
  final Widget initialScreen;
  const DwbApiTrackerApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DBW Accident Integration Hub',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardColor: const Color(0xFF1E293B),
        dividerColor: const Color(0xFF334155),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0EA5E9),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF1E293B),
          error: Color(0xFFEF4444),
        ),
        fontFamily: 'Segoe UI',
      ),
      home: initialScreen,
    );
  }
}
