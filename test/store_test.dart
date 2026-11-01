import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:agenttower/connection_store.dart';

class MemoryCredentials implements Credentials {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  test(
    'relay switch isolates credentials and restores saved bindings',
    () async {
      final credentials = MemoryCredentials();
      final identities = <Json>[];
      final urls = <String>[];
      for (final name in ['first', 'second']) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        urls.add('http://127.0.0.1:${server.port}');
        server.listen((req) async {
          req.response.headers.contentType = ContentType.json;
          if (req.uri.path == '/mobile/register') {
            expect(req.headers.value('Authorization'), isNull);
            identities.add(
              jsonDecode(await utf8.decoder.bind(req).join()) as Json,
            );
            req.response.write(jsonEncode({'token': '$name-token'}));
          } else {
            expect(req.headers.value('Authorization'), 'Bearer $name-token');
            req.response.write(
              jsonEncode({
                ...emptyState(),
                'devices': [
                  {'id': name, 'bound': true},
                ],
              }),
            );
          }
          await req.response.close();
        });
      }
      final store = TowerStore(
        credentials: credentials,
        configuredEndpoint: urls[0],
      );
      addTearDown(store.dispose);
      await store.restore();
      await store.switchServer(urls[1]);
      expect(store.rows('devices').single['id'], 'second');
      expect(identities[0]['deviceId'], isNot(identities[1]['deviceId']));
      expect(
        identities[0]['installSecret'],
        isNot(identities[1]['installSecret']),
      );
      final restored = TowerStore(credentials: credentials);
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.endpoint, urls[1]);
      await restored.switchServer(urls[0]);
      expect(restored.rows('devices').single['id'], 'first');
      expect(identities.length, 2);
      await restored.disconnect();
      await restored.switchServer(urls[1]);
      expect(restored.rows('devices').single['id'], 'second');
      expect(identities.length, 2);
    },
  );

  test(
    'failed relay registration retains chosen endpoint without old token',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        expect(req.headers.value('Authorization'), isNull);
        req.response.headers.contentType = ContentType.json;
        req.response.statusCode = 503;
        req.response.write('{"error":"unavailable"}');
        await req.response.close();
      });
      final credentials = MemoryCredentials();
      final store = TowerStore(credentials: credentials)
        ..setAuthenticatedForTest();
      addTearDown(store.dispose);
      final url = 'http://127.0.0.1:${server.port}';
      await expectLater(store.switchServer(url), throwsA(isA<ApiError>()));
      expect(store.endpoint, url);
      expect(store.connected, false);
      expect(store.paired, false);
      expect(store.rows('devices'), isEmpty);
      expect((jsonDecode(credentials.value!) as Map)['endpoint'], url);
    },
  );

  test(
    'setup agents are fetched publicly and retain the last valid list',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var agents = <Json>[
        {
          'id': 'new-agent',
          'name': ' 新工具 ',
          'icon': 'https://relay.example.com/new.svg',
          'brand': 'codex',
        },
      ];
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        expect(request.headers.value('Authorization'), isNull);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'agents': agents}));
        await request.response.close();
      });
      final store = TowerStore(
        credentials: MemoryCredentials(),
        configuredEndpoint: 'http://127.0.0.1:${server.port}',
      )..setAuthenticatedForTest();
      addTearDown(store.dispose);
      await store.refreshSetupAgents();
      expect(store.setupAgents, [
        {
          'id': 'new-agent',
          'name': '新工具',
          'icon': 'https://relay.example.com/new.svg',
          'brand': 'codex',
        },
      ]);
      agents = [
        {'id': 'codex', 'name': 'Codex CLI'},
      ];
      await store.refreshSetupAgents();
      expect(store.setupAgents.single['id'], 'codex');
      agents = [
        {'id': 'invalid;command', 'name': '错误配置'},
      ];
      await store.refreshSetupAgents();
      expect(store.setupAgents.single['id'], 'codex');
      expect(store.setupAgentsError, isNotEmpty);
      expect(store.setupAgentsLoading, isFalse);
      expect(paths, ['/setup/agents', '/setup/agents', '/setup/agents']);
    },
  );
  test(
    'session controls require capability and send request to the selected session',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final state = emptyState();
      state['capabilities'] = {'sessionControl': true};
      state['instances'] = [
        {
          'id': 'device/agent',
          'online': true,
          'lastSeenAt': DateTime.now().millisecondsSinceEpoch,
          'capabilities': {'sessionControl': true},
        },
      ];
      Json? received;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/session-control') {
          received =
              jsonDecode(await utf8.decoder.bind(request).join()) as Json;
          request.response.write(jsonEncode({'ok': true}));
        } else {
          request.response.write(jsonEncode(state));
        }
        await request.response.close();
      });
      final store = TowerStore(
        credentials: MemoryCredentials(),
        configuredEndpoint: 'http://127.0.0.1:${server.port}',
      );
      addTearDown(store.dispose);
      store.setAuthenticatedForTest(state: state);
      expect(store.canControlSession('other/agent'), false);
      await store.controlSession(
        {'instanceId': 'device/agent', 'id': 'session-1'},
        'prompt',
        text: '继续检查',
      );
      expect(received?['sessionID'], 'session-1');
      expect(received?['text'], '继续检查');
      await store.controlSession(
        {'id': 'device/agent'},
        'create',
        text: '检查项目',
        model: 'openai/gpt-5',
        directory: 'C:/project',
      );
      expect(received?['model'], 'openai/gpt-5');
      expect(received?.containsKey('title'), false);
      expect(store.action, isEmpty);
    },
  );
  test('reject insecure remote endpoints, embedded credentials, and paths', () {
    for (final endpoint in [
      'http://example.com',
      'https://user:pass@example.com',
      'https://example.com/device',
      'https://example.com?token=x',
    ]) {
      expect(
        () => TowerStore.validateEndpoint(endpoint),
        throwsA(isA<ApiError>()),
      );
    }
    expect(
      TowerStore.validateEndpoint('https://tower.example.com/').toString(),
      'https://tower.example.com',
    );
  });
  test(
    'demo approval stays isolated and matches device + request identity',
    () async {
      final store = TowerStore(credentials: MemoryCredentials());
      addTearDown(store.dispose);
      store.enterDemo();
      final p = store.rows('permissions').first;
      store.data['permissions'] = [
        ...store.rows('permissions'),
        {...p, 'instanceId': 'cloud'},
      ];
      await store.reply(p, 'once');
      expect(store.rows('permissions').length, 1);
      expect(store.rows('permissions').first['instanceId'], 'cloud');
      expect(store.rows('logs').last['text'], contains('未执行真实命令'));
      store.leaveDemo();
      expect(store.rows('instances'), isEmpty);
    },
  );
  test('restore, approval ACK and revocation use server protocol', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    bool pending = true;
    String? received;
    String? deviceAction;
    server.listen((req) async {
      final body = req.method == 'POST'
          ? jsonDecode(await utf8.decoder.bind(req).join())
          : null;
      req.response.headers.contentType = ContentType.json;
      if (req.uri.path == '/pair') {
        expect(body['code'], 'ABCDEF123456');
        req.response.write(jsonEncode({'token': 'phone-token'}));
      } else {
        expect(req.headers.value('Authorization'), 'Bearer phone-token');
        if (req.uri.path == '/snapshot') {
          req.response.write(
            jsonEncode({
              'instances': [
                {
                  'id': 'device/agent',
                  'online': true,
                  'lastSeenAt': DateTime.now().millisecondsSinceEpoch,
                },
              ],
              'sessions': [],
              'permissions': pending
                  ? [
                      {'id': 'p', 'instanceId': 'device/agent'},
                    ]
                  : [],
              'logs': [],
            }),
          );
        }
        if (req.uri.path == '/permission') {
          expect(body['reply'], 'always');
          received = body['instanceId'];
          pending = false;
          req.response.write('{"resolved":true}');
        }
        if (req.uri.path == '/device-bind/confirm') {
          expect(body['code'], 'ABCDEFGH');
          deviceAction = 'bind';
          req.response.write('{"ok":true}');
        }
        if (req.uri.path == '/devices/rename') {
          expect(body['deviceId'], 'new-device');
          expect(body['name'], '工作电脑');
          deviceAction = 'rename';
          req.response.write('{"ok":true}');
        }
        if (req.uri.path == '/devices/unbind') {
          expect(body['deviceId'], 'new-device');
          deviceAction = 'unbind';
          req.response.write('{"ok":true}');
        }
        if (req.uri.path == '/unpair') req.response.write('{"ok":true}');
      }
      await req.response.close();
    });
    final credentials = MemoryCredentials()
      ..value = jsonEncode({
        'endpoint': 'http://127.0.0.1:${server.port}',
        'token': 'phone-token',
        'deviceId': 'phone_1234567890123456',
      });
    final store = TowerStore(credentials: credentials);
    addTearDown(store.dispose);
    await store.restore();
    expect(store.connected, true);
    expect(credentials.value, contains('phone-token'));
    await store.confirmDeviceBinding('abcdefgh');
    expect(deviceAction, 'bind');
    await store.renameDevice('new-device', '工作电脑');
    expect(deviceAction, 'rename');
    await store.unbindDevice('new-device');
    expect(deviceAction, 'unbind');
    await store.reply(store.rows('permissions').first, 'always');
    expect(received, 'device/agent');
    expect(store.rows('permissions'), isEmpty);
    final restored = TowerStore(credentials: credentials);
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.connected, true);
    await store.disconnect();
    expect((jsonDecode(credentials.value!) as Map)['token'], isEmpty);
    expect(store.paired, false);
  });
  test(
    'public build creates a per-install credential without a bundled secret',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        final body = req.method == 'POST'
            ? jsonDecode(await utf8.decoder.bind(req).join())
            : null;
        req.response.headers.contentType = ContentType.json;
        if (req.uri.path == '/mobile/register') {
          expect(body['deviceId'], hasLength(48));
          expect(body['installSecret'], hasLength(64));
          req.response.statusCode = 201;
          req.response.write('{"token":"automatic-phone-token"}');
        } else if (req.uri.path == '/snapshot') {
          expect(
            req.headers.value('Authorization'),
            'Bearer automatic-phone-token',
          );
          req.response.write(
            '{"instances":[],"sessions":[],"permissions":[],"logs":[]}',
          );
        }
        await req.response.close();
      });
      final credentials = MemoryCredentials();
      final store = TowerStore(
        credentials: credentials,
        configuredEndpoint: 'http://127.0.0.1:${server.port}',
      );
      addTearDown(store.dispose);
      await store.restore();
      expect(store.connected, true);
      expect(store.paired, true);
      expect(credentials.value, contains('automatic-phone-token'));
      expect(credentials.value, contains('installSecret'));
    },
  );
  test('setup ticket renews an expired phone credential and retries', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var setupRequests = 0;
    var registrations = 0;
    server.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      if (req.uri.path == '/setup/issue') {
        setupRequests += 1;
        if (req.headers.value('Authorization') == 'Bearer renewed-token') {
          req.response.statusCode = 201;
          req.response.write('{"ticket":"setup-ticket"}');
        } else {
          req.response.statusCode = 401;
          req.response.write('{"error":"手机凭证已失效，请重新连接工作空间"}');
        }
      } else if (req.uri.path == '/mobile/register') {
        registrations += 1;
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Json;
        expect(body['deviceId'], hasLength(48));
        expect(body['installSecret'], hasLength(64));
        req.response.statusCode = 201;
        req.response.write('{"token":"renewed-token"}');
      } else if (req.uri.path == '/snapshot') {
        expect(req.headers.value('Authorization'), 'Bearer renewed-token');
        req.response.write(
          '{"instances":[],"sessions":[],"permissions":[],"logs":[]}',
        );
      }
      await req.response.close();
    });
    final credentials = MemoryCredentials();
    final store = TowerStore(
      credentials: credentials,
      configuredEndpoint: 'http://127.0.0.1:${server.port}',
    );
    addTearDown(store.dispose);
    store.setAuthenticatedForTest(token: 'expired-token');

    expect(await store.issueSetupTicket(), 'setup-ticket');
    expect(setupRequests, 2);
    expect(registrations, 1);
    expect(credentials.value, contains('renewed-token'));
  });
}
