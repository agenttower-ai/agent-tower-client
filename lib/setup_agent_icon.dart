import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'connection_store.dart';

/// Uses local copies of the mini program's brands and remote icon convention.
class SetupAgentIcon extends StatelessWidget {
  const SetupAgentIcon({super.key, required this.agent});
  final Json agent;

  static const brands = {
    'opencode',
    'claude',
    'codebuddy',
    'cursor',
    'deepseek',
    'codex',
    'aider',
    'cline',
    'gemini',
    'githubcopilot',
    'kimi',
    'qwen',
    'roocode',
    'trae',
    'windsurf',
  };

  @override
  Widget build(BuildContext context) {
    const fallback = Center(child: Text('AI', style: TextStyle(fontSize: 11)));
    final icon = agent['icon'] as String? ?? '';
    final brand = agent['brand'] as String? ?? '';
    final bundled = icon.startsWith('/assets/brands/')
        ? icon.substring('/assets/brands/'.length)
        : icon.isEmpty && brands.contains(brand)
        ? '$brand.svg'
        : '';
    if (bundled.endsWith('.svg') &&
        brands.contains(bundled.substring(0, bundled.length - 4))) {
      return SvgPicture.asset(
        'assets/brands/$bundled',
        width: 23,
        height: 23,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    if (icon.startsWith('https://')) {
      if (Uri.parse(icon).path.toLowerCase().endsWith('.svg')) {
        return SvgPicture.network(
          icon,
          width: 23,
          height: 23,
          placeholderBuilder: (_) => fallback,
          errorBuilder: (_, _, _) => fallback,
        );
      }
      return Image.network(
        icon,
        width: 23,
        height: 23,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return fallback;
  }
}
