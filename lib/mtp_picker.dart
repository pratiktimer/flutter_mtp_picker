import 'package:flutter/widgets.dart';

import 'mtp_folder_picker.dart';
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

  static Future<List<MtpFile>> listMediaFiles({
    required String deviceId,
    required String folderId,
    required List<String> extensions,
  }) {
    return FlutterMtpPickerPlatform.instance.listMediaFiles(
      deviceId: deviceId,
      folderId: folderId,
      extensions: extensions,
    );
  }

  static Future<MtpFolderSelection?> pickFolder(BuildContext context) {
    return MtpFolderPicker.pickFolder(context);
  }
}
