import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_mtp_picker_method_channel.dart';
import 'mtp_models.dart';

abstract class FlutterMtpPickerPlatform extends PlatformInterface {
  /// Constructs a FlutterMtpPickerPlatform.
  FlutterMtpPickerPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterMtpPickerPlatform _instance = MethodChannelFlutterMtpPicker();

  /// The default instance of [FlutterMtpPickerPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterMtpPicker].
  static FlutterMtpPickerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterMtpPickerPlatform] when
  /// they register themselves.
  static set instance(FlutterMtpPickerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<List<MtpDevice>> getDevices() {
    throw UnimplementedError('getDevices() has not been implemented.');
  }
}
