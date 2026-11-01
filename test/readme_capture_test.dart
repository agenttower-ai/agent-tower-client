import "package:agenttower/conversation_view.dart";
import "package:agenttower/app_localizations.dart";
import 'dart:io';
import 'dart:ui' as ui;
import 'package:agenttower/connection_store.dart';
import 'package:agenttower/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class PreviewStore extends TowerStore {
  @override
  Future<void> refreshProjectLinks() async {}
  @override
  Future<void> refreshMobileAnnouncements() async {}
  @override
  Future<void> refreshSetupAgents() async {
    setupAgents = [
      for (final entry in {
        'opencode': 'OpenCode',
        'claude': 'Claude Code',
        'cursor': 'Cursor',
        'codex': 'Codex',
        'codebuddy': 'CodeBuddy',
        'dsh': 'DeepSeek Harness',
      }.entries)
        {'id': entry.key, 'name': entry.value, 'enabled': true},
    ];
    emit();
  }
}

void main() {
  testWidgets('Export actual Flutter surfaces for the website', (tester) async {
    final font = FontLoader('Roboto');
    font.addFont(
      Future.value(
        ByteData.sublistView(
          File(
            Platform.isWindows
                ? '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/msyh.ttc'
                : '/System/Library/Fonts/Hiragino Sans GB.ttc',
          ).readAsBytesSync(),
        ),
      ),
    );
    await tester.runAsync(font.load);
    var sdk = File(Platform.resolvedExecutable).parent;
    while (!Directory('${sdk.path}/packages/flutter').existsSync()) {
      if (sdk.parent.path == sdk.path) {
        throw StateError('Flutter SDK not found');
      }
      sdk = sdk.parent;
    }
    for (final entry in {
      'MaterialIcons':
          '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      'monospace': Platform.isWindows
          ? '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/consola.ttf'
          : '/System/Library/Fonts/Menlo.ttc',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(
        Future.value(ByteData.sublistView(File(entry.value).readAsBytesSync())),
      );
      await tester.runAsync(loader.load);
    }
    final output = Directory(
      Platform.environment['WEBSITE_CAPTURE_OUTPUT'] ?? 'docs/screenshots',
    )..createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewStore();
    addTearDown(store.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AgentTowerApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/agenttower-profile.png'),
        key.currentContext!,
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async => tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${output.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await capture('connect');
    await tester.ensureVisible(find.text('体验演示空间 →'));
    await tester.tap(find.text('体验演示空间 →'));
    await tester.pumpAndSettle();
    await capture('approval');
    await tester.pumpWidget(MaterialApp(home: AppLocale(language: AppLanguage.zh, child: RepaintBoundary(key: key, child: ConversationView(store: store, session: store.rows('sessions').first, hostname: 'Demo workstation', onNavigate: (_) {})))));
    await tester.pumpAndSettle();
    await capture('conversation');
    expect(tester.takeException(), isNull);
  });
}
