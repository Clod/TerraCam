import 'package:flutter/material.dart';
import 'guidance_screen.dart';

void main() {
  // It's important to ensure bindings are initialized before using plugins.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TerraCam - Prototipo',
      theme: ThemeData.dark(),
      home: const GuidanceScreen(),
    );
  }
}