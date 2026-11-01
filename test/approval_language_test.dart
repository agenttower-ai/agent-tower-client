import 'package:agenttower/app_localizations.dart';
import 'package:agenttower/approval_catalog.dart';
import 'package:agenttower/connection_store.dart';
import 'package:agenttower/main.dart';
import 'package:agenttower/settings_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'store_test.dart' show MemoryCredentials;

void main() {
  test(
    'approval translations cover all supported languages and placeholders',
    () {
      for (final language in AppLanguage.values) {
        final row = approvalCatalog[language.name]!;
        expect(row.length, approvalKeys.length);
        expect(row.every((text) => text.trim().isNotEmpty), isTrue);
        final t = AppStrings(language);
        expect(t.approval('approveAndAllow', scope: 'RULE'), contains('RULE'));
        expect(
          t.approval('answerRequiredHint', name: 'QUESTION'),
          contains('QUESTION'),
        );
      }
    },
  );

  for (final language in AppLanguage.values) {
    testWidgets('demo approval and rejection follow ${language.name}', (
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
          locale: language.locale,
          supportedLocales: AppLanguage.values
              .map((value) => value.locale)
              .toList(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) =>
              AppLocale(language: language, child: child!),
          home: TowerHome(store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t.approval('tryTitle')), findsOneWidget);
      expect(find.text(t.approval('tryGuide')), findsOneWidget);
      expect(find.text(t.approval('workstation')), findsOneWidget);
      expect(find.text(t.approval('authorization')), findsOneWidget);
      expect(find.text(t.approval('executeShell')), findsOneWidget);
      final approve = find.byKey(const ValueKey('permission-approve-01'));
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(find.text(t.approval('approveTitle')), findsOneWidget);
      expect(find.textContaining(t.approval('demoMode')), findsOneWidget);
      expect(
        find.textContaining('rm -rf /var/tmp/agent-cache/*'),
        findsWidgets,
      );
      await tester.tap(find.text(t.setting(SettingsText.cancel)));
      await tester.pumpAndSettle();
      expect(store.rows('permissions'), hasLength(1));
      await tester.tap(find.widgetWithText(FilledButton, t.approval('reject')));
      await tester.pumpAndSettle();
      expect(find.text(t.approval('rejectTitle')), findsOneWidget);
      await tester.tap(find.text(t.approval('confirmReject')));
      await tester.pumpAndSettle();
      expect(store.rows('permissions'), isEmpty);
      expect(find.text(t.approval('demoDone')), findsOneWidget);
      expect(find.text(t.approval('doneTitle')), findsOneWidget);
      expect(find.text(t.approval('doneGuide')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
