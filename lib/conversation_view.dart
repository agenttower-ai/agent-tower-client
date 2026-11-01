import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chat_markdown.dart';
import 'connection_store.dart';
import 'wechat_ui.dart';
import 'app_localizations.dart';
import 'settings_catalog.dart';

class ConversationView extends StatefulWidget {
  const ConversationView({
    super.key,
    required this.store,
    required this.session,
    required this.hostname,
    required this.onNavigate,
  });
  final TowerStore store;
  final Json session;
  final String hostname;
  final ValueChanged<String> onNavigate;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final prompt = TextEditingController();
  final scroll = ScrollController();
  List<Json> history = [];
  final List<Json> pendingMessages = [];
  bool loading = true, sending = false, infoOpen = false;
  String historyError = '', selectedModel = '', signature = '';
  TowerStore get store => widget.store;
  AppStrings get t => AppLocale.of(context);
  String c(String key) => t.conversation(key);
  String demoText(dynamic value) => t.demoValue(value, demo: store.demo);
  Json get current =>
      store
          .rows('sessions')
          .where(
            (session) =>
                session['id'] == widget.session['id'] &&
                session['instanceId'] == widget.session['instanceId'],
          )
          .firstOrNull ??
      widget.session;
  bool get running => ['busy', 'retry', 'thinking'].contains(current['status']);

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    try {
      final messages = await store.loadSessionMessages(widget.session);
      if (mounted) {
        setState(() {
          history = messages;
          loading = false;
          historyError = '';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          loading = false;
          historyError = '$error';
        });
      }
    }
  }

  @override
  void dispose() {
    prompt.dispose();
    scroll.dispose();
    super.dispose();
  }

  void toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> send() async {
    final text = prompt.text.trim();
    if (text.isEmpty ||
        sending ||
        running ||
        !store.canControlSession('${current['instanceId']}')) {
      return;
    }
    setState(() => sending = true);
    try {
      await store.controlSession(
        current,
        'prompt',
        text: text,
        model: selectedModel,
      );
      if (!mounted) return;
      setState(() {
        pendingMessages.add({
          'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
          'role': 'user',
          'text': text,
          'at': DateTime.now().millisecondsSinceEpoch,
        });
        prompt.clear();
      });
      toast(c('sent'));
      await loadHistory();
    } catch (error) {
      if (mounted) toast(t.errorText(error));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  List<Json> messages() {
    final merged = <String, Json>{};
    for (final message in [
      ...history,
      ...store
          .rows('logs')
          .where(
            (log) =>
                log['instanceId'] == widget.session['instanceId'] &&
                log['sessionID'] == widget.session['id'],
          ),
    ]) {
      merged['${message['role']}:${message['messageID'] ?? message['id']}'] =
          message;
    }
    for (final message in pendingMessages) {
      if (!merged.values.any(
        (other) =>
            other['role'] == 'user' &&
            other['text'] == message['text'] &&
            ((other['at'] as num? ?? 0) - (message['at'] as num)).abs() < 60000,
      )) {
        merged['${message['id']}'] = message;
      }
    }
    return merged.values.toList()
      ..sort((a, b) => (a['at'] as num? ?? 0).compareTo(b['at'] as num? ?? 0));
  }

  Future<void> pickModel() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => _ModelPicker(
        store: store,
        instanceId: '${current['instanceId']}',
        selected: selectedModel,
        onSelected: (value) => setState(() => selectedModel = value),
      ),
    );
  }

  Future<void> abort() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c('abortTitle')),
        content: Text(c('abortExplanation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.setting(SettingsText.cancel)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(c('abort')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await store.controlSession(current, 'abort');
      if (mounted) toast(c('aborted'));
    } catch (error) {
      if (mounted) toast(t.errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final items = messages();
      final nextSignature = items
          .map((message) => '${message['id']}:${message['text']}')
          .join('|');
      if (signature != nextSignature) {
        signature = nextSignature;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) {
            scroll.jumpTo(scroll.position.maxScrollExtent);
          }
        });
      }
      final live = store
          .rows('sessions')
          .any(
            (session) =>
                session['id'] == widget.session['id'] &&
                session['instanceId'] == widget.session['instanceId'],
          );
      final status = live
          ? t.sessionStatus(current['status'])
          : store
                .rows('instances')
                .any(
                  (instance) =>
                      instance['id'] == current['instanceId'] &&
                      store.online(instance),
                )
          ? c('ended')
          : c('offline');
      final canControl = store.canControlSession('${current['instanceId']}');
      final busy = sending || store.action.isNotEmpty;
      return Scaffold(
        key: scaffoldKey,
        backgroundColor: const Color(0xfff6f9fd),
        drawerScrimColor: const Color(0x6113231d),
        drawer: WechatUiHome(
          store: store,
          onDemo: () {},
          sidebarOnly: true,
          onClose: () => scaffoldKey.currentState?.closeDrawer(),
          onNavigate: (label) {
            scaffoldKey.currentState?.closeDrawer();
            widget.onNavigate(label);
          },
          onSession: (session) {
            scaffoldKey.currentState?.closeDrawer();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => ConversationView(
                  store: store,
                  session: session,
                  hostname:
                      '${store.rows('instances').where((instance) => instance['id'] == session['instanceId']).firstOrNull?['hostname'] ?? session['instanceId']}',
                  onNavigate: widget.onNavigate,
                ),
              ),
            );
          },
        ),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xffedf0f3))),
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('conversation-menu'),
                      tooltip: t.menu,
                      onPressed: () => scaffoldKey.currentState?.openDrawer(),
                      icon: const Icon(
                        Icons.menu_rounded,
                        size: 20,
                        color: wechatText,
                      ),
                    ),
                    IconButton(
                      tooltip: t.home,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: wechatText,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            demoText(current['title'] ?? c('untitled')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: wechatText,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$status · ${demoText(widget.hostname)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: wechatMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('conversation-info'),
                      tooltip: c('info'),
                      onPressed: () => setState(() => infoOpen = !infoOpen),
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: wechatMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: loadHistory,
                  child: ListView(
                    key: const ValueKey('conversation-thread'),
                    controller: scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
                    children: [
                      if (infoOpen)
                        Container(
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xffe8ecf1)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${current['agent'] ?? 'OpenCode'} · ${current['tool'] is Map ? demoText(current['tool']['title'] ?? current['tool']['name'] ?? c('noTool')) : c('noTool')}',
                                style: const TextStyle(
                                  color: wechatMuted,
                                  height: 1.8,
                                ),
                              ),
                              Text(
                                '${c('directory')} · ${current['directory'] ?? c('unspecified')}',
                                style: const TextStyle(
                                  color: wechatMuted,
                                  height: 1.8,
                                ),
                              ),
                              if (current['parentID'] != null)
                                Text('${c('parent')} · ${current['parentID']}'),
                              OutlinedButton(
                                onPressed: canControl && running && !busy
                                    ? abort
                                    : null,
                                child: Text(
                                  c('abort'),
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 50),
                          child: Column(
                            children: [
                              Text(
                                loading
                                    ? c('loading')
                                    : historyError.isNotEmpty
                                    ? '${c('loadFailed')}: ${t.errorText(historyError)}'
                                    : c('empty'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: wechatMuted,
                                  fontSize: 14,
                                  height: 1.8,
                                ),
                              ),
                              if (historyError.isNotEmpty)
                                TextButton(
                                  onPressed: loadHistory,
                                  child: Text(t.retry),
                                ),
                            ],
                          ),
                        ),
                      for (final message in items) _message(message),
                      if (running && live)
                        Row(
                          children: [
                            const SizedBox(
                              width: 6,
                              height: 6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xff18bffb),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                current['tool'] is Map
                                    ? demoText(
                                        current['tool']['title'] ??
                                            current['tool']['name'] ??
                                            c('working'),
                                      )
                                    : c('working'),
                                style: const TextStyle(
                                  color: wechatMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xffe9edf2))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey('session-prompt-input'),
                      controller: prompt,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      enabled: !busy && canControl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: c('prompt'),
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xfff4f6f9),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            key: const ValueKey('session-model-picker'),
                            onPressed: busy ? null : pickModel,
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xfff4f6f9),
                              alignment: Alignment.centerLeft,
                              foregroundColor: const Color(0xff536589),
                            ),
                            child: Text(
                              '${c('model')} · ${selectedModel.isNotEmpty ? selectedModel : current['model'] ?? c('default')} ▾',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('session-prompt-send'),
                          onPressed:
                              !busy &&
                                  canControl &&
                                  live &&
                                  !running &&
                                  prompt.text.trim().isNotEmpty
                              ? send
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: wechatBlue,
                            minimumSize: const Size(100, 36),
                          ),
                          child: Text(sending ? c('sending') : c('send')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      !canControl
                          ? c('disabled')
                          : running
                          ? c('wait')
                          : selectedModel.isNotEmpty
                          ? c('selectedModel')
                          : c('sessionModel'),
                      style: const TextStyle(color: wechatMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _message(Json message) {
    final user = message['role'] == 'user';
    final at = DateTime.fromMillisecondsSinceEpoch(
      (message['at'] as num? ?? 0).toInt(),
    ).toLocal();
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}:${at.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: user
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            '${user ? c('me') : c('assistant')}  $time',
            style: const TextStyle(color: wechatMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * (user ? .88 : 1),
            ),
            padding: user
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
                : const EdgeInsets.symmetric(vertical: 2),
            decoration: user
                ? const BoxDecoration(
                    color: Color(0xffeaf4ff),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(14),
                      topRight: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(4),
                    ),
                  )
                : null,
            child: ChatMarkdown(
              data: store.demo && message['demoTextKey'] is String
                  ? c(message['demoTextKey'] as String)
                  : '${message['text'] ?? ''}',
              onOpenLink: openMessageLink,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> openMessageLink(String url) async {
    if (TowerStore.validProjectLink(url)) {
      try {
        await const MethodChannel(
          'com.agenttower.mobile/project-links',
        ).invokeMethod<void>('openLink', url);
        return;
      } catch (_) {
        // Keep the URL available when the system browser cannot open it.
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(t.setting(SettingsText.copyLink)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.setting(SettingsText.close)),
          ),
        ],
      ),
    );
  }
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({
    required this.store,
    required this.instanceId,
    required this.selected,
    required this.onSelected,
  });
  final TowerStore store;
  final String instanceId, selected;
  final ValueChanged<String> onSelected;
  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  AppStrings get t => AppLocale.of(context);
  String c(String key) => t.conversation(key);
  List<Json> models = [];
  bool loading = true;
  String error = '', query = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await widget.store.listSessionModels(widget.instanceId);
      if (mounted) {
        setState(() {
          models = result;
          loading = false;
        });
      }
    } catch (value) {
      if (mounted) {
        setState(() {
          error = '$value';
          loading = false;
        });
      }
    }
  }

  void select(String id) {
    widget.onSelected(id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c('chooseModel'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            ListTile(
              title: Text(c('reuseModel')),
              trailing: widget.selected.isEmpty
                  ? const Icon(Icons.check, color: wechatBlue)
                  : null,
              onTap: () => select(''),
            ),
            TextField(
              onChanged: (value) => setState(() => query = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: c('searchModel'),
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : error.isNotEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.errorText(error), textAlign: TextAlign.center),
                          TextButton(onPressed: load, child: Text(t.retry)),
                        ],
                      ),
                    )
                  : ListView(
                      children: [
                        for (final model in models.where(
                          (model) =>
                              '${model['name']} ${model['id']} ${model['provider']}'
                                  .toLowerCase()
                                  .contains(query),
                        ))
                          ListTile(
                            title: Text('${model['name'] ?? model['id']}'),
                            subtitle: Text('${model['id']}'),
                            trailing: widget.selected == model['id']
                                ? const Icon(Icons.check, color: wechatBlue)
                                : null,
                            onTap: () => select('${model['id']}'),
                          ),
                        if (models
                            .where(
                              (model) =>
                                  '${model['name']} ${model['id']} ${model['provider']}'
                                      .toLowerCase()
                                      .contains(query),
                            )
                            .isEmpty)
                          Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              c('noModels'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
