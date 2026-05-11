import 'package:flutter/material.dart';
import 'dart:async';

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
  final List<MtpObject> _path = <MtpObject>[];
  bool _loadingChildren = false;
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
      _path.clear();
      _loadingChildren = true;
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
      _loadingChildren = true;
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
      _loadingChildren = true;
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('MTP devices')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
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
            ],
          ],
        ),
      ),
    );
  }
}
