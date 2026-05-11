import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mtp_picker/flutter_mtp_picker_method_channel.dart';
import 'package:flutter_mtp_picker/mtp_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelFlutterMtpPicker platform = MethodChannelFlutterMtpPicker();
  const MethodChannel channel = MethodChannel('flutter_mtp_picker');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'listChildren') {
            return <Map<String, Object?>>[
              <String, Object?>{
                'id': 'storage-1',
                'name': 'Internal shared storage',
                'isFolder': true,
              },
            ];
          }

          return <Map<String, Object?>>[
            <String, Object?>{'id': 'device-1', 'name': 'Android Phone'},
          ];
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getDevices', () async {
    expect(await platform.getDevices(), const <MtpDevice>[
      MtpDevice(id: 'device-1', name: 'Android Phone'),
    ]);
  });

  test('listChildren', () async {
    expect(
      await platform.listChildren(deviceId: 'device-1', objectId: 'ROOT'),
      const <MtpObject>[
        MtpObject(
          id: 'storage-1',
          name: 'Internal shared storage',
          isFolder: true,
        ),
      ],
    );
  });
}
