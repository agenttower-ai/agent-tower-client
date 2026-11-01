import 'dart:convert';
import 'package:flutter/services.dart';
import 'drawer_catalog.dart';

// Keep existing preference keys stable across language changes.
final unspecifiedProjectDirectory =
    drawerCatalog['zh']![drawerKeys.indexOf('unnamedProject')];

class ProjectPreferences {
  static const channel = MethodChannel('com.agenttower.mobile/credentials');
  final followed = <String>{};
  final hidden = <String>{};
  Future<void> _writes = Future.value();
  Future<void> load() async {
    final raw = await channel.invokeMethod<String>('readProjectPreferences');
    if (raw == null) return;
    final data = jsonDecode(raw) as Map;
    followed.addAll((data['followed'] as List? ?? []).whereType<String>());
    hidden.addAll((data['hidden'] as List? ?? []).whereType<String>());
  }

  Future<void> save() {
    final raw = jsonEncode({
      'followed': followed.toList(),
      'hidden': hidden.toList(),
    });
    _writes = _writes
        .catchError((Object _) {})
        .then(
          (_) => channel.invokeMethod<void>('writeProjectPreferences', raw),
        );
    return _writes;
  }
}
