import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_mtp_picker/flutter_mtp_picker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getDevices returns a device list', (WidgetTester tester) async {
    final devices = await MtpPicker.getDevices();

    expect(devices, isA<List<MtpDevice>>());
  });
}
