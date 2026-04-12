import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mangayomi/services/library_update_cancel_service.dart';

const int backgroundLibraryUpdateNotificationId = 1001;
const String _backgroundLibraryUpdateChannelId = 'library_updates';
const String _backgroundLibraryUpdateChannelName = 'Background library updates';
const String _backgroundLibraryUpdateChannelDescription =
    'Shows progress for background library updates.';
const String _backgroundLibraryUpdateIcon = 'ic_stat_library_update';
const String _backgroundLibraryUpdateCategory = 'library_update_progress';
const String _cancelLibraryUpdateActionId = 'cancel_library_update';

@pragma('vm:entry-point')
void backgroundUpdateNotificationResponseDispatcher(
  NotificationResponse response,
) {
  BackgroundUpdateNotificationService.handleNotificationResponse(response);
}

class BackgroundUpdateNotificationService {
  BackgroundUpdateNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    final initializationSettings = InitializationSettings(
      android: const AndroidInitializationSettings(
        _backgroundLibraryUpdateIcon,
      ),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            _backgroundLibraryUpdateCategory,
            actions: [
              DarwinNotificationAction.plain(
                _cancelLibraryUpdateActionId,
                'Cancel',
                options: {DarwinNotificationActionOption.destructive},
              ),
            ],
          ),
        ],
      ),
    );

    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          backgroundUpdateNotificationResponseDispatcher,
    );
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _backgroundLibraryUpdateChannelId,
              _backgroundLibraryUpdateChannelName,
              description: _backgroundLibraryUpdateChannelDescription,
              importance: Importance.defaultImportance,
              playSound: false,
              enableVibration: false,
            ),
          );
    }
    _initialized = true;
  }

  static void handleNotificationResponse(NotificationResponse response) {
    if (response.actionId == _cancelLibraryUpdateActionId) {
      unawaited(LibraryUpdateCancelService.requestCancel(response.payload));
    }
  }

  static Future<bool> ensurePermissions() async {
    await initialize();

    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }

    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: false) ??
          false;
    }

    return false;
  }

  static Future<void> showLibraryUpdateProgress({
    required int current,
    required int total,
    required int failed,
    String? currentTitle,
    String? cancelScope,
  }) async {
    await initialize();
    await _plugin.show(
      backgroundLibraryUpdateNotificationId,
      'Updating library',
      _progressBody(
        current: current,
        total: total,
        failed: failed,
        currentTitle: currentTitle,
      ),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _backgroundLibraryUpdateChannelId,
          _backgroundLibraryUpdateChannelName,
          channelDescription: _backgroundLibraryUpdateChannelDescription,
          icon: _backgroundLibraryUpdateIcon,
          channelAction: AndroidNotificationChannelAction.createIfNotExists,
          category: AndroidNotificationCategory.progress,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: total,
          progress: current,
          ongoing: true,
          autoCancel: false,
          playSound: false,
          enableVibration: false,
          indeterminate: false,
          actions: cancelScope == null
              ? null
              : [
                  AndroidNotificationAction(
                    _cancelLibraryUpdateActionId,
                    'Cancel',
                    showsUserInterface: false,
                    cancelNotification: false,
                  ),
                ],
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
          threadIdentifier: _backgroundLibraryUpdateChannelId,
          categoryIdentifier: cancelScope == null
              ? null
              : _backgroundLibraryUpdateCategory,
        ),
      ),
      payload: cancelScope,
    );
  }

  static Future<void> showLibraryUpdateCanceled({
    required int completed,
    required int total,
    required int failed,
  }) async {
    await initialize();
    final failedText = failed == 0 ? '' : ' Failed: $failed.';
    await _plugin.show(
      backgroundLibraryUpdateNotificationId,
      'Library update canceled',
      'Stopped after $completed of $total items.$failedText',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _backgroundLibraryUpdateChannelId,
          _backgroundLibraryUpdateChannelName,
          channelDescription: _backgroundLibraryUpdateChannelDescription,
          icon: _backgroundLibraryUpdateIcon,
          channelAction: AndroidNotificationChannelAction.createIfNotExists,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          autoCancel: true,
          ongoing: false,
          playSound: false,
          enableVibration: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
          threadIdentifier: _backgroundLibraryUpdateChannelId,
        ),
      ),
    );
  }

  static Future<void> showLibraryUpdateFinished({
    required int total,
    required int failed,
  }) async {
    await initialize();
    final succeeded = total - failed;
    final body = failed == 0
        ? 'Updated $succeeded of $total items.'
        : 'Updated $succeeded of $total items. Failed: $failed.';
    await _plugin.show(
      backgroundLibraryUpdateNotificationId,
      'Library update finished',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _backgroundLibraryUpdateChannelId,
          _backgroundLibraryUpdateChannelName,
          channelDescription: _backgroundLibraryUpdateChannelDescription,
          icon: _backgroundLibraryUpdateIcon,
          channelAction: AndroidNotificationChannelAction.createIfNotExists,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          onlyAlertOnce: true,
          autoCancel: true,
          ongoing: false,
          playSound: false,
          enableVibration: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
          threadIdentifier: _backgroundLibraryUpdateChannelId,
        ),
      ),
    );
  }

  static Future<void> showLibraryUpdateFailed(String message) async {
    await initialize();
    await _plugin.show(
      backgroundLibraryUpdateNotificationId,
      'Library update failed',
      message,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _backgroundLibraryUpdateChannelId,
          _backgroundLibraryUpdateChannelName,
          channelDescription: _backgroundLibraryUpdateChannelDescription,
          icon: _backgroundLibraryUpdateIcon,
          channelAction: AndroidNotificationChannelAction.createIfNotExists,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          autoCancel: true,
          ongoing: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
          threadIdentifier: _backgroundLibraryUpdateChannelId,
        ),
      ),
    );
  }

  static String _progressBody({
    required int current,
    required int total,
    required int failed,
    String? currentTitle,
  }) {
    final progress = '$current/$total';
    final failedText = failed == 0 ? '' : ' Failed: $failed.';
    final titleText = (currentTitle?.trim().isNotEmpty ?? false)
        ? ' Current: $currentTitle.'
        : '';
    return 'Progress: $progress.$failedText$titleText';
  }
}
