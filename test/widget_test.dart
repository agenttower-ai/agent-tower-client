import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agenttower/main.dart';
import 'package:agenttower/connection_store.dart';
import 'package:agenttower/wechat_ui.dart';
import 'package:agenttower/mini_program_pages.dart';
import 'store_test.dart' show MemoryCredentials;

void main({bool useDeviceSize = false}) {
  testWidgets('relay dialog validates addresses before confirming', (
    tester,
  ) async {
    final store = TowerStore(credentials: MemoryCredentials());
    addTearDown(store.dispose);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showDialog<String>(
                  context: context,
                  builder: (_) => RelayServerDialog(store: store),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('relay-server-address'));
    final confirm = find.byKey(const ValueKey('relay-server-confirm'));
    await tester.enterText(field, 'http://untrusted.example.com');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.byType(RelayServerDialog), findsOneWidget);
    expect(selected, isNull);
    await tester.enterText(field, ' https://private.example.com/ ');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(selected, 'https://private.example.com');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'new session dialog accepts multiline text and cancels without sending',
    (tester) async {
      final store = TowerStore(credentials: MemoryCredentials());
      store.data['instances'] = [
        {
          'id': 'device',
          'directory': 'C:/project',
          'projects': ['C:/history-project'],
        },
      ];
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => sessionControlDialog(context, store, {
                  'id': 'device',
                  'directory': 'C:/project',
                }, 'create'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('新建会话'), findsNWidgets(2));
      expect(find.text('选择项目'), findsOneWidget);
      expect(find.text('项目目录：C:/project'), findsOneWidget);
      expect(find.text('项目文件夹'), findsNothing);
      expect(find.text('标题（可选）'), findsNothing);
      expect(find.text('模型（可选）'), findsOneWidget);
      expect(find.text('内容'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('C:/history-project').last);
      await tester.pumpAndSettle();
      expect(find.text('C:/history-project'), findsWidgets);
      expect(find.text('项目目录：C:/history-project'), findsOneWidget);
      expect(find.text('项目文件夹'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('＋ 新建项目').last);
      await tester.pumpAndSettle();
      expect(find.text('项目文件夹'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '检查代码\n然后运行测试');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.action, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  test('binding QR parser accepts only AgentTower bind payloads', () {
    expect(bindingCodeFromQr('agenttower://bind?code=ABCDEFGH'), 'ABCDEFGH');
    expect(bindingCodeFromQr('abcdefgh'), 'ABCDEFGH');
    expect(bindingCodeFromQr('https://evil.example/?code=ABCDEFGH'), isNull);
    expect(bindingCodeFromQr('agenttower://bind?code=IIIIIIII'), isNull);
  });

  testWidgets('registered controller without a bound device stays onboarding', (
    tester,
  ) async {
    if (!useDeviceSize) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final store = TowerStore(credentials: MemoryCredentials())
      ..setAuthenticatedForTest();
    addTearDown(store.dispose);
    await tester.pumpWidget(AgentTowerApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(WechatUiHome), findsOneWidget);
    expect(find.text('让电脑上的 AI，\n帮你完成连接。'), findsOneWidget);
    expect(find.byType(TowerHome), findsNothing);
    expect(find.text('电脑已绑定，等待上线'), findsNothing);
  });

  testWidgets('unbound user can visit drawer pages and return to onboarding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = TowerStore(credentials: MemoryCredentials())
      ..setAuthenticatedForTest();
    addTearDown(store.dispose);
    await tester.pumpWidget(AgentTowerApp(store: store));
    await tester.pumpAndSettle();

    Future<void> openDrawer() async {
      final menu = find.byType(WechatUiHome).evaluate().isNotEmpty
          ? find.byIcon(Icons.menu_rounded)
          : find.byKey(const ValueKey('demo-menu'));
      await tester.tap(menu);
      await tester.pumpAndSettle();
    }

    await openDrawer();
    await tester.tap(find.text('开发者公告'));
    await tester.pumpAndSettle();
    expect(find.byType(TowerHome), findsOneWidget);
    expect(find.byType(AnnouncementsView), findsOneWidget);

    await openDrawer();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('连接与设置'), findsOneWidget);

    await openDrawer();
    await tester.tap(find.text('帮助与反馈'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpView), findsOneWidget);

    await openDrawer();
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.byType(WechatUiHome), findsOneWidget);
    expect(find.text('让电脑上的 AI，\n帮你完成连接。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bound computer opens the workspace', (tester) async {
    final state = emptyState();
    state['devices'] = [
      {'id': 'bound-pc', 'name': '工作电脑', 'bound': true},
    ];
    final store = TowerStore(credentials: MemoryCredentials())
      ..setAuthenticatedForTest(state: state);
    addTearDown(store.dispose);
    await tester.pumpWidget(AgentTowerApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(TowerHome), findsOneWidget);
    expect(find.byKey(const ValueKey('add-device-action')), findsOneWidget);
  });

  testWidgets('add device opens onboarding with optional existing binding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = emptyState();
    state['devices'] = [
      {'id': 'bound-pc', 'name': '工作电脑', 'bound': true},
    ];
    final store = TowerStore(credentials: MemoryCredentials())
      ..setAuthenticatedForTest(state: state);
    addTearDown(store.dispose);
    await tester.pumpWidget(AgentTowerApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-device-action')));
    await tester.pumpAndSettle();
    expect(find.text('让电脑上的 AI，\n帮你完成连接。'), findsOneWidget);
    expect(find.text('复制安装指令'), findsOneWidget);
    expect(find.text('扫描二维码绑定'), findsNothing);
    expect(find.text('体验演示空间 →'), findsNothing);

    final existing = find.text('已有 Connector？扫描二维码绑定 >');
    await tester.scrollUntilVisible(
      existing,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(existing);
    await tester.pumpAndSettle();
    await tester.tap(existing);
    await tester.pumpAndSettle();
    expect(find.text('扫描二维码绑定'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-binding-code')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('返回首页'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-device-action')), findsOneWidget);
    expect(store.rows('devices').single['id'], 'bound-pc');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'onboarding, demo approval and task detail render without overflow',
    (tester) async {
      if (!useDeviceSize) {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      final store = TowerStore(credentials: MemoryCredentials());
      addTearDown(store.dispose);
      await tester.pumpWidget(AgentTowerApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('让电脑上的 AI，\n帮你完成连接。'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('体验演示空间 →'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('体验演示空间 →')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('体验演示空间 →'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('批准一次'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('批准一次')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('批准一次').last);
      await tester.pumpAndSettle();
      expect(find.text('确认批准此次操作？'), findsOneWidget);
      await tester.tap(find.text('批准一次').last);
      await tester.pumpAndSettle();
      expect(store.rows('permissions'), isEmpty);
      expect(find.text('体验完成，接下来连接你的电脑'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskPage(
            store: store,
            task: store.rows('sessions').first,
            hostname: 'MacBook Pro',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('conversation-thread')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-prompt-input')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
