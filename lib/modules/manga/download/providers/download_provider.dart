import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/eval/lib.dart';
import 'package:mangayomi/eval/model/m_bridge.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/page.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/download.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/models/video.dart';
import 'package:mangayomi/modules/library/providers/file_scanner.dart';
import 'package:mangayomi/modules/manga/detail/providers/export_metadata.dart';
import 'package:mangayomi/modules/manga/download/providers/convert_to_cbz.dart';
import 'package:mangayomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:mangayomi/modules/more/settings/downloads/providers/downloads_state_provider.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/providers/storage_provider.dart';
import 'package:mangayomi/router/router.dart';
import 'package:mangayomi/services/download_manager/m_downloader.dart';
import 'package:mangayomi/services/get_video_list.dart';
import 'package:mangayomi/services/get_chapter_pages.dart';
import 'package:mangayomi/services/http/m_client.dart';
import 'package:mangayomi/services/download_manager/m3u8/m3u8_downloader.dart';
import 'package:mangayomi/services/download_manager/m3u8/models/download.dart';
import 'package:mangayomi/utils/chapter_recognition.dart';
import 'package:mangayomi/utils/extensions/chapter.dart';
import 'package:mangayomi/utils/extensions/string_extensions.dart';
import 'package:mangayomi/utils/headers.dart';
import 'package:mangayomi/utils/localized_message.dart';
import 'package:mangayomi/utils/reg_exp_matcher.dart';
import 'package:mangayomi/utils/utils.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'download_provider.g.dart';

@riverpod
Future<void> addDownloadToQueue(Ref ref, {required Chapter chapter}) async {
  final download = isar.downloads.getSync(chapter.id!);
  if (download == null) {
    final download = Download(
      id: chapter.id,
      succeeded: 0,
      failed: 0,
      total: 100,
      isDownload: false,
      isStartDownload: true,
    );
    isar.writeTxnSync(() {
      isar.downloads.putSync(download..chapter.value = chapter);
    });
  }
}

@riverpod
Future<void> downloadChapter(
  Ref ref, {
  required Chapter chapter,
  bool? useWifi,
  LocalFolder? localFolder,
  VoidCallback? callback,
}) async {
  final keepAlive = ref.keepAlive();

  try {
    bool onlyOnWifi = useWifi ?? ref.read(onlyOnWifiStateProvider);
    final connectivity = await Connectivity().checkConnectivity();
    final isOnWifi =
        connectivity.contains(ConnectivityResult.wifi) ||
        connectivity.contains(ConnectivityResult.ethernet);
    if (onlyOnWifi && !isOnWifi) {
      botToast(navigatorKey.currentContext!.l10n.downloads_are_limited_to_wifi);
      keepAlive.close();
      return;
    }
    final http = MClient.init(
      reqcopyWith: {'useDartHttpClient': true, 'followRedirects': false},
    );

    List<PageUrl> pageUrls = [];
    PageUrl? novelPage;
    List<PageUrl> pages = [];
    final StorageProvider storageProvider = StorageProvider();
    await storageProvider.requestPermission();
    final manga = chapter.manga.value!;
    final itemType = manga.itemType;
    final targetLocalFolder = localFolder ?? await getDownloadLocalFolder();
    final targetPath = targetLocalFolder?.path;
    if (targetPath == null || targetPath.isEmpty) {
      botToast(
        localizedMessage(
          (l10n) => l10n.no_local_folder_available_for_downloads,
        ),
      );
      keepAlive.close();
      return;
    }
    final mangaMainDirectory = Directory(
      p.join(targetPath, manga.name!.replaceForbiddenCharacters('_')),
    );
    await storageProvider.createDirectorySafely(mangaMainDirectory.path);
    final metadataHeaders = (manga.isLocalArchive ?? false)
        ? null
        : ref.read(
            headersProvider(
              source: manga.source!,
              lang: manga.lang!,
              sourceId: manga.sourceId,
            ),
          );
    await exportMangaMetadata(
      manga: manga,
      directory: mangaMainDirectory,
      headers: metadataHeaders,
      onlyIfMissing: true,
    );
    List<Track>? subtitles;
    bool isOk = false;
    final chapterName = chapter.name!.replaceForbiddenCharacters(' ');
    final chapterDirectory = itemType == ItemType.anime
        ? Directory(p.join(mangaMainDirectory.path, chapterName))
        : (await storageProvider.getMangaChapterDirectory(
            chapter,
            mangaMainDirectory: mangaMainDirectory,
          ))!;
    if (itemType != ItemType.anime) {
      await storageProvider.createDirectorySafely(chapterDirectory.path);
    }
    final subtitleDirectoryBase = itemType == ItemType.anime
        ? p.join(mangaMainDirectory.path, chapterName)
        : chapterDirectory.path;
    Map<String, String> videoHeader = {};
    Map<String, String> htmlHeader = {
      "Priority": "u=0, i",
      "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36",
    };
    bool hasM3U8File = false;
    bool nonM3U8File = false;
    M3u8Downloader? m3u8Downloader;

    bool isMangaImageFile(String path) {
      final ext = p.extension(path).toLowerCase();
      return ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp';
    }

    Future<void> exportCoverFromDownloadedPages() async {
      if (itemType != ItemType.manga) return;
      final coverFile = File(p.join(mangaMainDirectory.path, "cover.jpg"));
      if (await coverFile.exists()) return;

      final dir = Directory(chapterDirectory.path);
      if (!await dir.exists()) return;

      final imageFiles =
          await dir
                .list()
                .where(
                  (entity) => entity is File && isMangaImageFile(entity.path),
                )
                .cast<File>()
                .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (imageFiles.isEmpty) return;

      await exportMangaCoverFromFile(
        directory: mangaMainDirectory,
        imageFile: imageFiles.first,
        onlyIfMissing: true,
      );
    }

    Future<void> deleteEmptyAnimeEpisodeDirectory() async {
      if (itemType != ItemType.anime) return;
      if (!await chapterDirectory.exists()) return;
      if (await chapterDirectory.list().isEmpty) {
        await chapterDirectory.delete();
      }
    }

    Future<void> processConvert() async {
      await exportCoverFromDownloadedPages();
      if (!ref.read(saveAsCBZArchiveStateProvider)) return;
      try {
        // Extract chapter number from name (e.g., "Chapter 5" → "5")
        final chapterNumber = ChapterRecognition().parseChapterNumber(
          chapter.manga.value!.name!,
          chapter.name!,
        );

        final comicInfo = ComicInfoData(
          title: chapter.name,
          series: manga.name,
          number: chapterNumber.toString(),
          writer: manga.author,
          penciller: manga.artist,
          summary: manga.description,
          genre: manga.genre?.join(', '),
          translator: chapter.scanlator,
          publishingStatusStr: manga.status.name,
        );

        await ref.read(
          convertToCBZProvider(
            chapterDirectory.path,
            mangaMainDirectory.path,
            chapterName,
            pages.map((e) => e.fileName!).toList(),
            comicInfo: comicInfo,
          ).future,
        );
      } catch (error) {
        botToast(localizedMessage((l10n) => l10n.failed_to_create_cbz(error)));
      }
    }

    Future<void> setProgress(DownloadProgress progress) async {
      if (progress.isCompleted && itemType == ItemType.manga) {
        await processConvert();
      }
      final download = isar.downloads.getSync(chapter.id!);
      if (download == null) {
        final download = Download(
          id: chapter.id,
          succeeded: progress.completed == 0
              ? 0
              : (progress.completed / progress.total * 100).toInt(),
          failed: 0,
          total: 100,
          isDownload: progress.isCompleted,
          isStartDownload: true,
        );
        isar.writeTxnSync(() {
          isar.downloads.putSync(download..chapter.value = chapter);
        });
      } else {
        final download = isar.downloads.getSync(chapter.id!);
        if (download != null && progress.total != 0) {
          isar.writeTxnSync(() {
            isar.downloads.putSync(
              download
                ..succeeded = progress.completed == 0
                    ? 0
                    : (progress.completed / progress.total * 100).toInt()
                ..total = 100
                ..failed = 0
                ..isDownload = progress.isCompleted,
            );
          });
        }
      }
    }

    setProgress(DownloadProgress(0, 0, itemType));
    void savePageUrls() {
      final settings = isar.settings.getSync(227)!;
      List<ChapterPageurls>? chapterPageUrls = [];
      for (var chapterPageUrl in settings.chapterPageUrlsList ?? []) {
        if (chapterPageUrl.chapterId != chapter.id) {
          chapterPageUrls.add(chapterPageUrl);
        }
      }
      final chapterPageHeaders = pageUrls
          .map((e) => e.headers == null ? null : jsonEncode(e.headers))
          .toList();
      chapterPageUrls.add(
        ChapterPageurls()
          ..chapterId = chapter.id
          ..urls = pageUrls.map((e) => e.url).toList()
          ..chapterUrl = chapter.url
          ..headers = chapterPageHeaders.first != null
              ? chapterPageHeaders.map((e) => e.toString()).toList()
              : null,
      );
      isar.writeTxnSync(
        () => isar.settings.putSync(
          settings
            ..chapterPageUrlsList = chapterPageUrls
            ..updatedAt = DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    if (itemType == ItemType.manga) {
      ref.read(getChapterPagesProvider(chapter: chapter).future).then((value) {
        if (value.pageUrls.isNotEmpty) {
          pageUrls = value.pageUrls;
          isOk = true;
        }
      });
    } else if (itemType == ItemType.anime) {
      ref.read(getVideoListProvider(episode: chapter).future).then((
        value,
      ) async {
        final m3u8Urls = value.$1
            .where(
              (element) =>
                  element.originalUrl.endsWith(".m3u8") ||
                  element.originalUrl.endsWith(".m3u"),
            )
            .toList();
        final nonM3u8Urls = value.$1
            .where((element) => element.originalUrl.isMediaVideo())
            .toList();
        nonM3U8File = nonM3u8Urls.isNotEmpty;
        hasM3U8File = nonM3U8File ? false : m3u8Urls.isNotEmpty;
        final videosUrls = nonM3U8File ? nonM3u8Urls : m3u8Urls;
        if (videosUrls.isNotEmpty) {
          subtitles = videosUrls.first.subtitles;
          if (hasM3U8File) {
            m3u8Downloader = M3u8Downloader(
              m3u8Url: videosUrls.first.url,
              downloadDir: mangaMainDirectory.path,
              headers: videosUrls.first.headers ?? {},
              subtitles: subtitles,
              subDownloadDir: subtitleDirectoryBase,
              fileName: p.join(mangaMainDirectory.path, "$chapterName.mp4"),
              chapter: chapter,
            );
          } else {
            pageUrls = [PageUrl(videosUrls.first.url)];
          }
          videoHeader.addAll(videosUrls.first.headers ?? {});
          isOk = true;
        }
      });
    } else if (itemType == ItemType.novel && chapter.url != null) {
      final manga = chapter.manga.value!;
      final source = getSource(manga.lang!, manga.source!, manga.sourceId)!;
      final chapterUrl = "${source.baseUrl}${chapter.url!.getUrlWithoutDomain}";
      final cookie = MClient.getCookiesPref(chapterUrl);
      final headers = htmlHeader;
      if (cookie.isNotEmpty) {
        final userAgent = isar.settings.getSync(227)!.userAgent!;
        headers.addAll(cookie);
        headers[HttpHeaders.userAgentHeader] = userAgent;
      }
      final res = await http.get(Uri.parse(chapterUrl), headers: headers);
      if (res.headers.containsKey("Location")) {
        novelPage = PageUrl(res.headers["Location"]!);
      } else {
        novelPage = PageUrl(chapterUrl);
      }
      isOk = true;
    }

    await Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (isOk == true) {
        return false;
      }
      return true;
    });

    if (pageUrls.isNotEmpty) {
      bool cbzFileExist =
          (await File(
                p.join(mangaMainDirectory.path, "${chapter.name}.cbz"),
              ).exists() ||
              await File(
                p.join(mangaMainDirectory.path, "$chapterName.cbz"),
              ).exists()) &&
          ref.read(saveAsCBZArchiveStateProvider);
      bool mp4FileExist = await File(
        p.join(mangaMainDirectory.path, "$chapterName.mp4"),
      ).exists();
      bool htmlFileExist = await File(
        p.join(mangaMainDirectory.path, "$chapterName.html"),
      ).exists();
      if (!cbzFileExist && itemType == ItemType.manga ||
          !mp4FileExist && itemType == ItemType.anime ||
          !htmlFileExist && itemType == ItemType.novel) {
        final mainDirectory = Directory(targetPath);
        storageProvider.createDirectorySafely(mainDirectory.path);
        for (var index = 0; index < pageUrls.length; index++) {
          if (Platform.isAndroid) {
            if (!(await File(
              p.join(mainDirectory.path, ".nomedia"),
            ).exists())) {
              await File(p.join(mainDirectory.path, ".nomedia")).create();
            }
          }
          final page = pageUrls[index];
          final cookie = MClient.getCookiesPref(page.url);
          final headers = itemType == ItemType.manga
              ? ref.read(
                  headersProvider(
                    source: manga.source!,
                    lang: manga.lang!,
                    sourceId: manga.sourceId,
                  ),
                )
              : itemType == ItemType.anime
              ? videoHeader
              : htmlHeader;
          if (cookie.isNotEmpty) {
            final userAgent = isar.settings.getSync(227)!.userAgent!;
            headers.addAll(cookie);
            headers[HttpHeaders.userAgentHeader] = userAgent;
          }
          Map<String, String> pageHeaders = headers;
          pageHeaders.addAll(page.headers ?? {});

          if (itemType == ItemType.manga) {
            final file = File(
              p.join(chapterDirectory.path, "${padIndex(index)}.jpg"),
            );
            if (!file.existsSync()) {
              pages.add(
                PageUrl(
                  page.url.trim(),
                  headers: pageHeaders,
                  fileName: p.join(
                    chapterDirectory.path,
                    "${padIndex(index)}.jpg",
                  ),
                ),
              );
            }
          } else if (itemType == ItemType.anime) {
            final file = File(
              p.join(mangaMainDirectory.path, "$chapterName.mp4"),
            );
            if (!file.existsSync()) {
              pages.add(
                PageUrl(
                  page.url.trim(),
                  headers: pageHeaders,
                  fileName: p.join(mangaMainDirectory.path, "$chapterName.mp4"),
                ),
              );
            }
          }
        }
      }

      if (pages.isEmpty && pageUrls.isNotEmpty) {
        await processConvert();
        savePageUrls();
        await setProgress(DownloadProgress(1, 1, itemType, isCompleted: true));
      } else {
        savePageUrls();
        await MDownloader(
          chapter: chapter,
          pageUrls: pages,
          subtitles: subtitles,
          subDownloadDir: subtitleDirectoryBase,
        ).download((progress) {
          setProgress(progress);
        });
        await exportCoverFromDownloadedPages();
      }
    } else if (itemType == ItemType.novel) {
      final file = File(p.join(chapterDirectory.path, "$chapterName.html"));
      if (!file.existsSync() && novelPage != null) {
        final source = getSource(manga.lang!, manga.source!, manga.sourceId)!;
        p.join(chapterDirectory.path, "$chapterName.html");
        final html = await withExtensionService(
          source,
          ref.read(androidProxyServerStateProvider),
          (service) =>
              service.getHtmlContent(chapter.manga.value!.name!, chapter.url!),
        );
        if (html.isNotEmpty) {
          await file.writeAsString(html);
          await setProgress(
            DownloadProgress(1, 1, itemType, isCompleted: true),
          );
        }
      } else {
        await setProgress(DownloadProgress(1, 1, itemType, isCompleted: true));
      }
    } else if (hasM3U8File) {
      await m3u8Downloader?.download((progress) {
        setProgress(progress);
      });
    }
    if (callback != null) {
      callback();
    }
    await deleteEmptyAnimeEpisodeDirectory();
    await ref.read(scanLocalLibraryProvider.future);
    keepAlive.close();
  } catch (_) {
    keepAlive.close();
  }
}

@riverpod
Future<void> processDownloads(
  Ref ref, {
  bool? useWifi,
  LocalFolder? localFolder,
}) async {
  final keepAlive = ref.keepAlive();
  try {
    final ongoingDownloads = await isar.downloads
        .filter()
        .idIsNotNull()
        .isDownloadEqualTo(false)
        .isStartDownloadEqualTo(true)
        .findAll();
    final maxConcurrentDownloads = ref.read(concurrentDownloadsStateProvider);
    int index = 0;
    int downloaded = 0;
    int current = 0;
    await Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (ongoingDownloads.length == downloaded) {
        return false;
      }
      if (current < maxConcurrentDownloads) {
        current++;
        final downloadItem = ongoingDownloads[index++];
        final chapter = downloadItem.chapter.value!;
        chapter.cancelDownloads(downloadItem.id);
        await Future.delayed(const Duration(milliseconds: 500));
        ref.read(
          downloadChapterProvider(
            chapter: chapter,
            useWifi: useWifi,
            localFolder: localFolder,
            callback: () {
              downloaded++;
              current--;
            },
          ),
        );
      }
      return true;
    });
    keepAlive.close();
  } catch (_) {
    keepAlive.close();
  }
}
