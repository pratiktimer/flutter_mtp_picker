# flutter_mtp_picker

A Flutter Windows plugin for browsing Android phones, cameras, and other USB MTP devices through the Windows Portable Devices API.

Windows exposes MTP devices as portable-device object trees, not normal filesystem paths. This plugin returns stable MTP device IDs and object IDs so apps can browse those devices without faking paths like `C:\...`.

## Features

- Enumerate connected MTP devices.
- Browse folders recursively using device IDs and object IDs.
- Recursively list media files by extension.
- Show a Flutter folder picker dialog for MTP devices.
- Windows desktop implementation using `IPortableDeviceManager`, `IPortableDevice`, and `IPortableDeviceContent`.

## Platform support

| Platform | Status |
| --- | --- |
| Windows | Supported |
| Android, iOS, macOS, Linux, Web | Not implemented |

## Usage

Import the package:

```dart
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

Show the built-in Flutter MTP folder picker:

```dart
final selection = await MtpPicker.pickFolder(context);

if (selection != null) {
  print(selection.device.id);
  print(selection.folder.id);
}
```

## Important notes

- MTP object IDs are not filesystem paths.
- Android phones usually need to be unlocked and set to File Transfer / MTP mode.
- Some devices may expose storage through functional objects before normal folders appear.
- Very large recursive scans can take time because MTP enumeration is device-backed USB communication.

## Example

Run the included Windows example:

```powershell
cd example
flutter run -d windows
```

Connect an Android phone by USB, unlock it, and choose File Transfer / MTP mode.
