import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Markdown embedded in the conversation's existing vertical scroll view.
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown({super.key, required this.data, required this.onOpenLink});

  final String data;
  final Future<void> Function(String url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(color: Color(0xff172b46), fontSize: 16, height: 1.6);
    return MarkdownBody(
      data: data,
      selectable: true,
      fitContent: false,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: body,
        h1: body.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
        h2: body.copyWith(fontSize: 21, fontWeight: FontWeight.w700),
        h3: body.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        listBullet: body,
        blockquote: body,
        a: body.copyWith(color: const Color(0xff155ac2)),
        code: body.copyWith(fontFamily: 'monospace', fontSize: 13),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xffeaf0f7),
          borderRadius: BorderRadius.circular(8),
        ),
        tableHead: body.copyWith(fontWeight: FontWeight.w700),
        tableBody: body,
        // Wide tables scroll horizontally without widening the message.
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.all(10),
        tableBorder: TableBorder.all(color: const Color(0xffdce5f0)),
        blockSpacing: 12,
      ),
      onTapLink: (text, href, title) {
        if (href != null) onOpenLink(href);
      },
      // Do not automatically fetch URLs or local files mentioned by an agent.
      imageBuilder: (uri, title, alt) => TextButton.icon(
        onPressed: () => onOpenLink(uri.toString()),
        icon: const Icon(Icons.image_outlined),
        label: Text(alt?.isNotEmpty == true ? alt! : uri.toString()),
      ),
    );
  }
}
