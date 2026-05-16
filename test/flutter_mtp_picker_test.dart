import 'package:flutter_mtp_picker/flutter_mtp_picker.dart';
import 'package:flutter_mtp_picker/flutter_mtp_picker_method_channel.dart';
import 'package:flutter_mtp_picker/flutter_mtp_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
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
  }) =>
      Future.value(const <MtpObject>[
        MtpObject(
            id: 'storage-1', name: 'Internal shared storage', isFolder: true),
      ]);

  @override
  Future<List<MtpFile>> listMediaFiles({
    required String deviceId,
    required String folderId,
    required List<String> extensions,
  }) =>
      Future.value(const <MtpFile>[
        MtpFile(id: 'file-1', name: 'lesson1.mp4', size: 123456),
      ]);

  @override
  Future<String> copyFileToLocal({
    required String deviceId,
    required String fileId,
    required String destinationPath,
  }) =>
      Future.value(destinationPath);

  @override
  Future<List<String>> copyFilesToLocal({
    required String deviceId,
    required Map<String, String> files,
  }) =>
      Future.value(files.values.toList(growable: false));
}

void main() {
  final FlutterMtpPickerPlatform initialPlatform =
      FlutterMtpPickerPlatform.instance;

  test('$MethodChannelFlutterMtpPicker is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterMtpPicker>());
  });

  test('getDevices', () async {
    final fakePlatform = MockFlutterMtpPickerPlatform();
    FlutterMtpPickerPlatform.instance = fakePlatform;

    expect(await MtpPicker.getDevices(), const <MtpDevice>[
      MtpDevice(id: 'device-1', name: 'Android Phone'),
    ]);
  });

  test('listChildren', () async {
    final fakePlatform = MockFlutterMtpPickerPlatform();
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
    final fakePlatform = MockFlutterMtpPickerPlatform();
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

  test('copyFileToLocal', () async {
    final fakePlatform = MockFlutterMtpPickerPlatform();
    FlutterMtpPickerPlatform.instance = fakePlatform;

    expect(
      await MtpPicker.copyFileToLocal(
        deviceId: 'device-1',
        fileId: 'file-1',
        destinationPath: 'C:\\Temp\\lesson1.mp4',
      ),
      'C:\\Temp\\lesson1.mp4',
    );
  });

  test('copyFilesToLocal', () async {
    final fakePlatform = MockFlutterMtpPickerPlatform();
    FlutterMtpPickerPlatform.instance = fakePlatform;

    expect(
      await MtpPicker.copyFilesToLocal(
        deviceId: 'device-1',
        files: const <String, String>{
          'file-1': 'C:\\Temp\\lesson1.mp4',
          'file-2': 'C:\\Temp\\lesson2.mp4',
        },
      ),
      const <String>['C:\\Temp\\lesson1.mp4', 'C:\\Temp\\lesson2.mp4'],
    );
  });
}
