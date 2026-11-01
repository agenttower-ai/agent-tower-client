import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'conversation_catalog.dart';

typedef Json = Map<String, dynamic>;

abstract class Credentials {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class PlatformCredentials implements Credentials {
  static const channel = MethodChannel('com.agenttower.mobile/credentials');
  @override
  Future<String?> read() => channel.invokeMethod<String>('read');
  @override
  Future<void> write(String value) =>
      channel.invokeMethod<void>('write', value);
  @override
  Future<void> clear() => channel.invokeMethod<void>('clear');
}

class ApiError implements Exception {
  final String message;
  final int status;
  ApiError(this.message, [this.status = 0]);
  ApiError.localized(String key, [int status = 0])
    : this('AgentTowerError:$key', status);
  @override
  String toString() => message;
}

Json emptyState() => {
  'instances': <Json>[],
  'sessions': <Json>[],
  'permissions': <Json>[],
  'logs': <Json>[],
  'devices': <Json>[],
};

class TowerStore extends ChangeNotifier {
  static const bundledEndpoint = String.fromEnvironment(
    'AGENTTOWER_SERVER_URL',
    defaultValue: 'https://relay.example.com',
  );
  TowerStore({Credentials? credentials, String? configuredEndpoint})
    : credentials = credentials ?? PlatformCredentials(),
      endpoint = configuredEndpoint ?? bundledEndpoint;
  final Credentials credentials;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  Json data = emptyState();
  List<Json> setupAgents = [];
  List<Json> projectLinks = [];
  List<Json> mobileAnnouncements = [];
  final Map<String, Json> _servers = {};
  int _serverRevision = 0;
  List<String> get savedEndpoints => _servers.keys.toList();

  Json _profile() => {
    'token': _token,
    'deviceId': _deviceId,
    'installSecret': _installSecret,
  };

  Future<void> _saveCredentials() async {
    _servers[endpoint] = _profile();
    await credentials.write(
      jsonEncode({'endpoint': endpoint, ..._profile(), 'servers': _servers}),
    );
  }

  Future<void> switchServer(String value) async {
    final url = validateEndpoint(value).toString();
    if (connecting || action.isNotEmpty) {
      throw ApiError.localized('serverSwitchBusy');
    }
    if (url == endpoint && !demo) {
      if (paired) {
        await refresh();
      } else {
        await connectAutomatically();
      }
      return;
    }
    final profiles = {..._servers, endpoint: _profile()};
    final profile = profiles[url] ?? <String, dynamic>{};
    // Persist the selected server before sending any request to it. A failed
    // connection must not silently fall back to the previous relay.
    await credentials.write(
      jsonEncode({'endpoint': url, ...profile, 'servers': profiles}),
    );
    stop();
    _serverRevision++;
    _servers.clear();
    _servers.addAll(profiles);
    endpoint = url;
    _token = '${profile['token'] ?? ''}';
    _deviceId = '${profile['deviceId'] ?? ''}';
    _installSecret = '${profile['installSecret'] ?? ''}';
    demo = false;
    connected = false;
    data = emptyState();
    setupAgents = [];
    projectLinks = [];
    mobileAnnouncements = [];
    setupAgentsError = '';
    setupAgentsLoading = false;
    error = '';
    latency = 0;
    _failures = 0;
    emit();
    try {
      if (paired) await refresh();
      if (!paired) await connectAutomatically();
    } catch (e) {
      error = '$e';
      emit();
      rethrow;
    }
  }

  static bool validProjectLink(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty ||
            RegExp(r'^mailto:[^\s@]+@[^\s@]+$').hasMatch(value));
  }

  Future<void> refreshProjectLinks() async {
    final revision = _serverRevision;
    try {
      final result = await request('/project-links', token: '');
      if (revision != _serverRevision || _disposed) return;
      final items = result['links'];
      projectLinks = items is List
          ? items
                .whereType<Map>()
                .where(
                  (item) =>
                      item['id'] is String &&
                      item['label'] is String &&
                      item['url'] is String &&
                      validProjectLink(item['url'] as String),
                )
                .take(12)
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : [];
    } catch (_) {
      if (revision != _serverRevision || _disposed) return;
      projectLinks = [];
    }
    emit();
  }

  Future<void> refreshMobileAnnouncements() async {
    final revision = _serverRevision;
    try {
      final result = await request('/mobile/announcements', token: '');
      if (revision != _serverRevision || _disposed) return;
      mobileAnnouncements = (result['announcements'] as List? ?? [])
          .whereType<Map>()
          .where(
            (item) => item['title'] is String && item['paragraphs'] is List,
          )
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      if (revision != _serverRevision || _disposed) return;
      mobileAnnouncements = [];
    }
    emit();
  }

  String setupAgentsError = '';
  bool setupAgentsLoading = false;
  String endpoint,
      _token = '',
      _deviceId = '',
      _installSecret = '',
      error = '',
      action = '';
  bool demo = false,
      connected = false,
      connecting = false,
      _disposed = false,
      _foreground = true;
  int latency = 0, _generation = 0, _failures = 0;
  Timer? _timer;
  bool get paired => _token.isNotEmpty;
  bool get hasBoundWorkspace =>
      rows('devices').any((device) => device['bound'] != false) ||
      rows('instances').isNotEmpty;
  @visibleForTesting
  void setAuthenticatedForTest({
    String token = 'test-phone-token',
    Json? state,
  }) {
    _token = token;
    data = state ?? emptyState();
    connected = true;
  }

  List<Json> rows(String key) => (data[key] as List? ?? [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  bool online(Json device) =>
      (demo || connected) &&
      device['online'] == true &&
      (demo ||
          DateTime.now().millisecondsSinceEpoch -
                  ((device['lastSeenAt'] as num?)?.toInt() ?? 0) <
              60000);
  bool canApprove(Json permission) =>
      action.isEmpty &&
      permission['submitting'] != true &&
      (demo ||
          connected &&
              rows(
                'instances',
              ).any((d) => d['id'] == permission['instanceId'] && online(d)));
  void emit() {
    if (!_disposed) notifyListeners();
  }

  static Uri validateEndpoint(String value) {
    final uri = Uri.tryParse(value.trim().replaceAll(RegExp(r'/+$'), ''));
    final loopback =
        uri != null && ['localhost', '127.0.0.1', '::1'].contains(uri.host);
    final emulator = kDebugMode && uri?.host == '10.0.2.2';
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isNotEmpty ||
        !(uri.scheme == 'https' ||
            uri.scheme == 'http' && (loopback || emulator))) {
      throw ApiError.localized('invalidEndpoint');
    }
    return uri;
  }

  Future<Json> request(
    String path, {
    Json? body,
    String? server,
    String? token,
  }) async {
    final target = server ?? endpoint;
    final accessToken = token ?? _token;
    try {
      final result = await (() async {
        final req = await _http.openUrl(
          body == null ? 'GET' : 'POST',
          Uri.parse('$target$path'),
        );
        req.followRedirects = false;
        req.headers.contentType = ContentType.json;
        req.headers.set('X-AgentTower-Source', 'app');
        if (accessToken.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $accessToken');
        }
        if (body != null) req.write(jsonEncode(body));
        final response = await req.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 4 * 1024 * 1024) {
            throw ApiError.localized('responseTooLarge');
          }
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) throw ApiError.localized('invalidResponse');
        final json = Map<String, dynamic>.from(decoded);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ApiError(
            '${json['error'] ?? 'HTTP ${response.statusCode}'}',
            response.statusCode,
          );
        }
        return json;
      })().timeout(const Duration(seconds: 16));
      return result;
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw ApiError.localized('requestTimeout');
    } catch (_) {
      throw ApiError.localized('connectionFailed');
    }
  }

  Future<void> restore() async {
    try {
      final value = await credentials.read();
      if (value != null) {
        final saved = jsonDecode(value) as Map;
        final profiles = saved['servers'];
        if (profiles is Map) {
          for (final entry in profiles.entries) {
            _servers[validateEndpoint('${entry.key}').toString()] =
                Map<String, dynamic>.from(entry.value as Map);
          }
        }
        endpoint = validateEndpoint(
          '${saved['endpoint'] ?? endpoint}',
        ).toString();
        _token = '${saved['token'] ?? ''}';
        _deviceId = '${saved['deviceId'] ?? ''}';
        _installSecret = '${saved['installSecret'] ?? ''}';
        _servers[endpoint] = _profile();
        await refresh();
        if (paired) return;
      }
      await connectAutomatically();
    } catch (e) {
      error = '$e';
      emit();
    }
  }

  Future<void> refreshSetupAgents() async {
    if (setupAgentsLoading) return;
    final revision = _serverRevision;
    setupAgentsLoading = true;
    setupAgentsError = '';
    emit();
    try {
      final result = await request('/setup/agents', token: '');
      if (revision != _serverRevision || _disposed) return;
      final items = result['agents'];
      if (items is! List || items.isEmpty || items.length > 100) {
        throw ApiError.localized('invalidAgentList');
      }
      final ids = <String>{};
      final agents = <Json>[];
      for (final item in items) {
        if (item is! Map ||
            item['id'] is! String ||
            !RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(item['id']) ||
            !ids.add(item['id']) ||
            item['name'] is! String ||
            (item['name'] as String).trim().isEmpty ||
            (item['name'] as String).length > 80) {
          throw ApiError.localized('invalidAgentConfig');
        }
        final icon = item['icon'];
        final brand = item['brand'];
        if (icon != null &&
                (icon is! String ||
                    icon.isNotEmpty &&
                        !RegExp(
                          r'^(https://[^\s]+|/assets/[a-zA-Z0-9_./-]+)$',
                        ).hasMatch(icon)) ||
            brand != null &&
                (brand is! String ||
                    brand.isNotEmpty &&
                        !RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(brand))) {
          throw ApiError.localized('invalidAgentConfig');
        }
        agents.add({
          'id': item['id'],
          'name': (item['name'] as String).trim(),
          if (icon != null) 'icon': icon,
          if (brand != null) 'brand': brand,
        });
      }
      setupAgents = agents;
    } catch (e) {
      if (revision != _serverRevision || _disposed) return;
      setupAgentsError = '$e';
    } finally {
      if (revision == _serverRevision && !_disposed) {
        setupAgentsLoading = false;
        emit();
      }
    }
  }

  Future<void> connectAutomatically() async {
    if (connecting) throw ApiError.localized('connectionBusy');
    final url = validateEndpoint(endpoint).toString();
    connecting = true;
    error = '';
    emit();
    try {
      if (_deviceId.isEmpty) {
        final random = Random.secure();
        _deviceId = List.generate(
          24,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
      }
      if (_installSecret.isEmpty) {
        final random = Random.secure();
        _installSecret = List.generate(
          32,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
      }
      final result = await request(
        '/mobile/register',
        server: url,
        token: '',
        body: {
          'deviceId': _deviceId,
          'installSecret': _installSecret,
          'name': Platform.isMacOS
              ? 'Mac'
              : Platform.isIOS
              ? 'iPhone / iPad'
              : Platform.isWindows
              ? 'Windows'
              : 'Android',
          'source': 'app',
          'platform':
              '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        },
      );
      final newToken = result['token'];
      if (newToken is! String || newToken.isEmpty) {
        throw ApiError.localized('invalidCredentials');
      }
      _token = newToken;
      await _saveCredentials();
      stop();
      demo = false;
      data = emptyState();
      endpoint = url;
      _token = newToken;
      connected = false;
      await refresh();
    } catch (_) {
      _token = '';
      rethrow;
    } finally {
      connecting = false;
      emit();
    }
  }

  Future<void> refresh() async {
    _timer?.cancel();
    if (!paired || demo || !_foreground || _disposed) return;
    final version = ++_generation;
    final clock = Stopwatch()..start();
    try {
      final next = await request('/snapshot');
      if (version != _generation || _disposed) return;
      if (![
        'instances',
        'sessions',
        'permissions',
        'logs',
      ].every((k) => next[k] is List)) {
        throw ApiError.localized('incompatibleSnapshot');
      }
      data = next;
      connected = true;
      latency = clock.elapsedMilliseconds;
      error = '';
      _failures = 0;
    } catch (e) {
      if (version != _generation || _disposed) return;
      connected = false;
      error = '$e';
      _failures = (_failures + 1).clamp(0, 4);
      if (e is ApiError && e.status == 401) {
        _token = '';
        try {
          await _saveCredentials();
        } catch (_) {}
      }
    } finally {
      if (version == _generation && !_disposed) {
        emit();
        if (paired && _foreground) {
          _timer = Timer(
            Duration(seconds: (2 << _failures).clamp(2, 30)),
            refresh,
          );
        }
      }
    }
  }

  Future<void> reply(
    Json permission,
    String decision, {
    List<List<String>>? answers,
  }) async {
    if (!['once', 'always', 'reject', 'answer'].contains(decision)) {
      throw ApiError.localized('unsupportedApproval');
    }
    if (decision == 'answer' &&
        (answers == null || answers.any((a) => a.isEmpty))) {
      throw ApiError.localized('answerAll');
    }
    if (!canApprove(permission)) {
      throw ApiError.localized('approvalUnavailable');
    }
    action = '${permission['instanceId']}:${permission['id']}';
    emit();
    try {
      if (demo) {
        data['permissions'] = rows('permissions')
            .where(
              (p) =>
                  !(p['id'] == permission['id'] &&
                      p['instanceId'] == permission['instanceId']),
            )
            .toList();
        data['logs'] = [
          ...rows('logs'),
          {
            'id': DateTime.now().microsecondsSinceEpoch,
            'at': DateTime.now().millisecondsSinceEpoch,
            'instanceId': permission['instanceId'],
            'sessionID': permission['sessionID'],
            'demoTextKey': 'demoAction',
            'text':
                conversationCatalog['zh']![conversationKeys.indexOf(
                  'demoAction',
                )],
            'level': 'success',
          },
        ];
      } else {
        final result = await request(
          '/permission',
          body: {
            'instanceId': permission['instanceId'],
            'requestID': permission['id'],
            'reply': decision,
            if (answers != null) 'answers': answers,
          },
        );
        if (result['resolved'] != true) {
          throw ApiError.localized('approvalUnconfirmed');
        }
        await refresh();
      }
    } finally {
      action = '';
      emit();
    }
  }

  bool canControlSession(String instanceId) =>
      !demo &&
      action.isEmpty &&
      data['capabilities']?['sessionControl'] == true &&
      rows('instances').any(
        (d) =>
            d['id'] == instanceId &&
            online(d) &&
            d['capabilities']?['sessionControl'] == true,
      );

  Future<List<Json>> loadSessionMessages(Json session) async {
    if (demo) return [];
    final result = await request(
      '/session-messages',
      body: {'instanceId': session['instanceId'], 'sessionID': session['id']},
    );
    return (result['messages'] as List? ?? [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
  }

  Future<List<Json>> listSessionModels(String instanceId) async {
    if (demo) return [];
    final result = await request(
      '/session-models',
      body: {'instanceId': instanceId},
    );
    final models = (result['models'] as List? ?? [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .where(
          (value) => RegExp(r'^[^/\s]+/.+$').hasMatch('${value['id'] ?? ''}'),
        )
        .toList();
    if (models.isEmpty) throw ApiError.localized('modelsUnavailable');
    return models;
  }

  Future<void> controlSession(
    Json target,
    String operation, {
    String text = '',
    String title = '',
    String model = '',
    String directory = '',
  }) async {
    final instanceId = operation == 'create'
        ? target['id']
        : target['instanceId'];
    if (!canControlSession('$instanceId')) {
      throw ApiError.localized('updateConnector');
    }
    if (!['create', 'abort', 'prompt'].contains(operation)) {
      throw ApiError.localized('unsupportedOperation');
    }
    if (text.length > 4000 ||
        title.length > 200 ||
        model.length > 300 ||
        (model.trim().isNotEmpty &&
            !RegExp(r'^[^/\s]+/.+$').hasMatch(model.trim())) ||
        (operation == 'prompt' && text.trim().isEmpty)) {
      throw ApiError.localized('invalidMessage');
    }
    action = 'session:$instanceId:${target['id']}';
    emit();
    try {
      final result = await request(
        '/session-control',
        body: {
          'instanceId': instanceId,
          'action': operation,
          if (operation != 'create') 'sessionID': target['id'],
          'text': text.trim(),
          if (title.trim().isNotEmpty) 'title': title.trim(),
          if (model.trim().isNotEmpty) 'model': model.trim(),
          if (operation == 'create' && directory.trim().isNotEmpty)
            'directory': directory.trim(),
        },
      );
      if (result['ok'] != true) {
        throw ApiError.localized('operationUnconfirmed');
      }
      await refresh();
    } finally {
      action = '';
      emit();
    }
  }

  Future<void> confirmDeviceBinding(String code) async {
    final value = code.trim().toUpperCase();
    if (!RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(value)) {
      throw ApiError.localized('bindingCodeRequired');
    }
    await _requestAfterRegistration(
      '/device-bind/confirm',
      body: {'code': value},
    );
    await refresh();
  }

  Future<String> issueSetupTicket() async {
    final result = await _requestAfterRegistration('/setup/issue', body: {});
    final ticket = result['ticket'];
    if (ticket is! String || ticket.isEmpty) {
      throw ApiError.localized('invalidSetupTicket');
    }
    return ticket;
  }

  Future<Json> _requestAfterRegistration(
    String path, {
    required Json body,
  }) async {
    if (!paired) await connectAutomatically();
    try {
      return await request(path, body: body);
    } on ApiError catch (error) {
      if (error.status != 401) rethrow;
      await connectAutomatically();
      return request(path, body: body);
    }
  }

  Future<void> renameDevice(String deviceId, String name) async {
    if (name.trim().isEmpty || name.trim().length > 80) {
      throw ApiError.localized('invalidDeviceName');
    }
    await request(
      '/devices/rename',
      body: {'deviceId': deviceId, 'name': name.trim()},
    );
    await refresh();
  }

  Future<void> unbindDevice(String deviceId) async {
    await request('/devices/unbind', body: {'deviceId': deviceId});
    await refresh();
  }

  Future<void> removeDetachedDevice(String deviceId) async {
    await request('/devices/remove', body: {'deviceId': deviceId});
    await refresh();
  }

  Future<void> disconnect() async {
    if (paired) await request('/unpair', body: {});
    stop();
    _token = '';
    _deviceId = '';
    _installSecret = '';
    connected = false;
    demo = false;
    data = emptyState();
    error = '';
    emit();
    await _saveCredentials();
  }

  void enterDemo() {
    stop();
    demo = true;
    connected = false;
    error = '';
    data = demoState();
    emit();
  }

  void leaveDemo() {
    stop();
    demo = false;
    data = emptyState();
    connected = false;
    emit();
    refresh();
  }

  void stop() {
    _generation++;
    _timer?.cancel();
  }

  void foreground(bool active) {
    _foreground = active;
    if (active) {
      refresh();
    } else {
      stop();
      connected = false;
      emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _http.close(force: true);
    super.dispose();
  }
}

double? progress(Json session) {
  final todos = session['todos'] as List?;
  if (todos == null || todos.isEmpty) return null;
  return todos.where((t) => t is Map && t['status'] == 'completed').length /
      todos.length;
}

Json demoState() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return {
    'instances': [
      {
        'id': 'office',
        'hostname': 'MacBook Pro',
        'directory': 'Office · macOS',
        'online': true,
        'lastSeenAt': now,
      },
      {
        'id': 'cloud',
        'hostname': 'AWS Server #1',
        'directory': 'us-west-2 · Linux',
        'online': true,
        'lastSeenAt': now,
      },
      {
        'id': 'home',
        'hostname':
            conversationCatalog['zh']![conversationKeys.indexOf('homeDevice')],
        'directory': 'Home Desktop · RTX 4090',
        'online': true,
        'lastSeenAt': now,
      },
    ],
    'sessions': [
      {
        'id': '104',
        'instanceId': 'office',
        'title':
            conversationCatalog['zh']![conversationKeys.indexOf('refactor')],
        'agent': 'Claude Code',
        'status': 'busy',
        'tool': {
          'title':
              conversationCatalog['zh']![conversationKeys.indexOf('cleanup')],
        },
        'todos': [
          {'status': 'completed'},
          {'status': 'completed'},
          {'status': 'pending'},
        ],
      },
      {
        'id': '105',
        'instanceId': 'office',
        'parentID': '104',
        'title':
            conversationCatalog['zh']![conversationKeys.indexOf('deadlock')],
        'agent': 'Aider CLI',
        'status': 'busy',
        'todos': [
          {'status': 'completed'},
          {'status': 'pending'},
        ],
      },
      {
        'id': '106',
        'instanceId': 'cloud',
        'title': conversationCatalog['zh']![conversationKeys.indexOf('prices')],
        'agent': 'AutoGPT',
        'status': 'busy',
        'todos': List.generate(
          8,
          (i) => {'status': i == 0 ? 'completed' : 'pending'},
        ),
      },
      {
        'id': '107',
        'instanceId': 'home',
        'title':
            conversationCatalog['zh']![conversationKeys.indexOf('training')],
        'agent': 'DeepSeek LLM',
        'status': 'busy',
        'todos': List.generate(
          5,
          (i) => {'status': i < 4 ? 'completed' : 'pending'},
        ),
      },
    ],
    'permissions': [
      {
        'id': '01',
        'instanceId': 'office',
        'sessionID': '104',
        'permission':
            conversationCatalog['zh']![conversationKeys.indexOf('shell')],
        'patterns': ['rm -rf /var/tmp/agent-cache/*'],
      },
    ],
    'logs': [
      for (final (i, text) in [
        'Reading src/api/user.py…',
        'Analyzing dependencies with AST parser…',
        'Applied patch to user_controller.py (3 chunks)',
        '24 passed in 1.42s · Coverage 94.2%',
        'Waiting for permission approval…',
      ].indexed)
        {
          'id': i,
          'at': now - (5 - i) * 4000,
          'instanceId': 'office',
          'sessionID': '104',
          'text': text,
          'demoTextKey': [
            'readLog',
            'analyzeLog',
            'patchLog',
            'testsLog',
            'approvalLog',
          ][i],
          'level': i == 3
              ? 'success'
              : i == 4
              ? 'warn'
              : 'info',
        },
    ],
  };
}
