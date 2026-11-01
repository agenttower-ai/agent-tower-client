import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agenttower/app_localizations.dart';
import 'package:agenttower/mobile_catalog.dart';
import 'package:agenttower/connection_store.dart';
import 'package:agenttower/wechat_ui.dart';
import 'package:agenttower/main.dart';
import 'package:agenttower/mini_program_pages.dart';
import 'package:agenttower/server_error_catalog.dart';
import 'store_test.dart' show MemoryCredentials;

void main() {
  test('every mobile translation is complete and preserves placeholders', () {
    final placeholder = RegExp(r'\{v\d+\}');
    expect(mobileKeys.toSet(), hasLength(mobileKeys.length));
    for (final language in AppLanguage.values) {
      final row = mobileCatalog[language.name]!;
      expect(row, hasLength(mobileKeys.length));
      for (var i = 0; i < row.length; i++) {
        expect(row[i], isNotEmpty, reason: '${language.name}/${mobileKeys[i]}');
        expect(
          placeholder.allMatches(row[i]).map((m) => m[0]).toSet(),
          placeholder
              .allMatches(mobileCatalog['en']![i])
              .map((m) => m[0])
              .toSet(),
          reason: '${language.name}/${mobileKeys[i]}',
        );
      }
      final t = AppStrings(language);
      for (final key in serverErrorKeys.values.toSet()) {
        if ([
          'offline',
          'agentsUnavailable',
          'announcementsUnavailable',
        ].contains(key)) {
          continue;
        }
        expect(mobileKeys, contains(key));
      }
      expect(
        t.errorText(ApiError.localized('invalidDeviceName')),
        t.mobile('invalidDeviceName'),
      );
      expect(t.errorText('绑定码错误次数过多，请 10 分钟后再试'), t.mobile('bindingRateLimit'));
      expect(
        t.errorText('Agent 回执超时，结果未知，请刷新审批状态'),
        t.mobile('agentReceiptTimeout'),
      );
      expect(
        t.mobile('installPrompt', values: ['hello {v0} 中文']),
        contains('hello {v0} 中文'),
      );
    }
  });

  test('UI and store sources contain no hardcoded Chinese', () {
    for (final file in Directory('lib').listSync().whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('_catalog.dart') ||
          file.path.endsWith('app_localizations.dart')) {
        continue;
      }
      expect(
        RegExp(r'[\u3400-\u9fff]').hasMatch(file.readAsStringSync()),
        isFalse,
        reason: file.path,
      );
    }
  });

  testWidgets('help opens the localized website using the browser', (
    tester,
  ) async {
    final store = TowerStore(credentials: MemoryCredentials());
    addTearDown(store.dispose);
    MethodCall? call;
    const channel = MethodChannel('com.agenttower.mobile/project-links');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      value,
    ) async {
      call = value;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppLocale(
          language: AppLanguage.en,
          child: Scaffold(
            body: SingleChildScrollView(child: HelpView(store: store)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open website'));
    await tester.tap(find.text('Open website'));
    await tester.pumpAndSettle();
    expect(call?.method, 'openLink');
    expect(call?.arguments, 'https://relay.example.com/?lang=en');
    expect(find.text('Copy website link'), findsNothing);
  });

  for (final language in [
    AppLanguage.en,
    AppLanguage.zhHant,
    AppLanguage.ja,
    AppLanguage.ar,
  ]) {
    testWidgets('device binding and back navigation use ${language.name}', (
      tester,
    ) async {
      final store = TowerStore(credentials: MemoryCredentials());
      addTearDown(store.dispose);
      final t = AppStrings(language);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppLocale(language: language, child: child!),
          home: WechatUiHome(store: store, onDemo: () {}, onBack: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t.helpText('backHome')), findsOneWidget);
      await tester.ensureVisible(find.text(t.alreadyConnected));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.alreadyConnected));
      await tester.pumpAndSettle();
      expect(find.text(t.mobile('scanToBind')), findsOneWidget);
      expect(find.text(t.mobile('bindingCodeLabel')), findsOneWidget);
      expect(find.text(t.mobile('confirmAdd')), findsOneWidget);
      expect(find.text('确认添加'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('new session dialog translates labels and validation', (
    tester,
  ) async {
    final store = TowerStore(credentials: MemoryCredentials());
    addTearDown(store.dispose);
    final t = AppStrings(AppLanguage.en);
    await tester.pumpWidget(
      MaterialApp(
        home: AppLocale(
          language: AppLanguage.en,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => sessionControlDialog(context, store, {
                  'id': 'device',
                }, 'create'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(t.drawer('newSession')), findsNWidgets(2));
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.mobile('newProject')).last);
    await tester.pumpAndSettle();
    expect(find.text(t.mobile('projectFolder')), findsOneWidget);
    expect(find.text(t.mobile('optionalModel')), findsOneWidget);
    await tester.tap(find.text(t.drawer('newSession')).last);
    await tester.pumpAndSettle();
    expect(find.text(t.mobile('folderRequired')), findsOneWidget);
    expect(find.text('项目文件夹'), findsNothing);
  });
}
