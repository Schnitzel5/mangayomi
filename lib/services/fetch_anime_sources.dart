import 'package:mangayomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:mangayomi/services/fetch_sources_list.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'fetch_anime_sources.g.dart';

@riverpod
Future fetchAnimeSourcesList(FetchAnimeSourcesListRef ref,
    {int? id, required bool reFresh}) async {
  if (ref.watch(checkForExtensionsUpdateStateProvider) || reFresh) {
    final url = ref.read(changeAnimeSourcesStateProvider.notifier).build();
    await fetchSourcesList(
        sourcesIndexUrl: url,
        refresh: reFresh,
        id: id,
        ref: ref,
        isManga: false);
  }
}
