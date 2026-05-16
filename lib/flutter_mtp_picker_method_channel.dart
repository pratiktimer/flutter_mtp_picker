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

  @override
  Future<List<MtpObject>> listChildren({
    required String deviceId,
    required String objectId,
  }) async {
    final children = await methodChannel.invokeListMethod<Object?>(
      'listChildren',
      <String, Object?>{'deviceId': deviceId, 'objectId': objectId},
    );
    return (children ?? <Object?>[])
        .cast<Map<Object?, Object?>>()
        .map(MtpObject.fromMap)
        .toList(growable: false);
  }

  @override
  Future<List<MtpFile>> listMediaFiles({
    required String deviceId,
    required String folderId,
    required List<String> extensions,
  }) async {
    final files = await methodChannel.invokeListMethod<Object?>(
      'listMediaFiles',
      <String, Object?>{
        'deviceId': deviceId,
        'folderId': folderId,
        'extensions': extensions,
      },
    );
    return (files ?? <Object?>[])
        .cast<Map<Object?, Object?>>()
        .map(MtpFile.fromMap)
        .toList(growable: false);
  }

  @override
  Future<String> copyFileToLocal({
    required String deviceId,
    required String fileId,
    required String destinationPath,
  }) async {
    final path = await methodChannel.invokeMethod<String>(
      'copyFileToLocal',
      <String, Object?>{
        'deviceId': deviceId,
        'fileId': fileId,
        'destinationPath': destinationPath,
      },
    );
    if (path == null || path.isEmpty) {
      throw StateError('copyFileToLocal returned an empty path.');
    }
    return path;
  }

  @override
  Future<List<String>> copyFilesToLocal({
    required String deviceId,
    required Map<String, String> files,
  }) async {
    final paths = await methodChannel.invokeListMethod<String>(
      'copyFilesToLocal',
      <String, Object?>{'deviceId': deviceId, 'files': files},
    );
    return (paths ?? <String>[]).toList(growable: false);
  }
}
