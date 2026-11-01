import 'package:agenttower/app_localizations.dart';
import 'package:agenttower/conversation_catalog.dart';
import 'package:agenttower/conversation_view.dart';
import 'package:agenttower/connection_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'store_test.dart' show MemoryCredentials;

void main() {
  test('conversation translations cover every supported language', () {
    for (final language in AppLanguage.values) {
      final row = conversationCatalog[language.name]!;
      expect(row.length, conversationKeys.length);
      expect(row.every((value) => value.trim().isNotEmpty), isTrue);
      final t = AppStrings(language);
      expect(t.demoValue('用户写的中文消息', demo: false), '用户写的中文消息');
      expect(t.demoValue('重构 User API 模块', demo: false), '重构 User API 模块');
    }
  });

  for (final language in AppLanguage.values) {
    testWidgets('demo conversation uses ${language.name} throughout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TowerStore(credentials: MemoryCredentials())..enterDemo();
      addTearDown(store.dispose);
      final t = AppStrings(language);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppLocale(language: language, child: child!),
          home: ConversationView(
            store: store,
            session: store.rows('sessions').first,
            hostname: '家庭工作站',
            onNavigate: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t.conversation('refactor')), findsOneWidget);
      expect(
        find.text(
          '${t.conversation('busy')} · ${t.conversation('homeDevice')}',
        ),
        findsOneWidget,
      );
      expect(find.text(t.conversation('prompt')), findsOneWidget);
      expect(find.text(t.conversation('disabled')), findsOneWidget);
      expect(find.text(t.conversation('approvalLog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('conversation-info')));
      await tester.pumpAndSettle();
      final thread = find.byKey(const ValueKey('conversation-thread'));
      await tester.drag(thread, const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(
        find.text('Claude Code · ${t.conversation('cleanup')}'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('session-model-picker')));
      await tester.pumpAndSettle();
      expect(find.text(t.conversation('chooseModel')), findsOneWidget);
      expect(find.text(t.conversation('reuseModel')), findsOneWidget);
      expect(find.text(t.conversation('noModels')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('open demo conversation responds to language changes', (
    tester,
  ) async {
    final store = TowerStore(credentials: MemoryCredentials())..enterDemo();
    addTearDown(store.dispose);
    Widget app(AppLanguage language) => MaterialApp(
      home: AppLocale(
        language: language,
        child: ConversationView(
          store: store,
          session: store.rows('sessions').first,
          hostname: 'MacBook Pro',
          onNavigate: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(app(AppLanguage.zh));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(AppLanguage.en));
    await tester.pumpAndSettle();
    expect(find.text('Refactor the User API module'), findsOneWidget);
    expect(find.text('重构 User API 模块'), findsNothing);
    expect(find.text('给 AI 发送消息…'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
