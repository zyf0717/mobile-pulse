import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/polar/loop/presentation/loop_dev_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: MobilePulseLoopApp()));
}

class MobilePulseLoopApp extends StatelessWidget {
  const MobilePulseLoopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Polar Loop',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const LoopDevScreen(),
    );
  }
}
