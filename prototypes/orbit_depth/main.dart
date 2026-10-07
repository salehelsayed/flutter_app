/// Standalone entry point for the Orbit depth prototype: fake friends, no
/// identity, no P2P. Run with:
///   flutter run -t prototypes/orbit_depth/main.dart
library;

import 'package:flutter/material.dart';
import 'orbit_depth_prototype_screen.dart';

void main() {
  applyPlaygroundSettings();
  runApp(const OrbitDepthPrototypeApp());
}

/// Settings copied from depth_playground.html (2026-10-03, second pass).
/// Replace this block to try another look on the phone.
void applyPlaygroundSettings() {
  OrbitDepthTuning.tiltDegrees = 54;
  OrbitDepthTuning.ringRadius = 166;
  OrbitDepthTuning.avatarSize = 36;
  OrbitDepthTuning.youSize = 40;
  OrbitDepthTuning.perspective = false;
  OrbitDepthTuning.depthScale = 0.8;
  OrbitDepthTuning.cameraDistance = 3;
  OrbitDepthTuning.backDim = 0.55;
  OrbitDepthTuning.bubbleDepth = 0.8;

  OrbitDepthTuning.orbitHeight = 0.21;
  OrbitDepthTuning.platformSize = 0.74;
  OrbitDepthTuning.youPlatformSize = 0.6;
  OrbitDepthTuning.platformFlatness = 0.3;
  OrbitDepthTuning.avatarHover = 7;
  OrbitDepthTuning.youHover = 2;
  OrbitDepthTuning.bubbleWidth = 99;
  OrbitDepthTuning.farOrbitSize = 0.14;
  OrbitDepthTuning.farOrbitY = 15;
  OrbitDepthTuning.farOrbitBrightness = 0.45;
  OrbitDepthTuning.farOrbitTilt = 49;
  OrbitDepthTuning.cardGap = 22;
  OrbitDepthTuning.beamStrength = 0.05;
  OrbitDepthTuning.frontNeighbourBubbles = OrbitNeighbourBubbles.small;
  OrbitDepthTuning.maxBubbleSize = 1.6;
  OrbitDepthTuning.bubbleTextSize = 11;
  OrbitDepthTuning.frontFriendLift = 0.12;
  OrbitDepthTuning.frontNameSize = 10;
  OrbitDepthTuning.cardWidth = 1;
  OrbitDepthTuning.cardScale = 1.3;
  OrbitDepthTuning.maxPhotoHeight = 202;
  OrbitDepthTuning.bubbleStyle = OrbitBubbleStyle.notes;
  OrbitDepthTuning.bubbleTint = 0.05;
  OrbitDepthTuning.unreadDot = true;
  OrbitDepthTuning.bubblesWhenFlat = true;
  OrbitDepthTuning.thoughtsInDepth = OrbitDepthThoughts.dots;
  OrbitDepthTuning.friendsPerOrbit = 7;
  OrbitDepthTuning.postCards = OrbitPostCards.universe;
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
