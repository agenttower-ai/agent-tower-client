import 'package:agenttower/connection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/widget_test.dart' as widget_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native credentials can be created, read, updated and cleared', (
    tester,
  ) async {
    final credentials = PlatformCredentials();
    // Restore any previous value so this test can also run on a developer device.
    final previous = await credentials.read();
    try {
      await credentials.clear();
      expect(await credentials.read(), isNull);
      await credentials.write('agenttower-native-smoke-v1');
      expect(await PlatformCredentials().read(), 'agenttower-native-smoke-v1');
      await credentials.write('agenttower-native-smoke-v2');
      expect(await PlatformCredentials().read(), 'agenttower-native-smoke-v2');
      await credentials.clear();
      expect(await credentials.read(), isNull);
      await credentials.clear();
    } finally {
      if (previous == null) {
        await credentials.clear();
      } else {
        await credentials.write(previous);
      }
    }
  });

  widget_tests.main(useDeviceSize: true);
}
