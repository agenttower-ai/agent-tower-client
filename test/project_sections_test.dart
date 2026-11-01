import 'package:flutter/material.dart';
import 'package:agenttower/project_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agenttower/main.dart';
import 'package:agenttower/connection_store.dart';
import 'store_test.dart' show MemoryCredentials;

class PromptStore extends TowerStore {
  PromptStore() : super(credentials: MemoryCredentials()) {
    setAuthenticatedForTest();
  }
  String sent = '';
  @override
  bool canControlSession(String instanceId) => true;
  @override
  Future<void> controlSession(
    Json target,
    String operation, {
    String text = '',
    String title = '',
    String model = '',
    String directory = '',
  }) async {
    expect(operation, 'prompt');
    sent = text;
  }
}

class CreateStore extends TowerStore {
  CreateStore() : super(credentials: MemoryCredentials()) {
    setAuthenticatedForTest();
  }
  String? createdDirectory;
  @override
  bool canControlSession(String instanceId) => true;
  @override
  Future<void> controlSession(
    Json target,
    String operation, {
    String text = '',
    String title = '',
    String model = '',
    String directory = '',
  }) async {
    expect(operation, 'create');
    expect(text, '新的任务');
    createdDirectory = directory;
  }
}

class QuestionStore extends TowerStore {
  QuestionStore() : super(credentials: MemoryCredentials()) {
    setAuthenticatedForTest();
  }
  List<List<String>>? answers;
  @override
  bool canApprove(Json permission) => true;
  @override
  Future<void> reply(
    Json permission,
    String decision, {
    List<List<String>>? answers,
  }) async {
    expect(decision, 'answer');
    this.answers = answers;
  }
}

void main() {
  testWidgets('drawer project order stays stable across reordered snapshots', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = CreateStore();
    addTearDown(store.dispose);
    store.data['instances'] = [
      {
        'id': 'pc/b',
        'deviceId': 'pc',
        'directory': 'C:/beta',
        'agent': 'codex',
      },
      {
        'id': 'pc/a',
        'deviceId': 'pc',
        'directory': 'C:/alpha',
        'agent': 'opencode',
      },
    ];
    store.data['sessions'] = [
      {'id': 'z', 'instanceId': 'pc/a', 'directory': 'C:/zeta', 'title': 'Z'},
      {'id': 'g', 'instanceId': 'pc/a', 'directory': 'C:/gamma', 'title': 'G'},
    ];
    await tester.pumpWidget(AgentTowerApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('demo-menu')));
    await tester.pumpAndSettle();
    final positions = {
      for (final name in ['alpha', 'beta', 'gamma', 'zeta'])
        name: tester.getTopLeft(find.text(name)).dy,
    };
    const key = 'pc\u0000opencode\u0000C:/gamma';
    await tester.tap(find.byKey(const ValueKey('drawer-project-toggle-$key')));
    await tester.pumpAndSettle();
    store.data['instances'] = store.rows('instances').reversed.toList();
    store.data['sessions'] = store.rows('sessions').reversed.toList();
    store.setAuthenticatedForTest(state: store.data);
    await tester.pumpAndSettle();
    expect(find.text('G'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drawer-project-toggle-$key')));
    await tester.pumpAndSettle();
    for (final name in positions.keys) {
      expect(tester.getTopLeft(find.text(name)).dy, positions[name]);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'drawer aligns sessions and creates one in the selected project',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CreateStore();
      addTearDown(store.dispose);
      store.data['instances'] = [
        {
          'id': 'pc/a',
          'deviceId': 'pc',
          'hostname': 'My PC',
          'directory': 'C:/other',
          'agent': 'OpenCode',
        },
      ];
      store.data['sessions'] = [
        {
          'id': 'first',
          'instanceId': 'pc/a',
          'directory': 'C:/selected',
          'title': '短标题',
          'status': 'idle',
        },
        {
          'id': 'second',
          'instanceId': 'pc/a',
          'directory': 'C:/selected',
          'title': '一段很长的会话标题',
          'status': 'idle',
        },
      ];
      await tester.pumpWidget(AgentTowerApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('demo-menu')));
      await tester.pumpAndSettle();
      const key = 'pc\u0000OpenCode\u0000C:/selected';
      await tester.tap(
        find.byKey(const ValueKey('drawer-project-toggle-$key')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('短标题')).dx,
        tester.getTopLeft(find.text('一段很长的会话标题')).dx,
      );
      await tester.tap(find.byKey(const ValueKey('drawer-project-menu-$key')));
      await tester.pumpAndSettle();
      expect(find.text('新建会话'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      await tester.tap(find.text('新建会话'));
      await tester.pumpAndSettle();
      expect(find.text('项目目录：C:/selected'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '新的任务');
      await tester.tap(find.widgetWithText(FilledButton, '新建会话'));
      await tester.pumpAndSettle();
      expect(store.createdDirectory, 'C:/selected');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'follow, hide and restore projects persist across home recreation',
    (tester) async {
      String? saved;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ProjectPreferences.channel,
        (call) async {
          if (call.method == 'readProjectPreferences') return saved;
          if (call.method == 'writeProjectPreferences') {
            saved = call.arguments as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ProjectPreferences.channel,
          null,
        ),
      );
      final store = TowerStore(credentials: MemoryCredentials())
        ..setAuthenticatedForTest();
      addTearDown(store.dispose);
      store.data['instances'] = [
        {
          'id': 'pc/a',
          'deviceId': 'pc',
          'hostname': 'My PC',
          'directory': 'C:/alpha',
          'agent': 'OpenCode',
        },
        {
          'id': 'pc/b',
          'deviceId': 'pc',
          'hostname': 'My PC',
          'directory': 'C:/beta',
          'agent': 'OpenCode',
        },
      ];
      await tester.pumpWidget(AgentTowerApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('demo-menu')));
      await tester.pumpAndSettle();
      final menu = find.byKey(
        const ValueKey('drawer-project-menu-pc\u0000OpenCode\u0000C:/alpha'),
      );
      Future<void> choose(String label) async {
        await tester.ensureVisible(menu);
        await tester.pumpAndSettle();
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      Future<void> filter(String key) async {
        final chip = find.byKey(const ValueKey('drawer-project-filter'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(find.text('取消'), findsOneWidget);
        await tester.tap(
          find
              .text(
                {
                  'all': '全部',
                  'followed': '关注',
                  'hidden': '已隐藏',
                  'active': '活跃',
                }[key]!,
              )
              .last,
        );
        await tester.pumpAndSettle();
      }

      await choose('关注项目');
      await filter('followed');
      expect(find.text('关注 ▾'), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsNothing);
      await choose('隐藏项目');
      expect(find.text('alpha'), findsNothing);
      await filter('hidden');
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsNothing);
      // Simulate closing and opening the home; native preferences remain intact.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(AgentTowerApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('demo-menu')));
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsNothing);
      await filter('hidden');
      await choose('恢复显示');
      expect(find.text('alpha'), findsNothing);
      await filter('followed');
      expect(find.text('alpha'), findsOneWidget);
      expect(saved, contains('followed'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'device projects collapse, limit history and keep state on refresh',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TowerStore(credentials: MemoryCredentials())
        ..setAuthenticatedForTest();
      addTearDown(store.dispose);
      store.data['instances'] = [
        {
          'id': 'pc/a',
          'deviceId': 'pc',
          'hostname': 'My PC',
          'directory': 'C:/alpha',
          'agent': 'OpenCode',
        },
        {
          'id': 'pc/b',
          'deviceId': 'pc',
          'hostname': 'My PC',
          'directory': 'C:/beta',
          'agent': 'OpenCode',
        },
      ];
      store.data['sessions'] = [
        for (var i = 0; i < 23; i++)
          {
            'id': 'a$i',
            'instanceId': 'pc/a',
            'directory': 'C:/alpha',
            'agent': 'OpenCode',
            'title': 'History $i',
            'status': 'idle',
            'updatedAt': i,
          },
        {
          'id': 'active',
          'instanceId': 'pc/a',
          'directory': 'C:/alpha',
          'agent': 'OpenCode',
          'title': 'Active task',
          'status': 'busy',
          'updatedAt': 0,
        },
      ];
      await tester.pumpWidget(AgentTowerApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('demo-menu')));
      await tester.pumpAndSettle();
      expect(find.text('My PC'), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      final activeFilter = find.byKey(const ValueKey('drawer-project-filter'));
      await tester.tap(activeFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('活跃').last);
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('drawer-project-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('History 22'), findsNothing);
      expect(find.textContaining('History 17'), findsNothing);
      expect(find.textContaining('Active task'), findsNothing);
      final projectToggle = find.byKey(
        const ValueKey('drawer-project-toggle-pc\u0000OpenCode\u0000C:/alpha'),
      );
      await tester.ensureVisible(projectToggle);
      await tester.pumpAndSettle();
      await tester.tap(projectToggle);
      await tester.pumpAndSettle();
      expect(find.textContaining('History 22'), findsOneWidget);
      await tester.tap(projectToggle);
      await tester.pumpAndSettle();
      expect(find.textContaining('Active task'), findsNothing);
      store.emit();
      await tester.pumpAndSettle();
      expect(find.textContaining('Active task'), findsNothing);
      await tester.tap(projectToggle);
      await tester.pumpAndSettle();
      final historyToggle = find.textContaining('查看更多 · 还有');
      await tester.ensureVisible(historyToggle);
      await tester.pumpAndSettle();
      await tester.tap(historyToggle);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('History 0'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('History 0'), findsOneWidget);
      await tester.ensureVisible(projectToggle);
      await tester.pumpAndSettle();
      await tester.tap(projectToggle);
      await tester.pumpAndSettle();
      expect(find.text('History 0'), findsNothing);
      store.emit();
      await tester.pumpAndSettle();
      expect(find.text('History 0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('vanished session shows an honest status instead of stale busy', (
    tester,
  ) async {
    final store = TowerStore(credentials: MemoryCredentials())
      ..setAuthenticatedForTest();
    addTearDown(store.dispose);
    final task = {
      'id': 'gone-session',
      'instanceId': 'pc/a',
      'title': 'Vanished run',
      'status': 'busy',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPage(store: store, task: task, hostname: 'My PC'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('设备离线 ·'), findsOneWidget);
    expect(find.text('运行中'), findsNothing);
  });

  testWidgets('question card submits the selected option', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = QuestionStore();
    addTearDown(store.dispose);
    store.data['devices'] = [
      {'id': 'pc', 'name': 'My PC', 'bound': true},
    ];
    store.data['permissions'] = [
      {
        'id': 'question-1',
        'instanceId': 'pc/a',
        'sessionID': 'session-1',
        'permission': '采集筛选',
        'question': true,
        'questions': [
          {
            'header': '筛选规则',
            'question': '请选择优先规则',
            'options': [
              {'label': '好友数量优先', 'description': ''},
              {'label': '活跃度优先', 'description': ''},
            ],
            'multiple': false,
            'custom': false,
          },
        ],
      },
    ];
    await tester.pumpWidget(MaterialApp(home: AgentTowerApp(store: store)));
    await tester.pumpAndSettle();
    final answerButton = find.byKey(
      const ValueKey('question-answer-question-1'),
    );
    await tester.ensureVisible(answerButton);
    await tester.pumpAndSettle();
    await tester.tap(answerButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('活跃度优先'));
    await tester.tap(find.byKey(const ValueKey('question-submit')));
    await tester.pumpAndSettle();
    expect(store.answers, [
      ['活跃度优先'],
    ]);
    expect(find.text('回答已发送，Agent 将继续处理'), findsOneWidget);
  });

  testWidgets('conversation displays messages in chronological order', (
    tester,
  ) async {
    final store = TowerStore(credentials: MemoryCredentials())
      ..setAuthenticatedForTest();
    addTearDown(store.dispose);
    final task = {
      'id': 'session-1',
      'instanceId': 'pc/a',
      'title': 'Source session',
      'status': 'busy',
    };
    store.data['sessions'] = [task];
    store.data['logs'] = [
      {
        'id': 1,
        'instanceId': 'pc/a',
        'sessionID': 'session-1',
        'at': 1,
        'text': 'old event',
      },
      {
        'id': 2,
        'instanceId': 'pc/a',
        'sessionID': 'session-1',
        'at': 2,
        'text': 'new event',
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPage(store: store, task: task, hostname: 'My PC'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('new event')).dy,
      greaterThan(tester.getTopLeft(find.text('old event')).dy),
    );
  });

  testWidgets(
    'drawer opens a session with composer visible and no bottom navigation',
    (tester) async {
      final store = TowerStore(credentials: MemoryCredentials())
        ..setAuthenticatedForTest();
      addTearDown(store.dispose);
      store.data['instances'] = [
        {
          'id': 'pc/a',
          'deviceId': 'pc',
          'hostname': 'My PC',
          'online': true,
          'lastSeenAt': DateTime.now().millisecondsSinceEpoch,
        },
      ];
      store.data['sessions'] = [
        {
          'id': 'session-1',
          'instanceId': 'pc/a',
          'title': 'Active source',
          'status': 'busy',
        },
      ];
      store.data['logs'] = [
        {
          'id': 9,
          'instanceId': 'pc/a',
          'sessionID': 'session-1',
          'at': 2,
          'text': 'source event',
        },
      ];
      await tester.pumpWidget(AgentTowerApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('demo-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('drawer-project-toggle-pc\u0000Agent\u0000未指定项目'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Active source'));
      await tester.pumpAndSettle();
      expect(find.text('Active source'), findsOneWidget);
      expect(find.text('设备离线或暂不支持发送'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        find.byKey(const ValueKey('session-prompt-input')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'existing session accepts a prompt directly from its detail page',
    (tester) async {
      final store = PromptStore();
      addTearDown(store.dispose);
      final task = {
        'id': 'session-1',
        'instanceId': 'pc/a',
        'title': 'Existing session',
        'status': 'idle',
      };
      store.data['sessions'] = [task];
      await tester.pumpWidget(
        MaterialApp(
          home: TaskPage(store: store, task: task, hostname: 'My PC'),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('session-prompt-input'));
      expect(input, findsOneWidget);
      await tester.enterText(input, '请继续修复剩余问题');
      final send = find.byKey(const ValueKey('session-prompt-send'));
      await tester.ensureVisible(send);
      await tester.pumpAndSettle();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(store.sent, '请继续修复剩余问题');
      expect(find.text('请继续修复剩余问题'), findsOneWidget);
      expect(find.text('消息已发送'), findsOneWidget);
    },
  );
}
