import 'dart:io';

import 'package:flutter/services.dart';

class LocalDirectoryAccess {
  static const _channel = MethodChannel(
    'com.kodjodevf.mangayomi.local_directory_access',
  );

  static Future<String?> pickDirectory() async {
    if (!Platform.isIOS) return null;
    return _channel.invokeMethod<String>('pickDirectory');
  }

  static Future<String?> startAccessing(String path) async {
    if (!Platform.isIOS) return path;
    try {
      final result = await _channel.invokeMethod<String>('startAccessing', {
        'path': path,
      });
      return result ?? path;
    } catch (_) {
      return path;
    }
  }

  static Future<void> stopAccessing(String path) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('stopAccessing', {'path': path});
    } catch (_) {}
  }

  static Future<List<LocalDirectoryEntry>?> listDirectory(String path) async {
    if (!Platform.isIOS) return null;
    final result = await _channel.invokeMethod<List<dynamic>>('listDirectory', {
      'path': path,
    });
    if (result == null) return null;
    return result
        .whereType<Map>()
        .map(
          (entry) => LocalDirectoryEntry(
            path: entry['path'] as String? ?? '',
            type: entry['type'] as String? ?? 'other',
          ),
        )
        .where((entry) => entry.path.isNotEmpty)
        .toList();
  }
}

class LocalDirectoryEntry {
  final String path;
  final String type;

  const LocalDirectoryEntry({required this.path, required this.type});

  bool get isDirectory => type == 'directory';
  bool get isFile => type == 'file';
}
