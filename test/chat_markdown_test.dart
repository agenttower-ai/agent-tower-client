import 'package:agenttower/chat_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const sample = '''# Task plan

Use **priorities** and `task.id`.

- Capture tasks
- Track progress

> Keep the first release small.

| Feature | Implementation details |
| --- | --- |
| Tasks | Create, edit, search, filter, prioritize, and complete tasks |

```dart
final task = Task(id: 'task-123', title: 'A very long task description that should scroll rather than overflow');
```

[Setup guide](https://relay.example.com/connector.html)

![Architecture](https://example.com/private-image.png)
''';

void main() {
  for (final width in [390.0, 1032.0]) {
    testWidgets('Markdown renders and scrolls at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 1376);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? opened;
      Widget page(String text) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ChatMarkdown(
              data: text,
              onOpenLink: (url) async => opened = url,
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(sample));
      await tester.pumpAndSettle();
      expect(find.text('Task plan'), findsOneWidget);
      expect(find.text('# Task plan'), findsNothing);
      expect(find.byType(Table), findsOneWidget);
      final horizontal = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      expect(horizontal, findsAtLeastNWidgets(2));
      await tester.drag(horizontal.first, const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Links remain interactive alongside selectable rendered text.
      await tester.ensureVisible(find.text('Setup guide'));
      await tester.tap(find.text('Setup guide'));
      await tester.pumpAndSettle();
      expect(opened, 'https://relay.example.com/connector.html');
      expect(find.byType(Image), findsNothing);
      // Partial streaming markup must not break layout.
      await tester.pumpWidget(
        page('# Streaming\n\n**Partial response\n\n```dart\nfinal task ='),
      );
      await tester.pumpAndSettle();
      expect(find.text('Streaming'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
