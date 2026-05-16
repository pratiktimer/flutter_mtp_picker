import 'package:flutter/material.dart';
import 'package:flutter_mtp_picker/flutter_mtp_picker.dart';
import 'package:flutter_mtp_picker/flutter_mtp_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeMtpPickerPlatform
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
      Future.value(const <MtpFile>[]);

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
  testWidgets('pickFolder returns selected MTP root folder', (
    WidgetTester tester,
  ) async {
    FlutterMtpPickerPlatform.instance = FakeMtpPickerPlatform();
    MtpFolderSelection? selection;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return TextButton(
              onPressed: () async {
                selection = await MtpPicker.pickFolder(context);
              },
              child: const Text('Pick'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Android Phone').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose folder'));
    await tester.pumpAndSettle();

    expect(
      selection,
      const MtpFolderSelection(
        device: MtpDevice(id: 'device-1', name: 'Android Phone'),
        folder: MtpObject(id: 'ROOT', name: 'Android Phone', isFolder: true),
      ),
    );
  });
}
