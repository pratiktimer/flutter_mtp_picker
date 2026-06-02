import 'package:flutter/material.dart';

import 'flutter_mtp_picker_platform_interface.dart';
import 'mtp_models.dart';

class MtpFolderPicker {
  const MtpFolderPicker._();

  static Future<MtpFolderSelection?> pickFolder(
    BuildContext context, {
    List<MtpDevice>? devices,
  }) {
    return showDialog<MtpFolderSelection>(
      context: context,
      builder: (BuildContext context) {
        return _MtpFolderPickerDialog(initialDevices: devices);
      },
    );
  }

  static Future<List<MtpFolderSelection>?> pickFolders(
    BuildContext context, {
    List<MtpDevice>? devices,
  }) {
    return showDialog<List<MtpFolderSelection>>(
      context: context,
      builder: (BuildContext context) {
        return _MtpFolderPickerDialog(
          initialDevices: devices,
          allowMultiple: true,
        );
      },
    );
  }
}

class _MtpFolderPickerDialog extends StatefulWidget {
  const _MtpFolderPickerDialog({
    this.initialDevices,
    this.allowMultiple = false,
  });

  final List<MtpDevice>? initialDevices;
  final bool allowMultiple;

  @override
  State<_MtpFolderPickerDialog> createState() => _MtpFolderPickerDialogState();
}

class _MtpFolderPickerDialogState extends State<_MtpFolderPickerDialog> {
  List<MtpDevice> _devices = const <MtpDevice>[];
  List<MtpObject> _children = const <MtpObject>[];
  final List<MtpObject> _path = <MtpObject>[];
  MtpDevice? _device;
  final Map<String, MtpFolderSelection> _selectedFolders =
      <String, MtpFolderSelection>{};
  bool _loadingDevices = true;
  bool _loadingChildren = false;
  String? _error;

  MtpObject? get _currentFolder {
    final device = _device;
    if (device == null) return null;
    if (_path.isNotEmpty) return _path.last;
    return MtpObject(id: 'ROOT', name: device.name, isFolder: true);
  }

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final initialDevices = widget.initialDevices;
    if (initialDevices != null) {
      setState(() {
        _devices = initialDevices;
        _loadingDevices = false;
      });
      return;
    }

    try {
      final devices = await FlutterMtpPickerPlatform.instance.getDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loadingDevices = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _devices = const <MtpDevice>[];
        _loadingDevices = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _selectDevice(MtpDevice device) async {
    setState(() {
      _device = device;
      _children = const <MtpObject>[];
      _path.clear();
      _selectedFolders.clear();
      _loadingChildren = true;
      _error = null;
    });

    await _loadChildren('ROOT');
  }

  Future<void> _openFolder(MtpObject folder) async {
    if (!folder.isFolder) return;

    setState(() {
      _path.add(folder);
      _children = const <MtpObject>[];
      _loadingChildren = true;
      _error = null;
    });

    await _loadChildren(folder.id);
  }

  Future<void> _goBack() async {
    if (_device == null || _path.isEmpty) return;

    setState(() {
      _path.removeLast();
      _children = const <MtpObject>[];
      _loadingChildren = true;
      _error = null;
    });

    await _loadChildren(_path.isEmpty ? 'ROOT' : _path.last.id);
  }

  Future<void> _loadChildren(String objectId) async {
    final device = _device;
    if (device == null) return;

    try {
      final children = await FlutterMtpPickerPlatform.instance.listChildren(
        deviceId: device.id,
        objectId: objectId,
      );
      if (!mounted) return;
      setState(() {
        _children = children
            .where((MtpObject object) => object.isFolder)
            .toList(growable: false);
        _loadingChildren = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _children = const <MtpObject>[];
        _loadingChildren = false;
        _error = error.toString();
      });
    }
  }

  void _chooseCurrentFolder() {
    final device = _device;
    final folder = _currentFolder;
    if (device == null || folder == null) return;

    Navigator.of(
      context,
    ).pop(MtpFolderSelection(device: device, folder: folder));
  }

  void _chooseSelectedFolders() {
    Navigator.of(context).pop(
      _selectedFolders.values.toList(growable: false),
    );
  }

  void _toggleFolder(MtpObject folder, bool selected) {
    final device = _device;
    if (device == null) return;

    setState(() {
      final key = _selectionKey(device, folder);
      if (selected) {
        _selectedFolders[key] = MtpFolderSelection(
          device: device,
          folder: folder,
        );
      } else {
        _selectedFolders.remove(key);
      }
    });
  }

  bool _isSelected(MtpObject folder) {
    final device = _device;
    if (device == null) return false;
    return _selectedFolders.containsKey(_selectionKey(device, folder));
  }

  static String _selectionKey(MtpDevice device, MtpObject folder) {
    return '${device.id}:${folder.id}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Column(
          children: <Widget>[
            _Header(
              device: _device,
              path: _path,
              selectedCount: _selectedFolders.length,
              canGoBack: _path.isNotEmpty && !_loadingChildren,
              onBack: _goBack,
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(context)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _device == null || _loadingChildren
                        ? null
                        : widget.allowMultiple
                            ? _selectedFolders.isEmpty
                                  ? null
                                  : _chooseSelectedFolders
                            : _chooseCurrentFolder,
                    child: Text(
                      widget.allowMultiple
                          ? 'Choose ${_selectedFolders.length} folders'
                          : 'Choose folder',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingDevices) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    if (_device == null) {
      if (_devices.isEmpty) {
        return const Center(child: Text('No MTP devices connected.'));
      }

      return ListView.builder(
        itemCount: _devices.length,
        itemBuilder: (BuildContext context, int index) {
          final device = _devices[index];
          return ListTile(
            leading: const Icon(Icons.phone_android_outlined),
            title: Text(device.name),
            subtitle: Text(device.id),
            onTap: () => _selectDevice(device),
          );
        },
      );
    }

    if (_loadingChildren) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_children.isEmpty && !widget.allowMultiple) {
      return const Center(child: Text('No folders here.'));
    }

    return ListView.builder(
      itemCount: _children.length + (widget.allowMultiple ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (widget.allowMultiple && index == 0) {
          final current = _currentFolder;
          if (current == null) return const SizedBox.shrink();

          return CheckboxListTile(
            secondary: const Icon(Icons.folder_special_outlined),
            title: Text(
              _path.isEmpty ? 'Select device root' : 'Select current folder',
            ),
            subtitle: Text(current.name),
            value: _isSelected(current),
            onChanged: (bool? value) {
              _toggleFolder(current, value ?? false);
            },
          );
        }

        final childIndex = widget.allowMultiple ? index - 1 : index;
        if (_children.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No folders here.')),
          );
        }

        final child = _children[childIndex];
        if (!widget.allowMultiple) {
          return ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(child.name),
            subtitle: Text(child.id),
            onTap: () => _openFolder(child),
          );
        }

        return CheckboxListTile(
          secondary: IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Open folder',
            onPressed: () => _openFolder(child),
          ),
          title: Text(child.name),
          subtitle: Text(child.id),
          value: _isSelected(child),
          onChanged: (bool? value) {
            _toggleFolder(child, value ?? false);
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.device,
    required this.path,
    required this.selectedCount,
    required this.canGoBack,
    required this.onBack,
  });

  final MtpDevice? device;
  final List<MtpObject> path;
  final int selectedCount;
  final bool canGoBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final title = device == null
        ? 'Select MTP device'
        : path.isEmpty
            ? device!.name
            : path.map((MtpObject folder) => folder.name).join(' / ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: canGoBack ? onBack : null,
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (selectedCount > 0)
                  Text(
                    '$selectedCount selected',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
