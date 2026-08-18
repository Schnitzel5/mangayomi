import 'package:isar_community/isar.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/update.dart';
import 'package:mangayomi/models/history.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'isar_providers.g.dart';

@riverpod
Stream<List<History>> getAllHistoryStream(
  Ref ref, {
  required ItemType itemType,
  String search = "",
}) {
  final mangaSub = isar.mangas.watchLazy().listen((_) => ref.invalidateSelf());
  ref.onDispose(mangaSub.cancel);
  // idIsNotNull() removed — every Isar document has a non-null id.
  // The itemType hash-index on History + the link traversal does the filtering.
  return isar.historys
      .filter()
      .chapter(
        (q) => q.manga(
          (q) => q
              .itemTypeEqualTo(itemType)
              .and()
              .group(
                (q) => q
                    .nameContains(search, caseSensitive: false)
                    .or()
                    .displayTitleContains(search, caseSensitive: false),
              ),
        ),
      )
      .watch(fireImmediately: true);
}

@riverpod
Stream<List<Update>> getAllUpdateStream(
  Ref ref, {
  required ItemType itemType,
  String search = "",
}) {
  final mangaSub = isar.mangas.watchLazy().listen((_) => ref.invalidateSelf());
  ref.onDispose(mangaSub.cancel);
  return isar.updates
      .filter()
      .chapter(
        (q) => q.manga(
          (q) => q
              .itemTypeEqualTo(itemType)
              .and()
              .group(
                (q) => q
                    .nameContains(search, caseSensitive: false)
                    .or()
                    .displayTitleContains(search, caseSensitive: false),
              ),
        ),
      )
      .watch(fireImmediately: true);
}
