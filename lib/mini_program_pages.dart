import 'package:flutter/material.dart';
import 'external_link.dart';
import 'connection_store.dart';
import 'wechat_ui.dart';
import 'setup_agent_icon.dart';
import 'app_localizations.dart';

class AnnouncementsView extends StatefulWidget {
  const AnnouncementsView({super.key, required this.store});
  final TowerStore store;
  @override
  State<AnnouncementsView> createState() => _AnnouncementsViewState();
}

class _AnnouncementsViewState extends State<AnnouncementsView> {
  late Future<Json> result = widget.store.request(
    '/mobile/announcements',
    token: '',
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: result,
    builder: (context, snapshot) {
      final t = AppLocale.of(context);
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError) {
        return Column(
          children: [
            Text(t.announcementsUnavailable),
            TextButton(
              onPressed: () => setState(
                () => result = widget.store.request(
                  '/mobile/announcements',
                  token: '',
                ),
              ),
              child: Text(t.retry),
            ),
          ],
        );
      }
      final notices = (snapshot.data?['announcements'] as List? ?? [])
          .whereType<Map>()
          .map(t.localizedContent);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.developerNews,
            style: const TextStyle(
              color: wechatText,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          if (notices.isEmpty)
            Text(t.noAnnouncements, textAlign: TextAlign.center),
          for (final notice in notices)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xffdce4f3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${notice['title'] ?? ''}',
                    style: const TextStyle(
                      color: wechatText,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${notice['publishedLabel'] ?? notice['publishedAt'] ?? ''}',
                    style: const TextStyle(color: wechatMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    (notice['paragraphs'] as List?)?.join('\n\n') ??
                        '${notice['content'] ?? ''}',
                    style: const TextStyle(
                      color: wechatText,
                      fontSize: 15,
                      height: 1.85,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class HelpView extends StatefulWidget {
  const HelpView({super.key, required this.store});
  final TowerStore store;
  @override
  State<HelpView> createState() => _HelpViewState();
}

class _HelpViewState extends State<HelpView> {
  AppStrings get t => AppLocale.of(context);
  @override
  void initState() {
    super.initState();
    Future.microtask(widget.store.refreshSetupAgents);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.help,
          style: const TextStyle(
            color: wechatText,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          t.helpText('supportedAgents'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          t.helpText('restartAgent'),
          style: const TextStyle(color: wechatMuted, height: 1.8),
        ),
        if (widget.store.setupAgentsLoading && widget.store.setupAgents.isEmpty)
          Text(t.helpText('agentsLoading')),
        if (widget.store.setupAgentsError.isNotEmpty) ...[
          Text(
            '${t.helpText("agentsLoadError")}: ${t.errorText(widget.store.setupAgentsError)}',
          ),
          TextButton(
            onPressed: widget.store.refreshSetupAgents,
            child: Text(t.retry),
          ),
        ],
        for (final agent in widget.store.setupAgents)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(
              width: 23,
              height: 23,
              child: SetupAgentIcon(agent: agent),
            ),
            title: Text(agent['name'] as String),
          ),
        Text(
          t.helpText('agentControls'),
          style: const TextStyle(color: wechatMuted, height: 1.8),
        ),
        const SizedBox(height: 24),
        Text(
          t.helpText('websiteFeedback'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SelectableText('https://relay.example.com'),
        TextButton(
          onPressed: () => openExternalLink(context, websiteUri(t.language)),
          child: Text(t.mobile('openWebsite')),
        ),
        Text(
          t.helpText('feedbackGuide'),
          style: const TextStyle(color: wechatMuted, height: 1.8),
        ),
      ],
    ),
  );
}
