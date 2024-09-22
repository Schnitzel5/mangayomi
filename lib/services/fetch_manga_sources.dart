import 'package:mangayomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:mangayomi/services/fetch_sources_list.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'fetch_manga_sources.g.dart';

@riverpod
Future fetchMangaSourcesList(FetchMangaSourcesListRef ref,
    {int? id, required reFresh}) async {
  if (ref.watch(checkForExtensionsUpdateStateProvider) || reFresh) {
    final url = ref.read(changeMangaSourcesStateProvider.notifier).build();
    await fetchSourcesList(
        sourcesIndexUrl: url,
        refresh: reFresh,
        id: id,
        ref: ref,
        isManga: true);
  }
}
