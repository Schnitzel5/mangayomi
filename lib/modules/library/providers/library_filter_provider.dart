import 'package:isar_community/isar.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/download.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/track.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'library_filter_provider.g.dart';

/// Pre-fetches all downloaded chapter IDs in a single Isar query.
/// Returns a [Set<int>] for O(1) lookup instead of per-chapter queries.
@riverpod
Stream<Set<int>> downloadedChapterIds(Ref ref) {
  return isar.downloads
      .where()
      .isDownloadEqualTo(true)
      .watch(fireImmediately: true)
      .map((list) => list.map((d) => d.id).whereType<int>().toSet());
}

/// Pre-fetches all manga IDs that have at least one tracking entry.
@riverpod
Stream<Set<int>> trackedMangaIds(Ref ref) {
  return isar.tracks
      .where()
      .watch(fireImmediately: true)
      .map((list) => list.map((t) => t.mangaId).whereType<int>().toSet());
}

/// Filters and sorts a list of [Manga] based on library filter/sort settings.
@riverpod
List<Manga> filteredLibraryManga(
  Ref ref, {
  required List<Manga> data,
  required int downloadFilterType,
  required int unreadFilterType,
  required int startedFilterType,
  required int bookmarkedFilterType,
  required int completedFilterType,
  required int trackingFilterType,
  required int sortType,
  required bool downloadedOnly,
  required String searchQuery,
  required bool ignoreFiltersOnSearch,
}) {
  final downloadedIds =
      ref.watch(downloadedChapterIdsProvider).asData?.value ?? const <int>{};
  final trackedIds =
      ref.watch(trackedMangaIdsProvider).asData?.value ?? const <int>{};

  List<Manga> mangas;

  // Skip all filters, just do search
  if (searchQuery.isNotEmpty && ignoreFiltersOnSearch) {
    mangas = data
        .where((element) => _matchesSearchQuery(element, searchQuery))
        .toList();
  } else {
    mangas = data.where((element) {
      // Filter by download — uses Set lookup instead of per-chapter Isar query
      if (downloadFilterType == 1 || downloadedOnly) {
        final hasDownloaded = element.chapters.any(
          (chap) => chap.id != null && downloadedIds.contains(chap.id),
        );
        if (!hasDownloaded) return false;
      } else if (downloadFilterType == 2) {
        final allNotDownloaded = element.chapters.every(
          (chap) => chap.id == null || !downloadedIds.contains(chap.id),
        );
        if (!allNotDownloaded) return false;
      }

      // Filter by unread or started
      if (unreadFilterType == 1 || startedFilterType == 1) {
        final hasUnread = element.chapters.any((chap) => !chap.isRead!);
        if (!hasUnread) return false;
      } else if (unreadFilterType == 2 || startedFilterType == 2) {
        final allRead = element.chapters.every((chap) => chap.isRead!);
        if (!allRead) return false;
      }

      // Filter by bookmarked
      if (bookmarkedFilterType == 1) {
        final hasBookmarked = element.chapters.any(
          (chap) => chap.isBookmarked!,
        );
        if (!hasBookmarked) return false;
      } else if (bookmarkedFilterType == 2) {
        final allNotBookmarked = element.chapters.every(
          (chap) => !chap.isBookmarked!,
        );
        if (!allNotBookmarked) return false;
      }

      // Filter by completed status
      if (completedFilterType == 1) {
        if (element.status != Status.completed) return false;
      } else if (completedFilterType == 2) {
        if (element.status == Status.completed) return false;
      }

      // Filter by tracking
      if (trackingFilterType == 1) {
        if (element.id == null || !trackedIds.contains(element.id)) {
          return false;
        }
      } else if (trackingFilterType == 2) {
        if (element.id != null && trackedIds.contains(element.id)) {
          return false;
        }
      }

      // Search filter
      if (searchQuery.isNotEmpty) {
        if (!_matchesSearchQuery(element, searchQuery)) return false;
      }

      return true;
    }).toList();
  }

  // Sort. Chapter-derived keys (unread count, chapter count, last upload) are
  // computed once per manga up front — computing them inside the comparator
  // traverses the IsarLinks O(n log n) times.
  switch (sortType) {
    case 0:
      mangas.sort((a, b) => a.name!.compareTo(b.name!));
    case 1:
      mangas.sort((a, b) => a.lastRead!.compareTo(b.lastRead!));
    case 2:
      mangas.sort((a, b) => a.lastUpdate?.compareTo(b.lastUpdate ?? 0) ?? 0);
    case 3:
      final unreadCount = {
        for (final m in mangas)
          m.id: m.chapters.where((e) => !e.isRead!).length,
      };
      mangas.sort((a, b) => unreadCount[a.id]!.compareTo(unreadCount[b.id]!));
    case 4:
      final chapterCount = {for (final m in mangas) m.id: m.chapters.length};
      mangas.sort((a, b) => chapterCount[a.id]!.compareTo(chapterCount[b.id]!));
    case 5:
      final lastUpload = {
        for (final m in mangas) m.id: m.chapters.lastOrNull?.dateUpload ?? "",
      };
      mangas.sort((a, b) => lastUpload[a.id]!.compareTo(lastUpload[b.id]!));
    case 6:
      mangas.sort((a, b) => a.dateAdded?.compareTo(b.dateAdded ?? 0) ?? 0);
  }

  return mangas;
}

bool _matchesSearchQuery(Manga manga, String query) {
  final keywords = query
      .toLowerCase()
      .split(',')
      .map((k) => k.trim())
      .where((k) => k.isNotEmpty);

  return keywords.any(
    (keyword) =>
        (manga.name?.toLowerCase().contains(keyword) ?? false) ||
        (manga.source?.toLowerCase().contains(keyword) ?? false) ||
        (manga.genre?.any((g) => g.toLowerCase().contains(keyword)) ?? false),
  );
}
