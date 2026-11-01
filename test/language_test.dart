import 'package:agenttower/app_localizations.dart';
import 'package:agenttower/connection_store.dart';
import 'package:agenttower/main.dart';
import 'package:agenttower/language_catalog.dart';
import 'package:agenttower/settings_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'store_test.dart' show MemoryCredentials;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? saved;
  setUp(() {
    saved = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LanguagePreference.channel, (call) async {
          if (call.method == 'readLanguage') return saved;
          if (call.method == 'writeLanguage') saved = call.arguments as String;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LanguagePreference.channel, null);
  });

  test('language preference survives recreation', () async {
    final first = LanguagePreference();
    await first.select(AppLanguage.en);
    final restored = LanguagePreference();
    await restored.load();
    expect(restored.value, AppLanguage.en);
    await restored.select(AppLanguage.zh);
    expect(saved, 'zh');
    first.dispose();
    restored.dispose();
  });

  test('remote content follows selected language with English fallback', () {
    final notice = {
      'id': 'mobile-v1',
      'title': '手机版更新',
      'paragraphs': ['中文内容'],
      'translations': {
        'en': {
          'title': 'Mobile update',
          'paragraphs': ['English content'],
        },
        'zh-Hant': {
          'title': '手機版更新',
          'paragraphs': ['繁體內容'],
        },
      },
    };
    expect(
      AppStrings(AppLanguage.en).localizedContent(notice)['title'],
      'Mobile update',
    );
    expect(
      AppStrings(AppLanguage.zhHant).localizedContent(notice)['paragraphs'],
      ['繁體內容'],
    );
    expect(
      AppStrings(AppLanguage.ja).localizedContent(notice)['title'],
      'Mobile update',
    );
    expect(
      AppStrings(AppLanguage.zh).localizedContent(notice)['title'],
      '手机版更新',
    );
    for (final language in AppLanguage.values) {
      final t = AppStrings(language);
      expect(t.appName, 'Agent Tower');
      expect(
        [
          t.retry,
          t.noAnnouncements,
          t.announcementsUnavailable,
        ].every((value) => value.isNotEmpty),
        isTrue,
      );
    }
  });

  test(
    'all supported languages have complete resources and restore correctly',
    () async {
      expect(AppLanguage.values.length, 14);
      for (final language in AppLanguage.values) {
        final row = languageCatalog[language.name]!;
        expect(row.length, languageKeys.length, reason: language.name);
        expect(row.every((text) => text.isNotEmpty), isTrue);
        saved = language.name;
        final preference = LanguagePreference();
        await preference.load();
        expect(preference.value, language);
        preference.dispose();
      }
      expect(AppLanguage.fromSaved('unknown'), AppLanguage.zh);
    },
  );

  test('settings resources are complete in every supported language', () {
    expect(
      settingsCatalog.keys.toSet(),
      AppLanguage.values.map((l) => l.name).toSet(),
    );
    for (final language in AppLanguage.values) {
      final row = settingsCatalog[language.name]!;
      if (language != AppLanguage.en) {
        expect(
          row,
          isNot(orderedEquals(settingsCatalog['en']!)),
          reason: language.name,
        );
      }
      expect(row.length, SettingsText.values.length, reason: language.name);
      expect(row.every((value) => value.trim().isNotEmpty), isTrue);
      for (final key in SettingsText.values) {
        final value = AppStrings(language).setting(key, name: 'Test device');
        expect(
          value,
          isNot(contains('{name}')),
          reason: '${language.name}: ${key.name}',
        );
      }
    }
  });

  testWidgets('settings panels and relay dialog follow language changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = TowerStore(credentials: MemoryCredentials());
    addTearDown(store.dispose);
    final language = ValueNotifier(AppLanguage.zh);
    addTearDown(language.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ValueListenableBuilder<AppLanguage>(
          valueListenable: language,
          builder: (context, value, _) => AppLocale(
            language: value,
            child: Directionality(
              textDirection: value.direction,
              child: child!,
            ),
          ),
        ),
        home: TowerHome(store: store, initialTab: 3),
      ),
    );
    await tester.pumpAndSettle();
    for (final value in AppLanguage.values) {
      language.value = value;
      await tester.pumpAndSettle();
      final t = AppStrings(value);
      for (final text in [
        t.setting(SettingsText.deviceManagement),
        t.setting(SettingsText.addDevice),
        t.setting(SettingsText.switchRelayServer),
        t.setting(SettingsText.notifications),
      ]) {
        await tester.ensureVisible(find.text(text));
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget);
      }
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('settings-switch-server'))),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-switch-server')));
      await tester.pumpAndSettle();
      expect(find.text(t.setting(SettingsText.saveAndConnect)), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('relay-server-address')),
        'http://untrusted.example.com',
      );
      await tester.tap(find.byKey(const ValueKey('relay-server-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.text(t.setting(SettingsText.invalidServerAddress)),
        findsOneWidget,
      );
      await tester.tap(find.text(t.setting(SettingsText.cancel)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: value.name);
      await tester.drag(find.byType(ListView).last, const Offset(0, 3000));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('language switch updates home and survives route navigation', (
    tester,
  ) async {
    final store = TowerStore(credentials: MemoryCredentials());
    addTearDown(store.dispose);
    await tester.pumpWidget(AgentTowerApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Agent Tower'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('language-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-en')));
    await tester.pumpAndSettle();
    expect(find.text('Agent Tower'), findsOneWidget);
    expect(saved, 'en');
    await tester.scrollUntilVisible(
      find.text('Try demo workspace →'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Try demo workspace →'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try demo workspace →'));
    await tester.pumpAndSettle();
    expect(find.text('Agent Tower'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('language-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-zh')));
    await tester.pumpAndSettle();
    expect(find.text('Agent Tower'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all languages render localized onboarding with correct direction',
    (tester) async {
      final store = TowerStore(credentials: MemoryCredentials());
      addTearDown(store.dispose);
      for (final language in AppLanguage.values) {
        saved = language.name;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(AgentTowerApp(store: store));
        await tester.pumpAndSettle();
        final heading = find.text(AppStrings(language).appName);
        expect(heading, findsOneWidget);
        expect(Directionality.of(tester.element(heading)), language.direction);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
