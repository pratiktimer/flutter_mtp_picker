## 0.1.0

- Added a macOS plugin target backed by `libmtp`.
- Added macOS device enumeration, folder browsing, recursive media listing, and local copy support for USB MTP devices.
- Updated package metadata to advertise desktop support beyond Windows.
- Documented the Homebrew `libmtp` requirement and macOS USB/MTP setup notes.

## 0.0.3

- Fixed the multi-folder picker dialog reference used by `pickFolders`.
- Fixed the `pickFolders` return type so the package can compile on non-Windows Flutter builds.

## 0.0.2

- Added local copy APIs for single files and batches of MTP files.
- Added media file sizes to recursive media scan results.
- Updated the example app with copy benchmarking, progress estimation, and a cancel-and-clean-up flow for large transfers.

## 0.0.1

- Initial Windows implementation.
- Added MTP device enumeration through Windows Portable Devices.
- Added folder browsing with stable device IDs and object IDs.
- Added recursive media file listing by extension.
- Added a Flutter MTP folder picker dialog.
