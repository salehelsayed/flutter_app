/// Standalone entry point for the Orbit depth prototype: fake friends, no
/// identity, no P2P. Run with:
///   flutter run -t prototypes/orbit_depth/main.dart
library;

import 'package:flutter/material.dart';
import 'orbit_depth_prototype_screen.dart';

void main() {
  runApp(const OrbitDepthPrototypeApp());
}

class OrbitDepthPrototypeApp extends StatelessWidget {
  const OrbitDepthPrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orbit depth prototype',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF040605),
      ),
      home: const OrbitDepthPrototypeScreen(),
    );
  }
}
