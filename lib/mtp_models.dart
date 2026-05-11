class MtpDevice {
  const MtpDevice({required this.id, required this.name});

  factory MtpDevice.fromMap(Map<Object?, Object?> map) {
    return MtpDevice(id: map['id']! as String, name: map['name']! as String);
  }

  final String id;
  final String name;

  Map<String, Object?> toMap() {
    return <String, Object?>{'id': id, 'name': name};
  }

  @override
  String toString() => 'MtpDevice(id: $id, name: $name)';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MtpDevice && other.id == id && other.name == name;
  }

  @override
  int get hashCode => Object.hash(id, name);
}

class MtpObject {
  const MtpObject({
    required this.id,
    required this.name,
    required this.isFolder,
  });

  factory MtpObject.fromMap(Map<Object?, Object?> map) {
    return MtpObject(
      id: map['id']! as String,
      name: map['name']! as String,
      isFolder: map['isFolder']! as bool,
    );
  }

  final String id;
  final String name;
  final bool isFolder;

  Map<String, Object?> toMap() {
    return <String, Object?>{'id': id, 'name': name, 'isFolder': isFolder};
  }
}

class MtpFile {
  const MtpFile({required this.id, required this.name, required this.size});

  factory MtpFile.fromMap(Map<Object?, Object?> map) {
    return MtpFile(
      id: map['id']! as String,
      name: map['name']! as String,
      size: map['size']! as int,
    );
  }

  final String id;
  final String name;
  final int size;

  Map<String, Object?> toMap() {
    return <String, Object?>{'id': id, 'name': name, 'size': size};
  }
}
