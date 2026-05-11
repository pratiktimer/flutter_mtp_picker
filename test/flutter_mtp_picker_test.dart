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
}
