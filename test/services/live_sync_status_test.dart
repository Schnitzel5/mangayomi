import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/category.dart';
import 'package:mangayomi/models/changed.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/history.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/models/source.dart';
import 'package:mangayomi/models/sync_preference.dart';
import 'package:mangayomi/models/track.dart';
import 'package:mangayomi/models/update.dart';
import 'package:mangayomi/modules/more/settings/sync/providers/sync_providers.dart';
import 'package:mangayomi/services/sync_server.dart';

void main() {
  late Directory dir;
  late HttpServer server;
  String? receivedDevice;
  WebSocket? serverSocket;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
    dir = await Directory.systemTemp.createTemp('live_sync_status');
    isar = await Isar.open([
      MangaSchema,
      ChapterSchema,
      CategorySchema,
      TrackSchema,
      HistorySchema,
      UpdateSchema,
      SettingsSchema,
      SourceSchema,
      SyncPreferenceSchema,
      ChangedPartSchema,
    ], directory: dir.path);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/sync/live') {
        receivedDevice = request.uri.queryParameters['device'];
        final clientId = request.uri.queryParameters['clientId'];
        final socket = await WebSocketTransformer.upgrade(request);
        serverSocket = socket;
        socket.add(jsonEncode({'type': 'ready'}));
        socket.add(
          jsonEncode({
            'type': 'presence',
            'devices': [
              {'clientId': clientId, 'device': 'This device'},
              {'clientId': 'other-client', 'device': 'Living room TV'},
            ],
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });

    await isar.writeTxn(() async {
      await isar.settings.put(Settings(id: 227));
      await isar.syncPreferences.put(
        SyncPreference(
          syncId: 1,
          server: 'http://127.0.0.1:${server.port}',
          email: 'user@example.com',
          authToken: 'token',
          syncOn: true,
        ),
      );
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    await isar.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  test('reports connection state and connected devices, honors toggle', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = syncServerProvider(syncId: 1);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);

    Future<LiveSyncStatus> waitFor(bool Function(LiveSyncStatus) accept) async {
      late LiveSyncStatus status;
      for (var i = 0; i < 100; i++) {
        status = container.read(provider);
        if (accept(status)) return status;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return status;
    }

    final connected = await waitFor(
      (s) => s.state == LiveSyncState.connected && s.devices.isNotEmpty,
    );
    expect(connected.state, LiveSyncState.connected);
    expect(connected.devices, hasLength(1), reason: 'own client filtered out');
    expect(connected.devices.single.device, 'Living room TV');
    expect(receivedDevice, isNotNull, reason: 'device label sent to server');

    // Dropping the socket server-side puts the client into reconnecting.
    await serverSocket?.close();
    final reconnecting = await waitFor(
      (s) => s.state == LiveSyncState.connecting,
    );
    expect(reconnecting.state, LiveSyncState.connecting);

    // Toggling live sync off tears everything down.
    container.read(synchingProvider(syncId: 1).notifier).setLiveSyncOn(false);
    final off = await waitFor((s) => s.state == LiveSyncState.off);
    expect(off.state, LiveSyncState.off);
    expect(off.devices, isEmpty);
  });
}
