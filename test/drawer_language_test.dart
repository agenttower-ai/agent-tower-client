import 'package:agenttower/app_localizations.dart';
import 'package:agenttower/drawer_catalog.dart';
import 'package:agenttower/connection_store.dart';
import 'package:agenttower/project_preferences.dart';
import 'package:agenttower/settings_catalog.dart';
import 'package:agenttower/wechat_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'store_test.dart' show MemoryCredentials;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          ProjectPreferences.channel,
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProjectPreferences.channel, null);
  });

  test('drawer translations cover all languages and counts', () {
    for (final language in AppLanguage.values) {
      final values = drawerCatalog[language.name]!;
      expect(values.length, drawerKeys.length);
      expect(values.every((text) => text.trim().isNotEmpty), isTrue);
      expect(
        AppStrings(language).drawer('sessionCount', count: 7),
        contains('7'),
      );
    }
  });

  for (final language in AppLanguage.values) {
    testWidgets(
      'drawer controls use ${language.name} and keep stable project keys',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = TowerStore(credentials: MemoryCredentials())..enterDemo();
        addTearDown(store.dispose);
        store.data['instances'] = [
          {'id': 'pc', 'deviceId': 'a', 'hostname': 'My PC', 'agent': 'codex'},
          {'id': 'home', 'deviceId': 'b', 'hostname': '家庭工作站'},
        ];
        store.data['sessions'] = [
          for (var i = 0; i < 7; i++)
            {
              'id': '$i',
              'instanceId': 'pc',
              'title': '用户会话 $i',
              'status': 'busy',
            },
        ];
        Widget app(AppLanguage selected) => MaterialApp(
          locale: selected.locale,
          supportedLocales: AppLanguage.values
              .map((value) => value.locale)
              .toList(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) =>
              AppLocale(language: selected, child: child!),
          home: WechatUiHome(store: store, onDemo: () {}, sidebarOnly: true),
        );
        final t = AppStrings(language);
        await tester.pumpWidget(app(language));
        await tester.pumpAndSettle();
        const projectKey = 'a\u0000codex\u0000未指定项目';
        final toggle = find.byKey(
          const ValueKey('drawer-project-toggle-$projectKey'),
        );
        final menu = find.byKey(
          const ValueKey('drawer-project-menu-$projectKey'),
        );
        expect(find.text(t.drawer('unnamedProject')), findsOneWidget);
        expect(
          find.text('codex · ${t.drawer('sessionCount', count: 7)}'),
          findsOneWidget,
        );
        expect(find.text('${t.drawer('switchNode')} ▾'), findsOneWidget);
        await tester.tap(find.text('${t.drawer('switchNode')} ▾'));
        await tester.pumpAndSettle();
        expect(find.text(t.conversation('homeDevice')), findsOneWidget);
        await tester.tap(find.text('My PC').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('drawer-project-filter')));
        await tester.pumpAndSettle();
        for (final key in ['all', 'active', 'followed', 'hidden']) {
          expect(find.text(t.drawer(key)), findsOneWidget);
        }
        await tester.tap(find.text(t.setting(SettingsText.cancel)));
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.text('用户会话 0'), findsOneWidget);
        final more = find.text('${t.drawer('moreSessions', count: 1)} ›');
        await tester.ensureVisible(more);
        expect(more, findsOneWidget);
        await tester.tap(more);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('用户会话 6'));
        expect(find.text('用户会话 6'), findsOneWidget);
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text(t.drawer('follow')), findsOneWidget);
        expect(find.text(t.drawer('hide')), findsOneWidget);
        expect(find.text(t.drawer('newSession')), findsOneWidget);
        await tester.tap(find.text(t.drawer('follow')));
        await tester.pumpAndSettle();
        // Switching language must preserve the identity, follow state, and expansion.
        await tester.pumpWidget(app(AppLanguage.en));
        await tester.pumpAndSettle();
        expect(toggle, findsOneWidget);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Unfollow'), findsOneWidget);
        await tester.tap(find.text('Hide project'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('drawer-project-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hidden'));
        await tester.pumpAndSettle();
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Show project'), findsOneWidget);
        await tester.tap(find.text('Show project'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
