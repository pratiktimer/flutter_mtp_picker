import 'flutter_mtp_picker_platform_interface.dart';
import 'mtp_models.dart';

class MtpPicker {
  const MtpPicker._();

  static Future<List<MtpDevice>> getDevices() {
    return FlutterMtpPickerPlatform.instance.getDevices();
  }

  static Future<List<MtpObject>> listChildren({
    required String deviceId,
    required String objectId,
  }) {
    return FlutterMtpPickerPlatform.instance.listChildren(
      deviceId: deviceId,
      objectId: objectId,
    );
  }
}
