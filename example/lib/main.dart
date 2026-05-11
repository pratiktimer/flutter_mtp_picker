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
                ListTile(title: Text(device.name), subtitle: Text(device.id)),
          ],
        ),
      ),
    );
  }
}
