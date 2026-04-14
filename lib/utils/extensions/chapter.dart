import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/download.dart';
import 'package:mangayomi/modules/library/providers/file_scanner.dart';
import 'package:mangayomi/modules/manga/reader/providers/push_router.dart';
import 'package:mangayomi/modules/manga/reader/providers/reader_controller_provider.dart';
import 'package:mangayomi/providers/storage_provider.dart';
import 'package:mangayomi/services/download_manager/download_isolate_pool.dart';
import 'package:mangayomi/services/download_manager/m_downloader.dart';
import 'package:mangayomi/utils/extensions/string_extensions.dart';
import 'package:path/path.dart' as p;

extension ChapterExtension on Chapter {
  Future<void> pushToReaderView(
    BuildContext context, {
    bool ignoreIsRead = false,
  }) async {
    if (ignoreIsRead || !isRead!) {
      await pushMangaReaderView(context: context, chapter: this);
    } else {
      final filteredChaps = manga.value!.getFilteredChapterList();
      bool exist = false;
      for (var filteredChap in filteredChaps.reversed) {
        if (filteredChap.toJson().toString() == toJson().toString()) {
          exist = true;
        }
        if (exist && !filteredChap.isRead!) {
          await pushMangaReaderView(context: context, chapter: filteredChap);
          break;
        }
      }
    }
  }

  void cancelDownloads(int? downloadId) {
    // Cancel via the Isolate pool (new system)
    DownloadIsolatePool.instance.cancelTask('$id');
    DownloadIsolatePool.instance.cancelTask('m3u8_$id');

    // Clean the map for compatibility
    isolateChapsSendPorts.remove('$id');

    isar.writeTxnSync(() {
      isar.downloads.deleteSync(id!);
      if (downloadId != null) {
        isar.downloads.deleteSync(downloadId);
      }
    });
  }

  Future<void> deleteDownloadedFiles() async {
    final download = isar.downloads.getSync(id!);
    if (download == null) return;

    final storageProvider = StorageProvider();
    final chapterName = name!.replaceForbiddenCharacters(' ');
    final folders = await getAllLocalFolders();
    for (final folder in folders) {
      final folderPath = folder.path;
      if (folderPath == null || folderPath.isEmpty) continue;
      final mangaDir = Directory(
        p.join(folderPath, manga.value!.name!.replaceForbiddenCharacters('_')),
      );
      final chapterDir = await storageProvider.getMangaChapterDirectory(
        this,
        mangaMainDirectory: mangaDir,
      );

      for (final entity in [
        File(p.join(mangaDir.path, "$name.cbz")),
        File(p.join(mangaDir.path, "$chapterName.cbz")),
        File(p.join(mangaDir.path, "$chapterName.mp4")),
        File(p.join(mangaDir.path, "$name.html")),
        File(p.join(chapterDir!.path, "$chapterName.html")),
        chapterDir,
      ]) {
        try {
          if (entity.existsSync()) entity.deleteSync(recursive: true);
        } catch (_) {}
      }
    }

    cancelDownloads(download.id);
  }
}
