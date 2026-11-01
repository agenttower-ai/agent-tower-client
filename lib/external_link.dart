import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_localizations.dart';
import 'settings_catalog.dart';

Uri websiteUri(AppLanguage language, [String page = '']) =>
    Uri.https('relay.example.com', '/$page', {
      'lang': language == AppLanguage.zh
          ? 'zh-CN'
          : language == AppLanguage.zhHant
          ? 'zh-TW'
          : language.code,
    });

Future<void> openExternalLink(BuildContext context, Uri uri) async {
  try {
    await const MethodChannel(
      'com.agenttower.mobile/project-links',
    ).invokeMethod<void>('openLink', uri.toString());
  } catch (_) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        final t = AppLocale.of(context);
        return AlertDialog(
          title: Text(t.setting(SettingsText.browserUnavailable)),
          content: SelectableText(uri.toString()),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: uri.toString()));
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(t.setting(SettingsText.copyLink)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.setting(SettingsText.close)),
            ),
          ],
        );
      },
    );
  }
}
