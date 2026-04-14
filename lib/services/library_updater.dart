import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/eval/model/m_bridge.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/modules/manga/detail/providers/update_manga_detail_providers.dart';
import 'package:mangayomi/modules/more/settings/appearance/providers/theme_mode_state_provider.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/services/library_update_cancel_service.dart';
import 'package:mangayomi/services/background_update_notification_service.dart';
import 'package:mangayomi/services/ios_background_task_service.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';
import 'package:mangayomi/utils/log/logger.dart';
import 'package:mangayomi/models/manga.dart';

typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);
typedef LibraryUpdateProgressCallback =
    FutureOr<void> Function(int current, int failed, int total, Manga manga);

const Duration libraryUpdateRequestInterval = Duration(seconds: 2);
const Duration _libraryUpdateLockMaxAge = Duration(hours: 3);

final Set<ItemType> _runningLibraryUpdates = {};

String libraryUpdateCancelScopeForItemType(ItemType itemType) =>
    'item_${itemType.name}';

class LibraryUpdateResult {
  final int attempted;
  final int failed;
  final List<String> failedTitles;
  final bool skipped;
  final bool canceled;

  const LibraryUpdateResult({
    required this.attempted,
    required this.failed,
    required this.failedTitles,
    this.skipped = false,
    this.canceled = false,
  });

  bool get hasFailures => failedTitles.isNotEmpty;
}

class LibraryUpdateLock {
  final File file;
  bool _released = false;

  LibraryUpdateLock._(this.file);

  Future<void> release() async {
    if (_released) {
      return;
    }
    _released = true;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, stackTrace) {
      AppLogger.log(
        "Failed to release library update lock: $e\n$stackTrace",
        logLevel: LogLevel.error,
      );
    }
  }
}

Future<LibraryUpdateLock?> _tryAcquireLibraryUpdateLock(
  ItemType itemType,
) async {
  final lockFile = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'mangayomi_library_update_${itemType.name}.lock',
  );
  try {
    if (await lockFile.exists()) {
      final stat = await lockFile.stat();
      if (DateTime.now().difference(stat.modified) > _libraryUpdateLockMaxAge) {
        await lockFile.delete();
      }
    }
    await lockFile.create(exclusive: true);
    await lockFile.writeAsString(
      '${DateTime.now().millisecondsSinceEpoch}\n$pid\n',
    );
    return LibraryUpdateLock._(lockFile);
  } on FileSystemException {
    return null;
  }
}

Future<bool> _delayUntilNextLibraryRequest(
  DateTime requestStartedAt,
  Duration requestInterval,
  LibraryUpdateCancelToken? cancelToken,
) async {
  if (requestInterval <= Duration.zero) {
    return await cancelToken?.isCancelled ?? false;
  }
  final elapsed = DateTime.now().difference(requestStartedAt);
  final remaining = requestInterval - elapsed;
  var pending = remaining;
  while (pending > Duration.zero) {
    if (await cancelToken?.isCancelled ?? false) {
      return true;
    }
    final delay = pending > const Duration(milliseconds: 250)
        ? const Duration(milliseconds: 250)
        : pending;
    await Future.delayed(delay);
    pending -= delay;
  }
  return await cancelToken?.isCancelled ?? false;
}

List<Manga> getFavoriteLibraryMangas(ItemType itemType) {
  return isar.mangas
      .filter()
      .idIsNotNull()
      .favoriteEqualTo(true)
      .and()
      .itemTypeEqualTo(itemType)
      .and()
      .isLocalArchiveEqualTo(false)
      .findAllSync();
}

String formatItemTypeLabel(ItemType itemType) {
  return itemType.name[0].toUpperCase() + itemType.name.substring(1);
}

Future<LibraryUpdateResult> updateLibraryCore({
  required ProviderReader read,
  required List<Manga> mangaList,
  required ItemType itemType,
  LibraryUpdateProgressCallback? onProgress,
  Duration requestInterval = libraryUpdateRequestInterval,
  LibraryUpdateLock? updateLock,
  LibraryUpdateCancelToken? cancelToken,
}) async {
  final itemtype = formatItemTypeLabel(itemType);
  AppLogger.log("Starting $itemtype library update...");
  if (mangaList.isEmpty) {
    AppLogger.log("$itemtype library is empty. Nothing to update.");
    return const LibraryUpdateResult(attempted: 0, failed: 0, failedTitles: []);
  }

  final lock = updateLock ?? await _tryAcquireLibraryUpdateLock(itemType);
  if (lock == null) {
    AppLogger.log(
      "$itemtype library update is already running. Skipping duplicate run.",
    );
    return const LibraryUpdateResult(
      attempted: 0,
      failed: 0,
      failedTitles: [],
      skipped: true,
    );
  }

  try {
    int failed = 0;
    int attempted = 0;
    final failedMangas = <String>[];
    for (var i = 0; i < mangaList.length; i++) {
      if (await cancelToken?.isCancelled ?? false) {
        AppLogger.log("$itemtype library update canceled.");
        return LibraryUpdateResult(
          attempted: attempted,
          failed: failed,
          failedTitles: failedMangas,
          canceled: true,
        );
      }
      final requestStartedAt = DateTime.now();
      final manga = mangaList[i];
      try {
        await read(
          updateMangaDetailProvider(
            mangaId: manga.id,
            isInit: false,
            showToast: false,
          ).future,
        );
      } catch (e) {
        AppLogger.log("Failed to update $itemtype:", logLevel: LogLevel.error);
        AppLogger.log(e.toString(), logLevel: LogLevel.error);
        failed++;
        failedMangas.add(manga.name ?? "Unknown $itemtype");
      }
      attempted++;
      await onProgress?.call(i + 1, failed, mangaList.length, manga);
      if (i < mangaList.length - 1) {
        final canceled = await _delayUntilNextLibraryRequest(
          requestStartedAt,
          requestInterval,
          cancelToken,
        );
        if (canceled) {
          AppLogger.log("$itemtype library update canceled.");
          return LibraryUpdateResult(
            attempted: attempted,
            failed: failed,
            failedTitles: failedMangas,
            canceled: true,
          );
        }
      }
    }

    return LibraryUpdateResult(
      attempted: mangaList.length,
      failed: failed,
      failedTitles: failedMangas,
    );
  } finally {
    await lock.release();
  }
}

Future<void> updateLibrary({
  required WidgetRef ref,
  required BuildContext context,
  required List<Manga> mangaList,
  required ItemType itemType,
}) async {
  if (mangaList.isEmpty) {
    return;
  }

  final itemtype = formatItemTypeLabel(itemType);
  if (_runningLibraryUpdates.contains(itemType)) {
    botToast(
      "$itemtype library update is already running.",
      fontSize: 13,
      second: 3,
      themeDark: ref.read(themeModeStateProvider),
    );
    return;
  }
  final read = ProviderScope.containerOf(context, listen: false).read;
  final progressMessage = context.l10n.updating_library;
  final isDark = ref.read(themeModeStateProvider);
  final initialMessage = progressMessage("0", "0", "0");
  final double alignY = !context.isTablet ? 0.85 : 1.0;
  final showNotifications = Platform.isAndroid || Platform.isIOS;
  var notificationsEnabled = showNotifications;
  _runningLibraryUpdates.add(itemType);
  final lock = await _tryAcquireLibraryUpdateLock(itemType);
  if (lock == null) {
    _runningLibraryUpdates.remove(itemType);
    botToast(
      "$itemtype library update is already running.",
      fontSize: 13,
      second: 3,
      alignY: alignY,
      themeDark: isDark,
    );
    return;
  }
  final cancelToken = LibraryUpdateCancelToken(
    libraryUpdateCancelScopeForItemType(itemType),
  );
  await cancelToken.clear();
  if (showNotifications) {
    try {
      await BackgroundUpdateNotificationService.initialize();
      notificationsEnabled =
          await BackgroundUpdateNotificationService.ensurePermissions();
      if (notificationsEnabled) {
        await BackgroundUpdateNotificationService.showLibraryUpdateProgress(
          current: 0,
          total: mangaList.length,
          failed: 0,
          cancelScope: cancelToken.scope,
        );
      }
    } catch (e, stackTrace) {
      notificationsEnabled = false;
      AppLogger.log(
        "Failed to prepare library update notification: "
        "$e\n$stackTrace",
        logLevel: LogLevel.error,
      );
    }
  }

  botToast(
    initialMessage,
    fontSize: 13,
    second: showNotifications ? 3 : 30,
    alignY: alignY,
    themeDark: isDark,
    actionLabel: "Cancel",
    onAction: () => unawaited(cancelToken.cancel()),
  );

  unawaited(
    _runLibraryUpdateInBackground(
      read: read,
      mangaList: List<Manga>.of(mangaList),
      itemType: itemType,
      itemtype: itemtype,
      updateLock: lock,
      cancelToken: cancelToken,
      showNotifications: notificationsEnabled,
      progressMessage: progressMessage,
      alignY: alignY,
      isDark: isDark,
    ).whenComplete(() => _runningLibraryUpdates.remove(itemType)),
  );
}

Future<void> _runLibraryUpdateInBackground({
  required ProviderReader read,
  required List<Manga> mangaList,
  required ItemType itemType,
  required String itemtype,
  required LibraryUpdateLock updateLock,
  required LibraryUpdateCancelToken cancelToken,
  required bool showNotifications,
  required String Function(Object cur, Object failed, Object max)
  progressMessage,
  required double alignY,
  required bool isDark,
}) async {
  VoidCallback? cancelProgressToast;
  final iosBackgroundTaskId = await IosBackgroundTaskService.begin(
    '$itemtype library update',
  );
  try {
    final result = await updateLibraryCore(
      read: read,
      mangaList: mangaList,
      itemType: itemType,
      updateLock: updateLock,
      cancelToken: cancelToken,
      onProgress: (current, failed, total, manga) async {
        if (showNotifications) {
          await BackgroundUpdateNotificationService.showLibraryUpdateProgress(
            current: current,
            total: total,
            failed: failed,
            currentTitle: manga.name,
            cancelScope: cancelToken.scope,
          );
        }
        cancelProgressToast?.call();
        cancelProgressToast = botToast(
          progressMessage(current, failed, total),
          fontSize: 13,
          second: 10,
          alignY: alignY,
          animationDuration: 0,
          dismissDirections: [DismissDirection.none],
          onlyOne: false,
          themeDark: isDark,
          actionLabel: "Cancel",
          onAction: () => unawaited(cancelToken.cancel()),
        );
      },
    );

    if (result.skipped) {
      cancelProgressToast?.call();
      if (!showNotifications) {
        botToast(
          "$itemtype library update is already running.",
          fontSize: 13,
          second: 3,
          alignY: alignY,
          themeDark: isDark,
        );
      }
      return;
    }

    if (result.canceled) {
      cancelProgressToast?.call();
      if (showNotifications) {
        await BackgroundUpdateNotificationService.showLibraryUpdateCanceled(
          completed: result.attempted,
          total: mangaList.length,
          failed: result.failed,
        );
      } else {
        botToast(
          "$itemtype library update canceled.",
          fontSize: 13,
          second: 3,
          alignY: alignY,
          themeDark: isDark,
        );
      }
      return;
    }

    await Future.delayed(const Duration(seconds: 1));
    cancelProgressToast?.call();
    if (showNotifications) {
      await BackgroundUpdateNotificationService.showLibraryUpdateFinished(
        total: mangaList.length,
        failed: result.failed,
      );
    } else if (result.hasFailures) {
      final failedListText = result.failedTitles.map((m) => "• $m").join('\n');
      final plural = result.failed == 1 ? itemtype : "${itemtype}s";
      botToast(
        "Failed to update ${result.failed} $plural:\n$failedListText",
        fontSize: 13,
        second: 10,
        alignY: alignY,
        themeDark: isDark,
      );
    }
  } catch (e, stackTrace) {
    cancelProgressToast?.call();
    AppLogger.log(
      "Library update failed: $e\n$stackTrace",
      logLevel: LogLevel.error,
    );
    if (showNotifications) {
      await BackgroundUpdateNotificationService.showLibraryUpdateFailed(
        e.toString(),
      );
    } else {
      botToast(
        "Library update failed: $e",
        fontSize: 13,
        second: 10,
        alignY: alignY,
        themeDark: isDark,
      );
    }
  } finally {
    await IosBackgroundTaskService.end(iosBackgroundTaskId);
    await cancelToken.clear();
  }
}
