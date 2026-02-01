import 'package:flutter/material.dart';

void main() {
  runApp(const CombatGoblinApp());
}

class CombatGoblinApp extends StatelessWidget {
  const CombatGoblinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Combat Goblin')),
      ),
    );
  }
}
