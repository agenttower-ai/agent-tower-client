import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'connection_store.dart';
import 'project_preferences.dart';
import 'wechat_ui.dart';
import 'conversation_view.dart';
import 'mini_program_pages.dart';
import 'app_localizations.dart';
import 'settings_catalog.dart';
import 'app_brand_icon.dart';
import 'external_link.dart';

const green = Color(0xff00bb70),
    ink = wechatText,
    muted = wechatMuted,
    red = Color(0xfffa5965),
    amber = Color(0xfff7a52e);

String deviceObservation(
  Json device, [
  AppStrings t = const AppStrings(AppLanguage.zh),
]) {
  final rawBinding = device['binding'];
  final binding = rawBinding is Map
      ? Map<String, dynamic>.from(rawBinding)
      : <String, dynamic>{};
  final rawSource = '${binding['source'] ?? device['source'] ?? ''}';
  final source =
      {
        'app': 'App',
        'wechat-mini-program': t.setting(SettingsText.wechatMiniProgram),
        'connector-cli': 'Connector CLI',
        'binding': t.setting(SettingsText.pairingCode),
        'environment': t.setting(SettingsText.serverConfiguration),
      }[rawSource] ??
      rawSource;
  final platform = '${binding['devicePlatform'] ?? device['platform'] ?? ''}';
  final ip =
      '${binding['ip'] ?? device['lastIp'] ?? device['registeredIp'] ?? ''}';
  final lastSeenValue = binding['lastSeenAt'] ?? device['lastSeenAt'];
  final lastSeenAt = lastSeenValue is num
      ? DateTime.fromMillisecondsSinceEpoch(lastSeenValue.toInt()).toLocal()
      : null;
  final lastSeen = lastSeenAt == null
      ? ''
      : '${t.setting(SettingsText.lastSeen)} ${lastSeenAt.month.toString().padLeft(2, '0')}-${lastSeenAt.day.toString().padLeft(2, '0')} ${lastSeenAt.hour.toString().padLeft(2, '0')}:${lastSeenAt.minute.toString().padLeft(2, '0')}';
  return [
    source,
    platform,
    if (ip.isNotEmpty) 'IP $ip',
    lastSeen,
  ].where((value) => value.isNotEmpty).join(' · ');
}

String? bindingCodeFromQr(String raw) {
  final value = raw.trim();
  final direct = value.toUpperCase();
  if (RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(direct)) return direct;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'agenttower' ||
      uri.host.toLowerCase() != 'bind') {
    return null;
  }
  final code = (uri.queryParameters['code'] ?? '').trim().toUpperCase();
  return RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(code) ? code : null;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Match the mini-program presentation: the Flutter surface owns the whole
  // screen instead of leaving Android's navigation/status bars around it.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const AgentTowerApp());
}

class AgentTowerApp extends StatefulWidget {
  const AgentTowerApp({super.key, this.store});
  final TowerStore? store;
  @override
  State<AgentTowerApp> createState() => _AgentTowerAppState();
}

class _AgentTowerAppState extends State<AgentTowerApp>
    with WidgetsBindingObserver {
  late final TowerStore store = widget.store ?? TowerStore();
  int onboardingTab = 0;
  final language = LanguagePreference();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    language.load();
    if (widget.store == null) {
      store.restore();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    store.foreground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    language.dispose();
    if (widget.store == null) {
      store.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: language,
    builder: (context, selectedLanguage, _) => MaterialApp(
      title: 'Agent Tower',
      debugShowCheckedModeBanner: false,
      locale: selectedLanguage.locale,
      supportedLocales: AppLanguage.values
          .map((language) => language.locale)
          .toList(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => ValueListenableBuilder<AppLanguage>(
        valueListenable: language,
        builder: (context, value, _) => AppLocale(
          language: value,
          onChanged: (value) async {
            try {
              await language.select(value);
            } on PlatformException catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(content: Text(AppStrings(value).saveError)),
                );
              }
            } on MissingPluginException catch (_) {
              // Previews still support changing the current language.
            }
          },
          child: Directionality(textDirection: value.direction, child: child!),
        ),
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: wechatBlue,
          primary: wechatBlue,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: wechatBackground,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: wechatBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: wechatBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xfff2f7ff),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xffdce5f0)),
          ),
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
      home: Builder(
        builder: (context) => AnimatedBuilder(
          animation: store,
          builder: (context, _) => store.hasBoundWorkspace && !store.demo
              ? TowerHome(store: store)
              : onboardingTab != 0 && !store.demo
              ? TowerHome(
                  store: store,
                  initialTab: onboardingTab,
                  onHome: () => setState(() => onboardingTab = 0),
                )
              : WechatUiHome(
                  store: store,
                  onNavigate: (label) {
                    final tab =
                        AppLanguage.values.any(
                          (language) => AppStrings(language).settings == label,
                        )
                        ? 3
                        : AppLanguage.values.any(
                            (language) =>
                                AppStrings(language).developerNews == label,
                          )
                        ? 4
                        : AppLanguage.values.any(
                            (language) => AppStrings(language).help == label,
                          )
                        ? 5
                        : 0;
                    if (tab != 0) setState(() => onboardingTab = tab);
                  },
                  onDemo: () async {
                    store.enterDemo();
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => TowerHome(store: store),
                      ),
                    );
                    store.leaveDemo();
                  },
                ),
        ),
      ),
    ),
  );
}

class TowerHome extends StatefulWidget {
  const TowerHome({
    super.key,
    required this.store,
    this.initialTab = 0,
    this.onHome,
  });
  final TowerStore store;
  final int initialTab;
  final VoidCallback? onHome;
  @override
  State<TowerHome> createState() => _TowerHomeState();
}

class _TowerHomeState extends State<TowerHome> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  TowerStore get s => widget.store;
  AppStrings get t => AppLocale.of(context);

  void navigateDrawer(String label) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (AppLanguage.values.any(
          (language) => AppStrings(language).home == label,
        ) &&
        widget.onHome != null) {
      widget.onHome!();
      return;
    }
    setState(() {
      tab =
          AppLanguage.values.any(
            (language) => AppStrings(language).settings == label,
          )
          ? 3
          : AppLanguage.values.any(
              (language) => AppStrings(language).developerNews == label,
            )
          ? 4
          : AppLanguage.values.any(
              (language) => AppStrings(language).help == label,
            )
          ? 5
          : 0;
      query = '';
    });
  }

  void openSession(Json session) {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationView(
          store: s,
          session: session,
          hostname: deviceName(session['instanceId']),
          onNavigate: navigateDrawer,
        ),
      ),
    );
  }

  late int tab;
  String query = '';
  final Set<String> expandedTasks = {};
  final Set<String> collapsedDevices = {};
  final Set<String> expandedProjects = {};
  final Set<String> allProjectSessions = {};
  final projectPreferences = ProjectPreferences();
  String projectFilter = 'all';
  @override
  void initState() {
    super.initState();
    tab = widget.initialTab;
    projectPreferences
        .load()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object _) {});
  }

  bool projectVisible(String key, List<Json> tasks) => projectFilter == 'hidden'
      ? projectPreferences.hidden.contains(key)
      : !projectPreferences.hidden.contains(key) &&
            (projectFilter != 'followed' ||
                projectPreferences.followed.contains(key)) &&
            (projectFilter != 'active' || tasks.any(needsAttention));
  bool hasVisibleProjects(List<Json> instances, List<Json> sessions) {
    for (final instance in instances) {
      final id =
          '${instance['deviceId'] ?? instance['hostname'] ?? instance['id']}';
      final tasks = sessions
          .where((t) => t['instanceId'] == instance['id'])
          .toList();
      final agent =
          '${instance['agent'] ?? tasks.firstOrNull?['agent'] ?? 'Agent'}';
      final directories = {
        '${instance['directory'] ?? unspecifiedProjectDirectory}',
        ...tasks.map(
          (t) =>
              '${t['directory'] ?? instance['directory'] ?? unspecifiedProjectDirectory}',
        ),
      };
      if (directories.any(
        (directory) => projectVisible(
          '$id\u0000$agent\u0000$directory',
          tasks
              .where(
                (t) =>
                    '${t['directory'] ?? instance['directory'] ?? unspecifiedProjectDirectory}' ==
                    directory,
              )
              .toList(),
        ),
      )) {
        return true;
      }
    }
    return false;
  }

  void projectAction(String key, String action) {
    setState(() {
      final values = action == 'follow'
          ? projectPreferences.followed
          : projectPreferences.hidden;
      if (!values.remove(key)) values.add(key);
    });
    projectPreferences.save().catchError(
      (Object _) => message(t.drawer("saveFailed")),
    );
  }

  String deviceName(dynamic id) =>
      s
          .rows('instances')
          .where((d) => d['id'] == id)
          .map((d) => t.demoValue(d['hostname'] ?? id, demo: s.demo))
          .firstOrNull ??
      '$id';
  void message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> reconnect() async {
    try {
      await s.connectAutomatically();
      if (mounted) setState(() => tab = 0);
    } catch (e) {
      message(t.errorText(e));
    }
  }

  Future<void> addDevice() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => WechatUiHome(
          store: s,
          onDemo: () {},
          onBack: () => Navigator.of(context).pop(),
          onNavigate: navigateDrawer,
        ),
      ),
    );
  }

  Future<void> renameBoundDevice(Json device) async {
    final controller = TextEditingController(text: '${device['name']}');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(settingsText(SettingsText.renameDevice)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(settingsText(SettingsText.cancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: Text(settingsText(SettingsText.save)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    try {
      await s.renameDevice('${device['id']}', name);
    } catch (e) {
      message(t.errorText(e));
    }
  }

  Future<void> removeBoundDevice(Json device) async {
    final detached = device['bound'] == false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          detached
              ? settingsText(SettingsText.removeUnpairedDeviceTitle)
              : settingsText(SettingsText.unpairDeviceTitle),
        ),
        content: Text(
          detached
              ? settingsText(
                  SettingsText.removeDeviceHistory,
                  name: '${device['name']}',
                )
              : settingsText(
                  SettingsText.unpairDeviceExplanation,
                  name: '${device['name']}',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(settingsText(SettingsText.cancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              detached
                  ? settingsText(SettingsText.removeRecord)
                  : settingsText(SettingsText.unpair),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (detached) {
        await s.removeDetachedDevice('${device['id']}');
      } else {
        await s.unbindDevice('${device['id']}');
      }
    } catch (e) {
      message(t.errorText(e));
    }
  }

  Future<void> approve(Json p, String decision) async {
    final nativeRules = s
        .rows('instances')
        .any((i) => i['id'] == p['instanceId'] && i['agent'] == 'opencode');
    final scope = nativeRules
        ? AppLocale.of(context).approval('nativeScope')
        : AppLocale.of(context).approval('connectorScope');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          decision == 'always'
              ? AppLocale.of(context).approval('allowTitle')
              : decision == 'once'
              ? AppLocale.of(context).approval('approveTitle')
              : AppLocale.of(context).approval('rejectTitle'),
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            '${s.demo ? '${AppLocale.of(context).approval('demoMode')} · ' : ''}${deviceName(p['instanceId'])}\n\n${patterns(p, t)}${decision == 'always' ? '\n\n${AppLocale.of(context).approval('approveAndAllow', scope: scope)}' : ''}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(settingsText(SettingsText.cancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              decision == 'always'
                  ? AppLocale.of(context).approval('allow')
                  : decision == 'once'
                  ? AppLocale.of(context).approval('approveOnce')
                  : AppLocale.of(context).approval('confirmReject'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await s.reply(p, decision);
      if (!mounted) return;
      message(
        s.demo
            ? AppLocale.of(context).approval('demoDone')
            : AppLocale.of(context).approval('agentConfirmed'),
      );
    } catch (e) {
      message(t.errorText(e));
    }
  }

  Future<void> answerQuestion(Json p) async {
    final questions =
        (p['questions'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        <Json>[];
    if (questions.isEmpty) return;
    final selected = List.generate(questions.length, (_) => <String>{});
    final custom = List.generate(
      questions.length,
      (_) => TextEditingController(),
    );
    final answers = await showDialog<List<List<String>>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(AppLocale.of(context).approval('answerTitle')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < questions.length; index++) ...[
                    Text(
                      '${questions[index]['header'] ?? '${AppLocale.of(context).approval('question')} ${index + 1}'}',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${questions[index]['question'] ?? ''}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option
                            in (questions[index]['options'] as List? ??
                                const []))
                          Builder(
                            builder: (_) {
                              final value = '${(option as Map)['label'] ?? ''}';
                              return ChoiceChip(
                                label: Text(value),
                                selected: selected[index].contains(value),
                                onSelected: (enabled) => setDialogState(() {
                                  if (questions[index]['multiple'] != true) {
                                    selected[index].clear();
                                  }
                                  if (enabled) {
                                    selected[index].add(value);
                                  } else {
                                    selected[index].remove(value);
                                  }
                                }),
                              );
                            },
                          ),
                      ],
                    ),
                    if (questions[index]['custom'] != false) ...[
                      const SizedBox(height: 10),
                      TextField(
                        key: ValueKey('question-custom-$index'),
                        controller: custom[index],
                        maxLength: 2000,
                        decoration: InputDecoration(
                          hintText: AppLocale.of(
                            context,
                          ).approval('customAnswer'),
                        ),
                      ),
                    ],
                    if (index + 1 < questions.length) const Divider(height: 30),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(settingsText(SettingsText.cancel)),
            ),
            FilledButton(
              key: const ValueKey('question-submit'),
              onPressed: () {
                final value = <List<String>>[];
                for (var index = 0; index < questions.length; index++) {
                  final answer = selected[index].toList();
                  final text = custom[index].text.trim();
                  if (text.isNotEmpty) answer.add(text);
                  if (answer.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocale.of(context).approval(
                            'answerRequiredHint',
                            name:
                                '${questions[index]['header'] ?? '${AppLocale.of(context).approval('question')} ${index + 1}'}',
                          ),
                        ),
                      ),
                    );
                    return;
                  }
                  value.add(answer);
                }
                Navigator.pop(dialogContext, value);
              },
              child: Text(AppLocale.of(context).approval('submitAnswer')),
            ),
          ],
        ),
      ),
    );
    for (final controller in custom) {
      controller.dispose();
    }
    if (answers == null) return;
    try {
      await s.reply(p, 'answer', answers: answers);
      if (!mounted) return;
      message(AppLocale.of(context).approval('answerSent'));
    } catch (e) {
      message(t.errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: s,
    builder: (context, _) => Scaffold(
      key: _scaffoldKey,
      drawerScrimColor: const Color(0x6113231d),
      drawer: WechatUiHome(
        store: s,
        onDemo: () {},
        sidebarOnly: true,
        onClose: () => _scaffoldKey.currentState?.closeDrawer(),
        onNavigate: navigateDrawer,
        onCreateSession: (instance) =>
            sessionControlDialog(context, s, instance, 'create'),
        onSession: (session) {
          _scaffoldKey.currentState?.closeDrawer();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ConversationView(
                store: s,
                session: session,
                hostname: deviceName(session['instanceId']),
                onNavigate: navigateDrawer,
              ),
            ),
          );
        },
      ),
      backgroundColor: const Color(0xfff5f8fc),
      body: SafeArea(
        child: Column(
          children: [
            _wechatDemoHeader(),
            if (s.demo) _demoNotice(),
            if (s.paired && !s.demo && !s.connected)
              Container(
                width: double.infinity,
                color: red.withAlpha(20),
                padding: const EdgeInsets.all(10),
                child: Text(
                  s.error.isEmpty
                      ? settingsText(SettingsText.connectingServer)
                      : '${t.errorText(s.error)} · ${settingsText(SettingsText.controlDisabled)}',
                  style: const TextStyle(fontSize: 11, color: red),
                ),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints.expand(),
                  child: RefreshIndicator(
                    onRefresh: s.refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (tab == 3)
                          ...settings()
                        else if (tab == 4)
                          AnnouncementsView(store: s)
                        else if (tab == 5)
                          HelpView(store: s)
                        else if (!s.paired && !s.demo)
                          ...welcome()
                        else if (tab == 2)
                          ...logs()
                        else
                          ...dashboard(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _wechatDemoHeader() => Container(
    height: 66,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    color: Colors.white,
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('demo-menu'),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          icon: const Icon(Icons.menu_rounded, color: Color(0xff34445b)),
        ),
        const AppBrandIcon(size: 38),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppLocale.of(context).appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xff172b46),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const LanguageButton(),
        if (s.paired && !s.demo)
          IconButton(
            key: const ValueKey('add-device-action'),
            tooltip: settingsText(SettingsText.addDevice),
            onPressed: addDevice,
            icon: const Icon(Icons.add_link_rounded, color: wechatBlue),
          ),
      ],
    ),
  );

  Widget _demoNotice() => Container(
    color: const Color(0xfffff3d9),
    padding: const EdgeInsets.only(left: 16, right: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            settingsText(SettingsText.demoNotice),
            style: TextStyle(fontSize: 11, color: Color(0xffa1813a)),
          ),
        ),
        TextButton(
          onPressed: () {
            s.leaveDemo();
            Navigator.of(context).maybePop();
          },
          child: Text(
            settingsText(SettingsText.exitDemo),
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );

  List<Widget> welcome() => [
    Row(
      children: [
        Dot(amber),
        SizedBox(width: 8),
        Text(t.mobile("waitingConnection"), style: TextStyle(fontSize: 12)),
        SizedBox(width: 12),
        Text(
          t.mobile("zeroOnline"),
          style: TextStyle(fontSize: 12, color: muted),
        ),
        Spacer(),
        Text(
          'SERVER LINK',
          style: TextStyle(fontSize: 9, letterSpacing: 1, color: muted),
        ),
      ],
    ),
    const SizedBox(height: 20),
    Panel(
      child: Column(
        children: [
          Container(
            height: 200,
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: const Color(0xfff4f9f6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.phone_android_rounded,
                  size: 43,
                  color: Color(0xff527e6c),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('···', style: TextStyle(color: muted)),
                ),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: green.withAlpha(25),
                        blurRadius: 25,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Dot(red, size: 25),
                      SizedBox(height: 8),
                      Dot(amber, size: 25),
                      SizedBox(height: 8),
                      Dot(green, size: 25),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('···', style: TextStyle(color: muted)),
                ),
                const Icon(
                  Icons.laptop_mac_rounded,
                  size: 48,
                  color: Color(0xff527e6c),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            t.mobile("agentReach"),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            t.mobile("connectGuide"),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.9, color: muted),
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: s.connecting ? null : reconnect,
              icon: const Icon(Icons.sync_rounded),
              label: Text(
                s.connecting
                    ? t.setting(SettingsText.connecting)
                    : t.setting(SettingsText.reconnect),
              ),
            ),
          ),
          if (s.error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              t.errorText(s.error),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: red),
            ),
          ],
          const SizedBox(height: 13),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_outlined, size: 14, color: green),
              SizedBox(width: 5),
              Text(
                t.mobile("secureConnection"),
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: s.enterDemo, child: Text(t.demo)),
        ],
      ),
    ),
    if (s.paired)
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              t.setting(SettingsText.deviceManagement),
              trailing: 'DEVICE ACCESS',
            ),
            if (s.rows('devices').isEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  t.mobile("noAuthorizedDevices"),
                  style: TextStyle(color: muted),
                ),
              ),
            for (final device in s.rows('devices'))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  device['online'] == true
                      ? Icons.computer
                      : Icons.computer_outlined,
                  color: device['online'] == true ? wechatBlue : muted,
                ),
                title: Text('${device['name'] ?? device['id']}'),
                subtitle: Text(
                  '${device['id']} · ${device['bound'] == false
                      ? t.setting(SettingsText.unpaired)
                      : device['managed'] == true
                      ? t.mobile("phoneManaged")
                      : t.setting(SettingsText.serverConfiguration)}${deviceObservation(device, t).isEmpty ? '' : '\n${deviceObservation(device, t)}'}',
                ),
                trailing: device['managed'] == true || device['bound'] == false
                    ? PopupMenuButton<String>(
                        onSelected: (value) => value == 'rename'
                            ? renameBoundDevice(device)
                            : removeBoundDevice(device),
                        itemBuilder: (_) => [
                          if (device['bound'] != false)
                            PopupMenuItem(
                              value: 'rename',
                              child: Text(t.setting(SettingsText.rename)),
                            ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(
                              device['bound'] == false
                                  ? t.setting(SettingsText.removeRecord)
                                  : t.setting(SettingsText.unpair),
                            ),
                          ),
                        ],
                      )
                    : Tooltip(
                        message: t.mobile("environmentManaged"),
                        child: Icon(Icons.lock_outline, size: 18),
                      ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: addDevice,
                icon: const Icon(Icons.add),
                label: Text(t.setting(SettingsText.addDevice)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.setting(SettingsText.addDeviceGuide),
              style: TextStyle(fontSize: 11, color: muted, height: 1.6),
            ),
          ],
        ),
      ),
    Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(t.mobile("quickStart"), trailing: 'QUICK START'),
          for (final (index, title, copy) in [
            (1, t.mobile("relayDeploy"), t.mobile("relayDeployGuide")),
            (2, t.mobile("installMonitor"), t.mobile("monitorGuide")),
            (3, t.mobile("phoneConfirm"), t.mobile("phoneConfirmGuide")),
          ])
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BadgeText('$index', green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          copy,
                          style: const TextStyle(
                            fontSize: 12,
                            color: muted,
                            height: 1.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  ];

  List<Widget> dashboard() {
    final devices = s.rows('instances'),
        permissions = s.rows('permissions'),
        sessions = s.rows('sessions');
    final online = devices.where(s.online).toList();
    if (tab == 0) {
      return [
        if (s.demo)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xffeaf4ff),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permissions.isEmpty
                      ? AppLocale.of(context).approval('doneTitle')
                      : AppLocale.of(context).approval('tryTitle'),
                  style: TextStyle(
                    color: wechatText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  permissions.isEmpty
                      ? AppLocale.of(context).approval('doneGuide')
                      : AppLocale.of(context).approval('tryGuide'),
                  style: const TextStyle(
                    color: wechatMuted,
                    fontSize: 13,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        for (final permission in permissions)
          if (s.demo)
            _demoApprovalCard(permission)
          else
            approvalCard(permission),
        if (!s.demo && devices.isNotEmpty && permissions.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xffe3ebf5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocale.of(
                    context,
                  ).workspace(sessions.isEmpty ? 'firstTask' : 'sessionsReady'),
                  style: TextStyle(
                    color: wechatText,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  AppLocale.of(context).workspace(
                    sessions.isEmpty ? 'startGuide' : 'sessionsGuide',
                  ),
                  style: const TextStyle(color: wechatMuted, height: 1.8),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  style: FilledButton.styleFrom(backgroundColor: wechatBlue),
                  child: Text(AppLocale.of(context).workspace('viewProjects')),
                ),
              ],
            ),
          ),
        if (!s.demo && devices.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.mobile("waitingOnline"),
                style: TextStyle(
                  color: wechatText,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t.mobile("keepConnectorRunning"),
                style: TextStyle(color: wechatMuted, height: 1.8),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('empty-add-device'),
                onPressed: addDevice,
                style: FilledButton.styleFrom(backgroundColor: wechatBlue),
                child: Text(t.mobile("connectAnother")),
              ),
            ],
          ),
      ];
    }
    final active = sessions
        .where(
          (a) =>
              ['busy', 'retry', 'thinking'].contains(a['status']) &&
              online.any((d) => d['id'] == a['instanceId']),
        )
        .length;
    return [
      Row(
        children: [
          Dot(s.demo || s.connected ? green : amber),
          const SizedBox(width: 8),
          Text(
            s.demo
                ? t.mobile("demoReady")
                : s.connected
                ? t.setting(SettingsText.relayConnected)
                : t.setting(SettingsText.connectingServer),
            style: const TextStyle(fontSize: 12),
          ),
          const Spacer(),
          Text(
            s.demo
                ? 'DEMO WORKSPACE'
                : t.mobile("syncLatency", values: [s.latency]),
            style: const TextStyle(color: muted, fontSize: 10),
          ),
        ],
      ),
      const SizedBox(height: 18),
      if (tab == 0) ...[
        Panel(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          permissions.isEmpty
                              ? t.mobile("allReady")
                              : t.mobile("decisionNeeded"),
                          style: TextStyle(
                            fontSize: 11,
                            color: permissions.isEmpty ? green : red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.mobile("clusterStatus"),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Text(
                          'TRAFFIC LIGHT',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.5,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.power_settings_new, size: 16),
                    label: Text(
                      t.mobile("emergencyStop"),
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const Divider(height: 32, color: Color(0xffedf0ed)),
              Row(
                children: [
                  Expanded(
                    child: Metric(
                      t.mobile("runningNodes"),
                      '${deviceGroups(online).length}',
                      t.mobile("onlineUnit"),
                      green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Metric(
                      t.conversation("approval"),
                      '${permissions.length}',
                      t.mobile("requestsUnit"),
                      red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Metric(
                      t.mobile("tasksTitle"),
                      '$active',
                      t.mobile("runningUnit"),
                      amber,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final p in permissions) approvalCard(p),
        if (permissions.isEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_outlined, size: 17, color: green),
                SizedBox(width: 7),
                Text(
                  AppLocale.of(context).approval('queueEmpty'),
                  style: TextStyle(color: Color(0xff6d977d), fontSize: 11),
                ),
              ],
            ),
          ),
      ] else
        Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DEVICE FLEET',
                style: TextStyle(fontSize: 10, letterSpacing: 2, color: muted),
              ),
              SizedBox(height: 7),
              Text(
                t.mobile("deviceTree"),
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      SectionTitle(
        t.mobile("deviceCluster"),
        trailing: t.mobile(
          "deviceSessionCount",
          values: [deviceGroups(devices).length, sessions.length],
        ),
      ),
      const SizedBox(height: 13),
      Wrap(
        spacing: 8,
        children: [
          for (final entry in {
            'active': t.drawer("active"),
            'followed': t.drawer("followed"),
            'all': t.text("all"),
            'hidden': t.drawer("hidden"),
          }.entries)
            ChoiceChip(
              key: ValueKey('project-filter-${entry.key}'),
              label: Text(entry.value),
              selected: projectFilter == entry.key,
              onSelected: (_) => setState(() => projectFilter = entry.key),
            ),
        ],
      ),
      const SizedBox(height: 12),
      for (final group in deviceGroups(devices).entries)
        groupedDeviceCard(group.key, group.value, sessions),
      if (devices.isNotEmpty && !hasVisibleProjects(devices, sessions))
        Panel(
          child: Text(
            projectFilter == 'followed'
                ? t.mobile("noFollowed")
                : projectFilter == 'hidden'
                ? t.mobile("noHidden")
                : t.mobile("restoreGuide"),
          ),
        ),
      if (devices.isEmpty)
        Panel(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  t.mobile("noDevicesGuide"),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, height: 1.8),
                ),
                if (!s.demo) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('empty-add-device'),
                      onPressed: addDevice,
                      icon: const Icon(Icons.add_link_rounded),
                      label: Text(t.mobile("addWithCode")),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    ];
  }

  Widget approvalCard(Json p) {
    final isQuestion = p['question'] == true && p['questions'] is List;
    final task = s
        .rows('sessions')
        .where(
          (a) =>
              a['id'] == p['sessionID'] && a['instanceId'] == p['instanceId'],
        )
        .firstOrNull;
    final tool = task?['tool'];
    return Panel(
      borderTop: red,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AgentIcon(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName(p['instanceId']),
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${AppLocale.of(context).demoValue(p['permission'], demo: s.demo)} · ${isQuestion ? AppLocale.of(context).approval('answerRequired') : AppLocale.of(context).approval('authorization')}',
                      style: const TextStyle(fontSize: 11, color: red),
                    ),
                  ],
                ),
              ),
              BadgeText(
                '${AppLocale.of(context).approval('approval')} #${p['id'].toString().length > 4 ? p['id'].toString().substring(p['id'].toString().length - 4) : p['id']}',
                red,
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            isQuestion
                ? AppLocale.of(context).approval('waitingChoice')
                : tool is Map
                ? AppLocale.of(context).demoValue(
                    tool['title'] ??
                        AppLocale.of(context).approval('requestAction'),
                    demo: s.demo,
                  )
                : AppLocale.of(context).approval('requestAction'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xff222a31),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isQuestion
                      ? '[question] ${AppLocale.of(context).approval('questionGuide')}'
                      : '[permission] ${AppLocale.of(context).approval('permissionGuide')}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: amber,
                  ),
                ),
                const SizedBox(height: 9),
                SelectableText(
                  '\$ ${patterns(p, t)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          if (p['error'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t.errorText(p['error']),
                style: const TextStyle(color: red, fontSize: 11),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: s.canApprove(p)
                      ? () => approve(p, 'reject')
                      : null,
                  child: Text(
                    AppLocale.of(context).approval('reject'),
                    style: TextStyle(color: red),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: ValueKey(
                    isQuestion
                        ? 'question-answer-${p['id']}'
                        : 'permission-approve-${p['id']}',
                  ),
                  onPressed: s.canApprove(p)
                      ? () =>
                            isQuestion ? answerQuestion(p) : approve(p, 'once')
                      : null,
                  icon: Icon(
                    isQuestion
                        ? Icons.question_answer_outlined
                        : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(
                    s.action == '${p['instanceId']}:${p['id']}' ||
                            p['submitting'] == true
                        ? AppLocale.of(context).approval('receipt')
                        : isQuestion
                        ? AppLocale.of(context).approval('answer')
                        : AppLocale.of(context).approval('approveExecute'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          if (!isQuestion &&
              (p['allowSimilar'] == true ||
                  s
                      .rows('instances')
                      .any(
                        (i) =>
                            i['id'] == p['instanceId'] &&
                            i['agent'] == 'opencode',
                      )))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: ValueKey('permission-always-${p['id']}'),
                  onPressed: s.canApprove(p)
                      ? () => approve(p, 'always')
                      : null,
                  child: Text(AppLocale.of(context).approval('allow')),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _demoApprovalCard(Json permission) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffe1e9f3)),
      borderRadius: BorderRadius.circular(15),
    ),
    foregroundDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: red, width: 3)),
      borderRadius: BorderRadius.all(Radius.circular(15)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              AppLocale.of(context).approval('workstation'),
              style: TextStyle(color: wechatMuted, fontSize: 12),
            ),
            BadgeText(AppLocale.of(context).approval('authorization'), red),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          AppLocale.of(context).approval('executeShell'),
          style: TextStyle(
            color: wechatText,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xff1d2938),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            patterns(permission, t),
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => approve(permission, 'reject'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xfffff0f2),
                  foregroundColor: red,
                ),
                child: Text(AppLocale.of(context).approval('reject')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: ValueKey('permission-approve-${permission['id']}'),
                onPressed: () => approve(permission, 'once'),
                style: FilledButton.styleFrom(backgroundColor: wechatBlue),
                child: Text(AppLocale.of(context).approval('approveOnce')),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  String taskKey(Json task) => '${task['instanceId']}:${task['id']}';

  List<Json> childTasks(Json parent, List<Json> sessions) => sessions
      .where(
        (task) =>
            task['parentID'] != null &&
            '${task['parentID']}' == '${parent['id']}' &&
            task['instanceId'] == parent['instanceId'] &&
            taskKey(task) != taskKey(parent),
      )
      .toList();

  List<Json> rootTasks(List<Json> sessions) {
    final ids = sessions.map(taskKey).toSet();
    return sessions
        .where(
          (task) =>
              task['parentID'] == null ||
              !ids.contains('${task['instanceId']}:${task['parentID']}') ||
              '${task['parentID']}' == '${task['id']}',
        )
        .toList();
  }

  List<Widget> taskTree(
    Json task,
    List<Json> sessions, {
    int depth = 0,
    Set<String> ancestors = const <String>{},
  }) {
    final key = taskKey(task);
    final nextAncestors = {...ancestors, key};
    final children = childTasks(
      task,
      sessions,
    ).where((child) => !nextAncestors.contains(taskKey(child))).toList();
    final expanded = expandedTasks.contains(key);
    return [
      Container(
        margin: EdgeInsets.only(left: depth * 18.0),
        decoration: BoxDecoration(
          color: depth == 0 ? Colors.transparent : const Color(0xfffbfdfc),
          border: const Border(top: BorderSide(color: Color(0xffedf0ee))),
          borderRadius: depth == 0
              ? null
              : const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => TaskPage(
                    store: s,
                    task: task,
                    hostname: deviceName(task['instanceId']),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        AgentIcon(blue: task['agent'] == 'Aider CLI'),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${task['agent'] ?? 'OpenCode'} · ${AppLocale.of(context).demoValue(task['title'], demo: s.demo)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                depth > 0
                                    ? t.mobile("subagentDetails")
                                    : t.mobile("taskDetailsHint"),
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        BadgeText(
                          AppLocale.of(context).sessionStatus(task['status']),
                          task['status'] == 'error'
                              ? red
                              : ['idle', 'success'].contains(task['status'])
                              ? green
                              : amber,
                        ),
                      ],
                    ),
                    if (progress(task) != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: progress(task),
                            minHeight: 5,
                            color: progress(task) == 1 ? green : amber,
                            backgroundColor: const Color(0xffeaedeb),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (children.isNotEmpty)
              InkWell(
                key: ValueKey('children-toggle-$key'),
                onTap: () => setState(() {
                  if (expanded) {
                    expandedTasks.remove(key);
                  } else {
                    expandedTasks.add(key);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 11),
                  child: Row(
                    children: [
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 18,
                        color: const Color(0xff61806e),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        t.mobile("childCount", values: [children.length]),
                        style: TextStyle(
                          color: Color(0xff61806e),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        expanded ? t.mobile("collapse") : t.mobile("expand"),
                        style: const TextStyle(color: muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      if (expanded)
        for (final child in children)
          ...taskTree(
            child,
            sessions,
            depth: depth + 1,
            ancestors: nextAncestors,
          ),
    ];
  }

  Map<String, List<Json>> deviceGroups(List<Json> instances) {
    final groups = <String, List<Json>>{};
    for (final instance in instances) {
      final id =
          '${instance['deviceId'] ?? instance['hostname'] ?? instance['id']}';
      groups.putIfAbsent(id, () => []).add(instance);
    }
    return groups;
  }

  bool needsAttention(Json task) =>
      [
        'busy',
        'thinking',
        'retry',
        'alarm',
        'error',
      ].contains(task['status']) ||
      s
          .rows('permissions')
          .any(
            (p) =>
                p['instanceId'] == task['instanceId'] &&
                p['sessionID'] == task['id'],
          );

  Widget groupedDeviceCard(
    String id,
    List<Json> instances,
    List<Json> sessions,
  ) {
    final ids = instances.map((i) => i['id']).toSet();
    final tasks = sessions.where((t) => ids.contains(t['instanceId'])).toList();
    final projects = <String, List<Json>>{};
    final representatives = <String, Json>{};
    for (final instance in instances) {
      final instanceTasks = tasks
          .where((t) => t['instanceId'] == instance['id'])
          .toList();
      final directories = <String>{
        '${instance['directory'] ?? unspecifiedProjectDirectory}',
        ...instanceTasks.map(
          (t) =>
              '${t['directory'] ?? instance['directory'] ?? unspecifiedProjectDirectory}',
        ),
      };
      for (final directory in directories) {
        final agent =
            '${instance['agent'] ?? instanceTasks.firstOrNull?['agent'] ?? 'Agent'}';
        final key = '$id\u0000$agent\u0000$directory';
        projects
            .putIfAbsent(key, () => [])
            .addAll(
              instanceTasks.where(
                (t) =>
                    '${t['directory'] ?? instance['directory'] ?? unspecifiedProjectDirectory}' ==
                    directory,
              ),
            );
        if (!representatives.containsKey(key) ||
            (!s.online(representatives[key]!) && s.online(instance))) {
          representatives[key] = {
            ...instance,
            'directory': directory,
            'agent': agent,
          };
        }
      }
    }
    final collapsed = collapsedDevices.contains(id);
    final visibleProjects = projects.entries
        .where((p) => projectVisible(p.key, p.value))
        .toList();
    if (visibleProjects.isEmpty) return const SizedBox.shrink();
    return Panel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              key: ValueKey('device-toggle-$id'),
              onTap: () => setState(() {
                if (!collapsedDevices.remove(id)) collapsedDevices.add(id);
              }),
              leading: const Icon(Icons.devices_rounded, color: muted),
              title: Text(
                t.demoValue(instances.first['hostname'] ?? id, demo: s.demo),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                t.mobile(
                  "projectSessionCount",
                  values: [projects.length, tasks.length],
                ),
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BadgeText(
                    instances.any(s.online)
                        ? t.setting(SettingsText.online)
                        : t.setting(SettingsText.offline),
                    instances.any(s.online) ? green : muted,
                  ),
                  Icon(collapsed ? Icons.expand_more : Icons.expand_less),
                ],
              ),
            ),
            if (!collapsed)
              for (final project in visibleProjects)
                projectSection(
                  project.key,
                  representatives[project.key]!,
                  project.value,
                ),
          ],
        ),
      ),
    );
  }

  Widget projectSection(String key, Json instance, List<Json> tasks) {
    final roots = rootTasks(tasks);
    int time(Json task) =>
        task['updatedAt'] is num ? (task['updatedAt'] as num).toInt() : 0;
    bool attention(Json root) =>
        needsAttention(root) ||
        tasks.any(
          (t) =>
              needsAttention(t) &&
              t['instanceId'] == root['instanceId'] &&
              t['parentID'] == root['id'],
        );
    roots.sort((a, b) {
      final priority = (attention(b) ? 1 : 0) - (attention(a) ? 1 : 0);
      if (priority != 0) return priority;
      final recent = time(b).compareTo(time(a));
      return recent != 0 ? recent : taskKey(a).compareTo(taskKey(b));
    });
    final important = roots.where(attention).toList();
    final recent = roots
        .where((t) => !attention(t))
        .take(tab == 0 ? 0 : 5)
        .toList();
    final visible = projectFilter == 'active'
        ? important
        : allProjectSessions.contains(key)
        ? roots
        : [...important, ...recent];
    final collapsed = !expandedProjects.contains(key);
    final directory = '${instance['directory']}';
    final name = directory == unspecifiedProjectDirectory
        ? t.drawer('unnamedProject')
        : directory
                  .replaceAll('\\', '/')
                  .split('/')
                  .where((v) => v.isNotEmpty)
                  .lastOrNull ??
              directory;
    final running = tasks
        .where((t) => ['busy', 'thinking', 'retry'].contains(t['status']))
        .length;
    final pending = s
        .rows('permissions')
        .where(
          (p) => tasks.any(
            (t) =>
                t['id'] == p['sessionID'] && t['instanceId'] == p['instanceId'],
          ),
        )
        .length;
    return Column(
      children: [
        ListTile(
          key: ValueKey('project-toggle-$key'),
          onTap: () => setState(() {
            if (!expandedProjects.remove(key)) expandedProjects.add(key);
          }),
          leading: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
          title: Text(
            '$name · ${instance['agent']}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            t.mobile(
              "projectSummary",
              values: [
                running,
                pending,
                tasks.length,
                directory == unspecifiedProjectDirectory
                    ? t.drawer('unnamedProject')
                    : directory,
              ],
            ),
            style: const TextStyle(fontSize: 10, color: muted),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (projectPreferences.followed.contains(key))
                const Icon(Icons.star_rounded, color: amber, size: 18),
              PopupMenuButton<String>(
                key: ValueKey('project-menu-$key'),
                tooltip: t.drawer("projectActions"),
                onSelected: (value) {
                  if (value == 'create') {
                    sessionControlDialog(context, s, instance, 'create');
                  } else {
                    projectAction(key, value);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'follow',
                    child: Text(
                      projectPreferences.followed.contains(key)
                          ? t.drawer("unfollow")
                          : t.drawer("follow"),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'hide',
                    child: Text(
                      projectPreferences.hidden.contains(key)
                          ? t.drawer("restore")
                          : t.drawer("hide"),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'create',
                    enabled: s.canControlSession('${instance['id']}'),
                    child: Text(t.drawer("newSession")),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!collapsed) ...[
          for (final task in visible) ...taskTree(task, tasks),
          if (tasks.isEmpty)
            Padding(
              padding: EdgeInsets.all(12),
              child: Text(t.mobile("waitSessionEvents")),
            ),
          if (roots.length > visible.length || allProjectSessions.contains(key))
            TextButton(
              key: ValueKey('project-history-$key'),
              onPressed: () => setState(() {
                if (!allProjectSessions.remove(key)) {
                  allProjectSessions.add(key);
                }
              }),
              child: Text(
                allProjectSessions.contains(key)
                    ? t.mobile("collapseHistory")
                    : t.mobile("viewAllSessions", values: [roots.length]),
              ),
            ),
        ],
      ],
    );
  }

  List<Widget> logs() => [
    Text(
      t.mobile("logsTitle"),
      style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 8),
    Text(
      t.mobile("recentEvents"),
      style: TextStyle(color: muted, fontSize: 12),
    ),
    const SizedBox(height: 20),
    TextField(
      onChanged: (v) => setState(() => query = v),
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: t.mobile("searchEvents"),
      ),
    ),
    const SizedBox(height: 18),
    Panel(
      child: Column(
        children: [
          for (final log
              in s
                  .rows('logs')
                  .reversed
                  .where(
                    (e) => '${e['text']}'.toLowerCase().contains(
                      query.toLowerCase(),
                    ),
                  ))
            GestureDetector(
              key: ValueKey('log-${log['id']}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => openLogSession(log),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Dot(
                        log['level'] == 'warn'
                            ? amber
                            : log['level'] == 'error'
                            ? red
                            : green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${deviceName(log['instanceId'])} · ${sessionName(log)} · ${clock(log['at'])}',
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                          const SizedBox(height: 7),
                          SelectableText(
                            s.demo && log['demoTextKey'] is String
                                ? t.conversation(log['demoTextKey'] as String)
                                : '${log['text']}',
                            style: const TextStyle(fontSize: 12, height: 1.7),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!s
              .rows('logs')
              .any(
                (e) =>
                    '${e['text']}'.toLowerCase().contains(query.toLowerCase()),
              ))
            Padding(
              padding: EdgeInsets.all(20),
              child: Text(t.mobile("noEvents"), style: TextStyle(color: muted)),
            ),
        ],
      ),
    ),
  ];
  String sessionName(Json log) {
    final id = log['sessionID'];
    if (id == null) return t.mobile("deviceEvent");
    return s
            .rows('sessions')
            .where(
              (task) =>
                  task['instanceId'] == log['instanceId'] && task['id'] == id,
            )
            .map((task) => t.demoValue(task['title'] ?? id, demo: s.demo))
            .firstOrNull ??
        t.mobile(
          "sessionId",
          values: [
            id.toString().length > 8 ? id.toString().substring(0, 8) : id,
          ],
        );
  }

  void openLogSession(Json log) {
    final session = s
        .rows('sessions')
        .where(
          (task) =>
              task['instanceId'] == log['instanceId'] &&
              task['id'] == log['sessionID'],
        )
        .firstOrNull;
    if (session == null) {
      message(t.mobile("sessionGone"));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskPage(
          store: s,
          task: session,
          hostname: deviceName(session['instanceId']),
        ),
      ),
    );
  }

  String settingsText(SettingsText key, {String? name}) =>
      AppLocale.of(context).setting(key, name: name);

  Future<void> openSupportPage(String page) =>
      openExternalLink(context, websiteUri(t.language, page));

  List<Widget> settings() => [
    Text(
      AppLocale.of(context).connectionSettings,
      style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 8),
    Text(
      AppLocale.of(context).settingsCopy,
      style: const TextStyle(fontSize: 12, color: muted),
    ),
    const SizedBox(height: 24),
    Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(settingsText(SettingsText.privacyAndSupport)),
          Material(
            color: Colors.transparent,
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey('settings-privacy'),
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(settingsText(SettingsText.privacyPolicy)),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => openSupportPage('privacy.html'),
                ),
                ListTile(
                  key: const ValueKey('settings-support'),
                  leading: const Icon(Icons.help_outline),
                  title: Text(settingsText(SettingsText.helpAndSupport)),
                  subtitle: Text(settingsText(SettingsText.connectionGuide)),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => openSupportPage('connector.html'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(AppLocale.of(context).languageLabel),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: ListTile(
              key: const ValueKey('settings-language'),
              title: Text(AppLocale.of(context).language.nativeName),
              leading: const Icon(Icons.language),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLanguagePicker(context),
            ),
          ),
        ],
      ),
    ),
    Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            settingsText(SettingsText.deviceManagement),
            trailing:
                '${s.rows('devices').where((d) => d['bound'] != false).length}${settingsText(SettingsText.pairedCountSuffix)}',
          ),
          const SizedBox(height: 10),
          Text(
            settingsText(SettingsText.localManagementGuide),
            style: const TextStyle(fontSize: 12, color: muted, height: 1.6),
          ),
          const SizedBox(height: 8),
          const SelectableText('http://127.0.0.1:17654/'),
          const SizedBox(height: 8),
          Text(
            settingsText(SettingsText.unpairingGuide),
            style: const TextStyle(fontSize: 11, color: muted, height: 1.6),
          ),
          const SizedBox(height: 12),
          if (s.rows('devices').isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                settingsText(SettingsText.noPairedMonitor),
                style: TextStyle(color: muted),
              ),
            ),
          for (final device in s.rows('devices'))
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  device['online'] == true
                      ? Icons.computer
                      : Icons.computer_outlined,
                  color: device['online'] == true ? wechatBlue : muted,
                ),
                title: Text('${device['name'] ?? device['id']}'),
                subtitle: Text(
                  '${device['bound'] == false
                      ? settingsText(SettingsText.unpaired)
                      : device['online'] == true
                      ? settingsText(SettingsText.online)
                      : settingsText(SettingsText.offline)}${deviceObservation(device, AppLocale.of(context)).isEmpty ? '' : '\n${deviceObservation(device, AppLocale.of(context))}'}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => value == 'rename'
                      ? renameBoundDevice(device)
                      : removeBoundDevice(device),
                  itemBuilder: (_) => [
                    if (device['bound'] != false)
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(settingsText(SettingsText.rename)),
                      ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(
                        device['bound'] == false
                            ? settingsText(SettingsText.removeRecord)
                            : settingsText(SettingsText.unpair),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('settings-add-device'),
              onPressed: s.demo ? null : addDevice,
              icon: const Icon(Icons.add_link_rounded),
              label: Text(settingsText(SettingsText.addDevice)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            settingsText(SettingsText.addDeviceGuide),
            style: TextStyle(fontSize: 11, color: muted, height: 1.6),
          ),
        ],
      ),
    ),
    Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            settingsText(SettingsText.workspace),
            trailing: s.connected
                ? settingsText(SettingsText.connected)
                : settingsText(SettingsText.disconnected),
          ),
          const SizedBox(height: 16),
          SelectableText(
            s.endpoint.isEmpty
                ? settingsText(SettingsText.noServer)
                : s.endpoint,
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 16),
          MetaRow(
            settingsText(SettingsText.syncPolicy),
            settingsText(SettingsText.foregroundSync),
          ),
          MetaRow(
            settingsText(SettingsText.deviceConnection),
            settingsText(SettingsText.connectionFlow),
          ),
          MetaRow(
            settingsText(SettingsText.credentialProtection),
            'Keystore / Keychain',
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('settings-switch-server'),
              onPressed: s.connecting || s.action.isNotEmpty
                  ? null
                  : () async {
                      final endpoint = await showDialog<String>(
                        context: context,
                        builder: (_) => RelayServerDialog(store: s),
                      );
                      if (endpoint == null || !mounted) return;
                      try {
                        await s.switchServer(endpoint);
                        message(
                          s.connected
                              ? settingsText(SettingsText.relayConnected)
                              : settingsText(
                                  SettingsText.relayConnectionFailed,
                                ),
                        );
                      } catch (e) {
                        message(t.errorText(e));
                      }
                    },
              icon: const Icon(Icons.dns_outlined),
              label: Text(settingsText(SettingsText.switchRelayServer)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            settingsText(SettingsText.relayGuide),
            style: TextStyle(fontSize: 11, color: muted, height: 1.6),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: s.connected || s.connecting ? null : reconnect,
              child: Text(
                s.connecting
                    ? settingsText(SettingsText.connecting)
                    : s.connected
                    ? settingsText(SettingsText.automaticallyConnected)
                    : settingsText(SettingsText.reconnect),
              ),
            ),
          ),
          if (s.paired)
            Center(
              child: TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text(
                        settingsText(SettingsText.disconnectWorkspaceTitle),
                      ),
                      content: Text(
                        settingsText(
                          SettingsText.disconnectWorkspaceExplanation,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text(settingsText(SettingsText.cancel)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(settingsText(SettingsText.disconnect)),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    try {
                      await s.disconnect();
                    } catch (e) {
                      message(t.errorText(e));
                    }
                  }
                },
                child: Text(settingsText(SettingsText.disconnectWorkspace)),
              ),
            ),
        ],
      ),
    ),
    Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            settingsText(SettingsText.explore),
            trailing: '0.2.0 · Flutter',
          ),
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                settingsText(SettingsText.demoWorkspace),
                style: TextStyle(fontSize: 14),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                s.enterDemo();
                setState(() => tab = 0);
              },
            ),
          ),
          MetaRow(
            settingsText(SettingsText.notifications),
            settingsText(SettingsText.pushUnavailable),
          ),
          const SizedBox(height: 8),
          Text(
            settingsText(SettingsText.authorizationGuide),
            style: TextStyle(fontSize: 11, color: muted, height: 1.8),
          ),
        ],
      ),
    ),
  ];
}

class RelayServerDialog extends StatefulWidget {
  const RelayServerDialog({super.key, required this.store});
  final TowerStore store;

  @override
  State<RelayServerDialog> createState() => _RelayServerDialogState();
}

class _RelayServerDialogState extends State<RelayServerDialog> {
  String settingsText(SettingsText key, {String? name}) =>
      AppLocale.of(context).setting(key, name: name);

  late final address = TextEditingController(text: widget.store.endpoint);
  String? error;

  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(settingsText(SettingsText.switchRelayServer)),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(settingsText(SettingsText.serverSwitchGuide)),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('relay-server-address'),
              controller: address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: settingsText(SettingsText.httpsServerAddress),
                hintText: 'https://tower.example.com',
                errorText: error,
              ),
              onChanged: (_) => setState(() => error = null),
            ),
            const SizedBox(height: 12),
            for (final endpoint in {
              TowerStore.bundledEndpoint,
              ...widget.store.savedEndpoints,
            })
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(endpoint, style: const TextStyle(fontSize: 12)),
                trailing: endpoint == widget.store.endpoint
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () => setState(() {
                  address.text = endpoint;
                  error = null;
                }),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(settingsText(SettingsText.cancel)),
      ),
      FilledButton(
        key: const ValueKey('relay-server-confirm'),
        onPressed: () {
          try {
            final endpoint = TowerStore.validateEndpoint(address.text);
            Navigator.pop(context, endpoint.toString());
          } catch (e) {
            setState(
              () => error = settingsText(SettingsText.invalidServerAddress),
            );
          }
        },
        child: Text(settingsText(SettingsText.saveAndConnect)),
      ),
    ],
  );
}

class DeviceBindSheet extends StatefulWidget {
  const DeviceBindSheet({super.key, required this.store});
  final TowerStore store;
  @override
  State<DeviceBindSheet> createState() => _DeviceBindSheetState();
}

class _DeviceBindSheetState extends State<DeviceBindSheet> {
  AppStrings get t => AppLocale.of(context);
  final code = TextEditingController();
  String error = '';
  String scannedHint = '';
  bool busy = false;

  Future<void> scanCode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const DeviceQrScannerPage()),
    );
    if (result == null || !mounted) return;
    code.text = result;
    setState(() {
      error = '';
      scannedHint = t.mobile("recognizedCode", values: [result]);
    });
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      22,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.setting(SettingsText.addDevice),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          t.mobile("monitorScanGuide"),
          style: TextStyle(fontSize: 12, color: muted, height: 1.8),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('scan-device-qr'),
            onPressed: busy ? null : scanCode,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(t.mobile("scanQr")),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: code,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          maxLength: 8,
          decoration: InputDecoration(labelText: t.mobile("bindingCodeLabel")),
        ),
        if (error.isNotEmpty)
          Text(
            t.errorText(error),
            style: const TextStyle(color: red, fontSize: 12),
          ),
        if (scannedHint.isNotEmpty)
          Text(
            scannedHint,
            style: const TextStyle(color: green, fontSize: 12, height: 1.5),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = '';
                    });
                    try {
                      await widget.store.confirmDeviceBinding(code.text);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          busy = false;
                          error = '$e';
                        });
                      }
                    }
                  },
            child: Text(
              busy ? t.mobile("bindingBusy") : t.mobile("confirmAdd"),
            ),
          ),
        ),
      ],
    ),
  );
}

class DeviceQrScannerPage extends StatefulWidget {
  const DeviceQrScannerPage({super.key});
  @override
  State<DeviceQrScannerPage> createState() => _DeviceQrScannerPageState();
}

class _DeviceQrScannerPageState extends State<DeviceQrScannerPage> {
  AppStrings get t => AppLocale.of(context);
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool handled = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void detected(BarcodeCapture capture) {
    if (handled) return;
    for (final barcode in capture.barcodes) {
      final code = bindingCodeFromQr(barcode.rawValue ?? '');
      if (code == null) continue;
      handled = true;
      controller.stop();
      Navigator.pop(context, code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(t.mobile("scanDeviceQr")),
      actions: [
        IconButton(
          tooltip: t.mobile("flashlight"),
          onPressed: controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_rounded),
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: controller, onDetect: detected),
        Center(
          child: Container(
            width: 248,
            height: 248,
            decoration: BoxDecoration(
              border: Border.all(color: green, width: 3),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            minimum: EdgeInsets.all(28),
            child: Text(
              t.mobile("monitorQrFrame"),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, height: 1.6),
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> sessionControlDialog(
  BuildContext context,
  TowerStore store,
  Json target,
  String operation,
) async {
  final t = AppLocale.of(context);
  final text = TextEditingController();
  final model = TextEditingController();
  final projects = store
      .rows('instances')
      .where(
        (item) =>
            item['directory'] != null && !'${item['id']}'.startsWith('hook:'),
      )
      .expand(
        (item) =>
            <String>{
              '${item['directory']}',
              ...((item['projects'] as List?) ?? []).whereType<String>(),
            }.map(
              (directory) => <String, dynamic>{...item, 'directory': directory},
            ),
      )
      .toList();
  if (!projects.any(
    (item) =>
        item['id'] == target['id'] && item['directory'] == target['directory'],
  )) {
    projects.insert(0, target);
  }
  var selectedProject = projects.indexWhere(
    (item) =>
        item['id'] == target['id'] && item['directory'] == target['directory'],
  );
  if (selectedProject < 0) selectedProject = 0;
  final projectDirectory = TextEditingController(
    text: '${projects[selectedProject]['directory'] ?? ''}',
  );
  var directoryError = '';
  var contentError = '';
  final label = operation == 'create'
      ? t.drawer("newSession")
      : operation == 'abort'
      ? t.mobile("abortSession")
      : t.mobile("continueConversation");
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(label),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (operation == 'create')
                DropdownButtonFormField<int>(
                  initialValue: selectedProject,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t.mobile("chooseProject"),
                  ),
                  items: [
                    for (var i = 0; i < projects.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          '${projects[i]['directory'] ?? ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    DropdownMenuItem(
                      value: -1,
                      child: Text(t.mobile("newProject")),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedProject = value;
                        directoryError = '';
                      });
                      projectDirectory.text = value < 0
                          ? ''
                          : '${projects[value]['directory'] ?? ''}';
                    }
                  },
                )
              else
                Text('${target['title'] ?? ''}'),
              if (operation == 'abort')
                Text(t.conversation("abortExplanation")),
              if (operation == 'create' && selectedProject < 0)
                TextField(
                  controller: projectDirectory,
                  maxLength: 4096,
                  decoration: InputDecoration(
                    labelText: t.mobile("projectFolder"),
                    helperText: t.mobile("folderGuide"),
                  ),
                ),
              if (operation == 'create' && selectedProject >= 0)
                Text(
                  t.mobile(
                    "projectDirectoryValue",
                    values: [projects[selectedProject]['directory'] ?? ''],
                  ),
                ),
              if (directoryError.isNotEmpty)
                Text(directoryError, style: const TextStyle(color: Colors.red)),
              if (operation == 'create')
                TextField(
                  controller: model,
                  maxLength: 300,
                  decoration: InputDecoration(
                    labelText: t.mobile("optionalModel"),
                    hintText: 'provider/model',
                    helperText: t.mobile("modelGuide"),
                  ),
                ),
              if (operation != 'abort')
                TextField(
                  controller: text,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 4000,
                  decoration: InputDecoration(
                    labelText: operation == 'create'
                        ? t.mobile("content")
                        : t.mobile("newMessage"),
                    errorText: contentError.isEmpty ? null : contentError,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.setting(SettingsText.cancel)),
          ),
          FilledButton(
            onPressed: () {
              if (operation == 'create' &&
                  selectedProject < 0 &&
                  projectDirectory.text.trim().isEmpty) {
                setDialogState(
                  () => directoryError = t.mobile("folderRequired"),
                );
                return;
              }
              if (operation == 'create' && text.text.trim().isEmpty) {
                setDialogState(
                  () => contentError = t.mobile("contentRequired"),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: Text(label),
          ),
        ],
      ),
    ),
  );
  final message = text.text;
  final sessionModel = model.text;
  final selectedDirectory = projectDirectory.text;
  // Dialog route finishes its exit animation before controllers are disposed.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  text.dispose();
  model.dispose();
  projectDirectory.dispose();
  if (accepted != true || !context.mounted) return;
  try {
    await store.controlSession(
      operation == 'create' && selectedProject >= 0
          ? projects[selectedProject]
          : target,
      operation,
      text: message,
      model: sessionModel,
      directory: selectedDirectory,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.mobile("agentConfirmed", values: [label]))),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.errorText(error))));
    }
  }
}

class TaskPage extends StatefulWidget {
  const TaskPage({
    super.key,
    required this.store,
    required this.task,
    required this.hostname,
    this.onNavigate,
  });
  final TowerStore store;
  final Json task;
  final String hostname;
  final ValueChanged<String>? onNavigate;
  @override
  State<TaskPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<TaskPage> {
  @override
  Widget build(BuildContext context) => ConversationView(
    store: widget.store,
    session: widget.task,
    hostname: widget.hostname,
    onNavigate: (label) {
      widget.onNavigate?.call(label);
      Navigator.of(context).popUntil((route) => route.isFirst);
    },
  );
}

class LegacyTaskPageState extends State<TaskPage> {
  AppStrings get t => AppLocale.of(context);
  final prompt = TextEditingController();
  bool sending = false;
  String lastSent = '';
  TowerStore get store => widget.store;
  Json get task => widget.task;
  String get hostname => widget.hostname;
  @override
  void dispose() {
    prompt.dispose();
    super.dispose();
  }

  Future<void> sendPrompt(Json current) async {
    final value = prompt.text.trim();
    if (value.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await store.controlSession(current, 'prompt', text: value);
      if (!mounted) return;
      setState(() {
        lastSent = value;
        prompt.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.mobile("messageContinued"))));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.errorText(error))));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final live = store
          .rows('sessions')
          .where((t) => t['id'] == task['id'])
          .firstOrNull;
      final current = live ?? task;
      final gone = live == null;
      final instanceLive = store
          .rows('instances')
          .any((d) => d['id'] == '${current['instanceId']}' && store.online(d));
      final statusText = gone
          ? (instanceLive ? t.conversation("ended") : t.conversation("offline"))
          : t.sessionStatus(current['status']);
      final logs = store
          .rows('logs')
          .where(
            (l) =>
                l['instanceId'] == current['instanceId'] &&
                l['sessionID'] == task['id'],
          )
          .toList()
          .reversed
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(
            t.mobile("taskDetails", values: [task['id']]),
            style: const TextStyle(fontSize: 17),
          ),
          actions: [
            BadgeText(statusText, gone ? muted : green),
            const SizedBox(width: 16),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.demoValue(current['title'], demo: store.demo),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Divider(height: 28),
                      MetaRow(
                        t.mobile("runningDevice"),
                        t.demoValue(hostname, demo: store.demo),
                      ),
                      MetaRow(
                        t.mobile("executingAgent"),
                        '${current['agent'] ?? 'OpenCode'}',
                      ),
                      MetaRow(
                        t.mobile("parentSession"),
                        '${current['parentID'] ?? t.mobile("rootSession")}',
                      ),
                    ],
                  ),
                ),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.mobile("continueSession"),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('session-prompt-input'),
                        controller: prompt,
                        minLines: 2,
                        maxLines: 6,
                        maxLength: 4000,
                        enabled: !sending,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: t.mobile("messageHint"),
                        ),
                      ),
                      if (lastSent.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            t.mobile("justSent", values: [lastSent]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey('session-prompt-send'),
                          onPressed:
                              !sending &&
                                  prompt.text.trim().isNotEmpty &&
                                  store.canControlSession(
                                    '${current['instanceId']}',
                                  ) &&
                                  ![
                                    'busy',
                                    'retry',
                                    'thinking',
                                  ].contains(current['status'])
                              ? () => sendPrompt(current)
                              : null,
                          icon: sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                          label: Text(
                            sending
                                ? t.conversation("sending")
                                : t.mobile("sendContinue"),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xff1c232a),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const Dot(red),
                            const SizedBox(width: 5),
                            const Dot(amber),
                            const SizedBox(width: 5),
                            const Dot(green),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                t.mobile("agentEventStream"),
                                style: TextStyle(fontSize: 10, color: muted),
                              ),
                            ),
                            IconButton(
                              tooltip: t.mobile("copyLogs"),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(
                                    text: logs
                                        .map(
                                          (l) =>
                                              '${clock(l['at'])} ${l['text']}',
                                        )
                                        .join('\n'),
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(t.mobile("logsCopied")),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.copy_rounded,
                                size: 16,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 360,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 5, 14, 20),
                          itemCount: logs.isEmpty ? 1 : logs.length,
                          itemBuilder: (_, i) => logs.isEmpty
                              ? Text(
                                  t.mobile("waitTaskEvents"),
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                    height: 1.8,
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        clock(logs[i]['at']),
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                          color: muted,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: SelectableText(
                                          '${logs[i]['text']}',
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            height: 1.8,
                                            color: logs[i]['level'] == 'warn'
                                                ? amber
                                                : logs[i]['level'] == 'success'
                                                ? green
                                                : const Color(0xffc7d2d9),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0xff344048)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              t.mobile("eventCount", values: [logs.length]),
                              style: const TextStyle(fontSize: 9, color: muted),
                            ),
                            const Spacer(),
                            Text(
                              t.mobile("readOnly"),
                              style: TextStyle(fontSize: 9, color: green),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            store.canControlSession(
                                  '${current['instanceId']}',
                                ) &&
                                [
                                  'busy',
                                  'retry',
                                  'thinking',
                                ].contains(current['status'])
                            ? () => sessionControlDialog(
                                context,
                                store,
                                current,
                                'abort',
                              )
                            : null,
                        child: Text(
                          t.mobile("abortSession"),
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    t.mobile("controlGuide"),
                    style: TextStyle(color: muted, fontSize: 11, height: 1.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String patterns(Json p, [AppStrings t = const AppStrings(AppLanguage.zh)]) =>
    (p['patterns'] as List?)?.join('\n') ??
    '${p['metadata'] ?? p['permission'] ?? t.mobile("reviewOperation")}';
String clock(dynamic value) {
  final t = DateTime.fromMillisecondsSinceEpoch((value as num?)?.toInt() ?? 0);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderTop,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? borderTop;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xffdce5f0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0520324d),
          blurRadius: 5,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (borderTop != null) Container(height: 4, color: borderTop),
        Padding(padding: padding, child: child),
      ],
    ),
  );
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 7});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class BadgeText extends StatelessWidget {
  const BadgeText(this.text, this.color, {super.key});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withAlpha(20),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
    ),
  );
}

class Metric extends StatelessWidget {
  const Metric(this.title, this.value, this.unit, this.color, {super.key});
  final String title, value, unit;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 5),
    decoration: BoxDecoration(
      color: color.withAlpha(12),
      border: Border.all(color: color.withAlpha(35)),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Column(
      children: [
        Text('● $title', style: TextStyle(color: color, fontSize: 10)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: color == red ? red : ink,
              ),
            ),
            const SizedBox(width: 4),
            Text(unit, style: const TextStyle(fontSize: 9, color: muted)),
          ],
        ),
      ],
    ),
  );
}

class AgentIcon extends StatelessWidget {
  const AgentIcon({super.key, this.blue = false});
  final bool blue;
  @override
  Widget build(BuildContext context) => Container(
    width: 35,
    height: 35,
    decoration: BoxDecoration(
      color: (blue ? Colors.blue : amber).withAlpha(15),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: (blue ? Colors.blue : amber).withAlpha(60)),
    ),
    child: Icon(
      blue ? Icons.terminal : Icons.view_in_ar_outlined,
      color: blue ? Colors.blue : amber,
      size: 21,
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing = ''});
  final String title, trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      Text(trailing, style: const TextStyle(color: muted, fontSize: 10)),
    ],
  );
}

class MetaRow extends StatelessWidget {
  const MetaRow(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}
