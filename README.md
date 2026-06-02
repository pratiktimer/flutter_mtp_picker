# flutter_mtp_picker

A Flutter desktop plugin for browsing phones, cameras, and other USB media devices through platform-native APIs.

Windows exposes MTP devices as portable-device object trees, not normal filesystem paths. This plugin returns stable MTP device IDs and object IDs so apps can browse those devices without faking paths like `C:\...`.

On macOS, the plugin uses Apple's ImageCaptureCore framework. That framework exposes camera/PTP-compatible devices and some phones, but macOS does not provide a public generic Android MTP filesystem API. If an Android device does not appear in Image Capture on macOS, this plugin cannot browse it there.

## Features

- Enumerate connected MTP devices.
- Browse folders recursively using device IDs and object IDs.
- Recursively list media files by extension.
- Show a Flutter folder picker dialog for MTP devices.
- Copy one or more MTP files to local storage.
- Windows desktop implementation using `IPortableDeviceManager`, `IPortableDevice`, and `IPortableDeviceContent`.
- macOS desktop implementation using ImageCaptureCore.

## Platform support

| Platform | Status |
| --- | --- |
| Windows | Supported |
| macOS | Supported for ImageCaptureCore camera/PTP-compatible devices |
| Android, iOS, Linux, Web | Not implemented |

## Usage

Import the package:

```dart
import 'dart:io';

import 'package:flutter_mtp_picker/flutter_mtp_picker.dart';
```

List connected MTP devices:

```dart
final devices = await MtpPicker.getDevices();

for (final device in devices) {
  print('${device.name}: ${device.id}');
}
```

Browse folders from the device root:

```dart
final children = await MtpPicker.listChildren(
  deviceId: devices.first.id,
  objectId: 'ROOT',
);

final folders = children.where((object) => object.isFolder);
```

Browse into a returned folder:

```dart
final nestedChildren = await MtpPicker.listChildren(
  deviceId: devices.first.id,
  objectId: folders.first.id,
);
```

List media files recursively:

```dart
final videos = await MtpPicker.listMediaFiles(
  deviceId: devices.first.id,
  folderId: folders.first.id,
  extensions: const ['mp4', 'mkv', 'avi'],
);
```

Copy one file to local storage:

```dart
final copiedPath = await MtpPicker.copyFileToLocal(
  deviceId: devices.first.id,
  fileId: videos.first.id,
  destinationPath: r'C:\Users\me\Videos\lesson-01.mp4',
);
```

Copy several files with one opened MTP connection:

```dart
final copiedPaths = await MtpPicker.copyFilesToLocal(
  deviceId: devices.first.id,
  files: {
    for (final file in videos.take(5))
      file.id: 'C:\\Users\\me\\Videos\\${file.name}',
  },
);
```

Show the built-in Flutter MTP folder picker:

```dart
final selection = await MtpPicker.pickFolder(context);

if (selection != null) {
  print(selection.device.id);
  print(selection.folder.id);
}
```

Track progress for long copies and support cancel:

```dart
class MtpImportCancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

class MtpImportProgress {
  const MtpImportProgress({
    required this.fileName,
    required this.copiedBytes,
    required this.totalBytes,
    required this.elapsed,
    this.isCancelling = false,
  });

  final String fileName;
  final int copiedBytes;
  final int totalBytes;
  final Duration elapsed;
  final bool isCancelling;

  double? get fraction {
    if (totalBytes <= 0) return null;
    return (copiedBytes / totalBytes).clamp(0, 1).toDouble();
  }

  Duration? get estimatedRemaining {
    if (copiedBytes <= 0 ||
        totalBytes <= copiedBytes ||
        elapsed.inMilliseconds <= 0) {
      return null;
    }

    final bytesPerMillisecond = copiedBytes / elapsed.inMilliseconds;
    final remainingMilliseconds =
        ((totalBytes - copiedBytes) / bytesPerMillisecond).round();
    return Duration(milliseconds: remainingMilliseconds);
  }
}

Future<void> copyLargeMtpFile({
  required MtpDevice device,
  required MtpFile file,
  required String destinationPath,
  required void Function(MtpImportProgress progress) onProgress,
  MtpImportCancelToken? cancelToken,
}) async {
  final destinationFile = File(destinationPath);
  final stopwatch = Stopwatch()..start();

  var isCopyComplete = false;
  Object? copyError;
  StackTrace? copyStackTrace;

  final copyFuture =
      MtpPicker.copyFileToLocal(
            deviceId: device.id,
            fileId: file.id,
            destinationPath: destinationPath,
          )
          .then((_) {
            isCopyComplete = true;
          })
          .catchError((Object error, StackTrace stackTrace) {
            copyError = error;
            copyStackTrace = stackTrace;
            isCopyComplete = true;
          });

  while (!isCopyComplete) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final currentLength = await destinationFile.exists()
        ? await destinationFile.length()
        : 0;

    onProgress(
      MtpImportProgress(
        fileName: file.name,
        copiedBytes: currentLength.clamp(0, file.size).toInt(),
        totalBytes: file.size,
        elapsed: stopwatch.elapsed,
        isCancelling: cancelToken?.isCancelled == true,
      ),
    );
  }

  await copyFuture;
  stopwatch.stop();

  if (copyError != null) {
    Error.throwWithStackTrace(
      copyError!,
      copyStackTrace ?? StackTrace.current,
    );
  }

  if (cancelToken?.isCancelled == true) {
    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }
    throw StateError('Import cancelled.');
  }
}
```

The copy API runs in a background native operation. The progress pattern above
polls the destination file size while that operation is active. A cancel request
is cooperative: mark the UI as cancelling, wait for the current MTP transfer to
return, then delete the local file and stop importing the remaining files.

## Important notes

- MTP object IDs are not filesystem paths.
- Android phones usually need to be unlocked and set to File Transfer / MTP mode.
- Some devices may expose storage through functional objects before normal folders appear.
- Very large recursive scans can take time because MTP enumeration is device-backed USB communication.
- The copy methods do not expose a native abort handle. Use cooperative cancellation in your app when copying very large files or whole courses.
- On macOS, device visibility depends on ImageCaptureCore support for the connected device. Some Android phones expose no browsable storage through Apple's public APIs.

## Example

Run the included Windows example:

```powershell
cd example
flutter run -d windows
```

Connect an Android phone by USB, unlock it, and choose File Transfer / MTP mode.
