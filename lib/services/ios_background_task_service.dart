import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mangayomi/utils/log/logger.dart';

class IosBackgroundTaskService {
  IosBackgroundTaskService._();

  static const MethodChannel _channel = MethodChannel(
    'com.kodjodevf.mangayomi.background_task',
  );

  static Future<String?> begin(String name) async {
    if (!Platform.isIOS) {
      return null;
    }

    try {
      return await _channel.invokeMethod<String>('begin', {'name': name});
    } catch (e) {
      AppLogger.log(
        'Failed to begin iOS background task: $e',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  static Future<void> end(String? identifier) async {
    if (!Platform.isIOS || identifier == null) {
      return;
    }

    try {
      await _channel.invokeMethod('end', {'identifier': identifier});
    } catch (e) {
      AppLogger.log(
        'Failed to end iOS background task: $e',
        logLevel: LogLevel.warning,
      );
    }
  }
}
