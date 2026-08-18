import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:isar_community/isar.dart';
import 'package:http/http.dart' as http;
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/utils/constant.dart';

const defaultMetadataDomain = "api-metadata.friedcutlet.com";

Future<bool> fetchMangaMetadata(int mangaId, {bool force = false}) async {
  final settings = isar.settings.getSync(227);
  if (!(settings?.enableMetadataFetch ?? false)) return false;
  final manga = isar.mangas.getSync(mangaId);
  final name = manga?.name?.trim();
  if (manga == null || name == null || name.isEmpty) return false;
  if (!force && manga.titleRomaji != null) return false;

  final domain = settings?.metadataDomain?.trim();
  final uri = Uri.https(
    (domain == null || domain.isEmpty) ? defaultMetadataDomain : domain,
    "/api/v1/media",
    {"q": name, "type": manga.itemType.name, "per_page": "10"},
  );
  try {
    final res = await http.get(
      uri,
      headers: const {
        "Accept": "application/json",
        "User-Agent": metadataApiUserAgent,
      },
    );
    if (res.statusCode != 200) return false;
    final data = (jsonDecode(res.body) as Map<String, dynamic>)["data"];
    final media = bestMatch(name, (data as List?) ?? const []);
    if (media == null) return false;
    manga
      ..titleRomaji = media["title"] as String?
      ..titleEnglish = media["title_english"] as String?
      ..titleNative = media["title_native"] as String?
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (manga.displayTitle != null &&
        ![
          manga.titleEnglish,
          manga.titleRomaji,
          manga.titleNative,
        ].contains(manga.displayTitle)) {
      manga.displayTitle = null;
    }
    if (manga.description == null || manga.description!.trim().isEmpty) {
      final description = media["description"] as String?;
      if (description != null && description.trim().isNotEmpty) {
        manga.description = _stripHtml(description);
      }
    }
    if (manga.status == Status.unknown) {
      manga.status =
          _statusFromMetadata(media["status"] as String?) ?? Status.unknown;
    }
    final genres = (media["genres"] as List?)?.cast<String>() ?? const [];
    if (genres.isNotEmpty) {
      final existing = manga.genre ?? const [];
      manga.genre = existing.isEmpty
          ? genres
          : (settings!.metadataMergeGenres ?? true)
          ? {...existing, ...genres}.toList()
          : genres;
    }
    await isar.writeTxn(() => isar.mangas.put(manga));
    return true;
  } catch (_) {
    return false;
  }
}

Status? _statusFromMetadata(String? status) => switch (status) {
  "RELEASING" => Status.ongoing,
  "FINISHED" => Status.completed,
  "CANCELLED" => Status.canceled,
  "HIATUS" => Status.onHiatus,
  _ => null,
};

String _stripHtml(String description) => description
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .trim();

Future<int> refreshLibraryMetadata() async {
  final ids = isar.mangas
      .filter()
      .favoriteEqualTo(true)
      .findAllSync()
      .map((manga) => manga.id!)
      .toList();
  var updated = 0;
  for (var i = 0; i < ids.length; i += 5) {
    final results = await Future.wait(
      ids.skip(i).take(5).map((id) => fetchMangaMetadata(id, force: true)),
    );
    updated += results.where((stored) => stored).length;
  }
  return updated;
}

@visibleForTesting
Map<String, dynamic>? bestMatch(String name, List<dynamic> candidates) {
  final query = _normalize(name);
  Map<String, dynamic>? best;
  var bestScore = 0.7;
  for (final candidate in candidates.cast<Map<String, dynamic>>()) {
    for (final key in const ["title", "title_english", "title_native"]) {
      final title = candidate[key] as String?;
      if (title == null) continue;
      final score = _similarity(query, _normalize(title));
      if (score >= bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
  }
  return best;
}

String _normalize(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

double _similarity(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  final curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = [
        curr[j - 1] + 1,
        prev[j] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = List.of(curr);
  }
  final maxLen = a.length > b.length ? a.length : b.length;
  return 1 - prev[b.length] / maxLen;
}
