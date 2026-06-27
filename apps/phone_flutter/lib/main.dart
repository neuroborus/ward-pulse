import 'package:flutter/material.dart';

void main() {
  runApp(const WardPulseApp());
}

class WardPulseApp extends StatelessWidget {
  const WardPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WardPulse',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A5A)),
        useMaterial3: true,
      ),
      home: const DashboardShell(),
    );
  }
}

class DashboardShell extends StatelessWidget {
  const DashboardShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Text('WardPulse'),
        ),
      ),
    );
  }
}
