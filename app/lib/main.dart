import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: MobilePulseApp()));
}

class MobilePulseApp extends StatelessWidget {
  const MobilePulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const TelemetryDashboard(),
    );
  }
}

class TelemetryDashboard extends StatelessWidget {
  const TelemetryDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mobile Pulse')),
      body: const Center(child: Text('Android Environment Ready')),
    );
  }
}
