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

  Future<List<MtpObject>> listChildren({
    required String deviceId,
    required String objectId,
  }) {
    throw UnimplementedError('listChildren() has not been implemented.');
  }

  Future<List<MtpFile>> listMediaFiles({
    required String deviceId,
    required String folderId,
    required List<String> extensions,
  }) {
    throw UnimplementedError('listMediaFiles() has not been implemented.');
  }

  Future<String> copyFileToLocal({
    required String deviceId,
    required String fileId,
    required String destinationPath,
  }) {
    throw UnimplementedError('copyFileToLocal() has not been implemented.');
  }

  Future<List<String>> copyFilesToLocal({
    required String deviceId,
    required Map<String, String> files,
  }) {
    throw UnimplementedError('copyFilesToLocal() has not been implemented.');
  }
}
