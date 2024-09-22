import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'browse_state_provider.g.dart';

@riverpod
class OnlyIncludePinnedSourceState extends _$OnlyIncludePinnedSourceState {
  @override
  bool build() {
    return isar.settings.getSync(227)!.onlyIncludePinnedSources!;
  }

  void set(bool value) {
    final settings = isar.settings.getSync(227);
    state = value;
    isar.writeTxnSync(() =>
        isar.settings.putSync(settings!..onlyIncludePinnedSources = value));
  }
}

@riverpod
class AutoUpdateExtensionsState extends _$AutoUpdateExtensionsState {
  @override
  bool build() {
    return isar.settings.getSync(227)!.autoExtensionsUpdates ?? false;
  }

  void set(bool value) {
    final settings = isar.settings.getSync(227);
    state = value;
    isar.writeTxnSync(
        () => isar.settings.putSync(settings!..autoExtensionsUpdates = value));
  }
}

@riverpod
class CheckForExtensionsUpdateState extends _$CheckForExtensionsUpdateState {
  @override
  bool build() {
    return isar.settings.getSync(227)!.checkForExtensionUpdates ?? true;
  }

  void set(bool value) {
    final settings = isar.settings.getSync(227);
    state = value;
    isar.writeTxnSync(() =>
        isar.settings.putSync(settings!..checkForExtensionUpdates = value));
  }
}

@riverpod
class ChangeMangaSourcesState extends _$ChangeMangaSourcesState {
  @override
  String build() {
    return isar.settings.getSync(227)!.fetchMangaSourcesListUrl ??
        "https://kodjodevf.github.io/mangayomi-extensions/index.json";
  }

  void set(String value) {
    final settings = isar.settings.getSync(227);
    state = value;
    isar.writeTxnSync(() =>
        isar.settings.putSync(settings!..fetchMangaSourcesListUrl = value));
  }
}

@riverpod
class ChangeAnimeSourcesState extends _$ChangeAnimeSourcesState {
  @override
  String build() {
    return isar.settings.getSync(227)!.fetchAnimeSourcesListUrl ??
        "https://kodjodevf.github.io/mangayomi-extensions/anime_index.json";
  }

  void set(String value) {
    final settings = isar.settings.getSync(227);
    state = value;
    isar.writeTxnSync(() =>
        isar.settings.putSync(settings!..fetchAnimeSourcesListUrl = value));
  }
}
