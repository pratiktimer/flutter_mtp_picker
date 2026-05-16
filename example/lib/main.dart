import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mtp_picker/flutter_mtp_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<MtpDevice> _devices = const <MtpDevice>[];
  MtpDevice? _selectedDevice;
  List<MtpObject> _children = const <MtpObject>[];
  List<MtpFile> _mediaFiles = const <MtpFile>[];
  final List<MtpObject> _path = <MtpObject>[];
  MtpFolderSelection? _pickedFolder;
  bool _loadingChildren = false;
  bool _loadingMedia = false;
  bool _copyingMedia = false;
  bool _copyCancelRequested = false;
  MtpCopyProgress? _copyProgress;
  String? _copyStats;
  String? _error;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    List<MtpDevice> devices;
    String? error;
    try {
      devices = await MtpPicker.getDevices();
    } on PlatformException catch (e) {
      devices = const <MtpDevice>[];
      error = e.message ?? 'Failed to enumerate MTP devices.';
    }

    if (!mounted) return;

    setState(() {
      _devices = devices;
      _error = error;
    });
  }

  Future<void> _openDevice(MtpDevice device) async {
    setState(() {
      _selectedDevice = device;
      _children = const <MtpObject>[];
      _mediaFiles = const <MtpFile>[];
      _path.clear();
      _loadingChildren = true;
      _loadingMedia = false;
      _error = null;
    });

    await _loadChildren(deviceId: device.id, objectId: 'ROOT');
  }

  Future<void> _openFolder(MtpObject folder) async {
    final device = _selectedDevice;
    if (device == null || !folder.isFolder) return;

    setState(() {
      _path.add(folder);
      _children = const <MtpObject>[];
      _mediaFiles = const <MtpFile>[];
      _loadingChildren = true;
      _loadingMedia = false;
      _error = null;
    });

    await _loadChildren(deviceId: device.id, objectId: folder.id);
  }

  Future<void> _goBack() async {
    final device = _selectedDevice;
    if (device == null || _path.isEmpty) return;

    setState(() {
      _path.removeLast();
      _children = const <MtpObject>[];
      _mediaFiles = const <MtpFile>[];
      _loadingChildren = true;
      _loadingMedia = false;
      _error = null;
    });

    await _loadChildren(
      deviceId: device.id,
      objectId: _path.isEmpty ? 'ROOT' : _path.last.id,
    );
  }

  Future<void> _loadChildren({
    required String deviceId,
    required String objectId,
  }) async {
    List<MtpObject> children;
    String? error;
    try {
      children = await MtpPicker.listChildren(
        deviceId: deviceId,
        objectId: objectId,
      );
    } on PlatformException catch (e) {
      children = const <MtpObject>[];
      error = e.message ?? 'Failed to list MTP folder.';
    }

    if (!mounted) return;

    setState(() {
      _children = children;
      _loadingChildren = false;
      _error = error;
    });
  }

  Future<void> _scanVideos() async {
    final device = _selectedDevice;
    if (device == null) return;

    setState(() {
      _mediaFiles = const <MtpFile>[];
      _loadingMedia = true;
      _error = null;
    });

    List<MtpFile> files;
    String? error;
    try {
      files = await MtpPicker.listMediaFiles(
        deviceId: device.id,
        folderId: _path.isEmpty ? 'ROOT' : _path.last.id,
        extensions: const <String>['mp4', 'mkv', 'avi'],
      );
    } on PlatformException catch (e) {
      files = const <MtpFile>[];
      error = e.message ?? 'Failed to scan media files.';
    }

    if (!mounted) return;

    setState(() {
      _mediaFiles = files;
      _loadingMedia = false;
      _copyStats = null;
      _error = error;
    });
  }

  Future<void> _pickFolder() async {
    final selection = await MtpPicker.pickFolder(context);
    if (!mounted || selection == null) return;

    setState(() {
      _pickedFolder = selection;
    });
  }

  Future<Directory> _benchmarkDirectory(String label) async {
    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'flutter_mtp_picker_benchmark${Platform.pathSeparator}$label',
    );
    return directory.create(recursive: true);
  }

  String _safeFileName(String name) {
    final sanitized = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    return sanitized.isEmpty ? 'mtp_file' : sanitized;
  }

  String _copySummary({
    required String label,
    required int fileCount,
    required int byteCount,
    required Duration elapsed,
    required String directoryPath,
  }) {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final megabytes = byteCount / (1024 * 1024);
    final rate = seconds <= 0 ? 0 : megabytes / seconds;
    return '$label: $fileCount file(s), '
        '${megabytes.toStringAsFixed(2)} MB in '
        '${seconds.toStringAsFixed(2)}s '
        '(${rate.toStringAsFixed(2)} MB/s)\n'
        'Saved to: $directoryPath';
  }

  Future<void> _copyFirstVideo() async {
    final device = _selectedDevice;
    if (device == null || _mediaFiles.isEmpty || _copyingMedia) return;

    setState(() {
      _copyingMedia = true;
      _copyCancelRequested = false;
      _copyProgress = null;
      _copyStats = null;
      _error = null;
    });

    String? stats;
    String? error;
    try {
      final file = _mediaFiles.first;
      final directory = await _benchmarkDirectory('single');
      final destination =
          '${directory.path}${Platform.pathSeparator}${_safeFileName(file.name)}';
      final result = await _copyFileWithProgress(
        device: device,
        file: file,
        destinationPath: destination,
      );
      stats = _copySummary(
        label: 'Single copy',
        fileCount: 1,
        byteCount: file.size,
        elapsed: result.elapsed,
        directoryPath: directory.path,
      );
    } on _MtpCopyCancelledException {
      stats =
          'Copy cancelled. The local file was deleted after the active '
          'MTP transfer returned.';
    } on PlatformException catch (e) {
      error = e.message ?? 'Failed to copy media file.';
    } on FileSystemException catch (e) {
      error = e.message;
    }

    if (!mounted) return;

    setState(() {
      _copyingMedia = false;
      _copyCancelRequested = false;
      _copyProgress = null;
      _copyStats = stats;
      _error = error;
    });
  }

  Future<_MtpCopyResult> _copyFileWithProgress({
    required MtpDevice device,
    required MtpFile file,
    required String destinationPath,
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
      final copiedBytes = currentLength.clamp(0, file.size).toInt();

      if (mounted) {
        setState(() {
          _copyProgress = MtpCopyProgress(
            fileName: file.name,
            copiedBytes: copiedBytes,
            totalBytes: file.size,
            elapsed: stopwatch.elapsed,
            isCancelling: _copyCancelRequested,
          );
        });
      }
    }

    await copyFuture;
    stopwatch.stop();

    if (copyError != null) {
      Error.throwWithStackTrace(
        copyError!,
        copyStackTrace ?? StackTrace.current,
      );
    }

    if (_copyCancelRequested) {
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }
      throw const _MtpCopyCancelledException();
    }

    return _MtpCopyResult(elapsed: stopwatch.elapsed);
  }

  void _cancelCopy() {
    if (!_copyingMedia) return;
    setState(() {
      _copyCancelRequested = true;
      final progress = _copyProgress;
      if (progress != null) {
        _copyProgress = progress.copyWith(isCancelling: true);
      }
    });
  }

  Future<void> _copyFirstVideosBatch() async {
    final device = _selectedDevice;
    if (device == null || _mediaFiles.isEmpty || _copyingMedia) return;

    setState(() {
      _copyingMedia = true;
      _copyCancelRequested = false;
      _copyProgress = null;
      _copyStats = null;
      _error = null;
    });

    String? stats;
    String? error;
    try {
      final files = _mediaFiles.take(5).toList(growable: false);
      final directory = await _benchmarkDirectory('batch');
      final destinations = <String, String>{};
      var totalBytes = 0;

      for (var index = 0; index < files.length; index += 1) {
        final file = files[index];
        totalBytes += file.size;
        destinations[file.id] =
            '${directory.path}${Platform.pathSeparator}'
            '${index + 1}_${_safeFileName(file.name)}';
      }

      final stopwatch = Stopwatch()..start();
      await MtpPicker.copyFilesToLocal(
        deviceId: device.id,
        files: destinations,
      );
      stopwatch.stop();
      stats = _copySummary(
        label: 'Batch copy',
        fileCount: files.length,
        byteCount: totalBytes,
        elapsed: stopwatch.elapsed,
        directoryPath: directory.path,
      );
    } on PlatformException catch (e) {
      error = e.message ?? 'Failed to batch copy media files.';
    } on FileSystemException catch (e) {
      error = e.message;
    }

    if (!mounted) return;

    setState(() {
      _copyingMedia = false;
      _copyCancelRequested = false;
      _copyProgress = null;
      _copyStats = stats;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('MTP devices')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _pickFolder,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Pick MTP folder'),
              ),
            ),
            if (_pickedFolder != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Picked: ${_pickedFolder!.device.name} / '
                  '${_pickedFolder!.folder.name}\n'
                  'Folder ID: ${_pickedFolder!.folder.id}',
                ),
              ),
            const Divider(height: 32),
            if (_error != null)
              Text(_error!, style: Theme.of(context).textTheme.bodyLarge)
            else if (_devices.isEmpty)
              const Text('No MTP devices connected.')
            else
              for (final device in _devices)
                ListTile(
                  title: Text(device.name),
                  subtitle: Text(device.id),
                  selected: _selectedDevice?.id == device.id,
                  onTap: () => _openDevice(device),
                ),
            if (_selectedDevice != null) ...<Widget>[
              const Divider(height: 32),
              Row(
                children: <Widget>[
                  IconButton(
                    onPressed: _path.isEmpty || _loadingChildren
                        ? null
                        : _goBack,
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Text(
                      _path.isEmpty
                          ? _selectedDevice!.name
                          : _path
                                .map((MtpObject object) => object.name)
                                .join(' / '),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loadingChildren || _loadingMedia
                        ? null
                        : _scanVideos,
                    icon: const Icon(Icons.video_file_outlined),
                    label: const Text('Scan videos'),
                  ),
                ],
              ),
              if (_loadingChildren)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_children.isEmpty)
                const ListTile(title: Text('No child objects.'))
              else
                for (final child in _children)
                  ListTile(
                    leading: Icon(
                      child.isFolder
                          ? Icons.folder_outlined
                          : Icons.insert_drive_file_outlined,
                    ),
                    title: Text(child.name),
                    subtitle: Text(child.id),
                    enabled: child.isFolder,
                    onTap: child.isFolder ? () => _openFolder(child) : null,
                  ),
              if (_loadingMedia)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_mediaFiles.isNotEmpty) ...<Widget>[
                const Divider(height: 32),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Videos',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _copyingMedia ? null : _copyFirstVideo,
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy first'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _copyingMedia ? null : _copyFirstVideosBatch,
                      icon: const Icon(Icons.file_copy_outlined),
                      label: const Text('Batch first 5'),
                    ),
                  ],
                ),
                if (_copyingMedia || _copyProgress != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _CopyProgressView(
                      progress: _copyProgress,
                      onCancel: _copyingMedia && !_copyCancelRequested
                          ? _cancelCopy
                          : null,
                    ),
                  ),
                if (_copyStats != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: SelectableText(_copyStats!),
                  ),
                for (final file in _mediaFiles)
                  ListTile(
                    leading: const Icon(Icons.movie_outlined),
                    title: Text(file.name),
                    subtitle: Text('${file.size} bytes\n${file.id}'),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _CopyProgressView extends StatelessWidget {
  const _CopyProgressView({required this.progress, required this.onCancel});

  final MtpCopyProgress? progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LinearProgressIndicator(value: progress?.fraction),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                progress == null
                    ? 'Starting copy...'
                    : progress.isCancelling
                    ? 'Cancelling after active MTP transfer finishes...'
                    : 'Copying ${progress.fileName}',
              ),
            ),
            TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel'),
            ),
          ],
        ),
        if (progress != null)
          Text(
            '${_formatBytes(progress.copiedBytes)} of '
            '${_formatBytes(progress.totalBytes)}'
            '${progress.estimatedRemaining == null ? '' : ' - about ${_formatDuration(progress.estimatedRemaining!)} left'}',
          ),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} KB';
    final mib = kib / 1024;
    if (mib < 1024) return '${mib.toStringAsFixed(1)} MB';
    final gib = mib / 1024;
    return '${gib.toStringAsFixed(1)} GB';
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (minutes == 0) return '${seconds}s';
    return '${minutes}m ${seconds}s';
  }
}

class MtpCopyProgress {
  const MtpCopyProgress({
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
    if (bytesPerMillisecond <= 0) return null;

    final remainingMilliseconds =
        ((totalBytes - copiedBytes) / bytesPerMillisecond).round();
    return Duration(milliseconds: remainingMilliseconds);
  }

  MtpCopyProgress copyWith({bool? isCancelling}) {
    return MtpCopyProgress(
      fileName: fileName,
      copiedBytes: copiedBytes,
      totalBytes: totalBytes,
      elapsed: elapsed,
      isCancelling: isCancelling ?? this.isCancelling,
    );
  }
}

class _MtpCopyResult {
  const _MtpCopyResult({required this.elapsed});

  final Duration elapsed;
}

class _MtpCopyCancelledException implements Exception {
  const _MtpCopyCancelledException();
}
