import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'app_localizations.dart';
import 'settings_catalog.dart';
import 'connection_store.dart';
import 'project_preferences.dart';
import 'setup_agent_icon.dart';
import 'app_brand_icon.dart';

const wechatBlue = Color(0xff2477ed);
const wechatBackground = Color(0xfff5f8fc);
const wechatText = Color(0xff20324d);
const wechatMuted = Color(0xff788aa5);

class WechatUiHome extends StatefulWidget {
  const WechatUiHome({
    super.key,
    required this.store,
    required this.onDemo,
    this.onSession,
    this.onCreateSession,
    this.sidebarOnly = false,
    this.onClose,
    this.onNavigate,
    this.onBack,
  });

  final TowerStore store;
  final VoidCallback onDemo;
  final ValueChanged<Json>? onSession;
  final ValueChanged<Json>? onCreateSession;
  final bool sidebarOnly;
  final VoidCallback? onClose;
  final ValueChanged<String>? onNavigate;
  final VoidCallback? onBack;

  @override
  State<WechatUiHome> createState() => _WechatUiHomeState();
}

class _WechatUiHomeState extends State<WechatUiHome> {
  int platform = 0;
  String selectedTool = 'opencode';
  Json? get selectedAgent =>
      widget.store.setupAgents
          .where((agent) => agent['id'] == selectedTool)
          .firstOrNull ??
      widget.store.setupAgents.firstOrNull;
  String copiedTool = '';
  bool setupBusy = false;
  bool drawerOpen = false;
  String drawerQuery = '';
  final Set<String> expandedDrawerProjects = <String>{};
  final preferences = ProjectPreferences();
  String projectFilter = 'all', selectedNode = '';
  final Set<String> allSessions = <String>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(widget.store.refreshProjectLinks);
    if (!widget.sidebarOnly) {
      Future.microtask(widget.store.refreshMobileAnnouncements);
    }
    if (!widget.sidebarOnly) Future.microtask(widget.store.refreshSetupAgents);
    preferences
        .load()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object _) {});
  }

  String nodeId(Json instance) =>
      '${instance['deviceId'] ?? instance['hostname'] ?? instance['id']}';
  Map<String, String> get nodes {
    final instances = widget.store.rows('instances').toList()
      ..sort((a, b) => nodeId(a).compareTo(nodeId(b)));
    return {
      for (final instance in instances)
        nodeId(instance): '${instance['hostname'] ?? nodeId(instance)}',
    };
  }

  String get activeNode => nodes.containsKey(selectedNode)
      ? selectedNode
      : nodes.keys.firstOrNull ?? '';

  AppStrings get t => AppLocale.of(context);

  @override
  Widget build(BuildContext context) {
    if (widget.sidebarOnly) {
      return AnimatedBuilder(
        animation: widget.store,
        builder: (_, _) => _drawerPanel(),
      );
    }
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) => Stack(
        children: [
          Scaffold(
            backgroundColor: wechatBackground,
            body: SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _topBar()),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (widget.store.mobileAnnouncements.isNotEmpty)
                          _announcement(),
                        if (widget.onBack != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: widget.onBack,
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: Text(t.helpText('backHome')),
                            ),
                          ),
                        const SizedBox(height: 24),
                        Text(
                          t.connectComputer,
                          style: const TextStyle(
                            color: wechatMuted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          t.heroTitle,
                          style: TextStyle(
                            color: wechatText,
                            fontSize: 28,
                            height: 1.28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          t.heroCopy,
                          style: const TextStyle(
                            color: wechatMuted,
                            fontSize: 14,
                            height: 1.65,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _platformTabs(),
                        _setupCard(),
                        if (widget.onBack == null) ...[
                          const SizedBox(height: 14),
                          _demoButton(),
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (drawerOpen) _drawer(),
        ],
      ),
    );
  }

  Widget _topBar() => Container(
    height: 68,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        _roundIcon(
          Icons.menu_rounded,
          t.menu,
          () => setState(() => drawerOpen = true),
        ),
        const SizedBox(width: 9),
        const AppBrandIcon(),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            t.appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: wechatText,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        const LanguageButton(),
      ],
    ),
  );

  Widget _roundIcon(IconData icon, String tooltip, VoidCallback onTap) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, color: wechatText),
            ),
          ),
        ),
      );

  Widget _announcement() => InkWell(
    onTap: () => widget.onNavigate?.call(t.developerNews),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xffedf4ff),
        border: Border.all(color: const Color(0xffc9dcff)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: wechatBlue,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              t.announcement,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${t.localizedContent(widget.store.mobileAnnouncements.first)['title']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xff315b9d),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            t.viewAll,
            style: const TextStyle(color: wechatBlue, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _platformTabs() {
    final labels = [t.windows, t.linux, t.macos];
    final icons = [Icons.window_rounded, Icons.computer_rounded, Icons.apple];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: InkWell(
              onTap: () => setState(() {
                platform = i;
                copiedTool = '';
              }),
              child: Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: platform == i ? wechatBlue : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icons[i],
                      size: 16,
                      color: platform == i ? wechatBlue : wechatText,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      labels[i],
                      style: TextStyle(
                        color: platform == i ? wechatBlue : wechatText,
                        fontSize: 12,
                        fontWeight: platform == i
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _setupCard() {
    final tools = widget.store.setupAgents;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffdce5f0)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(7),
          bottomRight: Radius.circular(7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.chooseTool,
            style: TextStyle(
              color: wechatText,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 9),
          if (widget.store.setupAgentsLoading && tools.isEmpty)
            Text(t.helpText("agentsLoading")),
          if (widget.store.setupAgentsError.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${t.helpText("agentsLoadError")}: ${t.errorText(widget.store.setupAgentsError)}",
                  ),
                ),
                TextButton(
                  onPressed: widget.store.refreshSetupAgents,
                  child: Text(t.retry),
                ),
              ],
            ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tools.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 51,
              crossAxisSpacing: 7,
              mainAxisSpacing: 7,
            ),
            itemBuilder: (_, index) => _toolTile(tools[index], index),
          ),
          const SizedBox(height: 15),
          Text(
            t.copyCommand,
            style: TextStyle(
              color: wechatText,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 9),
          Center(
            child: FilledButton(
              onPressed: setupBusy || selectedAgent == null
                  ? null
                  : _copyCommand,
              style: FilledButton.styleFrom(
                backgroundColor: wechatBlue,
                minimumSize: const Size(172, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: Text(
                t.copyInstallCommand,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (copiedTool.isNotEmpty)
            Container(
              key: const ValueKey('setup-copy-success'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xffeaf4ff),
                border: Border.all(color: const Color(0xffc9defa)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.mobile("copySuccess"),
                    style: TextStyle(
                      color: Color(0xff155ac2),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.mobile("pasteCommandGuide", values: [copiedTool]),
                    style: const TextStyle(
                      color: Color(0xff344965),
                      fontSize: 12,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              t.copyHint,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: wechatMuted,
                fontSize: 11,
                height: 1.55,
              ),
            ),
          const SizedBox(height: 14),
          Center(
            child: InkWell(
              onTap: _showBindingSheet,
              child: Text(
                t.alreadyConnected,
                style: const TextStyle(
                  color: wechatMuted,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolTile(Json agent, int index) {
    final name = agent['name'] as String;
    final selected = selectedAgent?['id'] == agent['id'];
    return InkWell(
      onTap: () => setState(() {
        selectedTool = agent['id'] as String;
        copiedTool = '';
      }),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xfff2f7ff) : Colors.white,
          border: Border.all(
            color: selected ? wechatBlue : const Color(0xffdbe5f3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(
                color: index.isEven
                    ? const Color(0xffe4f1e9)
                    : const Color(0xffeef0f5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SetupAgentIcon(agent: agent),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: selected ? wechatBlue : const Color(0xff50627c),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_outline_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? wechatBlue : const Color(0xff70a3ec),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _demoButton() => Center(
    child: OutlinedButton(
      onPressed: widget.onDemo,
      style: OutlinedButton.styleFrom(
        foregroundColor: wechatBlue,
        side: const BorderSide(color: Color(0xffa9ccff)),
        minimumSize: const Size(172, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: Text(t.demo, style: TextStyle(fontWeight: FontWeight.w700)),
    ),
  );

  Future<void> _copyCommand() async {
    final selected = selectedAgent;
    if (setupBusy || selected == null) return;
    final agent = selected['id'] as String;
    final name = selected['name'] as String;
    setState(() {
      setupBusy = true;
      copiedTool = '';
    });
    try {
      final ticket = await widget.store.issueSetupTicket();
      if (!widget.store.setupAgents.any((item) => item['id'] == agent)) {
        throw ApiError.localized('agentListChanged');
      }
      final endpoint = widget.store.endpoint;
      final command = platform == 0
          ? r"$s=Join-Path $env:TEMP 'agenttower-install.ps1'; "
                "iwr '$endpoint/install-monitor.ps1' -OutFile \$s; "
                "& \$s -Agent $agent -Server '$endpoint' -SetupTicket '$ticket'"
          : "curl -fsSL '$endpoint/install-monitor.sh' -o /tmp/agenttower-install.sh && "
                "sh /tmp/agenttower-install.sh --agent $agent --server '$endpoint' --setup-ticket '$ticket'";
      await Clipboard.setData(
        ClipboardData(text: t.mobile("installPrompt", values: [command])),
      );
      if (mounted) setState(() => copiedTool = name);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t.mobile("installFailed", values: [t.errorText(error)]),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => setupBusy = false);
    }
  }

  Future<void> _showBindingSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    barrierColor: Colors.black45,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _WechatBindingSheet(store: widget.store),
  );

  Widget _drawer() => GestureDetector(
    onTap: () => setState(() => drawerOpen = false),
    child: Container(
      color: Colors.black38,
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(onTap: () {}, child: _drawerPanel()),
      ),
    ),
  );

  Widget _drawerPanel() => Material(
    color: const Color(0xfff7fbff),
    borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: _drawerWidth(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  const AppBrandIcon(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.appName,
                          style: TextStyle(
                            color: wechatText,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          widget.store.demo
                              ? t.setting(SettingsText.demoWorkspace)
                              : widget.store.connected
                              ? t.connected
                              : t.setting(SettingsText.disconnected),
                          style: const TextStyle(
                            color: wechatMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _closeDrawer,
                    icon: const Icon(Icons.close_rounded, color: wechatMuted),
                  ),
                ],
              ),
            ),
            _drawerNode(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                onChanged: (value) => setState(() => drawerQuery = value),
                decoration: InputDecoration(
                  hintText: t.searchHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  filled: true,
                  fillColor: const Color(0xffeaf1fa),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${t.projects} · ${_drawerProjects().length}',
                    style: const TextStyle(color: wechatMuted, fontSize: 13),
                  ),
                  const Spacer(),
                  InkWell(
                    key: const ValueKey('drawer-project-filter'),
                    onTap: _showProjectFilters,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffeaf4ff),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${t.drawer(projectFilter)} ▾',
                        style: const TextStyle(
                          color: Color(0xff155ac2),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _drawerProjectList()),
            _drawerLinks(),
          ],
        ),
      ),
    ),
  );

  void _closeDrawer() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      setState(() => drawerOpen = false);
    }
  }

  double _drawerWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return (width * .82).clamp(0.0, 325.0).toDouble();
  }

  Widget _drawerNode() => InkWell(
    onTap: nodes.length > 1
        ? () async {
            final value = await showModalBottomSheet<String>(
              context: context,
              builder: (context) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final node in nodes.entries)
                      ListTile(
                        title: Text(
                          t.demoValue(node.value, demo: widget.store.demo),
                        ),
                        onTap: () => Navigator.pop(context, node.key),
                      ),
                  ],
                ),
              ),
            );
            if (value != null && mounted) setState(() => selectedNode = value);
          }
        : null,
    child: Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xffeaf2fc),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          const Icon(Icons.dns_outlined, size: 17, color: wechatBlue),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              t.demoValue(
                nodes[activeNode] ?? t.drawer('noNodes'),
                demo: widget.store.demo,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: wechatText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            nodes.length > 1
                ? '${t.drawer('switchNode')} ▾'
                : t.drawer('singleNode'),
            style: const TextStyle(color: wechatMuted, fontSize: 11),
          ),
        ],
      ),
    ),
  );

  Widget _drawerLinks() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
    child: Column(
      children: [
        _drawerLink(Icons.home_outlined, t.home, true),
        _drawerLink(Icons.article_outlined, t.developerNews, false),
        for (final link in widget.store.projectLinks)
          _drawerLink(
            link['id'] == 'github' ? Icons.code_rounded : Icons.link_rounded,
            '${t.localizedContent(link)['label']}',
            false,
            onTap: () => _openProjectLink('${link['id']}'),
          ),
        _drawerLink(Icons.settings_outlined, t.settings, false),
        _drawerLink(Icons.help_outline_rounded, t.help, false),
      ],
    ),
  );

  Future<void> _openProjectLink(String id) async {
    await widget.store.refreshProjectLinks();
    if (!mounted) return;
    final link = widget.store.projectLinks
        .where((item) => item['id'] == id)
        .firstOrNull;
    final url = '${link?['url'] ?? ''}';
    try {
      if (url.isEmpty) throw StateError('No project link');
      await const MethodChannel(
        'com.agenttower.mobile/project-links',
      ).invokeMethod<void>('openLink', url);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.projectLinkUnavailable)));
    }
  }

  Widget _drawerLink(
    IconData icon,
    String label,
    bool active, {
    VoidCallback? onTap,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 2),
    child: Material(
      color: active ? const Color(0xffeaf2fc) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        onTap: () {
          if (onTap != null) {
            onTap();
            return;
          }
          _closeDrawer();
          widget.onNavigate?.call(label);
        },
        dense: true,
        leading: Icon(icon, size: 18, color: active ? wechatBlue : wechatMuted),
        title: Text(
          label,
          style: TextStyle(
            color: active ? wechatBlue : wechatMuted,
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );

  String _projectName(_DrawerProject project) =>
      project.unnamed ? t.drawer('unnamedProject') : project.name;

  List<_DrawerProject> _drawerProjects() {
    final instances = widget.store.rows('instances');
    final sessions = widget.store.rows('sessions');
    final result = <_DrawerProject>[];
    final grouped = <String, List<Json>>{};
    for (final instance in instances) {
      final id = nodeId(instance);
      if (id != activeNode) continue;
      final instanceSessions = sessions
          .where((session) => session['instanceId'] == instance['id'])
          .toList();
      final directories = {
        '${instance['directory'] ?? unspecifiedProjectDirectory}',
        ...instanceSessions.map(
          (session) =>
              '${session['directory'] ?? instance['directory'] ?? unspecifiedProjectDirectory}',
        ),
      };
      final agent =
          '${instance['agent'] ?? instanceSessions.firstOrNull?['agent'] ?? 'Agent'}';
      for (final directory in directories) {
        final key = '$id\u0000$agent\u0000$directory';
        grouped
            .putIfAbsent(key, () => [])
            .addAll(
              sessions.where(
                (session) =>
                    session['instanceId'] == instance['id'] &&
                    '${session['directory'] ?? directory}' == directory,
              ),
            );
        if (!result.any((project) => project.key == key)) {
          result.add(
            _DrawerProject(
              key: key,
              name:
                  directory
                      .replaceAll('\\', '/')
                      .split('/')
                      .where((part) => part.isNotEmpty)
                      .lastOrNull ??
                  directory,
              unnamed:
                  directory == unspecifiedProjectDirectory &&
                  instance['directory'] == null &&
                  !instanceSessions.any(
                    (session) =>
                        session['directory'] == unspecifiedProjectDirectory,
                  ),
              agent: agent,
              instance: {...instance, 'directory': directory},
              sessions: const [],
            ),
          );
        } else if (widget.store.online(instance)) {
          final project = result.firstWhere((project) => project.key == key);
          project.instance = {...instance, 'directory': directory};
        }
      }
    }
    for (final project in result) {
      project.sessions = grouped[project.key] ?? const [];
      project.sessions.sort(
        (a, b) => (b['updatedAt'] as num? ?? 0).compareTo(
          a['updatedAt'] as num? ?? 0,
        ),
      );
    }
    result.sort((a, b) {
      final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (name != 0) return name;
      final agent = a.agent.compareTo(b.agent);
      return agent != 0 ? agent : a.key.compareTo(b.key);
    });
    if (drawerQuery.trim().isEmpty) {
      return result
          .where(
            (project) => projectFilter == 'hidden'
                ? preferences.hidden.contains(project.key)
                : !preferences.hidden.contains(project.key) &&
                      (projectFilter != 'followed' ||
                          preferences.followed.contains(project.key)) &&
                      (projectFilter != 'active' ||
                          project.sessions.any(
                            (session) => [
                              'busy',
                              'thinking',
                              'retry',
                              'alarm',
                              'error',
                            ].contains(session['status']),
                          )),
          )
          .toList();
    }
    final query = drawerQuery.trim().toLowerCase();
    return result
        .map(
          (project) => project.copyWith(
            sessions:
                '${_projectName(project)} ${project.agent}'
                    .toLowerCase()
                    .contains(query)
                ? project.sessions
                : project.sessions
                      .where(
                        (session) => t
                            .demoValue(
                              session['title'],
                              demo: widget.store.demo,
                            )
                            .toLowerCase()
                            .contains(query),
                      )
                      .toList(),
          ),
        )
        .where(
          (project) =>
              _projectName(project).toLowerCase().contains(query) ||
              project.agent.toLowerCase().contains(query) ||
              project.sessions.isNotEmpty,
        )
        .toList();
  }

  Widget _drawerProjectList() {
    final projects = _drawerProjects();
    if (projects.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Text(
            drawerQuery.isEmpty ? t.noProjects : t.drawer('noMatches'),
            style: const TextStyle(color: wechatMuted, fontSize: 12),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        final expanded =
            drawerQuery.isNotEmpty ||
            expandedDrawerProjects.contains(project.key);
        return Column(
          key: ValueKey(project.key),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xffedf1f7))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: ValueKey('drawer-project-toggle-${project.key}'),
                      onTap: () => setState(() {
                        if (!expandedDrawerProjects.remove(project.key)) {
                          expandedDrawerProjects.add(project.key);
                        }
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 7,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              expanded
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.chevron_right_rounded,
                              size: 17,
                              color: wechatMuted,
                            ),
                            const Icon(
                              Icons.folder_outlined,
                              size: 17,
                              color: wechatMuted,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _projectName(project),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: wechatText,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${project.agent} · ${t.drawer('sessionCount', count: project.sessions.length)}',
                                    style: const TextStyle(
                                      color: wechatMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('drawer-project-menu-${project.key}'),
                    tooltip: t.drawer('projectActions'),
                    onPressed: () => _showProjectActions(project),
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: wechatMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (expanded)
              for (final session in project.sessions.take(
                allSessions.contains(project.key) ? project.sessions.length : 6,
              ))
                InkWell(
                  onTap: () => widget.onSession?.call(session),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(left: 32, right: 6),
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.demoValue(
                            session['title'] ?? t.conversation('untitled'),
                            demo: widget.store.demo,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: wechatText,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          t.sessionStatus(session['status']),
                          style: const TextStyle(
                            color: wechatMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (expanded &&
                project.sessions.length > 6 &&
                !allSessions.contains(project.key))
              InkWell(
                onTap: () => setState(() => allSessions.add(project.key)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(46, 10, 8, 10),
                  child: Text(
                    '${t.drawer('moreSessions', count: project.sessions.length - 6)} ›',
                    style: const TextStyle(
                      color: Color(0xff155ac2),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showProjectFilters() async {
    final filter = await _showDrawerChoices([
      ('all', t.drawer('all')),
      ('active', t.drawer('active')),
      ('followed', t.drawer('followed')),
      ('hidden', t.drawer('hidden')),
    ], selected: projectFilter);
    if (mounted && filter != null) setState(() => projectFilter = filter);
  }

  Future<String?> _showDrawerChoices(
    List<(String, String)> choices, {
    String? selected,
  }) => showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in choices)
              InkWell(
                onTap: () => Navigator.pop(sheetContext, entry.$1),
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    child: Center(
                      child: Text(
                        entry.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: selected == entry.$1
                              ? const Color(0xff155ac2)
                              : wechatText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const Divider(height: 7, thickness: 7, color: Color(0xfff5f5f5)),
            InkWell(
              onTap: () => Navigator.pop(sheetContext),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: Center(
                  child: Text(
                    t.setting(SettingsText.cancel),
                    style: TextStyle(fontSize: 16, color: wechatText),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _showProjectActions(_DrawerProject project) async {
    final action = await _showDrawerChoices([
      (
        'follow',
        preferences.followed.contains(project.key)
            ? t.drawer('unfollow')
            : t.drawer('follow'),
      ),
      (
        'hide',
        preferences.hidden.contains(project.key)
            ? t.drawer('restore')
            : t.drawer('hide'),
      ),
      ('create', t.drawer('newSession')),
    ]);
    if (!mounted || action == null) return;
    if (action == 'create') {
      if (!widget.store.canControlSession('${project.instance['id']}')) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.drawer('controlUnavailable'))));
      } else {
        widget.onCreateSession?.call(project.instance);
      }
      return;
    }
    setState(() {
      final values = action == 'follow'
          ? preferences.followed
          : preferences.hidden;
      if (!values.remove(project.key)) values.add(project.key);
    });
    preferences.save().catchError((Object error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${t.drawer('saveFailed')}: ${t.errorText(error)}'),
          ),
        );
      }
    });
  }
}

class _WechatBindingSheet extends StatefulWidget {
  const _WechatBindingSheet({required this.store});

  final TowerStore store;

  @override
  State<_WechatBindingSheet> createState() => _WechatBindingSheetState();
}

class _WechatBindingSheetState extends State<_WechatBindingSheet> {
  AppStrings get t => AppLocale.of(context);
  final code = TextEditingController();
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _WechatQrScannerPage()),
    );
    if (result == null || !mounted) return;
    code.text = result;
    setState(() => error = '');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.mobile("qrRecognized"))));
  }

  Future<void> _bind() async {
    if (busy || code.text.length != 8) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.store.confirmDeviceBinding(code.text);
      if (mounted) Navigator.pop(context);
    } catch (value) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$value';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      28,
      22,
      28,
      MediaQuery.viewInsetsOf(context).bottom + 28,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t.setting(SettingsText.addDevice),
                style: TextStyle(
                  color: Color(0xff161c22),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: t.setting(SettingsText.close),
              onPressed: busy ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Color(0xff8c9995)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          t.mobile("connectorBindingGuide"),
          style: TextStyle(color: Color(0xff9ba09e), fontSize: 13, height: 1.8),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('onboarding-scan-device-qr'),
            onPressed: busy ? null : _scan,
            style: FilledButton.styleFrom(
              backgroundColor: wechatBlue,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: Text(
              t.mobile("scanToBind"),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Divider(color: Color(0xffe2e6e4))),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                t.mobile("manualEntry"),
                style: TextStyle(color: Color(0xff9ba09e), fontSize: 11),
              ),
            ),
            Expanded(child: Divider(color: Color(0xffe2e6e4))),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('onboarding-binding-code'),
          controller: code,
          enabled: !busy,
          maxLength: 8,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(8),
          ],
          onChanged: (value) {
            final upper = value.toUpperCase();
            if (upper != value) {
              code.value = TextEditingValue(
                text: upper,
                selection: TextSelection.collapsed(offset: upper.length),
              );
            }
            setState(() => error = '');
          },
          decoration: InputDecoration(
            hintText: t.mobile("bindingCodeLabel"),
            counterText: '${code.text.length}/8',
            filled: true,
            fillColor: const Color(0xfff0f6fd),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: Color(0xff69716f)),
            ),
          ),
        ),
        if (error.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            t.errorText(error),
            style: const TextStyle(color: Color(0xffd64545), fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('onboarding-confirm-binding'),
            onPressed: !busy && code.text.length == 8 ? _bind : null,
            style: FilledButton.styleFrom(
              backgroundColor: wechatBlue,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: Text(busy ? t.mobile("addingBusy") : t.mobile("confirmAdd")),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            t.mobile("codeExpiry"),
            style: TextStyle(color: Color(0xff8b9990), fontSize: 11),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () async {
              await Clipboard.setData(
                const ClipboardData(
                  text: 'https://relay.example.com/connector.html',
                ),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t.mobile("installGuideCopied"))),
                );
              }
            },
            child: Text(
              t.mobile("copyInstallGuide"),
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xff155ac2), fontSize: 12),
            ),
          ),
        ),
      ],
    ),
  );
}

String? _bindingCodeFromQr(String raw) {
  final value = raw.trim();
  final direct = value.toUpperCase();
  if (RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(direct)) return direct;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'agenttower' ||
      uri.host.toLowerCase() != 'bind') {
    return null;
  }
  final result = (uri.queryParameters['code'] ?? '').trim().toUpperCase();
  return RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(result) ? result : null;
}

class _WechatQrScannerPage extends StatefulWidget {
  const _WechatQrScannerPage();

  @override
  State<_WechatQrScannerPage> createState() => _WechatQrScannerPageState();
}

class _WechatQrScannerPageState extends State<_WechatQrScannerPage> {
  AppStrings get t => AppLocale.of(context);
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool handled = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _detected(BarcodeCapture capture) {
    if (handled) return;
    for (final barcode in capture.barcodes) {
      final code = _bindingCodeFromQr(barcode.rawValue ?? '');
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
        MobileScanner(controller: controller, onDetect: _detected),
        Center(
          child: Container(
            width: 248,
            height: 248,
            decoration: BoxDecoration(
              border: Border.all(color: wechatBlue, width: 3),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            minimum: EdgeInsets.all(28),
            child: Text(
              t.mobile("connectorQrFrame"),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, height: 1.6),
            ),
          ),
        ),
      ],
    ),
  );
}

class _DrawerProject {
  _DrawerProject({
    required this.key,
    required this.name,
    required this.agent,
    required this.instance,
    required this.sessions,
    this.unnamed = false,
  });

  final bool unnamed;
  final String key;
  final String name;
  final String agent;
  Json instance;
  List<Json> sessions;

  _DrawerProject copyWith({List<Json>? sessions}) => _DrawerProject(
    key: key,
    unnamed: unnamed,
    name: name,
    agent: agent,
    instance: instance,
    sessions: sessions ?? this.sessions,
  );
}
