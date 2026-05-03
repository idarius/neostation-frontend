import 'package:flutter/services.dart';
import 'smb_exceptions.dart';

/// Dart wrapper around the Kotlin SmbClientPlugin.
///
/// Lifecycle:
///   final conn = await SmbClient.connect(...);
///   try { ... } finally { await conn.disconnect(); }
class SmbClient {
  static const _channel = MethodChannel('fr.idarius.idastation/smb');

  /// Opens a connection to `smb://<host>/<share>/` with NTLMv2 auth.
  /// Throws a typed SmbException on failure. Returns a [SmbConnection]
  /// handle that owns the underlying connection id.
  static Future<SmbConnection> connect({
    required String host,
    required String share,
    required String user,
    required String pass,
    String domain = 'WORKGROUP',
  }) async {
    try {
      final id = await _channel.invokeMethod<String>('connect', {
        'host': host,
        'share': share,
        'user': user,
        'pass': pass,
        'domain': domain,
      });
      if (id == null) {
        throw const SmbUnknownException('connect returned null id');
      }
      return SmbConnection._(id);
    } on PlatformException catch (e) {
      throw smbExceptionFromCode(e.code, e.message);
    }
  }
}

class SmbConnection {
  final String _id;
  bool _closed = false;

  SmbConnection._(this._id);

  String get id => _id;
  bool get isClosed => _closed;

  Future<void> disconnect() async {
    if (_closed) return;
    _closed = true;
    try {
      await SmbClient._channel
          .invokeMethod('disconnect', {'connectionId': _id});
    } on PlatformException {
      // Swallow disconnect errors; connection is being torn down anyway.
    }
  }

  /// Returns entries directly under [path] (relative to share root).
  /// Empty list when the directory doesn't exist.
  Future<List<SmbDirEntry>> listDirectory(String path) async {
    _checkOpen();
    try {
      final raw = await SmbClient._channel
          .invokeMethod<List<Object?>>('listDirectory', {
        'connectionId': _id,
        'path': path,
      });
      return (raw ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(SmbDirEntry._fromMap)
          .toList();
    } on PlatformException catch (e) {
      throw smbExceptionFromCode(e.code, e.message);
    }
  }

  /// Returns true iff [path] points to an existing file.
  ///
  /// **Files only.** JCIFS-NG resolves directory paths only when the URL ends
  /// with a trailing slash, but this method does not auto-detect intent — pass
  /// it a file path or use [listDirectory] to probe directories.
  Future<bool> fileExists(String path) async {
    _checkOpen();
    try {
      final r = await SmbClient._channel.invokeMethod<bool>('fileExists', {
        'connectionId': _id,
        'path': path,
      });
      return r ?? false;
    } on PlatformException catch (e) {
      throw smbExceptionFromCode(e.code, e.message);
    }
  }

  /// Returns size + mtime + isDir for [path], or null when missing.
  ///
  /// **Files only** (same JCIFS-NG trailing-slash caveat as [fileExists]).
  Future<SmbStat?> stat(String path) async {
    _checkOpen();
    try {
      final m = await SmbClient._channel
          .invokeMethod<Map<Object?, Object?>?>('stat', {
        'connectionId': _id,
        'path': path,
      });
      if (m == null) return null;
      return SmbStat._fromMap(m);
    } on PlatformException catch (e) {
      throw smbExceptionFromCode(e.code, e.message);
    }
  }

  Future<void> mkdirs(String path) async {
    _checkOpen();
    try {
      await SmbClient._channel.invokeMethod('mkdirs', {
        'connectionId': _id,
        'path': path,
      });
    } on PlatformException catch (e) {
      throw smbExceptionFromCode(e.code, e.message);
    }
  }

  Future<Uint8List> readFile(String path) async {
    _checkOpen();
    try {
      final bytes = await SmbClient._channel
          .invokeMethod<Uint8List>('readFile', {
        'connectionId': _id,
        'path': path,
      });
      if (bytes == null) {
        throw const SmbUnknownException('readFile returned null');
      }
      return bytes;
    } on PlatformException catch (e) {
      throw smbExceptionFromCode(e.code, e.message);
    }
  }

  Future<void> writeFile(String path, Uint8List bytes) async {
    _checkOpen();
    try {
      await SmbClient._channel.invokeMethod('writeFile', {
        'connectionId': _id,
        'path': path,
        'bytes': bytes,
      });
    } on PlatformException catch (e) {
      throw smbExceptionFromCode(e.code, e.message);
    }
  }

  /// Deletes the file at [path].
  ///
  /// **Files only** (same JCIFS-NG trailing-slash caveat as [fileExists]).
  /// Throws [SmbPathNotFoundException] when [path] is missing.
  Future<void> delete(String path) async {
    _checkOpen();
    try {
      await SmbClient._channel.invokeMethod('delete', {
        'connectionId': _id,
        'path': path,
      });
    } on PlatformException catch (e) {
      throw smbExceptionFromCode(e.code, e.message);
    }
  }

  void _checkOpen() {
    if (_closed) {
      throw const SmbUnknownException(
          'SmbConnection has been disconnected');
    }
  }
}

class SmbDirEntry {
  final String name;
  final bool isDir;
  final int size;
  final DateTime modifiedAt;

  const SmbDirEntry({
    required this.name,
    required this.isDir,
    required this.size,
    required this.modifiedAt,
  });

  factory SmbDirEntry._fromMap(Map<Object?, Object?> m) => SmbDirEntry(
        name: m['name'] as String,
        isDir: m['isDir'] as bool,
        size: (m['size'] as num).toInt(),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['modifiedAt'] as num).toInt()),
      );
}

class SmbStat {
  final int size;
  final DateTime modifiedAt;
  final bool isDir;

  const SmbStat({
    required this.size,
    required this.modifiedAt,
    required this.isDir,
  });

  factory SmbStat._fromMap(Map<Object?, Object?> m) => SmbStat(
        size: (m['size'] as num).toInt(),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['modifiedAt'] as num).toInt()),
        isDir: m['isDir'] as bool,
      );
}
