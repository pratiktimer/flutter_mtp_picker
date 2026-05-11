import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mtp_picker/flutter_mtp_picker.dart';
import 'package:flutter_mtp_picker/flutter_mtp_picker_platform_interface.dart';
import 'package:flutter_mtp_picker/flutter_mtp_picker_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterMtpPickerPlatform
    with MockPlatformInterfaceMixin
    implements FlutterMtpPickerPlatform {
  @override
  Future<List<MtpDevice>> getDevices() => Future.value(const <MtpDevice>[
    MtpDevice(id: 'device-1', name: 'Android Phone'),
  ]);

  @override
  Future<List<MtpObject>> listChildren({
    required String deviceId,
    required String objectId,
  }) => Future.value(const <MtpObject>[
    MtpObject(id: 'storage-1', name: 'Internal shared storage', isFolder: true),
  ]);

  @override
  Future<List<MtpFile>> listMediaFiles({
    required String deviceId,
    required String folderId,
    required List<String> extensions,
  }) => Future.value(const <MtpFile>[
    MtpFile(id: 'file-1', name: 'lesson1.mp4', size: 123456),
  ]);
}

void main() {
  final FlutterMtpPickerPlatform initialPlatform =
      FlutterMtpPickerPlatform.instance;

  test('$MethodChannelFlutterMtpPicker is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterMtpPicker>());
  });

  test('getDevices', () async {
    MockFlutterMtpPickerPlatform fakePlatform = MockFlutterMtpPickerPlatform();
    FlutterMtpPickerPlatform.instance = fakePlatform;

    expect(await MtpPicker.getDevices(), const <MtpDevice>[
      MtpDevice(id: 'device-1', name: 'Android Phone'),
    ]);
  });

  test('listChildren', () async {
    MockFlutterMtpPickerPlatform fakePlatform = MockFlutterMtpPickerPlatform();
    FlutterMtpPickerPlatform.instance = fakePlatform;

    expect(
      await MtpPicker.listChildren(deviceId: 'device-1', objectId: 'ROOT'),
      const <MtpObject>[
        MtpObject(
          id: 'storage-1',
          name: 'Internal shared storage',
          isFolder: true,
        ),
      ],
    );
  });

  test('listMediaFiles', () async {
    MockFlutterMtpPickerPlatform fakePlatform = MockFlutterMtpPickerPlatform();
    FlutterMtpPickerPlatform.instance = fakePlatform;

    expect(
      await MtpPicker.listMediaFiles(
        deviceId: 'device-1',
        folderId: 'storage-1',
        extensions: const <String>['mp4', 'mkv', 'avi'],
      ),
      const <MtpFile>[MtpFile(id: 'file-1', name: 'lesson1.mp4', size: 123456)],
    );
  });
}
