import 'package:agenttower/connection_store.dart';
import 'package:agenttower/main.dart';
import 'package:agenttower/wechat_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'store_test.dart' show MemoryCredentials;

void main() {
  testWidgets('preview fills the window and opens mini-program demo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = TowerStore(credentials: MemoryCredentials());
    addTearDown(store.dispose);
    await tester.pumpWidget(AgentTowerApp(store: store));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.radio_button_checked_rounded), findsNothing);
    expect(tester.getTopLeft(find.text('连接你的电脑')).dx, 16);
    expect(tester.getSize(find.byType(CustomScrollView)).width, 1280);
    await tester.ensureVisible(find.text('体验演示空间 →'));
    await tester.tap(find.text('体验演示空间 →'));
    await tester.pumpAndSettle();
    expect(store.demo, isTrue);
    expect(find.byType(TowerHome), findsOneWidget);
    expect(find.text('试着在手机上批准一次操作'), findsOneWidget);
    expect(find.text('批准一次'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    Navigator.of(tester.element(find.byType(TowerHome))).pop();
    await tester.pumpAndSettle();
    expect(store.demo, isFalse);
    expect(find.byType(WechatUiHome), findsOneWidget);

    await tester.ensureVisible(find.text('已有 Connector？扫描二维码绑定 >'));
    await tester.tap(find.text('已有 Connector？扫描二维码绑定 >'));
    await tester.pumpAndSettle();
    expect(find.text('添加设备'), findsOneWidget);
    expect(find.text('扫描二维码绑定'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-binding-code')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('onboarding-confirm-binding')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('添加设备'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
