import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_mtp_picker_platform_interface.dart';
import 'mtp_models.dart';

/// An implementation of [FlutterMtpPickerPlatform] that uses method channels.
class MethodChannelFlutterMtpPicker extends FlutterMtpPickerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_mtp_picker');

  @override
  Future<List<MtpDevice>> getDevices() async {
    final devices = await methodChannel.invokeListMethod<Object?>('getDevices');
    return (devices ?? <Object?>[])
        .cast<Map<Object?, Object?>>()
        .map(MtpDevice.fromMap)
        .toList(growable: false);
  }
}
