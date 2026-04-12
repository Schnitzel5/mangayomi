import 'dart:async';
import 'dart:io';

import 'package:mangayomi/utils/log/logger.dart';

const String libraryUpdateCancelScopeAll = 'all';
const Duration _libraryUpdateCancelMaxAge = Duration(hours: 3);

class LibraryUpdateCancelToken {
  final String scope;
  bool _cancelled = false;

  LibraryUpdateCancelToken(this.scope);

  Future<void> cancel() async {
    _cancelled = true;
    await LibraryUpdateCancelService.requestCancel(scope);
  }

  Future<bool> get isCancelled async {
    if (_cancelled) {
      return true;
    }
    return LibraryUpdateCancelService.isCancelRequested(scope);
  }

  Future<void> clear() async {
    _cancelled = false;
    await LibraryUpdateCancelService.clear(scope);
  }
}

class LibraryUpdateCancelService {
  LibraryUpdateCancelService._();

  static Future<void> requestCancel(String? scope) async {
    final signal = _signalFile(_normalizeScope(scope));
    try {
      await signal.writeAsString(
        '${DateTime.now().millisecondsSinceEpoch}\n$pid\n',
        flush: true,
      );
    } catch (e, stackTrace) {
      AppLogger.log(
        'Failed to request library update cancellation: $e\n$stackTrace',
        logLevel: LogLevel.error,
      );
    }
  }

  static Future<bool> isCancelRequested(String scope) async {
    return await _existsAndIsFresh(_signalFile(scope)) ||
        await _existsAndIsFresh(_signalFile(libraryUpdateCancelScopeAll));
  }

  static Future<void> clear(String scope) async {
    await _deleteIfExists(_signalFile(scope));
  }

  static String _normalizeScope(String? scope) {
    final normalized = scope?.trim();
    return normalized?.isNotEmpty == true
        ? normalized!
        : libraryUpdateCancelScopeAll;
  }

  static File _signalFile(String scope) {
    final safeScope = scope.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    return File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'mangayomi_library_update_cancel_$safeScope.signal',
    );
  }

  static Future<bool> _existsAndIsFresh(File file) async {
    if (!await file.exists()) {
      return false;
    }
    final stat = await file.stat();
    if (DateTime.now().difference(stat.modified) > _libraryUpdateCancelMaxAge) {
      await _deleteIfExists(file);
      return false;
    }
    return true;
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, stackTrace) {
      AppLogger.log(
        'Failed to clear library update cancellation signal: $e\n$stackTrace',
        logLevel: LogLevel.error,
      );
    }
  }
}
