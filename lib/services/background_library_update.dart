import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/providers/storage_provider.dart';
import 'package:mangayomi/services/isolate_service.dart';
import 'package:mangayomi/services/library_updater.dart';
import 'package:mangayomi/services/library_update_cancel_service.dart';
import 'package:mangayomi/services/background_update_notification_service.dart';
import 'package:mangayomi/src/rust/frb_generated.dart';
import 'package:mangayomi/utils/log/logger.dart';
import 'package:workmanager/workmanager.dart';

const int backgroundLibraryUpdateOff = 0;
const int backgroundLibraryUpdateEvery6Hours = 6;
const int backgroundLibraryUpdateEvery12Hours = 12;

const String backgroundLibraryUpdateTaskName =
    'com.kodjodevf.mangayomi.background_library_update';
const String backgroundLibraryUpdateUniqueName =
    backgroundLibraryUpdateTaskName;
const String _legacyBackgroundLibraryUpdateUniqueName =
    'background-library-update';

@pragma('vm:entry-point')
void backgroundLibraryUpdateDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case backgroundLibraryUpdateTaskName:
      case Workmanager.iOSBackgroundTask:
        return _runBackgroundLibraryUpdateTask();
      default:
        return true;
    }
  });
}

class BackgroundLibraryUpdateScheduler {
  static bool _isInitialized = false;

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static Future<void> initialize() async {
    if (!isSupported || _isInitialized) {
      return;
    }
    await Workmanager().initialize(backgroundLibraryUpdateDispatcher);
    _isInitialized = true;
  }

  static Future<void> syncWithSettings() async {
    if (!isSupported) {
      return;
    }

    await initialize();
    await Workmanager().cancelByUniqueName(
      _legacyBackgroundLibraryUpdateUniqueName,
    );
    final intervalHours =
        isar.settings.getSync(227)!.backgroundLibraryUpdateIntervalHours ??
        backgroundLibraryUpdateOff;
    if (intervalHours == backgroundLibraryUpdateOff) {
      await Workmanager().cancelByUniqueName(backgroundLibraryUpdateUniqueName);
      return;
    }

    await Workmanager().registerPeriodicTask(
      backgroundLibraryUpdateUniqueName,
      backgroundLibraryUpdateTaskName,
      frequency: Duration(hours: intervalHours),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresStorageNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      inputData: {'intervalHours': intervalHours},
    );
  }
}

Future<bool> _runBackgroundLibraryUpdateTask() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  await RustLib.init();

  isar = await StorageProvider().initDB(null, inspector: kDebugMode);
  await AppLogger.init();
  await BackgroundUpdateNotificationService.initialize();
  customDns = isar.settings.getSync(227)?.customDns ?? "";
  await getIsolateService.start();

  final settings = isar.settings.getSync(227)!;
  final intervalHours =
      settings.backgroundLibraryUpdateIntervalHours ??
      backgroundLibraryUpdateOff;
  if (intervalHours == backgroundLibraryUpdateOff) {
    AppLogger.log("Background library update is disabled.");
    return true;
  }

  final now = DateTime.now();
  final lastRunAt = settings.lastBackgroundLibraryUpdateAt;
  if (lastRunAt != null) {
    final elapsed = now.difference(
      DateTime.fromMillisecondsSinceEpoch(lastRunAt),
    );
    if (elapsed < Duration(hours: intervalHours)) {
      AppLogger.log(
        "Skipping background library update; next run is not due yet.",
      );
      return true;
    }
  }

  final container = ProviderContainer();
  final cancelToken = LibraryUpdateCancelToken(libraryUpdateCancelScopeAll);
  try {
    await cancelToken.clear();
    int totalCandidates = 0;
    for (final itemType in ItemType.values) {
      totalCandidates += getFavoriteLibraryMangas(itemType).length;
    }
    if (totalCandidates == 0) {
      AppLogger.log("No favorite library entries found for background update.");
      return true;
    }

    await BackgroundUpdateNotificationService.showLibraryUpdateProgress(
      current: 0,
      total: totalCandidates,
      failed: 0,
      cancelScope: cancelToken.scope,
    );

    isar.writeTxnSync(
      () => isar.settings.putSync(
        settings
          ..lastBackgroundLibraryUpdateAt = now.millisecondsSinceEpoch
          ..updatedAt = now.millisecondsSinceEpoch,
      ),
    );

    int completed = 0;
    int failed = 0;
    for (final itemType in ItemType.values) {
      final mangas = getFavoriteLibraryMangas(itemType);
      final result = await updateLibraryCore(
        read: container.read,
        mangaList: mangas,
        itemType: itemType,
        cancelToken: cancelToken,
        onProgress: (current, typeFailed, total, manga) async {
          await BackgroundUpdateNotificationService.showLibraryUpdateProgress(
            current: completed + current,
            total: totalCandidates,
            failed: failed + typeFailed,
            currentTitle: manga.name,
            cancelScope: cancelToken.scope,
          );
        },
      );
      completed += result.attempted;
      failed += result.failed;
      if (result.canceled) {
        AppLogger.log("Background library update canceled.");
        await BackgroundUpdateNotificationService.showLibraryUpdateCanceled(
          completed: completed,
          total: totalCandidates,
          failed: failed,
        );
        return true;
      }
      AppLogger.log(
        "Background ${formatItemTypeLabel(itemType)} update finished: "
        "${result.attempted - result.failed}/${result.attempted} succeeded.",
      );
    }

    await BackgroundUpdateNotificationService.showLibraryUpdateFinished(
      total: totalCandidates,
      failed: failed,
    );

    return true;
  } catch (e, stackTrace) {
    AppLogger.log(
      "Background library update failed: $e\n$stackTrace",
      logLevel: LogLevel.error,
    );
    await BackgroundUpdateNotificationService.showLibraryUpdateFailed(
      e.toString(),
    );
    return true;
  } finally {
    await cancelToken.clear();
    container.dispose();
    await getIsolateService.stop();
  }
}
