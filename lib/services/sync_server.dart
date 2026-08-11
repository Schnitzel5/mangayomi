import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_qjs/quickjs/ffi.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/eval/model/m_bridge.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/category.dart';
import 'package:mangayomi/models/changed.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/history.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/models/sync_preference.dart';
import 'package:mangayomi/models/track.dart';
import 'package:mangayomi/models/update.dart';
import 'package:mangayomi/modules/more/settings/appearance/providers/blend_level_state_provider.dart';
import 'package:mangayomi/modules/more/settings/appearance/providers/flex_scheme_color_state_provider.dart';
import 'package:mangayomi/modules/more/settings/appearance/providers/pure_black_dark_mode_state_provider.dart';
import 'package:mangayomi/modules/more/settings/appearance/providers/theme_mode_state_provider.dart';
import 'package:mangayomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:mangayomi/modules/more/settings/sync/providers/sync_providers.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/services/http/m_client.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
part 'sync_server.g.dart';

enum _SyncDomain { manga, histories, updates, settings }

String _newSyncClientId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

@riverpod
class SyncServer extends _$SyncServer {
  final http = MClient.init(reqcopyWith: {'useDartHttpClient': true});
  final String _loginUrl = '/login';
  final String _syncMangaUrl = '/sync/manga';
  final String _syncHistoryUrl = '/sync/histories';
  final String _syncUpdateUrl = '/sync/updates';
  final String _syncSettingsUrl = '/sync/settings';
  final String _clientId = _newSyncClientId();
  final List<StreamSubscription<void>> _databaseSubscriptions = [];
  final Map<_SyncDomain, Timer> _debounceTimers = {};
  final Set<_SyncDomain> _pendingUploads = {};
  final Set<_SyncDomain> _pendingPulls = {};
  final Set<_SyncDomain> _remoteWrites = {};

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _operationRetryTimer;
  Future<void> _serialFuture = Future<void>.value();
  bool _disposed = false;
  bool _socketReady = false;
  bool _draining = false;
  int _connectionGeneration = 0;
  int _reconnectAttempt = 0;

  @override
  void build({required int syncId}) {
    ref.keepAlive();
    _disposed = false;
    _socketReady = false;
    _draining = false;
    _reconnectAttempt = 0;
    ref.onDispose(_dispose);
    Future<void>.microtask(_startLiveSync);
  }

  Future<void> _startLiveSync() async {
    if (_disposed) {
      return;
    }
    final preference = ref.read(synchingProvider(syncId: syncId));
    if (!_liveSyncEnabled(preference)) {
      return;
    }
    _subscribeToDatabase();
    await _connect();
  }

  bool _liveSyncEnabled(SyncPreference preference) =>
      preference.syncOn &&
      (preference.authToken?.isNotEmpty ?? false) &&
      (preference.server?.isNotEmpty ?? false);

  bool _domainEnabled(_SyncDomain domain, SyncPreference preference) {
    return switch (domain) {
      _SyncDomain.manga => true,
      _SyncDomain.histories => preference.syncHistories,
      _SyncDomain.updates => preference.syncUpdates,
      _SyncDomain.settings => preference.syncSettings,
    };
  }

  Set<_SyncDomain> _enabledDomains(SyncPreference preference) => _SyncDomain
      .values
      .where((domain) => _domainEnabled(domain, preference))
      .toSet();

  void _queueExistingLocalChanges(SyncPreference preference) {
    final mangaActions = {
      ActionType.removeCategory,
      ActionType.removeItem,
      ActionType.removeChapter,
      ActionType.removeTrack,
    };
    final changedParts = isar.changedParts
        .filter()
        .idIsNotNull()
        .findAllSync()
        .map((part) => part.actionType)
        .toSet();
    final lastMangaSync = preference.lastSyncManga ?? 0;
    if (changedParts.any(mangaActions.contains) ||
        isar.categorys
            .filter()
            .updatedAtGreaterThan(lastMangaSync)
            .isNotEmptySync() ||
        isar.mangas
            .filter()
            .updatedAtGreaterThan(lastMangaSync)
            .isNotEmptySync() ||
        isar.chapters
            .filter()
            .updatedAtGreaterThan(lastMangaSync)
            .isNotEmptySync() ||
        isar.tracks
            .filter()
            .updatedAtGreaterThan(lastMangaSync)
            .isNotEmptySync()) {
      _pendingUploads.add(_SyncDomain.manga);
    }

    if (preference.syncHistories &&
        (changedParts.contains(ActionType.removeHistory) ||
            isar.historys
                .filter()
                .updatedAtGreaterThan(preference.lastSyncHistory ?? 0)
                .isNotEmptySync())) {
      _pendingUploads.add(_SyncDomain.histories);
    }
    if (preference.syncUpdates &&
        (changedParts.contains(ActionType.removeUpdate) ||
            isar.updates
                .filter()
                .updatedAtGreaterThan(preference.lastSyncUpdate ?? 0)
                .isNotEmptySync())) {
      _pendingUploads.add(_SyncDomain.updates);
    }
  }

  void _subscribeToDatabase() {
    if (_databaseSubscriptions.isNotEmpty) {
      return;
    }
    void watch(Stream<void> stream, _SyncDomain domain) {
      _databaseSubscriptions.add(
        stream.listen((_) => _onLocalDatabaseChange(domain)),
      );
    }

    watch(isar.categorys.watchLazy(), _SyncDomain.manga);
    watch(isar.mangas.watchLazy(), _SyncDomain.manga);
    watch(isar.chapters.watchLazy(), _SyncDomain.manga);
    watch(isar.tracks.watchLazy(), _SyncDomain.manga);
    watch(isar.historys.watchLazy(), _SyncDomain.histories);
    watch(isar.updates.watchLazy(), _SyncDomain.updates);
    watch(isar.settings.watchLazy(), _SyncDomain.settings);
    _databaseSubscriptions.add(
      isar.changedParts.watchLazy().listen((_) => _onChangedPartsChanged()),
    );
  }

  void _onChangedPartsChanged() {
    if (_disposed) {
      return;
    }
    final actions = isar.changedParts
        .filter()
        .idIsNotNull()
        .findAllSync()
        .map((part) => part.actionType)
        .toSet();
    if (actions.any(
      {
        ActionType.removeCategory,
        ActionType.removeItem,
        ActionType.removeChapter,
        ActionType.removeTrack,
      }.contains,
    )) {
      _onLocalDatabaseChange(_SyncDomain.manga);
    }
    if (actions.contains(ActionType.removeHistory)) {
      _onLocalDatabaseChange(_SyncDomain.histories);
    }
    if (actions.contains(ActionType.removeUpdate)) {
      _onLocalDatabaseChange(_SyncDomain.updates);
    }
  }

  void _onLocalDatabaseChange(_SyncDomain domain) {
    if (_disposed || _remoteWrites.contains(domain)) {
      return;
    }
    final preference = ref.read(synchingProvider(syncId: syncId));
    if (!_liveSyncEnabled(preference) || !_domainEnabled(domain, preference)) {
      return;
    }
    _debounceTimers[domain]?.cancel();
    _debounceTimers[domain] = Timer(const Duration(milliseconds: 600), () {
      _debounceTimers.remove(domain);
      _pendingUploads.add(domain);
      _scheduleDrain();
    });
  }

  Future<void> _connect() async {
    if (_disposed) {
      return;
    }
    final preference = ref.read(synchingProvider(syncId: syncId));
    if (!_liveSyncEnabled(preference)) {
      return;
    }
    final generation = ++_connectionGeneration;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      final serverUri = Uri.parse(preference.server!);
      final socketUri = serverUri.replace(
        scheme: serverUri.scheme == 'https' ? 'wss' : 'ws',
        path:
            '${serverUri.path.endsWith('/') ? serverUri.path.substring(0, serverUri.path.length - 1) : serverUri.path}/sync/live',
        queryParameters: {...serverUri.queryParameters, 'clientId': _clientId},
      );
      final socket = await WebSocket.connect(
        socketUri.toString(),
        headers: {'Cookie': 'id=${preference.authToken}'},
      );
      if (_disposed || generation != _connectionGeneration) {
        await socket.close();
        return;
      }
      _socket = socket..pingInterval = const Duration(seconds: 20);
      _socketSubscription = socket.listen(
        (message) => _handleSocketMessage(message),
        onDone: () => _handleSocketClosed(generation),
        onError: (_) => _handleSocketClosed(generation),
        cancelOnError: true,
      );
    } catch (_) {
      if (!_disposed && generation == _connectionGeneration) {
        _scheduleReconnect();
      }
    }
  }

  void _handleSocketMessage(dynamic message) {
    if (_disposed || message is! String) {
      return;
    }
    try {
      final event = jsonDecode(message);
      if (event is! Map<String, dynamic>) {
        return;
      }
      if (event['type'] == 'ready') {
        _socketReady = true;
        _reconnectAttempt = 0;
        final preference = ref.read(synchingProvider(syncId: syncId));
        if (_liveSyncEnabled(preference)) {
          _queueExistingLocalChanges(preference);
          _pendingPulls.addAll(_enabledDomains(preference));
          _scheduleDrain();
        }
        return;
      }
      if (event['type'] != 'sync') {
        return;
      }
      final domain = switch (event['domain']) {
        'manga' => _SyncDomain.manga,
        'histories' => _SyncDomain.histories,
        'updates' => _SyncDomain.updates,
        'settings' => _SyncDomain.settings,
        _ => null,
      };
      if (domain == null) {
        return;
      }
      final preference = ref.read(synchingProvider(syncId: syncId));
      if (_liveSyncEnabled(preference) && _domainEnabled(domain, preference)) {
        _pendingPulls.add(domain);
        _scheduleDrain();
      }
    } on FormatException {
      // Ignore malformed invalidations; REST remains the source of truth.
    }
  }

  void _handleSocketClosed(int generation) {
    if (_disposed || generation != _connectionGeneration) {
      return;
    }
    _socketReady = false;
    _socket = null;
    _socketSubscription = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer != null) {
      return;
    }
    final preference = ref.read(synchingProvider(syncId: syncId));
    if (!_liveSyncEnabled(preference)) {
      return;
    }
    const delays = [1, 2, 4, 8, 16, 30];
    final delay = delays[min(_reconnectAttempt, delays.length - 1)];
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _reconnectTimer = null;
      unawaited(_connect());
    });
  }

  void _scheduleDrain() {
    if (_disposed || _draining || !_socketReady) {
      return;
    }
    _operationRetryTimer?.cancel();
    _operationRetryTimer = null;
    _draining = true;
    var retryNeeded = false;
    unawaited(
      _serialize(() async {
        while (!_disposed && _socketReady) {
          final preference = ref.read(synchingProvider(syncId: syncId));
          if (!_liveSyncEnabled(preference)) {
            return;
          }
          _pendingPulls.removeWhere(
            (domain) => !_domainEnabled(domain, preference),
          );
          _pendingUploads.removeWhere(
            (domain) => !_domainEnabled(domain, preference),
          );
          final isPull = _pendingPulls.isNotEmpty;
          final domain = isPull
              ? _pendingPulls.first
              : (_pendingUploads.isNotEmpty ? _pendingUploads.first : null);
          if (domain == null) {
            return;
          }
          if (isPull) {
            _pendingPulls.remove(domain);
          } else {
            _pendingUploads.remove(domain);
          }
          bool success;
          try {
            success = await _syncDomain(domain, download: isPull);
          } catch (_) {
            success = false;
          }
          if (!success) {
            (isPull ? _pendingPulls : _pendingUploads).add(domain);
            retryNeeded = true;
            return;
          }
        }
      }).whenComplete(() {
        _draining = false;
        if (_disposed || !_socketReady) {
          return;
        }
        if (retryNeeded) {
          _operationRetryTimer?.cancel();
          _operationRetryTimer = Timer(
            const Duration(seconds: 5),
            _scheduleDrain,
          );
        } else if (_pendingPulls.isNotEmpty || _pendingUploads.isNotEmpty) {
          _scheduleDrain();
        }
      }),
    );
  }

  Future<T> _withRemoteWritesSuppressed<T>(
    _SyncDomain domain,
    Future<T> Function() operation,
  ) async {
    _remoteWrites.add(domain);
    try {
      return await operation();
    } finally {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      _remoteWrites.remove(domain);
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final previous = _serialFuture;
    final release = Completer<void>();
    _serialFuture = release.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        release.complete();
      }
    }();
  }

  Future<bool> _syncDomain(_SyncDomain domain, {required bool download}) async {
    final preference = ref.read(synchingProvider(syncId: syncId));
    final syncNotifier = ref.read(synchingProvider(syncId: syncId).notifier);
    return switch (domain) {
      _SyncDomain.manga => _syncManga(
        syncNotifier,
        download: download,
        lastSync: preference.lastSyncManga ?? 0,
      ),
      _SyncDomain.histories => _syncHistory(
        syncNotifier,
        download: download,
        lastSync: preference.lastSyncHistory ?? 0,
      ),
      _SyncDomain.updates => _syncUpdate(
        syncNotifier,
        download: download,
        lastSync: preference.lastSyncUpdate ?? 0,
      ),
      _SyncDomain.settings => _syncSettings(download: download),
    };
  }

  void _dispose() {
    _disposed = true;
    _socketReady = false;
    _connectionGeneration++;
    _reconnectTimer?.cancel();
    _operationRetryTimer?.cancel();
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    for (final subscription in _databaseSubscriptions) {
      unawaited(subscription.cancel());
    }
    _databaseSubscriptions.clear();
    final socketSubscription = _socketSubscription;
    if (socketSubscription != null) {
      unawaited(socketSubscription.cancel());
    }
    _socketSubscription = null;
    final socket = _socket;
    if (socket != null) {
      unawaited(socket.close());
    }
    _socket = null;
    _pendingPulls.clear();
    _pendingUploads.clear();
    _remoteWrites.clear();
  }

  Future<(bool, String)> login(
    AppLocalizations l10n,
    String server,
    String username,
    String password,
  ) async {
    server = server.isNotEmpty && server[server.length - 1] == '/'
        ? server.substring(0, server.length - 1)
        : server;
    try {
      var response = await http.post(
        Uri.parse('$server$_loginUrl'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': username, 'password': password}),
      );
      var cookieHeader = response.headers["set-cookie"];
      var startIdx = cookieHeader?.indexOf("id=") ?? -1;
      var endIdx = cookieHeader?.indexOf(";", startIdx) ?? -1;
      if (startIdx == -1 || endIdx == -1) {
        return (false, "Auth failed");
      }
      final authToken = cookieHeader!.substring(startIdx + 3, endIdx);
      ref
          .read(synchingProvider(syncId: syncId).notifier)
          .login(server, username, authToken);
      botToast(l10n.sync_logged);
      return (true, "");
    } catch (e) {
      return (false, e.toString());
    }
  }

  Future<void> startSync(
    AppLocalizations l10n,
    bool silent, {
    bool upload = false,
    bool download = false,
  }) async {
    if (!silent) {
      botToast(l10n.sync_starting, second: 500);
    }
    try {
      final success = await _serialize(() async {
        final syncPreference = ref.read(synchingProvider(syncId: syncId));
        final syncNotifier = ref.read(
          synchingProvider(syncId: syncId).notifier,
        );

        final resultManga = await _syncManga(
          syncNotifier,
          download: download,
          upload: upload,
          lastSync: syncPreference.lastSyncManga ?? 0,
        );
        if (!resultManga) {
          return false;
        }
        if (syncPreference.syncHistories) {
          final resultHistory = await _syncHistory(
            syncNotifier,
            download: download,
            upload: upload,
            lastSync: syncPreference.lastSyncHistory ?? 0,
          );
          if (!resultHistory) {
            return false;
          }
        }
        if (syncPreference.syncUpdates) {
          final resultUpdate = await _syncUpdate(
            syncNotifier,
            download: download,
            upload: upload,
            lastSync: syncPreference.lastSyncUpdate ?? 0,
          );
          if (!resultUpdate) {
            return false;
          }
        }
        if (syncPreference.syncSettings) {
          final resultSettings = await _syncSettings(
            download: download,
            upload: upload,
          );
          if (!resultSettings) {
            return false;
          }
        }
        return true;
      });

      if (!success) {
        if (!silent) {
          botToast(l10n.sync_failed, second: 5);
        }
        return;
      }
      ref.invalidate(synchingProvider(syncId: syncId));
      if (!silent) {
        botToast(l10n.sync_finished, second: 2);
      }
    } catch (error) {
      if (!silent) {
        botToast(error.toString(), second: 5);
      }
    }
  }

  Future<bool> _syncManga(
    Synching syncNotifier, {
    bool upload = false,
    bool download = false,
    int lastSync = 0,
  }) async {
    final mangaData = _getMangaData(upload: upload, download: download);
    final accessToken = _getAccessToken();
    var response = await http.post(
      Uri.parse('${_getServer()}$_syncMangaUrl'),
      headers: _syncHeaders(accessToken),
      body: mangaData,
    );
    if (response.statusCode != 200) {
      return false;
    }

    if (!upload) {
      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      await _withRemoteWritesSuppressed(
        _SyncDomain.manga,
        () => _upsertCategories(
          jsonData,
          syncNotifier,
          downloadOnly: download,
          lastSync: lastSync,
        ),
      );
      await _withRemoteWritesSuppressed(
        _SyncDomain.manga,
        () => _upsertManga(
          jsonData,
          syncNotifier,
          downloadOnly: download,
          lastSync: lastSync,
        ),
      );
      await _withRemoteWritesSuppressed(
        _SyncDomain.manga,
        () => _upsertChapters(
          jsonData,
          syncNotifier,
          downloadOnly: download,
          lastSync: lastSync,
        ),
      );
      await _withRemoteWritesSuppressed(
        _SyncDomain.manga,
        () => _upsertTracks(
          jsonData,
          syncNotifier,
          downloadOnly: download,
          lastSync: lastSync,
        ),
      );
    } else {
      await _withRemoteWritesSuppressed(
        _SyncDomain.manga,
        () => syncNotifier.clearChangedParts([
          ActionType.removeCategory,
          ActionType.removeItem,
          ActionType.removeChapter,
          ActionType.removeTrack,
        ], true),
      );
    }

    syncNotifier.setLastSyncManga(DateTime.now().millisecondsSinceEpoch);
    return true;
  }

  Future<bool> _syncHistory(
    Synching syncNotifier, {
    bool upload = false,
    bool download = false,
    int lastSync = 0,
  }) async {
    final historyData = _getHistoryData(upload: upload, download: download);
    final accessToken = _getAccessToken();
    var response = await http.post(
      Uri.parse('${_getServer()}$_syncHistoryUrl'),
      headers: _syncHeaders(accessToken),
      body: historyData,
    );
    if (response.statusCode != 200) {
      return false;
    }

    if (!upload) {
      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      await _withRemoteWritesSuppressed(
        _SyncDomain.histories,
        () => _upsertHistories(
          jsonData,
          syncNotifier,
          downloadOnly: download,
          lastSync: lastSync,
        ),
      );
    } else {
      await _withRemoteWritesSuppressed(
        _SyncDomain.histories,
        () => syncNotifier.clearChangedParts([ActionType.removeHistory], true),
      );
    }

    syncNotifier.setLastSyncHistory(DateTime.now().millisecondsSinceEpoch);
    return true;
  }

  Future<bool> _syncUpdate(
    Synching syncNotifier, {
    bool upload = false,
    bool download = false,
    int lastSync = 0,
  }) async {
    final updateData = _getUpdateData(upload: upload, download: download);
    final accessToken = _getAccessToken();
    var response = await http.post(
      Uri.parse('${_getServer()}$_syncUpdateUrl'),
      headers: _syncHeaders(accessToken),
      body: updateData,
    );
    if (response.statusCode != 200) {
      return false;
    }

    if (!upload) {
      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      await _withRemoteWritesSuppressed(
        _SyncDomain.updates,
        () => _upsertUpdates(
          jsonData,
          syncNotifier,
          downloadOnly: download,
          lastSync: lastSync,
        ),
      );
    } else {
      await _withRemoteWritesSuppressed(
        _SyncDomain.updates,
        () => syncNotifier.clearChangedParts([ActionType.removeUpdate], true),
      );
    }

    syncNotifier.setLastSyncUpdate(DateTime.now().millisecondsSinceEpoch);
    return true;
  }

  Future<bool> _syncSettings({
    bool upload = false,
    bool download = false,
  }) async {
    final settingsData = _getSettingsData(download: download);
    final accessToken = _getAccessToken();
    var response = await http.post(
      Uri.parse('${_getServer()}$_syncSettingsUrl'),
      headers: _syncHeaders(accessToken),
      body: settingsData,
    );
    if (response.statusCode != 200) {
      return false;
    }

    if (!upload) {
      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      await _withRemoteWritesSuppressed(
        _SyncDomain.settings,
        () => _upsertSettings(jsonData),
      );
    }
    return true;
  }

  Future<void> _upsertCategories(
    Map<String, dynamic> jsonData,
    Synching syncNotifier, {
    required bool downloadOnly,
    required int lastSync,
  }) async {
    final categories =
        (jsonData["categories"] as List?)
            ?.map((e) => Category.fromJson(e))
            .toList() ??
        [];
    final pendingDeletes = downloadOnly
        ? _pendingDeletionIds(ActionType.removeCategory)
        : const <int>{};
    await isar.writeTxn(() async {
      for (var category
          in await isar.categorys.filter().idIsNotNull().findAll()) {
        final temp = categories.firstWhereOrNull((e) => e.id == category.id);
        if (temp != null) {
          if (!pendingDeletes.contains(category.id) &&
              (category.updatedAt ?? 0) < (temp.updatedAt ?? 1)) {
            await isar.categorys.put(temp);
          }
          categories.remove(temp);
        } else if (!downloadOnly || (category.updatedAt ?? 0) <= lastSync) {
          await isar.categorys.delete(category.id!);
        }
      }
      for (var category in categories) {
        if (!pendingDeletes.contains(category.id)) {
          await isar.categorys.put(category);
        }
      }
      if (!downloadOnly) {
        await syncNotifier.clearChangedParts([
          ActionType.removeCategory,
        ], false);
      }
    });
  }

  Future<void> _upsertManga(
    Map<String, dynamic> jsonData,
    Synching syncNotifier, {
    required bool downloadOnly,
    required int lastSync,
  }) async {
    final mangas =
        (jsonData["manga"] as List?)?.map((e) => Manga.fromJson(e)).toList() ??
        [];
    final pendingDeletes = downloadOnly
        ? _pendingDeletionIds(ActionType.removeItem)
        : const <int>{};
    await isar.writeTxn(() async {
      for (var manga in await isar.mangas.filter().idIsNotNull().findAll()) {
        final temp = mangas.firstWhereOrNull((e) => e.id == manga.id);
        if (temp != null) {
          if (!pendingDeletes.contains(manga.id) &&
              (manga.updatedAt ?? 0) < (temp.updatedAt ?? 1)) {
            await isar.mangas.put(temp);
          }
          mangas.remove(temp);
        } else if (!downloadOnly || (manga.updatedAt ?? 0) <= lastSync) {
          await isar.mangas.delete(manga.id!);
        }
      }
      for (var manga in mangas) {
        if (!pendingDeletes.contains(manga.id)) {
          await isar.mangas.put(manga);
        }
      }
      if (!downloadOnly) {
        await syncNotifier.clearChangedParts([ActionType.removeItem], false);
      }
    });
  }

  Future<void> _upsertChapters(
    Map<String, dynamic> jsonData,
    Synching syncNotifier, {
    required bool downloadOnly,
    required int lastSync,
  }) async {
    final chapters =
        (jsonData["chapters"] as List?)
            ?.map((e) => Chapter.fromJson(e))
            .toList() ??
        [];
    final pendingDeletes = downloadOnly
        ? _pendingDeletionIds(ActionType.removeChapter)
        : const <int>{};
    await isar.writeTxn(() async {
      for (var chapter
          in await isar.chapters.filter().idIsNotNull().findAll()) {
        final temp = chapters.firstWhereOrNull((e) => e.id == chapter.id);
        if (temp != null) {
          final manga = await isar.mangas.get(temp.mangaId!);
          if (!pendingDeletes.contains(chapter.id) &&
              manga != null &&
              (chapter.updatedAt ?? 0) < (temp.updatedAt ?? 1)) {
            await isar.chapters.put(temp..manga.value = manga);
            await temp.manga.save();
          }
          chapters.remove(temp);
        } else if (!downloadOnly || (chapter.updatedAt ?? 0) <= lastSync) {
          await isar.chapters.delete(chapter.id!);
        }
      }
      for (var chapter in chapters) {
        if (pendingDeletes.contains(chapter.id)) {
          continue;
        }
        final manga = await isar.mangas.get(chapter.mangaId!);
        if (manga != null) {
          await isar.chapters.put(chapter..manga.value = manga);
          await chapter.manga.save();
        }
      }
      if (!downloadOnly) {
        await syncNotifier.clearChangedParts([ActionType.removeChapter], false);
      }
    });
  }

  Future<void> _upsertTracks(
    Map<String, dynamic> jsonData,
    Synching syncNotifier, {
    required bool downloadOnly,
    required int lastSync,
  }) async {
    final tracks =
        (jsonData["tracks"] as List?)?.map((e) => Track.fromJson(e)).toList() ??
        [];
    final pendingDeletes = downloadOnly
        ? _pendingDeletionIds(ActionType.removeTrack)
        : const <int>{};
    await isar.writeTxn(() async {
      for (var track in await isar.tracks.filter().idIsNotNull().findAll()) {
        final temp = tracks.firstWhereOrNull((e) => e.id == track.id);
        if (temp != null) {
          if (!pendingDeletes.contains(track.id) &&
              (track.updatedAt ?? 0) < (temp.updatedAt ?? 1)) {
            await isar.tracks.put(temp);
          }
          tracks.remove(temp);
        } else if (!downloadOnly || (track.updatedAt ?? 0) <= lastSync) {
          await isar.tracks.delete(track.id!);
        }
      }
      for (var track in tracks) {
        if (!pendingDeletes.contains(track.id)) {
          await isar.tracks.put(track);
        }
      }
      if (!downloadOnly) {
        await syncNotifier.clearChangedParts([ActionType.removeTrack], false);
      }
    });
  }

  Future<void> _upsertHistories(
    Map<String, dynamic> jsonData,
    Synching syncNotifier, {
    required bool downloadOnly,
    required int lastSync,
  }) async {
    final histories =
        (jsonData["histories"] as List?)
            ?.map((e) => History.fromJson(e))
            .toList() ??
        [];
    final pendingDeletes = downloadOnly
        ? _pendingDeletionIds(ActionType.removeHistory)
        : const <int>{};
    await isar.writeTxn(() async {
      for (var history
          in await isar.historys.filter().idIsNotNull().findAll()) {
        final temp = histories.firstWhereOrNull((e) => e.id == history.id);
        if (temp != null) {
          final chapter = await isar.chapters.get(temp.chapterId!);
          if (!pendingDeletes.contains(history.id) &&
              chapter != null &&
              (history.updatedAt ?? 0) < (temp.updatedAt ?? 1)) {
            await isar.historys.put(temp..chapter.value = chapter);
            await temp.chapter.save();
          }
          histories.remove(temp);
        } else if (!downloadOnly || (history.updatedAt ?? 0) <= lastSync) {
          await isar.historys.delete(history.id!);
        }
      }
      for (var history in histories) {
        if (pendingDeletes.contains(history.id)) {
          continue;
        }
        final chapter = await isar.chapters.get(history.chapterId!);
        if (chapter != null) {
          await isar.historys.put(history..chapter.value = chapter);
          await history.chapter.save();
        }
      }
      if (!downloadOnly) {
        await syncNotifier.clearChangedParts([ActionType.removeHistory], false);
      }
    });
  }

  Future<void> _upsertUpdates(
    Map<String, dynamic> jsonData,
    Synching syncNotifier, {
    required bool downloadOnly,
    required int lastSync,
  }) async {
    final updates =
        (jsonData["updates"] as List?)
            ?.map((e) => Update.fromJson(e))
            .toList() ??
        [];
    final pendingDeletes = downloadOnly
        ? _pendingDeletionIds(ActionType.removeUpdate)
        : const <int>{};
    await isar.writeTxn(() async {
      for (var update in await isar.updates.filter().idIsNotNull().findAll()) {
        final temp = updates.firstWhereOrNull((e) => e.id == update.id);
        if (temp != null) {
          final chapter = await isar.chapters
              .filter()
              .mangaIdEqualTo(temp.mangaId)
              .nameEqualTo(temp.chapterName)
              .findFirst();
          if (!pendingDeletes.contains(update.id) &&
              chapter != null &&
              (update.updatedAt ?? 0) < (temp.updatedAt ?? 1)) {
            await isar.updates.put(temp..chapter.value = chapter);
            await temp.chapter.save();
          }
          updates.remove(temp);
        } else if (!downloadOnly || (update.updatedAt ?? 0) <= lastSync) {
          await isar.updates.delete(update.id!);
        }
      }
      for (var update in updates) {
        if (pendingDeletes.contains(update.id)) {
          continue;
        }
        final chapter = await isar.chapters
            .filter()
            .mangaIdEqualTo(update.mangaId)
            .nameEqualTo(update.chapterName)
            .findFirst();
        if (chapter != null) {
          await isar.updates.put(update..chapter.value = chapter);
          await update.chapter.save();
        }
      }
      if (!downloadOnly) {
        await syncNotifier.clearChangedParts([ActionType.removeUpdate], false);
      }
    });
  }

  Future<void> _upsertSettings(Map<String, dynamic> jsonData) async {
    final oldSettings = isar.settings.getSync(227)!;
    final settings = Settings.fromJson(jsonData["settings"]);
    if ((oldSettings.updatedAt ?? 0) >= (settings.updatedAt ?? 1)) {
      return;
    }
    await isar.writeTxn(() async {
      await isar.settings.put(
        _preserveDeviceLocalSettings(settings, oldSettings)
          ..cookiesList = oldSettings.cookiesList,
      );
      ref.invalidate(followSystemThemeStateProvider);
      ref.invalidate(themeModeStateProvider);
      ref.invalidate(blendLevelStateProvider);
      ref.invalidate(flexSchemeColorStateProvider);
      ref.invalidate(pureBlackDarkModeStateProvider);
      ref.invalidate(l10nLocaleStateProvider);
      ref.invalidate(extensionsRepoStateProvider(ItemType.manga));
      ref.invalidate(extensionsRepoStateProvider(ItemType.anime));
      ref.invalidate(extensionsRepoStateProvider(ItemType.novel));
    });
  }

  Map<String, String> _syncHeaders(String accessToken) => {
    'Content-Type': 'application/json',
    'Cookie': 'id=$accessToken',
    'X-Sync-Client': _clientId,
  };

  Set<int> _pendingDeletionIds(ActionType actionType) =>
      _getDeletedObjects(actionType).toSet();

  String _getMangaData({bool upload = false, bool download = false}) {
    Map<String, dynamic> data = {};
    data["categories"] = download ? [] : _getCategories();
    data["deleted_categories"] = download
        ? []
        : _getDeletedObjects(ActionType.removeCategory);
    data["manga"] = download ? [] : _getManga();
    data["deleted_manga"] = download
        ? []
        : _getDeletedObjects(ActionType.removeItem);
    data["chapters"] = download ? [] : _getChapters();
    data["deleted_chapters"] = download
        ? []
        : _getDeletedObjects(ActionType.removeChapter);
    data["tracks"] = download ? [] : _getTracks();
    data["deleted_tracks"] = download
        ? []
        : _getDeletedObjects(ActionType.removeTrack);
    if (upload) {
      data["resetAll"] = true;
    }
    return jsonEncode(data);
  }

  String _getHistoryData({bool upload = false, bool download = false}) {
    Map<String, dynamic> data = {};
    data["histories"] = download ? [] : _getHistories();
    data["deleted_histories"] = download
        ? []
        : _getDeletedObjects(ActionType.removeHistory);
    if (upload) {
      data["resetAll"] = true;
    }
    return jsonEncode(data);
  }

  String _getUpdateData({bool upload = false, bool download = false}) {
    Map<String, dynamic> data = {};
    data["updates"] = download ? [] : _getUpdates();
    data["deleted_updates"] = download
        ? []
        : _getDeletedObjects(ActionType.removeUpdate);
    if (upload) {
      data["resetAll"] = true;
    }
    return jsonEncode(data);
  }

  String _getSettingsData({bool download = false}) {
    final data = <String, dynamic>{};
    if (!download) {
      final settingsJson = isar.settings.getSync(227)!.toJson();
      settingsJson["updatedAt"] ??= DateTime.now().millisecondsSinceEpoch;
      settingsJson["cookiesList"] = [];
      for (final key in _deviceLocalSettingsKeys) {
        settingsJson.remove(key);
      }
      data["settings"] = settingsJson;
    }
    return jsonEncode(data);
  }

  List<int> _getDeletedObjects(ActionType actionType) {
    return ref
        .read(synchingProvider(syncId: syncId).notifier)
        .getChangedParts([actionType])
        .map((e) => e.isarId)
        .nonNulls
        .toList();
  }

  List<Map<String, dynamic>> _getManga() {
    return isar.mangas
        .where()
        .findAllSync()
        .map((e) => (e..customCoverImage = null).toJson())
        .toList();
  }

  List<Map<String, dynamic>> _getCategories() {
    return isar.categorys.where().findAllSync().map((e) => e.toJson()).toList();
  }

  List<Map<String, dynamic>> _getChapters() {
    return isar.chapters.where().findAllSync().map((e) => e.toJson()).toList();
  }

  List<Map<String, dynamic>> _getTracks() {
    return isar.tracks.where().findAllSync().map((e) => e.toJson()).toList();
  }

  List<Map<String, dynamic>> _getHistories() {
    return isar.historys.where().findAllSync().map((e) => e.toJson()).toList();
  }

  List<Map<String, dynamic>> _getUpdates() {
    return isar.updates.where().findAllSync().map((e) => e.toJson()).toList();
  }

  String _getAccessToken() {
    final syncPrefs = ref.read(synchingProvider(syncId: syncId));
    return syncPrefs.authToken ?? "";
  }

  String _getServer() {
    final syncPrefs = ref.read(synchingProvider(syncId: syncId));
    return syncPrefs.server ?? "";
  }
}

const _deviceLocalSettingsKeys = {
  'localFolders',
  'namedLocalFolders',
  'downloadLocalFolderName',
  'askDownloadDestination',
  'androidProxyServer',
  'jrePath',
  'extensionServerPath',
};

Settings _preserveDeviceLocalSettings(Settings incoming, Settings current) {
  return incoming
    ..id = current.id
    ..localFolders = current.localFolders
    ..namedLocalFolders = current.namedLocalFolders
    ..downloadLocalFolderName = current.downloadLocalFolderName
    ..askDownloadDestination = current.askDownloadDestination
    ..androidProxyServer = current.androidProxyServer
    ..jrePath = current.jrePath
    ..extensionServerPath = current.extensionServerPath;
}
