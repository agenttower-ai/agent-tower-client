import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agenttower/app_localizations.dart';
import 'package:agenttower/help_catalog.dart';
import 'package:agenttower/connection_store.dart';
import 'package:agenttower/mini_program_pages.dart';
import 'store_test.dart' show MemoryCredentials;

void main() {
  testWidgets('help follows language changes and translates loading errors', (
    tester,
  ) async {
    final store = TowerStore(credentials: MemoryCredentials());
    addTearDown(store.dispose);
    Widget app(AppLanguage language) => MaterialApp(
      home: AppLocale(
        language: language,
        child: Scaffold(
          body: SingleChildScrollView(child: HelpView(store: store)),
        ),
      ),
    );
    for (final language in AppLanguage.values) {
      expect(helpCatalog[language.name], hasLength(helpKeys.length));
      await tester.pumpWidget(app(language));
      await tester.pumpAndSettle();
      final t = AppStrings(language);
      expect(find.text(t.help), findsOneWidget);
      expect(find.text(t.helpText('restartAgent')), findsOneWidget);
      expect(find.text(t.mobile('openWebsite')), findsOneWidget);
      if (language != AppLanguage.zh) {
        expect(find.text('帮助与反馈'), findsNothing);
        expect(find.text('复制官网链接'), findsNothing);
      }
    }
    store.setupAgentsError = 'offline';
    await tester.pumpWidget(app(AppLanguage.en));
    await tester.pump();
    expect(find.text('Unable to load agents: offline'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
