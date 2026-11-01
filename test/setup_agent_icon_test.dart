import 'package:agenttower/setup_agent_icon.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all reserved brand SVGs are bundled and can be decoded', () async {
    for (final brand in SetupAgentIcon.brands) {
      final loader = SvgAssetLoader('assets/brands/$brand.svg');
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(manifest.listAssets(), contains(loader.assetName));
      expect(await rootBundle.loadString(loader.assetName), contains('<svg'));
      expect((await loader.loadBytes(null)).lengthInBytes, greaterThan(0));
    }
  });
  testWidgets('every reserved icon renders through the configured asset path', (
    tester,
  ) async {
    for (final brand in SetupAgentIcon.brands) {
      await tester.pumpWidget(
        MaterialApp(
          home: SetupAgentIcon(
            agent: {'icon': '/assets/brands/$brand.svg', 'brand': brand},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('AI'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
