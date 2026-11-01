import 'package:flutter/material.dart';

class AppBrandIcon extends StatelessWidget {
  const AppBrandIcon({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/agenttower-profile.png',
    width: size,
    height: size,
    semanticLabel: 'Agent Tower',
  );
}
